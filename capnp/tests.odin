package capnp

import "core:mem"
import "core:testing"

// ============================================================================
// Pointer Encoding/Decoding Tests
// ============================================================================

@(test)
test_pointer_get_kind :: proc(t: ^testing.T) {
	// Test all four pointer kinds
	testing.expect_value(t, pointer_get_kind(0b00), Pointer_Kind.Struct)
	testing.expect_value(t, pointer_get_kind(0b01), Pointer_Kind.List)
	testing.expect_value(t, pointer_get_kind(0b10), Pointer_Kind.Far)
	testing.expect_value(t, pointer_get_kind(0b11), Pointer_Kind.Other)
	
	// Test with other bits set
	testing.expect_value(t, pointer_get_kind(0xFFFFFFFF_FFFFFFFC), Pointer_Kind.Struct)
	testing.expect_value(t, pointer_get_kind(0xFFFFFFFF_FFFFFFFD), Pointer_Kind.List)
}

@(test)
test_pointer_is_null :: proc(t: ^testing.T) {
	testing.expect(t, pointer_is_null(0), "Zero should be null")
	testing.expect(t, !pointer_is_null(1), "Non-zero should not be null")
	testing.expect(t, !pointer_is_null(0xFFFFFFFF_FFFFFFFF), "All ones should not be null")
}

@(test)
test_struct_pointer_roundtrip :: proc(t: ^testing.T) {
	// Test basic struct pointer
	encoded := struct_pointer_encode(10, 2, 3)
	parts, ok := struct_pointer_decode(encoded)
	
	testing.expect(t, ok, "Decode should succeed")
	testing.expect_value(t, parts.offset, i32(10))
	testing.expect_value(t, parts.data_size, u16(2))
	testing.expect_value(t, parts.pointer_count, u16(3))
	
	// Verify kind
	testing.expect_value(t, pointer_get_kind(encoded), Pointer_Kind.Struct)
}

@(test)
test_struct_pointer_negative_offset :: proc(t: ^testing.T) {
	// Test with negative offset
	encoded := struct_pointer_encode(-5, 1, 1)
	parts, ok := struct_pointer_decode(encoded)
	
	testing.expect(t, ok, "Decode should succeed")
	testing.expect_value(t, parts.offset, i32(-5))
}

@(test)
test_struct_pointer_target :: proc(t: ^testing.T) {
	// Pointer at word 5, offset 3 -> target is 5 + 1 + 3 = 9
	target1, ok1 := struct_pointer_target(5, 3)
	testing.expect(t, ok1, "Should succeed")
	testing.expect_value(t, target1, u32(9))
	
	// Pointer at word 10, offset -2 -> target is 10 + 1 + (-2) = 9
	target2, ok2 := struct_pointer_target(10, -2)
	testing.expect(t, ok2, "Should succeed")
	testing.expect_value(t, target2, u32(9))
	
	// Pointer at word 0, offset 0 -> target is 0 + 1 + 0 = 1
	target3, ok3 := struct_pointer_target(0, 0)
	testing.expect(t, ok3, "Should succeed")
	testing.expect_value(t, target3, u32(1))
	
	// Underflow: pointer at word 0, offset -2 -> would be negative
	_, ok4 := struct_pointer_target(0, -2)
	testing.expect(t, !ok4, "Should fail on underflow")
}

@(test)
test_list_pointer_roundtrip :: proc(t: ^testing.T) {
	// Test basic list pointer
	encoded := list_pointer_encode(5, .Four_Bytes, 100)
	parts, ok := list_pointer_decode(encoded)
	
	testing.expect(t, ok, "Decode should succeed")
	testing.expect_value(t, parts.offset, i32(5))
	testing.expect_value(t, parts.element_size, Element_Size.Four_Bytes)
	testing.expect_value(t, parts.element_count, u32(100))
	
	// Verify kind
	testing.expect_value(t, pointer_get_kind(encoded), Pointer_Kind.List)
}

@(test)
test_list_pointer_target :: proc(t: ^testing.T) {
	// Valid target
	target, ok := list_pointer_target(5, 3)
	testing.expect(t, ok, "Should succeed")
	testing.expect_value(t, target, u32(9))
	
	// Underflow
	_, ok2 := list_pointer_target(0, -5)
	testing.expect(t, !ok2, "Should fail on underflow")
}

@(test)
test_list_pointer_all_sizes :: proc(t: ^testing.T) {
	sizes := []Element_Size{
		.Void, .Bit, .Byte, .Two_Bytes, .Four_Bytes, 
		.Eight_Bytes, .Pointer, .Composite,
	}
	
	for size in sizes {
		encoded := list_pointer_encode(0, size, 10)
		parts, ok := list_pointer_decode(encoded)
		testing.expect(t, ok, "Decode should succeed")
		testing.expect_value(t, parts.element_size, size)
	}
}

@(test)
test_far_pointer_roundtrip :: proc(t: ^testing.T) {
	// Test single landing pad
	encoded := far_pointer_encode(false, 100, 5)
	parts, ok := far_pointer_decode(encoded)
	
	testing.expect(t, ok, "Decode should succeed")
	testing.expect(t, !parts.is_double, "Should be single landing pad")
	testing.expect_value(t, parts.offset, u32(100))
	testing.expect_value(t, parts.segment_id, u32(5))
	
	// Verify kind
	testing.expect_value(t, pointer_get_kind(encoded), Pointer_Kind.Far)
}

@(test)
test_far_pointer_double :: proc(t: ^testing.T) {
	// Test double landing pad
	encoded := far_pointer_encode(true, 50, 10)
	parts, ok := far_pointer_decode(encoded)
	
	testing.expect(t, ok, "Decode should succeed")
	testing.expect(t, parts.is_double, "Should be double landing pad")
	testing.expect_value(t, parts.offset, u32(50))
	testing.expect_value(t, parts.segment_id, u32(10))
}

@(test)
test_element_size_bits :: proc(t: ^testing.T) {
	testing.expect_value(t, element_size_bits(.Void), u32(0))
	testing.expect_value(t, element_size_bits(.Bit), u32(1))
	testing.expect_value(t, element_size_bits(.Byte), u32(8))
	testing.expect_value(t, element_size_bits(.Two_Bytes), u32(16))
	testing.expect_value(t, element_size_bits(.Four_Bytes), u32(32))
	testing.expect_value(t, element_size_bits(.Eight_Bytes), u32(64))
	testing.expect_value(t, element_size_bits(.Pointer), u32(64))
	testing.expect_value(t, element_size_bits(.Composite), u32(0))
}

@(test)
test_decode_wrong_kind :: proc(t: ^testing.T) {
	// Struct pointer should fail to decode as list
	struct_ptr := struct_pointer_encode(0, 1, 1)
	_, ok := list_pointer_decode(struct_ptr)
	testing.expect(t, !ok, "Should fail to decode struct as list")
	
	// List pointer should fail to decode as far
	list_ptr := list_pointer_encode(0, .Byte, 10)
	_, ok2 := far_pointer_decode(list_ptr)
	testing.expect(t, !ok2, "Should fail to decode list as far")
}

// ============================================================================
// Segment Management Tests
// ============================================================================

@(test)
test_segment_manager_init_destroy :: proc(t: ^testing.T) {
	sm: Segment_Manager
	segment_manager_init(&sm)
	defer segment_manager_destroy(&sm)
	
	testing.expect_value(t, segment_manager_segment_count(&sm), u32(0))
}

@(test)
test_segment_manager_allocate :: proc(t: ^testing.T) {
	sm: Segment_Manager
	segment_manager_init(&sm)
	defer segment_manager_destroy(&sm)
	
	// First allocation creates a segment
	seg_id, offset, err := segment_manager_allocate(&sm, 5)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, seg_id, u32(0))
	testing.expect_value(t, offset, u32(0))
	testing.expect_value(t, segment_manager_segment_count(&sm), u32(1))
	
	// Second allocation from same segment
	seg_id2, offset2, err2 := segment_manager_allocate(&sm, 3)
	testing.expect_value(t, err2, Error.None)
	testing.expect_value(t, seg_id2, u32(0))
	testing.expect_value(t, offset2, u32(5))
}

