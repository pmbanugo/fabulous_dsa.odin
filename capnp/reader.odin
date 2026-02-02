package capnp

import "core:mem"
import "core:slice"

// ============================================================================
// Read Limits
// ============================================================================

Read_Limits :: struct {
	traversal_limit: u64,
	nesting_limit:   int,
}

default_read_limits :: proc() -> Read_Limits {
	return Read_Limits{
		traversal_limit = DEFAULT_TRAVERSAL_LIMIT,
		nesting_limit   = DEFAULT_NESTING_LIMIT,
	}
}

// ============================================================================
// Message Reader
// ============================================================================

Message_Reader :: struct {
	segments:         [][]Word,
	traversal_budget: u64,
	nesting_limit:    int,
	allocator:        mem.Allocator,
}

// Create a message reader from raw bytes (parses frame header)
message_reader_from_bytes :: proc(
	data: []byte,
	limits := Read_Limits{},
	allocator := context.allocator,
) -> (reader: Message_Reader, err: Error) {
	// Use default limits if not specified
	actual_limits := limits
	if actual_limits.traversal_limit == 0 {
		actual_limits.traversal_limit = DEFAULT_TRAVERSAL_LIMIT
	}
	if actual_limits.nesting_limit == 0 {
		actual_limits.nesting_limit = DEFAULT_NESTING_LIMIT
	}
	
	// Parse frame header
	header, header_size, header_err := deserialize_frame_header(data, allocator)
	if header_err != .None {
		return {}, header_err
	}
	defer frame_header_destroy(&header, allocator)
	
	// Calculate expected data size (use u64 to prevent overflow)
	total_words: u64 = 0
	for size in header.segment_sizes {
		total_words += u64(size)
	}
	expected_size := u64(header_size) + (total_words * WORD_SIZE_BYTES)
	
	if u64(len(data)) < expected_size {
		return {}, .Unexpected_End_Of_Input
	}
	
	// Create segment slices pointing into the data
	segments, alloc_err := make([][]Word, header.segment_count, allocator)
	if alloc_err != nil {
		return {}, .Out_Of_Memory
	}
	
	offset := u64(header_size)
	for i in 0 ..< header.segment_count {
		seg_size := header.segment_sizes[i]
		
		// Create a slice of Words from the byte data
		// Note: This assumes little-endian architecture and proper alignment
		// Caller must keep `data` alive for the reader's lifetime
		byte_slice := data[offset:offset + u64(seg_size) * WORD_SIZE_BYTES]
		word_ptr := cast([^]Word)raw_data(byte_slice)
		segments[i] = word_ptr[:seg_size]
		
		offset += u64(seg_size) * WORD_SIZE_BYTES
	}
	
	return Message_Reader{
		segments         = segments,
		traversal_budget = actual_limits.traversal_limit,
		nesting_limit    = actual_limits.nesting_limit,
		allocator        = allocator,
	}, .None
}

// Create a message reader from pre-existing segments
message_reader_from_segments :: proc(
	segments: [][]Word,
	limits := Read_Limits{},
) -> Message_Reader {
	actual_limits := limits
	if actual_limits.traversal_limit == 0 {
		actual_limits.traversal_limit = DEFAULT_TRAVERSAL_LIMIT
	}
	if actual_limits.nesting_limit == 0 {
		actual_limits.nesting_limit = DEFAULT_NESTING_LIMIT
	}
	
	return Message_Reader{
		segments         = segments,
		traversal_budget = actual_limits.traversal_limit,
		nesting_limit    = actual_limits.nesting_limit,
	}
}

// Destroy a message reader (frees the segments slice if allocated)
message_reader_destroy :: proc(mr: ^Message_Reader) {
	if mr.segments != nil && mr.allocator.procedure != nil {
		delete(mr.segments, mr.allocator)
	}
	mr^ = {}
}

