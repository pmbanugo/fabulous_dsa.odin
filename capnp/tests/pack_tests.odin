package capnp_tests

import capnp ".."
import "core:testing"

// ============================================================================
// Basic Pack/Unpack Roundtrip Tests
// ============================================================================

@(test)
test_pack_empty_input :: proc(t: ^testing.T) {
	data: []byte = {}

	packed, pack_err := capnp.pack(data)
	testing.expect_value(t, pack_err, capnp.Error.None)
	testing.expect(t, packed == nil, "Empty input should produce nil output")

	unpacked, unpack_err := capnp.unpack(data)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	testing.expect(t, unpacked == nil, "Empty input should produce nil output")
}

@(test)
test_pack_single_zero_word :: proc(t: ^testing.T) {
	// All zeros
	original := [?]byte{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}

	packed, pack_err := capnp.pack(original[:])
	defer delete(packed)
	testing.expect_value(t, pack_err, capnp.Error.None)

	// Should be: 0x00 (tag) + 0x00 (zero count = 0 additional)
	testing.expect_value(t, len(packed), 2)
	testing.expect_value(t, packed[0], u8(0x00))
	testing.expect_value(t, packed[1], u8(0x00))

	unpacked, unpack_err := capnp.unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	testing.expect_value(t, len(unpacked), 8)

	for i in 0 ..< 8 {
		testing.expect_value(t, unpacked[i], u8(0x00))
	}
}

@(test)
test_pack_single_nonzero_word :: proc(t: ^testing.T) {
	// All non-zero bytes
	original := [?]byte{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08}

	packed, pack_err := capnp.pack(original[:])
	defer delete(packed)
	testing.expect_value(t, pack_err, capnp.Error.None)

	// Should be: 0xFF (tag) + 8 bytes + 0x00 (literal count)
	testing.expect_value(t, len(packed), 10)
	testing.expect_value(t, packed[0], u8(0xFF))
	testing.expect_value(t, packed[1], u8(0x01))
	testing.expect_value(t, packed[8], u8(0x08))
	testing.expect_value(t, packed[9], u8(0x00)) // literal count

	unpacked, unpack_err := capnp.unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	testing.expect_value(t, len(unpacked), 8)

	for i in 0 ..< 8 {
		testing.expect_value(t, unpacked[i], original[i])
	}
}

// ============================================================================
// Zero Word Run Tests (Tag 0x00)
// ============================================================================

@(test)
test_pack_zero_word_runs :: proc(t: ^testing.T) {
	// 5 zero words
	original := make([]byte, 40)
	defer delete(original)
	// All zeros by default

	packed, pack_err := capnp.pack(original)
	defer delete(packed)
	testing.expect_value(t, pack_err, capnp.Error.None)

	// Should be: 0x00 (tag) + 0x04 (4 additional zero words)
	testing.expect_value(t, len(packed), 2)
	testing.expect_value(t, packed[0], u8(0x00))
	testing.expect_value(t, packed[1], u8(0x04)) // 4 additional

	unpacked, unpack_err := capnp.unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	testing.expect_value(t, len(unpacked), 40)
}

@(test)
test_pack_max_zero_word_run :: proc(t: ^testing.T) {
	// 256 zero words: 1 (first) + 255 (additional) = 256 total
	// Encoding: 0x00 (tag) + 0xFF (255 additional) = 2 bytes total
	original := make([]byte, 256 * 8)
	defer delete(original)

	packed, pack_err := capnp.pack(original)
	defer delete(packed)
	testing.expect_value(t, pack_err, capnp.Error.None)

	// 256 words = 1 + 255 additional, fits in one run
	testing.expect_value(t, len(packed), 2)
	testing.expect_value(t, packed[0], u8(0x00))
	testing.expect_value(t, packed[1], u8(0xFF)) // 255 additional

	// Roundtrip
	unpacked, unpack_err := capnp.unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	testing.expect_value(t, len(unpacked), 256 * 8)
}