@(test)
test_segment_manager_multiple_segments :: proc(t: ^testing.T) {
	sm: Segment_Manager
	segment_manager_init(&sm, 10) // Small segments for testing
	defer segment_manager_destroy(&sm)
	
	// Fill first segment
	_, _, err1 := segment_manager_allocate(&sm, 8)
	testing.expect_value(t, err1, Error.None)
	
	// This should create a new segment
	seg_id, _, err2 := segment_manager_allocate(&sm, 8)
	testing.expect_value(t, err2, Error.None)
	testing.expect_value(t, seg_id, u32(1))
	testing.expect_value(t, segment_manager_segment_count(&sm), u32(2))
}

@(test)
test_segment_word_access :: proc(t: ^testing.T) {
	sm: Segment_Manager
	segment_manager_init(&sm)
	defer segment_manager_destroy(&sm)
	
	seg_id, offset, _ := segment_manager_allocate(&sm, 3)
	seg := segment_manager_get_segment(&sm, seg_id)
	
	// Write words
	testing.expect(t, segment_set_word(seg, offset, 0xDEADBEEF), "Set word 0 should succeed")
	testing.expect(t, segment_set_word(seg, offset + 1, 0xCAFEBABE), "Set word 1 should succeed")
	testing.expect(t, segment_set_word(seg, offset + 2, 0x12345678), "Set word 2 should succeed")
	
	// Read words back
	w0, ok0 := segment_get_word(seg, offset)
	testing.expect(t, ok0, "Get word 0 should succeed")
	testing.expect_value(t, w0, Word(0xDEADBEEF))
	
	w1, ok1 := segment_get_word(seg, offset + 1)
	testing.expect(t, ok1, "Get word 1 should succeed")
	testing.expect_value(t, w1, Word(0xCAFEBABE))
}

@(test)
test_segment_manager_with_arena :: proc(t: ^testing.T) {
	// Test using Odin's arena allocator
	// Arena buffer must be large enough for segment manager internals + segment data
	// DEFAULT_SEGMENT_SIZE is 1024 words = 8KB, plus dynamic array overhead
	arena: mem.Arena
	arena_buf: [64 * 1024]byte // 64KB is plenty for 8KB segment + overhead
	mem.arena_init(&arena, arena_buf[:])
	arena_allocator := mem.arena_allocator(&arena)
	
	sm: Segment_Manager
	segment_manager_init(&sm, DEFAULT_SEGMENT_SIZE, arena_allocator)
	defer segment_manager_destroy(&sm)
	
	// Allocate some words
	seg_id, offset, err := segment_manager_allocate(&sm, 10)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, seg_id, u32(0))
	testing.expect_value(t, offset, u32(0))
	
	// Write and read
	seg := segment_manager_get_segment(&sm, seg_id)
	segment_set_word(seg, 0, 0x1234)
	w, ok := segment_get_word(seg, 0)
	testing.expect(t, ok, "Should get word")
	testing.expect_value(t, w, Word(0x1234))
}

@(test)
test_segment_manager_clear :: proc(t: ^testing.T) {
	sm: Segment_Manager
	segment_manager_init(&sm)
	defer segment_manager_destroy(&sm)
	
	// Allocate and write some data
	segment_manager_allocate(&sm, 10)
	seg := segment_manager_get_segment(&sm, 0)
	segment_set_word(seg, 0, 0xDEADBEEF)
	
	// Clear
	segment_manager_clear(&sm)
	
	// Should still have 1 segment but used should be 0
	testing.expect_value(t, segment_manager_segment_count(&sm), u32(1))
	testing.expect_value(t, segment_manager_get_segment(&sm, 0).used, u32(0))
}

@(test)
test_segment_get_bytes :: proc(t: ^testing.T) {
	sm: Segment_Manager
	segment_manager_init(&sm)
	defer segment_manager_destroy(&sm)
	
	// Allocate 2 words
	_, _, _ = segment_manager_allocate(&sm, 2)
	seg := segment_manager_get_segment(&sm, 0)
	
	// Write known pattern: 0x0102030405060708 (little-endian)
	segment_set_word(seg, 0, 0x0807060504030201)
	segment_set_word(seg, 1, 0x100F0E0D0C0B0A09)
	
	// Get first 4 bytes
	bytes, ok := segment_get_bytes(seg, 0, 4)
	testing.expect(t, ok, "Should get bytes")
	testing.expect_value(t, bytes[0], u8(0x01))
	testing.expect_value(t, bytes[1], u8(0x02))
	testing.expect_value(t, bytes[2], u8(0x03))
	testing.expect_value(t, bytes[3], u8(0x04))
	
	// Get all 16 bytes
	all_bytes, ok2 := segment_get_bytes(seg, 0, 16)
	testing.expect(t, ok2, "Should get all bytes")
	testing.expect_value(t, len(all_bytes), 16)
	testing.expect_value(t, all_bytes[8], u8(0x09))
	
	// Out of bounds should fail
	_, ok3 := segment_get_bytes(seg, 0, 24)
	testing.expect(t, !ok3, "Should fail for out of bounds")
}

// ============================================================================
// Message Framing Tests
// ============================================================================

@(test)
test_frame_header_size :: proc(t: ^testing.T) {
	// 1 segment: 4 (count) + 4 (size) = 8 bytes (already aligned)
	testing.expect_value(t, frame_header_size(1), u32(8))
	
	// 2 segments: 4 (count) + 8 (sizes) = 12, pad to 16
	testing.expect_value(t, frame_header_size(2), u32(16))
	
	// 3 segments: 4 (count) + 12 (sizes) = 16 (already aligned)
	testing.expect_value(t, frame_header_size(3), u32(16))
	
	// 4 segments: 4 (count) + 16 (sizes) = 20, pad to 24
	testing.expect_value(t, frame_header_size(4), u32(24))
}

@(test)
test_frame_header_roundtrip :: proc(t: ^testing.T) {
	sizes := []u32{100, 50, 25}
	buffer: [32]byte
	
	// Serialize
	bytes_written, err := serialize_frame_header(sizes, buffer[:])
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, bytes_written, u32(16))
	
	// Deserialize
	header, bytes_read, err2 := deserialize_frame_header(buffer[:])
	defer frame_header_destroy(&header)
	
	testing.expect_value(t, err2, Error.None)
	testing.expect_value(t, bytes_read, u32(16))
	testing.expect_value(t, header.segment_count, u32(3))
	testing.expect_value(t, header.segment_sizes[0], u32(100))
	testing.expect_value(t, header.segment_sizes[1], u32(50))
	testing.expect_value(t, header.segment_sizes[2], u32(25))
}

@(test)
test_frame_header_single_segment :: proc(t: ^testing.T) {
	sizes := []u32{42}
	buffer: [16]byte
	
	bytes_written, err := serialize_frame_header(sizes, buffer[:])
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, bytes_written, u32(8))
	
	header, bytes_read, err2 := deserialize_frame_header(buffer[:])
	defer frame_header_destroy(&header)
	
	testing.expect_value(t, err2, Error.None)
	testing.expect_value(t, bytes_read, u32(8))
	testing.expect_value(t, header.segment_count, u32(1))
	testing.expect_value(t, header.segment_sizes[0], u32(42))
}

