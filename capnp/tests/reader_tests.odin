package capnp_tests

import capnp ".."
import "core:mem"
import "core:testing"

// ============================================================================
// Primitive Type Reading Tests
// ============================================================================

@(test)
test_reader_get_u8_default :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 0)
	capnp.struct_builder_set_u8(&root, 0, 0x42)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	// Valid read
	testing.expect_value(t, capnp.struct_reader_get_u8(&sr, 0), u8(0x42))

	// Out-of-bounds read returns default
	testing.expect_value(t, capnp.struct_reader_get_u8(&sr, 100, 0xFF), u8(0xFF))
}

@(test)
test_reader_get_u16_default :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 0)
	capnp.struct_builder_set_u16(&root, 0, 0x1234)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	testing.expect_value(t, capnp.struct_reader_get_u16(&sr, 0), u16(0x1234))
	testing.expect_value(t, capnp.struct_reader_get_u16(&sr, 100, 0xABCD), u16(0xABCD))
}

@(test)
test_reader_get_u32_default :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 0)
	capnp.struct_builder_set_u32(&root, 0, 0x12345678)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	testing.expect_value(t, capnp.struct_reader_get_u32(&sr, 0), u32(0x12345678))
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr, 100, 0xDEADBEEF), u32(0xDEADBEEF))
}

@(test)
test_reader_get_u64_default :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 0)
	capnp.struct_builder_set_u64(&root, 0, 0x123456789ABCDEF0)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	testing.expect_value(t, capnp.struct_reader_get_u64(&sr, 0), u64(0x123456789ABCDEF0))
	testing.expect_value(t, capnp.struct_reader_get_u64(&sr, 100, 0xFFFF), u64(0xFFFF))
}

@(test)
test_reader_get_signed_integers_default :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 2, 0)
	capnp.struct_builder_set_i8(&root, 0, -42)
	capnp.struct_builder_set_i16(&root, 2, -1234)
	capnp.struct_builder_set_i32(&root, 4, -100000)
	capnp.struct_builder_set_i64(&root, 8, -9876543210)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	// Valid reads
	testing.expect_value(t, capnp.struct_reader_get_i8(&sr, 0), i8(-42))
	testing.expect_value(t, capnp.struct_reader_get_i16(&sr, 2), i16(-1234))
	testing.expect_value(t, capnp.struct_reader_get_i32(&sr, 4), i32(-100000))
	testing.expect_value(t, capnp.struct_reader_get_i64(&sr, 8), i64(-9876543210))

	// Out-of-bounds with defaults
	testing.expect_value(t, capnp.struct_reader_get_i8(&sr, 100, -99), i8(-99))
	testing.expect_value(t, capnp.struct_reader_get_i16(&sr, 100, -999), i16(-999))
	testing.expect_value(t, capnp.struct_reader_get_i32(&sr, 100, -99999), i32(-99999))
	testing.expect_value(t, capnp.struct_reader_get_i64(&sr, 100, -9999999999), i64(-9999999999))
}

@(test)
test_reader_get_floats_default :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 2, 0)
	capnp.struct_builder_set_f32(&root, 0, 3.14159)
	capnp.struct_builder_set_f64(&root, 8, 2.71828)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	f32_val := capnp.struct_reader_get_f32(&sr, 0)
	testing.expect(t, abs(f32_val - 3.14159) < 0.0001, "f32 should match")

	f64_val := capnp.struct_reader_get_f64(&sr, 8)
	testing.expect(t, abs(f64_val - 2.71828) < 0.00001, "f64 should match")

	// Defaults
	testing.expect_value(t, capnp.struct_reader_get_f32(&sr, 100, 1.0), f32(1.0))
	testing.expect_value(t, capnp.struct_reader_get_f64(&sr, 100, 2.0), f64(2.0))
}

@(test)
test_reader_get_bool_default :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 0)
	capnp.struct_builder_set_bool(&root, 0, true)
	capnp.struct_builder_set_bool(&root, 1, false)
	capnp.struct_builder_set_bool(&root, 7, true)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 0), true)
	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 1), false)
	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 7), true)

	// Out-of-bounds with default true
	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 1000, true), true)
	// Out-of-bounds with default false
	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 1000, false), false)
}

// ============================================================================
// Nested Struct Reading Tests
// ============================================================================

@(test)
test_reader_nested_struct :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 1)
	capnp.struct_builder_set_u32(&root, 0, 100)

	nested, _ := capnp.struct_builder_init_struct(&root, 0, 1, 0)
	capnp.struct_builder_set_u64(&nested, 0, 0xDEADBEEF)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr, 0), u32(100))

	nested_sr, nested_err := capnp.struct_reader_get_struct(&sr, 0)
	testing.expect_value(t, nested_err, capnp.Error.None)
	testing.expect_value(t, capnp.struct_reader_get_u64(&nested_sr, 0), u64(0xDEADBEEF))
}

