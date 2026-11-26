# Inline layer reconciliation lab

Message text, shared inline text controls and reply/header text previously appended valid layer keys to an array and called linear `contains` for every existing layer during cleanup. With many emoji this becomes quadratic work.

`InlineStickerKeyCollection` keeps the same array storage and validates its position indexes as keys are appended. For consecutive indexes, membership computes `query.index - firstIndex`, checks the bounds, then compares the complete key at that position. File ID, position and color must still match. Integer subtraction reports overflow rather than trapping. Nonconsecutive, reversed, sparse or duplicate indexes automatically fall back to the original linear search. There is no hash table, persistent cache or global retained state.

All three callers use the new collection without changing their layer creation, reuse, removal or ordering logic. A plain set was considered first, but exploratory measurements showed its color-inclusive hashing cost was worse for typical short lists. The index-based approach uses the position information already produced by these renderers.

## Validation

The mini-app compiles the exact production collection and key definition. It extracts the current cleanup block and preserves the original cleanup block from `5ca1b89a6`. Generated binding adapters populate real Core Animation layers using lightweight fixtures; they do not construct full sticker/decoder objects. The layer benchmark runs both algorithms on the same dictionary and parent, resetting the starting keys outside the timed region to reduce allocation/order differences.

Seven functional tests pass in debug, release and Address Sanitizer. They cover 1,500 seeded sequences and membership queries, all key fields, equivalent color objects, empty arrays, negative/extreme indexes, arithmetic overflow, sparse/reversed/duplicate positions, copy-and-append value semantics, layer identity, layer removal and final sublayer order. All four changed production files pass Swift syntax parsing. Full account-backed feature modules and the main app were not built.

## Measurements

Apple Silicon, Swift 6.3.3, optimized build, nine alternating batches after warmup. Values are microseconds per operation. Membership includes constructing the collection and querying every key; binding includes dictionary lookup, layer creation when needed, and the extracted cleanup block.

| Scenario | Before | After |
|---|---:|---:|
| 0 keys, membership | 0.0049 | 0.0057 |
| 1 key, membership | 0.0434 | 0.0417 |
| 4 keys, membership | 0.1502 | 0.1391 |
| 16 keys, membership | 0.7019 | 0.3255 |
| 64 keys, membership | 7.2871 | 0.8053 |
| 256 keys, membership | 100.0597 | 2.5083 |
| 1,024 keys, membership stress case | 1547.5903 | 9.1667 |
| 64 sparse keys, fallback membership | 7.4411 | 7.3614 |
| 16 unchanged layers, binding | 0.8119 | 0.7088 |
| 64 unchanged layers, binding | 3.5643 | 2.7491 |
| 256 unchanged layers, binding | 23.0014 | 9.8556 |
| 64 layers, half replaced each binding | 22.9375 | 21.3976 |

The complete binding fixture improves by about 1.3× at 64 unchanged layers and 2.3× at 256. The replacement-heavy fixture improves about 7%. Empty/single-key cases are effectively unchanged; the empty case adds less than one nanosecond in this run. The much larger membership-only gains are algorithm measurements, not full rendering speedups. Actual sticker construction, fetching, decoding, drawing and end-to-end scrolling are excluded. No resident-memory reduction is claimed; the temporary collection adds an index and flag alongside the existing array.

`results.json` includes every batch, and `provenance.json`/`validation.json` record source and test-log hashes.

## Reproduce

```sh
python3 tools/perflab/InlineReconciliationLab/prepare.py
swift test --package-path tools/perflab/InlineReconciliationLab --scratch-path /tmp/InlineReconciliationLab-debug
swift test -c release --package-path tools/perflab/InlineReconciliationLab --scratch-path /tmp/InlineReconciliationLab-release
swift test --sanitize address --package-path tools/perflab/InlineReconciliationLab --scratch-path /tmp/InlineReconciliationLab-asan
INLINE_RECONCILIATION_BENCHMARK=1 swift test -c release --skip-build --package-path tools/perflab/InlineReconciliationLab --scratch-path /tmp/InlineReconciliationLab-release --filter ReconciliationTests.testReconciliationBenchmark
```

Run timing after builds finish. The benchmark writes `/tmp/inline-reconciliation-benchmark.json`.