@(test)
test_serialize_segments_roundtrip :: proc(t: ^testing.T) {
	sm: Segment_Manager
	segment_manager_init(&sm)
	defer segment_manager_destroy(&sm)
	
	// Allocate and write some data
	_, _, _ = segment_manager_allocate(&sm, 3)
	seg := segment_manager_get_segment(&sm, 0)
	segment_set_word(seg, 0, 0x0123456789ABCDEF)
	segment_set_word(seg, 1, 0xFEDCBA9876543210)
	segment_set_word(seg, 2, 0xDEADBEEFCAFEBABE)
	
	// Serialize
	data, err := serialize_segments(&sm)
	defer delete(data)
	
	testing.expect_value(t, err, Error.None)
	testing.expect(t, len(data) > 0, "Should have data")
	
	// Deserialize
	sm2, bytes_read, err2 := deserialize_segments(data)
	defer segment_manager_destroy(&sm2)
	
	testing.expect_value(t, err2, Error.None)
	testing.expect_value(t, bytes_read, u32(len(data)))
	testing.expect_value(t, segment_manager_segment_count(&sm2), u32(1))
	
	// Verify data
	seg2 := segment_manager_get_segment(&sm2, 0)
	w0, _ := segment_get_word(seg2, 0)
	w1, _ := segment_get_word(seg2, 1)
	w2, _ := segment_get_word(seg2, 2)
	
	testing.expect_value(t, w0, Word(0x0123456789ABCDEF))
	testing.expect_value(t, w1, Word(0xFEDCBA9876543210))
	testing.expect_value(t, w2, Word(0xDEADBEEFCAFEBABE))
}

@(test)
test_deserialize_truncated :: proc(t: ^testing.T) {
	// Too short for header
	short_data := []byte{0, 0}
	_, _, err := deserialize_frame_header(short_data)
	testing.expect_value(t, err, Error.Unexpected_End_Of_Input)
}

// ============================================================================
// Pointer Union Tests
// ============================================================================

@(test)
test_pointer_union :: proc(t: ^testing.T) {
	// Test that the union properly reinterprets bits
	p: Pointer
	p.raw = struct_pointer_encode(5, 2, 3)
	
	testing.expect_value(t, p.struct_ptr.kind, Pointer_Kind.Struct)
	testing.expect_value(t, p.struct_ptr.offset, i32(5))
	testing.expect_value(t, p.struct_ptr.data_size, u16(2))
	testing.expect_value(t, p.struct_ptr.pointer_count, u16(3))
}

// ============================================================================
// Message Builder Tests
// ============================================================================

@(test)
test_message_builder_init_destroy :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Initially no segments
	testing.expect_value(t, message_builder_total_words(&mb), u32(0))
}

@(test)
test_message_builder_make :: proc(t: ^testing.T) {
	mb, err := message_builder_make()
	defer message_builder_destroy(&mb)
	
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, message_builder_total_words(&mb), u32(0))
}

@(test)
test_message_builder_init_root :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Initialize root with 2 data words and 1 pointer
	root, err := message_builder_init_root(&mb, 2, 1)
	
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, root.data_words, u16(2))
	testing.expect_value(t, root.pointer_count, u16(1))
	
	// Should have allocated: 1 root pointer + 2 data words + 1 pointer = 4 words
	testing.expect_value(t, message_builder_total_words(&mb), u32(4))
}

@(test)
test_message_builder_clear :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Initialize root
	message_builder_init_root(&mb, 2, 1)
	testing.expect(t, message_builder_total_words(&mb) > 0, "Should have words after init")
	
	// Clear
	message_builder_clear(&mb)
	testing.expect_value(t, message_builder_total_words(&mb), u32(0))
}

// ============================================================================
// Struct Builder Tests
// ============================================================================

@(test)
test_struct_builder_set_primitives :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Root with 2 data words
	root, _ := message_builder_init_root(&mb, 2, 0)
	
	// Set various primitives
	struct_builder_set_u8(&root, 0, 0x42)
	struct_builder_set_u16(&root, 2, 0x1234)
	struct_builder_set_u32(&root, 4, 0xDEADBEEF)
	struct_builder_set_u64(&root, 8, 0xCAFEBABE12345678)
	
	// Verify by reading segment bytes
	seg := segment_manager_get_segment(&mb.segments, 0)
	bytes, ok := segment_get_bytes(seg, 1, 16) // Skip root pointer at word 0
	
	testing.expect(t, ok, "Should get bytes")
	testing.expect_value(t, bytes[0], u8(0x42))
	testing.expect_value(t, bytes[2], u8(0x34))
	testing.expect_value(t, bytes[3], u8(0x12))
	testing.expect_value(t, bytes[4], u8(0xEF))
	testing.expect_value(t, bytes[5], u8(0xBE))
	testing.expect_value(t, bytes[6], u8(0xAD))
	testing.expect_value(t, bytes[7], u8(0xDE))
}

@(test)
test_struct_builder_set_bool :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 1, 0)
	
	// Set bits at various positions
	struct_builder_set_bool(&root, 0, true)
	struct_builder_set_bool(&root, 3, true)
	struct_builder_set_bool(&root, 7, true)
	
	seg := segment_manager_get_segment(&mb.segments, 0)
	bytes, _ := segment_get_bytes(seg, 1, 1)
	
	// Bits 0, 3, 7 set = 0b10001001 = 0x89
	testing.expect_value(t, bytes[0], u8(0x89))
}

@(test)
test_struct_builder_set_signed :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 2, 0)
	
	struct_builder_set_i8(&root, 0, -1)
	struct_builder_set_i16(&root, 2, -256)
	struct_builder_set_i32(&root, 4, -100000)
	struct_builder_set_i64(&root, 8, -1)
	
	seg := segment_manager_get_segment(&mb.segments, 0)
	bytes, _ := segment_get_bytes(seg, 1, 16)
	
	// -1 as i8 = 0xFF
	testing.expect_value(t, bytes[0], u8(0xFF))
	// -256 as i16 little-endian = 0xFF00
	testing.expect_value(t, bytes[2], u8(0x00))
	testing.expect_value(t, bytes[3], u8(0xFF))
}

@(test)
test_struct_builder_set_float :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 2, 0)
	
	struct_builder_set_f32(&root, 0, 1.0)
	struct_builder_set_f64(&root, 8, 2.0)
	
	seg := segment_manager_get_segment(&mb.segments, 0)
	
	// 1.0f as u32 = 0x3F800000
	w0, _ := segment_get_word(seg, 1)
	testing.expect_value(t, u32(w0 & 0xFFFFFFFF), u32(0x3F800000))
	
	// 2.0 as u64 = 0x4000000000000000
	w1, _ := segment_get_word(seg, 2)
	testing.expect_value(t, w1, Word(0x4000000000000000))
}

@(test)
test_struct_builder_init_nested_struct :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Root with 1 data word and 1 pointer
	root, _ := message_builder_init_root(&mb, 1, 1)
	struct_builder_set_u64(&root, 0, 0x1234567890ABCDEF)
	
	// Initialize nested struct at pointer 0
	nested, err := struct_builder_init_struct(&root, 0, 1, 0)
	testing.expect_value(t, err, Error.None)
	
	struct_builder_set_u64(&nested, 0, 0xFEDCBA0987654321)
	
	// Verify the nested struct was created
	seg := segment_manager_get_segment(&mb.segments, 0)
	
	// Word 0: root pointer
	// Word 1: root data (0x1234567890ABCDEF)
	// Word 2: pointer to nested struct
	// Word 3: nested struct data
	
	w1, _ := segment_get_word(seg, 1)
	testing.expect_value(t, w1, Word(0x1234567890ABCDEF))
	
	w3, _ := segment_get_word(seg, 3)
	testing.expect_value(t, w3, Word(0xFEDCBA0987654321))
}

@(test)
test_struct_builder_set_text :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	
	err := struct_builder_set_text(&root, 0, "Hello")
	testing.expect_value(t, err, Error.None)
	
	// Text is stored as List(Byte) with NUL terminator
	// "Hello" + NUL = 6 bytes = 1 word
	seg := segment_manager_get_segment(&mb.segments, 0)
	
	// Word 0: root pointer
	// Word 1: list pointer to text (in root's pointer section)
	// Word 2: "Hello\0" + padding
	
	bytes, _ := segment_get_bytes(seg, 2, 6)
	testing.expect_value(t, bytes[0], u8('H'))
	testing.expect_value(t, bytes[1], u8('e'))
	testing.expect_value(t, bytes[2], u8('l'))
	testing.expect_value(t, bytes[3], u8('l'))
	testing.expect_value(t, bytes[4], u8('o'))
	testing.expect_value(t, bytes[5], u8(0)) // NUL terminator
}

