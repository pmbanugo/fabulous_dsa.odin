package capnp

import "core:slice"

// ============================================================================
// Message Builder
// ============================================================================

// Message_Builder is used to construct Cap'n Proto messages
Message_Builder :: struct {
	segments: Segment_Manager,
}

// Initialize a Message_Builder (pointer-based init, efficient for stack allocation)
// Returns pointer for chaining. Uses context.allocator by default.
message_builder_init :: proc(
	mb: ^Message_Builder,
	allocator := context.allocator,
) -> (res: ^Message_Builder, err: Error) {
	segment_manager_init(&mb.segments, DEFAULT_SEGMENT_SIZE, allocator)
	return mb, .None
}

// Create a Message_Builder (value-based make, convenient for simple cases)
// Uses context.allocator by default.
message_builder_make :: proc(
	allocator := context.allocator,
) -> (res: Message_Builder, err: Error) {
	mb: Message_Builder
	segment_manager_init(&mb.segments, DEFAULT_SEGMENT_SIZE, allocator)
	return mb, .None
}

// Free all memory used by the message builder
message_builder_destroy :: proc(mb: ^Message_Builder) {
	segment_manager_destroy(&mb.segments)
}

// Reset the message builder for reuse (keeps first segment's capacity)
message_builder_clear :: proc(mb: ^Message_Builder) {
	segment_manager_clear(&mb.segments)
}

// Initialize the root struct of the message
// The root pointer is stored at word 0 of segment 0
message_builder_init_root :: proc(
	mb: ^Message_Builder,
	data_words: u16,
	pointer_count: u16,
) -> (sb: Struct_Builder, err: Error) {
	struct_words := u32(data_words) + u32(pointer_count)
	
	// Special case: zero-sized struct uses offset = -1 per spec
	if struct_words == 0 {
		// Allocate only the root pointer word
		seg_id, offset, alloc_err := segment_manager_allocate(&mb.segments, 1)
		if alloc_err != .None {
			return {}, alloc_err
		}
		
		seg := segment_manager_get_segment(&mb.segments, seg_id)
		root_ptr := struct_pointer_encode(-1, 0, 0)
		segment_set_word(seg, offset, root_ptr)
		
		return Struct_Builder{
			segment       = seg,
			data_offset   = offset, // Won't be dereferenced (bounds checks will fail)
			data_words    = 0,
			pointer_count = 0,
			manager       = &mb.segments,
		}, .None
	}
	
	// Allocate space for the root pointer + struct content
	total_words := 1 + struct_words // 1 word for root pointer
	
	seg_id, offset, alloc_err := segment_manager_allocate(&mb.segments, total_words)
	if alloc_err != .None {
		return {}, alloc_err
	}
	
	seg := segment_manager_get_segment(&mb.segments, seg_id)
	
	// The root pointer is at offset, struct content starts at offset+1
	// Pointer offset = target - (pointer_location + 1) = (offset+1) - (offset+1) = 0
	root_ptr := struct_pointer_encode(0, data_words, pointer_count)
	segment_set_word(seg, offset, root_ptr)
	
	// Return builder for the struct content
	return Struct_Builder{
		segment       = seg,
		data_offset   = offset + 1,
		data_words    = data_words,
		pointer_count = pointer_count,
		manager       = &mb.segments,
	}, .None
}

// Get segment data for serialization (returns slice of used words per segment)
message_builder_get_segments :: proc(mb: ^Message_Builder) -> [][]Word {
	count := segment_manager_segment_count(&mb.segments)
	if count == 0 {
		return nil
	}
	
	// This allocates - caller should be aware
	result := make([][]Word, count, mb.segments.allocator)
	for i in 0 ..< count {
		seg := segment_manager_get_segment(&mb.segments, i)
		result[i] = segment_get_data(seg)
	}
	return result
}

// Return total words used across all segments
message_builder_total_words :: proc(mb: ^Message_Builder) -> u32 {
	total: u32 = 0
	count := segment_manager_segment_count(&mb.segments)
	for i in 0 ..< count {
		seg := segment_manager_get_segment(&mb.segments, i)
		total += seg.used
	}
	return total
}

