package funnel_hash

import "base:intrinsics"
import "core:hash/xxhash"
import "core:math"
import "core:math/bits"
import "core:mem"
import "core:slice"

// --- Core Types using #soa ---

Slot :: struct($K, $V: typeid) {
    state: Slot_State,
    hash:  u64,
    key:   K,
    value: V,
}

Slot_State :: enum u8 {
    Empty     = 0,
    Filled    = 1,
    Tombstone = 2,
}

Funnel_Level :: struct($K, $V: typeid) {
    slots:        #soa[]Slot(K, V),
    bucket_size:  int,
    bucket_count: int,
}

Overflow_Uniform :: struct($K, $V: typeid) {
    slots:       #soa[]Slot(K, V),
    mask:        u64,
    probe_limit: int,
}

Overflow_Two_Choice :: struct($K, $V: typeid) {
    slots:        #soa[]Slot(K, V),
    bucket_size:  int,
    bucket_count: int,
}

Funnel_Table :: struct($K, $V: typeid) {
    allocator:      mem.Allocator,
    seed:           u64,
    len:            int,
    tombstones:     int,
    capacity:       int,
    alpha:          int,
    beta:           int,
    _backing_store: #soa[]Slot(K, V),
    levels:         []Funnel_Level(K, V),
    overflow_b:     Overflow_Uniform(K, V),
    overflow_c:     Overflow_Two_Choice(K, V),
}

Insert_Result :: enum {
    Inserted,
    Replaced,
    Failed,
}

Make_Error :: enum {
    None,
    Invalid_Capacity,
    Alloc_Error,
}

// --- Hash helpers with type dispatch ---

@(private = "file")
hash_key :: proc(key: $K, seed: u64) -> u64 {
    when K == string {
        return xxhash.XXH64(transmute([]u8)key, seed)
    } else when K == cstring {
        if key == nil do return xxhash.XXH64({}, seed)
        return xxhash.XXH64(([^]u8)(key)[:len(key)], seed)
    } else when intrinsics.type_is_slice(K) {
        return xxhash.XXH64(mem.slice_to_bytes(key), seed)
    } else {
        k := key
        return xxhash.XXH64(mem.ptr_to_bytes(&k), seed)
    }
}

@(private = "file")
keys_equal :: #force_inline proc(a, b: $K) -> bool {
    when intrinsics.type_is_slice(K) {
        if len(a) != len(b) do return false
        return mem.compare(mem.slice_to_bytes(a), mem.slice_to_bytes(b)) == 0
    } else when K == cstring {
        if a == b do return true
        if a == nil || b == nil do return false
        return string(a) == string(b)
    } else {
        return a == b
    }
}

// --- Math helpers ---

@(private = "file")
mix :: #force_inline proc "contextless" (h: u64, i: u64) -> u64 {
    x := h ~ (0x9E3779B97F4A7C15 * (i + 1))
    x ~= x >> 33
    x *= 0xff51afd7ed558ccd
    x ~= x >> 33
    x *= 0xc4ceb9fe1a85ec53
    x ~= x >> 33
    return x
}

@(private = "file")
bucket_index :: #force_inline proc "contextless" (hash: u64, bucket_count: int) -> int {
    hi, _ := bits.mul_u64(hash, u64(bucket_count))
    return int(hi)
}

@(private = "file")
next_power_of_two :: proc(n: int) -> int {
    if n <= 1 do return 1
    return 1 << (64 - bits.count_leading_zeros(u64(n - 1)))
}

@(private = "file")
is_power_of_two :: #force_inline proc(n: int) -> bool {
    return n > 0 && (n & (n - 1)) == 0
}

@(private = "file")
compute_loglog_n :: proc(n: int) -> int {
    if n <= 4 do return 2
    log_n := 64 - bits.count_leading_zeros(u64(n))
    log_log_n := 64 - bits.count_leading_zeros(u64(log_n))
    return max(int(log_log_n), 2)
}

@(private = "file")
ceil_to_multiple :: #force_inline proc(x, m: int) -> int {
    if m == 0 do return x
    r := x % m
    if r == 0 do return x
    return x + m - r
}

