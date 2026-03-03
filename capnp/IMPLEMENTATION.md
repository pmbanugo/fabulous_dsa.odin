# Cap'n Proto Implementation Roadmap

This document tracks the implementation progress for Cap'n Proto in Odin. Each phase builds on the previous and can be completed in separate sessions.

## Progress Legend

- ⬜ Not started
- 🟡 In progress
- ✅ Complete
- ⏭️ Skipped (optional/deferred)

---

## Phase 1: Core Infrastructure

**Goal:** Establish foundational types, pointer encoding/decoding, and segment management.

### 1.1 Core Types (`types.odin`)

| Task                              | Status | Notes                            |
| --------------------------------- | ------ | -------------------------------- |
| Define `Word` type (u64)          | ✅     |                                  |
| Define `Pointer_Kind` enum        | ✅     | Struct=0, List=1, Far=2, Other=3 |
| Define `Element_Size` enum        | ✅     | 0-7 element size codes           |
| Define `Struct_Pointer` bit_field | ✅     | 2+30+16+16 bits                  |
| Define `List_Pointer` bit_field   | ✅     | 2+30+3+29 bits                   |
| Define `Far_Pointer` bit_field    | ✅     | 2+1+29+32 bits                   |
| Define `Pointer` raw_union        | ✅     | Union of all pointer types       |
| Define `Error` enum               | ✅     | All error codes (in errors.odin) |

### 1.2 Pointer Encoding/Decoding (`pointer.odin`)

| Task                            | Status | Notes                              |
| ------------------------------- | ------ | ---------------------------------- |
| `pointer_get_kind`              | ✅     | Extract kind from raw u64          |
| `pointer_is_null`               | ✅     | Check if pointer is null           |
| `struct_pointer_encode`         | ✅     | Create struct pointer from parts   |
| `struct_pointer_decode`         | ✅     | Extract parts from struct pointer  |
| `struct_pointer_target`         | ✅     | Calculate target address           |
| `list_pointer_encode`           | ✅     | Create list pointer from parts     |
| `list_pointer_decode`           | ✅     | Extract parts from list pointer    |
| `list_pointer_target`           | ✅     | Calculate target address           |
| `far_pointer_encode`            | ✅     | Create far pointer from parts      |
| `far_pointer_decode`            | ✅     | Extract parts from far pointer     |
| `element_size_bits`             | ✅     | Get bits per element for size code |
| Unit tests for pointer encoding | ✅     | Roundtrip tests                    |

### 1.3 Segment Management (`segment.odin`)

Uses Odin's `core:mem` allocators for actual memory allocation.

| Task                            | Status | Notes                                                  |
| ------------------------------- | ------ | ------------------------------------------------------ |
| Define `Segment` struct         | ✅     | id, data []Word, used, capacity                        |
| Define `Segment_Manager` struct | ✅     | segments, allocator (Odin allocator), default_seg_size |
| `segment_manager_init`          | ✅     | Initialize with Odin allocator (heap, arena, etc.)     |
| `segment_manager_destroy`       | ✅     | Free all segment memory via allocator                  |
| `segment_manager_allocate`      | ✅     | Allocate words, create new segment if needed           |
| `segment_manager_get_segment`   | ✅     | Get segment by ID                                      |
| `segment_allocate`              | ✅     | Allocate words within a segment                        |
| `segment_get_word`              | ✅     | Get word at offset                                     |
| `segment_set_word`              | ✅     | Set word at offset                                     |
| `segment_get_bytes`             | ✅     | Get byte slice at offset                               |

### 1.4 Message Framing (`message.odin`)