// ============================================================================
// Struct Builder
// ============================================================================

// Struct_Builder is used to construct a struct within a message
Struct_Builder :: struct {
	segment:       ^Segment,
	data_offset:   u32, // word offset where data section starts
	data_words:    u16, // size of data section in words
	pointer_count: u16, // number of pointers in pointer section
	manager:       ^Segment_Manager,
}

// Get byte offset within data section
@(private)
struct_data_byte_ptr :: proc(sb: ^Struct_Builder, byte_offset: u32) -> ^byte {
	data_bytes := slice.to_bytes(sb.segment.data[sb.data_offset:])
	return &data_bytes[byte_offset]
}

// Set a boolean at the given bit offset in the data section
struct_builder_set_bool :: proc(sb: ^Struct_Builder, offset_bits: u32, value: bool) {
	byte_offset := offset_bits / 8
	bit_offset := offset_bits % 8
	
	// Bounds check
	if byte_offset >= u32(sb.data_words) * WORD_SIZE_BYTES {
		return
	}
	
	ptr := struct_data_byte_ptr(sb, byte_offset)
	if value {
		ptr^ |= (1 << bit_offset)
	} else {
		ptr^ &= ~(1 << bit_offset)
	}
}

// Set an unsigned 8-bit integer at the given byte offset
struct_builder_set_u8 :: proc(sb: ^Struct_Builder, offset: u32, value: u8) {
	if offset >= u32(sb.data_words) * WORD_SIZE_BYTES {
		return
	}
	ptr := struct_data_byte_ptr(sb, offset)
	ptr^ = value
}

// Set an unsigned 16-bit integer at the given byte offset
struct_builder_set_u16 :: proc(sb: ^Struct_Builder, offset: u32, value: u16) {
	if offset + 1 >= u32(sb.data_words) * WORD_SIZE_BYTES {
		return
	}
	ptr := struct_data_byte_ptr(sb, offset)
	(cast(^u16le)ptr)^ = u16le(value)
}

// Set an unsigned 32-bit integer at the given byte offset
struct_builder_set_u32 :: proc(sb: ^Struct_Builder, offset: u32, value: u32) {
	if offset + 3 >= u32(sb.data_words) * WORD_SIZE_BYTES {
		return
	}
	ptr := struct_data_byte_ptr(sb, offset)
	(cast(^u32le)ptr)^ = u32le(value)
}

// Set an unsigned 64-bit integer at the given byte offset
struct_builder_set_u64 :: proc(sb: ^Struct_Builder, offset: u32, value: u64) {
	if offset + 7 >= u32(sb.data_words) * WORD_SIZE_BYTES {
		return
	}
	ptr := struct_data_byte_ptr(sb, offset)
	(cast(^u64le)ptr)^ = u64le(value)
}

// Set a signed 8-bit integer at the given byte offset
struct_builder_set_i8 :: proc(sb: ^Struct_Builder, offset: u32, value: i8) {
	if offset >= u32(sb.data_words) * WORD_SIZE_BYTES {
		return
	}
	ptr := struct_data_byte_ptr(sb, offset)
	(cast(^i8)ptr)^ = value
}

// Set a signed 16-bit integer at the given byte offset
struct_builder_set_i16 :: proc(sb: ^Struct_Builder, offset: u32, value: i16) {
	if offset + 1 >= u32(sb.data_words) * WORD_SIZE_BYTES {
		return
	}
	ptr := struct_data_byte_ptr(sb, offset)
	(cast(^i16le)ptr)^ = i16le(value)
}

// Set a signed 32-bit integer at the given byte offset
struct_builder_set_i32 :: proc(sb: ^Struct_Builder, offset: u32, value: i32) {
	if offset + 3 >= u32(sb.data_words) * WORD_SIZE_BYTES {
		return
	}
	ptr := struct_data_byte_ptr(sb, offset)
	(cast(^i32le)ptr)^ = i32le(value)
}

