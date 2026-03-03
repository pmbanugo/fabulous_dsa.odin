package capnp

import "core:fmt"
import "core:time"

Benchmark_Result :: struct {
	name:          string,
	iterations:    int,
	total_ns:      i64,
	ns_per_op:     f64,
	ops_per_sec:   f64,
	bytes_per_sec: f64, // 0 if not applicable
	bytes_per_op:  int, // 0 if not applicable
	alloc_count:   int, // 0 if not tracked
}

// Print a benchmark result in a human-readable format
benchmark_print :: proc(r: Benchmark_Result) {
	fmt.printf("  %-38s ", r.name)
	fmt.printf("%d ops  ", r.iterations)
	if r.ns_per_op < 1 {
		fmt.printf("<1 ns/op  ")
	} else {
		fmt.printf("%.0f ns/op  ", r.ns_per_op)
	}
	fmt.printf("%.0f ops/sec", r.ops_per_sec)
	if r.bytes_per_sec > 0 {
		mb_per_sec := r.bytes_per_sec / (1024 * 1024)
		fmt.printf("  %.1f MB/s", mb_per_sec)
	}
	if r.alloc_count > 0 {
		fmt.printf("  %d allocs", r.alloc_count)
	}
	fmt.println()
}

// Run all benchmarks and print results
benchmark_run_all :: proc() {
	fmt.println("=== Cap'n Proto Odin Benchmarks ===")
	fmt.println()

	results: [dynamic]Benchmark_Result
	defer delete(results)

	// Packing benchmarks
	fmt.println("--- Packing ---")
	append(&results, benchmark_pack_zero_heavy(1000))
	benchmark_print(results[len(results) - 1])
	append(&results, benchmark_pack_dense(1000))
	benchmark_print(results[len(results) - 1])
	append(&results, benchmark_pack_mixed(1000))
	benchmark_print(results[len(results) - 1])

	// Unpacking benchmarks
	fmt.println("--- Unpacking ---")
	append(&results, benchmark_unpack_zero_heavy(1000))
	benchmark_print(results[len(results) - 1])
	append(&results, benchmark_unpack_dense(1000))
	benchmark_print(results[len(results) - 1])

	// Build benchmarks
	fmt.println("--- Message Building ---")
	append(&results, benchmark_build_simple_struct(10000))
	benchmark_print(results[len(results) - 1])
	append(&results, benchmark_build_nested_struct(5000))
	benchmark_print(results[len(results) - 1])
	append(&results, benchmark_build_large_list(1000))
	benchmark_print(results[len(results) - 1])

	// Serialization benchmarks
	fmt.println("--- Serialization ---")
	append(&results, benchmark_serialize(5000))
	benchmark_print(results[len(results) - 1])
	append(&results, benchmark_serialize_packed(5000))
	benchmark_print(results[len(results) - 1])

	// Deserialization benchmarks
	fmt.println("--- Deserialization ---")
	append(&results, benchmark_deserialize(5000))
	benchmark_print(results[len(results) - 1])
	append(&results, benchmark_deserialize_packed(5000))
	benchmark_print(results[len(results) - 1])

	// Pool benchmarks
	fmt.println("--- Pooling ---")
	append(&results, benchmark_pool_temp_alloc(5000))
	benchmark_print(results[len(results) - 1])
	append(&results, benchmark_pool_heap_alloc(5000))
	benchmark_print(results[len(results) - 1])
	append(&results, benchmark_pool_reuse(5000))
	benchmark_print(results[len(results) - 1])

	// SIMD specific benchmarks
	fmt.println("--- SIMD Operations ---")
	append(&results, benchmark_compute_tag_simd(100000))
	benchmark_print(results[len(results) - 1])
	append(&results, benchmark_is_zero_word_simd(100000))
	benchmark_print(results[len(results) - 1])

	fmt.println()
	fmt.println("=== Benchmarks Complete ===")
}

// ============================================================================
// Packing Benchmarks
// ============================================================================

benchmark_pack_zero_heavy :: proc(iterations: int) -> Benchmark_Result {
	// 90% zeros, 10% non-zero — typical Cap'n Proto message
	data_size :: 1024 * 8 // 1024 words
	data := make([]byte, data_size)
	defer delete(data)
	// Set every 10th word to non-zero
	for i := 0; i < 1024; i += 10 {
		off := i * 8
		data[off] = u8(i & 0xFF)
		data[off + 1] = u8((i >> 8) & 0xFF)
	}

	start := time.now()
	for _ in 0 ..< iterations {
		packed, _ := pack(data, context.temp_allocator)
		_ = packed
		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name          = "pack_zero_heavy (1024 words)",
		iterations    = iterations,
		total_ns      = total_ns,
		ns_per_op     = ns_per,
		ops_per_sec   = 1e9 / ns_per,
		bytes_per_sec = f64(data_size) * 1e9 / f64(total_ns),
		bytes_per_op  = data_size,
	}
}

