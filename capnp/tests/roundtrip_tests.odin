package capnp_tests

import capnp ".."
import "core:mem"
import "core:testing"

// ============================================================================
// Simple Struct Roundtrip Tests
// ============================================================================

@(test)
test_roundtrip_simple_struct :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	// Build: struct with various primitive types
	root, _ := capnp.message_builder_init_root(&mb, 4, 0)
	capnp.struct_builder_set_u8(&root, 0, 0x42)
	capnp.struct_builder_set_u16(&root, 2, 0x1234)
	capnp.struct_builder_set_u32(&root, 4, 0xDEADBEEF)
	capnp.struct_builder_set_u64(&root, 8, 0x123456789ABCDEF0)
	capnp.struct_builder_set_i8(&root, 16, -42)
	capnp.struct_builder_set_i16(&root, 18, -1234)
	capnp.struct_builder_set_i32(&root, 20, -100000)
	capnp.struct_builder_set_bool(&root, 192, true)
	capnp.struct_builder_set_bool(&root, 193, false)
	capnp.struct_builder_set_bool(&root, 200, true)

	// Serialize
	data, ser_err := capnp.serialize(&mb)
	testing.expect_value(t, ser_err, capnp.Error.None)
	defer delete(data)

	// Deserialize
	reader, deser_err := capnp.deserialize(data)
	testing.expect_value(t, deser_err, capnp.Error.None)
	defer capnp.message_reader_destroy(&reader)

	// Read and verify
	sr, root_err := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, root_err, capnp.Error.None)

	testing.expect_value(t, capnp.struct_reader_get_u8(&sr, 0), u8(0x42))
	testing.expect_value(t, capnp.struct_reader_get_u16(&sr, 2), u16(0x1234))
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr, 4), u32(0xDEADBEEF))
	testing.expect_value(t, capnp.struct_reader_get_u64(&sr, 8), u64(0x123456789ABCDEF0))
	testing.expect_value(t, capnp.struct_reader_get_i8(&sr, 16), i8(-42))
	testing.expect_value(t, capnp.struct_reader_get_i16(&sr, 18), i16(-1234))
	testing.expect_value(t, capnp.struct_reader_get_i32(&sr, 20), i32(-100000))
	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 192), true)
	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 193), false)
	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 200), true)
}

@(test)
test_roundtrip_floats :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 2, 0)
	capnp.struct_builder_set_f32(&root, 0, 3.14159265)
	capnp.struct_builder_set_f64(&root, 8, 2.718281828459045)

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	f32_val := capnp.struct_reader_get_f32(&sr, 0)
	f64_val := capnp.struct_reader_get_f64(&sr, 8)

	testing.expect(t, abs(f32_val - 3.14159265) < 0.000001, "f32 should match")
	testing.expect(t, abs(f64_val - 2.718281828459045) < 0.0000000001, "f64 should match")
}

// ============================================================================
// Complex Nested Struct Roundtrip Tests
// ============================================================================

@(test)
test_roundtrip_nested_struct :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	// Build complex nested structure
	root, _ := capnp.message_builder_init_root(&mb, 1, 2)
	capnp.struct_builder_set_u32(&root, 0, 100)

	child1, _ := capnp.struct_builder_init_struct(&root, 0, 1, 1)
	capnp.struct_builder_set_u64(&child1, 0, 0xAAAAAAAA)

	grandchild, _ := capnp.struct_builder_init_struct(&child1, 0, 1, 0)
	capnp.struct_builder_set_u32(&grandchild, 0, 42)

	child2, _ := capnp.struct_builder_init_struct(&root, 1, 2, 0)
	capnp.struct_builder_set_u64(&child2, 0, 0xBBBBBBBB)
	capnp.struct_builder_set_u64(&child2, 8, 0xCCCCCCCC)

	// Serialize
	data, _ := capnp.serialize(&mb)
	defer delete(data)

	// Deserialize
	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	// Verify structure
	sr, _ := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr, 0), u32(100))

	sr_child1, _ := capnp.struct_reader_get_struct(&sr, 0)
	testing.expect_value(t, capnp.struct_reader_get_u64(&sr_child1, 0), u64(0xAAAAAAAA))

	sr_grandchild, _ := capnp.struct_reader_get_struct(&sr_child1, 0)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr_grandchild, 0), u32(42))

	sr_child2, _ := capnp.struct_reader_get_struct(&sr, 1)
	testing.expect_value(t, capnp.struct_reader_get_u64(&sr_child2, 0), u64(0xBBBBBBBB))
	testing.expect_value(t, capnp.struct_reader_get_u64(&sr_child2, 8), u64(0xCCCCCCCC))
}

