package capnp_tests

import capnp ".."
import "core:mem"
import "core:testing"

// ============================================================================
// Message Builder Initialization Tests
// ============================================================================

@(test)
test_message_builder_init :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	_, err := capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, capnp.message_builder_total_words(&mb), u32(0))
}

@(test)
test_message_builder_make :: proc(t: ^testing.T) {
	mb, err := capnp.message_builder_make()
	defer capnp.message_builder_destroy(&mb)

	testing.expect_value(t, err, capnp.Error.None)
}

@(test)
test_message_builder_clear :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	// Build something
	_, _ = capnp.message_builder_init_root(&mb, 2, 0)
	initial_words := capnp.message_builder_total_words(&mb)
	testing.expect(t, initial_words > 0, "Should have words")

	// Clear
	capnp.message_builder_clear(&mb)
	testing.expect_value(t, capnp.message_builder_total_words(&mb), u32(0))
}

@(test)
test_message_builder_tracking_allocator :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)

	alloc := mem.tracking_allocator(&tracking)

	{
		mb: capnp.Message_Builder
		capnp.message_builder_init(&mb, alloc)
		defer capnp.message_builder_destroy(&mb)

		root, _ := capnp.message_builder_init_root(&mb, 2, 1)
		capnp.struct_builder_set_u64(&root, 0, 0x12345678)
		_ = capnp.struct_builder_set_text(&root, 0, "test")
	}

	testing.expect_value(t, len(tracking.allocation_map), 0)
	testing.expect_value(t, len(tracking.bad_free_array), 0)
}

// ============================================================================
// Primitive Type Tests
// ============================================================================

@(test)
test_builder_set_u8 :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 0)
	capnp.struct_builder_set_u8(&root, 0, 0x42)
	capnp.struct_builder_set_u8(&root, 1, 0xFF)
	capnp.struct_builder_set_u8(&root, 7, 0xAB)

	// Serialize and read back
	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, capnp.struct_reader_get_u8(&sr, 0), u8(0x42))
	testing.expect_value(t, capnp.struct_reader_get_u8(&sr, 1), u8(0xFF))
	testing.expect_value(t, capnp.struct_reader_get_u8(&sr, 7), u8(0xAB))
}

@(test)
test_builder_set_u16 :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 0)
	capnp.struct_builder_set_u16(&root, 0, 0x1234)
	capnp.struct_builder_set_u16(&root, 2, 0xABCD)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, capnp.struct_reader_get_u16(&sr, 0), u16(0x1234))
	testing.expect_value(t, capnp.struct_reader_get_u16(&sr, 2), u16(0xABCD))
}

@(test)
test_builder_set_u32 :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 0)
	capnp.struct_builder_set_u32(&root, 0, 0x12345678)
	capnp.struct_builder_set_u32(&root, 4, 0xDEADBEEF)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr, 0), u32(0x12345678))
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr, 4), u32(0xDEADBEEF))
}

@(test)
test_builder_set_u64 :: proc(t: ^testing.T) {
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
}

@(test)
test_builder_set_signed_integers :: proc(t: ^testing.T) {
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
	testing.expect_value(t, capnp.struct_reader_get_i8(&sr, 0), i8(-42))
	testing.expect_value(t, capnp.struct_reader_get_i16(&sr, 2), i16(-1234))
	testing.expect_value(t, capnp.struct_reader_get_i32(&sr, 4), i32(-100000))
	testing.expect_value(t, capnp.struct_reader_get_i64(&sr, 8), i64(-9876543210))
}

@(test)
test_builder_set_floats :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 2, 0)
	capnp.struct_builder_set_f32(&root, 0, 3.14159)
	capnp.struct_builder_set_f64(&root, 8, 2.71828182845904523536)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	f32_val := capnp.struct_reader_get_f32(&sr, 0)
	f64_val := capnp.struct_reader_get_f64(&sr, 8)

	testing.expect(t, abs(f32_val - 3.14159) < 0.0001, "f32 should match")
	testing.expect(t, abs(f64_val - 2.71828182845904523536) < 0.0000000001, "f64 should match")
}

