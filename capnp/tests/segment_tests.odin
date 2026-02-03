package capnp_tests

import capnp ".."
import "core:mem"
import "core:testing"

// ============================================================================
// Segment Manager Initialization Tests
// ============================================================================

@(test)
test_segment_manager_init_destroy :: proc(t: ^testing.T) {
	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm)
	defer capnp.segment_manager_destroy(&sm)

	testing.expect_value(t, capnp.segment_manager_segment_count(&sm), u32(0))
}

@(test)
test_segment_manager_init_custom_size :: proc(t: ^testing.T) {
	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm, 64) // 64 words default segment size
	defer capnp.segment_manager_destroy(&sm)

	// Allocate to trigger segment creation
	_, _, err := capnp.segment_manager_allocate(&sm, 10)
	testing.expect_value(t, err, capnp.Error.None)

	seg := capnp.segment_manager_get_segment(&sm, 0)
	testing.expect_value(t, seg.capacity, u32(64))
}

@(test)
test_segment_manager_with_tracking_allocator :: proc(t: ^testing.T) {
	// Use tracking allocator to verify no leaks
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)

	alloc := mem.tracking_allocator(&tracking)

	{
		sm: capnp.Segment_Manager
		capnp.segment_manager_init(&sm, 128, alloc)
		defer capnp.segment_manager_destroy(&sm)

		// Allocate some data
		_, _, err := capnp.segment_manager_allocate(&sm, 50)
		testing.expect_value(t, err, capnp.Error.None)
	}

	// Check for leaks
	testing.expect_value(t, len(tracking.allocation_map), 0)
	testing.expect_value(t, len(tracking.bad_free_array), 0)
}

// ============================================================================
// Single Segment Allocation Tests
// ============================================================================

@(test)
test_segment_single_allocation :: proc(t: ^testing.T) {
	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm)
	defer capnp.segment_manager_destroy(&sm)

	seg_id, offset, err := capnp.segment_manager_allocate(&sm, 5)
	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, seg_id, u32(0))
	testing.expect_value(t, offset, u32(0))
	testing.expect_value(t, capnp.segment_manager_segment_count(&sm), u32(1))
}

@(test)
test_segment_sequential_allocations :: proc(t: ^testing.T) {
	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm)
	defer capnp.segment_manager_destroy(&sm)

	// First allocation
	seg_id1, offset1, err1 := capnp.segment_manager_allocate(&sm, 5)
	testing.expect_value(t, err1, capnp.Error.None)
	testing.expect_value(t, seg_id1, u32(0))
	testing.expect_value(t, offset1, u32(0))

	// Second allocation (should follow first)
	seg_id2, offset2, err2 := capnp.segment_manager_allocate(&sm, 3)
	testing.expect_value(t, err2, capnp.Error.None)
	testing.expect_value(t, seg_id2, u32(0))
	testing.expect_value(t, offset2, u32(5))

	// Third allocation
	seg_id3, offset3, err3 := capnp.segment_manager_allocate(&sm, 10)
	testing.expect_value(t, err3, capnp.Error.None)
	testing.expect_value(t, seg_id3, u32(0))
	testing.expect_value(t, offset3, u32(8))
}

// ============================================================================
// Multi-Segment Allocation Tests
// ============================================================================

@(test)
test_segment_allocation_new_segment :: proc(t: ^testing.T) {
	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm, 10) // Small segments for testing
	defer capnp.segment_manager_destroy(&sm)

	// Fill first segment
	seg_id1, offset1, err1 := capnp.segment_manager_allocate(&sm, 8)
	testing.expect_value(t, err1, capnp.Error.None)
	testing.expect_value(t, seg_id1, u32(0))
	testing.expect_value(t, offset1, u32(0))

	// This should overflow to a new segment
	seg_id2, offset2, err2 := capnp.segment_manager_allocate(&sm, 8)
	testing.expect_value(t, err2, capnp.Error.None)
	testing.expect_value(t, seg_id2, u32(1))
	testing.expect_value(t, offset2, u32(0))

	testing.expect_value(t, capnp.segment_manager_segment_count(&sm), u32(2))
}

@(test)
test_segment_allocation_larger_than_default :: proc(t: ^testing.T) {
	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm, 10) // 10 word segments
	defer capnp.segment_manager_destroy(&sm)

	// Allocate more than default segment size
	seg_id, offset, err := capnp.segment_manager_allocate(&sm, 20)
	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, seg_id, u32(0))
	testing.expect_value(t, offset, u32(0))

	// Segment should be sized to fit the allocation
	seg := capnp.segment_manager_get_segment(&sm, 0)
	testing.expect(t, seg.capacity >= 20, "Segment should be large enough")
}

// ============================================================================
// Segment Capacity Tracking Tests
// ============================================================================

@(test)
test_segment_capacity_tracking :: proc(t: ^testing.T) {
	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm, 100)
	defer capnp.segment_manager_destroy(&sm)

	// Allocate 30 words
	_, _, _ = capnp.segment_manager_allocate(&sm, 30)
	seg := capnp.segment_manager_get_segment(&sm, 0)
	testing.expect_value(t, seg.used, u32(30))
	testing.expect_value(t, seg.capacity, u32(100))

	// Allocate 20 more
	_, _, _ = capnp.segment_manager_allocate(&sm, 20)
	testing.expect_value(t, seg.used, u32(50))

	// Allocate remaining 50
	_, _, _ = capnp.segment_manager_allocate(&sm, 50)
	testing.expect_value(t, seg.used, u32(100))
}