| Task                         | Status | Notes                          |
| ---------------------------- | ------ | ------------------------------ |
| Define `Frame_Header` struct | ✅     | segment_count, segment_sizes   |
| `frame_header_size`          | ✅     | Calculate header size in bytes |
| `serialize_frame_header`     | ✅     | Write header to byte slice     |
| `deserialize_frame_header`   | ✅     | Parse header from byte slice   |
| `serialize_segments`         | ✅     | Write all segments to bytes    |
| `deserialize_segments`       | ✅     | Parse segments from bytes      |
| Unit tests for framing       | ✅     | Roundtrip tests                |

### Phase 1 Deliverables

- [x] All core types defined and compiling
- [x] Pointer encoding/decoding with tests
- [x] Segment management using Odin allocators working
- [x] Message framing serialize/deserialize

---

## Phase 2: Builder API

**Goal:** Implement the write path for constructing Cap'n Proto messages.

### 2.1 Message Builder (`builder.odin`)

| Task                            | Status | Notes                                                     |
| ------------------------------- | ------ | --------------------------------------------------------- |
| Define `Message_Builder` struct | ✅     | Contains Segment_Manager                                  |
| `message_builder_init`          | ✅     | Pointer-based, default: context.allocator                 |
| `message_builder_make`          | ✅     | Value-based, default: context.allocator                   |
| `message_builder_destroy`       | ✅     | Free all memory (delete)                                  |
| `message_builder_clear`         | ✅     | Reset for reuse, keeps capacity (clear)                   |
| `message_builder_init_root`     | ✅     | Initialize root struct, returns `(Struct_Builder, Error)` |
| `message_builder_get_segments`  | ✅     | Get segment data for serialization                        |
| `message_builder_total_words`   | ✅     | Total words used across segments                          |

### 2.2 Struct Builder (`builder.odin`)

| Task                              | Status | Notes                                  |
| --------------------------------- | ------ | -------------------------------------- |
| Define `Struct_Builder` struct    | ✅     | segment, data ptr, pointers ptr, sizes |
| `struct_builder_set_bool`         | ✅     | Set bit in data section                |
| `struct_builder_set_u8`           | ✅     |                                        |
| `struct_builder_set_u16`          | ✅     |                                        |
| `struct_builder_set_u32`          | ✅     |                                        |
| `struct_builder_set_u64`          | ✅     |                                        |
| `struct_builder_set_i8`           | ✅     |                                        |
| `struct_builder_set_i16`          | ✅     |                                        |
| `struct_builder_set_i32`          | ✅     |                                        |
| `struct_builder_set_i64`          | ✅     |                                        |
| `struct_builder_set_f32`          | ✅     |                                        |
| `struct_builder_set_f64`          | ✅     |                                        |
| `struct_builder_init_struct`      | ✅     | Initialize nested struct pointer       |
| `struct_builder_init_list`        | ✅     | Initialize list pointer                |
| `struct_builder_init_struct_list` | ✅     | Initialize composite list              |
| `struct_builder_set_text`         | ✅     | Set text blob                          |
| `struct_builder_set_data`         | ✅     | Set data blob                          |

### 2.3 List Builder (`builder.odin`)

| Task                         | Status | Notes                                         |
| ---------------------------- | ------ | --------------------------------------------- |
| Define `List_Builder` struct | ✅     | segment, ptr, count, step, sizes              |
| `list_builder_set_bool`      | ✅     | Bit packing                                   |
| `list_builder_set_u8`        | ✅     |                                               |
| `list_builder_set_u16`       | ✅     |                                               |
| `list_builder_set_u32`       | ✅     |                                               |
| `list_builder_set_u64`       | ✅     |                                               |
| `list_builder_set_i8`        | ✅     |                                               |
| `list_builder_set_i16`       | ✅     |                                               |
| `list_builder_set_i32`       | ✅     |                                               |
| `list_builder_set_i64`       | ✅     |                                               |
| `list_builder_set_f32`       | ✅     |                                               |
| `list_builder_set_f64`       | ✅     |                                               |
| `list_builder_set_pointer`   | ✅     | For pointer lists                             |
| `list_builder_get_struct`    | ✅     | Get struct builder for composite list element |

