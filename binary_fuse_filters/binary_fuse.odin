package binary_fuse

import "base:intrinsics"
import "core:math"
import "core:math/rand"
import "core:simd"
import "core:slice"

// ============================================================================
// Types
// ============================================================================

Binary_Fuse_8 :: struct {
	seed:                u64,
	segment_len:         u32,
	segment_mask:        u32,
	segment_count_less2: u32, // Precomputed: (capacity / segment_len) - 2 (avoids division AND subtraction in hot path)
	fingerprints:        []u8,
}

// SIMD lane width for batch operations (4 x u64 = 256-bit vectors)
// Note: On ARM64 NEON (128-bit registers), LLVM automatically splits 256-bit
// vectors into two instructions. This is acceptable since batch lookups are
// memory-bound anyway. See: https://pkg.odin-lang.org/core/simd/
SIMD_WIDTH :: 4
U64x4 :: #simd[SIMD_WIDTH]u64
U32x4 :: #simd[SIMD_WIDTH]u32
U8x4 :: #simd[SIMD_WIDTH]u8

// ============================================================================
// Public API
// ============================================================================

// create allocates and builds a filter from a set of keys.
// keys: Must be unique.
// allocator: Used for the persistent filter data.
// context.temp_allocator: Used for transient construction memory.
create :: proc(keys: []u64, allocator := context.allocator) -> (filter: Binary_Fuse_8, ok: bool) {
	size := len(keys)
	if size == 0 {return {}, false}

	// 1. Calculate sizing per paper formula:
	// capacity >= floor((0.875 + 0.25 * max(1, log(10^6)/log(n))) * n)
	n := f64(size)
	ratio := math.ln_f64(1e6) / math.ln_f64(n)
	mult := 0.875 + 0.25 * max(1.0, ratio)
	capacity := u32(math.floor_f64(mult * n))

	// segment_length = 2 ^ floor(log_3.33(n) + 2.25)
	seg_log := math.floor_f64(math.ln_f64(n) / math.ln_f64(3.33) + 2.25)
	segment_len := u32(1) << u32(seg_log)

	// Clamp segment length
	if segment_len > 262144 {segment_len = 262144}
	if segment_len < 32 {segment_len = 32}

	// Align capacity to segment length
	capacity = ((capacity + segment_len - 1) / segment_len) * segment_len

	// Ensure minimal arity size (3 segments)
	if capacity < 3 * segment_len {
		capacity = 3 * segment_len
	}

	filter.segment_len = segment_len
	filter.segment_mask = segment_len - 1
	filter.segment_count_less2 = (capacity / segment_len) - 2 // Precompute to avoid division AND subtraction in hot path
	alloc_result := make([]u8, int(capacity), allocator)
	if alloc_result == nil {return {}, false}
	filter.fingerprints = alloc_result

	// 2. Allocation of Scratch Memory (HOISTED OUT OF LOOP)
	// We allocate this once using the temp_allocator.
	// If construction fails, we simply zero these arrays and reuse them.
	ctx: Ctx
	ctx.t2count = make([]u8, int(capacity), context.temp_allocator)
	ctx.t2hash = make([]u64, int(capacity), context.temp_allocator)
	// SOA stack for peeled items - Odin's #soa provides cache-efficient layout
	ctx.stack = make(#soa[]Stack_Item, size, context.temp_allocator)
	// Fixed ring buffer queue - power of 2 size for bitwise wrap
	queue_size := next_power_of_2(capacity)
	ctx.queue = make([]u32, int(queue_size), context.temp_allocator)

	// Check scratch allocations succeeded
	if ctx.t2count == nil || ctx.t2hash == nil || ctx.stack == nil || ctx.queue == nil {
		delete(filter.fingerprints, allocator)
		return {}, false
	}

	// 3. Construction Loop
	rng_state := rand.create(u64(intrinsics.read_cycle_counter()))
	rng := rand.default_random_generator(&rng_state)
	MAX_ATTEMPTS :: 100

	// Ring buffer for singleton queue
	Q: Ring_Queue
	ring_queue_init(&Q, ctx.queue)

	for _ in 0 ..< MAX_ATTEMPTS {
		filter.seed = rand.uint64(rng)

		// Pass pointers to the scratch memory
		if construct(filter, keys, &ctx, &Q) {
			return filter, true
		}

		// RESET: Zero out scratch memory for the next attempt
		slice.fill(ctx.t2count, 0)
		slice.fill(ctx.t2hash, 0)
		ring_queue_clear(&Q)

		// Zero out the filter result for the next attempt
		slice.fill(filter.fingerprints, 0)
	}

	// Failure cleanup (persistent memory only)
	delete(filter.fingerprints, allocator)
	return {}, false
}

destroy :: proc(filter: ^Binary_Fuse_8) {
	delete(filter.fingerprints)
	filter^ = {}
}

// contain checks membership.
// False positive rate ~0.4%. False negatives impossible.
contain :: proc(filter: Binary_Fuse_8, key: u64) -> bool {
	hash := mix_split(key, filter.seed)

	// Recompute indices on the fly.
	// This is standard practice: Compute is cheap, Memory is expensive.
	h0, h1, h2 := get_indices(
		hash,
		filter.segment_len,
		filter.segment_mask,
		filter.segment_count_less2,
	)
	fp := u8(fingerprint(hash))

	#no_bounds_check {
		f0 := filter.fingerprints[h0]
		f1 := filter.fingerprints[h1]
		f2 := filter.fingerprints[h2]
		return fp == (f0 ~ f1 ~ f2)
	}
}