// Get the root struct reader
message_reader_get_root :: proc(mr: ^Message_Reader) -> (sr: Struct_Reader, err: Error) {
	if len(mr.segments) == 0 {
		return {}, .Unexpected_End_Of_Input
	}
	
	if len(mr.segments[0]) == 0 {
		return {}, .Unexpected_End_Of_Input
	}
	
	// Root pointer is at word 0 of segment 0
	root_ptr := mr.segments[0][0]
	
	if pointer_is_null(root_ptr) {
		return {}, .Null_Pointer
	}
	
	ctx := Validation_Context{
		segments         = mr.segments,
		traversal_budget = &mr.traversal_budget,
		nesting_limit    = mr.nesting_limit,
	}
	
	validated, validate_err := validate_struct_pointer(&ctx, 0, 0, root_ptr)
	if validate_err != .None {
		return {}, validate_err
	}
	
	return Struct_Reader{
		segment_id    = validated.segment_id,
		segment       = validated.segment,
		data_offset   = validated.data_offset,
		data_size     = validated.data_size,
		pointer_count = validated.pointer_count,
		nesting_limit = mr.nesting_limit - 1,
		message       = mr,
	}, .None
}

// ============================================================================
// Struct Reader
// ============================================================================

Struct_Reader :: struct {
	segment_id:    u32,
	segment:       []Word,
	data_offset:   u32,
	data_size:     u16,   // in words
	pointer_count: u16,
	nesting_limit: int,
	message:       ^Message_Reader,
}

// Get a pointer to the data section at byte offset
@(private)
struct_reader_data_ptr :: proc(sr: ^Struct_Reader, byte_offset: u32) -> ^byte {
	if byte_offset >= u32(sr.data_size) * WORD_SIZE_BYTES {
		return nil
	}
	data_bytes := slice.to_bytes(sr.segment[sr.data_offset:])
	return &data_bytes[byte_offset]
}

// Check if a pointer index is valid and non-null
struct_reader_has_pointer :: proc(sr: ^Struct_Reader, pointer_index: u16) -> bool {
	if pointer_index >= sr.pointer_count {
		return false
	}
	pointer_word_offset := sr.data_offset + u32(sr.data_size) + u32(pointer_index)
	if pointer_word_offset >= u32(len(sr.segment)) {
		return false
	}
	return !pointer_is_null(sr.segment[pointer_word_offset])
}

// Get pointer word at index
@(private)
struct_reader_get_pointer_word :: proc(sr: ^Struct_Reader, pointer_index: u16) -> (raw: u64, offset: u32, ok: bool) {
	if pointer_index >= sr.pointer_count {
		return 0, 0, false
	}
	pointer_word_offset := sr.data_offset + u32(sr.data_size) + u32(pointer_index)
	if pointer_word_offset >= u32(len(sr.segment)) {
		return 0, 0, false
	}
	return sr.segment[pointer_word_offset], pointer_word_offset, true
}

// Read boolean at bit offset with default
struct_reader_get_bool :: proc(sr: ^Struct_Reader, offset_bits: u32, default: bool = false) -> bool {
	byte_offset := offset_bits / 8
	bit_offset := offset_bits % 8
	
	ptr := struct_reader_data_ptr(sr, byte_offset)
	if ptr == nil {
		return default
	}
	
	value := (ptr^ >> bit_offset) & 1 != 0
	return value ~ default // XOR with default
}

// Read u8 at byte offset with default
struct_reader_get_u8 :: proc(sr: ^Struct_Reader, offset: u32, default: u8 = 0) -> u8 {
	ptr := struct_reader_data_ptr(sr, offset)
	if ptr == nil {
		return default
	}
	return ptr^ ~ default
}

// Read u16 at byte offset with default
struct_reader_get_u16 :: proc(sr: ^Struct_Reader, offset: u32, default: u16 = 0) -> u16 {
	if offset + 1 >= u32(sr.data_size) * WORD_SIZE_BYTES {
		return default
	}
	ptr := struct_reader_data_ptr(sr, offset)
	if ptr == nil {
		return default
	}
	value := u16((cast(^u16le)ptr)^)
	return value ~ default
}

// Read u32 at byte offset with default
struct_reader_get_u32 :: proc(sr: ^Struct_Reader, offset: u32, default: u32 = 0) -> u32 {
	if offset + 3 >= u32(sr.data_size) * WORD_SIZE_BYTES {
		return default
	}
	ptr := struct_reader_data_ptr(sr, offset)
	if ptr == nil {
		return default
	}
	value := u32((cast(^u32le)ptr)^)
	return value ~ default
}

