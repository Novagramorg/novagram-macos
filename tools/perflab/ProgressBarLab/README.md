# ProgressBarLab

This mini-app compares the complete previous `LinearProgressControl` from `d0610bf3d` with the current production class imported from TGUIKit. `prepare.py` verifies the preserved source against Git and generates a renamed reference class. The reference uses `@testable import TGUIKit` for the inherited tracking-area property; no production API was widened. Both controls use actual AppKit, Core Animation and TGUIKit code. The only fixture assets are bootstrap theme icons and a small generated scrubber image.

## Change

Three decorative views (played progress, fetched progress and preview) are now `SimpleLayer`s. Each visible buffered range also uses a layer. The container remains a view for coordinate conversion and clipping, and the scrubber remains an `ImageButton`. Public API, input callbacks, accessibility, playback invalidation and range-selection logic are preserved.

The layers match AppKit's zero anchor point, empty edge-antialiasing mask, clipping, opacity and continuous corners. Width changes preserve the former view's nonnegative size clamping. These details were required by the comparison tests: the initial version had visible pixel differences at fractional edges and rendered negative fetched progress incorrectly. GPU captures initially failed the nonblank checks because the render tree had not been committed after attaching it to CARenderer. The final harness commits it and requires nonblank results plus changing frames for moving animations.

A control without a scrubber or ranges now owns two views (control and container), versus five previously. Each visible range saves one additional view. Layer counts are unchanged; this is not a measurement of process resident memory.

## Validation

Nine functional tests pass in debug, release and Address Sanitizer. The opt-in benchmark is skipped in ordinary runs. The shared TGUIKit suite also passes all 213 functional tests, with two optional tests skipped.

- 430 exact static pixel pairs in the main geometry, appearance and invalid-input matrices: 1×/2×/3× rasterization, fractional sizes, all alignments, insets, minimum visibility, rounded/explicit corners, preview, colors, scrubbers, overlapping ranges, negative/oversized progress and NaN normalization.
- Additional comparisons after scrubbing, playback stopping/resizing and range removal. Geometry tolerates less than 0.00000001 points of AppKit floating-point roundoff; pixel comparisons are exact.
- Mouse down/drag/up callbacks and temporary state in live/deferred and enabled/disabled configurations; 2,484 hit-test points across interactive/noninteractive and scrubber-present/absent states.
- Accessibility slider values, increment/decrement callbacks and disabled accessibility/control behavior.
- Playback parameters, seeks, pause, resize invalidation, decoration counts and removed-range release.
- Sixteen exact nonblank GPU frame pairs using actual native layer trees in Metal-backed CARenderer: four samples each for playback, paused playback, ordinary width changes and buffered-range width changes. Explicit animation copies are held at controlled time offsets; the short buffered-range duration is normalized to four seconds. Unrelated scrubber-image appearance animations are cleared before starting the target animations. The moving scenarios must change across samples, while paused frames must stay identical. This validates interpolation and raster output, not wall-clock pacing. Images are in `renders/`.

The full Telegram application was not built and end-to-end chat scrolling was not measured.

## Release measurements

Apple Silicon, Swift 6.3.3. Medians of nine alternating batches of 2,000 operations, in microseconds per operation. CPU measurements ran after builds and GPU checks finished.

| Path | Before | After |
|---|---:|---:|
| Create, size and initialize progress | 118.290 | 55.597 |
| Plain progress update | 0.807 | 0.345 |
| Rebind unchanged buffered ranges | 1.603 | 1.623 |
| Add/remove three buffered ranges | 95.148 | 4.844 |
| Resize | 1.761 | 1.688 |
| Repeated playback notification | 0.141 | 0.151 |

Creation is about 53% faster, ordinary progress updates 57% faster, and range-view churn 95% faster in this isolated run. Unchanged ranges and playback notifications have small bookkeeping differences. These are actual control timings, not app-wide speedups or frame-rate measurements. Raw batches are in `results.json`; logs and source hashes are saved alongside it.

## Run

```sh
python3 tools/perflab/ProgressBarLab/prepare.py
swift test --package-path tools/perflab/ProgressBarLab --scratch-path /tmp/ProgressBarLab-debug
swift test -c release --package-path tools/perflab/ProgressBarLab --scratch-path /tmp/ProgressBarLab-release
swift test --sanitize address --package-path tools/perflab/ProgressBarLab --scratch-path /tmp/ProgressBarLab-asan
PROGRESS_RENDER_DIR=/tmp/progress-renders swift test --skip-build --package-path tools/perflab/ProgressBarLab --scratch-path /tmp/ProgressBarLab-debug --filter ProgressTests.testAnimatedMetalFramesMatch
PROGRESS_BENCHMARK=1 swift test -c release --skip-build --package-path tools/perflab/ProgressBarLab --scratch-path /tmp/ProgressBarLab-release --filter ProgressTests.testBenchmark
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-debug
```

Use separate scratch directories for each package. Run CPU benchmarks after builds and GPU tests finish. Benchmark output is `/tmp/progress-benchmark.json`.
