package capnp

import "core:io"
import "core:mem"

// Packing compression for Cap'n Proto messages.
// See: https://capnproto.org/encoding.html#packing
//
// Algorithm (per 8-byte word):
// 1. Create a tag byte where bit N = 1 if byte N of the word is non-zero
// 2. Write the tag byte
// 3. Write only the non-zero bytes in order
//
// Special cases:
// - Tag 0x00: All zeros, followed by count (0-255) of additional zero words
// - Tag 0xFF: All 8 bytes non-zero, followed by 8 literal bytes + count of literal words
//   The literal words are copied verbatim (may contain zeros per spec)

// Maximum output size for unpacking to prevent decompression bombs
DEFAULT_MAX_UNPACK_SIZE :: 64 * 1024 * 1024 // 64 MB

// Pack compresses data using Cap'n Proto packing algorithm.
// Input length must be a multiple of 8 (word-aligned).
// Returns packed data or error.
pack :: proc(data: []byte, allocator := context.allocator) -> (packed: []byte, err: Error) {
	if len(data) == 0 {
		return nil, .None
	}

	if len(data) % WORD_SIZE_BYTES != 0 {
		return nil, .Invalid_Packed_Data
	}

	word_count := len(data) / WORD_SIZE_BYTES

	// Worst case: 9 bytes per 8-byte word (tag + all 8 bytes) + literal run counts
	maximum_output_size := word_count * 10
	output, allocation_error := make([]byte, maximum_output_size, allocator)
	if allocation_error != nil {
		return nil, .Out_Of_Memory
	}

	output_position := 0
	input_position := 0

	for input_position < len(data) {
		word := data[input_position:input_position + WORD_SIZE_BYTES]
		tag := compute_tag(word)

		if tag == 0x00 {
			// Zero word - count additional zero words
			output[output_position] = 0x00
			output_position += 1
			input_position += WORD_SIZE_BYTES

			// Count additional zero words (up to 255)
			zero_word_count: u8 = 0
			for zero_word_count < 255 && input_position < len(data) {
				next_word := data[input_position:input_position + WORD_SIZE_BYTES]
				if !is_zero_word(next_word) {
					break
				}
				zero_word_count += 1
				input_position += WORD_SIZE_BYTES
			}
			output[output_position] = zero_word_count
			output_position += 1
		} else if tag == 0xFF {
			// All non-zero - write tag + 8 bytes, then count literal words
			output[output_position] = 0xFF
			output_position += 1

			// Use bulk copy for the 8 bytes
			copy(output[output_position:output_position + WORD_SIZE_BYTES], word)
			output_position += WORD_SIZE_BYTES
			input_position += WORD_SIZE_BYTES

			// Position for literal count byte
			literal_count_position := output_position
			output[output_position] = 0 // placeholder for count
			output_position += 1

			// Per spec: literal words are copied verbatim and "may or may not contain zeros"
			// We extend literal runs while beneficial (not just when tag == 0xFF)
			// Stop when we hit a highly compressible word (all zeros or <= 2 non-zero bytes)
			literal_word_count: u8 = 0
			for literal_word_count < 255 && input_position < len(data) {
				next_word := data[input_position:input_position + WORD_SIZE_BYTES]
				next_tag := compute_tag(next_word)

				// Stop literal run for highly compressible words
				if next_tag == 0x00 || count_bits(next_tag) <= 2 {
					break
				}

				// Copy literal word using bulk copy
				copy(output[output_position:output_position + WORD_SIZE_BYTES], next_word)
				output_position += WORD_SIZE_BYTES
				literal_word_count += 1
				input_position += WORD_SIZE_BYTES
			}
			output[literal_count_position] = literal_word_count
		} else {
			// Mixed word - write tag and non-zero bytes
			output[output_position] = tag
			output_position += 1

			for i in 0 ..< WORD_SIZE_BYTES {
				if (tag & (1 << uint(i))) != 0 {
					output[output_position] = word[i]
					output_position += 1
				}
			}
			input_position += WORD_SIZE_BYTES
		}
	}

	// Trim to actual size
	result, resize_error := make([]byte, output_position, allocator)
	if resize_error != nil {
		delete(output, allocator)
		return nil, .Out_Of_Memory
	}
	copy(result, output[:output_position])
	delete(output, allocator)

	return result, .None
}