@(test)
test_roundtrip_person_address_book :: proc(t: ^testing.T) {
	// Simulate "Address Book" schema:
	// AddressBook { count: u32, people: List(Person) }
	// Person { id: u64, age: u16, name: Text }

	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	// Build AddressBook: 1 data word, 1 pointer
	address_book, _ := capnp.message_builder_init_root(&mb, 1, 1)
	capnp.struct_builder_set_u32(&address_book, 0, 3) // count = 3

	// Build people list (composite list of structs)
	// Person: 2 data words (id@0, age@8), 1 pointer (name@0)
	people, _ := capnp.struct_builder_init_struct_list(&address_book, 0, 3, 2, 1)

	// Person 0
	p0, _ := capnp.list_builder_get_struct(&people, 0)
	capnp.struct_builder_set_u64(&p0, 0, 1001) // id
	capnp.struct_builder_set_u16(&p0, 8, 25)   // age
	_ = capnp.struct_builder_set_text(&p0, 0, "Alice")

	// Person 1
	p1, _ := capnp.list_builder_get_struct(&people, 1)
	capnp.struct_builder_set_u64(&p1, 0, 1002) // id
	capnp.struct_builder_set_u16(&p1, 8, 30)   // age
	_ = capnp.struct_builder_set_text(&p1, 0, "Bob")

	// Person 2
	p2, _ := capnp.list_builder_get_struct(&people, 2)
	capnp.struct_builder_set_u64(&p2, 0, 1003) // id
	capnp.struct_builder_set_u16(&p2, 8, 35)   // age
	_ = capnp.struct_builder_set_text(&p2, 0, "Charlie")

	// Serialize
	data, _ := capnp.serialize(&mb)
	defer delete(data)

	// Deserialize
	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	// Verify
	sr, _ := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr, 0), u32(3))

	lr, _ := capnp.struct_reader_get_list(&sr, 0, .Composite)
	testing.expect_value(t, capnp.list_reader_len(&lr), u32(3))

	// Person 0
	sr0, _ := capnp.list_reader_get_struct(&lr, 0)
	testing.expect_value(t, capnp.struct_reader_get_u64(&sr0, 0), u64(1001))
	testing.expect_value(t, capnp.struct_reader_get_u16(&sr0, 8), u16(25))
	name0, _ := capnp.struct_reader_get_text(&sr0, 0)
	testing.expect_value(t, name0, "Alice")

	// Person 1
	sr1, _ := capnp.list_reader_get_struct(&lr, 1)
	testing.expect_value(t, capnp.struct_reader_get_u64(&sr1, 0), u64(1002))
	testing.expect_value(t, capnp.struct_reader_get_u16(&sr1, 8), u16(30))
	name1, _ := capnp.struct_reader_get_text(&sr1, 0)
	testing.expect_value(t, name1, "Bob")

	// Person 2
	sr2, _ := capnp.list_reader_get_struct(&lr, 2)
	testing.expect_value(t, capnp.struct_reader_get_u64(&sr2, 0), u64(1003))
	testing.expect_value(t, capnp.struct_reader_get_u16(&sr2, 8), u16(35))
	name2, _ := capnp.struct_reader_get_text(&sr2, 0)
	testing.expect_value(t, name2, "Charlie")
}

// ============================================================================
// All List Types Roundtrip Tests
// ============================================================================