// Set a signed 64-bit integer at the given byte offset
struct_builder_set_i64 :: proc(sb: ^Struct_Builder, offset: u32, value: i64) {
	if offset + 7 >= u32(sb.data_words) * WORD_SIZE_BYTES {
		return
	}
	ptr := struct_data_byte_ptr(sb, offset)
	(cast(^i64le)ptr)^ = i64le(value)
}

// Set a 32-bit float at the given byte offset
struct_builder_set_f32 :: proc(sb: ^Struct_Builder, offset: u32, value: f32) {
	struct_builder_set_u32(sb, offset, transmute(u32)value)
}

// Set a 64-bit float at the given byte offset
struct_builder_set_f64 :: proc(sb: ^Struct_Builder, offset: u32, value: f64) {
	struct_builder_set_u64(sb, offset, transmute(u64)value)
}

// Get pointer to the pointer section at given index
@(private)
struct_pointer_slot :: proc(sb: ^Struct_Builder, ptr_idx: u16) -> ^Word {
	pointer_offset := sb.data_offset + u32(sb.data_words) + u32(ptr_idx)
	return &sb.segment.data[pointer_offset]
}

// Initialize a nested struct at the given pointer index
struct_builder_init_struct :: proc(
	sb: ^Struct_Builder,
	ptr_idx: u16,
	data_words: u16,
	pointer_count: u16,
) -> (nested: Struct_Builder, err: Error) {
	if ptr_idx >= sb.pointer_count {
		return {}, .Pointer_Out_Of_Bounds
	}
	
	struct_words := u32(data_words) + u32(pointer_count)
	
	// Special case: zero-sized struct uses offset = -1, no allocation needed
	if struct_words == 0 {
		ptr := struct_pointer_encode(-1, 0, 0)
		struct_pointer_slot(sb, ptr_idx)^ = ptr
		
		return Struct_Builder{
			segment       = sb.segment,
			data_offset   = 0, // Won't be dereferenced
			data_words    = 0,
			pointer_count = 0,
			manager       = sb.manager,
		}, .None
	}
	
	// Try to allocate in current segment first
	alloc_offset, ok := segment_allocate(sb.segment, struct_words)
	
	if ok {
		// Same segment - calculate relative offset
		pointer_word_idx := sb.data_offset + u32(sb.data_words) + u32(ptr_idx)
		// offset = target - (pointer_location + 1)
		rel_offset := i64(alloc_offset) - i64(pointer_word_idx + 1)
		
		// Validate offset fits in 30-bit signed field
		if rel_offset < -(1 << 29) || rel_offset > (1 << 29) - 1 {
			return {}, .Pointer_Out_Of_Bounds
		}
		
		ptr := struct_pointer_encode(i32(rel_offset), data_words, pointer_count)
		struct_pointer_slot(sb, ptr_idx)^ = ptr
		
		return Struct_Builder{
			segment       = sb.segment,
			data_offset   = alloc_offset,
			data_words    = data_words,
			pointer_count = pointer_count,
			manager       = sb.manager,
		}, .None
	}
	
	// Need to allocate in a new segment - use far pointer
	// Allocate landing pad (1 word) + struct content
	landing_and_struct := 1 + struct_words
	seg_id, far_offset, alloc_err := segment_manager_allocate(sb.manager, landing_and_struct)
	if alloc_err != .None {
		return {}, alloc_err
	}
	
	target_seg := segment_manager_get_segment(sb.manager, seg_id)
	
	// Landing pad at far_offset contains struct pointer with offset 0
	landing_pad := struct_pointer_encode(0, data_words, pointer_count)
	segment_set_word(target_seg, far_offset, landing_pad)
	
	// Far pointer at source
	far_ptr := far_pointer_encode(false, far_offset, seg_id)
	struct_pointer_slot(sb, ptr_idx)^ = far_ptr
	
	return Struct_Builder{
		segment       = target_seg,
		data_offset   = far_offset + 1, // struct content after landing pad
		data_words    = data_words,
		pointer_count = pointer_count,
		manager       = sb.manager,
	}, .None
}