// --- Table lifecycle ---

make_funnel_table :: proc(
    $K, $V: typeid,
    initial_capacity: int = 1024,
    delta: f64 = 0.01,
    allocator: mem.Allocator = context.allocator,
) -> (table: Funnel_Table(K, V), err: Make_Error) {
    if initial_capacity < 8 || !is_power_of_two(initial_capacity) {
        return {}, .Invalid_Capacity
    }

    log_delta := math.log2_f64(1.0 / delta)
    alpha := int(math.ceil(4.0 * log_delta + 10.0))
    beta := max(int(math.ceil(2.0 * log_delta)), 2)

    // Calculate total memory needed
    total_slots := 0
    level_sizes := make([]int, alpha, context.temp_allocator)

    sim_size := ceil_to_multiple(initial_capacity, beta)
    for i in 0 ..< alpha {
        actual := max(sim_size, beta)
        level_sizes[i] = actual
        total_slots += actual
        sim_size = max(ceil_to_multiple((sim_size * 3) / 4, beta), beta)
    }

    overflow_b_size := next_power_of_two(max(initial_capacity / 16, 8 * beta))
    total_slots += overflow_b_size

    overflow_c_bucket := max(2 * compute_loglog_n(initial_capacity), 2)
    overflow_c_size := ceil_to_multiple(max(initial_capacity / 32, 4 * overflow_c_bucket), overflow_c_bucket)
    total_slots += overflow_c_size

    table = Funnel_Table(K, V) {
        allocator = allocator,
        seed      = 0x517cc1b727220a95,
        capacity  = initial_capacity,
        alpha     = alpha,
        beta      = beta,
    }

    // Single allocation for all slots
    alloc_err: mem.Allocator_Error
    table._backing_store, alloc_err = make_soa(#soa[]Slot(K, V), total_slots, allocator)
    if alloc_err != nil {
        return {}, .Alloc_Error
    }

    table.levels, alloc_err = make([]Funnel_Level(K, V), alpha, allocator)
    if alloc_err != nil {
        delete_soa(table._backing_store, allocator)
        return {}, .Alloc_Error
    }

    // Slice into levels
    offset := 0
    for i in 0 ..< alpha {
        size := level_sizes[i]
        table.levels[i] = Funnel_Level(K, V) {
            slots        = table._backing_store[offset : offset + size],
            bucket_size  = beta,
            bucket_count = size / beta,
        }
        offset += size
    }

    // Overflow B
    table.overflow_b = Overflow_Uniform(K, V) {
        slots       = table._backing_store[offset : offset + overflow_b_size],
        mask        = u64(overflow_b_size - 1),
        probe_limit = compute_loglog_n(initial_capacity),
    }
    offset += overflow_b_size

    // Overflow C
    table.overflow_c = Overflow_Two_Choice(K, V) {
        slots        = table._backing_store[offset : offset + overflow_c_size],
        bucket_size  = overflow_c_bucket,
        bucket_count = overflow_c_size / overflow_c_bucket,
    }

    return table, .None
}

delete_funnel_table :: proc(table: ^Funnel_Table($K, $V)) {
    if table == nil || table._backing_store == nil do return
    delete_soa(table._backing_store, table.allocator)
    delete(table.levels, table.allocator)
    table^ = {}
}

// --- Lookup ---

get :: proc(table: ^Funnel_Table($K, $V), key: K) -> (value: V, found: bool) {
    if table.len == 0 do return {}, false

    h0 := hash_key(key, table.seed)

    for i in 0 ..< table.alpha {
        hi := mix(h0, u64(i))
        lvl := &table.levels[i]
        b := bucket_index(hi, lvl.bucket_count)
        start := b * lvl.bucket_size

        #no_bounds_check for j in 0 ..< lvl.bucket_size {
            idx := start + j
            if lvl.slots[idx].state == .Filled {
                if lvl.slots[idx].hash == hi && keys_equal(lvl.slots[idx].key, key) {
                    return lvl.slots[idx].value, true
                }
            }
        }
    }

    if v, ok := uniform_lookup(&table.overflow_b, h0, key); ok {
        return v, true
    }

    if v, ok := two_choice_lookup(&table.overflow_c, h0, key); ok {
        return v, true
    }

    return {}, false
}