// Read u64 at byte offset with default
struct_reader_get_u64 :: proc(sr: ^Struct_Reader, offset: u32, default: u64 = 0) -> u64 {
	if offset + 7 >= u32(sr.data_size) * WORD_SIZE_BYTES {
		return default
	}
	ptr := struct_reader_data_ptr(sr, offset)
	if ptr == nil {
		return default
	}
	value := u64((cast(^u64le)ptr)^)
	return value ~ default
}

// Read i8 at byte offset with default
struct_reader_get_i8 :: proc(sr: ^Struct_Reader, offset: u32, default: i8 = 0) -> i8 {
	ptr := struct_reader_data_ptr(sr, offset)
	if ptr == nil {
		return default
	}
	value := (cast(^i8)ptr)^
	return value ~ default
}

// Read i16 at byte offset with default
struct_reader_get_i16 :: proc(sr: ^Struct_Reader, offset: u32, default: i16 = 0) -> i16 {
	if offset + 1 >= u32(sr.data_size) * WORD_SIZE_BYTES {
		return default
	}
	ptr := struct_reader_data_ptr(sr, offset)
	if ptr == nil {
		return default
	}
	value := i16((cast(^i16le)ptr)^)
	return value ~ default
}

// Read i32 at byte offset with default
struct_reader_get_i32 :: proc(sr: ^Struct_Reader, offset: u32, default: i32 = 0) -> i32 {
	if offset + 3 >= u32(sr.data_size) * WORD_SIZE_BYTES {
		return default
	}
	ptr := struct_reader_data_ptr(sr, offset)
	if ptr == nil {
		return default
	}
	value := i32((cast(^i32le)ptr)^)
	return value ~ default
}

// Read i64 at byte offset with default
struct_reader_get_i64 :: proc(sr: ^Struct_Reader, offset: u32, default: i64 = 0) -> i64 {
	if offset + 7 >= u32(sr.data_size) * WORD_SIZE_BYTES {
		return default
	}
	ptr := struct_reader_data_ptr(sr, offset)
	if ptr == nil {
		return default
	}
	value := i64((cast(^i64le)ptr)^)
	return value ~ default
}

// Read f32 at byte offset with default
struct_reader_get_f32 :: proc(sr: ^Struct_Reader, offset: u32, default: f32 = 0) -> f32 {
	raw := struct_reader_get_u32(sr, offset, transmute(u32)default)
	return transmute(f32)raw
}

// Read f64 at byte offset with default
struct_reader_get_f64 :: proc(sr: ^Struct_Reader, offset: u32, default: f64 = 0) -> f64 {
	raw := struct_reader_get_u64(sr, offset, transmute(u64)default)
	return transmute(f64)raw
}

// Get nested struct at pointer index
struct_reader_get_struct :: proc(sr: ^Struct_Reader, pointer_index: u16) -> (nested: Struct_Reader, err: Error) {
	// Check nesting limit
	if err := check_nesting_limit(sr.nesting_limit); err != .None {
		return {}, err
	}
	
	raw_ptr, pointer_offset, ok := struct_reader_get_pointer_word(sr, pointer_index)
	if !ok {
		// Out of bounds pointer section - return empty struct
		return Struct_Reader{
			segment_id    = sr.segment_id,
			segment       = sr.segment,
			data_offset   = 0,
			data_size     = 0,
			pointer_count = 0,
			nesting_limit = sr.nesting_limit - 1,
			message       = sr.message,
		}, .None
	}
	
	if pointer_is_null(raw_ptr) {
		return Struct_Reader{
			segment_id    = sr.segment_id,
			segment       = sr.segment,
			data_offset   = 0,
			data_size     = 0,
			pointer_count = 0,
			nesting_limit = sr.nesting_limit - 1,
			message       = sr.message,
		}, .None
	}
	
	ctx := Validation_Context{
		segments         = sr.message.segments,
		traversal_budget = &sr.message.traversal_budget,
		nesting_limit    = sr.nesting_limit,
	}
	
	validated, validation_error := validate_struct_pointer(&ctx, sr.segment_id, pointer_offset, raw_ptr)
	if validation_error != .None {
		return {}, validation_error
	}
	
	return Struct_Reader{
		segment_id    = validated.segment_id,
		segment       = validated.segment,
		data_offset   = validated.data_offset,
		data_size     = validated.data_size,
		pointer_count = validated.pointer_count,
		nesting_limit = sr.nesting_limit - 1,
		message       = sr.message,
	}, .None
}

