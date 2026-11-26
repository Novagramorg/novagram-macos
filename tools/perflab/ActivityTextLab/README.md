# Activity text layout reuse

`ShortPeerRowView` updates its activity model on every active row binding. Previously, `ChatActivitiesModel` allocated and measured a fresh one-line `TextViewLayout` even when its rendered text and width were unchanged. The same model is used by chat titles, header bubbles, and chat-list rows.

The candidate retains only its current layout. Reuse requires identical attributed text, constrained width, backing scale, resolved text color, and selection color. Text construction still runs, preserving locale, peer-name, and activity changes. Every callback and animation update still runs. Empty activity and cleanup discard the cache. The view already retained the displayed layout, so the cache does not retain a history of layouts.

## Correctness evidence

Eleven functional tests pass in debug, release, and Address Sanitizer configurations. The twelfth test is an opt-in benchmark. Tests cover:

- 1,000 repeated model updates with one layout identity and every callback delivered.
- Upload progress changes, all 12 activity cases, private/secret/group namespaces, and groups with matching and mixed activities.
- Peer-name, localization, width, font, theme, scale, and dynamic appearance changes.
- Empty activity, cleanup, selection preservation, view geometry, bounded retention, and model release.
- 637 byte-for-byte CoreText raster comparisons against fresh original measurement, with matching attributed text, line ranges, line frames, and layout sizes. The matrix includes emoji, combining characters, RTL, CJK, long text, truncation, zero/negative widths, and 1×/2×/3× scales. A separate test confirms that the raster helper produces nonblank output.

`prepare.py` extracts the entire current production model and view, actual animation geometry/theme, and actual `PeerInputActivity` enum. It verifies the preserved original model against commit `d3f4a6235`. Both models compile against real TGUIKit, AppKit, CoreText, and SwiftSignalKit. The only current-model change for testing is making the layout helper internal. Model class names differ to allow side-by-side execution.

The lab uses small peer/identifier and localization fixtures, shared by both models; it does not link TelegramCore or the production localization catalog. The rendering proofs cover text lines, not full screenshots or compositor timing. Normal and `SHARE` production frontend parsing pass. The full Telegram application was not built or profiled.

## Performance evidence

Release measurements on Apple Silicon with Swift 6.3.3. Each row is the median of five passes of 10,000 complete model updates, alternating baseline/candidate order. Updates use the real view and signal pipeline; models are detached from a window. Compiler/test builds completed before timing. Raw samples are in `benchmark.json` and `benchmark.log`.

| Model update | Original µs | Candidate µs | Change |
|---|---:|---:|---:|
| Same text and width | 15.303 | 8.810 | 42% less |
| Upload progress changes, same displayed text | 14.720 | 8.917 | 39% less |
| Different peer name every update | 17.459 | 17.987 | 3% more |
| Alternating width | 15.352 | 15.841 | 3% more |
| New model every update | 117.320 | 118.546 | 1% more |
| Empty activity | 1.743 | 1.869 | 0.126 µs more |

These are component measurements, not whole-app speedups or scrolling FPS. Cache misses pay a small key-maintenance cost; repeated bindings avoid text-layout allocation and measurement. The cache retains four additional fields per model, including a reference to the existing displayed layout.

## Reproduce

From the repository root:

```sh
python3 tools/perflab/ActivityTextLab/prepare.py
swift test --package-path tools/perflab/ActivityTextLab --scratch-path /tmp/ActivityTextLab-debug
swift test --package-path tools/perflab/ActivityTextLab --scratch-path /tmp/ActivityTextLab-release -c release
swift test --package-path tools/perflab/ActivityTextLab --scratch-path /tmp/ActivityTextLab-asan --sanitize address
ACTIVITY_BENCHMARK=1 swift test --package-path tools/perflab/ActivityTextLab --scratch-path /tmp/ActivityTextLab-release -c release --skip-build --filter ActivityTextTests.testBenchmark
swiftc -frontend -parse packages/ShortPeerRow/Sources/ShortPeerRow/ChatActivitiesModel.swift
swiftc -frontend -parse -D SHARE packages/ShortPeerRow/Sources/ShortPeerRow/ChatActivitiesModel.swift
```

`provenance.json` records production, reference, generated-source, and supporting-source hashes. The checked-in logs are final successful runs. During test development, the selection test initially called inaccessible TGUIKit APIs; it was corrected to set the public layout selection value before these final runs.