benchmark_pack_dense :: proc(iterations: int) -> Benchmark_Result {
	data_size :: 1024 * 8
	data := make([]byte, data_size)
	defer delete(data)
	// Fill all bytes with non-zero values
	for i in 0 ..< data_size {
		data[i] = u8(i % 255) + 1
	}

	start := time.now()
	for _ in 0 ..< iterations {
		packed, _ := pack(data, context.temp_allocator)
		_ = packed
		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name          = "pack_dense (1024 words)",
		iterations    = iterations,
		total_ns      = total_ns,
		ns_per_op     = ns_per,
		ops_per_sec   = 1e9 / ns_per,
		bytes_per_sec = f64(data_size) * 1e9 / f64(total_ns),
		bytes_per_op  = data_size,
	}
}

benchmark_pack_mixed :: proc(iterations: int) -> Benchmark_Result {
	data_size :: 1024 * 8
	data := make([]byte, data_size)
	defer delete(data)
	// Alternating zero and non-zero words
	for i := 0; i < 1024; i += 2 {
		off := i * 8
		for j in 0 ..< 8 {
			data[off + j] = u8((i + j) & 0xFF)
		}
	}

	start := time.now()
	for _ in 0 ..< iterations {
		packed, _ := pack(data, context.temp_allocator)
		_ = packed
		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name          = "pack_mixed (1024 words)",
		iterations    = iterations,
		total_ns      = total_ns,
		ns_per_op     = ns_per,
		ops_per_sec   = 1e9 / ns_per,
		bytes_per_sec = f64(data_size) * 1e9 / f64(total_ns),
		bytes_per_op  = data_size,
	}
}

// ============================================================================
// Unpacking Benchmarks
// ============================================================================

benchmark_unpack_zero_heavy :: proc(iterations: int) -> Benchmark_Result {
	data_size :: 1024 * 8
	data := make([]byte, data_size)
	defer delete(data)
	for i := 0; i < 1024; i += 10 {
		off := i * 8
		data[off] = u8(i & 0xFF)
	}
	packed_data, _ := pack(data)
	defer delete(packed_data)

	start := time.now()
	for _ in 0 ..< iterations {
		unpacked, _ := unpack(packed_data, context.temp_allocator)
		_ = unpacked
		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name          = "unpack_zero_heavy (1024 words)",
		iterations    = iterations,
		total_ns      = total_ns,
		ns_per_op     = ns_per,
		ops_per_sec   = 1e9 / ns_per,
		bytes_per_sec = f64(data_size) * 1e9 / f64(total_ns),
		bytes_per_op  = data_size,
	}
}

benchmark_unpack_dense :: proc(iterations: int) -> Benchmark_Result {
	data_size :: 1024 * 8
	data := make([]byte, data_size)
	defer delete(data)
	for i in 0 ..< data_size {
		data[i] = u8(i % 255) + 1
	}
	packed_data, _ := pack(data)
	defer delete(packed_data)

	start := time.now()
	for _ in 0 ..< iterations {
		unpacked, _ := unpack(packed_data, context.temp_allocator)
		_ = unpacked
		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name          = "unpack_dense (1024 words)",
		iterations    = iterations,
		total_ns      = total_ns,
		ns_per_op     = ns_per,
		ops_per_sec   = 1e9 / ns_per,
		bytes_per_sec = f64(data_size) * 1e9 / f64(total_ns),
		bytes_per_op  = data_size,
	}
}

// ============================================================================
// Message Building Benchmarks
// ============================================================================

benchmark_build_simple_struct :: proc(iterations: int) -> Benchmark_Result {
	start := time.now()
	for _ in 0 ..< iterations {
		mb, _ := message_builder_make(context.temp_allocator)
		root, _ := message_builder_init_root(&mb, 2, 0) // 2 data words, 0 pointers
		struct_builder_set_u32(&root, 0, 42)
		struct_builder_set_u64(&root, 8, 1234567890)
		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name        = "build_simple_struct",
		iterations  = iterations,
		total_ns    = total_ns,
		ns_per_op   = ns_per,
		ops_per_sec = 1e9 / ns_per,
	}
}

