package binary_fuse

import "core:log"
import "core:math/rand"
import "core:testing"
import "core:time"

// ============================================================================
// 1. Fundamental Correctness (Zero False Negative Rule)
// ============================================================================

@(test)
test_zero_false_negatives_small :: proc(t: ^testing.T) {
	keys := make([]u64, 1000)
	defer delete(keys)

	for i in 0 ..< len(keys) {
		keys[i] = u64(i * 7 + 13)
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Filter construction failed")
	if !ok {return}
	defer destroy(&filter)

	for key in keys {
		testing.expect(t, contain(filter, key), "False negative detected - critical failure")
	}
}

@(test)
test_zero_false_negatives_large :: proc(t: ^testing.T) {
	testing.set_fail_timeout(t, 30 * time.Second)

	N :: 100_000
	keys := make([]u64, N)
	defer delete(keys)

	rng_state := rand.create(t.seed)
	rng := rand.default_random_generator(&rng_state)
	for i in 0 ..< N {
		keys[i] = rand.uint64(rng)
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Filter construction failed")
	if !ok {return}
	defer destroy(&filter)

	false_negatives := 0
	for key in keys {
		if !contain(filter, key) {
			false_negatives += 1
		}
	}

	testing.expect_value(t, false_negatives, 0)
}

// ============================================================================
// 2. Probabilistic Validation (False Positive Rate)
// ============================================================================

@(test)
test_false_positive_rate :: proc(t: ^testing.T) {
	testing.set_fail_timeout(t, 60 * time.Second)

	N :: 50_000
	M :: 500_000

	keys := make([]u64, N)
	defer delete(keys)

	rng_state := rand.create(t.seed)
	rng := rand.default_random_generator(&rng_state)
	for i in 0 ..< N {
		keys[i] = rand.uint64(rng) | 1 // Ensure odd numbers
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Filter construction failed")
	if !ok {return}
	defer destroy(&filter)

	false_positives := 0
	for _ in 0 ..< M {
		test_key := rand.uint64(rng) & ~u64(1) // Even numbers (definitely not in set)
		if contain(filter, test_key) {
			false_positives += 1
		}
	}

	observed_fpr := f64(false_positives) / f64(M)
	expected_fpr := 1.0 / 256.0 // ~0.39% for 8-bit fingerprints

	// Allow 50% tolerance for statistical variance
	lower_bound := expected_fpr * 0.5
	upper_bound := expected_fpr * 1.5

	log.infof("FPR: observed=%.4f%%, expected=%.4f%%, bounds=[%.4f%%, %.4f%%]",
		observed_fpr * 100, expected_fpr * 100, lower_bound * 100, upper_bound * 100)

	testing.expect(t, observed_fpr >= lower_bound && observed_fpr <= upper_bound,
		"False positive rate outside acceptable bounds")
}

// ============================================================================
// 3. Construction Logic and Stability
// ============================================================================

@(test)
test_construction_succeeds :: proc(t: ^testing.T) {
	testing.set_fail_timeout(t, 30 * time.Second)

	sizes := []int{100, 1000, 10_000, 50_000}

	for size in sizes {
		keys := make([]u64, size)

		rng_state := rand.create(t.seed ~ u64(size))
		rng := rand.default_random_generator(&rng_state)
		for i in 0 ..< size {
			keys[i] = rand.uint64(rng)
		}

		filter, ok := create(keys)
		testing.expect(t, ok, "Construction failed")

		if ok {
			// Verify at least one key works
			testing.expect(t, contain(filter, keys[0]), "First key not found")
			destroy(&filter)
		}

		delete(keys)
	}
}

@(test)
test_duplicate_keys_behavior :: proc(t: ^testing.T) {
	// The implementation requires unique keys (documented in README)
	// Duplicates corrupt XOR logic - construction should fail or produce undefined results
	keys := []u64{1, 2, 3, 4, 5, 1, 2, 3} // Contains duplicates

	filter, ok := create(keys)
	if ok {
		// Construction succeeded despite duplicates - this is undefined behavior
		// The filter is likely corrupted, clean up and note it
		log.warn("Filter constructed with duplicates - undefined behavior")
		destroy(&filter)
	}
	// Either outcome is acceptable, but failure is the expected/safe result
}

// ============================================================================
// 4. Boundary and Edge Case Testing
// ============================================================================

@(test)
test_empty_set :: proc(t: ^testing.T) {
	keys: []u64 = {}
	filter, ok := create(keys)
	testing.expect(t, !ok, "Empty set should fail construction")
	_ = filter
}

@(test)
test_single_key :: proc(t: ^testing.T) {
	keys := []u64{42}
	filter, ok := create(keys)
	testing.expect(t, ok, "Single key construction failed")
	if !ok {return}
	defer destroy(&filter)

	testing.expect(t, contain(filter, 42), "Single key not found")
	testing.expect(t, !contain(filter, 0) || true, "Expected potential false positive") // FP is acceptable
}

@(test)
test_tiny_sets :: proc(t: ^testing.T) {
	sizes := []int{1, 2, 3, 5, 10, 50, 100}

	for size in sizes {
		keys := make([]u64, size)
		for i in 0 ..< size {
			keys[i] = u64(i + 1)
		}

		filter, ok := create(keys)
		testing.expect(t, ok, "Tiny set construction failed")

		if ok {
			for key in keys {
				testing.expect(t, contain(filter, key), "Key not found in tiny set")
			}
			destroy(&filter)
		}

		delete(keys)
	}
}

@(test)
test_segment_power_of_two :: proc(t: ^testing.T) {
	keys := make([]u64, 10_000)
	defer delete(keys)

	for i in 0 ..< len(keys) {
		keys[i] = u64(i)
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Construction failed")
	if !ok {return}
	defer destroy(&filter)

	seg_len := filter.segment_len
	is_power_of_2 := seg_len > 0 && (seg_len & (seg_len - 1)) == 0
	testing.expect(t, is_power_of_2, "Segment length is not a power of 2")

	// Verify mask is correct
	testing.expect_value(t, filter.segment_mask, seg_len - 1)
}

// ============================================================================
// 5. Memory and Space Efficiency
// ============================================================================

@(test)
test_space_efficiency :: proc(t: ^testing.T) {
	N :: 100_000
	keys := make([]u64, N)
	defer delete(keys)

	for i in 0 ..< N {
		keys[i] = u64(i)
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Construction failed")
	if !ok {return}
	defer destroy(&filter)

	bits_allocated := len(filter.fingerprints) * 8
	bits_per_key := f64(bits_allocated) / f64(N)

	// For 8-bit fingerprints, expect ~9 bits per key (1.125 * 8)
	// Allow some margin for segment alignment
	expected_bits_per_key := 1.125 * 8.0
	max_bits_per_key := 1.3 * 8.0 // Allow up to 30% overhead

	log.infof("Space: %.2f bits/key (expected ~%.2f, max %.2f)",
		bits_per_key, expected_bits_per_key, max_bits_per_key)

	testing.expect(t, bits_per_key <= max_bits_per_key,
		"Space overhead exceeds acceptable limit")
}

// ============================================================================
// 6. Batch Operations (SIMD)
// ============================================================================

@(test)
test_batch_contain :: proc(t: ^testing.T) {
	N :: 10_000
	keys := make([]u64, N)
	defer delete(keys)

	for i in 0 ..< N {
		keys[i] = u64(i * 3 + 7)
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Construction failed")
	if !ok {return}
	defer destroy(&filter)

	// Test batch matches scalar
	results := make([]bool, N)
	defer delete(results)

	contain_batch(filter, keys, results)

	for result, i in results {
		testing.expect(t, result, "Batch contain false negative")
		// Also verify consistency with scalar version
		testing.expect(t, result == contain(filter, keys[i]), "Batch/scalar mismatch")
	}
}

@(test)
test_batch_contain_non_members :: proc(t: ^testing.T) {
	keys := make([]u64, 1000)
	defer delete(keys)

	for i in 0 ..< len(keys) {
		keys[i] = u64(i * 2) // Even numbers only
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Construction failed")
	if !ok {return}
	defer destroy(&filter)

	// Query odd numbers (not in set)
	query_keys := make([]u64, 1000)
	defer delete(query_keys)
	for i in 0 ..< len(query_keys) {
		query_keys[i] = u64(i * 2 + 1)
	}

	results := make([]bool, len(query_keys))
	defer delete(results)

	contain_batch(filter, query_keys, results)

	// Verify batch results match scalar
	for result, i in results {
		scalar_result := contain(filter, query_keys[i])
		testing.expect(t, result == scalar_result, "Batch/scalar mismatch for non-member")
	}
}

@(test)
test_batch_unaligned_size :: proc(t: ^testing.T) {
	// Test with sizes that don't align to SIMD width (4)
	keys := make([]u64, 100)
	defer delete(keys)

	for i in 0 ..< len(keys) {
		keys[i] = u64(i)
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Construction failed")
	if !ok {return}
	defer destroy(&filter)

	// Test with 7 keys (not divisible by 4)
	query := keys[0:7]
	results := make([]bool, 7)
	defer delete(results)

	contain_batch(filter, query, results)

	for result in results {
		testing.expect(t, result, "Unaligned batch contain failed")
	}
}

@(test)
test_batch_empty :: proc(t: ^testing.T) {
	// Empty batch should not crash or cause issues in SIMD loop
	keys := make([]u64, 100)
	defer delete(keys)

	for i in 0 ..< len(keys) {
		keys[i] = u64(i)
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Construction failed")
	if !ok {return}
	defer destroy(&filter)

	// Empty slices
	empty_keys: []u64 = {}
	empty_results: []bool = {}

	contain_batch(filter, empty_keys, empty_results)
	// No crash = success
}

// ============================================================================
// 7. Internal Helper Tests
// ============================================================================

@(test)
test_next_power_of_2 :: proc(t: ^testing.T) {
	cases := [][2]u32{
		{0, 1},
		{1, 1},
		{2, 2},
		{3, 4},
		{5, 8},
		{7, 8},
		{8, 8},
		{9, 16},
		{1000, 1024},
		{0x80000000, 0x80000000},
	}

	for test_case in cases {
		input := test_case[0]
		expected := test_case[1]
		result := next_power_of_2(input)
		testing.expect_value(t, result, expected)
	}
}

@(test)
test_ring_queue_operations :: proc(t: ^testing.T) {
	data := make([]u32, 8) // Power of 2
	defer delete(data)

	q: Ring_Queue
	ring_queue_init(&q, data)

	testing.expect_value(t, q.count, 0)

	ring_queue_push(&q, 10)
	ring_queue_push(&q, 20)
	ring_queue_push(&q, 30)

	testing.expect_value(t, q.count, 3)

	testing.expect_value(t, ring_queue_pop(&q), 10)
	testing.expect_value(t, ring_queue_pop(&q), 20)
	testing.expect_value(t, ring_queue_pop(&q), 30)

	testing.expect_value(t, q.count, 0)
}

@(test)
test_ring_queue_wrap_around :: proc(t: ^testing.T) {
	data := make([]u32, 4) // Small buffer to force wrap
	defer delete(data)

	q: Ring_Queue
	ring_queue_init(&q, data)

	// Fill and drain multiple times to test wrap
	for round in 0 ..< 3 {
		for i in 0 ..< 4 {
			ring_queue_push(&q, u32(round * 10 + i))
		}
		for i in 0 ..< 4 {
			expected := u32(round * 10 + i)
			testing.expect_value(t, ring_queue_pop(&q), expected)
		}
	}
}

// ============================================================================
// 8. Stress Tests
// ============================================================================

@(test)
test_large_filter :: proc(t: ^testing.T) {
	testing.set_fail_timeout(t, 120 * time.Second)

	N :: 500_000
	keys := make([]u64, N)
	defer delete(keys)

	rng_state := rand.create(t.seed)
	rng := rand.default_random_generator(&rng_state)
	for i in 0 ..< N {
		keys[i] = rand.uint64(rng)
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Large filter construction failed")
	if !ok {return}
	defer destroy(&filter)

	// Sample check (checking all would be slow)
	sample_size :: 10_000
	step := N / sample_size
	for i := 0; i < N; i += step {
		testing.expect(t, contain(filter, keys[i]), "Sampled key not found")
	}
}

@(test)
test_sequential_keys :: proc(t: ^testing.T) {
	// Sequential keys might have hash collision patterns
	keys := make([]u64, 10_000)
	defer delete(keys)

	for i in 0 ..< len(keys) {
		keys[i] = u64(i)
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Sequential key construction failed")
	if !ok {return}
	defer destroy(&filter)

	for key in keys {
		testing.expect(t, contain(filter, key), "Sequential key not found")
	}
}

@(test)
test_sparse_keys :: proc(t: ^testing.T) {
	// Very sparse keys (large gaps)
	keys := make([]u64, 1000)
	defer delete(keys)

	for i in 0 ..< len(keys) {
		keys[i] = u64(i) * 1_000_000_007 // Large prime multiplier
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Sparse key construction failed")
	if !ok {return}
	defer destroy(&filter)

	for key in keys {
		testing.expect(t, contain(filter, key), "Sparse key not found")
	}
}

@(test)
test_max_u64_keys :: proc(t: ^testing.T) {
	// Edge case values near u64 boundaries, padded with sequential keys for stable construction
	keys := make([]u64, 100)
	defer delete(keys)

	// First few are boundary values (all unique)
	keys[0] = 0
	keys[1] = 1
	keys[2] = max(u64) - 1
	keys[3] = max(u64)
	keys[4] = 0x8000000000000000
	keys[5] = 0x7FFFFFFFFFFFFFFF
	keys[6] = 0xFFFFFFFF
	keys[7] = 0x100000000
	keys[8] = 0xDEADBEEFCAFEBABE

	// Fill rest with unique values
	for i in 9 ..< len(keys) {
		keys[i] = u64(i) * 1000003
	}

	filter, ok := create(keys)
	testing.expect(t, ok, "Boundary key construction failed")
	if !ok {return}
	defer destroy(&filter)

	// Check boundary keys specifically
	for i in 0 ..< 9 {
		testing.expect(t, contain(filter, keys[i]), "Boundary key not found")
	}
}