@(test)
test_roundtrip_all_list_types :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 6)

	// Void list
	_, _ = capnp.struct_builder_init_list(&root, 0, .Void, 5)

	// Bit list
	bit_list, _ := capnp.struct_builder_init_list(&root, 1, .Bit, 16)
	for i in u32(0) ..< 16 {
		capnp.list_builder_set_bool(&bit_list, i, i % 2 == 0)
	}

	// Byte list
	byte_list, _ := capnp.struct_builder_init_list(&root, 2, .Byte, 8)
	for i in u32(0) ..< 8 {
		capnp.list_builder_set_u8(&byte_list, i, u8(i * 10))
	}

	// u32 list
	u32_list, _ := capnp.struct_builder_init_list(&root, 3, .Four_Bytes, 4)
	capnp.list_builder_set_u32(&u32_list, 0, 1000)
	capnp.list_builder_set_u32(&u32_list, 1, 2000)
	capnp.list_builder_set_u32(&u32_list, 2, 3000)
	capnp.list_builder_set_u32(&u32_list, 3, 4000)

	// u64 list
	u64_list, _ := capnp.struct_builder_init_list(&root, 4, .Eight_Bytes, 3)
	capnp.list_builder_set_u64(&u64_list, 0, 0x1111111111111111)
	capnp.list_builder_set_u64(&u64_list, 1, 0x2222222222222222)
	capnp.list_builder_set_u64(&u64_list, 2, 0x3333333333333333)

	// Composite list
	struct_list, _ := capnp.struct_builder_init_struct_list(&root, 5, 2, 1, 0)
	s0, _ := capnp.list_builder_get_struct(&struct_list, 0)
	capnp.struct_builder_set_u32(&s0, 0, 111)
	s1, _ := capnp.list_builder_get_struct(&struct_list, 1)
	capnp.struct_builder_set_u32(&s1, 0, 222)

	// Serialize
	data, _ := capnp.serialize(&mb)
	defer delete(data)

	// Deserialize and verify
	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	// Void list
	lr_void, _ := capnp.struct_reader_get_list(&sr, 0, .Void)
	testing.expect_value(t, capnp.list_reader_len(&lr_void), u32(5))

	// Bit list
	lr_bit, _ := capnp.struct_reader_get_list(&sr, 1, .Bit)
	testing.expect_value(t, capnp.list_reader_len(&lr_bit), u32(16))
	for i in u32(0) ..< 16 {
		expected := i % 2 == 0
		testing.expect_value(t, capnp.list_reader_get_bool(&lr_bit, i), expected)
	}

	// Byte list
	lr_byte, _ := capnp.struct_reader_get_list(&sr, 2, .Byte)
	testing.expect_value(t, capnp.list_reader_len(&lr_byte), u32(8))
	for i in u32(0) ..< 8 {
		testing.expect_value(t, capnp.list_reader_get_u8(&lr_byte, i), u8(i * 10))
	}

	// u32 list
	lr_u32, _ := capnp.struct_reader_get_list(&sr, 3, .Four_Bytes)
	testing.expect_value(t, capnp.list_reader_len(&lr_u32), u32(4))
	testing.expect_value(t, capnp.list_reader_get_u32(&lr_u32, 0), u32(1000))
	testing.expect_value(t, capnp.list_reader_get_u32(&lr_u32, 1), u32(2000))
	testing.expect_value(t, capnp.list_reader_get_u32(&lr_u32, 2), u32(3000))
	testing.expect_value(t, capnp.list_reader_get_u32(&lr_u32, 3), u32(4000))

	// u64 list
	lr_u64, _ := capnp.struct_reader_get_list(&sr, 4, .Eight_Bytes)
	testing.expect_value(t, capnp.list_reader_len(&lr_u64), u32(3))
	testing.expect_value(t, capnp.list_reader_get_u64(&lr_u64, 0), u64(0x1111111111111111))
	testing.expect_value(t, capnp.list_reader_get_u64(&lr_u64, 1), u64(0x2222222222222222))
	testing.expect_value(t, capnp.list_reader_get_u64(&lr_u64, 2), u64(0x3333333333333333))

	// Composite list
	lr_struct, _ := capnp.struct_reader_get_list(&sr, 5, .Composite)
	testing.expect_value(t, capnp.list_reader_len(&lr_struct), u32(2))

	sr0, _ := capnp.list_reader_get_struct(&lr_struct, 0)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr0, 0), u32(111))

	sr1, _ := capnp.list_reader_get_struct(&lr_struct, 1)
	testing.expect_value(t, capnp.struct_reader_get_u32(&sr1, 0), u32(222))
}

// ============================================================================
// Text and Data Roundtrip Tests
// ============================================================================

@(test)
test_roundtrip_text_and_data :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 0, 4)

	_ = capnp.struct_builder_set_text(&root, 0, "Hello, World!")
	_ = capnp.struct_builder_set_text(&root, 1, "") // Empty text
	_ = capnp.struct_builder_set_data(&root, 2, []byte{0x00, 0xFF, 0x42, 0x13, 0x37})
	_ = capnp.struct_builder_set_data(&root, 3, []byte{}) // Empty data

	data, _ := capnp.serialize(&mb)
	defer delete(data)

	reader, _ := capnp.deserialize(data)
	defer capnp.message_reader_destroy(&reader)

	sr, _ := capnp.message_reader_get_root(&reader)

	text1, _ := capnp.struct_reader_get_text(&sr, 0)
	testing.expect_value(t, text1, "Hello, World!")

	text2, _ := capnp.struct_reader_get_text(&sr, 1)
	testing.expect_value(t, text2, "")

	data_blob, _ := capnp.struct_reader_get_data(&sr, 2)
	testing.expect_value(t, len(data_blob), 5)
	testing.expect_value(t, data_blob[0], u8(0x00))
	testing.expect_value(t, data_blob[1], u8(0xFF))
	testing.expect_value(t, data_blob[4], u8(0x37))

	empty_data, _ := capnp.struct_reader_get_data(&sr, 3)
	testing.expect(t, len(empty_data) == 0, "Empty data should have length 0")
}

// ============================================================================
// Packed Serialization Roundtrip Tests
// ============================================================================

