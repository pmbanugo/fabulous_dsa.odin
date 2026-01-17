# Binary Fuse Filter

A high-performance, space-efficient probabilistic data structure for approximate set membership testing.

Binary fuse filters answer the question: _"Is this element in the set?"_ with either **"definitely not"** or **"probably yes"** (with a small false positive rate of ~0.4%).

## When to Use Binary Fuse Filters

Binary fuse filters are ideal when you have:

- **Static datasets** — All keys are known at construction time
- **Large sets** — Best suited for 10,000+ keys (for smaller sets, consider xor filters)
- **Memory-constrained environments** — Uses only ~12.5% overhead vs 44% for Bloom filters
- **Read-heavy workloads** — Immutable after construction, optimized for fast queries

### Common Use Cases

| Use Case                 | Why Binary Fuse Filters?                       |
| ------------------------ | ---------------------------------------------- |
| Database key lookups     | Avoid expensive disk I/O for non-existent keys |
| Network packet filtering | Fast in-memory checks at line speed            |
| Caching systems          | Quickly check if an item might be cached       |
| Spell checkers           | Efficiently store large dictionaries           |
| URL blocklists           | Compact storage of millions of URLs            |
| LSM-tree storage engines | Skip SSTable reads for missing keys            |

### Comparison with Alternatives

| Feature            | Binary Fuse                    | Bloom Filter              | Cuckoo Filter |
| ------------------ | ------------------------------ | ------------------------- | ------------- |
| Space efficiency   | **Best** (~1.125 bits/key/bit) | Poor (~1.44 bits/key/bit) | Good          |
| Query speed        | **Fast** (3 memory accesses)   | Varies                    | Fast          |
| Construction speed | **Fast**                       | Fast                      | Moderate      |
| Supports deletion  | ❌                             | ❌                        | ✅            |
| Supports insertion | ❌                             | ✅                        | ✅            |

**Choose binary fuse filters when** you need maximum space efficiency and your dataset doesn't change after construction.

## Usage

### Creating a Filter

```odin
import bf "binary_fuse_filters"

// Your unique keys
keys := []u64{1001, 2002, 3003, 4004, 5005}

// Build the filter
filter, ok := bf.create(keys)
if !ok {
    // Handle construction failure (rare, usually due to allocation failure)
    return
}
defer bf.destroy(&filter)
```

### Checking Membership

```odin
// Single key lookup
if bf.contain(filter, 1001) {
    // Key is probably in the set (~0.4% false positive rate)
}

if !bf.contain(filter, 9999) {
    // Key is definitely NOT in the set (no false negatives)
}
```

### Batch Lookups (SIMD-accelerated)

For high-throughput scenarios, use batch lookups to process multiple keys efficiently:

```odin
keys_to_check := []u64{1001, 9999, 2002, 8888}
results := make([]bool, len(keys_to_check))
defer delete(results)

bf.contain_batch(filter, keys_to_check, results)

for result, i in results {
    if result {
        fmt.printf("Key %d: probably present\n", keys_to_check[i])
    } else {
        fmt.printf("Key %d: definitely absent\n", keys_to_check[i])
    }
}
```

### Custom Allocators

```odin
// Use a custom allocator for the filter's persistent storage
filter, ok := bf.create(keys, my_allocator)

// Note: Transient construction memory uses context.temp_allocator
```

## API Reference

| Procedure                                                  | Description                                                     |
| ---------------------------------------------------------- | --------------------------------------------------------------- |
| `create(keys: []u64, allocator?) -> (Binary_Fuse_8, bool)` | Build a filter from unique keys. Returns `ok=false` on failure. |
| `destroy(filter: ^Binary_Fuse_8)`                          | Free filter memory.                                             |
| `contain(filter, key: u64) -> bool`                        | Check if a key is probably in the set.                          |
| `contain_batch(filter, keys: []u64, results: []bool)`      | SIMD-accelerated batch membership check.                        |

## Performance Characteristics

### Space Efficiency

- **~9 bits per key** for 8-bit fingerprints
- **~12.5% overhead** compared to the theoretical minimum
- Significantly more compact than Bloom filters

### False Positive Rate

- **~0.4%** with 8-bit fingerprints (this implementation)
- Formula: ε ≈ 1/2^k where k = fingerprint bits
- **Zero false negatives** — if `contain` returns `false`, the key is definitely not in the set

### Query Performance

- **3 random memory accesses** per lookup
- Memory-bound operation — actual speed depends on cache behavior
- Batch operations amortize overhead and improve cache utilization

### Construction

- O(n) expected time
- Uses a probabilistic "peeling" algorithm
- Very rare construction failures (<1%) trigger automatic retry with a new seed

## Technical Background

Binary fuse filters are a refinement of xor filters, introduced to improve both space efficiency and construction speed. The key innovation is **segmented hashing**: the filter array is divided into power-of-two sized segments, and each key maps to exactly 3 consecutive segments. This improves CPU cache utilization during both construction and queries.

The filter works by:

1. **Construction**: Building a hypergraph where each key creates an edge connecting 3 vertices (array positions), then "peeling" singletons to find an assignment
2. **Storage**: Each array position stores an 8-bit fingerprint
3. **Query**: XOR the fingerprints at the 3 positions; if the result equals the key's fingerprint, the key is probably present

## References

- **Paper**: [Binary Fuse Filters: Fast and Smaller Than Xor Filters](http://arxiv.org/abs/2201.01174)  
  Graf & Lemire, 2022
- **FastFilter Project**: [github.com/FastFilter](https://github.com/FastFilter)  
  Reference implementations and related filter algorithms

## Limitations

- **Immutable**: Cannot add or remove keys after construction
- **Requires unique keys**: Duplicate keys may cause construction failures
- **Minimum size**: For very small sets (<2,000 keys), [xor filters](https://arxiv.org/abs/1912.08258) may be more space-efficient
- **No streaming construction**: All keys must be available upfront
