# Audio waveform preparation lab

Release, Address Sanitizer and Thread Sanitizer each pass eight functional tests, with two opt-in tests skipped. Address Sanitizer leak detection is disabled. Both release timing orders are recorded below.

The production waveform renderer previously scanned source samples twice and allocated a temporary bucket array independently for each of its two layers on every draw. The candidate prepares immutable bucket peaks and normalization once, shares them between those layers, and retains them until the waveform identity or bucket count changes. Reveal animation, color changes and geometry within one bucket count reuse the preparation. The original source-to-bucket mapping and floating-point drawing order remain unchanged. The public view, clipping view and animation API remain unchanged.

A nonempty waveform rendered at width below four points previously computed zero buckets and accessed the zero-length temporary allocation. The candidate returns without drawing waveform bars at these widths. Nil waveforms retain their original placeholder rendering. The separate original-code reproducer reports an Address Sanitizer heap-buffer-overflow.

Attached-window coverage also exposed stale rendered contents after resizing: the original waveform layers did not invalidate on bounds changes. Both layer initializers now enable bounds-change display invalidation. The failing-first run had twelve resize/clipping assertions; the fixed run matches fresh original rendering at valid widths and clears old contents below four points.

The lab generates two independent modules from the captured original and current production files. It includes the entire waveform model and the complete waveform view implementation, stopping before the unrelated sparks renderer. Both variants link the real TGUIKit. Test-only extensions expose drawing and immutable preparation state; they do not replace the renderer, animation curve, layers or view implementations. Reference hashes are checked during generation. The baseline capture includes pending repository state and is recorded by content hash rather than assumed identical to a particular commit.

The tests compare exact RGBA bytes for both layers over nil/empty/odd-length/random/zero/extreme source data, bucket boundaries, multiple scales, colors and reveal fractions. The exact-pixel matrix contains 3,240 comparisons. Tests also check independent original bucket mapping, shared storage reuse, replacement/nil/resize invalidation, inline and heap-backed source-data value semantics, nonempty narrow inputs, animation restart prevention, and attached-window resize/clipping/detach/reentry behavior. A separate opt-in baseline crash test exists for Address Sanitizer; never enable it for the passing suite.

The benchmark measures both production layers drawing into an already allocated bitmap context, and separate complete view construction with or without drawing. It includes 100-source-sample typical fixtures and 1,000-source-sample exploratory fixtures at 40/200 points. Each workload has nine alternating batches, with an optional reversed starting order in a fresh process. Drawing includes Core Graphics rasterization but excludes window presentation and GPU composition. Normal playback progress changes the existing clipping view rather than redrawing the waveform, so this workload does not establish faster ordinary playback ticks or full-chat scrolling.

Preparation retains one UInt16 per displayed bar plus small metadata per waveform view. The benchmark includes a construction-only control to reveal that retention/allocation tradeoff. There is no global waveform cache.

## Measured costs

Nine alternating batches per variant were repeated in a fresh process with reversed initial order. Each batch performs 300 operations. The redraw measurements invoke both actual waveform painters; layouts, sample data and bitmap allocation precede timing.

| Reveal redraw, both layers | Original µs | Current µs | Less time |
| --- | ---: | ---: | ---: |
| 100 samples, 40 pt | 26.06–26.43 | 25.10–25.64 | 1.6–5.0% |
| 100 samples, 200 pt | 99.21–104.62 | 98.62–104.14 | 0.5–0.6% |
| 1,000 samples, 40 pt | 28.12–28.18 | 24.70–25.47 | 9.6–12.2% |
| 1,000 samples, 200 pt | 122.87–129.09 | 118.22–127.25 | 1.4–3.8% |

The 100-sample fixtures show a modest benefit; rasterization dominates. Construction-only controls range from 0.5% faster to 6.1% slower, with a largest observed increase of 0.99 µs. Construction plus first drawing is mixed for typical inputs: 0.7–1.5% slower at 40 pt and between 0.3% slower and 1.6% faster at 200 pt. The larger sample arrays benefit more from avoiding repeated preparation. The cache retains one UInt16 per displayed bar plus an object/array header; it does not establish lower retained memory. These tradeoffs are included in the full 16-workload report.

All 415 frozen compiler inputs remained unchanged. Raw samples, medians and empty compiler checks before/after both processes are in `results/timing/`; full sanitizer logs, original heap-overflow output, failing resize assertions, source hashes and frozen fixture sources are in `results/validation/`. Compiler checks were not continuous monitoring. Separate agents authored source/tests during timing, without running builds or measurements. The full app was not built or manually tested in this pass.

## Commands

Run sequentially, with timing only after all compilation and other benchmarks finish:

```sh
python3 tools/perflab/AudioWaveformLab/prepare.py
swift test -c release --package-path tools/perflab/AudioWaveformLab --scratch-path /tmp/AudioWaveformLab-release
ASAN_OPTIONS=detect_leaks=0 swift test --sanitize address --package-path tools/perflab/AudioWaveformLab --scratch-path /tmp/AudioWaveformLab-asan
swift test --sanitize thread --package-path tools/perflab/AudioWaveformLab --scratch-path /tmp/AudioWaveformLab-tsan
WAVEFORM_BENCHMARK=1 WAVEFORM_BENCHMARK_OUTPUT=/tmp/audio-waveform-forward.json swift test -c release --skip-build --package-path tools/perflab/AudioWaveformLab --scratch-path /tmp/AudioWaveformLab-release --filter WaveformBenchmarkTests
WAVEFORM_BENCHMARK=1 WAVEFORM_REVERSE=1 WAVEFORM_BENCHMARK_OUTPUT=/tmp/audio-waveform-reverse.json swift test -c release --skip-build --package-path tools/perflab/AudioWaveformLab --scratch-path /tmp/AudioWaveformLab-release --filter WaveformBenchmarkTests
```

The following command is expected to fail under Address Sanitizer and must run separately:

```sh
ASAN_OPTIONS=detect_leaks=0 WAVEFORM_REPRODUCE_ORIGINAL_CRASH=1 swift test --skip-build --sanitize address --package-path tools/perflab/AudioWaveformLab --scratch-path /tmp/AudioWaveformLab-asan --filter WaveformTests.testOriginalNarrowWidthReproducer
```