@(test)
test_segment_manager_clear :: proc(t: ^testing.T) {
	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm, 50)
	defer capnp.segment_manager_destroy(&sm)

	// Create multiple segments
	_, _, _ = capnp.segment_manager_allocate(&sm, 40)
	_, _, _ = capnp.segment_manager_allocate(&sm, 40) // Forces new segment
	testing.expect_value(t, capnp.segment_manager_segment_count(&sm), u32(2))

	// Clear should reset to one empty segment
	capnp.segment_manager_clear(&sm)
	testing.expect_value(t, capnp.segment_manager_segment_count(&sm), u32(1))

	seg := capnp.segment_manager_get_segment(&sm, 0)
	testing.expect_value(t, seg.used, u32(0))
}

// ============================================================================
// Word Get/Set Operations Tests
// ============================================================================

@(test)
test_segment_word_get_set :: proc(t: ^testing.T) {
	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm)
	defer capnp.segment_manager_destroy(&sm)

	seg_id, offset, _ := capnp.segment_manager_allocate(&sm, 5)
	seg := capnp.segment_manager_get_segment(&sm, seg_id)

	// Write words
	testing.expect(t, capnp.segment_set_word(seg, offset + 0, 0xDEAD_BEEF), "Set word 0")
	testing.expect(t, capnp.segment_set_word(seg, offset + 1, 0xCAFE_BABE), "Set word 1")
	testing.expect(t, capnp.segment_set_word(seg, offset + 2, 0x1234_5678_9ABC_DEF0), "Set word 2")

	// Read back
	w0, ok0 := capnp.segment_get_word(seg, offset + 0)
	testing.expect(t, ok0, "Get word 0")
	testing.expect_value(t, w0, capnp.Word(0xDEAD_BEEF))

	w1, ok1 := capnp.segment_get_word(seg, offset + 1)
	testing.expect(t, ok1, "Get word 1")
	testing.expect_value(t, w1, capnp.Word(0xCAFE_BABE))

	w2, ok2 := capnp.segment_get_word(seg, offset + 2)
	testing.expect(t, ok2, "Get word 2")
	testing.expect_value(t, w2, capnp.Word(0x1234_5678_9ABC_DEF0))
}

@(test)
test_segment_word_get_out_of_bounds :: proc(t: ^testing.T) {
	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm)
	defer capnp.segment_manager_destroy(&sm)

	_, _, _ = capnp.segment_manager_allocate(&sm, 3)
	seg := capnp.segment_manager_get_segment(&sm, 0)

	// Try to read beyond used portion
	_, ok := capnp.segment_get_word(seg, 5)
	testing.expect(t, !ok, "Should fail for out-of-bounds read")
}

@(test)
test_segment_get_bytes :: proc(t: ^testing.T) {
	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm)
	defer capnp.segment_manager_destroy(&sm)

	_, _, _ = capnp.segment_manager_allocate(&sm, 2)
	seg := capnp.segment_manager_get_segment(&sm, 0)

	// Set a known pattern
	capnp.segment_set_word(seg, 0, 0x0807_0605_0403_0201)
	capnp.segment_set_word(seg, 1, 0x100F_0E0D_0C0B_0A09)

	// Get bytes
	bytes, ok := capnp.segment_get_bytes(seg, 0, 10)
	testing.expect(t, ok, "Should get bytes")
	testing.expect_value(t, len(bytes), 10)

	// Verify little-endian byte order
	testing.expect_value(t, bytes[0], u8(0x01))
	testing.expect_value(t, bytes[1], u8(0x02))
	testing.expect_value(t, bytes[7], u8(0x08))
	testing.expect_value(t, bytes[8], u8(0x09))
	testing.expect_value(t, bytes[9], u8(0x0A))
}

@(test)
test_segment_get_segment_invalid_id :: proc(t: ^testing.T) {
	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm)
	defer capnp.segment_manager_destroy(&sm)

	// No segments exist yet
	seg := capnp.segment_manager_get_segment(&sm, 0)
	testing.expect(t, seg == nil, "Should return nil for invalid segment ID")

	seg2 := capnp.segment_manager_get_segment(&sm, 999)
	testing.expect(t, seg2 == nil, "Should return nil for non-existent segment")
}

// ============================================================================
// Arena Allocator Tests
// ============================================================================

@(test)
test_segment_manager_with_arena :: proc(t: ^testing.T) {
	// Allocate enough for segment manager + segment data
	arena_buffer: [16 * 1024]byte
	arena: mem.Arena
	mem.arena_init(&arena, arena_buffer[:])
	arena_allocator := mem.arena_allocator(&arena)

	sm: capnp.Segment_Manager
	capnp.segment_manager_init(&sm, 128, arena_allocator)

	// Allocate some words
	seg_id, offset, err := capnp.segment_manager_allocate(&sm, 50)
	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, seg_id, u32(0))
	testing.expect_value(t, offset, u32(0))

	// Write and verify data
	seg := capnp.segment_manager_get_segment(&sm, 0)
	capnp.segment_set_word(seg, 0, 0x12345678)

	word, ok := capnp.segment_get_word(seg, 0)
	testing.expect(t, ok, "Should get word")
	testing.expect_value(t, word, capnp.Word(0x12345678))

	// Note: Arena doesn't need explicit cleanup - just let it go out of scope
	// But we still call destroy for consistency
	capnp.segment_manager_destroy(&sm)
}