@(private = "file")
uniform_lookup :: proc(b: ^Overflow_Uniform($K, $V), h0: u64, key: K) -> (value: V, found: bool) {
    if len(b.slots) == 0 do return {}, false

    h1 := mix(h0, 0xB0B)
    h2 := mix(h0, 0xB0C) | 1

    #no_bounds_check for t in 0 ..< b.probe_limit {
        idx := int((h1 + u64(t) * h2) & b.mask)
        st := b.slots[idx].state

        if st == .Empty do return {}, false
        if st == .Filled && b.slots[idx].hash == h1 && keys_equal(b.slots[idx].key, key) {
            return b.slots[idx].value, true
        }
    }

    return {}, false
}

@(private = "file")
two_choice_lookup :: proc(c: ^Overflow_Two_Choice($K, $V), h0: u64, key: K) -> (value: V, found: bool) {
    if len(c.slots) == 0 do return {}, false

    h_a := mix(h0, 0xC0C)
    h_b := mix(h0, 0xC0D)

    b1 := bucket_index(h_a, c.bucket_count)
    b2 := bucket_index(h_b, c.bucket_count)

    for bucket in ([2]int{b1, b2}) {
        start := bucket * c.bucket_size
        #no_bounds_check for j in 0 ..< c.bucket_size {
            idx := start + j
            if c.slots[idx].state == .Filled && c.slots[idx].hash == h0 && keys_equal(c.slots[idx].key, key) {
                return c.slots[idx].value, true
            }
        }
    }

    return {}, false
}

// --- Insert (two-pass) ---

set :: proc(table: ^Funnel_Table($K, $V), key: K, value: V) -> Insert_Result {
    h0 := hash_key(key, table.seed)

    // Pass 1: Try replace
    if try_replace(table, h0, key, value) {
        return .Replaced
    }

    // Pass 2: Insert new
    result := insert_new(table, h0, key, value)
    if result == .Failed {
        grow_and_rebuild(table)
        return insert_new(table, hash_key(key, table.seed), key, value)
    }
    return result
}

@(private = "file")
try_replace :: proc(table: ^Funnel_Table($K, $V), h0: u64, key: K, value: V) -> bool {
    for i in 0 ..< table.alpha {
        hi := mix(h0, u64(i))
        lvl := &table.levels[i]
        b := bucket_index(hi, lvl.bucket_count)
        start := b * lvl.bucket_size

        #no_bounds_check for j in 0 ..< lvl.bucket_size {
            idx := start + j
            if lvl.slots[idx].state == .Filled {
                if lvl.slots[idx].hash == hi && keys_equal(lvl.slots[idx].key, key) {
                    lvl.slots[idx].value = value
                    return true
                }
            }
        }
    }

    if uniform_replace(&table.overflow_b, h0, key, value) do return true
    if two_choice_replace(&table.overflow_c, h0, key, value) do return true

    return false
}

@(private = "file")
uniform_replace :: proc(b: ^Overflow_Uniform($K, $V), h0: u64, key: K, value: V) -> bool {
    if len(b.slots) == 0 do return false

    h1 := mix(h0, 0xB0B)
    h2 := mix(h0, 0xB0C) | 1

    #no_bounds_check for t in 0 ..< b.probe_limit {
        idx := int((h1 + u64(t) * h2) & b.mask)
        st := b.slots[idx].state

        if st == .Empty do return false
        if st == .Filled && b.slots[idx].hash == h1 && keys_equal(b.slots[idx].key, key) {
            b.slots[idx].value = value
            return true
        }
    }

    return false
}