@(test)
test_pack_beyond_max_zero_word_run :: proc(t: ^testing.T) {
	// 257 zero words: needs 2 runs (1+255) + (1+0) = 4 bytes
	original := make([]byte, 257 * 8)
	defer delete(original)

	packed, pack_err := capnp.pack(original)
	defer delete(packed)
	testing.expect_value(t, pack_err, capnp.Error.None)

	// 257 words = (1 + 255) + (1 + 0) = two runs
	testing.expect_value(t, len(packed), 4)
	testing.expect_value(t, packed[0], u8(0x00))
	testing.expect_value(t, packed[1], u8(0xFF)) // 255 additional
	testing.expect_value(t, packed[2], u8(0x00))
	testing.expect_value(t, packed[3], u8(0x00)) // 0 additional

	// Roundtrip
	unpacked, unpack_err := capnp.unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	testing.expect_value(t, len(unpacked), 257 * 8)
}

// ============================================================================
// Literal Word Run Tests (Tag 0xFF)
// ============================================================================

@(test)
test_pack_literal_word_runs :: proc(t: ^testing.T) {
	// Two consecutive all-nonzero words
	original := [?]byte{
		0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
		0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
	}

	packed, pack_err := capnp.pack(original[:])
	defer delete(packed)
	testing.expect_value(t, pack_err, capnp.Error.None)

	// Roundtrip
	unpacked, unpack_err := capnp.unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	testing.expect_value(t, len(unpacked), 16)

	for i in 0 ..< 16 {
		testing.expect_value(t, unpacked[i], original[i])
	}
}

@(test)
test_pack_literal_words_with_zeros :: proc(t: ^testing.T) {
	// Per spec: literal words after 0xFF "may or may not contain zeros"
	// This test ensures we can unpack literal runs that contain zero bytes

	// Construct packed data manually
	packed := [?]byte{
		0xFF,                                           // tag: all 8 non-zero
		0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, // first word
		0x01,                                           // 1 literal word follows
		0xAA, 0x00, 0xBB, 0x00, 0xCC, 0x00, 0xDD, 0x00, // literal word WITH zeros
	}

	unpacked, unpack_err := capnp.unpack(packed[:])
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	testing.expect_value(t, len(unpacked), 16)

	// Verify literal word was unpacked correctly
	testing.expect_value(t, unpacked[8], u8(0xAA))
	testing.expect_value(t, unpacked[9], u8(0x00))
	testing.expect_value(t, unpacked[10], u8(0xBB))
	testing.expect_value(t, unpacked[11], u8(0x00))
}

// ============================================================================
// Mixed Content Tests
// ============================================================================

@(test)
test_pack_mixed_content :: proc(t: ^testing.T) {
	// Mix of zero, sparse, and dense words
	original := [?]byte{
		// Word 0: all zeros
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		// Word 1: sparse (1 non-zero)
		0x42, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
		// Word 2: all non-zero
		0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
		// Word 3: zeros again
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	}

	packed, pack_err := capnp.pack(original[:])
	defer delete(packed)
	testing.expect_value(t, pack_err, capnp.Error.None)

	// Packed should be smaller than original
	testing.expect(t, len(packed) < len(original), "Packed should be smaller")

	// Roundtrip
	unpacked, unpack_err := capnp.unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	testing.expect_value(t, len(unpacked), len(original))

	for i in 0 ..< len(original) {
		testing.expect_value(t, unpacked[i], original[i])
	}
}

@(test)
test_pack_alternating_patterns :: proc(t: ^testing.T) {
	// Alternating compressible and incompressible words
	original := [?]byte{
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // zero word
		0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, // all non-zero
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // zero word
		0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA, 0xF9, 0xF8, // all non-zero
	}

	packed, pack_err := capnp.pack(original[:])
	defer delete(packed)
	testing.expect_value(t, pack_err, capnp.Error.None)

	unpacked, unpack_err := capnp.unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	testing.expect_value(t, len(unpacked), len(original))

	for i in 0 ..< len(original) {
		testing.expect_value(t, unpacked[i], original[i])
	}
}

// ============================================================================
// Sparse Data Tests
// ============================================================================

