# Preserve sticky-header indexes through table layout

TableView.layout performs a native update workaround that adds and removes a temporary row. Each list mutation invalidated both cached sticky-header indexes even though the real rows and header positions were unchanged. The next sticky-header update scanned the complete list and allocated new index arrays.

The final change captures existing index arrays before that workaround and restores them only when exactly its two list mutations occurred. A wrapping version counter advances on every list mutation and either header-class setter. Synchronous callbacks that change rows or header classes therefore prevent stale indexes from being restored. Actual insertions, removals, replacements and class changes retain invalidation. Absent caches remain lazy.

This preserves the existing native update sequence, including row lifecycle and scroll geometry. It adds one UInt version counter per table and reuses already existing index arrays; it does not add a second persistent index cache. No whole-process memory reduction is claimed.

## Reproduce

```sh
python3 tools/perflab/TableLayoutLab/prepare-isolated.py /tmp/TableLayoutValidation
swift test --package-path /tmp/TableLayoutValidation --scratch-path /tmp/TableLayoutValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/TableLayoutValidation --scratch-path /tmp/TableLayoutValidation-asan --sanitize address
TABLE_LAYOUT_BENCHMARK=1 swift test --package-path /tmp/TableLayoutValidation --scratch-path /tmp/TableLayoutValidation-build -c release --skip-build --filter LayoutBenchmarkTests
cp /tmp/table-layout-benchmark.json /tmp/table-forward.json
TABLE_LAYOUT_BENCHMARK=1 TABLE_LAYOUT_REVERSE=1 swift test --package-path /tmp/TableLayoutValidation --scratch-path /tmp/TableLayoutValidation-build -c release --skip-build --filter LayoutBenchmarkTests
cp /tmp/table-layout-benchmark.json /tmp/table-reverse.json
swift test --package-path /tmp/TableLayoutValidation/TGUIKit --scratch-path /tmp/TableLayoutValidation-kit -c release
```

Use fresh output directories and measure without competing builds. The generator freezes complete candidate and baseline TGUIKit libraries. TableView.swift is their only production difference. An identical test-only extension exposes cached index counts, header frames and index validity; it adds no instance fields or production API. The reference contains unrelated pending TableView edits that were already present when captured and are preserved by this change.

## Measurements

Release medians in microseconds per operation. Nine alternating paired batches plus a separate reversed-order process. Positive percentages mean less CPU time. Real tables are attached to a hidden native window; transactions drain between batches outside timing. There are 1,000 layout iterations per batch and 300 resize iterations. A header occurs every twenty rows.

| Workload | Forward | Reversed |
| --- | ---: | ---: |
| layout_0 | 7.300 → 7.280 (+0.3%) | 7.845 → 7.627 (+2.8%) |
| layout_1000 | 13.448 → 13.296 (+1.1%) | 14.220 → 13.994 (+1.6%) |
| layout_10000 | 15.219 → 15.187 (+0.2%) | 16.353 → 16.514 (-1.0%) |
| layout_40 | 13.116 → 13.158 (-0.3%) | 13.065 → 13.352 (-2.2%) |
| layout_and_sticky_0 | 7.882 → 7.867 (+0.2%) | 7.967 → 8.103 (-1.7%) |
| layout_and_sticky_1000 | 23.404 → 16.542 (+29.3%) | 24.611 → 17.506 (+28.9%) |
| layout_and_sticky_10000 | 90.849 → 18.648 (+79.5%) | 91.672 → 19.782 (+78.4%) |
| layout_and_sticky_40 | 16.714 → 16.443 (+1.6%) | 17.557 → 17.108 (+2.6%) |
| resize_width_1000 | 65.104 → 58.660 (+9.9%) | 69.766 → 62.388 (+10.6%) |
| resize_width_40 | 58.370 → 59.097 (-1.2%) | 60.815 → 60.879 (-0.1%) |

Layout followed by a sticky-header update uses about 29% less CPU time at 1,000 rows and 78–80% less at 10,000 rows. The 40-row case improves by 1.6–2.6%. Width resizing followed by layout/header updates improves by 10–11% for 1,000 rows; the 40-row resize case is 0.1–1.2% slower. Layout without configured sticky headers varies from 2.8% faster to 2.2% slower, with the largest measured slowdown about 0.29 microseconds per call. This pass targets rescanning after layout; an ordinary scroll with no preceding layout already used cached indexes.

These fixtures use basic native table rows and headers. They exclude chat text measurement, media decoding, full scroll-event processing, GPU presentation and complete application frame pacing. They prove a reduction in shared layout/header work, not a whole-chat FPS increase. An initial timing run began while competing compilers were present; it is retained separately and excluded from all reported results. Final runs started after the compiler check returned no matching processes.

## Correctness

Five focused tests pass in release and Address Sanitizer with leak detection disabled. The native matrix covers 284 paired snapshots across empty, one-row, short and 80-row lists; flipped and nonflipped documents; content insets; fractional offsets and viewport sizes; selection; repeated layouts; scrolling; width/height changes; changed row heights; insert/remove operations; nested updates; clearing; and a tall row. Every document rectangle, clip bound, visible range, row rectangle, realized-row frame, selected row and complete bitmap matches exactly. Nonblank bitmap assertions prevent vacuous rendering comparisons.

A baseline-versus-baseline control compares another 72 snapshots. A sticky-header scenario compares header frames through scrolling, layout and removal. Cache tests prove that both existing arrays survive repeated unchanged layouts and invalidate after real insertion. A native table subclass injects synchronous callbacks from endUpdates: inserting a header, switching the primary class, switching the secondary class, replacing the first row at the same count, and removing all rows. All five cases per implementation preserve correct indexes.

Three additional tests in the production TGUIKit target count actual header-class queries. Twenty unchanged layouts trigger no rescans, while real insertion/removal and either class change still refresh the relevant indexes. The complete frozen TGUIKit suite passes 407 functional tests with 18 optional measurements skipped. Its existing tests cover coalesced scrolling, viewport geometry, resize anchoring, selection and animation completion.

A fresh generator reproduced all 515 Swift source and test files in both libraries and the host. All 668 final compiler inputs are retained by hash and verified unchanged. The measured production source equals the current worktree, with only the identical test-only inspection extension appended in the lab. The final snapshot adds the three production regression tests; its 354 library source files and benchmark implementation match the measured versions. The comparison test was renamed after the experiment changed direction; its assertions stayed unchanged and release/Address Sanitizer were rerun. No complete Telegram application build was performed.

## Rejected alternatives

An empty native update cycle plus needsLayout failed 96 assertions: short-list resizes could retain the old document height, change clip offsets and visible rows, and render different pixels. Explicit table tiling fixed geometry and pixels, but changed offscreen row-view retention. Waiting for pending run-loop work reduced the mismatch to four resize cases. Adding native layout invalidation or refreshing the final row height still left those differences. The baseline-versus-baseline control passed, confirming that the remaining comparison was not simply random fixture variation. These alternatives were not shipped; their logs and source snapshots are retained.

The final optimization retains the native workaround and removes the unnecessary index rebuild that follows it. Archived logs normalize trailing whitespace.