@(private = "file")
two_choice_replace :: proc(c: ^Overflow_Two_Choice($K, $V), h0: u64, key: K, value: V) -> bool {
    if len(c.slots) == 0 do return false

    h_a := mix(h0, 0xC0C)
    h_b := mix(h0, 0xC0D)

    b1 := bucket_index(h_a, c.bucket_count)
    b2 := bucket_index(h_b, c.bucket_count)

    for bucket in ([2]int{b1, b2}) {
        start := bucket * c.bucket_size
        #no_bounds_check for j in 0 ..< c.bucket_size {
            idx := start + j
            if c.slots[idx].state == .Filled && c.slots[idx].hash == h0 && keys_equal(c.slots[idx].key, key) {
                c.slots[idx].value = value
                return true
            }
        }
    }

    return false
}

@(private = "file")
insert_new :: proc(table: ^Funnel_Table($K, $V), h0: u64, key: K, value: V) -> Insert_Result {
    for i in 0 ..< table.alpha {
        hi := mix(h0, u64(i))
        lvl := &table.levels[i]
        b := bucket_index(hi, lvl.bucket_count)
        start := b * lvl.bucket_size

        first_tomb := -1

        #no_bounds_check for j in 0 ..< lvl.bucket_size {
            idx := start + j
            st := lvl.slots[idx].state

            if st == .Tombstone && first_tomb == -1 {
                first_tomb = idx
            } else if st == .Empty {
                target := idx if first_tomb == -1 else first_tomb
                lvl.slots[target] = Slot(K, V){state = .Filled, hash = hi, key = key, value = value}
                table.len += 1
                if first_tomb != -1 do table.tombstones -= 1
                return .Inserted
            }
        }

        if first_tomb != -1 {
            lvl.slots[first_tomb] = Slot(K, V){state = .Filled, hash = hi, key = key, value = value}
            table.len += 1
            table.tombstones -= 1
            return .Inserted
        }
    }

    if result := uniform_insert_new(&table.overflow_b, h0, key, value); result != .Failed {
        if result == .Inserted do table.len += 1
        return result
    }

    if result := two_choice_insert_new(&table.overflow_c, h0, key, value); result != .Failed {
        if result == .Inserted do table.len += 1
        return result
    }

    return .Failed
}

@(private = "file")
uniform_insert_new :: proc(b: ^Overflow_Uniform($K, $V), h0: u64, key: K, value: V) -> Insert_Result {
    if len(b.slots) == 0 do return .Failed

    h1 := mix(h0, 0xB0B)
    h2 := mix(h0, 0xB0C) | 1

    first_tomb := -1

    #no_bounds_check for t in 0 ..< b.probe_limit {
        idx := int((h1 + u64(t) * h2) & b.mask)
        st := b.slots[idx].state

        if st == .Tombstone && first_tomb == -1 {
            first_tomb = idx
        } else if st == .Empty {
            target := idx if first_tomb == -1 else first_tomb
            b.slots[target] = Slot(K, V){state = .Filled, hash = h1, key = key, value = value}
            return .Inserted
        }
    }

    if first_tomb != -1 {
        b.slots[first_tomb] = Slot(K, V){state = .Filled, hash = h1, key = key, value = value}
        return .Inserted
    }

    return .Failed
}

@(private = "file")
two_choice_insert_new :: proc(c: ^Overflow_Two_Choice($K, $V), h0: u64, key: K, value: V) -> Insert_Result {
    if len(c.slots) == 0 do return .Failed

    h_a := mix(h0, 0xC0C)
    h_b := mix(h0, 0xC0D)

    b1 := bucket_index(h_a, c.bucket_count)
    b2 := bucket_index(h_b, c.bucket_count)

    count1, count2 := 0, 0
    start1 := b1 * c.bucket_size
    start2 := b2 * c.bucket_size

    #no_bounds_check for j in 0 ..< c.bucket_size {
        if c.slots[start1 + j].state == .Filled do count1 += 1
        if c.slots[start2 + j].state == .Filled do count2 += 1
    }

    target_bucket := b1 if count1 <= count2 else b2

    for bucket in ([2]int{target_bucket, b2 if target_bucket == b1 else b1}) {
        start := bucket * c.bucket_size
        first_tomb := -1

        #no_bounds_check for j in 0 ..< c.bucket_size {
            idx := start + j
            st := c.slots[idx].state

            if st == .Tombstone && first_tomb == -1 {
                first_tomb = idx
            } else if st == .Empty {
                target := idx if first_tomb == -1 else first_tomb
                c.slots[target] = Slot(K, V){state = .Filled, hash = h0, key = key, value = value}
                return .Inserted
            }
        }

        if first_tomb != -1 {
            c.slots[first_tomb] = Slot(K, V){state = .Filled, hash = h0, key = key, value = value}
            return .Inserted
        }
    }

    return .Failed
}

