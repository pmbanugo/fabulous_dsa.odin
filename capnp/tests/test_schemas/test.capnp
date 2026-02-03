@0xbf4c8e2e1c8af4c7;

struct Point {
  x @0 :UInt32;
  y @1 :UInt32;
}

struct Person {
  name @0 :Text;
  age @1 :UInt16;
}

struct Numbers {
  values @0 :List(UInt32);
}

struct Inner {
  value @0 :UInt64;
}

struct Outer {
  inner @0 :Inner;
  id @1 :UInt32;
}

struct Entry {
  key @0 :UInt32;
  value @1 :UInt32;
}

struct Table {
  entries @0 :List(Entry);
}

struct DataHolder {
  data @0 :Data;
}

struct BoolList {
  flags @0 :List(Bool);
}
