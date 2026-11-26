# Chat-list activity invalidation

The original `ChatListRowView.inputActivities` observer compared the previous input's activities with `item.activities` and the current theme. It ignored available width, display scale, and conversation identity. Consequently, unchanged typing text could keep its old truncation after resizing or changing badge space. Switching between private/group contexts could keep the old wording, and an incoming value different from the item's snapshot could be skipped.

There was also redundant work during normal item rebinding: `super.set` calls `updateColors`, which reassigns the current activity value before the end of `ChatListRowView.set` assigns the new item's activities. The old observer compared against the new item snapshot during both assignments, updating the activity model twice when activity content changed.

The candidate compares previous and incoming tuples directly, preserving `Peer.isEqual` semantics without allocating a mapped `[Activity]` array. It includes conversation identity, width, backing scale, and theme in invalidation. The width/scale pair is stored before invoking the model callback so reentrant updates retain the latest state. Empty, nil, and invalid-item paths release the model and clear the pair. No peer history or extra activity array is retained.

## Correctness evidence

Ten functional tests pass in debug, release, and Address Sanitizer builds; one additional benchmark is opt-in.

- The preserved original observer demonstrably retains a 370-point constraint after shrinking the available width. The candidate follows each new width and matches fresh text measurement.
- Private/group namespace changes and incoming values that differ from the item snapshot reproduce stale original text and correct candidate text.
- Rebinding changed activity updates the original model twice and the candidate once. Equal replacement peers and 1,000 repeated assignments perform no extra candidate model updates.
- Theme, selection, display scale, group size, activity kind, and width changes invalidate correctly. All twelve activity cases are covered.
- Empty/nil/invalid item cleanup, media-preview visibility, object release, and same-value/replacement reentrancy are tested.
- 335 nonblank CoreText raster pairs match fresh model output, with equal attributed text, line ranges, and layout sizes. The matrix includes RTL, combining characters, family emoji, groups, narrow/wide constraints, and 1×/2×/3× scales.
- The production file passes Swift frontend parsing.

`prepare.py` extracts the exact original/current row observers, current width/scale field, entire production activity model/view/indicator, actual animation geometry/theme, actual activity enum, and actual `PeerEquatable` implementation. The original observer is verified against `f3bcad0ca`. The lab links real TGUIKit, AppKit, CoreText, and SwiftSignalKit. It uses small peer/item/theme/localization fixtures; its model subclass only counts calls before forwarding to the actual implementation. The test `bind` helper reproduces the relevant `super.set → updateColors → new activity assignment` order, not the entire chat-list row binding method.

The item fixture supplies a width directly rather than constructing real badges, accounts, or row items. Localization fixtures are shared by both observers; they are not the production language catalog. Raster proofs cover text lines rather than complete window screenshots. The full application was not built or profiled.

## Reproduce

From the repository root:

```sh
python3 tools/perflab/ChatListActivityLab/prepare.py
swift test --package-path tools/perflab/ChatListActivityLab --scratch-path /tmp/ChatListActivityLab-debug
swift test --package-path tools/perflab/ChatListActivityLab --scratch-path /tmp/ChatListActivityLab-release -c release
swift test --package-path tools/perflab/ChatListActivityLab --scratch-path /tmp/ChatListActivityLab-asan --sanitize address
LIST_ACTIVITY_BENCHMARK=1 swift test --package-path tools/perflab/ChatListActivityLab --scratch-path /tmp/ChatListActivityLab-release -c release --skip-build --filter ActivityTests.testBenchmark
swiftc -frontend -parse packages/ChatListUI/Sources/ChatListUI/ChatListRowView.swift
```

## Performance evidence

Release build on Apple Silicon, Swift 6.3.3. Medians of five alternating-order passes, each with 10,000 observer assignments or relevant rebinding sequences. All builds/tests complete before timing. Rows remain detached from a window. Raw timings and model-update counts are included in `benchmark.json` and `benchmark.log`.

| Scenario | Original µs | Candidate µs |
|---|---:|---:|
| Unchanged, one peer | 2.848 | 2.681 |
| Unchanged, eight peers | 2.896 | 2.807 |
| Unchanged, 64 peers | 4.026 | 3.601 |
| Rebinding changed activity | 26.001 | 19.998 |
| Cleared (nil) activity | 0.029 | 0.030 |

Each changed-item run performs 20,001 original model updates versus 10,001 candidate updates, including initial setup. Unchanged runs perform one initial update in both versions. The candidate replaces a mapped comparison array with direct tuple comparison and avoids the redundant old-content update. It adds a width/scale pair per row. These are component results using the documented fixtures, not whole-app scrolling or frame-rate measurements. The resize path intentionally does work the original incorrectly skipped; rendering correctness takes precedence over preserving that stale-text shortcut.