// Initialize a primitive list at the given pointer index
struct_builder_init_list :: proc(
	sb: ^Struct_Builder,
	ptr_idx: u16,
	element_size: Element_Size,
	count: u32,
) -> (lb: List_Builder, err: Error) {
	if ptr_idx >= sb.pointer_count {
		return {}, .Pointer_Out_Of_Bounds
	}
	
	if element_size == .Composite {
		return {}, .Invalid_Element_Size
	}
	
	// Calculate words needed
	total_bits := u64(element_size_bits(element_size)) * u64(count)
	total_words := u32((total_bits + 63) / 64)
	
	// Special case: zero-length or zero-sized list - no allocation needed
	if total_words == 0 {
		ptr := list_pointer_encode(0, element_size, count)
		struct_pointer_slot(sb, ptr_idx)^ = ptr
		
		return List_Builder{
			segment      = sb.segment,
			data_offset  = 0, // Won't be dereferenced
			count        = count,
			element_size = element_size,
			data_words   = 0,
			ptr_count    = 0,
			manager      = sb.manager,
		}, .None
	}
	
	// Try same segment first
	alloc_offset, ok := segment_allocate(sb.segment, total_words)
	
	if ok {
		pointer_word_idx := sb.data_offset + u32(sb.data_words) + u32(ptr_idx)
		rel_offset := i64(alloc_offset) - i64(pointer_word_idx + 1)
		
		// Validate offset fits in 30-bit signed field
		if rel_offset < -(1 << 29) || rel_offset > (1 << 29) - 1 {
			return {}, .Pointer_Out_Of_Bounds
		}
		
		ptr := list_pointer_encode(i32(rel_offset), element_size, count)
		struct_pointer_slot(sb, ptr_idx)^ = ptr
		
		return List_Builder{
			segment      = sb.segment,
			data_offset  = alloc_offset,
			count        = count,
			element_size = element_size,
			data_words   = 0,
			ptr_count    = 0,
			manager      = sb.manager,
		}, .None
	}
	
	// Cross-segment with far pointer
	landing_and_list := 1 + total_words
	seg_id, offset, alloc_err := segment_manager_allocate(sb.manager, landing_and_list)
	if alloc_err != .None {
		return {}, alloc_err
	}
	
	target_seg := segment_manager_get_segment(sb.manager, seg_id)
	
	// Landing pad with list pointer
	landing_pad := list_pointer_encode(0, element_size, count)
	segment_set_word(target_seg, offset, landing_pad)
	
	// Far pointer at source
	far_ptr := far_pointer_encode(false, offset, seg_id)
	struct_pointer_slot(sb, ptr_idx)^ = far_ptr
	
	return List_Builder{
		segment      = target_seg,
		data_offset  = offset + 1,
		count        = count,
		element_size = element_size,
		data_words   = 0,
		ptr_count    = 0,
		manager      = sb.manager,
	}, .None
}