@(test)
test_builder_set_bool :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 0)
	capnp.struct_builder_set_bool(&root, 0, true)
	capnp.struct_builder_set_bool(&root, 1, false)
	capnp.struct_builder_set_bool(&root, 7, true)
	capnp.struct_builder_set_bool(&root, 8, true)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 0), true)
	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 1), false)
	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 7), true)
	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 8), true)
}

// ============================================================================
// Nested Struct Tests
// ============================================================================

@(test)
test_builder_nested_struct :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 1)
	capnp.struct_builder_set_u32(&root, 0, 100)

	nested, nested_err := capnp.struct_builder_init_struct(&root, 0, 2, 0)
	testing.expect_value(t, nested_err, capnp.Error.None)
	capnp.struct_builder_set_u64(&nested, 0, 0xDEADBEEF)
	capnp.struct_builder_set_u32(&nested, 8, 42)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr, 0), u32(100))

	nested_sr, _ := capnp.struct_reader_get_struct(&sr, 0)
	testing.expect_value(t, capnp.struct_reader_get_u64(&nested_sr, 0), u64(0xDEADBEEF))
	testing.expect_value(t, capnp.struct_reader_get_u32(&nested_sr, 8), u32(42))
}

@(test)
test_builder_deeply_nested_structs :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	// Build 5 levels of nesting
	root, _ := capnp.message_builder_init_root(&mb, 1, 1)
	capnp.struct_builder_set_u32(&root, 0, 0)

	level1, _ := capnp.struct_builder_init_struct(&root, 0, 1, 1)
	capnp.struct_builder_set_u32(&level1, 0, 1)

	level2, _ := capnp.struct_builder_init_struct(&level1, 0, 1, 1)
	capnp.struct_builder_set_u32(&level2, 0, 2)

	level3, _ := capnp.struct_builder_init_struct(&level2, 0, 1, 1)
	capnp.struct_builder_set_u32(&level3, 0, 3)

	level4, _ := capnp.struct_builder_init_struct(&level3, 0, 1, 0)
	capnp.struct_builder_set_u32(&level4, 0, 4)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr, 0), u32(0))

	s1, _ := capnp.struct_reader_get_struct(&sr, 0)
	testing.expect_value(t, capnp.struct_reader_get_u32(&s1, 0), u32(1))

	s2, _ := capnp.struct_reader_get_struct(&s1, 0)
	testing.expect_value(t, capnp.struct_reader_get_u32(&s2, 0), u32(2))

	s3, _ := capnp.struct_reader_get_struct(&s2, 0)
	testing.expect_value(t, capnp.struct_reader_get_u32(&s3, 0), u32(3))

	s4, _ := capnp.struct_reader_get_struct(&s3, 0)
	testing.expect_value(t, capnp.struct_reader_get_u32(&s4, 0), u32(4))
}

// ============================================================================
// List Tests (All Element Sizes)
// ============================================================================

@(test)
test_builder_list_void :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	list, list_err := capnp.struct_builder_init_list(&root, 0, .Void, 10)
	testing.expect_value(t, list_err, capnp.Error.None)
	_ = list

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	lr, _ := capnp.struct_reader_get_list(&sr, 0, .Void)
	testing.expect_value(t, capnp.list_reader_len(&lr), u32(10))
}

