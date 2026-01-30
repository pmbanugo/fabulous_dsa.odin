package capnp

// Extract the pointer kind from a raw u64 value
pointer_get_kind :: proc(raw: u64) -> Pointer_Kind {
	return Pointer_Kind(raw & 0b11)
}

// Check if a pointer is null (all zeros)
pointer_is_null :: proc(raw: u64) -> bool {
	return raw == 0
}

// Create a struct pointer from its components
struct_pointer_encode :: proc(offset: i32, data_size: u16, pointer_count: u16) -> u64 {
	p := Struct_Pointer {
		kind          = .Struct,
		offset        = offset,
		data_size     = data_size,
		pointer_count = pointer_count,
	}
	return transmute(u64)p
}

// Decoded struct pointer components
Struct_Pointer_Parts :: struct {
	offset:        i32,
	data_size:     u16,
	pointer_count: u16,
}

// Decode a struct pointer into its components
struct_pointer_decode :: proc(raw: u64) -> (parts: Struct_Pointer_Parts, ok: bool) {
	if pointer_get_kind(raw) != .Struct {
		return {}, false
	}
	p := transmute(Struct_Pointer)raw
	return Struct_Pointer_Parts{
		offset        = p.offset,
		data_size     = p.data_size,
		pointer_count = p.pointer_count,
	}, true
}

// Calculate the target word address from a struct pointer location
// pointer_location is the word index where the pointer is stored
// Returns the word index where the struct content begins, or false if underflow
struct_pointer_target :: proc(pointer_location: u32, offset: i32) -> (target: u32, ok: bool) {
	// Target = pointer_location + 1 + offset
	// The +1 is because the offset is relative to the word AFTER the pointer
	result := i64(pointer_location) + 1 + i64(offset)
	if result < 0 || result > i64(max(u32)) {
		return 0, false
	}
	return u32(result), true
}

// Create a list pointer from its components
list_pointer_encode :: proc(offset: i32, element_size: Element_Size, element_count: u32) -> u64 {
	p := List_Pointer {
		kind          = .List,
		offset        = offset,
		element_size  = element_size,
		element_count = element_count,
	}
	return transmute(u64)p
}

// Decoded list pointer components
List_Pointer_Parts :: struct {
	offset:        i32,
	element_size:  Element_Size,
	element_count: u32,
}

// Decode a list pointer into its components
list_pointer_decode :: proc(raw: u64) -> (parts: List_Pointer_Parts, ok: bool) {
	if pointer_get_kind(raw) != .List {
		return {}, false
	}
	p := transmute(List_Pointer)raw
	return List_Pointer_Parts{
		offset        = p.offset,
		element_size  = p.element_size,
		element_count = p.element_count,
	}, true
}

// Calculate the target word address from a list pointer location
// pointer_location is the word index where the pointer is stored
// Returns the word index where the list content begins, or false if underflow
list_pointer_target :: proc(pointer_location: u32, offset: i32) -> (target: u32, ok: bool) {
	// Same formula as struct pointers
	result := i64(pointer_location) + 1 + i64(offset)
	if result < 0 || result > i64(max(u32)) {
		return 0, false
	}
	return u32(result), true
}

// Create a far pointer from its components
far_pointer_encode :: proc(is_double: bool, offset: u32, segment_id: u32) -> u64 {
	p := Far_Pointer {
		kind       = .Far,
		is_double  = is_double,
		offset     = offset,
		segment_id = segment_id,
	}
	return transmute(u64)p
}

// Decoded far pointer components
Far_Pointer_Parts :: struct {
	is_double:  bool,
	offset:     u32,
	segment_id: u32,
}

// Decode a far pointer into its components
far_pointer_decode :: proc(raw: u64) -> (parts: Far_Pointer_Parts, ok: bool) {
	if pointer_get_kind(raw) != .Far {
		return {}, false
	}
	p := transmute(Far_Pointer)raw
	return Far_Pointer_Parts{
		is_double  = p.is_double,
		offset     = p.offset,
		segment_id = p.segment_id,
	}, true
}

// Return the number of bits per element for each Element_Size
// Returns 0 for Void, and a special value for Composite (handled separately)
element_size_bits :: proc(size: Element_Size) -> u32 {
	switch size {
	case .Void:
		return 0
	case .Bit:
		return 1
	case .Byte:
		return 8
	case .Two_Bytes:
		return 16
	case .Four_Bytes:
		return 32
	case .Eight_Bytes, .Pointer:
		return 64
	case .Composite:
		return 0 // Composite lists have variable element size
	}
	return 0
}

// Return the number of bytes per element for each Element_Size
// For sub-byte sizes (Void, Bit), returns 0
element_size_bytes :: proc(size: Element_Size) -> u32 {
	switch size {
	case .Void, .Bit:
		return 0
	case .Byte:
		return 1
	case .Two_Bytes:
		return 2
	case .Four_Bytes:
		return 4
	case .Eight_Bytes, .Pointer:
		return 8
	case .Composite:
		return 0 // Composite lists have variable element size
	}
	return 0
}
