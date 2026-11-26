# Visual-effect and chat panel masks

Unmasked `VisualEffect` views no longer allocate an unused silhouette layer. A mask layer is allocated on first use, retained across non-empty mask updates, and detached and released when the mask is cleared. Cleared layers drop their image immediately, including while Core Animation finishes its transaction. Repeated nil assignments also avoid redundant native-mask and layer work. The view's stored object size is unchanged.

Flat chat panels reuse their existing mask layer instead of replacing it on every layout. Updates disable implicit actions so resizing a reused mask cannot introduce an animation that the previous newly-created mask did not have. Panel removal and changes between blur and flat rendering retain their existing behavior.

Native `NSImage` mask wrappers are still regenerated for non-empty assignments. This preserves the existing reset behavior when callers mutate or replace the inherited public `maskImage`. The optimization does not cache mutable image wrappers.

## Reproduce

```sh
python3 tools/perflab/VisualEffectMaskLab/prepare-isolated.py /tmp/VisualEffectMaskValidation
swift test --package-path /tmp/VisualEffectMaskValidation --scratch-path /tmp/VisualEffectMaskValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/VisualEffectMaskValidation --scratch-path /tmp/VisualEffectMaskValidation-asan --sanitize address
MASK_BENCHMARK=1 swift test --package-path /tmp/VisualEffectMaskValidation --scratch-path /tmp/VisualEffectMaskValidation-build -c release --skip-build --filter MaskBenchmarkTests
cp /tmp/visual-effect-mask-benchmark.json /tmp/mask-forward.json
MASK_BENCHMARK=1 MASK_REVERSE=1 swift test --package-path /tmp/VisualEffectMaskValidation --scratch-path /tmp/VisualEffectMaskValidation-build -c release --skip-build --filter MaskBenchmarkTests
cp /tmp/visual-effect-mask-benchmark.json /tmp/mask-reverse.json
```

Use a fresh output directory. The repository directory is a template, not a directly buildable package. The generator copies two complete TGUIKit libraries, restoring the captured original `VisualEffectView.swift` in the baseline. It extracts the actual `ChatRowView.applyCutBands` method into small row hosts; only its access level and surrounding model types differ. Baseline row code restores the original flat-mask allocation statements. Real AppKit/TGUIKit views and layers perform the work. The fixture supplies precomputed panels and bubble geometry. Panel construction, bubble-mask composition and account lite-mode lookup are stubbed or outside timing; it does not build a complete Telegram row.

## Validation scope

Seven functional tests compare exact flat-panel raster pixels, material-mask image pixels, geometry, corner clipping, native-mask replacement/mutation, resizing, blur-mode changes, panel-count changes, mask reuse/removal, and attached-window animation behavior. Lifecycle checks distinguish immediate detachment from release after Core Animation transactions drain. The initial test run incorrectly required deallocation before that drain; its log is retained. The corrected test verifies both cleared image contents and eventual release. A subsequent non-vacuous raster check exposed that unattached AppKit views produced empty images. The final renderer attaches each row host to a real window before display and verifies that the masked panel has visible pixels and that removing its mask increases visible coverage. Earlier unattached comparisons are not used as pixel-parity evidence. Both failure logs are retained.

Timing uses nine paired batches and a second process with reversed starting order. Core Animation transactions are committed and flushed between batches, outside the measured region. Attached-window cases include `layoutSubtreeIfNeeded`; windows are not presented. These are CPU construction/update/layout measurements, excluding frame presentation, blur rendering, the rest of the chat row and whole-app scrolling FPS. Retained-object counts cover only the explicit overlay and mask CALayer objects; they exclude Core Animation's internal storage, backing surfaces and total process memory.

## Measurements

Release medians in microseconds per operation. Positive percentages mean less time. Panel cases update three panels; the number identifies how many have a silhouette.

| Workload | Forward order | Reversed order |
| --- | ---: | ---: |
| construct_unmasked | 8.102 → 8.079 (+0.3%) | 7.875 → 7.754 (+1.5%) |
| construct_masked | 9.554 → 9.704 (-1.6%) | 9.512 → 9.499 (+0.1%) |
| panels_blur_0_masks | 2.075 → 0.831 (+59.9%) | 1.983 → 0.820 (+58.7%) |
| panels_blur_1_masks | 2.792 → 1.983 (+29.0%) | 2.714 → 2.024 (+25.4%) |
| panels_flat_1_masks | 0.845 → 0.535 (+36.7%) | 0.856 → 0.548 (+35.9%) |
| panels_flat_3_masks | 1.593 → 0.698 (+56.2%) | 1.566 → 0.690 (+55.9%) |
| attached_panels_blur_1_mask | 3.554 → 2.703 (+23.9%) | 3.461 → 2.648 (+23.5%) |
| attached_panels_flat_1_mask | 1.541 → 1.078 (+30.1%) | 1.521 → 1.032 (+32.2%) |
| toggle_mask | 1.230 → 1.414 (-15.0%) | 1.234 → 1.413 (-14.5%) |

Attached-window updates with one masked panel use 23–24% less CPU time in blur mode and 30–32% less in flat mode. These are microsecond-level improvements to panel layout, not complete-row or scrolling speedups. Ordinary view construction is approximately unchanged. The unchanged zero-mask flat path varies from 0.6% to 6% slower, at most 0.027 microseconds per operation; three masked blur panels vary from unchanged to 2.1% slower.

Toggling a mask off and immediately on costs about 0.18 microseconds more (14–15%), because clearing releases the layer and the next assignment creates another. This trades a small transition cost for releasing unused layer storage. Repeated non-empty assignments reuse the active layer.

For 1,000 retained unmasked effects, explicitly owned CALayer objects fall from 2,000 to 1,000. Their measured Objective-C object allocations total 64,000 versus 32,000 bytes. Both view instances occupy 768 bytes. This does not count Core Animation's private storage or app-wide memory and is not a 50% reduction in view or process memory.

## Final regression results

Release and Address Sanitizer each pass all seven final functional tests, with the optional benchmark skipped. Address Sanitizer disables leak detection. The frozen TGUIKit suite passes 397 functional tests with 18 optional measurements skipped; the chat/folding-text suite, including the actual asset-loader test, passes 337 with 33 optional measurements skipped. Both changed production files pass Swift syntax parsing.

The final generator reproduces both complete library source trees and all final test sources. All 1,072 recorded compiler inputs remain unchanged. Benchmark code and production sources are identical between timing and final validation; only the raster test setup was strengthened afterward. Complete logs, raw paired timings, generated row-host snapshots, source hashes and failure records are retained in results/. Unrelated profile-menu edits in ChatRowView are outside this change. The complete app has not been built or profiled by this lab.
