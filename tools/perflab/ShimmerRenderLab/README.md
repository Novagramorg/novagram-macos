# Shimmer placeholder reuse and latest-result delivery

Transparent placeholders could not reuse their previous mask because the cache guard required a non-nil background color. Repeated updates rebuilt paths and images even when nothing changed. Async layer/view requests also discarded their disposable, allowing older results to overwrite newer masks. Existing masks retained their initial frame after resize. Image dimensions, corner radius and display scale were missing from the cache keys, and silhouette opacity keyframes retained their previous alpha values.

The change compares complete inputs, including optional colors, with named/dynamic colors resolved to component colors, updates mask frames and silhouette opacity animations, and disposes replaced async requests. Queue work uses an atomic cancellation flag; the shared runOn(Queue) helper captures an unsynchronized Boolean, so these local render jobs do not use it. Already-running rasterization can finish, but disposed subscribers do not publish obsolete results. The telegram-ios submodule is unchanged.

This affects placeholders used by chat stickers, inline custom emoji, chat accessory text and peer-info content. It preserves the drawing primitives and adds no global image cache. The existing foreground gradient cache and animation lifecycle are separate follow-up candidates.

## Reproduce

```sh
python3 tools/perflab/ShimmerRenderLab/prepare-isolated.py /tmp/ShimmerValidation
swift test --package-path /tmp/ShimmerValidation --scratch-path /tmp/ShimmerValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/ShimmerValidation --scratch-path /tmp/ShimmerValidation-asan --sanitize address --filter ShimmerTests.ShimmerTests
swift test --package-path /tmp/ShimmerValidation --scratch-path /tmp/ShimmerValidation-tsan --sanitize thread --filter ShimmerTests.testCandidateRapidRequestsPublishTheLatestMask
python3 tools/perflab/ShimmerRenderLab/prepare-isolated.py /tmp/ShimmerTiming --without-probe
swift test --package-path /tmp/ShimmerTiming --scratch-path /tmp/ShimmerTiming-build -c release --filter ShimmerBenchmarkTests
swift test --package-path /tmp/ShimmerTiming/TGUIKit --scratch-path /tmp/ShimmerTiming-kit -c release
SHIMMER_RENDER_BENCHMARK=1 swift test --package-path /tmp/ShimmerTiming --scratch-path /tmp/ShimmerTiming-build -c release --skip-build --filter ShimmerBenchmarkTests
cp /tmp/shimmer-render-benchmark.json /tmp/shimmer-forward.json
SHIMMER_RENDER_BENCHMARK=1 SHIMMER_RENDER_REVERSE=1 swift test --package-path /tmp/ShimmerTiming --scratch-path /tmp/ShimmerTiming-build -c release --skip-build --filter ShimmerBenchmarkTests
cp /tmp/shimmer-render-benchmark.json /tmp/shimmer-reverse.json
```

Build and measure sequentially with no competing compilers during timing. Each generator requires a new output directory. It freezes complete baseline and candidate TGUIKit modules and records source hashes. Shared dependencies remain at their recorded repository paths. Reference sources preserve the original and candidate revisions with SHA-256 guards.

The functional snapshot appends identical test-only image/mask inspectors and an image-generation hook to both modules. The hook gates out-of-order requests and counts rasterization. The timing snapshot omits the raster hook calls, so the eliminated baseline work is not inflated by counter/lock overhead. Its async contents observers drain delivery after timed submission loops; synchronous sticker updates have no observer. No inspectors or probes are added to production.

## Coverage and limits

Twelve focused tests cover 180 fresh nonblank bitmap pairs across four classes, three scales, two sizes, background modes and encoded paths; 48 changing-input pairs; and 30 rapid-request final-image pairs. Further checks cover 30-to-one repeated transparent rasterization, resized masks, changed image dimensions/corner radii, scale changes, deterministic out-of-order results across background modes, silhouette opacity values, dynamic background mask colors both with and without appearance changes, and owner release while rendering is pending.

The dynamic-color test validates the mask, not the unchanged foreground gradient implementation. The silhouette animation fixture attaches layers to a native window; an unattached layer does not reliably retain its animation. The owner-release fixture drains native transactions and its autorelease pool before asserting release. Initial fixture failures are retained under Experiments.

