package funnel_hash

import "core:testing"

@(test)
test_soa_basic_insert_and_get :: proc(t: ^testing.T) {
    table, err := make_funnel_table(int, string, initial_capacity = 64)
    testing.expect(t, err == .None, "Expected no error")
    defer delete_funnel_table(&table)

    result := set(&table, 1, "one")
    testing.expect(t, result == .Inserted, "Expected .Inserted")

    value, found := get(&table, 1)
    testing.expect(t, found, "Expected key 1 to be found")
    testing.expect(t, value == "one", "Expected value 'one'")
}

@(test)
test_soa_replace_existing_key :: proc(t: ^testing.T) {
    table, _ := make_funnel_table(int, string, initial_capacity = 64)
    defer delete_funnel_table(&table)

    set(&table, 1, "one")
    result := set(&table, 1, "ONE")
    testing.expect(t, result == .Replaced, "Expected .Replaced")

    value, found := get(&table, 1)
    testing.expect(t, found, "Expected key 1 to be found")
    testing.expect(t, value == "ONE", "Expected value 'ONE'")
    testing.expect(t, length(&table) == 1, "Length should be 1")
}

@(test)
test_remove :: proc(t: ^testing.T) {
    table, _ := make_funnel_table(int, string, initial_capacity = 64)
    defer delete_funnel_table(&table)

    set(&table, 1, "one")
    set(&table, 2, "two")
    testing.expect(t, length(&table) == 2, "Length should be 2")

    removed := remove(&table, 1)
    testing.expect(t, removed, "Expected key 1 to be removed")
    testing.expect(t, length(&table) == 1, "Length should be 1")

    _, found := get(&table, 1)
    testing.expect(t, !found, "Key 1 should not be found after removal")
}

@(test)
test_soa_many_insertions :: proc(t: ^testing.T) {
    table, _ := make_funnel_table(int, int, initial_capacity = 64)
    defer delete_funnel_table(&table)

    count :: 1000
    for i in 0 ..< count {
        set(&table, i, i * 10)
    }
    testing.expect(t, length(&table) == count, "Length should be 1000")

    for i in 0 ..< count {
        value, found := get(&table, i)
        testing.expect(t, found, "Expected key to be found")
        testing.expect(t, value == i * 10, "Expected correct value")
    }
}

@(test)
test_soa_string_keys :: proc(t: ^testing.T) {
    table, _ := make_funnel_table(string, int, initial_capacity = 64)
    defer delete_funnel_table(&table)

    set(&table, "hello", 1)
    set(&table, "world", 2)

    v1, f1 := get(&table, "hello")
    v2, f2 := get(&table, "world")

    testing.expect(t, f1 && v1 == 1, "Expected 'hello' -> 1")
    testing.expect(t, f2 && v2 == 2, "Expected 'world' -> 2")
}

@(test)
test_soa_no_duplicate_after_remove_reinsert :: proc(t: ^testing.T) {
    table, _ := make_funnel_table(int, string, initial_capacity = 64)
    defer delete_funnel_table(&table)

    for i in 0 ..< 200 {
        set(&table, i, "original")
    }

    for i in 0 ..< 100 {
        remove(&table, i)
    }

    for i in 0 ..< 100 {
        set(&table, i, "updated")
    }

    for i in 0 ..< 100 {
        remove(&table, i)
    }

    for i in 0 ..< 100 {
        _, found := get(&table, i)
        testing.expect(t, !found, "Key should not be found after removal")
    }

    for i in 100 ..< 200 {
        value, found := get(&table, i)
        testing.expect(t, found, "Key should still exist")
        testing.expect(t, value == "original", "Value should be unchanged")
    }
}

@(test)
test_clear :: proc(t: ^testing.T) {
    table, _ := make_funnel_table(int, string, initial_capacity = 64)
    defer delete_funnel_table(&table)

    set(&table, 1, "one")
    set(&table, 2, "two")
    set(&table, 3, "three")
    testing.expect(t, length(&table) == 3, "Length should be 3")

    clear(&table)
    testing.expect(t, length(&table) == 0, "Length should be 0 after clear")
    testing.expect(t, !contains(&table, 1), "Key 1 should be absent after clear")
}

@(test)
test_soa_growth_trigger :: proc(t: ^testing.T) {
    table, _ := make_funnel_table(int, int, initial_capacity = 16, delta = 0.1)
    defer delete_funnel_table(&table)

    for i in 0 ..< 500 {
        set(&table, i, i)
    }

    testing.expect(t, length(&table) == 500, "Length should be 500")

    for i in 0 ..< 500 {
        value, found := get(&table, i)
        testing.expect(t, found, "Expected key to be found")
        testing.expect(t, value == i, "Expected correct value")
    }
}

@(test)
test_soa_overflow_data_preserved_on_resize :: proc(t: ^testing.T) {
    // Use small capacity to force items into overflow quickly
    table, _ := make_funnel_table(int, int, initial_capacity = 16, delta = 0.5)
    defer delete_funnel_table(&table)

    // Insert enough to fill levels and overflow
    for i in 0 ..< 100 {
        set(&table, i, i * 100)
    }

    // Force a resize by inserting more
    for i in 100 ..< 300 {
        set(&table, i, i * 100)
    }

    // Verify ALL keys are still accessible (including those that were in overflow)
    for i in 0 ..< 300 {
        value, found := get(&table, i)
        testing.expect(t, found, "Key should be found after resize")
        testing.expect(t, value == i * 100, "Value should be correct after resize")
    }
}