### 2.4 Serialization (`serialize.odin`)

| Task                  | Status | Notes                |
| --------------------- | ------ | -------------------- |
| `serialize`           | ✅     | Message to bytes     |
| `serialize_to_writer` | ✅     | Message to io.Writer |

### Phase 2 Deliverables

- [x] Can build simple structs with primitives
- [x] Can build nested structs
- [x] Can build primitive lists
- [x] Can build struct lists (composite)
- [x] Can set text and data blobs
- [x] Serialization to bytes working

---

## Phase 3: Reader API

**Goal:** Implement the read path with pointer validation and security limits.

### 3.1 Message Reader (`reader.odin`)

| Task                           | Status | Notes                          |
| ------------------------------ | ------ | ------------------------------ |
| Define `Message_Reader` struct | ✅     | segments, limits               |
| Define `Read_Limits` struct    | ✅     | traversal_limit, nesting_limit |
| `message_reader_from_bytes`    | ✅     | Deserialize with validation    |
| `message_reader_from_segments` | ✅     | Direct segment access          |
| `message_reader_get_root`      | ✅     | Get root struct reader         |

### 3.2 Struct Reader (`reader.odin`)

| Task                          | Status | Notes                                   |
| ----------------------------- | ------ | --------------------------------------- |
| Define `Struct_Reader` struct | ✅     | segment, data, pointers, sizes, nesting |
| `struct_reader_get_bool`      | ✅     | With default                            |
| `struct_reader_get_u8`        | ✅     |                                         |
| `struct_reader_get_u16`       | ✅     |                                         |
| `struct_reader_get_u32`       | ✅     |                                         |
| `struct_reader_get_u64`       | ✅     |                                         |
| `struct_reader_get_i8`        | ✅     |                                         |
| `struct_reader_get_i16`       | ✅     |                                         |
| `struct_reader_get_i32`       | ✅     |                                         |
| `struct_reader_get_i64`       | ✅     |                                         |
| `struct_reader_get_f32`       | ✅     |                                         |
| `struct_reader_get_f64`       | ✅     |                                         |
| `struct_reader_get_struct`    | ✅     | With pointer validation                 |
| `struct_reader_get_list`      | ✅     | With pointer validation                 |
| `struct_reader_get_text`      | ✅     | Returns string                          |
| `struct_reader_get_data`      | ✅     | Returns []byte                          |
| `struct_reader_has_pointer`   | ✅     | Check if pointer is non-null            |

### 3.3 List Reader (`reader.odin`)

| Task                        | Status | Notes               |
| --------------------------- | ------ | ------------------- |
| Define `List_Reader` struct | ✅     |                     |
| `list_reader_len`           | ✅     | Element count       |
| `list_reader_get_bool`      | ✅     |                     |
| `list_reader_get_u8`        | ✅     |                     |
| `list_reader_get_u16`       | ✅     |                     |
| `list_reader_get_u32`       | ✅     |                     |
| `list_reader_get_u64`       | ✅     |                     |
| `list_reader_get_i8`        | ✅     |                     |
| `list_reader_get_i16`       | ✅     |                     |
| `list_reader_get_i32`       | ✅     |                     |
| `list_reader_get_i64`       | ✅     |                     |
| `list_reader_get_f32`       | ✅     |                     |
| `list_reader_get_f64`       | ✅     |                     |
| `list_reader_get_struct`    | ✅     | For composite lists |
| `list_reader_get_text`      | ✅     | For List(Text)      |
| `list_reader_get_data`      | ✅     | For List(Data)      |

### 3.4 Pointer Validation (`validation.odin`)

