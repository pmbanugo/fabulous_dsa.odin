package capnp_tests

import capnp ".."
import "core:mem"
import "core:testing"

// ============================================================================
// Frame Header Size Calculation Tests
// ============================================================================

@(test)
test_frame_header_size_single_segment :: proc(t: ^testing.T) {
	// 1 segment: 4 bytes count + 4 bytes size = 8 bytes (aligned)
	size := capnp.frame_header_size(1)
	testing.expect_value(t, size, u32(8))
}

@(test)
test_frame_header_size_two_segments :: proc(t: ^testing.T) {
	// 2 segments: 4 bytes count + 8 bytes sizes = 12 bytes + 4 padding = 16 bytes
	size := capnp.frame_header_size(2)
	testing.expect_value(t, size, u32(16))
}

@(test)
test_frame_header_size_three_segments :: proc(t: ^testing.T) {
	// 3 segments: 4 bytes count + 12 bytes sizes = 16 bytes (aligned)
	size := capnp.frame_header_size(3)
	testing.expect_value(t, size, u32(16))
}

@(test)
test_frame_header_size_four_segments :: proc(t: ^testing.T) {
	// 4 segments: 4 bytes count + 16 bytes sizes = 20 bytes + 4 padding = 24 bytes
	size := capnp.frame_header_size(4)
	testing.expect_value(t, size, u32(24))
}

@(test)
test_frame_header_size_odd_vs_even :: proc(t: ^testing.T) {
	// Odd segment count = (1 + count) * 4, rounded up to 8
	// Even segment count = (1 + count) * 4, rounded up to 8

	// 1 segment: 8 bytes (no padding needed for 2 u32s)
	testing.expect_value(t, capnp.frame_header_size(1), u32(8))

	// 2 segments: 12 + 4 padding = 16
	testing.expect_value(t, capnp.frame_header_size(2), u32(16))

	// 5 segments: 24 bytes (no padding)
	testing.expect_value(t, capnp.frame_header_size(5), u32(24))

	// 6 segments: 28 + 4 padding = 32
	testing.expect_value(t, capnp.frame_header_size(6), u32(32))
}

// ============================================================================
// Frame Header Serialization Tests
// ============================================================================

@(test)
test_serialize_frame_header_single_segment :: proc(t: ^testing.T) {
	sizes := []u32{100} // Single segment with 100 words
	buffer: [16]byte

	bytes_written, err := capnp.serialize_frame_header(sizes, buffer[:])
	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, bytes_written, u32(8))

	// Segment count - 1 = 0 (little-endian)
	testing.expect_value(t, buffer[0], u8(0))
	testing.expect_value(t, buffer[1], u8(0))
	testing.expect_value(t, buffer[2], u8(0))
	testing.expect_value(t, buffer[3], u8(0))

	// Segment size = 100 (little-endian)
	testing.expect_value(t, buffer[4], u8(100))
	testing.expect_value(t, buffer[5], u8(0))
	testing.expect_value(t, buffer[6], u8(0))
	testing.expect_value(t, buffer[7], u8(0))
}

@(test)
test_serialize_frame_header_multi_segment :: proc(t: ^testing.T) {
	sizes := []u32{100, 200, 50}
	buffer: [32]byte

	bytes_written, err := capnp.serialize_frame_header(sizes, buffer[:])
	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, bytes_written, u32(16))

	// Segment count - 1 = 2
	testing.expect_value(t, buffer[0], u8(2))

	// Segment sizes
	testing.expect_value(t, buffer[4], u8(100))  // Segment 0
	testing.expect_value(t, buffer[8], u8(200))  // Segment 1
	testing.expect_value(t, buffer[12], u8(50)) // Segment 2
}

@(test)
test_serialize_frame_header_empty_error :: proc(t: ^testing.T) {
	sizes: []u32 = {}
	buffer: [16]byte

	_, err := capnp.serialize_frame_header(sizes, buffer[:])
	testing.expect_value(t, err, capnp.Error.Invalid_Frame_Header)
}

@(test)
test_serialize_frame_header_buffer_too_small :: proc(t: ^testing.T) {
	sizes := []u32{100}
	buffer: [4]byte // Too small

	_, err := capnp.serialize_frame_header(sizes, buffer[:])
	testing.expect_value(t, err, capnp.Error.Unexpected_End_Of_Input)
}

// ============================================================================
// Frame Header Deserialization Tests
// ============================================================================

@(test)
test_deserialize_frame_header_single_segment :: proc(t: ^testing.T) {
	// Hand-crafted single segment header
	data := [?]byte{
		0x00, 0x00, 0x00, 0x00, // segment count - 1 = 0
		0x64, 0x00, 0x00, 0x00, // segment size = 100
	}

	header, bytes_read, err := capnp.deserialize_frame_header(data[:])
	defer capnp.frame_header_destroy(&header)

	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, bytes_read, u32(8))
	testing.expect_value(t, header.segment_count, u32(1))
	testing.expect_value(t, len(header.segment_sizes), 1)
	testing.expect_value(t, header.segment_sizes[0], u32(100))
}