// Initialize a composite (struct) list at the given pointer index
struct_builder_init_struct_list :: proc(
	sb: ^Struct_Builder,
	ptr_idx: u16,
	count: u32,
	data_words: u16,
	pointer_count: u16,
) -> (lb: List_Builder, err: Error) {
	if ptr_idx >= sb.pointer_count {
		return {}, .Pointer_Out_Of_Bounds
	}
	
	words_per_element := u32(data_words) + u32(pointer_count)
	content_words := words_per_element * count
	total_words := 1 + content_words // 1 for tag word
	
	// Note: Even for count=0, we still need the tag word for composite lists
	
	alloc_offset, ok := segment_allocate(sb.segment, total_words)
	
	if ok {
		pointer_word_idx := sb.data_offset + u32(sb.data_words) + u32(ptr_idx)
		rel_offset := i64(alloc_offset) - i64(pointer_word_idx + 1)
		
		// Validate offset fits in 30-bit signed field
		if rel_offset < -(1 << 29) || rel_offset > (1 << 29) - 1 {
			return {}, .Pointer_Out_Of_Bounds
		}
		
		// List pointer: element_size = Composite, element_count = total words (not including tag)
		ptr := list_pointer_encode(i32(rel_offset), .Composite, content_words)
		struct_pointer_slot(sb, ptr_idx)^ = ptr
		
		// Tag word: struct pointer format with offset field = element count (unsigned)
		// We use struct_pointer_encode but the "offset" field here holds element count
		tag := struct_pointer_encode(i32(count), data_words, pointer_count)
		segment_set_word(sb.segment, alloc_offset, tag)
		
		return List_Builder{
			segment      = sb.segment,
			data_offset  = alloc_offset + 1, // content starts after tag
			count        = count,
			element_size = .Composite,
			data_words   = data_words,
			ptr_count    = pointer_count,
			manager      = sb.manager,
		}, .None
	}
	
	// Cross-segment with far pointer
	landing_and_content := 1 + total_words
	seg_id, offset, alloc_err := segment_manager_allocate(sb.manager, landing_and_content)
	if alloc_err != .None {
		return {}, alloc_err
	}
	
	target_seg := segment_manager_get_segment(sb.manager, seg_id)
	
	// Landing pad: list pointer with offset 0
	landing_pad := list_pointer_encode(0, .Composite, content_words)
	segment_set_word(target_seg, offset, landing_pad)
	
	// Tag word at offset+1: struct pointer format with offset field = element count
	tag := struct_pointer_encode(i32(count), data_words, pointer_count)
	segment_set_word(target_seg, offset + 1, tag)
	
	// Far pointer at source
	far_ptr := far_pointer_encode(false, offset, seg_id)
	struct_pointer_slot(sb, ptr_idx)^ = far_ptr
	
	return List_Builder{
		segment      = target_seg,
		data_offset  = offset + 2, // content starts after landing pad + tag
		count        = count,
		element_size = .Composite,
		data_words   = data_words,
		ptr_count    = pointer_count,
		manager      = sb.manager,
	}, .None
}

// Set text at the given pointer index (NUL-terminated)
struct_builder_set_text :: proc(
	sb: ^Struct_Builder,
	ptr_idx: u16,
	text: string,
) -> Error {
	if ptr_idx >= sb.pointer_count {
		return .Pointer_Out_Of_Bounds
	}
	
	// Text is stored as List(UInt8) with NUL terminator
	// Length includes the NUL byte
	text_bytes := transmute([]byte)text
	length := u32(len(text_bytes)) + 1 // +1 for NUL
	words_needed := (length + 7) / 8
	
	alloc_offset, ok := segment_allocate(sb.segment, words_needed)
	
	if ok {
		pointer_word_idx := sb.data_offset + u32(sb.data_words) + u32(ptr_idx)
		rel_offset := i64(alloc_offset) - i64(pointer_word_idx + 1)
		
		// Validate offset fits in 30-bit signed field
		if rel_offset < -(1 << 29) || rel_offset > (1 << 29) - 1 {
			return .Pointer_Out_Of_Bounds
		}
		
		ptr := list_pointer_encode(i32(rel_offset), .Byte, length)
		struct_pointer_slot(sb, ptr_idx)^ = ptr
		
		// Copy text data
		dest := slice.to_bytes(sb.segment.data[alloc_offset:])
		copy(dest, text_bytes)
		dest[len(text_bytes)] = 0 // NUL terminator
		
		return .None
	}
	
	// Cross-segment
	landing_and_text := 1 + words_needed
	seg_id, offset, alloc_err := segment_manager_allocate(sb.manager, landing_and_text)
	if alloc_err != .None {
		return alloc_err
	}
	
	target_seg := segment_manager_get_segment(sb.manager, seg_id)
	
	// Landing pad
	landing_pad := list_pointer_encode(0, .Byte, length)
	segment_set_word(target_seg, offset, landing_pad)
	
	// Copy text
	dest := slice.to_bytes(target_seg.data[offset + 1:])
	copy(dest, text_bytes)
	dest[len(text_bytes)] = 0
	
	// Far pointer
	far_ptr := far_pointer_encode(false, offset, seg_id)
	struct_pointer_slot(sb, ptr_idx)^ = far_ptr
	
	return .None
}

