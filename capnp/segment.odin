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
	segments:             [dynamic]Segment,
	allocator:            mem.Allocator,
	default_segment_size: u32,
}

// Initialize a segment manager with the given allocator
// If no allocator is provided, uses context.allocator (Odin idiom)
segment_manager_init :: proc(
	manager: ^Segment_Manager,
	default_size: u32 = DEFAULT_SEGMENT_SIZE,
	allocator := context.allocator,
) {
	manager.allocator = allocator
	manager.default_segment_size = default_size
	manager.segments = make([dynamic]Segment, allocator)
}

// Destroy a segment manager and free all segment memory
segment_manager_destroy :: proc(manager: ^Segment_Manager) {
	for &segment in manager.segments {
		if segment.data != nil {
			delete(segment.data, manager.allocator)
		}
	}
	delete(manager.segments)
	manager^ = {}
}

// Clear the segment manager for reuse (keeps first segment's capacity, resets used)
segment_manager_clear :: proc(manager: ^Segment_Manager) {
	if len(manager.segments) == 0 {
		return
	}
	
	// Free all segments except the first
	for i := 1; i < len(manager.segments); i += 1 {
		if manager.segments[i].data != nil {
			delete(manager.segments[i].data, manager.allocator)
		}
	}
	resize(&manager.segments, 1)
	
	// Reset first segment
	manager.segments[0].used = 0
	slice.zero(manager.segments[0].data)
}

// Allocate words from the segment manager
// Creates a new segment if current segments don't have enough space
// Returns segment ID and word offset within that segment
segment_manager_allocate :: proc(
	manager: ^Segment_Manager,
	words: u32,
) -> (segment_id: u32, offset: u32, err: Error) {
	// Try to allocate from the last segment first
	if len(manager.segments) > 0 {
		last := &manager.segments[len(manager.segments) - 1]
		if allocation_offset, ok := segment_allocate(last, words); ok {
			return last.id, allocation_offset, .None
		}
	}

	// Need a new segment
	new_segment_size := max(words, manager.default_segment_size)
	new_segment, allocation_error := segment_create(u32(len(manager.segments)), new_segment_size, manager.allocator)
	if allocation_error != .None {
		return 0, 0, allocation_error
	}

	append(&manager.segments, new_segment)
	offset, _ = segment_allocate(&manager.segments[len(manager.segments) - 1], words)
	return new_segment.id, offset, .None
}

// Get a segment by ID
segment_manager_get_segment :: proc(manager: ^Segment_Manager, id: u32) -> ^Segment {
	if id < u32(len(manager.segments)) {
		return &manager.segments[id]
	}
	return nil
}

// Get the number of segments
segment_manager_segment_count :: proc(manager: ^Segment_Manager) -> u32 {
	return u32(len(manager.segments))
}

// Create a new segment with the given capacity
segment_create :: proc(
	id: u32,
	capacity: u32,
	allocator: mem.Allocator,
) -> (segment: Segment, err: Error) {
	data, allocation_error := make([]Word, capacity, allocator)
	if allocation_error != nil {
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
segment_allocate :: proc(segment: ^Segment, words: u32) -> (offset: u32, ok: bool) {
	// Use subtraction to avoid overflow: words > (capacity - used)
	if words > segment.capacity - segment.used {
		return 0, false
	}
	offset = segment.used
	segment.used += words
	return offset, true
}

// Get word at offset within segment
segment_get_word :: proc(segment: ^Segment, offset: u32) -> (word: Word, ok: bool) {
	if offset >= segment.used {
		return 0, false
	}
	return segment.data[offset], true
}

// Set word at offset within segment
segment_set_word :: proc(segment: ^Segment, offset: u32, word: Word) -> bool {
	if offset >= segment.capacity {
		return false
	}
	segment.data[offset] = word
	return true
}

// Get byte slice at word offset within segment
// Returns a slice of bytes starting at the given word offset
segment_get_bytes :: proc(segment: ^Segment, word_offset: u32, byte_count: u32) -> (data: []byte, ok: bool) {
	// Check bounds
	words_needed := (byte_count + WORD_SIZE_BYTES - 1) / WORD_SIZE_BYTES
	if word_offset + words_needed > segment.used {
		return nil, false
	}
	
	// Convert word slice to byte slice
	word_slice := segment.data[word_offset:]
	byte_slice := slice.to_bytes(word_slice)
	
	if byte_count > u32(len(byte_slice)) {
		return nil, false
	}
	
	return byte_slice[:byte_count], true
}

// Get the raw data slice for a segment (for serialization)
segment_get_data :: proc(segment: ^Segment) -> []Word {
	return segment.data[:segment.used]
}