// Pack data and write to an io.Writer
pack_to_writer :: proc(data: []byte, writer: io.Writer) -> Error {
	if len(data) == 0 {
		return .None
	}

	if len(data) % WORD_SIZE_BYTES != 0 {
		return .Invalid_Packed_Data
	}

	input_position := 0

	for input_position < len(data) {
		word := data[input_position:input_position + WORD_SIZE_BYTES]
		tag := compute_tag(word)

		if tag == 0x00 {
			// Zero word - count additional zero words
			input_position += WORD_SIZE_BYTES

			zero_word_count: u8 = 0
			for zero_word_count < 255 && input_position < len(data) {
				next_word := data[input_position:input_position + WORD_SIZE_BYTES]
				if !is_zero_word(next_word) {
					break
				}
				zero_word_count += 1
				input_position += WORD_SIZE_BYTES
			}

			write_buffer := [2]byte{0x00, zero_word_count}
			if !write_all_bytes(writer, write_buffer[:]) {
				return .Unexpected_End_Of_Input
			}
		} else if tag == 0xFF {
			// All non-zero - write tag + 8 bytes
			write_buffer: [9]byte
			write_buffer[0] = 0xFF
			copy(write_buffer[1:], word)
			input_position += WORD_SIZE_BYTES

			if !write_all_bytes(writer, write_buffer[:]) {
				return .Unexpected_End_Of_Input
			}

			// Count and collect literal words
			literal_word_count: u8 = 0
			literal_buffer: [255 * WORD_SIZE_BYTES]byte
			literal_buffer_length := 0

			for literal_word_count < 255 && input_position < len(data) {
				next_word := data[input_position:input_position + WORD_SIZE_BYTES]
				next_tag := compute_tag(next_word)

				// Stop literal run for highly compressible words
				if next_tag == 0x00 || count_bits(next_tag) <= 2 {
					break
				}

				copy(literal_buffer[literal_buffer_length:literal_buffer_length + WORD_SIZE_BYTES], next_word)
				literal_buffer_length += WORD_SIZE_BYTES
				literal_word_count += 1
				input_position += WORD_SIZE_BYTES
			}

			// Write count byte
			count_buffer := [1]byte{literal_word_count}
			if !write_all_bytes(writer, count_buffer[:]) {
				return .Unexpected_End_Of_Input
			}

			// Write literal words
			if literal_buffer_length > 0 {
				if !write_all_bytes(writer, literal_buffer[:literal_buffer_length]) {
					return .Unexpected_End_Of_Input
				}
			}
		} else {
			// Mixed word - write tag and non-zero bytes
			write_buffer: [9]byte
			write_buffer[0] = tag
			buffer_length := 1

			for i in 0 ..< WORD_SIZE_BYTES {
				if (tag & (1 << uint(i))) != 0 {
					write_buffer[buffer_length] = word[i]
					buffer_length += 1
				}
			}
			input_position += WORD_SIZE_BYTES

			if !write_all_bytes(writer, write_buffer[:buffer_length]) {
				return .Unexpected_End_Of_Input
			}
		}
	}

	return .None
}

// Pack a single 8-byte word using tag encoding (without run-length extension).
// Result is 1-9 bytes: tag byte followed by 0-8 non-zero bytes.
// Note: This does NOT implement 0x00/0xFF run-length semantics.
pack_word :: proc(word: []byte) -> (result: [9]byte, length: int) {
	if len(word) != WORD_SIZE_BYTES {
		return {}, 0
	}

	tag := compute_tag(word)
	result[0] = tag
	length = 1

	for i in 0 ..< WORD_SIZE_BYTES {
		if (tag & (1 << uint(i))) != 0 {
			result[length] = word[i]
			length += 1
		}
	}

	return result, length
}