| Task                      | Status | Notes                        |
| ------------------------- | ------ | ---------------------------- |
| `validate_struct_pointer` | ✅     | Bounds check                 |
| `validate_list_pointer`   | ✅     | Bounds check                 |
| `follow_far_pointer`      | ✅     | Resolve far pointers         |
| `check_traversal_limit`   | ✅     | Update and check limit       |
| `check_nesting_limit`     | ✅     | Check depth                  |
| `bounds_check`            | ✅     | Verify offset+size in bounds |
| `validate_text`           | ✅     | NUL-termination check        |

### 3.5 Deserialization (`serialize.odin`)

| Task                      | Status | Notes                       |
| ------------------------- | ------ | --------------------------- |
| `deserialize`             | ✅     | Bytes to Message_Reader     |
| `deserialize_from_reader` | ✅     | io.Reader to Message_Reader |

### Phase 3 Deliverables

- [x] Can read all primitive types
- [x] Can traverse nested structs
- [x] Can read all list types
- [x] Can read text and data
- [x] Pointer validation working
- [x] Security limits enforced
- [x] Far pointer resolution working

---

## Phase 4: Packing Compression

**Goal:** Implement the packing algorithm for bandwidth-efficient serialization.

### 4.1 Packing (`pack.odin`)

| Task                           | Status | Notes              |
| ------------------------------ | ------ | ------------------ |
| `pack`                         | ✅     | Compress bytes     |
| `pack_to_writer`               | ✅     | Stream packing     |
| `pack_word`                    | ✅     | Pack single word   |
| `unpack`                       | ✅     | Decompress bytes   |
| `unpack_from_reader`           | ✅     | Stream unpacking   |
| `unpack_word`                  | ✅     | Unpack single word |
| Handle tag 0x00 (zero runs)    | ✅     |                    |
| Handle tag 0xFF (literal runs) | ✅     |                    |
| Unit tests for packing         | ✅     | 26 tests           |

### 4.2 Packed Serialization

| Task                 | Status | Notes                |
| -------------------- | ------ | -------------------- |
| `serialize_packed`   | ✅     | Serialize + pack     |
| `deserialize_packed` | ✅     | Unpack + deserialize |

### Phase 4 Deliverables

- [x] Packing compression working
- [x] Unpacking decompression working
- [x] Packed serialization end-to-end
- [x] Significant size reduction on typical messages

---

## Phase 5: Testing & Interoperability

**Goal:** Comprehensive testing and validation against reference implementation.

### 5.1 Unit Tests

| Task                             | Status | Notes                    |
| -------------------------------- | ------ | ------------------------ |
| Pointer encoding roundtrip tests | ✅     | tests/pointer_tests.odin |
| Segment allocation tests         | ✅     | tests/segment_tests.odin |
| Frame header tests               | ✅     | tests/frame_tests.odin   |
| Builder primitive tests          | ✅     | tests/builder_tests.odin |
| Builder nested struct tests      | ✅     | tests/builder_tests.odin |
| Builder list tests               | ✅     | tests/builder_tests.odin |
| Reader primitive tests           | ✅     | tests/reader_tests.odin  |
| Reader nested struct tests       | ✅     | tests/reader_tests.odin  |
| Reader list tests                | ✅     | tests/reader_tests.odin  |
| Packing tests                    | ✅     | tests/pack_tests.odin    |

### 5.2 Roundtrip Tests

| Task                     | Status | Notes                               |
| ------------------------ | ------ | ----------------------------------- |
| Simple struct roundtrip  | ✅     | tests/roundtrip_tests.odin          |
| Complex nested roundtrip | ✅     | Person/AddressBook example          |
| All list types roundtrip | ✅     | Void, Bit, Byte, u16-u64, Composite |
| Text/Data roundtrip      | ✅     | tests/roundtrip_tests.odin          |
| Packed roundtrip         | ✅     | tests/roundtrip_tests.odin          |

### 5.3 Security Tests