@(test)
test_struct_builder_set_data :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	
	data := []byte{0x01, 0x02, 0x03, 0x04}
	err := struct_builder_set_data(&root, 0, data)
	testing.expect_value(t, err, Error.None)
	
	seg := segment_manager_get_segment(&mb.segments, 0)
	bytes, _ := segment_get_bytes(seg, 2, 4)
	
	testing.expect_value(t, bytes[0], u8(0x01))
	testing.expect_value(t, bytes[1], u8(0x02))
	testing.expect_value(t, bytes[2], u8(0x03))
	testing.expect_value(t, bytes[3], u8(0x04))
}

// ============================================================================
// List Builder Tests
// ============================================================================

@(test)
test_struct_builder_init_list_u32 :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	
	// Create list of 4 u32 values (16 bytes = 2 words)
	list, err := struct_builder_init_list(&root, 0, .Four_Bytes, 4)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, list.count, u32(4))
	
	list_builder_set_u32(&list, 0, 100)
	list_builder_set_u32(&list, 1, 200)
	list_builder_set_u32(&list, 2, 300)
	list_builder_set_u32(&list, 3, 400)
	
	seg := segment_manager_get_segment(&mb.segments, 0)
	bytes, _ := segment_get_bytes(seg, 2, 16)
	
	// First u32 = 100 = 0x64 little-endian
	testing.expect_value(t, bytes[0], u8(100))
	testing.expect_value(t, bytes[1], u8(0))
	testing.expect_value(t, bytes[2], u8(0))
	testing.expect_value(t, bytes[3], u8(0))
	
	// Second u32 = 200 = 0xC8
	testing.expect_value(t, bytes[4], u8(200))
}

@(test)
test_list_builder_set_bool :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	
	// Create list of 8 bools (8 bits = 1 byte, rounded to 1 word)
	list, err := struct_builder_init_list(&root, 0, .Bit, 8)
	testing.expect_value(t, err, Error.None)
	
	list_builder_set_bool(&list, 0, true)
	list_builder_set_bool(&list, 2, true)
	list_builder_set_bool(&list, 7, true)
	
	seg := segment_manager_get_segment(&mb.segments, 0)
	bytes, _ := segment_get_bytes(seg, 2, 1)
	
	// Bits 0, 2, 7 set = 0b10000101 = 0x85
	testing.expect_value(t, bytes[0], u8(0x85))
}

@(test)
test_list_builder_set_u64 :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	
	list, _ := struct_builder_init_list(&root, 0, .Eight_Bytes, 2)
	
	list_builder_set_u64(&list, 0, 0x1234567890ABCDEF)
	list_builder_set_u64(&list, 1, 0xFEDCBA0987654321)
	
	seg := segment_manager_get_segment(&mb.segments, 0)
	w0, _ := segment_get_word(seg, 2)
	w1, _ := segment_get_word(seg, 3)
	
	testing.expect_value(t, w0, Word(0x1234567890ABCDEF))
	testing.expect_value(t, w1, Word(0xFEDCBA0987654321))
}

@(test)
test_struct_builder_init_struct_list :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	
	// Create composite list of 2 structs, each with 1 data word and 0 pointers
	list, err := struct_builder_init_struct_list(&root, 0, 2, 1, 0)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, list.count, u32(2))
	testing.expect_value(t, list.element_size, Element_Size.Composite)
	
	// Get struct builders for each element
	s0, err0 := list_builder_get_struct(&list, 0)
	testing.expect_value(t, err0, Error.None)
	struct_builder_set_u64(&s0, 0, 111)
	
	s1, err1 := list_builder_get_struct(&list, 1)
	testing.expect_value(t, err1, Error.None)
	struct_builder_set_u64(&s1, 0, 222)
	
	seg := segment_manager_get_segment(&mb.segments, 0)
	
	// Layout:
	// Word 0: root pointer
	// Word 1: list pointer (to composite list)
	// Word 2: tag word (element count in offset field)
	// Word 3: struct 0 data
	// Word 4: struct 1 data
	
	w3, _ := segment_get_word(seg, 3)
	w4, _ := segment_get_word(seg, 4)
	
	testing.expect_value(t, w3, Word(111))
	testing.expect_value(t, w4, Word(222))
}

// ============================================================================
// Serialization Tests
// ============================================================================

@(test)
test_serialize_simple_struct :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 1, 0)
	struct_builder_set_u64(&root, 0, 0xDEADBEEFCAFEBABE)
	
	data, err := serialize(&mb)
	defer delete(data)
	
	testing.expect_value(t, err, Error.None)
	testing.expect(t, len(data) > 0, "Should have data")
	
	// Verify frame header
	// 1 segment: header is 8 bytes (4 for count-1, 4 for size)
	// Segment size: 2 words (root pointer + 1 data word)
	testing.expect_value(t, data[0], u8(0)) // segment count - 1 = 0
	testing.expect_value(t, data[4], u8(2)) // segment size = 2 words
	
	// Total size: 8 bytes header + 16 bytes data = 24 bytes
	testing.expect_value(t, len(data), 24)
}

@(test)
test_serialize_roundtrip :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 2, 0)
	struct_builder_set_u64(&root, 0, 0x1234567890ABCDEF)
	struct_builder_set_u32(&root, 8, 42)
	
	// Serialize
	data, err := serialize(&mb)
	defer delete(data)
	testing.expect_value(t, err, Error.None)
	
	// Deserialize
	sm2, bytes_read, err2 := deserialize_segments(data)
	defer segment_manager_destroy(&sm2)
	
	testing.expect_value(t, err2, Error.None)
	testing.expect_value(t, bytes_read, u32(len(data)))
	
	// Verify data
	seg := segment_manager_get_segment(&sm2, 0)
	
	// Word 0: root pointer, word 1-2: data
	w1, _ := segment_get_word(seg, 1)
	testing.expect_value(t, w1, Word(0x1234567890ABCDEF))
	
	bytes, _ := segment_get_bytes(seg, 2, 4)
	testing.expect_value(t, bytes[0], u8(42))
}

// ============================================================================
// Edge Case Tests (from code review)
// ============================================================================

@(test)
test_zero_sized_root_struct :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Zero-sized struct should use offset = -1 per spec
	root, err := message_builder_init_root(&mb, 0, 0)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, root.data_words, u16(0))
	testing.expect_value(t, root.pointer_count, u16(0))
	
	// Verify the pointer encoding
	seg := segment_manager_get_segment(&mb.segments, 0)
	root_ptr, _ := segment_get_word(seg, 0)
	
	// Decode and verify offset = -1
	parts, ok := struct_pointer_decode(root_ptr)
	testing.expect(t, ok, "Should decode as struct pointer")
	testing.expect_value(t, parts.offset, i32(-1))
	testing.expect_value(t, parts.data_size, u16(0))
	testing.expect_value(t, parts.pointer_count, u16(0))
}

@(test)
test_zero_sized_nested_struct :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	
	// Initialize zero-sized nested struct
	nested, err := struct_builder_init_struct(&root, 0, 0, 0)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, nested.data_words, u16(0))
	testing.expect_value(t, nested.pointer_count, u16(0))
	
	// Verify the pointer encoding uses offset = -1
	seg := segment_manager_get_segment(&mb.segments, 0)
	ptr_word, _ := segment_get_word(seg, 1) // Pointer section of root
	
	parts, ok := struct_pointer_decode(ptr_word)
	testing.expect(t, ok, "Should decode as struct pointer")
	testing.expect_value(t, parts.offset, i32(-1))
}

