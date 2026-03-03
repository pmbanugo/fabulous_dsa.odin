package capnp_tests

import "base:intrinsics"
import capnp ".."
import "core:testing"

// ============================================================================
// SIMD Tag Computation Tests
// ============================================================================

@(test)
test_compute_tag_simd :: proc(t: ^testing.T) {
	word1 := [8]u8{0, 0, 0, 0, 0, 0, 0, 0}
	testing.expect_value(t, capnp.compute_tag_simd(&word1), u8(0x00))

	word2 := [8]u8{1, 2, 3, 4, 5, 6, 7, 8}
	testing.expect_value(t, capnp.compute_tag_simd(&word2), u8(0xFF))

	word3 := [8]u8{1, 0, 0, 0, 0, 0, 0, 0}
	testing.expect_value(t, capnp.compute_tag_simd(&word3), u8(0x01))

	word4 := [8]u8{0, 0, 0, 0, 0, 0, 0, 1}
	testing.expect_value(t, capnp.compute_tag_simd(&word4), u8(0x80))

	word5 := [8]u8{1, 0, 1, 0, 1, 0, 1, 0}
	testing.expect_value(t, capnp.compute_tag_simd(&word5), u8(0x55))
}

// ============================================================================
// Fast Zero Word Check Tests
// ============================================================================

@(test)
test_is_zero_word_simd :: proc(t: ^testing.T) {
	zero: u64 = 0
	testing.expect(t, capnp.is_zero_word_simd(&zero), "Zero word should return true")

	nonzero: u64 = 1
	testing.expect(t, !capnp.is_zero_word_simd(&nonzero), "Non-zero word should return false")

	big: u64 = 0xFFFFFFFFFFFFFFFF
	testing.expect(t, !capnp.is_zero_word_simd(&big), "All-ones word should return false")
}

// ============================================================================
// Hardware Popcount Tests
// ============================================================================

@(test)
test_hardware_popcount :: proc(t: ^testing.T) {
	testing.expect_value(t, int(intrinsics.count_ones(u8(0x00))), 0)
	testing.expect_value(t, int(intrinsics.count_ones(u8(0x01))), 1)
	testing.expect_value(t, int(intrinsics.count_ones(u8(0x03))), 2)
	testing.expect_value(t, int(intrinsics.count_ones(u8(0x0F))), 4)
	testing.expect_value(t, int(intrinsics.count_ones(u8(0xFF))), 8)
	testing.expect_value(t, int(intrinsics.count_ones(u8(0x55))), 4)
	testing.expect_value(t, int(intrinsics.count_ones(u8(0xAA))), 4)
	testing.expect_value(t, int(intrinsics.count_ones(u8(0x80))), 1)
}



// ============================================================================
// Segment Pool Tests
// ============================================================================

@(test)
test_segment_pool_acquire_release :: proc(t: ^testing.T) {
	pool: capnp.Segment_Pool
	capnp.segment_pool_init(&pool)
	defer capnp.segment_pool_destroy(&pool)

	testing.expect_value(t, capnp.segment_pool_count(&pool), 0)

	seg, err := capnp.segment_pool_acquire(&pool, 0)
	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, seg.id, u32(0))
	testing.expect_value(t, seg.used, u32(0))
	testing.expect(t, seg.data != nil, "Segment data should be allocated")

	capnp.segment_pool_release(&pool, &seg)
	testing.expect_value(t, capnp.segment_pool_count(&pool), 1)

	seg2, err2 := capnp.segment_pool_acquire(&pool, 1)
	testing.expect_value(t, err2, capnp.Error.None)
	testing.expect_value(t, seg2.id, u32(1))
	testing.expect_value(t, seg2.used, u32(0))
	testing.expect_value(t, capnp.segment_pool_count(&pool), 0)

	capnp.segment_pool_release(&pool, &seg2)
}

@(test)
test_segment_pool_max_size :: proc(t: ^testing.T) {
	pool: capnp.Segment_Pool
	capnp.segment_pool_init(&pool)
	defer capnp.segment_pool_destroy(&pool)

	for i in 0 ..< capnp.MAX_POOL_SIZE + 5 {
		seg, _ := capnp.segment_pool_acquire(&pool, u32(i))
		capnp.segment_pool_release(&pool, &seg)
	}

	testing.expect(t, capnp.segment_pool_count(&pool) <= capnp.MAX_POOL_SIZE,
		"Pool should respect MAX_POOL_SIZE limit")
}

@(test)
test_segment_pool_released_data_zeroed :: proc(t: ^testing.T) {
	pool: capnp.Segment_Pool
	capnp.segment_pool_init(&pool)
	defer capnp.segment_pool_destroy(&pool)

	seg, _ := capnp.segment_pool_acquire(&pool, 0)
	capnp.segment_set_word(&seg, 0, 0xDEADBEEF)
	seg.used = 1
	capnp.segment_pool_release(&pool, &seg)

	seg2, _ := capnp.segment_pool_acquire(&pool, 0)
	testing.expect(t, seg2.data[0] == 0, "Re-acquired segment data should be zeroed")
	testing.expect_value(t, seg2.used, u32(0))
	capnp.segment_pool_release(&pool, &seg2)
}

// ============================================================================
// Pooled Message Builder Tests
// ============================================================================