// Unpack decompresses packed Cap'n Proto data.
// max_output_size limits decompression to prevent decompression bombs (0 = use default).
// Returns unpacked data (word-aligned) or error.
unpack :: proc(
	packed: []byte,
	allocator := context.allocator,
	max_output_size: int = 0,
) -> (data: []byte, err: Error) {
	if len(packed) == 0 {
		return nil, .None
	}

	maximum_size := max_output_size
	if maximum_size == 0 {
		maximum_size = DEFAULT_MAX_UNPACK_SIZE
	}

	// Estimate initial output size
	estimated_size := len(packed) * 2
	if estimated_size < 256 {
		estimated_size = 256
	}
	if estimated_size > maximum_size {
		estimated_size = maximum_size
	}

	output, allocation_error := make([]byte, estimated_size, allocator)
	if allocation_error != nil {
		return nil, .Out_Of_Memory
	}
	// Odin's make returns zero-initialized memory

	output_position := 0
	input_position := 0

	for input_position < len(packed) {
		tag := packed[input_position]
		input_position += 1

		if tag == 0x00 {
			// Zero word followed by count of additional zero words
			if input_position >= len(packed) {
				delete(output, allocator)
				return nil, .Invalid_Packed_Data
			}

			additional_zero_count := int(packed[input_position])
			input_position += 1

			// Total zero bytes needed: (1 + additional_zero_count) words
			total_zero_bytes := (1 + additional_zero_count) * WORD_SIZE_BYTES

			// Check size limit
			if output_position + total_zero_bytes > maximum_size {
				delete(output, allocator)
				return nil, .Segment_Size_Overflow
			}

			// Ensure capacity
			output, err = ensure_capacity(&output, output_position, total_zero_bytes, allocator)
			if err != .None {
				return nil, err
			}

			// Output is already zero-initialized, just advance position
			output_position += total_zero_bytes

		} else if tag == 0xFF {
			// All 8 bytes present, then count, then literal words
			if input_position + WORD_SIZE_BYTES > len(packed) {
				delete(output, allocator)
				return nil, .Invalid_Packed_Data
			}

			// Check size limit for first word
			if output_position + WORD_SIZE_BYTES > maximum_size {
				delete(output, allocator)
				return nil, .Segment_Size_Overflow
			}

			// Ensure capacity for first word
			output, err = ensure_capacity(&output, output_position, WORD_SIZE_BYTES, allocator)
			if err != .None {
				return nil, err
			}

			// Bulk copy first 8 bytes
			copy(output[output_position:output_position + WORD_SIZE_BYTES], packed[input_position:input_position + WORD_SIZE_BYTES])
			output_position += WORD_SIZE_BYTES
			input_position += WORD_SIZE_BYTES

			// Read literal count
			if input_position >= len(packed) {
				delete(output, allocator)
				return nil, .Invalid_Packed_Data
			}
			literal_word_count := int(packed[input_position])
			input_position += 1

			// Validate and copy literal words
			literal_bytes := literal_word_count * WORD_SIZE_BYTES
			if input_position + literal_bytes > len(packed) {
				delete(output, allocator)
				return nil, .Invalid_Packed_Data
			}

			// Check size limit
			if output_position + literal_bytes > maximum_size {
				delete(output, allocator)
				return nil, .Segment_Size_Overflow
			}

			// Ensure capacity
			output, err = ensure_capacity(&output, output_position, literal_bytes, allocator)
			if err != .None {
				return nil, err
			}

			// Bulk copy literal words
			copy(output[output_position:output_position + literal_bytes], packed[input_position:input_position + literal_bytes])
			output_position += literal_bytes
			input_position += literal_bytes

		} else {
			// Mixed word - read non-zero bytes according to tag
			non_zero_byte_count := count_bits(tag)

			if input_position + non_zero_byte_count > len(packed) {
				delete(output, allocator)
				return nil, .Invalid_Packed_Data
			}

			// Check size limit
			if output_position + WORD_SIZE_BYTES > maximum_size {
				delete(output, allocator)
				return nil, .Segment_Size_Overflow
			}

			// Ensure capacity
			output, err = ensure_capacity(&output, output_position, WORD_SIZE_BYTES, allocator)
			if err != .None {
				return nil, err
			}

			// Reconstruct word (output already zero-initialized)
			for i in 0 ..< WORD_SIZE_BYTES {
				if (tag & (1 << uint(i))) != 0 {
					output[output_position + i] = packed[input_position]
					input_position += 1
				}
				// Zero bytes are already 0 from allocation
			}
			output_position += WORD_SIZE_BYTES
		}
	}

	// Trim to actual size
	result, resize_error := make([]byte, output_position, allocator)
	if resize_error != nil {
		delete(output, allocator)
		return nil, .Out_Of_Memory
	}
	copy(result, output[:output_position])
	delete(output, allocator)

	return result, .None
}

