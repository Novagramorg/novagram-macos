# Merge-list regression tests and benchmarks

Run from the repository root:

```sh
python3 tools/tests/merge-lists/run.py
python3 tools/tests/merge-lists/run.py --configuration release
python3 tools/tests/merge-lists/run.py --benchmark
```

The runner copies the complete working-tree `MergeLists.swift` into a temporary Swift package. This tests the actual production source without building AppKit or resolving the application's package graph. The XCTest files also belong to the normal TGUIKit test target.

`MergeListsReference.swift` freezes the ascending implementation from commit `8ac0b9796d1560e7d6ab735eea14c5d218fecb68`. Keep it unchanged when optimizing production code. Exact comparisons cover every removal, insertion and update tuple, including row values, stable IDs, previous indices and ordering. Cases include empty lists, sort ties, duplicate IDs, changed sort positions, hash collisions, value equality across different IDs, unsorted inputs and both `allUpdated` settings. Sorted transitions additionally check reconstruction of the destination list.

The benchmark compiles the reference and production functions in separate library modules without `@inlinable`, matching external package callers. It reports median microseconds per call over seven measured batches after warmup, alternating execution order. It exercises both small integer rows and larger rows with `AnyHashable` IDs, strings and array payloads, including separately allocated equal lists. These are synthetic measurements, not end-to-end UI timings.

The optimization preserves the merge's matching branches. Each unmatched right cursor position becomes an insertion immediately; those positions are exactly the entries the previous implementation left unmarked in `keptRight`. The right cursor only advances, preserving insertion order. The previous-index dictionary is built once on first use, in the same left-to-right order, preserving the last index for duplicate IDs. Unchanged and deletion-only transitions never need that dictionary. As with ordinary collection algorithms, comparison and identity operations must be stable while the call runs.
