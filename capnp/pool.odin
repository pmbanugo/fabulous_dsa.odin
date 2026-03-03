package capnp

import "core:mem"
import "core:slice"

// Maximum segments to keep in the pool
MAX_POOL_SIZE :: 16

// Segment_Pool recycles segments to avoid repeated allocation
Segment_Pool :: struct {
	free_segments: [dynamic]Segment,
	segment_size:  u32,
	allocator:     mem.Allocator,
}

segment_pool_init :: proc(pool: ^Segment_Pool, size: u32 = DEFAULT_SEGMENT_SIZE, allocator := context.allocator) {
	pool.segment_size = size
	pool.allocator = allocator
	pool.free_segments = make([dynamic]Segment, allocator)
}

segment_pool_destroy :: proc(pool: ^Segment_Pool) {
	for &seg in pool.free_segments {
		if seg.data != nil {
			delete(seg.data, pool.allocator)
		}
	}
	delete(pool.free_segments)
	pool^ = {}
}

// Get a segment from the pool or allocate a new one
segment_pool_acquire :: proc(pool: ^Segment_Pool, id: u32) -> (segment: Segment, err: Error) {
	if len(pool.free_segments) > 0 {
		seg := pop(&pool.free_segments)
		seg.id = id
		seg.used = 0
		slice.zero(seg.data)
		return seg, .None
	}
	return segment_create(id, pool.segment_size, pool.allocator)
}

// Return a segment to the pool for reuse
segment_pool_release :: proc(pool: ^Segment_Pool, seg: ^Segment) {
	if seg.capacity == pool.segment_size && len(pool.free_segments) < MAX_POOL_SIZE {
		append(&pool.free_segments, seg^)
	} else {
		if seg.data != nil {
			delete(seg.data, pool.allocator)
		}
	}
	seg^ = {}
}

segment_pool_count :: proc(pool: ^Segment_Pool) -> int {
	return len(pool.free_segments)
}

// ============================================================================
// Pooled Message Builder
// ============================================================================

Pooled_Message_Builder :: struct {
	segments: Segment_Manager,
	pool:     ^Segment_Pool,
}

pooled_message_builder_init :: proc(
	pmb: ^Pooled_Message_Builder,
	pool: ^Segment_Pool,
) -> (res: ^Pooled_Message_Builder, err: Error) {
	pmb.pool = pool
	segment_manager_init(&pmb.segments, pool.segment_size, pool.allocator)

	// Acquire first segment from pool to avoid heap allocation
	first_seg: Segment
	first_seg, err = segment_pool_acquire(pool, 0)
	if err != .None {
		return pmb, err
	}
	append(&pmb.segments.segments, first_seg)

	return pmb, .None
}

pooled_message_builder_destroy :: proc(pmb: ^Pooled_Message_Builder) {
	for &seg in pmb.segments.segments {
		segment_pool_release(pmb.pool, &seg)
	}
	delete(pmb.segments.segments)
	pmb.segments = {}
}

// Initialize the root struct of a pooled message
pooled_message_builder_init_root :: proc(
	pmb: ^Pooled_Message_Builder,
	data_words: u16,
	pointer_count: u16,
) -> (sb: Struct_Builder, err: Error) {
	return init_root_on_manager(&pmb.segments, data_words, pointer_count)
}

// Get segment data for serialization (returns slice of used words per segment)
pooled_message_builder_get_segments :: proc(pmb: ^Pooled_Message_Builder) -> [][]Word {
	count := segment_manager_segment_count(&pmb.segments)
	if count == 0 {
		return nil
	}
	result := make([][]Word, count, pmb.pool.allocator)
	for i in 0 ..< count {
		seg := segment_manager_get_segment(&pmb.segments, i)
		result[i] = segment_get_data(seg)
	}
	return result
}

pooled_message_builder_clear :: proc(pmb: ^Pooled_Message_Builder) {
	// Return extra segments to pool, keep first one
	for i := len(pmb.segments.segments) - 1; i > 0; i -= 1 {
		segment_pool_release(pmb.pool, &pmb.segments.segments[i])
	}
	if len(pmb.segments.segments) > 0 {
		resize(&pmb.segments.segments, 1)
		pmb.segments.segments[0].used = 0
		slice.zero(pmb.segments.segments[0].data)
	}
}
