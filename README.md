# fabulous_dsa.odin
An adventure and experiment on Data Structure and Algorithms, implemented in Odin

> Zig alternative available at https://github.com/pmbanugo/dsa_dump.zig, although they're not meant to map 1:1 on what they implement, and how they do it.

## Data Structures

- [Binary Fuse Filter](binary_fuse_filters/) - Space-efficient probabilistic set membership

## Testing

Run all tests:

```sh
odin test binary_fuse_filters/
```

Or run tests for a specific package from within its directory:

```sh
cd binary_fuse_filters && odin test .
```

Odin's test runner automatically tracks memory usage and reports leaks or bad frees.
