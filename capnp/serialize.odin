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