// Get list at pointer index
struct_reader_get_list :: proc(
	sr: ^Struct_Reader,
	pointer_index: u16,
	expected_element_size: Element_Size = .Void,
) -> (list: List_Reader, err: Error) {
	// Check nesting limit
	if err := check_nesting_limit(sr.nesting_limit); err != .None {
		return {}, err
	}
	
	raw_ptr, pointer_offset, ok := struct_reader_get_pointer_word(sr, pointer_index)
	if !ok {
		// Out of bounds - return empty list
		return List_Reader{
			segment_id    = sr.segment_id,
			segment       = sr.segment,
			data_offset   = 0,
			element_count = 0,
			element_size  = expected_element_size,
			nesting_limit = sr.nesting_limit - 1,
			message       = sr.message,
		}, .None
	}
	
	if pointer_is_null(raw_ptr) {
		return List_Reader{
			segment_id    = sr.segment_id,
			segment       = sr.segment,
			data_offset   = 0,
			element_count = 0,
			element_size  = expected_element_size,
			nesting_limit = sr.nesting_limit - 1,
			message       = sr.message,
		}, .None
	}
	
	ctx := Validation_Context{
		segments         = sr.message.segments,
		traversal_budget = &sr.message.traversal_budget,
		nesting_limit    = sr.nesting_limit,
	}
	
	validated, validation_error := validate_list_pointer(&ctx, sr.segment_id, pointer_offset, raw_ptr, expected_element_size)
	if validation_error != .None {
		return {}, validation_error
	}
	
	return List_Reader{
		segment_id            = validated.segment_id,
		segment               = validated.segment,
		data_offset           = validated.data_offset,
		element_count         = validated.element_count,
		element_size          = validated.element_size,
		struct_data_size      = validated.struct_data_size,
		struct_pointer_count  = validated.struct_pointer_count,
		nesting_limit         = sr.nesting_limit - 1,
		message               = sr.message,
	}, .None
}

// Get text at pointer index (NUL-terminated string)
struct_reader_get_text :: proc(sr: ^Struct_Reader, pointer_index: u16) -> (text: string, err: Error) {
	list, list_error := struct_reader_get_list(sr, pointer_index, .Byte)
	if list_error != .None {
		return "", list_error
	}
	
	if list.element_count == 0 {
		return "", .None
	}
	
	// Get the raw bytes
	data_bytes := slice.to_bytes(list.segment[list.data_offset:])
	text_bytes := data_bytes[:list.element_count]
	
	return validate_text(text_bytes)
}

// Get data at pointer index (raw bytes)
struct_reader_get_data :: proc(sr: ^Struct_Reader, pointer_index: u16) -> (data: []byte, err: Error) {
	list, list_error := struct_reader_get_list(sr, pointer_index, .Byte)
	if list_error != .None {
		return nil, list_error
	}
	
	if list.element_count == 0 {
		return nil, .None
	}
	
	data_bytes := slice.to_bytes(list.segment[list.data_offset:])
	return data_bytes[:list.element_count], .None
}

// ============================================================================
// List Reader
// ============================================================================

List_Reader :: struct {
	segment_id:           u32,
	segment:              []Word,
	data_offset:          u32,
	element_count:        u32,
	element_size:         Element_Size,
	// For composite lists:
	struct_data_size:     u16,
	struct_pointer_count: u16,
	nesting_limit:        int,
	message:              ^Message_Reader,
}

// Get element count
list_reader_len :: proc(lr: ^List_Reader) -> u32 {
	return lr.element_count
}

// Get a pointer to list data at byte offset
@(private)
list_reader_data_ptr :: proc(lr: ^List_Reader, byte_offset: u32) -> ^byte {
	data_bytes := slice.to_bytes(lr.segment[lr.data_offset:])
	if byte_offset >= u32(len(data_bytes)) {
		return nil
	}
	return &data_bytes[byte_offset]
}