@(test)
test_builder_list_bit :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	list, _ := capnp.struct_builder_init_list(&root, 0, .Bit, 16)

	capnp.list_builder_set_bool(&list, 0, true)
	capnp.list_builder_set_bool(&list, 1, false)
	capnp.list_builder_set_bool(&list, 7, true)
	capnp.list_builder_set_bool(&list, 15, true)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	lr, _ := capnp.struct_reader_get_list(&sr, 0, .Bit)

	testing.expect_value(t, capnp.list_reader_len(&lr), u32(16))
	testing.expect_value(t, capnp.list_reader_get_bool(&lr, 0), true)
	testing.expect_value(t, capnp.list_reader_get_bool(&lr, 1), false)
	testing.expect_value(t, capnp.list_reader_get_bool(&lr, 7), true)
	testing.expect_value(t, capnp.list_reader_get_bool(&lr, 15), true)
}

@(test)
test_builder_list_byte :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	list, _ := capnp.struct_builder_init_list(&root, 0, .Byte, 5)

	capnp.list_builder_set_u8(&list, 0, 10)
	capnp.list_builder_set_u8(&list, 1, 20)
	capnp.list_builder_set_u8(&list, 4, 50)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	lr, _ := capnp.struct_reader_get_list(&sr, 0, .Byte)

	testing.expect_value(t, capnp.list_reader_len(&lr), u32(5))
	testing.expect_value(t, capnp.list_reader_get_u8(&lr, 0), u8(10))
	testing.expect_value(t, capnp.list_reader_get_u8(&lr, 1), u8(20))
	testing.expect_value(t, capnp.list_reader_get_u8(&lr, 4), u8(50))
}

@(test)
test_builder_list_two_bytes :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	list, _ := capnp.struct_builder_init_list(&root, 0, .Two_Bytes, 3)

	capnp.list_builder_set_u16(&list, 0, 1000)
	capnp.list_builder_set_u16(&list, 1, 2000)
	capnp.list_builder_set_u16(&list, 2, 3000)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	lr, _ := capnp.struct_reader_get_list(&sr, 0, .Two_Bytes)

	testing.expect_value(t, capnp.list_reader_len(&lr), u32(3))
	testing.expect_value(t, capnp.list_reader_get_u16(&lr, 0), u16(1000))
	testing.expect_value(t, capnp.list_reader_get_u16(&lr, 1), u16(2000))
	testing.expect_value(t, capnp.list_reader_get_u16(&lr, 2), u16(3000))
}

@(test)
test_builder_list_four_bytes :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	list, _ := capnp.struct_builder_init_list(&root, 0, .Four_Bytes, 3)

	capnp.list_builder_set_u32(&list, 0, 100000)
	capnp.list_builder_set_u32(&list, 1, 200000)
	capnp.list_builder_set_u32(&list, 2, 300000)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	lr, _ := capnp.struct_reader_get_list(&sr, 0, .Four_Bytes)

	testing.expect_value(t, capnp.list_reader_len(&lr), u32(3))
	testing.expect_value(t, capnp.list_reader_get_u32(&lr, 0), u32(100000))
	testing.expect_value(t, capnp.list_reader_get_u32(&lr, 1), u32(200000))
	testing.expect_value(t, capnp.list_reader_get_u32(&lr, 2), u32(300000))
}

@(test)
test_builder_list_eight_bytes :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	list, _ := capnp.struct_builder_init_list(&root, 0, .Eight_Bytes, 2)

	capnp.list_builder_set_u64(&list, 0, 0x123456789ABCDEF0)
	capnp.list_builder_set_u64(&list, 1, 0xFEDCBA9876543210)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	lr, _ := capnp.struct_reader_get_list(&sr, 0, .Eight_Bytes)

	testing.expect_value(t, capnp.list_reader_len(&lr), u32(2))
	testing.expect_value(t, capnp.list_reader_get_u64(&lr, 0), u64(0x123456789ABCDEF0))
	testing.expect_value(t, capnp.list_reader_get_u64(&lr, 1), u64(0xFEDCBA9876543210))
}

