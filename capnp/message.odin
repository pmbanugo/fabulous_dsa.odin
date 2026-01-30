package capnp

import "core:slice"

// Frame header for serialized messages
// Contains segment count and sizes for stream framing
Frame_Header :: struct {
	segment_count: u32,        // number of segments (stored as count-1 in wire format)
	segment_sizes: []u32,      // size of each segment in words
}

// Calculate the size of a frame header in bytes
// Format: (4 bytes segment count-1) + (4 bytes × N segment sizes) + (0 or 4 bytes padding)
frame_header_size :: proc(segment_count: u32) -> u32 {
	// 4 bytes for segment count
	// 4 bytes per segment size
	header_words := 4 + (segment_count * 4)
	// Pad to 8-byte boundary
	if header_words % 8 != 0 {
		header_words += 4
	}
	return header_words
}

// Serialize a frame header to a byte slice
// The caller must provide a buffer of at least frame_header_size(segment_count) bytes
serialize_frame_header :: proc(
	segment_sizes: []u32,
	buffer: []byte,
) -> (bytes_written: u32, err: Error) {
	segment_count := u32(len(segment_sizes))
	if segment_count == 0 {
		return 0, .Invalid_Frame_Header
	}

	header_size := frame_header_size(segment_count)
	if u32(len(buffer)) < header_size {
		return 0, .Unexpected_End_Of_Input
	}

	// Write segment count - 1 (little-endian u32)
	count_minus_one := segment_count - 1
	buffer[0] = byte(count_minus_one)
	buffer[1] = byte(count_minus_one >> 8)
	buffer[2] = byte(count_minus_one >> 16)
	buffer[3] = byte(count_minus_one >> 24)

	// Write segment sizes (each as little-endian u32)
	offset: u32 = 4
	for size in segment_sizes {
		buffer[offset + 0] = byte(size)
		buffer[offset + 1] = byte(size >> 8)
		buffer[offset + 2] = byte(size >> 16)
		buffer[offset + 3] = byte(size >> 24)
		offset += 4
	}

	// Zero padding if needed
	for offset < header_size {
		buffer[offset] = 0
		offset += 1
	}

	return header_size, .None
}

// Deserialize a frame header from a byte slice
// Returns the header and the number of bytes consumed
deserialize_frame_header :: proc(
	data: []byte,
	allocator := context.allocator,
) -> (header: Frame_Header, bytes_read: u32, err: Error) {
	if len(data) < 4 {
		return {}, 0, .Unexpected_End_Of_Input
	}

	// Read segment count - 1 (little-endian u32)
	count_minus_one := u32(data[0]) |
	                   (u32(data[1]) << 8) |
	                   (u32(data[2]) << 16) |
	                   (u32(data[3]) << 24)
	
	segment_count := count_minus_one + 1
	
	// Sanity check: prevent excessive segment counts
	if segment_count > 512 { // Reasonable limit
		return {}, 0, .Segment_Count_Overflow
	}

	header_size := frame_header_size(segment_count)
	if u32(len(data)) < header_size {
		return {}, 0, .Unexpected_End_Of_Input
	}

	// Allocate segment sizes array
	sizes, alloc_err := make([]u32, segment_count, allocator)
	if alloc_err != nil {
		return {}, 0, .Out_Of_Memory
	}

	// Read segment sizes
	offset: u32 = 4
	for i in 0 ..< segment_count {
		sizes[i] = u32(data[offset + 0]) |
		           (u32(data[offset + 1]) << 8) |
		           (u32(data[offset + 2]) << 16) |
		           (u32(data[offset + 3]) << 24)
		
		// Sanity check segment size
		if sizes[i] > 1 << 28 { // ~2GB per segment max
			delete(sizes, allocator)
			return {}, 0, .Segment_Size_Overflow
		}
		offset += 4
	}

	return Frame_Header{
		segment_count = segment_count,
		segment_sizes = sizes,
	}, header_size, .None
}

