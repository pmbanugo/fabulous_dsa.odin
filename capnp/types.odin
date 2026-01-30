package capnp

// Cap'n Proto requires little-endian byte order for all data.
// This implementation assumes a little-endian host (x86_64, ARM64).
// Big-endian architectures are NOT supported.

// Word size constants as per Cap'n Proto specification
WORD_SIZE_BYTES :: 8
BITS_PER_WORD :: 64

// A Word is the fundamental unit in Cap'n Proto (64 bits / 8 bytes)
Word :: u64

// Pointer kind is determined by the lowest 2 bits of a pointer
Pointer_Kind :: enum u8 {
	Struct = 0,
	List   = 1,
	Far    = 2,
	Other  = 3, // Capability pointers (not implemented)
}

// Element size codes for list pointers (3 bits)
Element_Size :: enum u8 {
	Void      = 0, // 0 bits
	Bit       = 1, // 1 bit (bool)
	Byte      = 2, // 1 byte
	Two_Bytes = 3, // 2 bytes
	Four_Bytes= 4, // 4 bytes
	Eight_Bytes = 5, // 8 bytes
	Pointer   = 6, // 8 bytes (pointer)
	Composite = 7, // Inline composite (struct list)
}

// Struct Pointer layout: 2 + 30 + 16 + 16 = 64 bits
//   Bits 0-1:   kind (00 for struct)
//   Bits 2-31:  offset (signed, in words from pointer to struct content)
//   Bits 32-47: data section size in words
//   Bits 48-63: pointer count in pointer section
Struct_Pointer :: bit_field u64 {
	kind:         Pointer_Kind | 2,
	offset:       i32 | 30, // signed offset in words
	data_size:    u16 | 16, // data section size in words
	pointer_count: u16 | 16, // number of pointers
}

// List Pointer layout: 2 + 30 + 3 + 29 = 64 bits
//   Bits 0-1:   kind (01 for list)
//   Bits 2-31:  offset (signed, in words from pointer to list content)
//   Bits 32-34: element size code
//   Bits 35-63: element count (or total words for composite)
List_Pointer :: bit_field u64 {
	kind:         Pointer_Kind | 2,
	offset:       i32 | 30, // signed offset in words
	element_size: Element_Size | 3,
	element_count: u32 | 29, // element count (or total words for composite)
}

// Far Pointer layout: 2 + 1 + 29 + 32 = 64 bits
//   Bits 0-1:   kind (10 for far)
//   Bit 2:      landing pad type (0 = single, 1 = double)
//   Bits 3-31:  offset in target segment (words)
//   Bits 32-63: target segment ID
Far_Pointer :: bit_field u64 {
	kind:       Pointer_Kind | 2,
	is_double:  bool | 1, // 0 = single landing pad, 1 = double
	offset:     u32 | 29, // offset in target segment (words)
	segment_id: u32 | 32, // target segment ID
}

// Capability Pointer layout (for completeness, not implemented)
//   Bits 0-1:   kind (11 for capability)
//   Bits 2-31:  must be zero
//   Bits 32-63: capability table index
Capability_Pointer :: bit_field u64 {
	kind:       Pointer_Kind | 2,
	_reserved:  u32 | 30, // must be zero
	cap_index:  u32 | 32, // capability table index
}

// Raw union of all pointer types for reinterpretation
Pointer :: struct #raw_union {
	raw:        u64,
	struct_ptr: Struct_Pointer,
	list_ptr:   List_Pointer,
	far_ptr:    Far_Pointer,
	cap_ptr:    Capability_Pointer,
}
