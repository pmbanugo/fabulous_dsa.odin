# Cap'n Proto Implementation for Odin - Design Document

## Overview

This document describes the design for implementing Cap'n Proto data serialization format in the Odin programming language. The focus is on the binary encoding for serialization/deserialization, not the RPC system.

Cap'n Proto is an "insanely fast" data interchange format where the encoding is appropriate both as a data interchange format and an in-memory representation. Once a structure is built, you can simply write the bytes straight out to disk with zero encoding overhead.

### Key Properties

- **Zero-copy**: Data format is identical to in-memory representation
- **Position-independent**: Pointers are relative offsets, not absolute addresses
- **Little-endian**: All integers use little-endian byte order
- **Segment-based allocation**: All objects allocated in contiguous segments
- **O(1) access**: Random field access without parsing entire message

### References

- [Cap'n Proto Encoding Specification](https://capnproto.org/encoding.html)
- [Cap'n Proto Schema Language](https://capnproto.org/language.html)
- [Cap'n Proto GitHub Repository](https://github.com/capnproto/capnproto)

---

## 1. Core Concepts

### 1.1 Word Size

For Cap'n Proto, a **word** is defined as 8 bytes (64 bits). All objects (structs, lists, blobs) are aligned to word boundaries, and sizes are expressed in terms of words.

```
1 Word = 8 bytes = 64 bits
```

### 1.2 Message Structure

The unit of communication is a **message**. A message is a tree of objects, with the root always being a struct.

```
Message
├── Segment 0 (contains root struct pointer at word 0)
│   ├── Object 1 (struct)
│   ├── Object 2 (list)
│   └── ...
├── Segment 1 (optional)
└── Segment N (optional)
```

Messages may be split into multiple **segments** for:
- Incremental allocation (when size is unknown upfront)
- Avoiding large contiguous allocations

### 1.3 Objects

An **object** is any value which may have a pointer pointing to it. There are three kinds:
1. **Structs** - Fixed-layout records with data and pointer sections
2. **Lists** - Flat arrays of homogeneous values
3. **Far pointer landing pads** - For inter-segment references

Objects form a **tree**, not a graph (single ownership).

---

## 2. Pointer Encoding

All pointers are 64 bits. The lowest 2 bits determine the pointer type.

### 2.1 Struct Pointer (Type = 0)

```
 lsb                                       struct pointer                                       msb
 ├──────────────────┬──────────────────────────────────┬──────────────────┬──────────────────────┤
 │       A (2)      │           B (30)                 │     C (16)       │      D (16)          │
 ├──────────────────┼──────────────────────────────────┼──────────────────┼──────────────────────┤
 │ 0 0              │ Offset (signed, in words)        │ Data size (words)│ Pointer count        │
 └──────────────────┴──────────────────────────────────┴──────────────────┴──────────────────────┘
  Bits 0-1           Bits 2-31                          Bits 32-47         Bits 48-63
```

| Field | Bits | Description |
|-------|------|-------------|
| A | 0-1 | Pointer type = `00` (struct) |
| B | 2-31 | Signed offset in words from pointer to struct content |
| C | 32-47 | Size of data section in words |
| D | 48-63 | Number of pointers in pointer section |

**Layout in memory:**
```
[Struct Pointer] --> [Data Section (C words)][Pointer Section (D pointers)]
```

**Special cases:**
- All-zero pointer = null pointer
- Zero-sized struct: offset = -1, C = 0, D = 0

### 2.2 List Pointer (Type = 1)

```
 lsb                                        list pointer                                        msb
 ├──────────────────┬──────────────────────────────────┬─────────────┬─────────────────────────────┤
 │       A (2)      │           B (30)                 │   C (3)     │          D (29)             │
 ├──────────────────┼──────────────────────────────────┼─────────────┼─────────────────────────────┤
 │ 0 1              │ Offset (signed, in words)        │ Element Size│ List size (elements/words)  │
 └──────────────────┴──────────────────────────────────┴─────────────┴─────────────────────────────┘
  Bits 0-1           Bits 2-31                          Bits 32-34    Bits 35-63
```

| Field | Bits | Description |
|-------|------|-------------|
| A | 0-1 | Pointer type = `01` (list) |
| B | 2-31 | Signed offset in words from pointer to list content |
| C | 32-34 | Element size code (see table below) |
| D | 35-63 | Element count (or total words for composite) |

**Element Size Codes:**

| Code | Size | Type |
|------|------|------|
| 0 | 0 bits | Void |
| 1 | 1 bit | Bool |
| 2 | 1 byte | UInt8/Int8 |
| 3 | 2 bytes | UInt16/Int16 |
| 4 | 4 bytes | UInt32/Int32/Float32 |
| 5 | 8 bytes | UInt64/Int64/Float64 |
| 6 | 8 bytes | Pointer |
| 7 | composite | Inline composite (struct list) |

**Composite lists (C = 7):**
- Content prefixed by a "tag" word (struct pointer format)
- Tag's B field = element count
- D field = total words (not counting tag)

### 2.3 Far Pointer (Type = 2)

Used for inter-segment references.

```
 lsb                                        far pointer                                         msb
 ├──────────────────┬───┬────────────────────────────────────────────┬────────────────────────────┤
 │       A (2)      │ B │                  C (29)                    │          D (32)            │
 ├──────────────────┼───┼────────────────────────────────────────────┼────────────────────────────┤
 │ 1 0              │Pad│ Offset in target segment (words)           │ Segment ID                 │
 └──────────────────┴───┴────────────────────────────────────────────┴────────────────────────────┘
  Bits 0-1           Bit 2 Bits 3-31                                  Bits 32-63
```

| Field | Bits | Description |
|-------|------|-------------|
| A | 0-1 | Pointer type = `10` (far) |
| B | 2 | Landing pad type: 0 = single, 1 = double |
| C | 3-31 | Offset in target segment (words) |
| D | 32-63 | Target segment ID |

**Single landing pad (B = 0):** Target contains a regular pointer.
**Double landing pad (B = 1):** Target contains another far pointer + tag word.

### 2.4 Capability Pointer (Type = 3)

For RPC capabilities (out of scope for this implementation).

```
 lsb                                    capability pointer                                      msb
 ├──────────────────┬──────────────────────────────────┬────────────────────────────────────────────┤
 │       A (2)      │           B (30)                 │              C (32)                        │
 ├──────────────────┼──────────────────────────────────┼────────────────────────────────────────────┤
 │ 1 1              │ Must be zero                     │ Capability table index                     │
 └──────────────────┴──────────────────────────────────┴────────────────────────────────────────────┘
```

---

## 3. Struct Encoding

### 3.1 Layout

A struct is encoded as contiguous data and pointer sections:

```
┌─────────────────────────────────────────┬─────────────────────────────────────────┐
│            Data Section                 │           Pointer Section               │
│         (primitive values)              │        (pointers to objects)            │
│            C words                      │            D pointers                   │
└─────────────────────────────────────────┴─────────────────────────────────────────┘
```

### 3.2 Field Alignment

- Primitives aligned to multiples of their size within data section
- Booleans packed 8 per byte, little-endian bit order
- Fields stored XOR'd with default values (zero = default)

### 3.3 Default Values

- Default struct is all-zeros
- Null pointer returns field's default value
- Enables efficient zero-initialization and packing compression

---

## 4. List Encoding

### 4.1 Primitive Lists

Elements are tightly packed:
- Bools: bit-packed, little-endian (first bool = LSB of first byte)
- Integers/floats: aligned to element size

### 4.2 Struct Lists (Composite)

Always encoded with element size = 7:

```
┌─────────────┬─────────────────────────────────────────────────────────────────────┐
│  Tag Word   │                         List Content                                │
│ (struct ptr │  [Struct 0][Struct 1][Struct 2]...                                  │
│  format)    │                                                                     │
└─────────────┴─────────────────────────────────────────────────────────────────────┘
```

Tag word:
- Offset (B) = element count
- Data size (C) and pointer count (D) = per-element sizes

---

## 5. Stream Framing Format

For serialization over streams/files:

```
┌────────────────────────────────────────────────────────────────┐
│ (4 bytes) Segment count - 1 (little-endian u32)                │
├────────────────────────────────────────────────────────────────┤
│ (4 bytes × N) Size of each segment in words (u32 each)         │
├────────────────────────────────────────────────────────────────┤
│ (0 or 4 bytes) Padding to 8-byte boundary                      │
├────────────────────────────────────────────────────────────────┤
│ Segment 0 content                                              │
├────────────────────────────────────────────────────────────────┤
│ Segment 1 content (if any)                                     │
├────────────────────────────────────────────────────────────────┤
│ ... more segments ...                                          │
└────────────────────────────────────────────────────────────────┘
```

---

## 6. Packing Compression

Simple compression for zero-heavy messages:

### Algorithm

For each 8-byte word:
1. Create tag byte: bit N = 1 if byte N is non-zero
2. Write tag byte
3. Write only non-zero bytes in order

### Special Tags

| Tag | Meaning |
|-----|---------|
| 0x00 | Followed by count of additional zero words (0-255) |
| 0xFF | Followed by 8 literal bytes + count of literal words |

### Example

```
Input:  08 00 00 00 03 00 02 00   (struct pointer)
Tag:    0x15 (bits 0, 2, 4 set)
Output: 15 08 03 02
```

---

## 7. Architecture

### 7.1 Module Structure

```
capnp/
├── capnp.odin          # Main package, public API re-exports
├── types.odin          # Core type definitions
├── pointer.odin        # Pointer encoding/decoding
├── segment.odin        # Segment management & arena allocation
├── message.odin        # Message framing
├── builder.odin        # Builder API (write)
├── reader.odin         # Reader API (read)
├── pack.odin           # Packing compression
└── errors.odin         # Error handling
```

### 7.2 Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                   Public API                                     │
├─────────────────────────────────┬───────────────────────────────────────────────┤
│         Builder API             │              Reader API                        │
│  ┌─────────────────────────┐    │    ┌─────────────────────────┐                │
│  │    Message_Builder      │    │    │    Message_Reader       │                │
│  │  ┌───────────────────┐  │    │    │  ┌───────────────────┐  │                │
│  │  │  Struct_Builder   │  │    │    │  │  Struct_Reader    │  │                │
│  │  │  ┌─────────────┐  │  │    │    │  │  ┌─────────────┐  │  │                │
│  │  │  │List_Builder │  │  │    │    │  │  │List_Reader  │  │  │                │
│  │  │  └─────────────┘  │  │    │    │  │  └─────────────┘  │  │                │
│  │  └───────────────────┘  │    │    │  └───────────────────┘  │                │
│  └─────────────────────────┘    │    └─────────────────────────┘                │
├─────────────────────────────────┴───────────────────────────────────────────────┤
│                              Core Infrastructure                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐ │
│  │   Message    │  │   Segment    │  │   Pointer    │  │   Pack/Unpack        │ │
│  │   Framing    │  │   Manager    │  │   Codec      │  │   Compression        │ │
│  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────────────┘ │
│                          │                                                       │
│                          ▼                                                       │
│                    ┌──────────────┐                                              │
│                    │  core:mem    │  (Odin's built-in allocators)                │
│                    │  Allocators  │                                              │
│                    └──────────────┘                                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│                               Core Types                                         │
│  ┌────────┐  ┌────────────────┐  ┌──────────────┐  ┌─────────────────────────┐  │
│  │  Word  │  │ Pointer Types  │  │ Element_Size │  │  Error Types            │  │
│  │  (u64) │  │ (bit_fields)   │  │   (enum)     │  │                         │  │
│  └────────┘  └────────────────┘  └──────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### 7.3 Data Flow

```
                    WRITE PATH                              READ PATH
                    
  Application Data                                    Application Data
        │                                                    ▲
        ▼                                                    │
  ┌─────────────┐                                    ┌─────────────┐
  │  Builders   │                                    │   Readers   │
  │ (type-safe) │                                    │ (validated) │
  └──────┬──────┘                                    └──────┬──────┘
         │                                                  │
         ▼                                                  ▲
  ┌─────────────┐                                    ┌─────────────┐
  │   Segment   │                                    │   Segment   │
  │   Manager   │                                    │    Views    │
  └──────┬──────┘                                    └──────┬──────┘
         │                                                  │
         ▼                                                  ▲
  ┌─────────────┐                                    ┌─────────────┐
  │  Serialize  │                                    │ Deserialize │
  │   Frame     │                                    │    Frame    │
  └──────┬──────┘                                    └──────┬──────┘
         │                                                  │
         ▼                                                  ▲
  ┌─────────────┐        ┌─────────────┐            ┌─────────────┐
  │    Pack     │───────▶│   Bytes     │───────────▶│   Unpack    │
  │ (optional)  │        │  (on wire)  │            │ (optional)  │
  └─────────────┘        └─────────────┘            └─────────────┘
```

---

## 8. Core Type Definitions

### 8.1 Fundamental Types

```odin
WORD_SIZE_BYTES :: 8
BITS_PER_WORD :: 64

Word :: u64

Pointer_Kind :: enum u8 {
    Struct = 0,
    List   = 1,
    Far    = 2,
    Other  = 3,  // Capability (not implemented)
}

Element_Size :: enum u8 {
    Void        = 0,  // 0 bits
    Bit         = 1,  // 1 bit
    Byte        = 2,  // 1 byte
    Two_Bytes   = 3,  // 2 bytes
    Four_Bytes  = 4,  // 4 bytes
    Eight_Bytes = 5,  // 8 bytes
    Pointer     = 6,  // 8 bytes (pointer)
    Composite   = 7,  // Inline composite
}
```

### 8.2 Pointer Types (using bit_field)

```odin
Struct_Pointer :: bit_field u64 {
    kind:          Pointer_Kind | 2,   // bits 0-1
    offset:        i32          | 30,  // bits 2-31 (signed)
    data_size:     u16          | 16,  // bits 32-47
    pointer_count: u16          | 16,  // bits 48-63
}

List_Pointer :: bit_field u64 {
    kind:          Pointer_Kind | 2,   // bits 0-1
    offset:        i32          | 30,  // bits 2-31 (signed)
    element_size:  Element_Size | 3,   // bits 32-34
    element_count: u32          | 29,  // bits 35-63
}

Far_Pointer :: bit_field u64 {
    kind:          Pointer_Kind | 2,   // bits 0-1
    double_far:    bool         | 1,   // bit 2
    offset:        u32          | 29,  // bits 3-31
    segment_id:    u32          | 32,  // bits 32-63
}

Pointer :: struct #raw_union {
    raw:       u64,
    as_struct: Struct_Pointer,
    as_list:   List_Pointer,
    as_far:    Far_Pointer,
}
```

### 8.3 Segment Management

Cap'n Proto uses a segment-based memory model. We leverage Odin's built-in allocators 
from `core:mem` rather than reimplementing arena allocation.

**Key insight:** Cap'n Proto's "arena" is really a **segment manager** - it tracks 
multiple segments for serialization and inter-segment pointers, not general-purpose 
memory allocation.

```odin
import "core:mem"

// Segment represents a contiguous block of memory for Cap'n Proto objects
Segment :: struct {
    id:       u32,
    data:     []Word,      // Slice of words (allocated via Odin allocator)
    used:     u32,         // Words used (Cap'n Proto level tracking)
    capacity: u32,         // Total capacity in words
}

// Segment_Manager manages multiple segments for a message
// Uses Odin's allocators for actual memory allocation
Segment_Manager :: struct {
    segments:         [dynamic]Segment,   // Remembers its allocator automatically
    allocator:        mem.Allocator,      // Odin allocator for segment data ([]Word)
    default_seg_size: u32,                // Default segment size in words
}

// Note: [dynamic]Segment remembers its allocator, so delete() works correctly.
// The `allocator` field is for allocating the actual segment data ([]Word).
```

### 8.3.1 Allocator Strategy

**Default:** Uses `context.allocator` (Odin's implicit context), following Odin idioms.

**Cap'n Proto Recommendation:** Arena allocation is strongly preferred because:
- Messages are built atomically, then serialized and discarded as a whole
- No individual object deallocation is needed
- Arena = fast bump-pointer allocation + single bulk free
- Better cache locality for traversal

**Odin's Two Context Allocators:**
- `context.allocator` - Default heap-like allocator for persistent allocations
- `context.temp_allocator` - Growing arena-like allocator for temporary/scratch data

**Guidance by use case:**

| Use Case | Recommended Allocator | Rationale |
|----------|----------------------|-----------|
| Simple/one-off messages | `context.allocator` | Convenient, good enough |
| High-throughput (loops) | `mem.Arena` | Fast alloc, bulk free per message |
| Request handlers | `context.temp_allocator` | Built-in scratch space, auto-reset |
| Very large messages | `core:mem/virtual` | Avoids large contiguous alloc |
| Embedded/constrained | Fixed buffer + arena | No heap allocation |

**Note on `context.temp_allocator`:** Odin's built-in temp allocator is ideal for 
short-lived message building where you serialize immediately and discard. It's 
already arena-based and requires no setup.

**Usage examples:**
```odin
import "core:mem"

// DEFAULT (make): Convenient value-based creation
build_simple_message :: proc() -> Error {
    mb, err := message_builder_make()  // uses context.allocator by default
    if err != .None do return err
    defer message_builder_destroy(&mb)
    
    root, err2 := message_builder_init_root(&mb, 2, 1)
    if err2 != .None do return err2
    // ... build message ...
    return .None
}

// DEFAULT (init): Pointer-based for stack allocation
build_simple_message_stack :: proc() -> Error {
    mb: Message_Builder
    message_builder_init(&mb) or_return  // returns ^Message_Builder, Error
    defer message_builder_destroy(&mb)
    // ... build message ...
    return .None
}

// REUSE PATTERN: Clear and reuse builder (keeps allocated capacity)
process_many_messages_reuse :: proc(inputs: []Input) -> Error {
    mb: Message_Builder
    message_builder_init(&mb) or_return
    defer message_builder_destroy(&mb)
    
    for input in inputs {
        root, err := message_builder_init_root(&mb, 2, 1)
        if err != .None do return err
        // ... build message ...
        bytes, err2 := serialize(&mb)
        if err2 != .None do return err2
        send(bytes)
        
        // Clear for reuse - keeps capacity, avoids reallocation
        message_builder_clear(&mb)
    }
    return .None
}

// ARENA PATTERN: Arena allocator - fast allocation, bulk free
process_many_messages_arena :: proc(inputs: []Input) -> Error {
    // Reusable arena for all messages
    backing := make([]byte, 64 * mem.Kilobyte)
    defer delete(backing)
    
    arena: mem.Arena
    mem.arena_init(&arena, backing)
    
    for input in inputs {
        mb: Message_Builder
        message_builder_init(&mb, allocator = mem.arena_allocator(&arena)) or_return
        // ... build and serialize message ...
        
        // Reset arena for next message (fast bulk free)
        mem.arena_free_all(&arena)
    }
    return .None
}

// TEMP ALLOCATOR: Use Odin's built-in temp allocator for short-lived messages
send_response :: proc() -> Error {
    // context.temp_allocator is already arena-based, no setup needed!
    mb: Message_Builder
    message_builder_init(&mb, allocator = context.temp_allocator) or_return
    // No defer needed - temp allocator is managed by runtime
    
    // ... build message ...
    bytes, err := serialize(&mb)
    if err != .None do return err
    send(bytes)
    
    // Message data is temporary; will be reclaimed when temp allocator resets
    return .None
}

// EXPLICIT TEMP SCOPE: Use runtime.default_temp_allocator_proc for explicit control
handle_batch :: proc() -> Error {
    for item in batch {
        // Mark current temp allocator position
        runtime.default_temp_allocator_temp_begin()
        defer runtime.default_temp_allocator_temp_end()
        
        mb: Message_Builder
        message_builder_init(&mb, allocator = context.temp_allocator) or_return
        // ... process item ...
    }
    return .None
}
```

### 8.4 Message

```odin
Message :: struct {
    segments: Segment_Manager,
}

Read_Limits :: struct {
    traversal_limit: u64,  // max words to traverse
    nesting_limit:   int,  // max pointer depth
}

DEFAULT_TRAVERSAL_LIMIT :: 8 * 1024 * 1024  // 64 MB worth of words
DEFAULT_NESTING_LIMIT   :: 64
```

---

## 9. API Design

### 9.1 Builder API

```odin
// Message building
// Default: uses context.allocator; pass mem.arena_allocator(&arena) for high-throughput
// Following core:strings/Builder pattern: separate init (pointer-based) and make (value-based)

// Pointer-based init: efficient for stack allocation and reuse patterns
// Returns pointer for chaining, e.g.: mb, err := message_builder_init(&my_builder)
message_builder_init :: proc(
    mb: ^Message_Builder,
    allocator := context.allocator,
) -> (res: ^Message_Builder, err: Error)

// Value-based make: convenient for simple cases
// Returns value directly, e.g.: mb, err := message_builder_make()
message_builder_make :: proc(
    allocator := context.allocator,
) -> (res: Message_Builder, err: Error)

message_builder_destroy :: proc(mb: ^Message_Builder)        // Frees all memory
message_builder_clear :: proc(mb: ^Message_Builder)          // Resets for reuse (keeps capacity)
message_builder_init_root :: proc(mb: ^Message_Builder, data_words, ptr_words: u16) -> (Struct_Builder, Error)
message_builder_get_segments :: proc(mb: ^Message_Builder) -> [][]Word
message_builder_total_words :: proc(mb: ^Message_Builder) -> u32  // Total words used

// Struct building
struct_builder_set_bool :: proc(sb: ^Struct_Builder, offset_bits: u32, value: bool)
struct_builder_set_u8 :: proc(sb: ^Struct_Builder, offset: u32, value: u8)
struct_builder_set_u16 :: proc(sb: ^Struct_Builder, offset: u32, value: u16)
struct_builder_set_u32 :: proc(sb: ^Struct_Builder, offset: u32, value: u32)
struct_builder_set_u64 :: proc(sb: ^Struct_Builder, offset: u32, value: u64)
struct_builder_set_i8 :: proc(sb: ^Struct_Builder, offset: u32, value: i8)
struct_builder_set_i16 :: proc(sb: ^Struct_Builder, offset: u32, value: i16)
struct_builder_set_i32 :: proc(sb: ^Struct_Builder, offset: u32, value: i32)
struct_builder_set_i64 :: proc(sb: ^Struct_Builder, offset: u32, value: i64)
struct_builder_set_f32 :: proc(sb: ^Struct_Builder, offset: u32, value: f32)
struct_builder_set_f64 :: proc(sb: ^Struct_Builder, offset: u32, value: f64)

struct_builder_init_struct :: proc(sb: ^Struct_Builder, ptr_idx: u16, data_words, ptr_words: u16) -> Struct_Builder
struct_builder_init_list :: proc(sb: ^Struct_Builder, ptr_idx: u16, elem_size: Element_Size, count: u32) -> List_Builder
struct_builder_set_text :: proc(sb: ^Struct_Builder, ptr_idx: u16, text: string) -> Error
struct_builder_set_data :: proc(sb: ^Struct_Builder, ptr_idx: u16, data: []byte) -> Error

// List building
list_builder_set_bool :: proc(lb: ^List_Builder, index: u32, value: bool)
list_builder_set_u8 :: proc(lb: ^List_Builder, index: u32, value: u8)
// ... etc for all primitive types
list_builder_get_struct :: proc(lb: ^List_Builder, index: u32) -> Struct_Builder
```

### 9.2 Reader API

```odin
// Message reading
message_reader_from_bytes :: proc(data: []byte, limits := Read_Limits{}) -> (Message_Reader, Error)
message_reader_from_segments :: proc(segments: [][]Word, limits := Read_Limits{}) -> Message_Reader
message_reader_get_root :: proc(mr: ^Message_Reader) -> (Struct_Reader, Error)

// Struct reading
struct_reader_get_bool :: proc(sr: ^Struct_Reader, offset_bits: u32, default: bool = false) -> bool
struct_reader_get_u8 :: proc(sr: ^Struct_Reader, offset: u32, default: u8 = 0) -> u8
struct_reader_get_u16 :: proc(sr: ^Struct_Reader, offset: u32, default: u16 = 0) -> u16
// ... etc for all primitive types

struct_reader_get_struct :: proc(sr: ^Struct_Reader, ptr_idx: u16) -> (Struct_Reader, Error)
struct_reader_get_list :: proc(sr: ^Struct_Reader, ptr_idx: u16, expected: Element_Size) -> (List_Reader, Error)
struct_reader_get_text :: proc(sr: ^Struct_Reader, ptr_idx: u16) -> (string, Error)
struct_reader_get_data :: proc(sr: ^Struct_Reader, ptr_idx: u16) -> ([]byte, Error)
struct_reader_has_pointer :: proc(sr: ^Struct_Reader, ptr_idx: u16) -> bool

// List reading
list_reader_len :: proc(lr: ^List_Reader) -> u32
list_reader_get_bool :: proc(lr: ^List_Reader, index: u32) -> bool
list_reader_get_u8 :: proc(lr: ^List_Reader, index: u32) -> u8
// ... etc
list_reader_get_struct :: proc(lr: ^List_Reader, index: u32) -> (Struct_Reader, Error)
```

### 9.3 Serialization API

```odin
// Serialize message to bytes (with frame header)
serialize :: proc(mb: ^Message_Builder, allocator := context.allocator) -> ([]byte, Error)
serialize_to_writer :: proc(mb: ^Message_Builder, w: io.Writer) -> Error

// Deserialize bytes to message reader
deserialize :: proc(data: []byte, limits := Read_Limits{}) -> (Message_Reader, Error)

// Packing
pack :: proc(data: []byte, allocator := context.allocator) -> ([]byte, Error)
unpack :: proc(data: []byte, allocator := context.allocator) -> ([]byte, Error)

// Convenience: serialize + pack
serialize_packed :: proc(mb: ^Message_Builder, allocator := context.allocator) -> ([]byte, Error)
deserialize_packed :: proc(data: []byte, limits := Read_Limits{}) -> (Message_Reader, Error)
```

---

## 10. Security Considerations

### 10.1 Pointer Validation

Every pointer must be validated before dereferencing:
- Check pointer is within segment bounds
- Check target object is within segment bounds
- Validate struct/list sizes don't overflow segment

### 10.2 Traversal Limit

Count words accessed during message traversal:
- Prevents amplification attacks (small message, large traversal)
- Default limit: 64 MB worth of words
- Zero-sized elements count as 1 word each

### 10.3 Nesting Limit

Track pointer depth during traversal:
- Prevents stack overflow from deeply nested structures
- Default limit: 64 levels

### 10.4 List Amplification

A list of Void or zero-sized structs can have huge element count:
- Count each zero-sized element as 1 word for traversal limit
- Prevents CPU exhaustion attacks

---

## 11. Design Decisions

| Decision | Rationale |
|----------|-----------|
| Use `bit_field` for pointers | Matches spec exactly, Odin native feature |
| Use Odin's `core:mem` allocators | Leverage proven allocators (arena, virtual, heap) instead of reimplementing |
| Default to `context.allocator` | Idiomatic Odin; allows third-party interception |
| Accept allocator parameter | Users can override with arena/temp/custom allocators |
| Segment_Manager for Cap'n Proto segments | Separates Cap'n Proto segment tracking from memory allocation |
| Explicit error returns | Odin idiom, no exceptions |
| Zero-copy reading | Return slices into message buffer |
| Separate Builder/Reader | Clear mutable vs immutable distinction |
| Little-endian only | Spec requirement; modern CPUs are LE |
| No schema compiler | Focus on runtime library first |
| Skip capabilities/RPC | Focus on serialization only |

---

## 12. Implementation Roadmap

See [IMPLEMENTATION.md](./IMPLEMENTATION.md) for detailed phases and task tracking.

---

## Appendix A: Built-in Types Mapping

| Cap'n Proto | Odin | Size |
|-------------|------|------|
| Void | - | 0 bits |
| Bool | bool | 1 bit |
| Int8 | i8 | 1 byte |
| Int16 | i16 | 2 bytes |
| Int32 | i32 | 4 bytes |
| Int64 | i64 | 8 bytes |
| UInt8 | u8 | 1 byte |
| UInt16 | u16 | 2 bytes |
| UInt32 | u32 | 4 bytes |
| UInt64 | u64 | 8 bytes |
| Float32 | f32 | 4 bytes |
| Float64 | f64 | 8 bytes |
| Text | string | pointer + NUL-terminated UTF-8 |
| Data | []byte | pointer + byte array |
| List(T) | varies | pointer + flat array |
| struct | varies | pointer + data + pointers |

---

## Appendix B: Error Codes

```odin
Error :: enum {
    None,
    
    // Framing errors
    Invalid_Frame_Header,
    Segment_Count_Overflow,
    Segment_Size_Overflow,
    Unexpected_End_Of_Input,
    
    // Pointer errors
    Pointer_Out_Of_Bounds,
    Invalid_Pointer_Type,
    Null_Pointer,
    
    // Security errors
    Traversal_Limit_Exceeded,
    Nesting_Limit_Exceeded,
    
    // List errors
    Invalid_Element_Size,
    List_Index_Out_Of_Bounds,
    
    // Text/Data errors
    Text_Not_Nul_Terminated,
    Invalid_Utf8,
    
    // Allocation errors
    Out_Of_Memory,
    Segment_Full,
    
    // Packing errors
    Invalid_Packed_Data,
}
```