@(test)
test_reader_nested_struct_null :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	// Create struct with pointer slot but don't initialize it
	root, _ := capnp.message_builder_init_root(&mb, 1, 1)
	capnp.struct_builder_set_u32(&root, 0, 42)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	// Pointer is null
	testing.expect(t, !capnp.struct_reader_has_pointer(&sr, 0), "Pointer should be null")

	// Reading null struct returns an empty struct (Cap'n Proto default behavior)
	// This is NOT an error - null pointers are treated as default values
	nested, nested_err := capnp.struct_reader_get_struct(&sr, 0)
	testing.expect_value(t, nested_err, capnp.Error.None)
	testing.expect_value(t, nested.data_size, u16(0))
	testing.expect_value(t, nested.pointer_count, u16(0))
}

// ============================================================================
// List Reading Tests
// ============================================================================

@(test)
test_reader_list_all_types :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 6)

	// Create lists of various types
	list_bit, _ := capnp.struct_builder_init_list(&root, 0, .Bit, 8)
	capnp.list_builder_set_bool(&list_bit, 0, true)
	capnp.list_builder_set_bool(&list_bit, 7, true)

	list_byte, _ := capnp.struct_builder_init_list(&root, 1, .Byte, 4)
	capnp.list_builder_set_u8(&list_byte, 0, 10)
	capnp.list_builder_set_u8(&list_byte, 3, 40)

	list_u16, _ := capnp.struct_builder_init_list(&root, 2, .Two_Bytes, 3)
	capnp.list_builder_set_u16(&list_u16, 0, 1000)
	capnp.list_builder_set_u16(&list_u16, 2, 3000)

	list_u32, _ := capnp.struct_builder_init_list(&root, 3, .Four_Bytes, 2)
	capnp.list_builder_set_u32(&list_u32, 0, 100000)
	capnp.list_builder_set_u32(&list_u32, 1, 200000)

	list_u64, _ := capnp.struct_builder_init_list(&root, 4, .Eight_Bytes, 2)
	capnp.list_builder_set_u64(&list_u64, 0, 0x123456789ABCDEF0)
	capnp.list_builder_set_u64(&list_u64, 1, 0xFEDCBA9876543210)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	// Read and verify each list
	lr_bit, _ := capnp.struct_reader_get_list(&sr, 0, .Bit)
	testing.expect_value(t, capnp.list_reader_len(&lr_bit), u32(8))
	testing.expect_value(t, capnp.list_reader_get_bool(&lr_bit, 0), true)
	testing.expect_value(t, capnp.list_reader_get_bool(&lr_bit, 7), true)

	lr_byte, _ := capnp.struct_reader_get_list(&sr, 1, .Byte)
	testing.expect_value(t, capnp.list_reader_len(&lr_byte), u32(4))
	testing.expect_value(t, capnp.list_reader_get_u8(&lr_byte, 0), u8(10))
	testing.expect_value(t, capnp.list_reader_get_u8(&lr_byte, 3), u8(40))

	lr_u16, _ := capnp.struct_reader_get_list(&sr, 2, .Two_Bytes)
	testing.expect_value(t, capnp.list_reader_len(&lr_u16), u32(3))
	testing.expect_value(t, capnp.list_reader_get_u16(&lr_u16, 0), u16(1000))
	testing.expect_value(t, capnp.list_reader_get_u16(&lr_u16, 2), u16(3000))

	lr_u32, _ := capnp.struct_reader_get_list(&sr, 3, .Four_Bytes)
	testing.expect_value(t, capnp.list_reader_len(&lr_u32), u32(2))
	testing.expect_value(t, capnp.list_reader_get_u32(&lr_u32, 0), u32(100000))
	testing.expect_value(t, capnp.list_reader_get_u32(&lr_u32, 1), u32(200000))

	lr_u64, _ := capnp.struct_reader_get_list(&sr, 4, .Eight_Bytes)
	testing.expect_value(t, capnp.list_reader_len(&lr_u64), u32(2))
	testing.expect_value(t, capnp.list_reader_get_u64(&lr_u64, 0), u64(0x123456789ABCDEF0))
	testing.expect_value(t, capnp.list_reader_get_u64(&lr_u64, 1), u64(0xFEDCBA9876543210))
}