@(test)
test_deserialize_frame_header_multi_segment :: proc(t: ^testing.T) {
	// Two segments with sizes 100 and 200
	data := [?]byte{
		0x01, 0x00, 0x00, 0x00, // segment count - 1 = 1
		0x64, 0x00, 0x00, 0x00, // segment 0 size = 100
		0xC8, 0x00, 0x00, 0x00, // segment 1 size = 200
		0x00, 0x00, 0x00, 0x00, // padding
	}

	header, bytes_read, err := capnp.deserialize_frame_header(data[:])
	defer capnp.frame_header_destroy(&header)

	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, bytes_read, u32(16))
	testing.expect_value(t, header.segment_count, u32(2))
	testing.expect_value(t, header.segment_sizes[0], u32(100))
	testing.expect_value(t, header.segment_sizes[1], u32(200))
}

@(test)
test_deserialize_frame_header_truncated :: proc(t: ^testing.T) {
	// Incomplete header
	data := [?]byte{0x00, 0x00}

	_, _, err := capnp.deserialize_frame_header(data[:])
	testing.expect_value(t, err, capnp.Error.Unexpected_End_Of_Input)
}

@(test)
test_deserialize_frame_header_too_many_segments :: proc(t: ^testing.T) {
	// Claim 600 segments (>512 limit)
	data := [?]byte{
		0x57, 0x02, 0x00, 0x00, // segment count - 1 = 599
	}

	_, _, err := capnp.deserialize_frame_header(data[:])
	testing.expect_value(t, err, capnp.Error.Segment_Count_Overflow)
}

@(test)
test_deserialize_frame_header_segment_size_overflow :: proc(t: ^testing.T) {
	// Segment with size just under limit (0x0FFFFFFF = 268435455, under 2^28)
	data := [?]byte{
		0x00, 0x00, 0x00, 0x00, // segment count - 1 = 0
		0xFF, 0xFF, 0xFF, 0x0F, // segment size = 0x0FFFFFFF (valid, under limit)
	}

	header, _, err := capnp.deserialize_frame_header(data[:])
	defer capnp.frame_header_destroy(&header)
	testing.expect_value(t, err, capnp.Error.None)

	// Now with invalid size (> 2^28 = 0x10000000)
	data2 := [?]byte{
		0x00, 0x00, 0x00, 0x00, // segment count - 1 = 0
		0x00, 0x00, 0x00, 0x20, // segment size = 0x20000000 (over limit)
	}

	_, _, err2 := capnp.deserialize_frame_header(data2[:])
	testing.expect_value(t, err2, capnp.Error.Segment_Size_Overflow)
}

// ============================================================================
// Frame Header Roundtrip Tests
// ============================================================================

@(test)
test_frame_header_roundtrip_single :: proc(t: ^testing.T) {
	original_sizes := []u32{256}
	buffer: [16]byte

	bytes_written, ser_err := capnp.serialize_frame_header(original_sizes, buffer[:])
	testing.expect_value(t, ser_err, capnp.Error.None)

	header, bytes_read, deser_err := capnp.deserialize_frame_header(buffer[:bytes_written])
	defer capnp.frame_header_destroy(&header)

	testing.expect_value(t, deser_err, capnp.Error.None)
	testing.expect_value(t, bytes_read, bytes_written)
	testing.expect_value(t, header.segment_count, u32(1))
	testing.expect_value(t, header.segment_sizes[0], u32(256))
}

@(test)
test_frame_header_roundtrip_multi :: proc(t: ^testing.T) {
	original_sizes := []u32{100, 200, 300, 400}
	buffer: [32]byte

	bytes_written, ser_err := capnp.serialize_frame_header(original_sizes, buffer[:])
	testing.expect_value(t, ser_err, capnp.Error.None)

	header, bytes_read, deser_err := capnp.deserialize_frame_header(buffer[:bytes_written])
	defer capnp.frame_header_destroy(&header)

	testing.expect_value(t, deser_err, capnp.Error.None)
	testing.expect_value(t, bytes_read, bytes_written)
	testing.expect_value(t, header.segment_count, u32(4))

	for i in 0 ..< 4 {
		testing.expect_value(t, header.segment_sizes[i], original_sizes[i])
	}
}

@(test)
test_frame_header_roundtrip_max_size :: proc(t: ^testing.T) {
	// Large segment size (under the limit)
	original_sizes := []u32{0x0FFF_FFFF} // ~268 million words
	buffer: [16]byte

	bytes_written, ser_err := capnp.serialize_frame_header(original_sizes, buffer[:])
	testing.expect_value(t, ser_err, capnp.Error.None)

	header, _, deser_err := capnp.deserialize_frame_header(buffer[:bytes_written])
	defer capnp.frame_header_destroy(&header)

	testing.expect_value(t, deser_err, capnp.Error.None)
	testing.expect_value(t, header.segment_sizes[0], u32(0x0FFF_FFFF))
}

// ============================================================================
// Memory Management Tests
// ============================================================================

@(test)
test_frame_header_destroy :: proc(t: ^testing.T) {
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)

	alloc := mem.tracking_allocator(&tracking)

	data := [?]byte{
		0x02, 0x00, 0x00, 0x00, // 3 segments
		0x64, 0x00, 0x00, 0x00,
		0xC8, 0x00, 0x00, 0x00,
		0x32, 0x00, 0x00, 0x00,
	}

	{
		header, _, err := capnp.deserialize_frame_header(data[:], alloc)
		testing.expect_value(t, err, capnp.Error.None)
		capnp.frame_header_destroy(&header, alloc)
	}

	testing.expect_value(t, len(tracking.allocation_map), 0)
}
