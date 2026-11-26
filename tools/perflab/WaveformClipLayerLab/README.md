# Waveform clipping layer lab

The frozen candidate passes 15 functional tests in release, Address Sanitizer and Thread Sanitizer, with two optional measurements skipped and no failures. Address Sanitizer leak detection is disabled. The two timing orders and four allocation processes are recorded below. The later ownership-count correction changes only test/benchmark bookkeeping; its focused release test also passes, checking four owned layers before and after attachment and release after an active animation.

The candidate replaces the decorative `AudioWaveformView.foregroundClipingView` child NSView with a private `SimpleLayer`. The foreground and background painters, their shared sample cache, reveal animation and parent view remain. Seven production clipping updates across `ChatVoiceContentView` and `SingleTimeMediaViewer` call `updateForegroundClip(size:animated:)`. The native child was an ignored accessibility element with ordinary responder forwarding; the parent waveform keeps that forwarding role and remains the coordinate reference for seeking.

The clipping layer remains anchored at the origin and clips the full-size foreground painter without resizing it. Layout updates the painters but does not reset clipping progress. Animated updates use presentation bounds when retargeting an active bounds animation, preserving the existing 0.2-second ease-out behavior. Immediate updates cancel the bounds animation even when its model destination already equals the requested size. The previous view helper returned before cancellation in that case; the new test records both behaviors. Retargeting exactly to the current presentation bounds also cancels the old animation: the generic animation helper otherwise short-circuits equal endpoints and leaves the previous animation active. Negative clipping sizes clamp to zero, including timer progress that briefly runs beyond the disappearing waveform's endpoint.

## Baseline and fixture

`Reference/AudioWaveformView.swift.txt` is the immediate pre-change production source, including the already-completed sample-cache and bounds-display-invalidation improvements. Its hash and the waveform model hash are recorded in `Reference/hashes.json`. This baseline isolates the view removal; it does not attribute earlier painter optimizations to this change.

The generator compiles the full current and captured waveform model/view into separate modules linked to actual TGUIKit. It stops before the unrelated sparks implementation. Test-only extensions expose the real drawing layers, clipping layer, reveal progress and cache state; they do not substitute painting, animations, NSView behavior or Core Animation. `prepare-isolated.py` copies the TGUIKit sources/tests into a fresh temporary directory and records hashes. TGUIKit's small local dependencies still resolve to repository paths; root validation must capture and verify those compiler inputs as well.

The eight existing functional waveform tests are retained in this lab, including their 3,240 individual-painter exact bitmap comparisons. The historical narrow-width crash reproducer is intentionally absent here because this baseline already contains that fix. The older `AudioWaveformLab` keeps its reference and historical results; its current clipping calls are adapted to the new API so its original eight tests remain usable after generation.

Seven additional tests cover:

- 324 exact full-composite bitmap comparisons over nil/empty/normal data, narrow/fractional widths, differing heights, zero/partial/full/overflow clipping, three reveal fractions and three backing scales. Short clipping heights exercise vertical coordinate parity rather than only symmetric full-height waveforms.
- Parent resize without resetting clipping, unchanged full-width foreground geometry, and negative-size behavior.
- Animation endpoints, timing parameters, repeated targets and immediate cancellation at both equal and different destinations, including the baseline's same-target cancellation failure.
- Real attached presentation-layer retargeting from a paused intermediate animation, followed by resize, removal, reattachment and completion.
- Retargeting exactly to a paused presentation size, preserving that visible target and cancelling the stale animation endpoint; the captured baseline retains the old animation.
- Native hit testing and forwarded left/right/drag/scroll events in played and unplayed regions, zero/full progress, dragging outside the waveform, coordinate conversion, ignored accessibility state and first-click acceptance.
- Ownership/order, removal of the child NSView and release of the waveform, clip, painter and sample object after an active animation.