@(test)
test_roundtrip_packed_simple :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 2, 0)
	capnp.struct_builder_set_u64(&root, 0, 0x12345678)
	capnp.struct_builder_set_u64(&root, 8, 0) // Lots of zeros = good for packing

	// Serialize packed
	packed, pack_err := capnp.serialize_packed(&mb)
	testing.expect_value(t, pack_err, capnp.Error.None)
	defer delete(packed)

	// Deserialize packed
	reader, unpacked_data, unpack_err := capnp.deserialize_packed(packed)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	defer capnp.message_reader_destroy(&reader)
	defer delete(unpacked_data)

	// Verify
	sr, _ := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, capnp.struct_reader_get_u64(&sr, 0), u64(0x12345678))
	testing.expect_value(t, capnp.struct_reader_get_u64(&sr, 8), u64(0))
}

@(test)
test_roundtrip_packed_complex :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	root, _ := capnp.message_builder_init_root(&mb, 2, 2)
	capnp.struct_builder_set_u64(&root, 0, 0xDEADBEEF)
	capnp.struct_builder_set_bool(&root, 64, true)

	nested, _ := capnp.struct_builder_init_struct(&root, 0, 1, 0)
	capnp.struct_builder_set_u32(&nested, 0, 42)

	list, _ := capnp.struct_builder_init_list(&root, 1, .Four_Bytes, 3)
	capnp.list_builder_set_u32(&list, 0, 100)
	capnp.list_builder_set_u32(&list, 1, 200)
	capnp.list_builder_set_u32(&list, 2, 300)

	// Serialize packed
	packed, _ := capnp.serialize_packed(&mb)
	defer delete(packed)

	// Deserialize packed
	reader, unpacked_data, _ := capnp.deserialize_packed(packed)
	defer capnp.message_reader_destroy(&reader)
	defer delete(unpacked_data)

	// Verify all data
	sr, _ := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, capnp.struct_reader_get_u64(&sr, 0), u64(0xDEADBEEF))
	testing.expect_value(t, capnp.struct_reader_get_bool(&sr, 64), true)

	nested_sr, _ := capnp.struct_reader_get_struct(&sr, 0)
	testing.expect_value(t, capnp.struct_reader_get_u32(&nested_sr, 0), u32(42))

	lr, _ := capnp.struct_reader_get_list(&sr, 1, .Four_Bytes)
	testing.expect_value(t, capnp.list_reader_len(&lr), u32(3))
	testing.expect_value(t, capnp.list_reader_get_u32(&lr, 0), u32(100))
	testing.expect_value(t, capnp.list_reader_get_u32(&lr, 1), u32(200))
	testing.expect_value(t, capnp.list_reader_get_u32(&lr, 2), u32(300))
}

@(test)
test_roundtrip_packed_size_reduction :: proc(t: ^testing.T) {
	mb: capnp.Message_Builder
	capnp.message_builder_init(&mb)
	defer capnp.message_builder_destroy(&mb)

	// Create message with lots of zeros (typical Cap'n Proto pattern)
	root, _ := capnp.message_builder_init_root(&mb, 8, 0) // 8 words of data, mostly zeros
	capnp.struct_builder_set_u32(&root, 0, 100)
	capnp.struct_builder_set_u32(&root, 16, 200)

	// Serialize unpacked
	unpacked, _ := capnp.serialize(&mb)
	defer delete(unpacked)

	// Serialize packed
	packed, _ := capnp.serialize_packed(&mb)
	defer delete(packed)

	// Packed should be smaller
	testing.expect(t, len(packed) < len(unpacked), "Packed should be smaller than unpacked")
}

// ============================================================================
// Memory Leak Tests
// ============================================================================

@(test)
test_roundtrip_no_leaks :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)

	alloc := mem.tracking_allocator(&tracking)

	{
		mb: capnp.Message_Builder
		capnp.message_builder_init(&mb, alloc)
		defer capnp.message_builder_destroy(&mb)

		root, _ := capnp.message_builder_init_root(&mb, 2, 2)
		capnp.struct_builder_set_u64(&root, 0, 0x12345678)
		_ = capnp.struct_builder_set_text(&root, 0, "test")

		nested, _ := capnp.struct_builder_init_struct(&root, 1, 1, 0)
		capnp.struct_builder_set_u32(&nested, 0, 42)

		data, _ := capnp.serialize(&mb, alloc)
		defer delete(data, alloc)

		reader, _ := capnp.deserialize(data, capnp.Read_Limits{}, alloc)
		defer capnp.message_reader_destroy(&reader)

		sr, _ := capnp.message_reader_get_root(&reader)
		_ = capnp.struct_reader_get_u64(&sr, 0)
	}

	testing.expect_value(t, len(tracking.allocation_map), 0)
	testing.expect_value(t, len(tracking.bad_free_array), 0)
}