An early candidate resolved every color to CGColor on every call. It made already-cached updates unnecessarily expensive. The final candidate keeps immutable component colors directly and resolves named/dynamic colors; the initial measurements and source are retained under Experiments/color-resolution-overhead.

Release measurements use nine alternating paired batches and repeat in reverse initial order. Async results report main-thread update/submission cost, not end-to-end raster latency. Synchronous sticker measurements include image generation. Changed-input controls for all three async classes, synchronous changed-background updates and construction expose added work. Object instance and allocator sizes measure only each top-level object, not all child layers, transient allocations or process memory. Extra cache fields and retained disposables have a storage cost; reduced redundant work is not evidence of lower total retained app memory.

These fixtures use real TGUIKit, AppKit and Core Animation. They do not measure whole-app scrolling FPS, message-opening latency or the complete media pipeline.

## Final validation and results

All 12 focused release tests and all 12 focused Address Sanitizer tests pass. The candidate-only rapid-replacement test passes Thread Sanitizer; this is not a claim that the complete baseline or suite is race-free. The complete frozen TGUIKit suite passes 420 functional tests, with 18 optional measurements skipped. Leak detection is disabled for the Address Sanitizer run.

A fresh generator reproduces 521 Swift source files and three manifests after temporary-path normalization. All 1,228 recorded snapshot/dependency inputs and 259 production source/test files are verified unchanged. The two measured production files match the applied changes exactly. The path parser/renderer and foreground gradient implementation remain byte-identical to the originals. Other worktree changes are frozen identically in both modules. The baseline versions of the two changed files come from commit 95f414a59; reproducing the whole fixture also requires the recorded dependency/worktree inputs.

One attempted final benchmark overlapped an external build and was excluded; its output is retained under Experiments/competing-build. Neither accepted final run had matching swift-frontend, xcodebuild or clang processes in its pre/post checks. Measurements ran on arm64 macOS with Swift 6.3.3. See [all timing rows](results/medians.md) and the raw JSON batches for every control.

| Repeated transparent update | Baseline → candidate | Less time across both orders |
| --- | --- | ---: |
| Sticker view, rounded mask | 11.28–12.30 → 0.051–0.061 µs | 99.5% |
| Sticker view, detailed path | 152.77–211.95 → 0.048–0.065 µs | over 99.9% |
| Layer, rounded mask submission | 1.93–2.77 → 0.070–0.101 µs | 96.4% |
| Layer, detailed path submission | 1.77–1.93 → 0.104–0.107 µs | 94.0–94.6% |
| View, rounded mask submission | 2.68–2.78 → 0.082–0.088 µs | 96.8–96.9% |
| View, detailed path submission | 2.27 → 0.125–0.133 µs | 94.2–94.5% |

These are unchanged-input updates to an existing placeholder, not complete image loading, row construction or scrolling. The synchronous detailed path contains 60 encoded commands. In the functional counter fixture, 30 identical transparent updates generate 30 baseline masks versus one candidate mask. In each final timing order, repeated async transparent cases deliver 2,700 baseline images versus zero candidate replacements after the initial mask.

Already-cached opaque and silhouette updates become 0.019–0.102 µs slower due to the more complete input checks. Changed layer updates range from 0.3–9.7% less submission time, and changed view updates from 3.5–18.5% less; these variable results are not the headline. Changed silhouette updates range from 3.8% slower (+0.41 µs) to 6.6% faster. Changed synchronous sticker backgrounds range from 1.7% faster to 3.8% slower (+0.25 µs). Sticker construction ranges from 0.6% faster to 0.2% slower (+0.16 µs).

| Top-level object | Runtime bytes, baseline → candidate | Allocator bytes, baseline → candidate |
| --- | ---: | ---: |
| ShimmerLayer | 184 → 240 | 192 → 256 |
| ShimmerView | 1,000 → 1,056 | 1,024 → 1,280 |
| StickerShimmerEffectView | 1,000 → 1,008 | 1,024 → 1,024 |
| SilhouetteShimmerLayer | 152 → 176 | 160 → 192 |

The additional fields support correct cache invalidation and request ownership. These figures exclude child layers, retained subscriptions and transient rendering allocations. No reduction in total retained app memory is claimed. The full Telegram app was not built, and full-app FPS was not measured.