@(test)
test_pack_sparse_data :: proc(t: ^testing.T) {
	// Data with only occasional non-zero bytes (common in Cap'n Proto)
	original := [?]byte{
		0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // 1 non-zero
		0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, // 1 non-zero
		0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, // 1 non-zero
	}

	packed, pack_err := capnp.pack(original[:])
	defer delete(packed)
	testing.expect_value(t, pack_err, capnp.Error.None)

	// Should be well compressed
	testing.expect(t, len(packed) < len(original), "Sparse data should compress well")

	unpacked, unpack_err := capnp.unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	testing.expect_value(t, len(unpacked), len(original))

	for i in 0 ..< len(original) {
		testing.expect_value(t, unpacked[i], original[i])
	}
}

// ============================================================================
// pack_word Tests
// ============================================================================

@(test)
test_pack_word_all_zero :: proc(t: ^testing.T) {
	word := [?]byte{0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}

	result, length := capnp.pack_word(word[:])
	testing.expect_value(t, length, 1)
	testing.expect_value(t, result[0], u8(0x00))
}

@(test)
test_pack_word_all_nonzero :: proc(t: ^testing.T) {
	word := [?]byte{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08}

	result, length := capnp.pack_word(word[:])
	testing.expect_value(t, length, 9)
	testing.expect_value(t, result[0], u8(0xFF))
	testing.expect_value(t, result[1], u8(0x01))
	testing.expect_value(t, result[8], u8(0x08))
}

@(test)
test_pack_word_sparse :: proc(t: ^testing.T) {
	// Only byte 0 and byte 4 are non-zero
	word := [?]byte{0x42, 0x00, 0x00, 0x00, 0x13, 0x00, 0x00, 0x00}

	result, length := capnp.pack_word(word[:])
	// Tag: bit 0 and bit 4 set = 0x11 = 17
	testing.expect_value(t, result[0], u8(0x11))
	testing.expect_value(t, length, 3) // tag + 2 non-zero bytes
	testing.expect_value(t, result[1], u8(0x42))
	testing.expect_value(t, result[2], u8(0x13))
}

// ============================================================================
// unpack_word Tests
// ============================================================================

@(test)
test_unpack_word_all_zero :: proc(t: ^testing.T) {
	packed := [?]byte{0x00}

	word, consumed, err := capnp.unpack_word(packed[:])
	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, consumed, 1)

	for i in 0 ..< 8 {
		testing.expect_value(t, word[i], u8(0x00))
	}
}

@(test)
test_unpack_word_all_nonzero :: proc(t: ^testing.T) {
	packed := [?]byte{0xFF, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08}

	word, consumed, err := capnp.unpack_word(packed[:])
	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, consumed, 9)

	for i in 0 ..< 8 {
		testing.expect_value(t, word[i], u8(i + 1))
	}
}

@(test)
test_unpack_word_sparse :: proc(t: ^testing.T) {
	// Tag 0x11: bits 0 and 4 set, followed by values for those positions
	packed := [?]byte{0x11, 0x42, 0x13}

	word, consumed, err := capnp.unpack_word(packed[:])
	testing.expect_value(t, err, capnp.Error.None)
	testing.expect_value(t, consumed, 3)

	testing.expect_value(t, word[0], u8(0x42))
	testing.expect_value(t, word[1], u8(0x00))
	testing.expect_value(t, word[2], u8(0x00))
	testing.expect_value(t, word[3], u8(0x00))
	testing.expect_value(t, word[4], u8(0x13))
	testing.expect_value(t, word[5], u8(0x00))
	testing.expect_value(t, word[6], u8(0x00))
	testing.expect_value(t, word[7], u8(0x00))
}

// ============================================================================
// Error Cases Tests
// ============================================================================

@(test)
test_pack_unaligned_input :: proc(t: ^testing.T) {
	// Input not a multiple of 8
	data := [?]byte{0x01, 0x02, 0x03}

	_, err := capnp.pack(data[:])
	testing.expect_value(t, err, capnp.Error.Invalid_Packed_Data)
}