@(test)
test_zero_length_data :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	
	// Set empty data blob
	empty_data: []byte
	err := struct_builder_set_data(&root, 0, empty_data)
	testing.expect_value(t, err, Error.None)
	
	// Verify list pointer with count = 0
	seg := segment_manager_get_segment(&mb.segments, 0)
	ptr_word, _ := segment_get_word(seg, 1)
	
	parts, ok := list_pointer_decode(ptr_word)
	testing.expect(t, ok, "Should decode as list pointer")
	testing.expect_value(t, parts.element_size, Element_Size.Byte)
	testing.expect_value(t, parts.element_count, u32(0))
}

@(test)
test_zero_length_void_list :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	
	// Create list of 10 voids (0 bits each = 0 words total)
	list, err := struct_builder_init_list(&root, 0, .Void, 10)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, list.count, u32(10))
	
	// Verify list pointer with count = 10, but no allocation
	seg := segment_manager_get_segment(&mb.segments, 0)
	ptr_word, _ := segment_get_word(seg, 1)
	
	parts, ok := list_pointer_decode(ptr_word)
	testing.expect(t, ok, "Should decode as list pointer")
	testing.expect_value(t, parts.element_size, Element_Size.Void)
	testing.expect_value(t, parts.element_count, u32(10))
}

@(test)
test_zero_count_struct_list :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	
	// Create composite list with 0 elements (still needs tag word)
	list, err := struct_builder_init_struct_list(&root, 0, 0, 1, 0)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, list.count, u32(0))
	testing.expect_value(t, list.element_size, Element_Size.Composite)
}

// ============================================================================
// Reader API Tests
// ============================================================================

@(test)
test_reader_primitives_roundtrip :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 3, 0)
	struct_builder_set_u64(&root, 0, 0x1234567890ABCDEF)
	struct_builder_set_u32(&root, 8, 12345)
	struct_builder_set_u16(&root, 12, 6789)
	struct_builder_set_u8(&root, 14, 42)
	struct_builder_set_bool(&root, 120, true) // bit 120 = byte 15, bit 0
	
	// Serialize
	data, err := serialize(&mb)
	defer delete(data)
	testing.expect_value(t, err, Error.None)
	
	// Deserialize
	reader, reader_err := deserialize(data)
	defer message_reader_destroy(&reader)
	testing.expect_value(t, reader_err, Error.None)
	
	// Read root
	sr, root_err := message_reader_get_root(&reader)
	testing.expect_value(t, root_err, Error.None)
	
	// Verify primitives
	testing.expect_value(t, struct_reader_get_u64(&sr, 0), u64(0x1234567890ABCDEF))
	testing.expect_value(t, struct_reader_get_u32(&sr, 8), u32(12345))
	testing.expect_value(t, struct_reader_get_u16(&sr, 12), u16(6789))
	testing.expect_value(t, struct_reader_get_u8(&sr, 14), u8(42))
	testing.expect(t, struct_reader_get_bool(&sr, 120), "Bool at bit 120 should be true")
}

@(test)
test_reader_signed_integers :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 2, 0)
	struct_builder_set_i64(&root, 0, -1234567890)
	struct_builder_set_i32(&root, 8, -12345)
	struct_builder_set_i16(&root, 12, -678)
	struct_builder_set_i8(&root, 14, -42)
	
	data, _ := serialize(&mb)
	defer delete(data)
	
	reader, _ := deserialize(data)
	defer message_reader_destroy(&reader)
	
	sr, _ := message_reader_get_root(&reader)
	
	testing.expect_value(t, struct_reader_get_i64(&sr, 0), i64(-1234567890))
	testing.expect_value(t, struct_reader_get_i32(&sr, 8), i32(-12345))
	testing.expect_value(t, struct_reader_get_i16(&sr, 12), i16(-678))
	testing.expect_value(t, struct_reader_get_i8(&sr, 14), i8(-42))
}

@(test)
test_reader_floats :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 2, 0)
	struct_builder_set_f32(&root, 0, 3.14159)
	struct_builder_set_f64(&root, 8, 2.718281828)
	
	data, _ := serialize(&mb)
	defer delete(data)
	
	reader, _ := deserialize(data)
	defer message_reader_destroy(&reader)
	
	sr, _ := message_reader_get_root(&reader)
	
	f32_val := struct_reader_get_f32(&sr, 0)
	f64_val := struct_reader_get_f64(&sr, 8)
	
	testing.expect(t, abs(f32_val - 3.14159) < 0.0001, "f32 should be close to 3.14159")
	testing.expect(t, abs(f64_val - 2.718281828) < 0.0000001, "f64 should be close to 2.718281828")
}

@(test)
test_reader_defaults_for_out_of_bounds :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Create a struct with only 1 data word
	root, _ := message_builder_init_root(&mb, 1, 0)
	struct_builder_set_u64(&root, 0, 42)
	
	data, _ := serialize(&mb)
	defer delete(data)
	
	reader, _ := deserialize(data)
	defer message_reader_destroy(&reader)
	
	sr, _ := message_reader_get_root(&reader)
	
	// Read beyond struct size - should return defaults
	testing.expect_value(t, struct_reader_get_u64(&sr, 8, 999), u64(999))
	testing.expect_value(t, struct_reader_get_u32(&sr, 8, 999), u32(999))
	testing.expect_value(t, struct_reader_get_u16(&sr, 8, 999), u16(999))
	testing.expect_value(t, struct_reader_get_u8(&sr, 8, 99), u8(99))
	testing.expect_value(t, struct_reader_get_bool(&sr, 64, true), true)
}

@(test)
test_reader_text :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	struct_builder_set_text(&root, 0, "Hello, Cap'n Proto!")
	
	data, _ := serialize(&mb)
	defer delete(data)
	
	reader, _ := deserialize(data)
	defer message_reader_destroy(&reader)
	
	sr, _ := message_reader_get_root(&reader)
	
	text, text_err := struct_reader_get_text(&sr, 0)
	testing.expect_value(t, text_err, Error.None)
	testing.expect_value(t, text, "Hello, Cap'n Proto!")
}

@(test)
test_reader_data :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	test_data := []byte{0x01, 0x02, 0x03, 0x04, 0x05}
	struct_builder_set_data(&root, 0, test_data)
	
	data, _ := serialize(&mb)
	defer delete(data)
	
	reader, _ := deserialize(data)
	defer message_reader_destroy(&reader)
	
	sr, _ := message_reader_get_root(&reader)
	
	read_data, data_err := struct_reader_get_data(&sr, 0)
	testing.expect_value(t, data_err, Error.None)
	testing.expect_value(t, len(read_data), 5)
	for i in 0..<5 {
		testing.expect_value(t, read_data[i], test_data[i])
	}
}

@(test)
test_reader_nested_struct :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 1, 1)
	struct_builder_set_u64(&root, 0, 100)
	
	nested, _ := struct_builder_init_struct(&root, 0, 1, 0)
	struct_builder_set_u64(&nested, 0, 200)
	
	data, _ := serialize(&mb)
	defer delete(data)
	
	reader, _ := deserialize(data)
	defer message_reader_destroy(&reader)
	
	sr, _ := message_reader_get_root(&reader)
	
	testing.expect_value(t, struct_reader_get_u64(&sr, 0), u64(100))
	testing.expect(t, struct_reader_has_pointer(&sr, 0), "Should have pointer at index 0")
	
	nested_sr, nested_err := struct_reader_get_struct(&sr, 0)
	testing.expect_value(t, nested_err, Error.None)
	testing.expect_value(t, struct_reader_get_u64(&nested_sr, 0), u64(200))
}

