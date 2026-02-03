package capnp_tests

import capnp ".."
import "core:testing"

// ============================================================================
// Struct Pointer Encoding Tests
// ============================================================================

@(test)
test_struct_pointer_roundtrip_zero_offset :: proc(t: ^testing.T) {
	// Zero offset case
	encoded := capnp.struct_pointer_encode(0, 2, 3)
	parts, ok := capnp.struct_pointer_decode(encoded)

	testing.expect(t, ok, "Decode should succeed")
	testing.expect_value(t, parts.offset, i32(0))
	testing.expect_value(t, parts.data_size, u16(2))
	testing.expect_value(t, parts.pointer_count, u16(3))
	testing.expect_value(t, capnp.pointer_get_kind(encoded), capnp.Pointer_Kind.Struct)
}

@(test)
test_struct_pointer_negative_offset :: proc(t: ^testing.T) {
	// Test negative offsets (valid per spec)
	encoded := capnp.struct_pointer_encode(-100, 5, 2)
	parts, ok := capnp.struct_pointer_decode(encoded)

	testing.expect(t, ok, "Decode should succeed for negative offset")
	testing.expect_value(t, parts.offset, i32(-100))
	testing.expect_value(t, parts.data_size, u16(5))
	testing.expect_value(t, parts.pointer_count, u16(2))
}

@(test)
test_struct_pointer_max_sizes :: proc(t: ^testing.T) {
	// Maximum u16 values for data_size and pointer_count
	max_u16 := u16(0xFFFF)
	encoded := capnp.struct_pointer_encode(0, max_u16, max_u16)
	parts, ok := capnp.struct_pointer_decode(encoded)

	testing.expect(t, ok, "Decode should succeed")
	testing.expect_value(t, parts.data_size, max_u16)
	testing.expect_value(t, parts.pointer_count, max_u16)
}

@(test)
test_struct_pointer_zero_sized :: proc(t: ^testing.T) {
	// Zero-sized struct uses offset = -1 per spec
	encoded := capnp.struct_pointer_encode(-1, 0, 0)
	parts, ok := capnp.struct_pointer_decode(encoded)

	testing.expect(t, ok, "Decode should succeed")
	testing.expect_value(t, parts.offset, i32(-1))
	testing.expect_value(t, parts.data_size, u16(0))
	testing.expect_value(t, parts.pointer_count, u16(0))
}

@(test)
test_struct_pointer_target_underflow :: proc(t: ^testing.T) {
	// Pointer at word 0 with offset -2 would give negative target
	_, ok := capnp.struct_pointer_target(0, -2)
	testing.expect(t, !ok, "Should fail on underflow")
}

@(test)
test_struct_pointer_target_valid :: proc(t: ^testing.T) {
	// target = pointer_location + 1 + offset = 5 + 1 + 3 = 9
	target, ok := capnp.struct_pointer_target(5, 3)
	testing.expect(t, ok, "Should succeed")
	testing.expect_value(t, target, u32(9))
}

@(test)
test_null_pointer_detection :: proc(t: ^testing.T) {
	testing.expect(t, capnp.pointer_is_null(0), "Zero should be null")
	testing.expect(t, !capnp.pointer_is_null(1), "Non-zero should not be null")
	testing.expect(t, !capnp.pointer_is_null(0xFFFF_FFFF_FFFF_FFFF), "All ones should not be null")

	// A valid struct pointer with offset=0, data=0, pointers=0 is NOT null (kind bits are set)
	empty_struct := capnp.struct_pointer_encode(0, 0, 0)
	testing.expect(t, capnp.pointer_is_null(empty_struct), "Empty struct pointer (0,0,0) is null")
}

// ============================================================================
// List Pointer Encoding Tests
// ============================================================================

@(test)
test_list_pointer_roundtrip_zero_offset :: proc(t: ^testing.T) {
	encoded := capnp.list_pointer_encode(0, .Four_Bytes, 100)
	parts, ok := capnp.list_pointer_decode(encoded)

	testing.expect(t, ok, "Decode should succeed")
	testing.expect_value(t, parts.offset, i32(0))
	testing.expect_value(t, parts.element_size, capnp.Element_Size.Four_Bytes)
	testing.expect_value(t, parts.element_count, u32(100))
	testing.expect_value(t, capnp.pointer_get_kind(encoded), capnp.Pointer_Kind.List)
}

@(test)
test_list_pointer_negative_offset :: proc(t: ^testing.T) {
	encoded := capnp.list_pointer_encode(-50, .Eight_Bytes, 10)
	parts, ok := capnp.list_pointer_decode(encoded)

	testing.expect(t, ok, "Decode should succeed for negative offset")
	testing.expect_value(t, parts.offset, i32(-50))
}

@(test)
test_list_pointer_all_element_sizes :: proc(t: ^testing.T) {
	sizes := []capnp.Element_Size{
		.Void,
		.Bit,
		.Byte,
		.Two_Bytes,
		.Four_Bytes,
		.Eight_Bytes,
		.Pointer,
		.Composite,
	}

	for size in sizes {
		encoded := capnp.list_pointer_encode(0, size, 50)
		parts, ok := capnp.list_pointer_decode(encoded)
		testing.expect(t, ok, "Decode should succeed")
		testing.expect_value(t, parts.element_size, size)
	}
}