@(test)
test_unpack_truncated_tag :: proc(t: ^testing.T) {
	// Empty input
	data: []byte = {}

	_, err := capnp.unpack(data)
	testing.expect_value(t, err, capnp.Error.None) // Empty is valid
}

@(test)
test_unpack_truncated_nonzero_bytes :: proc(t: ^testing.T) {
	// Tag says 3 non-zero bytes but only 2 provided
	packed := [?]byte{0x07, 0x01, 0x02} // tag 0x07 = bits 0,1,2 = 3 non-zero needed

	_, err := capnp.unpack(packed[:])
	testing.expect_value(t, err, capnp.Error.Invalid_Packed_Data)
}

@(test)
test_unpack_truncated_zero_count :: proc(t: ^testing.T) {
	// 0x00 tag without count byte
	packed := [?]byte{0x00}

	_, err := capnp.unpack(packed[:])
	testing.expect_value(t, err, capnp.Error.Invalid_Packed_Data)
}

@(test)
test_unpack_truncated_literal_count :: proc(t: ^testing.T) {
	// 0xFF tag with 8 bytes but missing literal count
	packed := [?]byte{
		0xFF,
		0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
		// missing count byte
	}

	_, err := capnp.unpack(packed[:])
	testing.expect_value(t, err, capnp.Error.Invalid_Packed_Data)
}

@(test)
test_unpack_truncated_literal_words :: proc(t: ^testing.T) {
	// 0xFF with count > 0 but missing literal data
	packed := [?]byte{
		0xFF,
		0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
		0x02,                                           // count = 2 literal words expected
		0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, // only 1 word provided
	}

	_, err := capnp.unpack(packed[:])
	testing.expect_value(t, err, capnp.Error.Invalid_Packed_Data)
}

@(test)
test_unpack_size_limit :: proc(t: ^testing.T) {
	// Create packed data that would expand to more than the limit
	packed := [?]byte{
		0x00, 0xFF, // Zero word + 255 additional = 256 words = 2048 bytes
	}

	_, err := capnp.unpack(packed[:], max_output_size = 100)
	testing.expect_value(t, err, capnp.Error.Segment_Size_Overflow)
}

// ============================================================================
// Large Data Tests
// ============================================================================

@(test)
test_pack_word_bit_patterns :: proc(t: ^testing.T) {
	// Test exhaustive bit patterns for tag generation
	test_cases := []struct {
		input:    u8,
		expected: int,
	}{
		{0x00, 0}, {0x01, 1}, {0x03, 2}, {0x07, 3},
		{0x0F, 4}, {0xFF, 8}, {0x55, 4}, {0xAA, 4},
	}

	for tc in test_cases {
		word: [8]byte
		expected_non_zero := 0
		for i in 0 ..< 8 {
			if (tc.input & (1 << uint(i))) != 0 {
				word[i] = 0xFF
				expected_non_zero += 1
			}
		}
		result, length := capnp.pack_word(word[:])
		testing.expect_value(t, result[0], tc.input)
		testing.expect_value(t, length, 1 + expected_non_zero)
	}
}

// ============================================================================
// Large Data Tests
// ============================================================================

@(test)
test_pack_large_data :: proc(t: ^testing.T) {
	// 1000 words of mixed data
	original := make([]byte, 1000 * 8)
	defer delete(original)

	// Fill with pattern: every 10th word is non-zero
	for i := 0; i < 1000; i += 10 {
		offset := i * 8
		original[offset] = u8(i & 0xFF)
		original[offset + 1] = u8((i >> 8) & 0xFF)
	}

	packed, pack_err := capnp.pack(original)
	defer delete(packed)
	testing.expect_value(t, pack_err, capnp.Error.None)

	// Packed should be smaller (mostly zeros)
	testing.expect(t, len(packed) < len(original), "Packed should be smaller")

	unpacked, unpack_err := capnp.unpack(packed)
	defer delete(unpacked)
	testing.expect_value(t, unpack_err, capnp.Error.None)
	testing.expect_value(t, len(unpacked), len(original))

	for i in 0 ..< len(original) {
		testing.expect_value(t, unpacked[i], original[i])
	}
}
