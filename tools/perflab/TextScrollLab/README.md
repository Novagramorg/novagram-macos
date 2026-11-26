# Text updates and table scrolling lab

This standalone AppKit mini-app builds the real TGUIKit package without Telegram or TelegramCore. It benchmarks text updates both detached and mounted in a window, plus actual TGUIKit tables containing 300 text rows, links, and optional primary/secondary sticky headers. `--preview` opens the table for interactive scrolling and text selection.

The baseline is commit `28cf6ba5f`. `prepare.py` copies TGUIKit into a temporary package and replaces only `TextView.swift` and `TableView.swift` for the baseline. Both variants use identical dependencies and fixtures. The working checkout is never switched. Compiler and source hashes are recorded in `Evidence/*-provenance.json`.

```sh
bash tools/perflab/TextScrollLab/run.sh baseline > tools/perflab/TextScrollLab/Evidence/baseline.json
bash tools/perflab/TextScrollLab/run.sh candidate > tools/perflab/TextScrollLab/Evidence/candidate.json
bash tools/perflab/TextScrollLab/run.sh baseline --snapshots tools/perflab/TextScrollLab/Evidence/baseline-snapshots
bash tools/perflab/TextScrollLab/run.sh candidate --snapshots tools/perflab/TextScrollLab/Evidence/candidate-snapshots
python3 tools/perflab/TextScrollLab/compare.py
bash tools/perflab/TextScrollLab/run.sh candidate --preview
```

Run the variants sequentially without simultaneous tests or other CPU-heavy work. Text fixtures perform 10,000 update/layout operations per trial; changing fixtures alternate content and width, so they exercise invalidation. The scroll-geometry fixture performs 10,000 sticky-header/visible-range updates. The scrolling fixture performs 250 moves with run-loop delivery, layout, and text-row reuse. Every case has seven trials. `trialsMs` measures elapsed time; `cpuTrialsMs` measures process CPU time, including AppKit background work. Run-loop waiting dominates scroll elapsed time, and process CPU includes asynchronous rendering, so neither should be interpreted as frame-delivery latency.

## Changes

- Reuse tooltip rectangles while their geometry is unchanged. Callbacks resolve the current layout's links, even when their destinations change. External tooltip additions/removals invalidate the cache.
- Keep drawing and embedded-content layers in place when their order is already correct. Repair changed ordering, and preserve highlight, blur, and drawing-lock behavior.
- Compute spoiler rectangles once per ink update and reuse them for embedded-content visibility. Do not assign an already-correct opacity.
- Avoid requesting another layout pass on an ordinary TextView when its drawing and embedded-layer geometry already matches. Continue drawing invalidation and selection processing on every update. Subclasses, custom layout callbacks, blur, and changed geometry keep their layout path.
- Skip sticky-header range calculations when that header is absent or table updates suppress its processing. Read the visible rectangle once per `visibleRows` call. Scroll callback order, row mouse updates, and fresh post-callback range queries are preserved.

## Measurements

Medians from the recorded first final run on this Apple Silicon machine:

| Fixture | Baseline | Candidate | Reduction |
|---|---:|---:|---:|
| Mounted unchanged text, 10,000 updates | 20.60 ms | 10.89 ms | 47.1% |
| Detached unchanged text | 19.91 ms | 10.71 ms | 46.2% |
| Mounted linked text with changing width | 38.46 ms | 29.93 ms | 22.2% |
| Mounted spoiler text with changing width | 161.48 ms | 146.47 ms | 9.3% |
| Mounted plain text with changing width | 31.00 ms | 29.89 ms | 3.6% |
| Scroll geometry, no sticky header | 4.92 ms | 1.74 ms | 64.7% |
| Scroll geometry, one sticky header | 27.94 ms | 25.75 ms | 7.9% |
| Scroll geometry, two sticky headers | 43.27 ms | 42.40 ms | 2.0% |

Full scrolling elapsed time was essentially unchanged. Process CPU measurements varied substantially, with different gains and slowdowns across runs. A second run reversed execution order; both raw datasets and comparisons are retained in `Evidence/*-repeat.json` and `repeat-comparison.json`. The text-update gains persisted, while scrolling CPU results were inconsistent; this pass does not demonstrate an end-to-end scrolling speedup. No full Telegram build, chat-opening benchmark, or retained-memory reduction is claimed.

## Correctness checks

All 176 TGUIKit tests passed in both debug and release. All 35 focused Address Sanitizer tests passed without reported memory errors. `Evidence/validation.json` records hashes of the verified production and test sources.

`TextViewUpdateRegressionTests` covers tooltip reuse and invalidation, changed link destinations, highlight ordering, external layer-order changes, redraws, selection inheritance, mutable measurements, nil layouts, spoiler selection/reveal, embedded-content visibility, blur/drawing-lock transitions, geometry repair, subclass callbacks, and custom layout callbacks.

`TableScrollGeometryTests` checks eliminated row queries for absent headers, independent primary/secondary header configuration, both table orientations, insets, resizing, row removal, final coalesced scroll delivery, and callbacks that mutate the table before mouse updates.

The mini-app compares six rendered text fixtures byte-for-byte at 1× and 2× rasterization scales. The snapshot window uses a 2× backing scale; text measurements use the fixture's scale. Fixtures include multilingual text, emoji, links, and selection, with nonempty-render sentinels. It also compares 42 sticky-header frame/visibility/item and visible-range checkpoints across both orientations and zero/one/two headers. PNG previews, raw RGBA buffers, geometry traces, and source hashes are retained.

```sh
swift test --package-path packages/TGUIKit
swift test --package-path packages/TGUIKit -c release
swift test --package-path packages/TGUIKit --scratch-path /tmp/telegram-textscroll-asan --sanitize=address --filter 'TextViewUpdateRegressionTests|TableScrollGeometryTests|TextViewUpdateTests|AccessibilityTableReproTests|TextButtonLayoutTests'
```