| Task                    | Status | Notes                             |
| ----------------------- | ------ | --------------------------------- |
| Out-of-bounds pointer   | ✅     | tests/security_tests.odin         |
| Deeply nested message   | ✅     | Nesting limit exceeded test       |
| Large traversal message | ✅     | Traversal limit exceeded test     |
| Amplification attack    | ✅     | Void list amplification test      |
| Malformed frame header  | ✅     | Segment count/size overflow tests |
| Truncated message       | ✅     | Multiple truncation scenarios     |

### 5.4 Interoperability Tests

| Task                                   | Status | Notes                             |
| -------------------------------------- | ------ | --------------------------------- |
| Generate test messages with capnp tool | ✅     | tests/test_schemas/test.capnp     |
| Read messages from reference impl      | ✅     | Reference byte vectors from capnp |
| Write messages readable by reference   | ✅     | Builder output verified           |
| Packed message interop                 | ✅     | tests/interop_tests.odin          |

### Phase 5 Deliverables

- [x] All unit tests passing (164 tests in capnp/tests/)
- [x] All roundtrip tests passing
- [x] Security tests confirm limits work
- [x] Can exchange messages with reference format (capnp encode output)

---

## Phase 6: Optimization

**Goal:** Performance improvements using SIMD and other techniques.

### 6.1 SIMD Optimizations (`simd.odin`)

| Task                      | Status | Notes                                           |
| ------------------------- | ------ | ----------------------------------------------- |
| `pack_word_simd`          | ✅     | SIMD tag computation + ctz byte gather           |
| `unpack_word_simd`        | ✅     | ctz-based scatter of packed bytes by tag          |
| `compute_tag_simd`        | ✅     | SIMD lanes_ne + select + reduce_or               |
| `is_zero_word_simd`       | ✅     | u64 comparison                                   |
| ctz bit iteration         | ✅     | count_trailing_zeros replaces branch-per-bit      |
| Integrated into pack.odin | ✅     | compute_tag, count_ones, is_zero_word, ctz gather |

### 6.2 Memory Optimizations (`pool.odin`)

| Task                       | Status | Notes                                   |
| -------------------------- | ------ | --------------------------------------- |
| `Segment_Pool` struct               | ✅     | Pool with MAX_POOL_SIZE=16 limit              |
| `segment_pool_acquire`              | ✅     | Get from pool or allocate new                 |
| `segment_pool_release`              | ✅     | Return to pool (zeroed on reacquire)          |
| `Pooled_Message_Builder`            | ✅     | Builder using pool for segment reuse          |
| `pooled_message_builder_init_root`  | ✅     | Full builder API support for pooled builder   |
| `pooled_message_builder_get_segments` | ✅   | Get segment data for serialization            |

### 6.3 Benchmarks (`benchmark.odin`)

| Task                       | Status | Notes                                    |
| -------------------------- | ------ | ---------------------------------------- |
| Pack benchmarks            | ✅     | Zero-heavy, dense, mixed (1024 words)    |
| Unpack benchmarks          | ✅     | Zero-heavy, dense (1024 words)           |
| Build benchmarks           | ✅     | Simple, nested, large list               |
| Serialize benchmarks       | ✅     | Packed and unpacked                      |
| Deserialize benchmarks     | ✅     | Packed and unpacked                      |
| Pool benchmarks            | ✅     | Temp vs heap vs pool comparison          |
| SIMD micro-benchmarks      | ✅     | Tag computation, zero-check              |

### Phase 6 Deliverables

- [x] SIMD tag computation, ctz bit iteration, hardware popcount integrated into pack.odin
- [x] Enumerated array lookup tables for element_size_bits/bytes in pointer.odin
- [x] Segment pooling with configurable pool size
- [x] Pooled message builder with full builder API (init_root, set_*, init_struct, set_text)
- [x] Comprehensive benchmark suite (17 benchmarks across all operations)
- [x] Pool benchmarks compare temp vs heap vs pool (pooling shows improvement over heap)
- [x] 175 tests total, all passing
- [x] All 164 original tests still pass after optimizations

---