// Read boolean at index (bit-packed)
list_reader_get_bool :: proc(lr: ^List_Reader, index: u32) -> bool {
	if index >= lr.element_count || lr.element_size != .Bit {
		return false
	}
	
	byte_offset := index / 8
	bit_offset := index % 8
	
	ptr := list_reader_data_ptr(lr, byte_offset)
	if ptr == nil {
		return false
	}
	
	return (ptr^ >> bit_offset) & 1 != 0
}

// Read u8 at index
list_reader_get_u8 :: proc(lr: ^List_Reader, index: u32) -> u8 {
	if index >= lr.element_count || lr.element_size != .Byte {
		return 0
	}
	
	ptr := list_reader_data_ptr(lr, index)
	if ptr == nil {
		return 0
	}
	return ptr^
}

// Read u16 at index
list_reader_get_u16 :: proc(lr: ^List_Reader, index: u32) -> u16 {
	if index >= lr.element_count || lr.element_size != .Two_Bytes {
		return 0
	}
	
	ptr := list_reader_data_ptr(lr, index * 2)
	if ptr == nil {
		return 0
	}
	return u16((cast(^u16le)ptr)^)
}

// Read u32 at index
list_reader_get_u32 :: proc(lr: ^List_Reader, index: u32) -> u32 {
	if index >= lr.element_count || lr.element_size != .Four_Bytes {
		return 0
	}
	
	ptr := list_reader_data_ptr(lr, index * 4)
	if ptr == nil {
		return 0
	}
	return u32((cast(^u32le)ptr)^)
}

// Read u64 at index
list_reader_get_u64 :: proc(lr: ^List_Reader, index: u32) -> u64 {
	if index >= lr.element_count || lr.element_size != .Eight_Bytes {
		return 0
	}
	
	ptr := list_reader_data_ptr(lr, index * 8)
	if ptr == nil {
		return 0
	}
	return u64((cast(^u64le)ptr)^)
}

// Read i8 at index
list_reader_get_i8 :: proc(lr: ^List_Reader, index: u32) -> i8 {
	if index >= lr.element_count || lr.element_size != .Byte {
		return 0
	}
	
	ptr := list_reader_data_ptr(lr, index)
	if ptr == nil {
		return 0
	}
	return (cast(^i8)ptr)^
}

// Read i16 at index
list_reader_get_i16 :: proc(lr: ^List_Reader, index: u32) -> i16 {
	if index >= lr.element_count || lr.element_size != .Two_Bytes {
		return 0
	}
	
	ptr := list_reader_data_ptr(lr, index * 2)
	if ptr == nil {
		return 0
	}
	return i16((cast(^i16le)ptr)^)
}

// Read i32 at index
list_reader_get_i32 :: proc(lr: ^List_Reader, index: u32) -> i32 {
	if index >= lr.element_count || lr.element_size != .Four_Bytes {
		return 0
	}
	
	ptr := list_reader_data_ptr(lr, index * 4)
	if ptr == nil {
		return 0
	}
	return i32((cast(^i32le)ptr)^)
}

// Read i64 at index
list_reader_get_i64 :: proc(lr: ^List_Reader, index: u32) -> i64 {
	if index >= lr.element_count || lr.element_size != .Eight_Bytes {
		return 0
	}
	
	ptr := list_reader_data_ptr(lr, index * 8)
	if ptr == nil {
		return 0
	}
	return i64((cast(^i64le)ptr)^)
}

// Read f32 at index
list_reader_get_f32 :: proc(lr: ^List_Reader, index: u32) -> f32 {
	if index >= lr.element_count || lr.element_size != .Four_Bytes {
		return 0
	}
	
	raw := list_reader_get_u32(lr, index)
	return transmute(f32)raw
}

// Read f64 at index
list_reader_get_f64 :: proc(lr: ^List_Reader, index: u32) -> f64 {
	if index >= lr.element_count || lr.element_size != .Eight_Bytes {
		return 0
	}
	
	raw := list_reader_get_u64(lr, index)
	return transmute(f64)raw
}