@(test)
test_list_pointer_max_element_count :: proc(t: ^testing.T) {
	// 29-bit max value
	max_count := u32(0x1FFF_FFFF)
	encoded := capnp.list_pointer_encode(0, .Byte, max_count)
	parts, ok := capnp.list_pointer_decode(encoded)

	testing.expect(t, ok, "Decode should succeed")
	testing.expect_value(t, parts.element_count, max_count)
}

@(test)
test_list_pointer_target_underflow :: proc(t: ^testing.T) {
	_, ok := capnp.list_pointer_target(0, -5)
	testing.expect(t, !ok, "Should fail on underflow")
}

// ============================================================================
// Far Pointer Encoding Tests
// ============================================================================

@(test)
test_far_pointer_single_pad :: proc(t: ^testing.T) {
	encoded := capnp.far_pointer_encode(false, 100, 5)
	parts, ok := capnp.far_pointer_decode(encoded)

	testing.expect(t, ok, "Decode should succeed")
	testing.expect(t, !parts.is_double, "Should be single landing pad")
	testing.expect_value(t, parts.offset, u32(100))
	testing.expect_value(t, parts.segment_id, u32(5))
	testing.expect_value(t, capnp.pointer_get_kind(encoded), capnp.Pointer_Kind.Far)
}

@(test)
test_far_pointer_double_pad :: proc(t: ^testing.T) {
	encoded := capnp.far_pointer_encode(true, 200, 10)
	parts, ok := capnp.far_pointer_decode(encoded)

	testing.expect(t, ok, "Decode should succeed")
	testing.expect(t, parts.is_double, "Should be double landing pad")
	testing.expect_value(t, parts.offset, u32(200))
	testing.expect_value(t, parts.segment_id, u32(10))
}

@(test)
test_far_pointer_max_values :: proc(t: ^testing.T) {
	// 29-bit max for offset, 32-bit max for segment_id
	max_offset := u32(0x1FFF_FFFF)
	max_seg_id := u32(0xFFFF_FFFF)
	encoded := capnp.far_pointer_encode(true, max_offset, max_seg_id)
	parts, ok := capnp.far_pointer_decode(encoded)

	testing.expect(t, ok, "Decode should succeed")
	testing.expect_value(t, parts.offset, max_offset)
	testing.expect_value(t, parts.segment_id, max_seg_id)
}

// ============================================================================
// Cross-decode Validation Tests
// ============================================================================

@(test)
test_decode_wrong_kind_struct_as_list :: proc(t: ^testing.T) {
	struct_ptr := capnp.struct_pointer_encode(0, 1, 1)
	_, ok := capnp.list_pointer_decode(struct_ptr)
	testing.expect(t, !ok, "Should fail to decode struct as list")
}

@(test)
test_decode_wrong_kind_list_as_far :: proc(t: ^testing.T) {
	list_ptr := capnp.list_pointer_encode(0, .Byte, 10)
	_, ok := capnp.far_pointer_decode(list_ptr)
	testing.expect(t, !ok, "Should fail to decode list as far")
}

@(test)
test_decode_wrong_kind_far_as_struct :: proc(t: ^testing.T) {
	far_ptr := capnp.far_pointer_encode(false, 0, 0)
	_, ok := capnp.struct_pointer_decode(far_ptr)
	testing.expect(t, !ok, "Should fail to decode far as struct")
}

// ============================================================================
// Element Size Bits Tests
// ============================================================================

@(test)
test_element_size_bits :: proc(t: ^testing.T) {
	testing.expect_value(t, capnp.element_size_bits(.Void), u32(0))
	testing.expect_value(t, capnp.element_size_bits(.Bit), u32(1))
	testing.expect_value(t, capnp.element_size_bits(.Byte), u32(8))
	testing.expect_value(t, capnp.element_size_bits(.Two_Bytes), u32(16))
	testing.expect_value(t, capnp.element_size_bits(.Four_Bytes), u32(32))
	testing.expect_value(t, capnp.element_size_bits(.Eight_Bytes), u32(64))
	testing.expect_value(t, capnp.element_size_bits(.Pointer), u32(64))
	testing.expect_value(t, capnp.element_size_bits(.Composite), u32(0))
}

@(test)
test_element_size_bytes :: proc(t: ^testing.T) {
	testing.expect_value(t, capnp.element_size_bytes(.Void), u32(0))
	testing.expect_value(t, capnp.element_size_bytes(.Bit), u32(0))
	testing.expect_value(t, capnp.element_size_bytes(.Byte), u32(1))
	testing.expect_value(t, capnp.element_size_bytes(.Two_Bytes), u32(2))
	testing.expect_value(t, capnp.element_size_bytes(.Four_Bytes), u32(4))
	testing.expect_value(t, capnp.element_size_bytes(.Eight_Bytes), u32(8))
	testing.expect_value(t, capnp.element_size_bytes(.Pointer), u32(8))
	testing.expect_value(t, capnp.element_size_bytes(.Composite), u32(0))
}
