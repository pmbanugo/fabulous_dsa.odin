# Cap'n Proto for Odin

A pure Odin implementation of the [Cap'n Proto](https://capnproto.org/) serialization format.

## Features

- **Zero-copy deserialization** — Read data directly from byte buffers
- **Builder API** — Construct messages with structs, lists, text, and data blobs
- **Reader API** — Traverse messages with pointer validation and security limits
- **Packing compression** — Reduce message size for transmission
- **Security hardened** — Traversal limits, nesting limits, bounds checking
- **SIMD optimized** — Vectorized tag computation, hardware popcount, bulk memory ops
- **Segment pooling** — Reuse allocations for high-throughput message building

## Usage

```odin
import "capnp"

// Build a message
mb: capnp.Message_Builder
capnp.message_builder_init(&mb)
defer capnp.message_builder_destroy(&mb)

root, _ := capnp.message_builder_init_root(&mb, 1, 1)  // 1 data word, 1 pointer
capnp.struct_builder_set_u32(&root, 0, 42)
capnp.struct_builder_set_text(&root, 0, "Hello")

// Serialize
data, _ := capnp.serialize(&mb)
defer delete(data)

// Deserialize and read
reader, _ := capnp.deserialize(data)
defer capnp.message_reader_destroy(&reader)

sr, _ := capnp.message_reader_get_root(&reader)
value := capnp.struct_reader_get_u32(&sr, 0)
text, _ := capnp.struct_reader_get_text(&sr, 0)
```

## Packed Serialization

For bandwidth-sensitive use cases, pack messages before sending:

```odin
// Serialize + pack in one step
packed, _ := capnp.serialize_packed(&mb)
defer delete(packed)

// Unpack + deserialize
reader, unpacked_data, _ := capnp.deserialize_packed(packed)
defer delete(unpacked_data)
defer capnp.message_reader_destroy(&reader)
```

## Segment Pooling

For high-throughput scenarios (e.g., building many messages in a loop), use segment pooling to reuse allocations:

```odin
// Initialize a pool once
pool: capnp.Segment_Pool
capnp.segment_pool_init(&pool)
defer capnp.segment_pool_destroy(&pool)

for request in requests {
    pmb: capnp.Pooled_Message_Builder
    capnp.pooled_message_builder_init(&pmb, &pool)
    
    // Use the same builder API as Message_Builder
    root, _ := capnp.pooled_message_builder_init_root(&pmb, 2, 1)
    capnp.struct_builder_set_u32(&root, 0, 42)
    capnp.struct_builder_set_text(&root, 0, "Hello")
    
    // Serialize via segment manager
    data, _ := capnp.serialize_segments(&pmb.segments)
    defer delete(data)
    
    // Segments returned to pool instead of freed
    capnp.pooled_message_builder_destroy(&pmb)
}
```

## Running Tests

Run all tests:

```sh
# Full test suite (175 tests)
odin test capnp/tests/

# With memory leak detection
odin test capnp/tests/ -debug

# Run a specific test
odin test capnp/tests/ -define:ODIN_TEST_NAMES=capnp_tests.test_security_list_pointer_out_of_bounds
```

## Benchmarks

Run the benchmark suite:

```sh
odin run capnp/benchmark_runner/ -o:speed
```

Sample output (Apple M-series):

| Operation | Performance |
|-----------|-------------|
| Pack (1024 zero-heavy words) | ~791K ops/sec, 6.2 MB/s |
| Unpack (1024 dense words) | ~1.97M ops/sec, 15.5 MB/s |
| Build simple struct | ~8.8M ops/sec |
| Serialize | ~29M ops/sec |
| Deserialize | ~37M ops/sec |
| SIMD tag computation | ~1.3B words/sec |
| SIMD zero check | ~2.3B words/sec |

## Interoperability Testing

The test suite includes interoperability tests that verify compatibility with the reference Cap'n Proto implementation.

### Requirements (Optional)

To regenerate test vectors, you need the `capnp` command-line tool:

```sh
# macOS
brew install capnp

# Ubuntu/Debian
apt install capnproto

# Verify installation
capnp --version
```

### Generating Test Vectors

Test vectors are generated from `tests/test_schemas/test.capnp`:

```sh
cd capnp/tests/test_schemas

# Generate a Point message
echo '(x = 100, y = 200)' | capnp encode test.capnp Point | xxd -i

# Generate a Person message
echo '(name = "Alice", age = 30)' | capnp encode test.capnp Person | xxd -i

# Generate a composite list
echo '(entries = [(key = 1, value = 100), (key = 2, value = 200)])' | capnp encode test.capnp Table | xxd -i
```

The output bytes are embedded directly in `tests/interop_tests.odin`.

**Note:** The `capnp` tool is only needed to regenerate test vectors. All tests run without it since the expected bytes are embedded in the test files.

## Package Structure

| File | Description |
|------|-------------|
| `types.odin` | Core types: Word, pointers, element sizes |
| `errors.odin` | Error type definitions |
| `pointer.odin` | Pointer encoding/decoding |
| `segment.odin` | Memory segment management |
| `message.odin` | Frame header serialization |
| `builder.odin` | Message/Struct/List builders |
| `reader.odin` | Message/Struct/List readers |
| `validation.odin` | Pointer validation, security limits |
| `serialize.odin` | Serialize/deserialize functions |
| `pack.odin` | Packing compression |
| `simd.odin` | SIMD tag computation, zero check (internal ctz bit iteration) |
| `pool.odin` | Segment pooling, pooled message builder |
| `benchmark.odin` | Performance benchmark suite |

## Test Suite

| File | Tests | Description |
|------|-------|-------------|
| `tests/pointer_tests.odin` | 20 | Pointer encoding/decoding |
| `tests/segment_tests.odin` | 14 | Segment allocation |
| `tests/frame_tests.odin` | 18 | Frame header parsing |
| `tests/builder_tests.odin` | 27 | All builder operations |
| `tests/reader_tests.odin` | 16 | All reader operations |
| `tests/roundtrip_tests.odin` | 10 | Build → Serialize → Read |
| `tests/security_tests.odin` | 16 | Security limit enforcement |
| `tests/pack_tests.odin` | 26 | Packing compression |
| `tests/interop_tests.odin` | 17 | Reference implementation compatibility |
| `tests/optimization_tests.odin` | 11 | SIMD, pooling optimizations |

## Documentation

- [DESIGN.md](DESIGN.md) - Architecture and design decisions
- [IMPLEMENTATION.md](IMPLEMENTATION.md) - Implementation roadmap and progress

## Limitations

- No RPC support (serialization only)
- No schema compiler / code generation
- Little-endian architectures only (x86_64, ARM64)
- No capability pointers (Other pointer type)

## License

See the repository [LICENSE](../LICENSE) file.
