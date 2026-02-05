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
serialize_to_writer :: proc(message_builder: ^Message_Builder, writer: io.Writer) -> Error {
	segment_count := segment_manager_segment_count(&message_builder.segments)
	if segment_count == 0 {
		return .Invalid_Frame_Header
	}

	// Build frame header
	header_size := frame_header_size(segment_count)
	header_buffer := make([]byte, header_size, context.temp_allocator)

	// Collect segment sizes
	segment_sizes := make([]u32, segment_count, context.temp_allocator)
	for i in 0 ..< segment_count {
		segment := segment_manager_get_segment(&message_builder.segments, i)
		segment_sizes[i] = segment.used
	}

	// Serialize frame header
	_, header_error := serialize_frame_header(segment_sizes, header_buffer)
	if header_error != .None {
		return header_error
	}

	// Write header
	header_bytes_written, write_error := io.write(writer, header_buffer)
	if write_error != nil || header_bytes_written != len(header_buffer) {
		return .Unexpected_End_Of_Input
	}

	// Write each segment
	for i in 0 ..< segment_count {
		segment := segment_manager_get_segment(&message_builder.segments, i)
		segment_data := segment_get_data(segment)
		segment_bytes := slice.to_bytes(segment_data)

		bytes_written, segment_write_error := io.write(writer, segment_bytes)
		if segment_write_error != nil || bytes_written != len(segment_bytes) {
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

// ============================================================================
// Packed Serialization
// ============================================================================

// Serialize a message to packed bytes (serialize then pack)
serialize_packed :: proc(
	mb: ^Message_Builder,
	allocator := context.allocator,
) -> (packed: []byte, err: Error) {
	// First serialize to unpacked bytes using temp allocator
	// (freed automatically on temp allocator reset, but we delete explicitly for correctness)
	unpacked, serialize_err := serialize(mb, context.temp_allocator)
	if serialize_err != .None {
		return nil, serialize_err
	}
	defer delete(unpacked, context.temp_allocator)

	// Pack the serialized data
	packed_result, pack_err := pack(unpacked, allocator)
	return packed_result, pack_err
}

// Deserialize packed bytes to a Message_Reader (unpack then deserialize)
// Returns both the reader and the unpacked data buffer (caller owns the data)
// The data buffer must be kept alive for the reader's lifetime and freed after
deserialize_packed :: proc(
	packed: []byte,
	limits := Read_Limits{},
	allocator := context.allocator,
) -> (reader: Message_Reader, data: []byte, err: Error) {
	// First unpack the data
	unpacked, unpack_err := unpack(packed, allocator)
	if unpack_err != .None {
		return {}, nil, unpack_err
	}
	
	// Deserialize the unpacked data
	msg_reader, deserialize_err := message_reader_from_bytes(unpacked, limits, allocator)
	if deserialize_err != .None {
		delete(unpacked, allocator)
		return {}, nil, deserialize_err
	}
	
	return msg_reader, unpacked, .None
}

// Deserialize from an io.Reader to a Message_Reader
// This reads the entire message into a buffer first
// Returns both the reader and the data buffer (caller owns the data)
deserialize_from_reader :: proc(
	input_reader: io.Reader,
	limits := Read_Limits{},
	allocator := context.allocator,
) -> (reader: Message_Reader, data: []byte, err: Error) {
	// First, read the frame header to determine message size
	// Read first 4 bytes to get segment count
	header_start: [4]byte
	bytes_read, read_error := io.read(input_reader, header_start[:])
	if read_error != nil || bytes_read != 4 {
		return {}, nil, .Unexpected_End_Of_Input
	}

	// Parse segment count
	count_minus_one := u32((cast(^u32le)&header_start[0])^)
	segment_count := count_minus_one + 1

	if segment_count > 512 {
		return {}, nil, .Segment_Count_Overflow
	}

	// Calculate full header size
	header_size := frame_header_size(segment_count)

	// Allocate buffer for full header
	header_buffer, allocation_error := make([]byte, header_size, context.temp_allocator)
	if allocation_error != nil {
		return {}, nil, .Out_Of_Memory
	}

	copy(header_buffer[:4], header_start[:])

	// Read rest of header
	if header_size > 4 {
		remaining_header := header_buffer[4:]
		bytes_read, read_error = io.read(input_reader, remaining_header)
		if read_error != nil || bytes_read != int(header_size - 4) {
			return {}, nil, .Unexpected_End_Of_Input
		}
	}

	// Parse segment sizes
	segment_sizes, sizes_allocation_error := make([]u32, segment_count, context.temp_allocator)
	if sizes_allocation_error != nil {
		return {}, nil, .Out_Of_Memory
	}

	byte_offset: u32 = 4
	total_words: u32 = 0
	for i in 0 ..< segment_count {
		segment_sizes[i] = u32((cast(^u32le)&header_buffer[byte_offset])^)

		if segment_sizes[i] > 1 << 28 {
			return {}, nil, .Segment_Size_Overflow
		}
		total_words += segment_sizes[i]
		byte_offset += 4
	}

	// Calculate total message size and allocate buffer
	total_size := header_size + (total_words * WORD_SIZE_BYTES)
	data_buffer, data_allocation_error := make([]byte, total_size, allocator)
	if data_allocation_error != nil {
		return {}, nil, .Out_Of_Memory
	}

	// Copy header
	copy(data_buffer[:header_size], header_buffer)

	// Read segment data
	segment_data := data_buffer[header_size:]
	bytes_read, read_error = io.read_full(input_reader, segment_data)
	if read_error != nil || bytes_read != int(len(segment_data)) {
		delete(data_buffer, allocator)
		return {}, nil, .Unexpected_End_Of_Input
	}

	// Create message reader
	message_reader, reader_error := message_reader_from_bytes(data_buffer, limits, allocator)
	if reader_error != .None {
		delete(data_buffer, allocator)
		return {}, nil, reader_error
	}

	return message_reader, data_buffer, .None
}