// --- Remove ---

remove :: proc(table: ^Funnel_Table($K, $V), key: K) -> bool {
    if table.len == 0 do return false

    h0 := hash_key(key, table.seed)

    for i in 0 ..< table.alpha {
        hi := mix(h0, u64(i))
        lvl := &table.levels[i]
        b := bucket_index(hi, lvl.bucket_count)
        start := b * lvl.bucket_size

        #no_bounds_check for j in 0 ..< lvl.bucket_size {
            idx := start + j
            if lvl.slots[idx].state == .Filled && lvl.slots[idx].hash == hi && keys_equal(lvl.slots[idx].key, key) {
                lvl.slots[idx].state = .Tombstone
                table.len -= 1
                table.tombstones += 1
                return true
            }
        }
    }

    if uniform_remove(&table.overflow_b, h0, key) {
        table.len -= 1
        table.tombstones += 1
        return true
    }

    if two_choice_remove(&table.overflow_c, h0, key) {
        table.len -= 1
        table.tombstones += 1
        return true
    }

    return false
}

@(private = "file")
uniform_remove :: proc(b: ^Overflow_Uniform($K, $V), h0: u64, key: K) -> bool {
    if len(b.slots) == 0 do return false

    h1 := mix(h0, 0xB0B)
    h2 := mix(h0, 0xB0C) | 1

    #no_bounds_check for t in 0 ..< b.probe_limit {
        idx := int((h1 + u64(t) * h2) & b.mask)
        st := b.slots[idx].state

        if st == .Empty do return false
        if st == .Filled && b.slots[idx].hash == h1 && keys_equal(b.slots[idx].key, key) {
            b.slots[idx].state = .Tombstone
            return true
        }
    }

    return false
}

@(private = "file")
two_choice_remove :: proc(c: ^Overflow_Two_Choice($K, $V), h0: u64, key: K) -> bool {
    if len(c.slots) == 0 do return false

    h_a := mix(h0, 0xC0C)
    h_b := mix(h0, 0xC0D)

    b1 := bucket_index(h_a, c.bucket_count)
    b2 := bucket_index(h_b, c.bucket_count)

    for bucket in ([2]int{b1, b2}) {
        start := bucket * c.bucket_size
        #no_bounds_check for j in 0 ..< c.bucket_size {
            idx := start + j
            if c.slots[idx].state == .Filled && c.slots[idx].hash == h0 && keys_equal(c.slots[idx].key, key) {
                c.slots[idx].state = .Tombstone
                return true
            }
        }
    }

    return false
}

// --- Grow and Rebuild ---