// contain_batch processes multiple keys using SIMD to hide memory latency.
// Processes 4 keys at a time when possible.
contain_batch :: proc(filter: Binary_Fuse_8, keys: []u64, results: []bool) {
	n := len(keys)
	i := 0

	// Process 4 keys at a time using SIMD
	#no_bounds_check for ; i + SIMD_WIDTH <= n; i += SIMD_WIDTH {
		// Load 4 keys
		keys_vec := simd.from_slice(U64x4, keys[i:])

		// SIMD hash computation
		hashes := mix_split_simd(keys_vec, filter.seed)

		// Extract hashes and check individually (memory access is the bottleneck)
		hash_arr := simd.to_array(hashes)
		for j in 0 ..< SIMD_WIDTH {
			h := hash_arr[j]
			h0, h1, h2 := get_indices(h, filter.segment_len, filter.segment_mask, filter.segment_count_less2)
			fp := u8(fingerprint(h))
			results[i + j] = fp == (filter.fingerprints[h0] ~ filter.fingerprints[h1] ~ filter.fingerprints[h2])
		}
	}

	// Handle remaining keys scalar
	#no_bounds_check for ; i < n; i += 1 {
		results[i] = contain(filter, keys[i])
	}
}

// ============================================================================
// Internal
// ============================================================================

// Stack item for peeling algorithm - stores hash and which index (0,1,2) was peeled
@(private)
Stack_Item :: struct {
	hash:  u64,
	index: u8, // 0, 1, or 2 (which of h0, h1, h2 was peeled)
}

// Construction Context
@(private)
Ctx :: struct {
	t2count: []u8, // Count of keys mapping to index
	t2hash:  []u64, // XOR sum of hashes
	// Stack uses #soa for cache-efficient iteration during assignment
	stack:   #soa[]Stack_Item,
	// Ring buffer queue (fixed size, no dynamic allocation during peeling)
	queue:   []u32,
}

// Ring buffer for peeling queue - power-of-2 size enables bitwise wrap
@(private)
Ring_Queue :: struct {
	data:  []u32,
	mask:  int, // size - 1, for bitwise wrap (size must be power of 2)
	head:  int, // read position
	tail:  int, // write position
	count: int,
}

@(private)
ring_queue_init :: #force_inline proc(q: ^Ring_Queue, data: []u32) {
	q.data = data
	q.mask = len(data) - 1 // size must be power of 2
	q.head = 0
	q.tail = 0
	q.count = 0
}

@(private)
ring_queue_push :: #force_inline proc(q: ^Ring_Queue, val: u32) {
	q.data[q.tail] = val
	q.tail = (q.tail + 1) & q.mask // 1-cycle bitwise wrap
	q.count += 1
}

@(private)
ring_queue_pop :: #force_inline proc(q: ^Ring_Queue) -> u32 {
	val := q.data[q.head]
	q.head = (q.head + 1) & q.mask // 1-cycle bitwise wrap
	q.count -= 1
	return val
}

@(private)
ring_queue_clear :: #force_inline proc(q: ^Ring_Queue) {
	q.head = 0
	q.tail = 0
	q.count = 0
}

// Round up to next power of 2 (for ring buffer sizing)
// Returns 0 if n > 2^31 (overflow protection - allocation will fail gracefully)
@(private)
next_power_of_2 :: #force_inline proc(n: u32) -> u32 {
	if n == 0 {return 1}
	// Max power of 2 in u32 is 2^31. If n > 2^31, we can't round up.
	if n > 0x80000000 {return 0}
	// If already a power of 2 at the limit, return it
	if n == 0x80000000 {return n}
	v := n - 1
	v |= v >> 1
	v |= v >> 2
	v |= v >> 4
	v |= v >> 8
	v |= v >> 16
	return v + 1
}

