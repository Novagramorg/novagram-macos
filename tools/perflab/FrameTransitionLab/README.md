# Immediate frame update checks

`ContainedViewLayoutTransition.updateFrame(view:frame:completion:)` now checks the model frame first for immediate transitions. A matching frame completes without querying pending layer animations. Changed frames still check the animation endpoint before writing. Animated transitions retain the original endpoint guard and animation implementation. No stored state, cache or public API is added.

The original shared guard queried two layer animations, layer geometry and anchor position even when the immediate branch would subsequently find the view's frame unchanged. A counting-layer test proves two animation lookups become zero, with no frame write and exactly one successful completion.

## Reproduce

```sh
python3 tools/perflab/FrameTransitionLab/prepare-isolated.py /tmp/FrameTransitionValidation
swift test --package-path /tmp/FrameTransitionValidation --scratch-path /tmp/FrameTransitionValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/FrameTransitionValidation --scratch-path /tmp/FrameTransitionValidation-asan --sanitize address
FRAME_BENCHMARK=1 swift test --package-path /tmp/FrameTransitionValidation --scratch-path /tmp/FrameTransitionValidation-build -c release --skip-build --filter FrameBenchmarkTests
cp /tmp/frame-transition-benchmark.json /tmp/frame-forward.json
FRAME_BENCHMARK=1 FRAME_REVERSE=1 swift test --package-path /tmp/FrameTransitionValidation --scratch-path /tmp/FrameTransitionValidation-build -c release --skip-build --filter FrameBenchmarkTests
cp /tmp/frame-transition-benchmark.json /tmp/frame-reverse.json
```

Use a fresh output directory and run timing without competing builds. The repository directory is a generator template. Two complete TGUIKit copies differ only in `ContainableController.swift`; the baseline restores the captured original file. Calls use both public APIs from the same test module. The initial benchmark lacked the standalone theme images needed by TextView construction and trapped during theme initialization. Bootstrap now registers placeholder theme icons and sets the same scale for both modules. These icons are not part of the measured layout workload.

## Measurements

Release medians in microseconds per operation, with nine alternating paired batches and a second process reversing the initial order. Positive percentages mean less time.

| Workload | Forward order | Reversed order |
| --- | ---: | ---: |
| animated_same_frame | 0.066 → 0.070 (-6.7%) | 0.068 → 0.071 (-3.8%) |
| attached_16_controls_4_change | 4.479 → 4.112 (+8.2%) | 4.507 → 4.145 (+8.0%) |
| attached_16_controls_all_change_origin | 10.655 → 10.816 (-1.5%) | 10.660 → 10.820 (-1.5%) |
| attached_16_controls_all_change_size | 24.620 → 24.867 (-1.0%) | 24.687 → 24.912 (-0.9%) |
| attached_16_controls_same_frames | 1.934 → 1.409 (+27.1%) | 1.956 → 1.502 (+23.2%) |
| changing_frame | 0.713 → 0.723 (-1.4%) | 0.704 → 0.711 (-1.0%) |
| same_frame | 0.069 → 0.012 (+82.4%) | 0.067 → 0.012 (+82.9%) |
| same_frame_with_completion | 0.096 → 0.037 (+61.0%) | 0.097 → 0.039 (+60.0%) |
| same_model_frame_pending_animation | 0.122 → 0.012 (+90.3%) | 0.127 → 0.012 (+90.7%) |

The attached fixture contains twelve real Views and four real TextViews without text layouts. It includes `layoutSubtreeIfNeeded`, but not text measurement, drawing, frame presentation or complete chat-row work. Fully changing origin cases move all sixteen controls; size cases also change widths. `changing_frame` performs two single-view updates per operation. Core Animation transactions are committed/flushed between batches, outside timing.

Repeated sixteen-control layout uses 23–27% less CPU time; updating four controls while twelve stay fixed uses about 8% less. Fully changing layouts cost 0.9–1.5% more. Animated no-op calls cost about 3–4 nanoseconds more (3.8–6.7%). These tradeoffs accompany the reduction in redundant immediate-update work; this is not a universal speedup. Real-app frequencies of matching/changing frames and scrolling FPS have not been measured, and no retained-memory reduction is claimed.

## Functional coverage

Eight tests check unchanged/changed frames, layerless views, pending position/bounds animations with model/end/third destinations, animated endpoint and completion behavior, transformed/anchored views, attached windows, reentrant completions, real TGUIKit resize callbacks and native visual-effect views. They compare frame/bounds writes, callback order, animation keys, endpoints and durations. The optimization preserves pending animations on an immediate no-op, matching the original behavior.

## Final validation

The final release and Address Sanitizer runs each pass all eight functional tests and skip the opt-in benchmark. Address Sanitizer disables leak detection. The frozen TGUIKit suite passes 397 functional tests with 18 optional measurements skipped. The chat-layer/folding-text suite passes 337 with 33 optional measurements skipped, including the real icon-loader fixture. The changed production file passes Swift syntax parsing.

The generator reproduces both complete library source trees and all final test sources exactly. All 1,065 recorded compiler inputs remain unchanged after validation, and the production source matches the measured snapshot. Complete logs, raw batches, captured baseline/current source and input hashes are retained in results/. No full-app build, presented-frame measurement or retained-memory comparison was performed.