@(private = "file")
grow_and_rebuild :: proc(table: ^Funnel_Table($K, $V)) {
    old_backing := table._backing_store
    old_levels := table.levels
    old_overflow_b := table.overflow_b
    old_overflow_c := table.overflow_c
    old_alpha := table.alpha

    for attempt in 0 ..< 8 {
        if attempt > 0 {
            table.seed = mix(table.seed, u64(attempt))
        }

        table.capacity *= 2
        table.len = 0
        table.tombstones = 0

        if !allocate_new_storage(table) {
            continue
        }

        rebuild_ok := true

        // Copy from levels
        rebuild_levels: for i in 0 ..< old_alpha {
            lvl := &old_levels[i]
            #no_bounds_check for j in 0 ..< len(lvl.slots) {
                if lvl.slots[j].state == .Filled {
                    h0 := hash_key(lvl.slots[j].key, table.seed)
                    if insert_new(table, h0, lvl.slots[j].key, lvl.slots[j].value) == .Failed {
                        rebuild_ok = false
                        break rebuild_levels
                    }
                }
            }
        }

        // Copy from overflow B
        if rebuild_ok {
            #no_bounds_check for j in 0 ..< len(old_overflow_b.slots) {
                if old_overflow_b.slots[j].state == .Filled {
                    h0 := hash_key(old_overflow_b.slots[j].key, table.seed)
                    if insert_new(table, h0, old_overflow_b.slots[j].key, old_overflow_b.slots[j].value) == .Failed {
                        rebuild_ok = false
                        break
                    }
                }
            }
        }

        // Copy from overflow C
        if rebuild_ok {
            #no_bounds_check for j in 0 ..< len(old_overflow_c.slots) {
                if old_overflow_c.slots[j].state == .Filled {
                    h0 := hash_key(old_overflow_c.slots[j].key, table.seed)
                    if insert_new(table, h0, old_overflow_c.slots[j].key, old_overflow_c.slots[j].value) == .Failed {
                        rebuild_ok = false
                        break
                    }
                }
            }
        }

        if rebuild_ok {
            delete_soa(old_backing, table.allocator)
            delete(old_levels, table.allocator)
            return
        }

        delete_soa(table._backing_store, table.allocator)
        delete(table.levels, table.allocator)
    }

    // Restore old state
    table._backing_store = old_backing
    table.levels = old_levels
    table.overflow_b = old_overflow_b
    table.overflow_c = old_overflow_c
}

@(private = "file")
allocate_new_storage :: proc(table: ^Funnel_Table($K, $V)) -> bool {
    alpha := table.alpha
    beta := table.beta

    total_slots := 0
    level_sizes := make([]int, alpha, context.temp_allocator)

    sim_size := ceil_to_multiple(table.capacity, beta)
    for i in 0 ..< alpha {
        actual := max(sim_size, beta)
        level_sizes[i] = actual
        total_slots += actual
        sim_size = max(ceil_to_multiple((sim_size * 3) / 4, beta), beta)
    }

    overflow_b_size := next_power_of_two(max(table.capacity / 16, 8 * beta))
    total_slots += overflow_b_size

    overflow_c_bucket := max(2 * compute_loglog_n(table.capacity), 2)
    overflow_c_size := ceil_to_multiple(max(table.capacity / 32, 4 * overflow_c_bucket), overflow_c_bucket)
    total_slots += overflow_c_size

    alloc_err: mem.Allocator_Error

    table._backing_store, alloc_err = make_soa(#soa[]Slot(K, V), total_slots, table.allocator)
    if alloc_err != nil do return false

    table.levels, alloc_err = make([]Funnel_Level(K, V), alpha, table.allocator)
    if alloc_err != nil {
        delete_soa(table._backing_store, table.allocator)
        return false
    }

    offset := 0
    for i in 0 ..< alpha {
        size := level_sizes[i]
        table.levels[i] = Funnel_Level(K, V) {
            slots        = table._backing_store[offset : offset + size],
            bucket_size  = beta,
            bucket_count = size / beta,
        }
        offset += size
    }

    table.overflow_b = Overflow_Uniform(K, V) {
        slots       = table._backing_store[offset : offset + overflow_b_size],
        mask        = u64(overflow_b_size - 1),
        probe_limit = compute_loglog_n(table.capacity),
    }
    offset += overflow_b_size

    table.overflow_c = Overflow_Two_Choice(K, V) {
        slots        = table._backing_store[offset : offset + overflow_c_size],
        bucket_size  = overflow_c_bucket,
        bucket_count = overflow_c_size / overflow_c_bucket,
    }

    return true
}

// --- Utility ---

clear :: proc(table: ^Funnel_Table($K, $V)) {
    // Access the raw state array and fill with .Empty (fast memset)
    n := len(table._backing_store)
    if n > 0 {
        states := table._backing_store.state[:n]
        slice.fill(states, Slot_State.Empty)
    }
    table.len = 0
    table.tombstones = 0
}

contains :: proc(table: ^Funnel_Table($K, $V), key: K) -> bool {
    _, found := get(table, key)
    return found
}

length :: proc(table: ^Funnel_Table($K, $V)) -> int {
    return table.len
}