benchmark_build_nested_struct :: proc(iterations: int) -> Benchmark_Result {
	start := time.now()
	for _ in 0 ..< iterations {
		mb, _ := message_builder_make(context.temp_allocator)
		root, _ := message_builder_init_root(&mb, 1, 2) // 1 data word, 2 pointers
		struct_builder_set_u32(&root, 0, 42)

		child, _ := struct_builder_init_struct(&root, 0, 1, 0)
		struct_builder_set_u64(&child, 0, 999)

		child2, _ := struct_builder_init_struct(&root, 1, 2, 0)
		struct_builder_set_f64(&child2, 0, 3.14159)
		struct_builder_set_u32(&child2, 8, 100)

		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name        = "build_nested_struct",
		iterations  = iterations,
		total_ns    = total_ns,
		ns_per_op   = ns_per,
		ops_per_sec = 1e9 / ns_per,
	}
}

benchmark_build_large_list :: proc(iterations: int) -> Benchmark_Result {
	start := time.now()
	for _ in 0 ..< iterations {
		mb, _ := message_builder_make(context.temp_allocator)
		root, _ := message_builder_init_root(&mb, 0, 1) // 0 data, 1 pointer

		lb, _ := struct_builder_init_list(&root, 0, .Four_Bytes, 256)
		for i in 0 ..< u32(256) {
			list_builder_set_u32(&lb, i, i * i)
		}

		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name        = "build_large_list (256 u32s)",
		iterations  = iterations,
		total_ns    = total_ns,
		ns_per_op   = ns_per,
		ops_per_sec = 1e9 / ns_per,
	}
}

// ============================================================================
// Serialization Benchmarks
// ============================================================================

benchmark_serialize :: proc(iterations: int) -> Benchmark_Result {
	mb, _ := message_builder_make()
	defer message_builder_destroy(&mb)
	root, _ := message_builder_init_root(&mb, 2, 1)
	struct_builder_set_u32(&root, 0, 42)
	struct_builder_set_u64(&root, 8, 1234567890)

	start := time.now()
	for _ in 0 ..< iterations {
		data, _ := serialize(&mb, context.temp_allocator)
		_ = data
		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name        = "serialize",
		iterations  = iterations,
		total_ns    = total_ns,
		ns_per_op   = ns_per,
		ops_per_sec = 1e9 / ns_per,
	}
}

benchmark_serialize_packed :: proc(iterations: int) -> Benchmark_Result {
	mb, _ := message_builder_make()
	defer message_builder_destroy(&mb)
	root, _ := message_builder_init_root(&mb, 2, 1)
	struct_builder_set_u32(&root, 0, 42)
	struct_builder_set_u64(&root, 8, 1234567890)

	start := time.now()
	for _ in 0 ..< iterations {
		data, _ := serialize_packed(&mb, context.temp_allocator)
		_ = data
		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name        = "serialize_packed",
		iterations  = iterations,
		total_ns    = total_ns,
		ns_per_op   = ns_per,
		ops_per_sec = 1e9 / ns_per,
	}
}

// ============================================================================
// Deserialization Benchmarks
// ============================================================================

benchmark_deserialize :: proc(iterations: int) -> Benchmark_Result {
	mb, _ := message_builder_make()
	defer message_builder_destroy(&mb)
	root, _ := message_builder_init_root(&mb, 2, 1)
	struct_builder_set_u32(&root, 0, 42)
	struct_builder_set_u64(&root, 8, 1234567890)

	serialized, _ := serialize(&mb)
	defer delete(serialized)

	start := time.now()
	for _ in 0 ..< iterations {
		reader, _ := deserialize(serialized, {}, context.temp_allocator)
		_ = reader
		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name         = "deserialize",
		iterations   = iterations,
		total_ns     = total_ns,
		ns_per_op    = ns_per,
		ops_per_sec  = 1e9 / ns_per,
		bytes_per_op = len(serialized),
	}
}

benchmark_deserialize_packed :: proc(iterations: int) -> Benchmark_Result {
	mb, _ := message_builder_make()
	defer message_builder_destroy(&mb)
	root, _ := message_builder_init_root(&mb, 2, 1)
	struct_builder_set_u32(&root, 0, 42)
	struct_builder_set_u64(&root, 8, 1234567890)

	packed_data, _ := serialize_packed(&mb)
	defer delete(packed_data)

	start := time.now()
	for _ in 0 ..< iterations {
		reader, data, _ := deserialize_packed(packed_data, {}, context.temp_allocator)
		_ = reader
		_ = data
		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name         = "deserialize_packed",
		iterations   = iterations,
		total_ns     = total_ns,
		ns_per_op    = ns_per,
		ops_per_sec  = 1e9 / ns_per,
		bytes_per_op = len(packed_data),
	}
}