// Unpack data from an io.Reader
unpack_from_reader :: proc(
	reader: io.Reader,
	allocator := context.allocator,
	max_output_size: int = 0,
) -> (data: []byte, err: Error) {
	// Read all packed data first, then unpack
	initial_buffer_size := 1024
	buffer, allocation_error := make([]byte, initial_buffer_size, allocator)
	if allocation_error != nil {
		return nil, .Out_Of_Memory
	}

	total_bytes_read := 0
	for {
		if total_bytes_read >= len(buffer) {
			// Grow buffer
			new_size := len(buffer) * 2
			new_buffer, resize_error := make([]byte, new_size, allocator)
			if resize_error != nil {
				delete(buffer, allocator)
				return nil, .Out_Of_Memory
			}
			copy(new_buffer, buffer[:total_bytes_read])
			delete(buffer, allocator)
			buffer = new_buffer
		}

		bytes_read, read_error := io.read(reader, buffer[total_bytes_read:])
		total_bytes_read += bytes_read

		if read_error == .EOF || bytes_read == 0 {
			break
		}
		if read_error != nil && read_error != .EOF {
			delete(buffer, allocator)
			return nil, .Unexpected_End_Of_Input
		}
	}

	// Unpack the data
	result, unpack_error := unpack(buffer[:total_bytes_read], allocator, max_output_size)
	delete(buffer, allocator)

	return result, unpack_error
}

// Unpack a single tagged word (without run-length semantics).
// packed_bytes should start with the tag byte followed by non-zero bytes.
// Returns the reconstructed word and number of bytes consumed.
// Note: This does NOT handle 0x00/0xFF run-length encoding.
unpack_word :: proc(packed_bytes: []byte) -> (word: [WORD_SIZE_BYTES]byte, consumed: int, err: Error) {
	if len(packed_bytes) < 1 {
		return {}, 0, .Invalid_Packed_Data
	}

	tag := packed_bytes[0]
	consumed = 1

	non_zero_byte_count := count_bits(tag)

	if len(packed_bytes) < 1 + non_zero_byte_count {
		return {}, 0, .Invalid_Packed_Data
	}

	// Reconstruct word (word is zero-initialized by default)
	for i in 0 ..< WORD_SIZE_BYTES {
		if (tag & (1 << uint(i))) != 0 {
			word[i] = packed_bytes[consumed]
			consumed += 1
		}
	}

	return word, consumed, .None
}

// Helper: compute tag byte for a word
// Bit N is set if byte N is non-zero
@(private)
compute_tag :: proc(word: []byte) -> u8 {
	tag: u8 = 0
	for i in 0 ..< min(8, len(word)) {
		if word[i] != 0 {
			tag |= (1 << uint(i))
		}
	}
	return tag
}

// Helper: count set bits in a byte
@(private)
count_bits :: proc(value: u8) -> int {
	count := 0
	remaining := value
	for remaining != 0 {
		count += 1
		remaining &= remaining - 1 // Clear lowest set bit
	}
	return count
}

// Helper: check if a word is all zeros
@(private)
is_zero_word :: proc(word: []byte) -> bool {
	for byte_value in word {
		if byte_value != 0 {
			return false
		}
	}
	return true
}

// Helper: ensure output buffer has capacity for additional bytes
@(private)
ensure_capacity :: proc(
	output: ^[]byte,
	current_position: int,
	additional_bytes: int,
	allocator: mem.Allocator,
) -> (result: []byte, err: Error) {
	if current_position + additional_bytes <= len(output^) {
		return output^, .None
	}

	new_size := max(len(output^) * 2, current_position + additional_bytes + 256)
	new_output, allocation_error := make([]byte, new_size, allocator)
	if allocation_error != nil {
		delete(output^, allocator)
		return nil, .Out_Of_Memory
	}
	copy(new_output, output^[:current_position])
	delete(output^, allocator)

	return new_output, .None
}

// Helper: write all bytes to writer, handling short writes
@(private)
write_all_bytes :: proc(writer: io.Writer, data: []byte) -> bool {
	remaining := data
	for len(remaining) > 0 {
		bytes_written, write_error := io.write(writer, remaining)
		if write_error != nil {
			return false
		}
		if bytes_written == 0 {
			return false
		}
		remaining = remaining[bytes_written:]
	}
	return true
}