// construct now accepts pointers to the reused scratch memory
@(private)
construct :: proc(filter: Binary_Fuse_8, keys: []u64, ctx: ^Ctx, Q: ^Ring_Queue) -> bool {
	size := len(keys)

	// 1. Populate tables
	for key in keys {
		hash := mix_split(key, filter.seed)
		h0, h1, h2 := get_indices(hash, filter.segment_len, filter.segment_mask, filter.segment_count_less2)

		ctx.t2count[h0] += 1; ctx.t2hash[h0] ~= hash
		ctx.t2count[h1] += 1; ctx.t2hash[h1] ~= hash
		ctx.t2count[h2] += 1; ctx.t2hash[h2] ~= hash
	}

	// 2. Scan for Singletons
	for count, i in ctx.t2count {
		if count == 1 {
			ring_queue_push(Q, u32(i))
		}
	}

	stack_top := size

	// 3. Peeling Loop
	for Q.count > 0 {
		i := ring_queue_pop(Q)

		// If count is not 1, it means it was decremented to 0 by a neighbor already
		if ctx.t2count[i] != 1 {continue}

		hash := ctx.t2hash[i]
		h0, h1, h2 := get_indices(hash, filter.segment_len, filter.segment_mask, filter.segment_count_less2)

		// Determine which slot 'i' corresponds to
		dest_idx: u8 = 0
		if h1 == i {dest_idx = 1} else if h2 == i {dest_idx = 2}

		stack_top -= 1
		ctx.stack[stack_top] = {hash, dest_idx}

		// Remove from graph
		apply_remove :: #force_inline proc(h: u32, hash: u64, ctx: ^Ctx, Q: ^Ring_Queue) {
			when ODIN_DEBUG {
				assert(ctx.t2count[h] > 0, "t2count underflow: decrementing zero")
			}
			ctx.t2count[h] -= 1
			ctx.t2hash[h] ~= hash
			if ctx.t2count[h] == 1 {
				ring_queue_push(Q, h)
			}
		}

		apply_remove(h0, hash, ctx, Q)
		apply_remove(h1, hash, ctx, Q)
		apply_remove(h2, hash, ctx, Q)
	}

	// If stack is not full, graph had cycles
	if stack_top != 0 {return false}

	// 4. Assignment (Unwinding) - #soa provides natural iteration with SOA layout
	for item in ctx.stack {
		// Recompute indices
		h0, h1, h2 := get_indices(item.hash, filter.segment_len, filter.segment_mask, filter.segment_count_less2)

		fp := u8(fingerprint(item.hash))

		// Calculate current value
		val := fp
		val ~= filter.fingerprints[h0]
		val ~= filter.fingerprints[h1]
		val ~= filter.fingerprints[h2]

		// Assign to the target slot branchless-ly
		target_locs := [3]u32{h0, h1, h2}
		filter.fingerprints[target_locs[item.index]] ~= val
	}

	return true
}

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------

@(private)
mix_split :: #force_inline proc(key, seed: u64) -> u64 {
	h := key ~ seed
	h ~= h >> 33; h *= 0xff51afd7ed558ccd
	h ~= h >> 33; h *= 0xc4ceb9fe1a85ec53
	h ~= h >> 33
	return h
}

// SIMD version: hash 4 keys at once
@(private)
mix_split_simd :: #force_inline proc(keys: U64x4, seed: u64) -> U64x4 {
	seed_vec := U64x4{seed, seed, seed, seed}
	c1 := U64x4{0xff51afd7ed558ccd, 0xff51afd7ed558ccd, 0xff51afd7ed558ccd, 0xff51afd7ed558ccd}
	c2 := U64x4{0xc4ceb9fe1a85ec53, 0xc4ceb9fe1a85ec53, 0xc4ceb9fe1a85ec53, 0xc4ceb9fe1a85ec53}

	h := keys ~ seed_vec
	h ~= intrinsics.simd_shr(h, 33); h *= c1
	h ~= intrinsics.simd_shr(h, 33); h *= c2
	h ~= intrinsics.simd_shr(h, 33)
	return h
}

@(private)
fingerprint :: #force_inline proc(hash: u64) -> u64 {
	return hash ~ (hash >> 32)
}

@(private)
get_indices :: #force_inline proc(
	hash: u64,
	seg_len, mask, start_count: u32,
) -> (
	h0, h1, h2: u32,
) {
	// Paper-style: pick a base segment, then add offsets within each segment
	// h0 in segment[base], h1 in segment[base+1], h2 in segment[base+2]
	// start_count = (capacity / seg_len) - 2, precomputed to avoid division AND subtraction

	// Use 128-bit multiply-high for fair segment selection without modulo
	base_seg := u32((u128(hash) * u128(start_count)) >> 64)
	base := base_seg * seg_len

	// Extract independent offsets from different hash bits
	off0 := u32(hash) & mask
	off1 := u32(hash >> 21) & mask
	off2 := u32(hash >> 42) & mask

	h0 = base + off0
	h1 = base + seg_len + off1
	h2 = base + 2 * seg_len + off2

	return
}