// Set data blob at the given pointer index
struct_builder_set_data :: proc(
	sb: ^Struct_Builder,
	ptr_idx: u16,
	data: []byte,
) -> Error {
	if ptr_idx >= sb.pointer_count {
		return .Pointer_Out_Of_Bounds
	}
	
	// Data is stored as List(UInt8) without NUL terminator
	length := u32(len(data))
	
	// Special case: zero-length data - no allocation needed
	if length == 0 {
		ptr := list_pointer_encode(0, .Byte, 0)
		struct_pointer_slot(sb, ptr_idx)^ = ptr
		return .None
	}
	
	words_needed := (length + 7) / 8
	
	alloc_offset, ok := segment_allocate(sb.segment, words_needed)
	
	if ok {
		pointer_word_idx := sb.data_offset + u32(sb.data_words) + u32(ptr_idx)
		rel_offset := i64(alloc_offset) - i64(pointer_word_idx + 1)
		
		// Validate offset fits in 30-bit signed field
		if rel_offset < -(1 << 29) || rel_offset > (1 << 29) - 1 {
			return .Pointer_Out_Of_Bounds
		}
		
		ptr := list_pointer_encode(i32(rel_offset), .Byte, length)
		struct_pointer_slot(sb, ptr_idx)^ = ptr
		
		// Copy data
		dest := slice.to_bytes(sb.segment.data[alloc_offset:])
		copy(dest, data)
		
		return .None
	}
	
	// Cross-segment
	landing_and_data := 1 + words_needed
	seg_id, offset, alloc_err := segment_manager_allocate(sb.manager, landing_and_data)
	if alloc_err != .None {
		return alloc_err
	}
	
	target_seg := segment_manager_get_segment(sb.manager, seg_id)
	
	// Landing pad
	landing_pad := list_pointer_encode(0, .Byte, length)
	segment_set_word(target_seg, offset, landing_pad)
	
	// Copy data
	dest := slice.to_bytes(target_seg.data[offset + 1:])
	copy(dest, data)
	
	// Far pointer
	far_ptr := far_pointer_encode(false, offset, seg_id)
	struct_pointer_slot(sb, ptr_idx)^ = far_ptr
	
	return .None
}

// ============================================================================
// List Builder
// ============================================================================

// List_Builder is used to construct a list within a message
List_Builder :: struct {
	segment:      ^Segment,
	data_offset:  u32, // word offset where list content starts
	count:        u32, // number of elements
	element_size: Element_Size, // element size code
	// For composite lists:
	data_words:   u16, // data words per struct element
	ptr_count:    u16, // pointer count per struct element
	manager:      ^Segment_Manager,
}

// Get byte pointer to list content
@(private)
list_data_byte_ptr :: proc(lb: ^List_Builder, byte_offset: u32) -> ^byte {
	data_bytes := slice.to_bytes(lb.segment.data[lb.data_offset:])
	return &data_bytes[byte_offset]
}

// Set a boolean at the given index (bit-packed)
list_builder_set_bool :: proc(lb: ^List_Builder, index: u32, value: bool) {
	if index >= lb.count || lb.element_size != .Bit {
		return
	}
	
	byte_offset := index / 8
	bit_offset := index % 8
	
	ptr := list_data_byte_ptr(lb, byte_offset)
	if value {
		ptr^ |= (1 << bit_offset)
	} else {
		ptr^ &= ~(1 << bit_offset)
	}
}

// Set an unsigned 8-bit integer at the given index
list_builder_set_u8 :: proc(lb: ^List_Builder, index: u32, value: u8) {
	if index >= lb.count || lb.element_size != .Byte {
		return
	}
	ptr := list_data_byte_ptr(lb, index)
	ptr^ = value
}

// Set an unsigned 16-bit integer at the given index
list_builder_set_u16 :: proc(lb: ^List_Builder, index: u32, value: u16) {
	if index >= lb.count || lb.element_size != .Two_Bytes {
		return
	}
	ptr := list_data_byte_ptr(lb, index * 2)
	(cast(^u16le)ptr)^ = u16le(value)
}