@(test)
test_reader_list_u32 :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	list, _ := struct_builder_init_list(&root, 0, .Four_Bytes, 5)
	
	for i in 0..<5 {
		list_builder_set_u32(&list, u32(i), u32(i * 100))
	}
	
	data, _ := serialize(&mb)
	defer delete(data)
	
	reader, _ := deserialize(data)
	defer message_reader_destroy(&reader)
	
	sr, _ := message_reader_get_root(&reader)
	lr, list_err := struct_reader_get_list(&sr, 0, .Four_Bytes)
	testing.expect_value(t, list_err, Error.None)
	testing.expect_value(t, list_reader_len(&lr), u32(5))
	
	for i in 0..<5 {
		testing.expect_value(t, list_reader_get_u32(&lr, u32(i)), u32(i * 100))
	}
}

@(test)
test_reader_list_bool :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	list, _ := struct_builder_init_list(&root, 0, .Bit, 8)
	
	list_builder_set_bool(&list, 0, true)
	list_builder_set_bool(&list, 2, true)
	list_builder_set_bool(&list, 7, true)
	
	data, _ := serialize(&mb)
	defer delete(data)
	
	reader, _ := deserialize(data)
	defer message_reader_destroy(&reader)
	
	sr, _ := message_reader_get_root(&reader)
	lr, _ := struct_reader_get_list(&sr, 0, .Bit)
	
	testing.expect_value(t, list_reader_len(&lr), u32(8))
	testing.expect(t, list_reader_get_bool(&lr, 0), "Bit 0 should be true")
	testing.expect(t, !list_reader_get_bool(&lr, 1), "Bit 1 should be false")
	testing.expect(t, list_reader_get_bool(&lr, 2), "Bit 2 should be true")
	testing.expect(t, !list_reader_get_bool(&lr, 3), "Bit 3 should be false")
	testing.expect(t, list_reader_get_bool(&lr, 7), "Bit 7 should be true")
}

@(test)
test_reader_composite_list :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	root, _ := message_builder_init_root(&mb, 0, 1)
	list, _ := struct_builder_init_struct_list(&root, 0, 3, 1, 0)
	
	for i in 0..<3 {
		elem, _ := list_builder_get_struct(&list, u32(i))
		struct_builder_set_u64(&elem, 0, u64(i * 1000))
	}
	
	data, _ := serialize(&mb)
	defer delete(data)
	
	reader, _ := deserialize(data)
	defer message_reader_destroy(&reader)
	
	sr, _ := message_reader_get_root(&reader)
	lr, list_err := struct_reader_get_list(&sr, 0, .Composite)
	testing.expect_value(t, list_err, Error.None)
	testing.expect_value(t, list_reader_len(&lr), u32(3))
	
	for i in 0..<3 {
		elem, elem_err := list_reader_get_struct(&lr, u32(i))
		testing.expect_value(t, elem_err, Error.None)
		testing.expect_value(t, struct_reader_get_u64(&elem, 0), u64(i * 1000))
	}
}

@(test)
test_reader_nesting_limit :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Create deeply nested structure
	root, _ := message_builder_init_root(&mb, 1, 1)
	struct_builder_set_u64(&root, 0, 0)
	
	current := root
	for i in 0..<10 {
		nested, _ := struct_builder_init_struct(&current, 0, 1, 1)
		struct_builder_set_u64(&nested, 0, u64(i + 1))
		current = nested
	}
	
	data, _ := serialize(&mb)
	defer delete(data)
	
	// Read with a low nesting limit
	reader, _ := message_reader_from_bytes(data, Read_Limits{
		traversal_limit = DEFAULT_TRAVERSAL_LIMIT,
		nesting_limit   = 5,
	})
	defer message_reader_destroy(&reader)
	
	sr, _ := message_reader_get_root(&reader)
	
	// Traverse nested structs until limit
	current_sr := sr
	for i in 0..<10 {
		nested_sr, err := struct_reader_get_struct(&current_sr, 0)
		if err == .Nesting_Limit_Exceeded {
			// Expected to hit this before reaching depth 10
			testing.expect(t, i < 10, "Should hit nesting limit before depth 10")
			return
		}
		current_sr = nested_sr
	}
	testing.expect(t, false, "Should have hit nesting limit")
}

@(test)
test_reader_null_pointer :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Create struct with pointer slot but don't set it
	root, _ := message_builder_init_root(&mb, 0, 1)
	
	data, _ := serialize(&mb)
	defer delete(data)
	
	reader, _ := deserialize(data)
	defer message_reader_destroy(&reader)
	
	sr, _ := message_reader_get_root(&reader)
	
	// Pointer should be null
	testing.expect(t, !struct_reader_has_pointer(&sr, 0), "Pointer 0 should be null")
	
	// Getting struct should return empty struct, not error
	nested, err := struct_reader_get_struct(&sr, 0)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, nested.data_size, u16(0))
	testing.expect_value(t, nested.pointer_count, u16(0))
}

@(test)
test_reader_traversal_limit :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Create a large list
	root, _ := message_builder_init_root(&mb, 0, 1)
	list, _ := struct_builder_init_list(&root, 0, .Eight_Bytes, 100)
	
	for i in 0..<100 {
		list_builder_set_u64(&list, u32(i), u64(i))
	}
	
	data, _ := serialize(&mb)
	defer delete(data)
	
	// Read with a very low traversal limit
	reader, _ := message_reader_from_bytes(data, Read_Limits{
		traversal_limit = 10, // Only 10 words
		nesting_limit   = DEFAULT_NESTING_LIMIT,
	})
	defer message_reader_destroy(&reader)
	
	// Getting root should succeed
	sr, root_err := message_reader_get_root(&reader)
	testing.expect_value(t, root_err, Error.None)
	
	// Getting the list should exceed traversal limit (100 words > 10)
	_, list_err := struct_reader_get_list(&sr, 0, .Eight_Bytes)
	testing.expect_value(t, list_err, Error.Traversal_Limit_Exceeded)
}

// ============================================================================
// Packing Tests
// ============================================================================

@(test)
test_pack_word_basic :: proc(t: ^testing.T) {
	// Test packing a word with mixed zeros and non-zeros
	// Input: 08 00 00 00 03 00 02 00
	// Byte 0=0x08 (non-zero), Byte 4=0x03 (non-zero), Byte 6=0x02 (non-zero)
	// Expected tag: 0x51 (bits 0, 4, 6 set = 0b01010001)
	// Expected output: 51 08 03 02
	word := [8]byte{0x08, 0x00, 0x00, 0x00, 0x03, 0x00, 0x02, 0x00}
	result, length := pack_word(word[:])
	
	testing.expect_value(t, length, 4)
	testing.expect_value(t, result[0], u8(0x51)) // tag: bits 0, 4, 6
	testing.expect_value(t, result[1], u8(0x08))
	testing.expect_value(t, result[2], u8(0x03))
	testing.expect_value(t, result[3], u8(0x02))
}

@(test)
test_pack_word_all_zeros :: proc(t: ^testing.T) {
	word := [8]byte{0, 0, 0, 0, 0, 0, 0, 0}
	result, length := pack_word(word[:])
	
	testing.expect_value(t, length, 1)
	testing.expect_value(t, result[0], u8(0x00)) // tag
}

@(test)
test_pack_word_all_nonzero :: proc(t: ^testing.T) {
	word := [8]byte{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08}
	result, length := pack_word(word[:])
	
	testing.expect_value(t, length, 9)
	testing.expect_value(t, result[0], u8(0xFF)) // tag
	for i in 0 ..< 8 {
		testing.expect_value(t, result[i + 1], u8(i + 1))
	}
}

@(test)
test_unpack_word_basic :: proc(t: ^testing.T) {
	// Packed: 51 08 03 02 -> 08 00 00 00 03 00 02 00
	// Tag 0x51 = bits 0, 4, 6 set
	packed := [4]byte{0x51, 0x08, 0x03, 0x02}
	word, consumed, err := unpack_word(packed[:])
	
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, consumed, 4)
	testing.expect_value(t, word[0], u8(0x08)) // bit 0
	testing.expect_value(t, word[1], u8(0x00))
	testing.expect_value(t, word[2], u8(0x00))
	testing.expect_value(t, word[3], u8(0x00))
	testing.expect_value(t, word[4], u8(0x03)) // bit 4
	testing.expect_value(t, word[5], u8(0x00))
	testing.expect_value(t, word[6], u8(0x02)) // bit 6
	testing.expect_value(t, word[7], u8(0x00))
}

