# fabulous_dsa.odin

An adventure and experiment on Data Structure and Algorithms, implemented in Odin

> Zig alternative available at https://github.com/pmbanugo/dsa_dump.zig, although they're not meant to map 1:1 on what they implement, and how they do it.

## Data Structures

- [Binary Fuse Filter](binary_fuse_filters/) - Space-efficient probabilistic set membership
- [Funnel Hash Table](hash_tables/) - High-performance hash table with optimal worst-case probe complexity ([paper](https://arxiv.org/pdf/2501.02305))

## Serialization Formats

- [Cap'n Proto](capnp/) - Insanely fast data interchange format (WIP). Infinitely faster cerealisation protocol
  - [Design Document](capnp/DESIGN.md) - Architecture and specification
  - [Implementation Roadmap](capnp/IMPLEMENTATION.md) - Phase-by-phase task tracking

## Development

### Type-checking

This repository contains library packages (no `main` entry point). Use `-no-entry-point` when type-checking:

```sh
odin check capnp/ -no-entry-point
odin check binary_fuse_filters/ -no-entry-point
odin check hash_tables/ -no-entry-point
```

### Testing

Run tests for each package:

```sh
odin test binary_fuse_filters/
odin test hash_tables/
odin test capnp/tests/
```

Or run tests from within a package directory:

```sh
cd binary_fuse_filters && odin test .
```

Odin's test runner automatically tracks memory usage and reports leaks or bad frees.
