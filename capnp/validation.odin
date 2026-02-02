package capnp

// Validation context for reading messages
Validation_Context :: struct {
	segments:         [][]Word,
	traversal_budget: ^u64,
	nesting_limit:    int,
}

// Check traversal limit and decrement budget
// Returns error if limit exceeded
check_traversal_limit :: proc(budget: ^u64, words: u64) -> Error {
	if words > budget^ {
		return .Traversal_Limit_Exceeded
	}
	budget^ -= words
	return .None
}

// Check nesting limit
// Returns error if limit is zero or negative
check_nesting_limit :: proc(nesting_limit: int) -> Error {
	if nesting_limit <= 0 {
		return .Nesting_Limit_Exceeded
	}
	return .None
}

// Check if an offset + size is within segment bounds
bounds_check :: proc(segment: []Word, word_offset: u32, word_count: u32) -> bool {
	if word_offset > u32(len(segment)) {
		return false
	}
	if word_count > u32(len(segment)) - word_offset {
		return false
	}
	return true
}

// Validated struct pointer result
Validated_Struct :: struct {
	segment_id:    u32,
	segment:       []Word,
	data_offset:   u32,
	data_size:     u16,
	pointer_count: u16,
}

// Validate a struct pointer and return the target location
validate_struct_pointer :: proc(
	ctx: ^Validation_Context,
	segment_id: u32,
	pointer_offset: u32,
	raw_pointer: u64,
) -> (result: Validated_Struct, err: Error) {
	if pointer_is_null(raw_pointer) {
		return {}, .Null_Pointer
	}
	
	kind := pointer_get_kind(raw_pointer)
	
	// Handle far pointers
	if kind == .Far {
		return follow_far_pointer_to_struct(ctx, raw_pointer)
	}
	
	if kind != .Struct {
		return {}, .Invalid_Pointer_Type
	}
	
	parts, ok := struct_pointer_decode(raw_pointer)
	if !ok {
		return {}, .Invalid_Pointer_Type
	}
	
	// Validate segment bounds
	if segment_id >= u32(len(ctx.segments)) {
		return {}, .Pointer_Out_Of_Bounds
	}
	segment := ctx.segments[segment_id]
	
	// Calculate target
	target, target_ok := struct_pointer_target(pointer_offset, parts.offset)
	if !target_ok {
		return {}, .Pointer_Out_Of_Bounds
	}
	
	struct_words := u32(parts.data_size) + u32(parts.pointer_count)
	
	// Bounds check struct content
	if !bounds_check(segment, target, struct_words) {
		return {}, .Pointer_Out_Of_Bounds
	}
	
	// Check traversal limit
	// Minimum 1 word for amplification attack prevention
	traversal_words := max(struct_words, 1)
	if err := check_traversal_limit(ctx.traversal_budget, u64(traversal_words)); err != .None {
		return {}, err
	}
	
	return Validated_Struct{
		segment_id    = segment_id,
		segment       = segment,
		data_offset   = target,
		data_size     = parts.data_size,
		pointer_count = parts.pointer_count,
	}, .None
}

// Validated list pointer result
Validated_List :: struct {
	segment_id:           u32,
	segment:              []Word,
	data_offset:          u32,
	element_size:         Element_Size,
	element_count:        u32,
	// For composite lists:
	struct_data_size:     u16,
	struct_pointer_count: u16,
}

// Decode composite list tag element count (unsigned 30 bits)
composite_tag_element_count :: proc(tag_word: u64) -> (count: u32, ok: bool) {
	if pointer_get_kind(tag_word) != .Struct {
		return 0, false
	}
	// Bits 2-31 contain the element count as unsigned 30 bits
	count = u32((tag_word >> 2) & 0x3FFFFFFF)
	return count, true
}