The initial release run exposed two fixture issues: hit testing passed parent-local coordinates to an API expecting superview coordinates, and an unattached resize comparison did not update AppKit's child backing-layer geometry. The corrected event test uses superview coordinates and still asserts that the hit is inside the waveform before forwarding events. The resize test attaches both variants to a real window and compares each reused view with an independently constructed fresh native waveform, retaining exact pixel equality. The corrected release and sanitizer suites pass all 3,240 individual-painter pairs, 324 composite pairs and the additional fresh/reused resize checks. Both interrupted-animation regressions pass.

The event fixture checks actual AppKit responder forwarding into a parent spy. It does not replace the complete chat row or invoke the real audio player, so interactive seek/playback remains an integration gate. Composite rendering uses Core Animation's software layer rendering. The attached presentation test checks animation state and completion; it is not a GPU frame-by-frame movie comparison. The exact production waveform model/view also passed a separate type check against compiled production dependency APIs; the full app has not been built or interactively validated in this pass.

## Measurements

Both optional tests skip by default. The timing test defines 12 cases: two widths each for construction, configured construction, unchanged immediate clipping, changing immediate clipping, explicit animated retargeting and attached resize/layout. Every case uses 20 warmup operations and nine batches alternating variant order. Construction batches contain 300 operations; unchanged updates 2,000; changing/animated updates 1,000; attached layouts 500. A second fresh process reverses the initial order. Waveform data exists before timing and is independently owned by the two variants.

Only the resize/layout case is attached to a window. Animated timing measures model changes and animation setup on an unattached view, not presentation or frame delivery. Rasterization, audio/media work, the complete chat row, table scrolling and opening latency are outside these measurements. The plain `View` being removed already avoids allocating a bitmap backing store, so view-count reduction must not be reported as saved waveform bitmap memory. Structural change is two views to one per waveform, while both implementations retain four model layers.

The separate allocation probe retains 2,000 initialized, laid-out waveforms in a fresh process after warming both implementations. Each variant shares one independent waveform-data object across its rows. It records task physical footprint/resident bytes and view/layer counts. It is unattached and unrasterized, includes allocator/framework storage, and does not measure full-app memory. The recorded process order is original/current/current/original.

The archived JSON's `layers` and `layers_100`/`layers_200` fields traverse only the connected root layer subtree. Before attachment, the baseline's clipping NSView retains its backing layer and foreground painter separately, so this counter reports two baseline layers versus four candidate layers. It does not measure all owned layers. The raw samples remain unchanged. The corrected benchmark calls this field `connected_root_layers` and adds `owned_layers`, traversing every NSView backing layer plus its descendants with identity deduplication. The functional ownership test now asserts four layers in both variants before and after attachment; those additional assertions postdate the recorded suite and passed in a separate focused release run (`results/validation/ownership-count-release.log.gz`). The allocation readings precede the counting code and include the separately retained layers, so the counter issue does not invalidate the footprint measurements.

## Recorded results

Medians are microseconds per operation; ranges cover both widths and both initial orders. Full per-workload values are in [results/timing/medians.md](results/timing/medians.md), with raw batches and computed values in the adjacent JSON files.

| Workload | Original → current | Observed change |
| --- | ---: | ---: |
| Construction | 11.46–11.99 → 6.27–6.70 µs | 44.1–45.3% less time |
| Configured construction | 12.43–12.69 → 6.74–6.87 µs | 45.5–46.5% less time |
| Changing immediate clipping | 0.452–0.474 → 0.147–0.155 µs | 67.2–68.4% less time |
| Animated retarget setup | 1.67–1.78 → 1.04–1.11 µs | 37.0–38.2% less time |
| Attached resize/layout | 1.95–2.02 → 1.93–2.00 µs | 0.5–2.9% less time |
| Unchanged immediate clipping | 0.019–0.021 → 0.024–0.025 µs | Adds 0.003–0.006 µs |

Construction and changing progress show consistent improvements in both orders. Attached layout is close. The unchanged-input regression remains in the report: the new API must cancel active animation even at an unchanged model size, whereas the old view helper exits immediately. These measurements concern this component's CPU work and do not establish playback or scrolling frame-rate gains.