@(test)
test_pooled_message_builder :: proc(t: ^testing.T) {
	pool: capnp.Segment_Pool
	capnp.segment_pool_init(&pool)
	defer capnp.segment_pool_destroy(&pool)

	pmb: capnp.Pooled_Message_Builder
	capnp.pooled_message_builder_init(&pmb, &pool)

	seg_id, offset, err := capnp.segment_manager_allocate(&pmb.segments, 3)
	testing.expect_value(t, err, capnp.Error.None)

	capnp.pooled_message_builder_destroy(&pmb)
	testing.expect(t, capnp.segment_pool_count(&pool) > 0,
		"Destroyed builder should return segments to pool")
}

@(test)
test_pooled_message_builder_clear :: proc(t: ^testing.T) {
	pool: capnp.Segment_Pool
	capnp.segment_pool_init(&pool)
	defer capnp.segment_pool_destroy(&pool)

	pmb: capnp.Pooled_Message_Builder
	capnp.pooled_message_builder_init(&pmb, &pool)

	capnp.segment_manager_allocate(&pmb.segments, 3)

	capnp.pooled_message_builder_clear(&pmb)

	if len(pmb.segments.segments) > 0 {
		testing.expect_value(t, pmb.segments.segments[0].used, u32(0))
	}

	capnp.pooled_message_builder_destroy(&pmb)
}

@(test)
test_pooled_message_builder_init_root :: proc(t: ^testing.T) {
	pool: capnp.Segment_Pool
	capnp.segment_pool_init(&pool)
	defer capnp.segment_pool_destroy(&pool)

	pmb: capnp.Pooled_Message_Builder
	capnp.pooled_message_builder_init(&pmb, &pool)

	root, err := capnp.pooled_message_builder_init_root(&pmb, 2, 0)
	testing.expect_value(t, err, capnp.Error.None)

	capnp.struct_builder_set_u32(&root, 0, 42)
	capnp.struct_builder_set_u64(&root, 8, 9876543210)

	testing.expect(t, len(pmb.segments.segments) > 0, "Should have at least one segment")
	testing.expect(t, pmb.segments.segments[0].used > 0, "Segment should have used words")

	capnp.pooled_message_builder_destroy(&pmb)
}

@(test)
test_pooled_message_builder_full_roundtrip :: proc(t: ^testing.T) {
	pool: capnp.Segment_Pool
	capnp.segment_pool_init(&pool)
	defer capnp.segment_pool_destroy(&pool)

	// Build a message with primitives, nested struct, and text
	pmb: capnp.Pooled_Message_Builder
	capnp.pooled_message_builder_init(&pmb, &pool)

	root, root_err := capnp.pooled_message_builder_init_root(&pmb, 2, 2)
	testing.expect_value(t, root_err, capnp.Error.None)

	capnp.struct_builder_set_u32(&root, 0, 42)
	capnp.struct_builder_set_u64(&root, 8, 1234567890)

	child, child_err := capnp.struct_builder_init_struct(&root, 0, 1, 0)
	testing.expect_value(t, child_err, capnp.Error.None)
	capnp.struct_builder_set_u64(&child, 0, 999)

	text_err := capnp.struct_builder_set_text(&root, 1, "Hello")
	testing.expect_value(t, text_err, capnp.Error.None)

	// Serialize via segment manager
	serialized, ser_err := capnp.serialize_segments(&pmb.segments)
	testing.expect_value(t, ser_err, capnp.Error.None)
	defer delete(serialized)

	// Deserialize and verify
	reader, deser_err := capnp.deserialize(serialized)
	testing.expect_value(t, deser_err, capnp.Error.None)
	defer capnp.message_reader_destroy(&reader)

	sr, get_err := capnp.message_reader_get_root(&reader)
	testing.expect_value(t, get_err, capnp.Error.None)

	testing.expect_value(t, capnp.struct_reader_get_u32(&sr, 0), u32(42))
	testing.expect_value(t, capnp.struct_reader_get_u64(&sr, 8), u64(1234567890))

	child_reader, child_read_err := capnp.struct_reader_get_struct(&sr, 0)
	testing.expect_value(t, child_read_err, capnp.Error.None)
	testing.expect_value(t, capnp.struct_reader_get_u64(&child_reader, 0), u64(999))

	text, text_read_err := capnp.struct_reader_get_text(&sr, 1)
	testing.expect_value(t, text_read_err, capnp.Error.None)
	testing.expect_value(t, text, "Hello")

	capnp.pooled_message_builder_destroy(&pmb)
}

@(test)
test_pooled_message_builder_get_segments :: proc(t: ^testing.T) {
	pool: capnp.Segment_Pool
	capnp.segment_pool_init(&pool)
	defer capnp.segment_pool_destroy(&pool)

	pmb: capnp.Pooled_Message_Builder
	capnp.pooled_message_builder_init(&pmb, &pool)

	root, _ := capnp.pooled_message_builder_init_root(&pmb, 1, 0)
	capnp.struct_builder_set_u32(&root, 0, 77)

	segs := capnp.pooled_message_builder_get_segments(&pmb)
	defer delete(segs)
	testing.expect(t, len(segs) > 0, "Should return at least one segment")
	testing.expect(t, len(segs[0]) > 0, "First segment should have data")

	capnp.pooled_message_builder_destroy(&pmb)
}