@(test)
test_reader_composite_list :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	list, _ := capnp.struct_builder_init_struct_list(&root, 0, 3, 1, 0)

	s0, _ := capnp.list_builder_get_struct(&list, 0)
	capnp.struct_builder_set_u32(&s0, 0, 100)

	s1, _ := capnp.list_builder_get_struct(&list, 1)
	capnp.struct_builder_set_u32(&s1, 0, 200)

	s2, _ := capnp.list_builder_get_struct(&list, 2)
	capnp.struct_builder_set_u32(&s2, 0, 300)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	lr, list_err := capnp.struct_reader_get_list(&sr, 0, .Composite)
	testing.expect_value(t, list_err, capnp.Error.None)
	testing.expect_value(t, capnp.list_reader_len(&lr), u32(3))

	sr0, _ := capnp.list_reader_get_struct(&lr, 0)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr0, 0), u32(100))

	sr1, _ := capnp.list_reader_get_struct(&lr, 1)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr1, 0), u32(200))

	sr2, _ := capnp.list_reader_get_struct(&lr, 2)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr2, 0), u32(300))
}

// ============================================================================
// Text and Data Reading Tests
// ============================================================================

@(test)
test_reader_text :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 2)
	_ = capnp.struct_builder_set_text(&root, 0, "Hello, World!")
	_ = capnp.struct_builder_set_text(&root, 1, "")

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	text1, err1 := capnp.struct_reader_get_text(&sr, 0)
	testing.expect_value(t, err1, capnp.Error.None)
	testing.expect_value(t, text1, "Hello, World!")

	text2, err2 := capnp.struct_reader_get_text(&sr, 1)
	testing.expect_value(t, err2, capnp.Error.None)
	testing.expect_value(t, text2, "")
}

@(test)
test_reader_data :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	blob := []byte{0x00, 0xFF, 0x42, 0x13, 0x37}
	_ = capnp.struct_builder_set_data(&root, 0, blob)

	serialized, _ := capnp.serialize(&mb)
	defer delete(serialized)

	reader, _ := capnp.deserialize(serialized)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	read_data, err := capnp.struct_reader_get_data(&sr, 0)
	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, len(read_data), len(blob))

	for i in 0 ..< len(blob) {
		testing.expect_value(t, read_data[i], blob[i])
	}
}

// ============================================================================
// has_pointer Tests
// ============================================================================

@(test)
test_reader_has_pointer :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 3)

	// Set only pointer 0 and 2
	_ = capnp.struct_builder_set_text(&root, 0, "test")
	// Leave pointer 1 null
	_ = capnp.struct_builder_set_text(&root, 2, "another")

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	testing.expect(t, capnp.struct_reader_has_pointer(&sr, 0), "Pointer 0 should exist")
	testing.expect(t, !capnp.struct_reader_has_pointer(&sr, 1), "Pointer 1 should be null")
	testing.expect(t, capnp.struct_reader_has_pointer(&sr, 2), "Pointer 2 should exist")

	// Out of bounds
	testing.expect(t, !capnp.struct_reader_has_pointer(&sr, 10), "Out of bounds should return false")
}

// ============================================================================
// Default Value XOR Tests
// ============================================================================

@(test)
test_reader_default_xor :: proc(t: ^testing.T) {
	// Cap'n Proto XORs stored values with defaults on read
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 0)
	// Store 0x42 which when XOR'd with default 0x42 should give 0
	capnp.struct_builder_set_u8(&root, 0, 0x42)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	// Read with default 0x42: stored ^ default = 0x42 ^ 0x42 = 0
	testing.expect_value(t, capnp.struct_reader_get_u8(&sr, 0, 0x42), u8(0))

	// Read with default 0: stored ^ default = 0x42 ^ 0 = 0x42
	testing.expect_value(t, capnp.struct_reader_get_u8(&sr, 0, 0), u8(0x42))
}

// ============================================================================
// Message Reader Memory Tests
// ============================================================================

@(test)
test_reader_tracking_allocator :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)

	alloc := mem.tracking_allocator(&tracking)

	// Build message with default allocator
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 2, 1)
	capnp.struct_builder_set_u64(&root, 0, 0x12345678)
	_ = capnp.struct_builder_set_text(&root, 0, "test")

	serialized, _ := capnp.serialize(&mb)
	defer delete(serialized)

	// Read with tracking allocator
	{
		reader, _ := capnp.deserialize(serialized, capnp.Read_Limits{}, alloc)
		defer capnp.message_reader_destroy(&reader)

		sr, _ := capnp.message_reader_get_root(&reader)
		_ = capnp.struct_reader_get_u64(&sr, 0)
	}

	testing.expect_value(t, len(tracking.allocation_map), 0)
	testing.expect_value(t, len(tracking.bad_free_array), 0)
}
