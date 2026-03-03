package capnp

// SIMD and hardware-intrinsic optimizations for pack.odin.
// Uses SIMD vector ops for tag computation and ctz-based bit iteration
// for branchless byte gather/scatter in packing and unpacking.

import "base:intrinsics"
import "core:simd"

// SIMD-optimized version of pack_word.
// Computes the tag and gathers non-zero bytes from an 8-byte word.
@(private)
pack_word_simd :: proc(word_bytes: [8]u8) -> (tag: u8, packed: [8]u8, packed_count: int) {
	v := simd.from_array(word_bytes)
	zero: #simd[8]u8

	// Create mask of non-zero lanes
	mask := simd.lanes_ne(v, zero)

	// Build tag byte: bit N set if byte N is non-zero
	bit_positions := simd.from_array([8]u8{1, 2, 4, 8, 16, 32, 64, 128})
	tag_bits := simd.select(mask, bit_positions, zero)
	tag = simd.reduce_or(tag_bits)

	// Gather non-zero bytes using ctz bit iteration (branchless per-bit).
	// Odin's simd.shuffle requires compile-time indices ($indices), so
	// runtime SIMD compress is not portable. The ctz approach iterates
	// only set bits without branch mispredictions.
	packed_count = 0
	remaining := tag
	for remaining != 0 {
		i := intrinsics.count_trailing_zeros(remaining)
		packed[packed_count] = word_bytes[i]
		packed_count += 1
		remaining &= remaining - 1
	}

	return tag, packed, packed_count
}

// Scatters packed bytes into an 8-byte word according to the tag.
// Uses ctz bit iteration to visit only set bits without branch mispredictions.
@(private)
unpack_word_simd :: proc(tag: u8, packed_bytes: []u8) -> (word: [8]u8) {
	src_idx := 0
	remaining := tag
	for remaining != 0 {
		i := intrinsics.count_trailing_zeros(remaining)
		word[i] = packed_bytes[src_idx]
		src_idx += 1
		remaining &= remaining - 1
	}
	return word
}

// SIMD-optimized tag computation.
// Returns a byte where bit N is set if byte N of the word is non-zero.
compute_tag_simd :: proc(word: ^[8]u8) -> u8 {
	v := simd.from_array(word^)
	zero: #simd[8]u8
	mask := simd.lanes_ne(v, zero)
	bit_positions := simd.from_array([8]u8{1, 2, 4, 8, 16, 32, 64, 128})
	tag_bits := simd.select(mask, bit_positions, zero)
	return simd.reduce_or(tag_bits)
}

// Fast zero check via u64 comparison (fastest possible single-word check).
is_zero_word_simd :: proc(word_ptr: ^u64) -> bool {
	return word_ptr^ == 0
}