@(test)
test_pack_unpack_roundtrip :: proc(t: ^testing.T) {
	// Create test data with mixed patterns
	original := [?]byte{
		0x08, 0x00, 0x00, 0x00, 0x03, 0x00, 0x02, 0x00, // Mixed word
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // Zero word
		0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA, 0x99, 0x88, // All non-zero
	}
	
	packed, pack_err := pack(original[:])
	defer delete(packed)
	testing.expect_value(t, pack_err, Error.None)
	
	unpacked, unpack_err := unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, Error.None)
	
	testing.expect_value(t, len(unpacked), len(original))
	for i in 0 ..< len(original) {
		testing.expect_value(t, unpacked[i], original[i])
	}
}

@(test)
test_pack_zero_runs :: proc(t: ^testing.T) {
	// Three zero words -> should pack efficiently
	original := [24]byte{} // All zeros (3 words)
	
	packed, pack_err := pack(original[:])
	defer delete(packed)
	testing.expect_value(t, pack_err, Error.None)
	
	// Expected: 00 02 (tag 0x00, count 2 for additional words)
	testing.expect_value(t, len(packed), 2)
	testing.expect_value(t, packed[0], u8(0x00))
	testing.expect_value(t, packed[1], u8(0x02)) // 2 additional zero words
	
	// Roundtrip
	unpacked, unpack_err := unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, Error.None)
	testing.expect_value(t, len(unpacked), len(original))
}

@(test)
test_pack_literal_runs :: proc(t: ^testing.T) {
	// Two words with all non-zero bytes
	original := [16]byte{
		0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA, 0x99, 0x88,
		0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
	}
	
	packed, pack_err := pack(original[:])
	defer delete(packed)
	testing.expect_value(t, pack_err, Error.None)
	
	// Expected: FF [8 bytes] 01 [8 bytes]
	// = 1 + 8 + 1 + 8 = 18 bytes
	testing.expect_value(t, len(packed), 18)
	testing.expect_value(t, packed[0], u8(0xFF)) // tag for first word
	testing.expect_value(t, packed[9], u8(0x01)) // count of 1 additional literal word
	
	// Roundtrip
	unpacked, unpack_err := unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, Error.None)
	testing.expect_value(t, len(unpacked), len(original))
	for i in 0 ..< len(original) {
		testing.expect_value(t, unpacked[i], original[i])
	}
}

@(test)
test_pack_empty_input :: proc(t: ^testing.T) {
	packed, pack_err := pack(nil)
	testing.expect_value(t, pack_err, Error.None)
	testing.expect(t, packed == nil, "Empty input should return nil")
	
	unpacked, unpack_err := unpack(nil)
	testing.expect_value(t, unpack_err, Error.None)
	testing.expect(t, unpacked == nil, "Empty input should return nil")
}

@(test)
test_pack_single_word :: proc(t: ^testing.T) {
	original := [8]byte{0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}
	
	packed, pack_err := pack(original[:])
	defer delete(packed)
	testing.expect_value(t, pack_err, Error.None)
	
	// Tag should be 0x01 (only bit 0 set), followed by 0x01
	testing.expect_value(t, len(packed), 2)
	testing.expect_value(t, packed[0], u8(0x01))
	testing.expect_value(t, packed[1], u8(0x01))
	
	// Roundtrip
	unpacked, unpack_err := unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, Error.None)
	testing.expect_value(t, len(unpacked), len(original))
	for i in 0 ..< len(original) {
		testing.expect_value(t, unpacked[i], original[i])
	}
}

@(test)
test_pack_max_zero_run :: proc(t: ^testing.T) {
	// 256 zero words = 1 initial + 255 additional = exactly one max run
	original, alloc_err := make([]byte, 256 * 8)
	testing.expect(t, alloc_err == nil, "Allocation should succeed")
	defer delete(original)
	
	packed, pack_err := pack(original)
	defer delete(packed)
	testing.expect_value(t, pack_err, Error.None)
	
	// Should be: 00 FF (1 zero word + 255 additional = 256 total)
	// = 2 bytes total
	testing.expect_value(t, len(packed), 2)
	testing.expect_value(t, packed[0], u8(0x00))
	testing.expect_value(t, packed[1], u8(0xFF)) // 255 additional
	
	// Roundtrip
	unpacked, unpack_err := unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, Error.None)
	testing.expect_value(t, len(unpacked), len(original))
}

@(test)
test_pack_max_zero_run_plus_one :: proc(t: ^testing.T) {
	// 257 zero words = 1 initial + 255 additional + 1 more = needs two zero tags
	original, alloc_err := make([]byte, 257 * 8)
	testing.expect(t, alloc_err == nil, "Allocation should succeed")
	defer delete(original)
	
	packed, pack_err := pack(original)
	defer delete(packed)
	testing.expect_value(t, pack_err, Error.None)
	
	// Should be: 00 FF (256 zero words), 00 00 (1 more zero word)
	// = 4 bytes total
	testing.expect_value(t, len(packed), 4)
	testing.expect_value(t, packed[0], u8(0x00))
	testing.expect_value(t, packed[1], u8(0xFF)) // 255 additional
	testing.expect_value(t, packed[2], u8(0x00))
	testing.expect_value(t, packed[3], u8(0x00)) // 0 additional
	
	// Roundtrip
	unpacked, unpack_err := unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, Error.None)
	testing.expect_value(t, len(unpacked), len(original))
}

@(test)
test_unpack_truncated_data :: proc(t: ^testing.T) {
	// Tag says byte 0 is non-zero but no byte follows
	truncated := [1]byte{0x01}
	_, unpack_err := unpack(truncated[:])
	testing.expect_value(t, unpack_err, Error.Invalid_Packed_Data)
}

@(test)
test_unpack_truncated_zero_run :: proc(t: ^testing.T) {
	// Tag 0x00 but no count byte
	truncated := [1]byte{0x00}
	_, unpack_err := unpack(truncated[:])
	testing.expect_value(t, unpack_err, Error.Invalid_Packed_Data)
}

@(test)
test_unpack_truncated_literal_run :: proc(t: ^testing.T) {
	// Tag 0xFF with 8 bytes but no count byte
	truncated := [9]byte{0xFF, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08}
	_, unpack_err := unpack(truncated[:])
	testing.expect_value(t, unpack_err, Error.Invalid_Packed_Data)
}

@(test)
test_pack_not_word_aligned :: proc(t: ^testing.T) {
	// Input not a multiple of 8 bytes should fail
	not_aligned := [7]byte{1, 2, 3, 4, 5, 6, 7}
	_, pack_err := pack(not_aligned[:])
	testing.expect_value(t, pack_err, Error.Invalid_Packed_Data)
}

@(test)
test_serialize_packed_roundtrip :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Build a message with mixed data (some zeros, some non-zeros)
	root, _ := message_builder_init_root(&mb, 2, 1)
	struct_builder_set_u64(&root, 0, 0x12345678)
	struct_builder_set_u64(&root, 8, 0)
	struct_builder_set_text(&root, 0, "Hello, packed!")
	
	// Serialize packed
	packed, pack_err := serialize_packed(&mb)
	defer delete(packed)
	testing.expect_value(t, pack_err, Error.None)
	
	// Deserialize packed
	reader, unpacked_data, unpack_err := deserialize_packed(packed)
	defer message_reader_destroy(&reader)
	defer delete(unpacked_data)
	testing.expect_value(t, unpack_err, Error.None)
	
	// Verify data
	sr, root_err := message_reader_get_root(&reader)
	testing.expect_value(t, root_err, Error.None)
	testing.expect_value(t, struct_reader_get_u64(&sr, 0), u64(0x12345678))
	testing.expect_value(t, struct_reader_get_u64(&sr, 8), u64(0))
	
	text, text_err := struct_reader_get_text(&sr, 0)
	testing.expect_value(t, text_err, Error.None)
	testing.expect_value(t, text, "Hello, packed!")
}

