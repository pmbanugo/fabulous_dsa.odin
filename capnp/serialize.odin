package capnp

import "core:io"
import "core:slice"

// Serialize a message to bytes (includes frame header)
// Allocates and returns a new byte slice
serialize :: proc(
	mb: ^Message_Builder,
	allocator := context.allocator,
) -> (data: []byte, err: Error) {
	return serialize_segments(&mb.segments, allocator)
}

// Serialize a message to an io.Writer
serialize_to_writer :: proc(mb: ^Message_Builder, w: io.Writer) -> Error {
	segment_count := segment_manager_segment_count(&mb.segments)
	if segment_count == 0 {
		return .Invalid_Frame_Header
	}
	
	// Build frame header
	header_size := frame_header_size(segment_count)
	header_buf := make([]byte, header_size, context.temp_allocator)
	
	// Collect segment sizes
	sizes := make([]u32, segment_count, context.temp_allocator)
	for i in 0 ..< segment_count {
		seg := segment_manager_get_segment(&mb.segments, i)
		sizes[i] = seg.used
	}
	
	// Serialize frame header
	_, header_err := serialize_frame_header(sizes, header_buf)
	if header_err != .None {
		return header_err
	}
	
	// Write header
	header_written, write_err := io.write(w, header_buf)
	if write_err != nil || header_written != len(header_buf) {
		return .Unexpected_End_Of_Input
	}
	
	// Write each segment
	for i in 0 ..< segment_count {
		seg := segment_manager_get_segment(&mb.segments, i)
		seg_data := segment_get_data(seg)
		seg_bytes := slice.to_bytes(seg_data)
		
		bytes_written, seg_write_err := io.write(w, seg_bytes)
		if seg_write_err != nil || bytes_written != len(seg_bytes) {
			return .Unexpected_End_Of_Input
		}
	}
	
	return .None
}

// ============================================================================
// Deserialization to Message_Reader
// ============================================================================

// Deserialize bytes to a Message_Reader
deserialize :: proc(
	data: []byte,
	limits := Read_Limits{},
	allocator := context.allocator,
) -> (reader: Message_Reader, err: Error) {
	return message_reader_from_bytes(data, limits, allocator)
}

// Deserialize from an io.Reader to a Message_Reader
// This reads the entire message into a buffer first
// Returns both the reader and the data buffer (caller owns the data)
deserialize_from_reader :: proc(
	r: io.Reader,
	limits := Read_Limits{},
	allocator := context.allocator,
) -> (reader: Message_Reader, data: []byte, err: Error) {
	// First, read the frame header to determine message size
	// Read first 4 bytes to get segment count
	header_start: [4]byte
	bytes_read, read_err := io.read(r, header_start[:])
	if read_err != nil || bytes_read != 4 {
		return {}, nil, .Unexpected_End_Of_Input
	}
	
	// Parse segment count
	count_minus_one := u32(header_start[0]) |
	                   (u32(header_start[1]) << 8) |
	                   (u32(header_start[2]) << 16) |
	                   (u32(header_start[3]) << 24)
	segment_count := count_minus_one + 1
	
	if segment_count > 512 {
		return {}, nil, .Segment_Count_Overflow
	}
	
	// Calculate full header size
	header_size := frame_header_size(segment_count)
	
	// Allocate buffer for full header
	header_buf, alloc_err := make([]byte, header_size, context.temp_allocator)
	if alloc_err != nil {
		return {}, nil, .Out_Of_Memory
	}
	
	copy(header_buf[:4], header_start[:])
	
	// Read rest of header
	if header_size > 4 {
		remaining_header := header_buf[4:]
		bytes_read, read_err = io.read(r, remaining_header)
		if read_err != nil || bytes_read != int(header_size - 4) {
			return {}, nil, .Unexpected_End_Of_Input
		}
	}
	
	// Parse segment sizes
	segment_sizes, sizes_err := make([]u32, segment_count, context.temp_allocator)
	if sizes_err != nil {
		return {}, nil, .Out_Of_Memory
	}
	
	offset: u32 = 4
	total_words: u32 = 0
	for i in 0 ..< segment_count {
		segment_sizes[i] = u32(header_buf[offset + 0]) |
		                   (u32(header_buf[offset + 1]) << 8) |
		                   (u32(header_buf[offset + 2]) << 16) |
		                   (u32(header_buf[offset + 3]) << 24)
		
		if segment_sizes[i] > 1 << 28 {
			return {}, nil, .Segment_Size_Overflow
		}
		total_words += segment_sizes[i]
		offset += 4
	}
	
	// Calculate total message size and allocate buffer
	total_size := header_size + (total_words * WORD_SIZE_BYTES)
	data_buf, data_err := make([]byte, total_size, allocator)
	if data_err != nil {
		return {}, nil, .Out_Of_Memory
	}
	
	// Copy header
	copy(data_buf[:header_size], header_buf)
	
	// Read segment data
	segment_data := data_buf[header_size:]
	bytes_read, read_err = io.read_full(r, segment_data)
	if read_err != nil || bytes_read != int(len(segment_data)) {
		delete(data_buf, allocator)
		return {}, nil, .Unexpected_End_Of_Input
	}
	
	// Create message reader
	msg_reader, reader_err := message_reader_from_bytes(data_buf, limits, allocator)
	if reader_err != .None {
		delete(data_buf, allocator)
		return {}, nil, reader_err
	}
	
	return msg_reader, data_buf, .None
}