For 2,000 retained waveforms, physical-footprint increases are 12.75–12.78 MiB in the original processes and 7.5625 MiB in both candidate processes. Paired differences are 5.19–5.22 MiB, or 40.7–40.8% of this fixture's incremental allocation. That corresponds to approximately 2.66–2.67 KiB per waveform in these runs, including allocator/framework effects. Recorded view counts are 4,000 original versus 2,000 candidate. These are allocation-fixture results, not whole-app memory savings; neither variant has drawn or created waveform bitmap contents in this probe.

All six process logs report passing optional tests. Compiler checks before and after every process found no `swift-frontend`, `xcodebuild` or `clang`; they are boundary checks, not continuous monitoring. All 418 frozen compiler inputs were reverified during archiving. `results/timing/archive-manifest.json` records the original paths and hashes of the unchanged raw JSON, logs, compiler checks and runner script. The later count correction changes only the two test files; it is not part of the measured snapshot. Do not replace these samples with revised count fields or infer a layer-allocation increase from the old root-only count.

## Reproduction

Run preparation, builds and measurements sequentially, after other benchmark/compilation work has stopped. Use a fresh output directory. Preparation generates only the isolated fixture; no generated Swift files need to be committed in this lab.

```sh
python3 tools/perflab/WaveformClipLayerLab/prepare-isolated.py /tmp/WaveformClipCheck
swift test --package-path /tmp/WaveformClipCheck --scratch-path /tmp/WaveformClipCheck-release -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/WaveformClipCheck --scratch-path /tmp/WaveformClipCheck-asan --sanitize address
swift test --package-path /tmp/WaveformClipCheck --scratch-path /tmp/WaveformClipCheck-tsan --sanitize thread
WAVEFORM_CLIP_BENCHMARK=1 WAVEFORM_CLIP_OUTPUT=/tmp/waveform-clip-forward.json swift test --package-path /tmp/WaveformClipCheck --scratch-path /tmp/WaveformClipCheck-release -c release --skip-build --filter ClipLayerBenchmarkTests.testConstructionProgressAndLayoutCosts
WAVEFORM_CLIP_BENCHMARK=1 WAVEFORM_CLIP_REVERSE=1 WAVEFORM_CLIP_OUTPUT=/tmp/waveform-clip-reverse.json swift test --package-path /tmp/WaveformClipCheck --scratch-path /tmp/WaveformClipCheck-release -c release --skip-build --filter ClipLayerBenchmarkTests.testConstructionProgressAndLayoutCosts
WAVEFORM_CLIP_MEMORY=original WAVEFORM_CLIP_OUTPUT=/tmp/waveform-clip-original-1.json swift test --package-path /tmp/WaveformClipCheck --scratch-path /tmp/WaveformClipCheck-release -c release --skip-build --filter ClipLayerBenchmarkTests.testRetainedWaveformAllocationFootprint
WAVEFORM_CLIP_MEMORY=current WAVEFORM_CLIP_OUTPUT=/tmp/waveform-clip-current-1.json swift test --package-path /tmp/WaveformClipCheck --scratch-path /tmp/WaveformClipCheck-release -c release --skip-build --filter ClipLayerBenchmarkTests.testRetainedWaveformAllocationFootprint
WAVEFORM_CLIP_MEMORY=current WAVEFORM_CLIP_OUTPUT=/tmp/waveform-clip-current-2.json swift test --package-path /tmp/WaveformClipCheck --scratch-path /tmp/WaveformClipCheck-release -c release --skip-build --filter ClipLayerBenchmarkTests.testRetainedWaveformAllocationFootprint
WAVEFORM_CLIP_MEMORY=original WAVEFORM_CLIP_OUTPUT=/tmp/waveform-clip-original-2.json swift test --package-path /tmp/WaveformClipCheck --scratch-path /tmp/WaveformClipCheck-release -c release --skip-build --filter ClipLayerBenchmarkTests.testRetainedWaveformAllocationFootprint
```

Archive exact compiler input hashes, logs, raw JSON, generated fixture sources and compiler checks before/after each timing process. Do not claim completed validation from this authored fixture or from the earlier waveform-cache results.