// Set an unsigned 32-bit integer at the given index
list_builder_set_u32 :: proc(lb: ^List_Builder, index: u32, value: u32) {
	if index >= lb.count || lb.element_size != .Four_Bytes {
		return
	}
	ptr := list_data_byte_ptr(lb, index * 4)
	(cast(^u32le)ptr)^ = u32le(value)
}

// Set an unsigned 64-bit integer at the given index
list_builder_set_u64 :: proc(lb: ^List_Builder, index: u32, value: u64) {
	if index >= lb.count || lb.element_size != .Eight_Bytes {
		return
	}
	ptr := list_data_byte_ptr(lb, index * 8)
	(cast(^u64le)ptr)^ = u64le(value)
}

// Set a signed 8-bit integer at the given index
list_builder_set_i8 :: proc(lb: ^List_Builder, index: u32, value: i8) {
	if index >= lb.count || lb.element_size != .Byte {
		return
	}
	ptr := list_data_byte_ptr(lb, index)
	(cast(^i8)ptr)^ = value
}

// Set a signed 16-bit integer at the given index
list_builder_set_i16 :: proc(lb: ^List_Builder, index: u32, value: i16) {
	if index >= lb.count || lb.element_size != .Two_Bytes {
		return
	}
	ptr := list_data_byte_ptr(lb, index * 2)
	(cast(^i16le)ptr)^ = i16le(value)
}

// Set a signed 32-bit integer at the given index
list_builder_set_i32 :: proc(lb: ^List_Builder, index: u32, value: i32) {
	if index >= lb.count || lb.element_size != .Four_Bytes {
		return
	}
	ptr := list_data_byte_ptr(lb, index * 4)
	(cast(^i32le)ptr)^ = i32le(value)
}

// Set a signed 64-bit integer at the given index
list_builder_set_i64 :: proc(lb: ^List_Builder, index: u32, value: i64) {
	if index >= lb.count || lb.element_size != .Eight_Bytes {
		return
	}
	ptr := list_data_byte_ptr(lb, index * 8)
	(cast(^i64le)ptr)^ = i64le(value)
}

// Set a 32-bit float at the given index
list_builder_set_f32 :: proc(lb: ^List_Builder, index: u32, value: f32) {
	if index >= lb.count || lb.element_size != .Four_Bytes {
		return
	}
	ptr := list_data_byte_ptr(lb, index * 4)
	(cast(^u32le)ptr)^ = u32le(transmute(u32)value)
}

// Set a 64-bit float at the given index
list_builder_set_f64 :: proc(lb: ^List_Builder, index: u32, value: f64) {
	if index >= lb.count || lb.element_size != .Eight_Bytes {
		return
	}
	ptr := list_data_byte_ptr(lb, index * 8)
	(cast(^u64le)ptr)^ = u64le(transmute(u64)value)
}

// Set a pointer at the given index (for pointer lists)
list_builder_set_pointer :: proc(lb: ^List_Builder, index: u32, value: u64) {
	if index >= lb.count || lb.element_size != .Pointer {
		return
	}
	word_offset := lb.data_offset + index
	segment_set_word(lb.segment, word_offset, value)
}

// Get a Struct_Builder for an element in a composite list
list_builder_get_struct :: proc(lb: ^List_Builder, index: u32) -> (sb: Struct_Builder, err: Error) {
	if index >= lb.count {
		return {}, .List_Index_Out_Of_Bounds
	}
	
	if lb.element_size != .Composite {
		return {}, .Invalid_Element_Size
	}
	
	words_per_element := u32(lb.data_words) + u32(lb.ptr_count)
	element_offset := lb.data_offset + (index * words_per_element)
	
	return Struct_Builder{
		segment       = lb.segment,
		data_offset   = element_offset,
		data_words    = lb.data_words,
		pointer_count = lb.ptr_count,
		manager       = lb.manager,
	}, .None
}