## File Checklist

| File                                  | Phase | Status |
| ------------------------------------- | ----- | ------ |
| `capnp/capnp.odin`                    | 1     | ✅     |
| `capnp/types.odin`                    | 1     | ✅     |
| `capnp/errors.odin`                   | 1     | ✅     |
| `capnp/pointer.odin`                  | 1     | ✅     |
| `capnp/segment.odin`                  | 1     | ✅     |
| `capnp/message.odin`                  | 1     | ✅     |
| `capnp/builder.odin`                  | 2     | ✅     |
| `capnp/reader.odin`                   | 3     | ✅     |
| `capnp/validation.odin`               | 3     | ✅     |
| `capnp/serialize.odin`                | 2-3   | ✅     |
| `capnp/pack.odin`                     | 4     | ✅     |
| `capnp/tests/pointer_tests.odin`      | 5     | ✅     |
| `capnp/tests/segment_tests.odin`      | 5     | ✅     |
| `capnp/tests/frame_tests.odin`        | 5     | ✅     |
| `capnp/tests/builder_tests.odin`      | 5     | ✅     |
| `capnp/tests/reader_tests.odin`       | 5     | ✅     |
| `capnp/tests/roundtrip_tests.odin`    | 5     | ✅     |
| `capnp/tests/security_tests.odin`     | 5     | ✅     |
| `capnp/tests/pack_tests.odin`         | 5     | ✅     |
| `capnp/tests/interop_tests.odin`      | 5     | ✅     |
| `capnp/tests/test_schemas/test.capnp` | 5     | ✅     |
| `capnp/simd.odin`                     | 6     | ✅     |
| `capnp/pool.odin`                     | 6     | ✅     |
| `capnp/benchmark.odin`                | 6     | ✅     |
| `capnp/benchmark_runner/main.odin`    | 6     | ✅     |
| `capnp/tests/optimization_tests.odin` | 6     | ✅     |

---

## Session Log

Track implementation sessions here:

| Date       | Phase | Work Done                                                                                                         | Next Steps                       |
| ---------- | ----- | ----------------------------------------------------------------------------------------------------------------- | -------------------------------- |
| 2026-01-30 | 1     | Core types, pointer encoding, segment management, message framing                                                 | Phase 2: Builder API             |
| 2026-01-31 | 2     | Message/Struct/List Builders, serialization, 17 new tests                                                         | Phase 3: Reader API              |
| 2026-01-31 | 3     | Reader API, validation, deserialization, 13 new reader tests                                                      | Phase 4: Packing                 |
| 2026-02-01 | 4     | Packing/unpacking compression, serialize_packed/deserialize_packed, 25 new tests                                  | Phase 5: Testing                 |
| 2026-02-02 | 5     | Comprehensive test suite: 84 tests (pointer, segment, frame, builder, reader, roundtrip, security, pack, interop) | Phase 6: Optimization (optional) |
| 2026-02-03 | 5     | Fixed security_list_pointer_out_of_bounds test, added capnp encode reference tests (247 total tests)              | Phase 6: Optimization (optional) |
| 2026-03-03 | 6     | SIMD optimizations (simd.odin), segment pooling (pool.odin), benchmarks, 22 new tests (186 total)                 | Phase 6 fixes                    |
| 2026-03-03 | 6     | Fixed benchmarks (pool vs heap), removed dead code (simd_zero/copy, Small_Message_Buffer), added pooled builder API | Complete                         |

---

## Notes

### Decisions Made

- Phase 5: Test suite organized into separate files by category for maintainability
- Phase 5: Created test_schemas/test.capnp for generating reference byte vectors with `capnp encode`
- Phase 5: Added 7 new interop tests using byte vectors from the reference `capnp` tool

### Issues Encountered

- (Record any problems and solutions)

### Future Enhancements

- Schema compiler integration
- Code generation from .capnp files
- RPC support (separate package)