// Validate a list pointer and return the target location
validate_list_pointer :: proc(
	ctx: ^Validation_Context,
	segment_id: u32,
	pointer_offset: u32,
	raw_pointer: u64,
	expected_element_size: Element_Size,
) -> (result: Validated_List, err: Error) {
	if pointer_is_null(raw_pointer) {
		return {}, .Null_Pointer
	}
	
	kind := pointer_get_kind(raw_pointer)
	
	// Handle far pointers
	if kind == .Far {
		return follow_far_pointer_to_list(ctx, raw_pointer, expected_element_size)
	}
	
	if kind != .List {
		return {}, .Invalid_Pointer_Type
	}
	
	parts, ok := list_pointer_decode(raw_pointer)
	if !ok {
		return {}, .Invalid_Pointer_Type
	}
	
	// Validate segment bounds
	if segment_id >= u32(len(ctx.segments)) {
		return {}, .Pointer_Out_Of_Bounds
	}
	segment := ctx.segments[segment_id]
	
	// Calculate target
	target, target_ok := list_pointer_target(pointer_offset, parts.offset)
	if !target_ok {
		return {}, .Pointer_Out_Of_Bounds
	}
	
	// Calculate list size in words
	list_words: u32
	struct_data_size: u16 = 0
	struct_pointer_count: u16 = 0
	element_count := parts.element_count
	data_offset := target
	
	if parts.element_size == .Composite {
		// Composite list: element_count is total words, need to read tag
		list_words = parts.element_count
		
		// Need at least 1 word for tag
		if !bounds_check(segment, target, 1) {
			return {}, .Pointer_Out_Of_Bounds
		}
		
		// Read tag word
		tag := segment[target]
		tag_parts, tag_ok := struct_pointer_decode(tag)
		if !tag_ok {
			return {}, .Invalid_Pointer_Type
		}
		
		struct_data_size = tag_parts.data_size
		struct_pointer_count = tag_parts.pointer_count
		
		// Decode element count as unsigned 30-bit value (not signed offset)
		elem_count, elem_ok := composite_tag_element_count(tag)
		if !elem_ok {
			return {}, .Invalid_Pointer_Type
		}
		element_count = elem_count
		data_offset = target + 1 // content starts after tag
		
		// Verify consistency
		words_per_element := u32(struct_data_size) + u32(struct_pointer_count)
		if words_per_element > 0 && element_count > list_words / words_per_element {
			return {}, .Pointer_Out_Of_Bounds
		}
	} else {
		// Calculate words from element size and count
		bits_per_element := element_size_bits(parts.element_size)
		total_bits := u64(bits_per_element) * u64(parts.element_count)
		list_words = u32((total_bits + 63) / 64)
	}
	
	// Bounds check list content (use u64 to prevent overflow)
	total_list_words := u64(list_words) + (1 if parts.element_size == .Composite else 0)
	if u64(target) + total_list_words > u64(len(segment)) {
		return {}, .Pointer_Out_Of_Bounds
	}
	
	// Check traversal limit
	// Zero-sized elements count as 1 word each (amplification prevention)
	traversal_words: u64
	if parts.element_size == .Void || (parts.element_size == .Composite && struct_data_size == 0 && struct_pointer_count == 0) {
		traversal_words = u64(element_count)
	} else {
		traversal_words = u64(max(list_words, 1))
	}
	
	if err := check_traversal_limit(ctx.traversal_budget, traversal_words); err != .None {
		return {}, err
	}
	
	return Validated_List{
		segment_id           = segment_id,
		segment              = segment,
		data_offset          = data_offset,
		element_size         = parts.element_size,
		element_count        = element_count,
		struct_data_size     = struct_data_size,
		struct_pointer_count = struct_pointer_count,
	}, .None
}

// Follow a far pointer to resolve to a struct
follow_far_pointer_to_struct :: proc(
	ctx: ^Validation_Context,
	raw_pointer: u64,
) -> (result: Validated_Struct, err: Error) {
	far_parts, ok := far_pointer_decode(raw_pointer)
	if !ok {
		return {}, .Invalid_Pointer_Type
	}
	
	// Validate target segment exists
	if far_parts.segment_id >= u32(len(ctx.segments)) {
		return {}, .Pointer_Out_Of_Bounds
	}
	target_segment := ctx.segments[far_parts.segment_id]
	
	// Validate landing pad offset
	if far_parts.offset >= u32(len(target_segment)) {
		return {}, .Pointer_Out_Of_Bounds
	}
	
	if far_parts.is_double {
		// Double-far pointer: landing pad contains another far pointer + tag
		if far_parts.offset + 1 >= u32(len(target_segment)) {
			return {}, .Pointer_Out_Of_Bounds
		}
		
		// First word is far pointer to actual content
		content_far := target_segment[far_parts.offset]
		content_far_parts, content_ok := far_pointer_decode(content_far)
		if !content_ok {
			return {}, .Invalid_Pointer_Type
		}
		
		// Second word is the tag (struct pointer format without offset)
		tag := target_segment[far_parts.offset + 1]
		tag_parts, tag_ok := struct_pointer_decode(tag)
		if !tag_ok {
			return {}, .Invalid_Pointer_Type
		}
		
		// Validate content segment
		if content_far_parts.segment_id >= u32(len(ctx.segments)) {
			return {}, .Pointer_Out_Of_Bounds
		}
		content_segment := ctx.segments[content_far_parts.segment_id]
		
		struct_words := u32(tag_parts.data_size) + u32(tag_parts.pointer_count)
		
		// Bounds check
		if !bounds_check(content_segment, content_far_parts.offset, struct_words) {
			return {}, .Pointer_Out_Of_Bounds
		}
		
		// Check traversal limit
		traversal_words := max(struct_words, 1)
		if err := check_traversal_limit(ctx.traversal_budget, u64(traversal_words)); err != .None {
			return {}, err
		}
		
		return Validated_Struct{
			segment_id    = content_far_parts.segment_id,
			segment       = content_segment,
			data_offset   = content_far_parts.offset,
			data_size     = tag_parts.data_size,
			pointer_count = tag_parts.pointer_count,
		}, .None
	} else {
		// Single-far pointer: landing pad contains the actual struct pointer
		landing_pad := target_segment[far_parts.offset]
		
		// Recursively validate (but from new segment, at landing pad position)
		return validate_struct_pointer(ctx, far_parts.segment_id, far_parts.offset, landing_pad)
	}
}