// Free a frame header's allocated memory
frame_header_destroy :: proc(header: ^Frame_Header, allocator := context.allocator) {
	if header.segment_sizes != nil {
		delete(header.segment_sizes, allocator)
		header.segment_sizes = nil
	}
	header.segment_count = 0
}

// Calculate total size needed to serialize all segments (header + data)
serialize_segments_size :: proc(sm: ^Segment_Manager) -> u32 {
	segment_count := segment_manager_segment_count(sm)
	if segment_count == 0 {
		return 0
	}
	
	header_size := frame_header_size(segment_count)
	data_size: u32 = 0
	for i in 0 ..< segment_count {
		seg := segment_manager_get_segment(sm, i)
		data_size += seg.used * WORD_SIZE_BYTES
	}
	return header_size + data_size
}

// Serialize all segments to a byte slice
// Returns a newly allocated byte slice containing the complete message
serialize_segments :: proc(
	sm: ^Segment_Manager,
	allocator := context.allocator,
) -> (data: []byte, err: Error) {
	segment_count := segment_manager_segment_count(sm)
	if segment_count == 0 {
		return nil, .Invalid_Frame_Header
	}

	// Collect segment sizes
	sizes, sizes_err := make([]u32, segment_count, allocator)
	if sizes_err != nil {
		return nil, .Out_Of_Memory
	}
	defer delete(sizes, allocator)

	total_words: u32 = 0
	for i in 0 ..< segment_count {
		seg := segment_manager_get_segment(sm, i)
		sizes[i] = seg.used
		total_words += seg.used
	}

	// Allocate output buffer
	header_size := frame_header_size(segment_count)
	total_size := header_size + (total_words * WORD_SIZE_BYTES)
	
	buffer, alloc_err := make([]byte, total_size, allocator)
	if alloc_err != nil {
		return nil, .Out_Of_Memory
	}

	// Write header
	_, header_err := serialize_frame_header(sizes, buffer)
	if header_err != .None {
		delete(buffer, allocator)
		return nil, header_err
	}

	// Write segment data
	offset := header_size
	for i in 0 ..< segment_count {
		seg := segment_manager_get_segment(sm, i)
		seg_data := segment_get_data(seg)
		seg_bytes := slice.to_bytes(seg_data)
		copy(buffer[offset:], seg_bytes)
		offset += seg.used * WORD_SIZE_BYTES
	}

	return buffer, .None
}

// Deserialize segments from a byte slice
// Returns a segment manager containing all segments
deserialize_segments :: proc(
	data: []byte,
	allocator := context.allocator,
) -> (sm: Segment_Manager, bytes_read: u32, err: Error) {
	// Parse header
	header, header_size, header_err := deserialize_frame_header(data, allocator)
	if header_err != .None {
		return {}, 0, header_err
	}
	defer frame_header_destroy(&header, allocator)

	// Calculate expected data size
	total_words: u32 = 0
	for size in header.segment_sizes {
		total_words += size
	}
	expected_size := header_size + (total_words * WORD_SIZE_BYTES)
	
	if u32(len(data)) < expected_size {
		return {}, 0, .Unexpected_End_Of_Input
	}

	// Initialize segment manager
	segment_manager_init(&sm, DEFAULT_SEGMENT_SIZE, allocator)

	// Create segments from data
	offset := header_size
	for i in 0 ..< header.segment_count {
		seg_size := header.segment_sizes[i]
		
		// Create segment with exact size
		seg, seg_err := segment_create(i, seg_size, allocator)
		if seg_err != .None {
			segment_manager_destroy(&sm)
			return {}, 0, seg_err
		}
		
		// Copy data into segment
		seg_bytes := slice.to_bytes(seg.data)
		copy(seg_bytes, data[offset:offset + seg_size * WORD_SIZE_BYTES])
		seg.used = seg_size
		
		append(&sm.segments, seg)
		offset += seg_size * WORD_SIZE_BYTES
	}

	return sm, expected_size, .None
}