@(test)
test_builder_list_pointer :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	list, _ := capnp.struct_builder_init_list(&root, 0, .Pointer, 2)

	// Set pointer values directly (for testing)
	capnp.list_builder_set_pointer(&list, 0, 0x12345678)
	capnp.list_builder_set_pointer(&list, 1, 0x87654321)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	// Verify list was created
	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	lr, _ := capnp.struct_reader_get_list(&sr, 0, .Pointer)
	testing.expect_value(t, capnp.list_reader_len(&lr), u32(2))
}

// ============================================================================
// Composite (Struct) List Tests
// ============================================================================

@(test)
test_builder_struct_list :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	list, list_err := capnp.struct_builder_init_struct_list(&root, 0, 3, 1, 0)
	testing.expect_value(t, list_err, capnp.Error.None)

	// Set data in each struct
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
	lr, _ := capnp.struct_reader_get_list(&sr, 0, .Composite)

	testing.expect_value(t, capnp.list_reader_len(&lr), u32(3))

	sr0, _ := capnp.list_reader_get_struct(&lr, 0)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr0, 0), u32(100))

	sr1, _ := capnp.list_reader_get_struct(&lr, 1)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr1, 0), u32(200))

	sr2, _ := capnp.list_reader_get_struct(&lr, 2)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr2, 0), u32(300))
}

// ============================================================================
// Text and Data Blob Tests
// ============================================================================

@(test)
test_builder_text_nul_terminated :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	text_err := capnp.struct_builder_set_text(&root, 0, "Hello, Cap'n Proto!")
	testing.expect_value(t, text_err, capnp.Error.None)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	text, text_read_err := capnp.struct_reader_get_text(&sr, 0)
	testing.expect_value(t, text_read_err, capnp.Error.None)
	testing.expect_value(t, text, "Hello, Cap'n Proto!")
}

@(test)
test_builder_text_empty :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	text_err := capnp.struct_builder_set_text(&root, 0, "")
	testing.expect_value(t, text_err, capnp.Error.None)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	text, text_read_err := capnp.struct_reader_get_text(&sr, 0)
	testing.expect_value(t, text_read_err, capnp.Error.None)
	testing.expect_value(t, text, "")
}

@(test)
test_builder_data_blob :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	blob := []byte{0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD}
	data_err := capnp.struct_builder_set_data(&root, 0, blob)
	testing.expect_value(t, data_err, capnp.Error.None)

	serialized, _ := capnp.serialize(&mb)
	defer delete(serialized)

	reader, _ := capnp.deserialize(serialized)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	read_data, data_read_err := capnp.struct_reader_get_data(&sr, 0)
	testing.expect_value(t, data_read_err, capnp.Error.None)
	testing.expect_value(t, len(read_data), len(blob))

	for i in 0 ..< len(blob) {
		testing.expect_value(t, read_data[i], blob[i])
	}
}

@(test)
test_builder_data_empty :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 1)
	empty_blob: []byte
	data_err := capnp.struct_builder_set_data(&root, 0, empty_blob)
	testing.expect_value(t, data_err, capnp.Error.None)

	serialized, _ := capnp.serialize(&mb)
	defer delete(serialized)

	reader, _ := capnp.deserialize(serialized)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)
	read_data, _ := capnp.struct_reader_get_data(&sr, 0)
	testing.expect(t, len(read_data) == 0, "Data should be empty")
}

// ============================================================================
// Pointer Initialization Tests
// ============================================================================

@(test)
test_builder_pointer_index_out_of_bounds :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 1, 2) // Only 2 pointers

	// Try to set text at invalid pointer index
	err := capnp.struct_builder_set_text(&root, 5, "test")
	testing.expect_value(t, err, capnp.Error.Pointer_Out_Of_Bounds)
}

@(test)
test_builder_zero_sized_struct :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	// Zero-sized struct (0 data, 0 pointers)
	root, err := capnp.message_builder_init_root(&mb, 0, 0)
	testing.expect_value(t, err, capnp.Error.None)
	_ = root

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, root_err := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, root_err, capnp.Error.None)
	_ = sr
}
