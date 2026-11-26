# Text hit-testing lab

This executable measures the real TGUIKit `TextViewLayout.findIndex(location:)` against the implementation from `afbb2f441`. The baseline is shared with TGUIKit's regression tests through a source symlink. No Telegram account, native media libraries or main-app build is required.

The old lookup first allocated an array of all line frames, scanned for the closest rectangle, then scanned the lines again to recover its index. The candidate visits the actual lines once and returns immediately for a containing line. It preserves the existing five-point adjustment, nearest-line rules, first-match ties, special y coordinates, and fallbacks for nonfinite geometry. It does not cache frames or assume sorted/nonoverlapping lines: callers can mutate the public line array and frames.

Empty and unmeasured layouts now return `-1`. Existing callers were audited; TextView's mouse-down path now forwards an empty hit to its parent instead of indexing a missing line. Selection drawing also skips empty line arrays. This prevents out-of-bounds access when interacting with an empty or not-yet-measured view. The public method signature is unchanged.

## Validation

- All 182 TGUIKit tests pass in both debug and release.
- All 21 focused hit-testing, text-update and scroll-geometry tests pass under Address Sanitizer.
- Six new regression tests cover 50,000 seeded randomized hit queries; mutable, overlapping, duplicate and unordered frames; measured multilingual text, RTL, alignment, cutouts, line edges, points outside text, nonfinite coordinates, links and selection in both drag directions.
- Empty-text tests exercise hit-testing, word/paragraph selection, link/date/code lookup, mouse-down forwarding and drawing an empty selection.

These tests use real AppKit, Core Text and TGUIKit. Theme image placeholders initialize the toolkit. They do not constitute full Telegram UI or end-to-end chat-scrolling validation. There is no retained layout cache or additional per-layout state.

## Release measurements

Apple Silicon, Swift 6.3.3. Median of nine alternating baseline/candidate batches, 20,000 queries per batch. Complete results, including first-line and out-of-bounds cases, are in `results.json`.

| Lines | Middle-line query before | After | Speedup | Rectangle-array payload eliminated per query |
|---:|---:|---:|---:|---:|
| 1 | 50.5 ns | 12.8 ns | 3.94× | 32 B |
| 4 | 70.8 ns | 22.8 ns | 3.11× | 128 B |
| 20 | 207.7 ns | 74.4 ns | 2.79× | 640 B |
| 100 | 849.5 ns | 289.3 ns | 2.94× | 3,200 B |
| 500 | 4,173.0 ns | 1,392.2 ns | 3.00× | 16,000 B |

Array payload is calculated from `MemoryLayout<CGRect>.stride × line count`, excluding allocator/header overhead. It is temporary allocation traffic, not a measured reduction in retained application memory. The 500-line case is a stress fixture. No whole-app scrolling speedup is claimed.

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-debug
swift test -c release --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release
swift test --sanitize address --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-asan --filter 'TextHitTestingTests|TextViewUpdateRegressionTests|TextViewUpdateTests|TableScrollGeometryTests'
TEXT_HIT_RESULTS=tools/perflab/TextHitTestingLab/results.json swift run -c release --package-path tools/perflab/TextHitTestingLab --scratch-path /tmp/TextHitTestingLab-release TextHitTestingLab
```

Run performance measurements separately from compilation or other benchmarks.
