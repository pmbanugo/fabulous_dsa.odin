# Funnel Hash Table

A high-performance, cache-friendly hash table implementation in Odin based on the **Funnel Hashing** algorithm.

## Paper Reference

This implementation is based on the research paper:

> **"Funnel Hashing"**  
> Martin Farach-Colton, William Kuszmaul, Nathan Sheffield  
> arXiv:2501.02305  
> https://arxiv.org/pdf/2501.02305

## Why Funnel Hashing?

Funnel Hashing provides **optimal worst-case expected probe complexity** for open-addressed hash tables. Unlike traditional linear probing or Robin Hood hashing, Funnel Hashing guarantees:

| Metric | Complexity |
|--------|------------|
| Worst-case expected probes | O(log² δ⁻¹) |
| High-probability worst-case | O(log² δ⁻¹ + log log n) |
| Amortized expected probes | O(log δ⁻¹) |

Where `δ` is the slack parameter (default 0.01, meaning 99% load factor is achievable).

### Key Benefits

- **Predictable Performance**: Unlike traditional hash tables that can degrade to O(n) with bad hash distributions, Funnel Hashing maintains consistent probe counts.
- **Cache-Friendly**: This implementation uses a single contiguous memory allocation with Odin's `#soa` (Structure of Arrays), maximizing CPU cache utilization.
- **High Load Factor**: Supports load factors up to `1 - δ` (99% with default settings) without performance collapse.
- **Automatic Resizing**: Grows automatically when capacity is exceeded, with intelligent reseeding on rebuild failures.

## Installation

Copy the `hash_tables` directory to your project, or add this repository as a dependency.

```odin
import "hash_tables"
```

## Quick Start

```odin
import "hash_tables"

main :: proc() {
    // Create a table mapping integers to strings
    table, err := hash_tables.make_funnel_table(int, string)
    if err != .None {
        // Handle error
        return
    }
    defer hash_tables.delete_funnel_table(&table)

    // Insert key-value pairs
    hash_tables.set(&table, 1, "one")
    hash_tables.set(&table, 2, "two")
    hash_tables.set(&table, 3, "three")

    // Lookup
    if value, found := hash_tables.get(&table, 2); found {
        fmt.println("Found:", value)  // Prints: Found: two
    }

    // Remove
    hash_tables.remove(&table, 1)

    // Check existence
    if hash_tables.contains(&table, 1) {
        fmt.println("Key 1 exists")
    } else {
        fmt.println("Key 1 was removed")
    }

    // Get count
    fmt.println("Table size:", hash_tables.length(&table))

    // Clear all entries
    hash_tables.clear(&table)
}
```

## API Reference

### Types

#### `Funnel_Table($K, $V: typeid)`

The main hash table type. Generic over key type `K` and value type `V`.

```odin
Funnel_Table :: struct($K, $V: typeid) {
    allocator:      mem.Allocator,
    seed:           u64,
    len:            int,
    tombstones:     int,
    capacity:       int,
    alpha:          int,  // Number of funnel levels
    beta:           int,  // Bucket size
    // ... internal fields
}
```

#### `Insert_Result`

Result of an insertion operation.

```odin
Insert_Result :: enum {
    Inserted,   // New key was inserted
    Replaced,   // Existing key's value was updated
    Failed,     // Insertion failed (triggers automatic resize)
}
```

#### `Make_Error`

Errors that can occur during table creation.

```odin
Make_Error :: enum {
    None,              // Success
    Invalid_Capacity,  // Capacity must be >= 8 and a power of two
    Alloc_Error,       // Memory allocation failed
}
```

### Functions

#### `make_funnel_table`

Creates a new Funnel Hash table.

```odin
make_funnel_table :: proc(
    $K, $V: typeid,
    initial_capacity: int = 1024,    // Must be power of 2, >= 8
    delta: f64 = 0.01,               // Slack parameter (0 < δ < 1)
    allocator: mem.Allocator = context.allocator,
) -> (table: Funnel_Table(K, V), err: Make_Error)
```

**Parameters:**
- `K, V`: Key and value types
- `initial_capacity`: Initial number of slots (default: 1024). Must be a power of 2.
- `delta`: Slack parameter controlling the trade-off between space and probe count (default: 0.01). Smaller values mean more levels but higher load factor support.
- `allocator`: Memory allocator to use

