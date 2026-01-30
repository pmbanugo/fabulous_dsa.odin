// Cap'n Proto serialization library for Odin
// 
// Cap'n Proto is an "insanely fast" data interchange format where the encoding 
// is appropriate both as a data interchange format and an in-memory representation.
//
// Key Properties:
// - Zero-copy: Data format is identical to in-memory representation
// - Position-independent: Pointers are relative offsets, not absolute addresses
// - Little-endian: All integers use little-endian byte order
// - Segment-based allocation: All objects allocated in contiguous segments
// - O(1) access: Random field access without parsing entire message
//
// See: https://capnproto.org/encoding.html

package capnp

// Re-export constants
WORD_SIZE :: WORD_SIZE_BYTES
BITS_PER :: BITS_PER_WORD
DEFAULT_SEG_SIZE :: DEFAULT_SEGMENT_SIZE

// Re-export security limit defaults
DEFAULT_TRAVERSAL_LIMIT :: 8 * 1024 * 1024  // 64 MB worth of words
DEFAULT_NESTING_LIMIT :: 64