// Get struct at index (for composite lists)
list_reader_get_struct :: proc(lr: ^List_Reader, index: u32) -> (sr: Struct_Reader, err: Error) {
	if index >= lr.element_count {
		return {}, .List_Index_Out_Of_Bounds
	}
	
	if lr.element_size != .Composite {
		return {}, .Invalid_Element_Size
	}
	
	words_per_element := u32(lr.struct_data_size) + u32(lr.struct_pointer_count)
	
	// Use u64 for overflow safety
	element_offset_u64 := u64(lr.data_offset) + (u64(index) * u64(words_per_element))
	if element_offset_u64 >= u64(len(lr.segment)) {
		return {}, .Pointer_Out_Of_Bounds
	}
	element_offset := u32(element_offset_u64)
	
	return Struct_Reader{
		segment_id    = lr.segment_id,
		segment       = lr.segment,
		data_offset   = element_offset,
		data_size     = lr.struct_data_size,
		pointer_count = lr.struct_pointer_count,
		nesting_limit = lr.nesting_limit - 1,
		message       = lr.message,
	}, .None
}

// Get text at index (for List(Text))
list_reader_get_text :: proc(lr: ^List_Reader, index: u32) -> (text: string, err: Error) {
	if index >= lr.element_count {
		return "", .List_Index_Out_Of_Bounds
	}
	
	if lr.element_size != .Pointer {
		return "", .Invalid_Element_Size
	}
	
	// Check nesting limit
	if err := check_nesting_limit(lr.nesting_limit); err != .None {
		return "", err
	}
	
	// Get the pointer (use u64 for overflow safety)
	pointer_offset_u64 := u64(lr.data_offset) + u64(index)
	if pointer_offset_u64 >= u64(len(lr.segment)) {
		return "", .Pointer_Out_Of_Bounds
	}
	pointer_offset := u32(pointer_offset_u64)
	
	raw_ptr := lr.segment[pointer_offset]
	if pointer_is_null(raw_ptr) {
		return "", .None
	}
	
	ctx := Validation_Context{
		segments         = lr.message.segments,
		traversal_budget = &lr.message.traversal_budget,
		nesting_limit    = lr.nesting_limit,
	}
	
	validated, validate_err := validate_list_pointer(&ctx, lr.segment_id, pointer_offset, raw_ptr, .Byte)
	if validate_err != .None {
		return "", validate_err
	}
	
	if validated.element_count == 0 {
		return "", .None
	}
	
	data_bytes := slice.to_bytes(validated.segment[validated.data_offset:])
	text_bytes := data_bytes[:validated.element_count]
	
	return validate_text(text_bytes)
}

// Get data at index (for List(Data))
list_reader_get_data :: proc(lr: ^List_Reader, index: u32) -> (data: []byte, err: Error) {
	if index >= lr.element_count {
		return nil, .List_Index_Out_Of_Bounds
	}
	
	if lr.element_size != .Pointer {
		return nil, .Invalid_Element_Size
	}
	
	// Check nesting limit
	if err := check_nesting_limit(lr.nesting_limit); err != .None {
		return nil, err
	}
	
	// Get the pointer (use u64 for overflow safety)
	pointer_offset_u64 := u64(lr.data_offset) + u64(index)
	if pointer_offset_u64 >= u64(len(lr.segment)) {
		return nil, .Pointer_Out_Of_Bounds
	}
	pointer_offset := u32(pointer_offset_u64)
	
	raw_ptr := lr.segment[pointer_offset]
	if pointer_is_null(raw_ptr) {
		return nil, .None
	}
	
	ctx := Validation_Context{
		segments         = lr.message.segments,
		traversal_budget = &lr.message.traversal_budget,
		nesting_limit    = lr.nesting_limit,
	}
	
	validated, validate_err := validate_list_pointer(&ctx, lr.segment_id, pointer_offset, raw_ptr, .Byte)
	if validate_err != .None {
		return nil, validate_err
	}
	
	if validated.element_count == 0 {
		return nil, .None
	}
	
	data_bytes := slice.to_bytes(validated.segment[validated.data_offset:])
	return data_bytes[:validated.element_count], .None
}