// Follow a far pointer to resolve to a list
follow_far_pointer_to_list :: proc(
	ctx: ^Validation_Context,
	raw_pointer: u64,
	expected_element_size: Element_Size,
) -> (result: Validated_List, err: Error) {
	far_parts, ok := far_pointer_decode(raw_pointer)
	if !ok {
		return {}, .Invalid_Pointer_Type
	}
	
	// Validate target segment exists
	if far_parts.segment_id >= u32(len(ctx.segments)) {
		return {}, .Pointer_Out_Of_Bounds
	}
	target_segment := ctx.segments[far_parts.segment_id]
	
	// Validate landing pad offset
	if far_parts.offset >= u32(len(target_segment)) {
		return {}, .Pointer_Out_Of_Bounds
	}
	
	if far_parts.is_double {
		// Double-far pointer: landing pad contains another far pointer + tag
		if far_parts.offset + 1 >= u32(len(target_segment)) {
			return {}, .Pointer_Out_Of_Bounds
		}
		
		// First word is far pointer to actual content
		content_far := target_segment[far_parts.offset]
		content_far_parts, content_ok := far_pointer_decode(content_far)
		if !content_ok {
			return {}, .Invalid_Pointer_Type
		}
		
		// Second word is the tag (list pointer format without offset)
		tag := target_segment[far_parts.offset + 1]
		tag_parts, tag_ok := list_pointer_decode(tag)
		if !tag_ok {
			return {}, .Invalid_Pointer_Type
		}
		
		// Validate content segment
		if content_far_parts.segment_id >= u32(len(ctx.segments)) {
			return {}, .Pointer_Out_Of_Bounds
		}
		content_segment := ctx.segments[content_far_parts.segment_id]
		
		// Calculate list size
		struct_data_size: u16 = 0
		struct_pointer_count: u16 = 0
		element_count := tag_parts.element_count
		data_offset := content_far_parts.offset
		list_words: u32
		
		if tag_parts.element_size == .Composite {
			list_words = tag_parts.element_count
			
			// Read composite tag
			if !bounds_check(content_segment, data_offset, 1) {
				return {}, .Pointer_Out_Of_Bounds
			}
			
			composite_tag := content_segment[data_offset]
			composite_parts, composite_ok := struct_pointer_decode(composite_tag)
			if !composite_ok {
				return {}, .Invalid_Pointer_Type
			}
			
			struct_data_size = composite_parts.data_size
			struct_pointer_count = composite_parts.pointer_count
			
			// Decode element count as unsigned 30-bit value
			elem_count, elem_ok := composite_tag_element_count(composite_tag)
			if !elem_ok {
				return {}, .Invalid_Pointer_Type
			}
			element_count = elem_count
			data_offset += 1
		} else {
			bits_per_element := element_size_bits(tag_parts.element_size)
			total_bits := u64(bits_per_element) * u64(tag_parts.element_count)
			list_words = u32((total_bits + 63) / 64)
		}
		
		// Bounds check
		total_words := list_words
		if tag_parts.element_size == .Composite {
			total_words += 1 // tag word
		}
		if !bounds_check(content_segment, content_far_parts.offset, total_words) {
			return {}, .Pointer_Out_Of_Bounds
		}
		
		// Check traversal limit
		traversal_words: u64
		if tag_parts.element_size == .Void || (tag_parts.element_size == .Composite && struct_data_size == 0 && struct_pointer_count == 0) {
			traversal_words = u64(element_count)
		} else {
			traversal_words = u64(max(list_words, 1))
		}
		
		if err := check_traversal_limit(ctx.traversal_budget, traversal_words); err != .None {
			return {}, err
		}
		
		return Validated_List{
			segment_id           = content_far_parts.segment_id,
			segment              = content_segment,
			data_offset          = data_offset,
			element_size         = tag_parts.element_size,
			element_count        = element_count,
			struct_data_size     = struct_data_size,
			struct_pointer_count = struct_pointer_count,
		}, .None
	} else {
		// Single-far pointer: landing pad contains the actual list pointer
		landing_pad := target_segment[far_parts.offset]
		
		// Recursively validate (but from new segment, at landing pad position)
		return validate_list_pointer(ctx, far_parts.segment_id, far_parts.offset, landing_pad, expected_element_size)
	}
}

// Validate that text is properly NUL-terminated
validate_text :: proc(data: []byte) -> (text: string, err: Error) {
	if len(data) == 0 {
		return "", .None
	}
	
	// Last byte must be NUL
	if data[len(data) - 1] != 0 {
		return "", .Text_Not_Nul_Terminated
	}
	
	// Return string without the NUL terminator
	return string(data[:len(data) - 1]), .None
}