// ============================================================================
// Pool Benchmarks
// ============================================================================

benchmark_pool_temp_alloc :: proc(iterations: int) -> Benchmark_Result {
	start := time.now()
	for _ in 0 ..< iterations {
		mb, _ := message_builder_make(context.temp_allocator)
		root, _ := message_builder_init_root(&mb, 2, 0)
		struct_builder_set_u32(&root, 0, 42)
		free_all(context.temp_allocator)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name        = "build_temp_allocator (reference)",
		iterations  = iterations,
		total_ns    = total_ns,
		ns_per_op   = ns_per,
		ops_per_sec = 1e9 / ns_per,
	}
}

benchmark_pool_heap_alloc :: proc(iterations: int) -> Benchmark_Result {
	start := time.now()
	for _ in 0 ..< iterations {
		mb, _ := message_builder_make(context.allocator)
		root, _ := message_builder_init_root(&mb, 2, 0)
		struct_builder_set_u32(&root, 0, 42)
		message_builder_destroy(&mb)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name        = "build_heap_allocator (baseline)",
		iterations  = iterations,
		total_ns    = total_ns,
		ns_per_op   = ns_per,
		ops_per_sec = 1e9 / ns_per,
	}
}

benchmark_pool_reuse :: proc(iterations: int) -> Benchmark_Result {
	pool: Segment_Pool
	segment_pool_init(&pool)
	defer segment_pool_destroy(&pool)

	start := time.now()
	for _ in 0 ..< iterations {
		pmb: Pooled_Message_Builder
		pooled_message_builder_init(&pmb, &pool)

		root, _ := pooled_message_builder_init_root(&pmb, 2, 0)
		struct_builder_set_u32(&root, 0, 42)

		pooled_message_builder_destroy(&pmb)
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	ns_per := f64(total_ns) / f64(iterations)

	return Benchmark_Result {
		name        = "build_with_pool",
		iterations  = iterations,
		total_ns    = total_ns,
		ns_per_op   = ns_per,
		ops_per_sec = 1e9 / ns_per,
	}
}

// ============================================================================
// SIMD-Specific Benchmarks
// ============================================================================

benchmark_compute_tag_simd :: proc(iterations: int) -> Benchmark_Result {
	// Process 1024 words per iteration to get measurable timing
	batch :: 1024
	words: [batch][8]u8
	for i in 0 ..< batch {
		words[i] = {u8(i & 0xFF), 0, u8((i >> 2) & 0xFF), 0, u8((i >> 4) & 0xFF), 0, 0, u8(i & 1)}
	}

	sink: u8 = 0
	start := time.now()
	for _ in 0 ..< iterations {
		for i in 0 ..< batch {
			sink ~= compute_tag_simd(&words[i])
		}
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	total_ops := iterations * batch
	ns_per := f64(total_ns) / f64(total_ops)
	// Prevent dead code elimination
	if sink == 0xFF { fmt.println("sink") }

	return Benchmark_Result {
		name        = "compute_tag_simd (1024 words)",
		iterations  = total_ops,
		total_ns    = total_ns,
		ns_per_op   = ns_per,
		ops_per_sec = 1e9 / ns_per,
	}
}

benchmark_is_zero_word_simd :: proc(iterations: int) -> Benchmark_Result {
	batch :: 1024
	words: [batch]u64
	// Half zeros, half non-zero
	for i in 0 ..< batch {
		words[i] = u64(i % 2)
	}

	sink: bool = false
	start := time.now()
	for _ in 0 ..< iterations {
		for i in 0 ..< batch {
			sink = sink ~ is_zero_word_simd(&words[i])
		}
	}
	elapsed := time.diff(start, time.now())
	total_ns := time.duration_nanoseconds(elapsed)
	total_ops := iterations * batch
	ns_per := f64(total_ns) / f64(total_ops)
	if sink { fmt.print("") }

	return Benchmark_Result {
		name        = "is_zero_word_simd (1024 words)",
		iterations  = total_ops,
		total_ns    = total_ns,
		ns_per_op   = ns_per,
		ops_per_sec = 1e9 / ns_per,
	}
}