@(test)
test_packed_size_reduction :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Build a message with lots of zeros (typical Cap'n Proto pattern)
	root, _ := message_builder_init_root(&mb, 8, 0) // 8 words of data, mostly zeros
	struct_builder_set_u32(&root, 0, 100)
	struct_builder_set_u32(&root, 16, 200)
	
	// Serialize unpacked
	unpacked, _ := serialize(&mb)
	defer delete(unpacked)
	
	// Serialize packed
	packed, _ := serialize_packed(&mb)
	defer delete(packed)
	
	// Packed should be smaller
	testing.expect(t, len(packed) < len(unpacked), "Packed should be smaller than unpacked")
}

@(test)
test_packed_complex_message :: proc(t: ^testing.T) {
	mb: Message_Builder
	message_builder_init(&mb)
	defer message_builder_destroy(&mb)
	
	// Build a complex message
	root, _ := message_builder_init_root(&mb, 2, 2)
	struct_builder_set_u64(&root, 0, 0xDEADBEEF)
	struct_builder_set_bool(&root, 64, true)
	
	// Nested struct
	nested, _ := struct_builder_init_struct(&root, 0, 1, 0)
	struct_builder_set_u32(&nested, 0, 42)
	
	// List
	list, _ := struct_builder_init_list(&root, 1, .Four_Bytes, 3)
	list_builder_set_u32(&list, 0, 100)
	list_builder_set_u32(&list, 1, 200)
	list_builder_set_u32(&list, 2, 300)
	
	// Serialize packed
	packed, pack_err := serialize_packed(&mb)
	defer delete(packed)
	testing.expect_value(t, pack_err, Error.None)
	
	// Deserialize packed
	reader, unpacked_data, unpack_err := deserialize_packed(packed)
	defer message_reader_destroy(&reader)
	defer delete(unpacked_data)
	testing.expect_value(t, unpack_err, Error.None)
	
	// Verify all data
	sr, _ := message_reader_get_root(&reader)
	testing.expect_value(t, struct_reader_get_u64(&sr, 0), u64(0xDEADBEEF))
	testing.expect_value(t, struct_reader_get_bool(&sr, 64), true)
	
	nested_sr, _ := struct_reader_get_struct(&sr, 0)
	testing.expect_value(t, struct_reader_get_u32(&nested_sr, 0), u32(42))
	
	lr, _ := struct_reader_get_list(&sr, 1, .Four_Bytes)
	testing.expect_value(t, list_reader_len(&lr), u32(3))
	testing.expect_value(t, list_reader_get_u32(&lr, 0), u32(100))
	testing.expect_value(t, list_reader_get_u32(&lr, 1), u32(200))
	testing.expect_value(t, list_reader_get_u32(&lr, 2), u32(300))
}

@(test)
test_unpack_literal_words_with_zeros :: proc(t: ^testing.T) {
	// Per spec: literal words after 0xFF "may or may not contain zeros"
	// Construct packed data with 0xFF tag followed by literal words containing zeros
	// Format: FF [8 bytes] [count] [literal words...]
	packed := [?]byte{
		0xFF, // tag: all 8 non-zero
		0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, // first word (all non-zero)
		0x01, // 1 literal word follows
		0xAA, 0x00, 0xBB, 0x00, 0xCC, 0x00, 0xDD, 0x00, // literal word WITH zeros
	}

	unpacked, unpack_err := unpack(packed[:])
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, Error.None)
	testing.expect_value(t, len(unpacked), 16) // 2 words = 16 bytes

	// Verify first word
	testing.expect_value(t, unpacked[0], u8(0x01))
	testing.expect_value(t, unpacked[7], u8(0x08))

	// Verify literal word with zeros was unpacked correctly
	testing.expect_value(t, unpacked[8], u8(0xAA))
	testing.expect_value(t, unpacked[9], u8(0x00))
	testing.expect_value(t, unpacked[10], u8(0xBB))
	testing.expect_value(t, unpacked[11], u8(0x00))
	testing.expect_value(t, unpacked[12], u8(0xCC))
	testing.expect_value(t, unpacked[13], u8(0x00))
	testing.expect_value(t, unpacked[14], u8(0xDD))
	testing.expect_value(t, unpacked[15], u8(0x00))
}

@(test)
test_unpack_size_limit :: proc(t: ^testing.T) {
	// Test that unpack respects size limits to prevent decompression bombs
	// Create packed data that would expand to more than the limit
	packed := [?]byte{
		0x00, 0xFF, // Zero word + 255 additional = 256 words = 2048 bytes
	}

	// Unpack with a small limit
	_, unpack_err := unpack(packed[:], max_output_size = 100)
	testing.expect_value(t, unpack_err, Error.Segment_Size_Overflow)
}

@(test)
test_pack_alternating_patterns :: proc(t: ^testing.T) {
	// Alternating compressible and incompressible words
	original := [?]byte{
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // zero word
		0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, // all non-zero
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // zero word
		0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA, 0xF9, 0xF8, // all non-zero
	}

	packed, pack_err := pack(original[:])
	defer delete(packed)
	testing.expect_value(t, pack_err, Error.None)

	// Roundtrip
	unpacked, unpack_err := unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, Error.None)
	testing.expect_value(t, len(unpacked), len(original))

	for i in 0 ..< len(original) {
		testing.expect_value(t, unpacked[i], original[i])
	}
}

@(test)
test_pack_sparse_data :: proc(t: ^testing.T) {
	// Data with only occasional non-zero bytes (common in Cap'n Proto)
	original := [?]byte{
		0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 1 non-zero
		0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, // 1 non-zero
		0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, // 1 non-zero
	}

	packed, pack_err := pack(original[:])
	defer delete(packed)
	testing.expect_value(t, pack_err, Error.None)

	// Should be well compressed (3 bytes become: tag + value each = 6 bytes total)
	// 24 bytes -> 6 bytes = 75% reduction
	testing.expect(t, len(packed) < len(original), "Sparse data should compress well")

	// Roundtrip
	unpacked, unpack_err := unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, Error.None)
	testing.expect_value(t, len(unpacked), len(original))

	for i in 0 ..< len(original) {
		testing.expect_value(t, unpacked[i], original[i])
	}
}

@(test)
test_unpack_missing_literal_payload :: proc(t: ^testing.T) {
	// 0xFF with count > 0 but missing literal data
	packed := [?]byte{
		0xFF, // tag
		0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, // 8 bytes
		0x02, // count = 2 literal words expected
		0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, // only 1 word provided
	}

	_, unpack_err := unpack(packed[:])
	testing.expect_value(t, unpack_err, Error.Invalid_Packed_Data)
}

@(test)
test_count_bits :: proc(t: ^testing.T) {
	// Test the bit counting used in tag processing
	test_cases := []struct {
		input:    u8,
		expected: int,
	}{
		{0x00, 0},
		{0x01, 1},
		{0x03, 2},
		{0x07, 3},
		{0x0F, 4},
		{0xFF, 8},
		{0x55, 4}, // 01010101
		{0xAA, 4}, // 10101010
	}

	for tc in test_cases {
		// We can't directly test private proc, but pack_word with specific patterns
		// implicitly tests count_bits via tag creation
		word: [8]byte
		expected_non_zero := 0
		for i in 0 ..< 8 {
			if (tc.input & (1 << uint(i))) != 0 {
				word[i] = 0xFF
				expected_non_zero += 1
			}
		}
		result, length := pack_word(word[:])
		testing.expect_value(t, result[0], tc.input)
		testing.expect_value(t, length, 1 + expected_non_zero)
	}
}
