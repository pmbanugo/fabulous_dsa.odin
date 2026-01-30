package capnp

import "core:mem"
import "core:slice"

// Default segment size in words (8KB = 1024 words)
DEFAULT_SEGMENT_SIZE :: 1024

// A segment is a contiguous block of words
Segment :: struct {
	id:       u32,      // segment ID within message
	data:     []Word,   // backing storage (allocated via allocator)
	used:     u32,      // words currently used
	capacity: u32,      // total words available
}

// Manages multiple segments for a message
Segment_Manager :: struct {
	segments:         [dynamic]Segment,
	allocator:        mem.Allocator,
	default_seg_size: u32,
}

// Initialize a segment manager with the given allocator
// If no allocator is provided, uses context.allocator (Odin idiom)
segment_manager_init :: proc(
	sm: ^Segment_Manager,
	default_size: u32 = DEFAULT_SEGMENT_SIZE,
	allocator := context.allocator,
) {
	sm.allocator = allocator
	sm.default_seg_size = default_size
	sm.segments = make([dynamic]Segment, allocator)
}

// Destroy a segment manager and free all segment memory
segment_manager_destroy :: proc(sm: ^Segment_Manager) {
	for &seg in sm.segments {
		if seg.data != nil {
			delete(seg.data, sm.allocator)
		}
	}
	delete(sm.segments)
	sm^ = {}
}

// Clear the segment manager for reuse (keeps first segment's capacity, resets used)
segment_manager_clear :: proc(sm: ^Segment_Manager) {
	if len(sm.segments) == 0 {
		return
	}
	
	// Free all segments except the first
	for i := 1; i < len(sm.segments); i += 1 {
		if sm.segments[i].data != nil {
			delete(sm.segments[i].data, sm.allocator)
		}
	}
	resize(&sm.segments, 1)
	
	// Reset first segment
	sm.segments[0].used = 0
	slice.zero(sm.segments[0].data)
}

// Allocate words from the segment manager
// Creates a new segment if current segments don't have enough space
// Returns segment ID and word offset within that segment
segment_manager_allocate :: proc(
	sm: ^Segment_Manager,
	words: u32,
) -> (segment_id: u32, offset: u32, err: Error) {
	// Try to allocate from the last segment first
	if len(sm.segments) > 0 {
		last := &sm.segments[len(sm.segments) - 1]
		if alloc_offset, ok := segment_allocate(last, words); ok {
			return last.id, alloc_offset, .None
		}
	}

	// Need a new segment
	seg_size := max(words, sm.default_seg_size)
	seg, alloc_err := segment_create(u32(len(sm.segments)), seg_size, sm.allocator)
	if alloc_err != .None {
		return 0, 0, alloc_err
	}

	append(&sm.segments, seg)
	offset, _ = segment_allocate(&sm.segments[len(sm.segments) - 1], words)
	return seg.id, offset, .None
}

// Get a segment by ID
segment_manager_get_segment :: proc(sm: ^Segment_Manager, id: u32) -> ^Segment {
	if id < u32(len(sm.segments)) {
		return &sm.segments[id]
	}
	return nil
}

// Get the number of segments
segment_manager_segment_count :: proc(sm: ^Segment_Manager) -> u32 {
	return u32(len(sm.segments))
}

// Create a new segment with the given capacity
segment_create :: proc(
	id: u32,
	capacity: u32,
	allocator: mem.Allocator,
) -> (seg: Segment, err: Error) {
	data, alloc_err := make([]Word, capacity, allocator)
	if alloc_err != nil {
		return {}, .Out_Of_Memory
	}
	return Segment{
		id       = id,
		data     = data,
		used     = 0,
		capacity = capacity,
	}, .None
}

// Allocate words within a segment
// Returns the offset where allocation starts, or false if segment is full
segment_allocate :: proc(seg: ^Segment, words: u32) -> (offset: u32, ok: bool) {
	// Use subtraction to avoid overflow: words > (capacity - used)
	if words > seg.capacity - seg.used {
		return 0, false
	}
	offset = seg.used
	seg.used += words
	return offset, true
}

// Get word at offset within segment
segment_get_word :: proc(seg: ^Segment, offset: u32) -> (word: Word, ok: bool) {
	if offset >= seg.used {
		return 0, false
	}
	return seg.data[offset], true
}

// Set word at offset within segment
segment_set_word :: proc(seg: ^Segment, offset: u32, word: Word) -> bool {
	if offset >= seg.capacity {
		return false
	}
	seg.data[offset] = word
	return true
}

// Get byte slice at word offset within segment
// Returns a slice of bytes starting at the given word offset
segment_get_bytes :: proc(seg: ^Segment, word_offset: u32, byte_count: u32) -> (data: []byte, ok: bool) {
	// Check bounds
	words_needed := (byte_count + WORD_SIZE_BYTES - 1) / WORD_SIZE_BYTES
	if word_offset + words_needed > seg.used {
		return nil, false
	}
	
	// Convert word slice to byte slice
	word_slice := seg.data[word_offset:]
	byte_slice := slice.to_bytes(word_slice)
	
	if byte_count > u32(len(byte_slice)) {
		return nil, false
	}
	
	return byte_slice[:byte_count], true
}

// Get the raw data slice for a segment (for serialization)
segment_get_data :: proc(seg: ^Segment) -> []Word {
	return seg.data[:seg.used]
}