**Returns:**
- `table`: The created table
- `err`: `.None` on success, error code otherwise

**Example:**
```odin
// Default settings
table, _ := make_funnel_table(string, int)

// Custom capacity and allocator
table2, _ := make_funnel_table(
    int, 
    MyStruct, 
    initial_capacity = 4096,
    delta = 0.05,
    allocator = my_allocator,
)
```

#### `delete_funnel_table`

Frees all memory associated with the table. Safe to call multiple times (idempotent).

```odin
delete_funnel_table :: proc(table: ^Funnel_Table($K, $V))
```

#### `set`

Inserts or updates a key-value pair.

```odin
set :: proc(table: ^Funnel_Table($K, $V), key: K, value: V) -> Insert_Result
```

**Returns:**
- `.Inserted`: New key was added
- `.Replaced`: Existing key's value was updated

The table automatically resizes if needed.

#### `get`

Retrieves the value associated with a key.

```odin
get :: proc(table: ^Funnel_Table($K, $V), key: K) -> (value: V, found: bool)
```

**Returns:**
- `value`: The associated value (zero value if not found)
- `found`: `true` if the key exists

#### `remove`

Removes a key from the table.

```odin
remove :: proc(table: ^Funnel_Table($K, $V), key: K) -> bool
```

**Returns:** `true` if the key was found and removed, `false` otherwise.

#### `contains`

Checks if a key exists in the table.

```odin
contains :: proc(table: ^Funnel_Table($K, $V), key: K) -> bool
```

#### `length`

Returns the number of key-value pairs in the table.

```odin
length :: proc(table: ^Funnel_Table($K, $V)) -> int
```

#### `clear`

Removes all entries from the table without deallocating memory.

```odin
clear :: proc(table: ^Funnel_Table($K, $V))
```

## Supported Key Types

The following key types are fully supported with correct hashing and equality:

| Type | Hashing | Equality |
|------|---------|----------|
| `int`, `u32`, `i64`, etc. | ✅ Byte-based | ✅ `==` |
| `string` | ✅ Content-based | ✅ `==` |
| `cstring` | ✅ Content-based | ✅ Content comparison |
| `[]T` (slices) | ✅ Content-based | ✅ Content comparison |
| Simple structs | ⚠️ Byte-based* | ✅ `==` |

*⚠️ **Warning for struct keys**: Structs with padding bytes may produce inconsistent hashes. For struct keys, ensure fields are tightly packed or provide consistent initialization.

## How It Works

### The Funnel Structure

The table is organized as a "funnel" with multiple levels:

```
Level 0:  [████████████████████████████████]  (largest)
Level 1:  [██████████████████████████]        (~75% of Level 0)
Level 2:  [████████████████████]              (~75% of Level 1)
   ...           ...
Level α:  [████████]                          (smallest)
          
Overflow B: [Uniform Probing Buffer]
Overflow C: [Two-Choice Hashing Buffer]
```

**Insertion**: Keys cascade down through levels until finding an empty slot. Each level uses a different hash function derived from the base hash.

**Lookup**: The same cascade is followed. Early termination when the key is found.

**Overflow**: Keys that don't fit in any level go to overflow buffers using uniform probing (B) or two-choice hashing (C).

### Memory Layout

This implementation uses Odin's `#soa` (Structure of Arrays) feature for optimal cache performance:

```odin
// All slot data stored contiguously in memory:
_backing_store: #soa[]Slot(K, V)

// Internally becomes:
// states: [████████████████████]  // All states contiguous
// hashes: [████████████████████]  // All hashes contiguous  
// keys:   [████████████████████]  // All keys contiguous
// values: [████████████████████]  // All values contiguous
```

This layout means:
- **State checks** (the hot path) access contiguous memory
- **Cache prefetching** works optimally
- **Single allocation** for the entire table data

## Performance Characteristics

Based on the paper's analysis with default `δ = 0.01`:

- **α (levels)**: ~37 levels
- **β (bucket size)**: ~14 slots per bucket
- **Probe complexity**: O(log² 100) ≈ O(44) worst-case expected

In practice, most lookups complete in the first few levels due to the geometric size reduction.

## Running Tests

```bash
odin test hash_tables/
```

## License

See the repository's LICENSE file.

## Contributing

Contributions are welcome! Please ensure all tests pass before submitting a PR.
