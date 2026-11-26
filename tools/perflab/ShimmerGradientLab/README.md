# Bounded sharing of shimmer gradients

The layer-based foreground cached every gradient indefinitely, using NSColor keys compared after conversion to 8-bit ARGB and hashed through formatted color strings. Distinct colors could alias, and changing a named/dynamic color could invalidate the dictionary key's meaning. The view-based foreground regenerated its gradient for each new view and on duration changes.

Both foreground implementations now use one cache keyed by exact CGColors, gradient color space, dimensions and direction. They resolve named/dynamic colors before checking their previous input. This fixes stale gradients when a dynamic color changes and prevents sub-byte color changes from returning an unrelated cached image. The drawing operations, geometry and animation code keep their existing behavior.

The cache has 32 weak entries and retains at most three recent images within a 64 KiB pixel budget. Oversized images can be shared while another owner retains them, but do not enter the recent-image set. The recent set can hold keys no longer present in the weak index; metadata remains bounded by those two limits. A lock protects cache state, rendering happens outside the lock, and a second lookup reconciles concurrent generation. Cache entries are invalidated when the installed bitmap settings change. No fields are added to foreground-layer or foreground-view instances, and no public package API is added.

This is used by sticker placeholders, inline emoji, chat-list and news placeholders, peer-info loading content, and shimmer buttons in chat, wallet and premium screens. Bitmap reuse does not eliminate the per-view masks, child layers or other UI objects.

## Reproduce

```sh
python3 tools/perflab/ShimmerGradientLab/prepare-isolated.py /tmp/GradientValidation
swift test --package-path /tmp/GradientValidation --scratch-path /tmp/GradientValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/GradientValidation --scratch-path /tmp/GradientValidation-asan --sanitize address --filter GradientTests.GradientTests
swift test --package-path /tmp/GradientValidation --scratch-path /tmp/GradientValidation-tsan --sanitize thread --filter GradientTests.GradientTests
swift test --package-path /tmp/GradientValidation/TGUIKit --scratch-path /tmp/GradientValidation-kit -c release
SHIMMER_GRADIENT_BENCHMARK=1 swift test --package-path /tmp/GradientValidation --scratch-path /tmp/GradientValidation-build -c release --skip-build --filter GradientBenchmarkTests
cp /tmp/shimmer-gradient-benchmark.json /tmp/gradient-forward.json
SHIMMER_GRADIENT_BENCHMARK=1 SHIMMER_GRADIENT_REVERSE=1 swift test --package-path /tmp/GradientValidation --scratch-path /tmp/GradientValidation-build -c release --skip-build --filter GradientBenchmarkTests
cp /tmp/shimmer-gradient-benchmark.json /tmp/gradient-reverse.json
python3 tools/perflab/ShimmerGradientLab/prepare-mask-regressions.py /tmp/GradientMaskRegression
swift test --package-path /tmp/GradientMaskRegression --scratch-path /tmp/GradientMaskRegression-build -c release
```

Use new output directories. Build and measure sequentially, with no competing compilers during timing. The generator freezes two complete TGUIKit modules and records hashes; only ShimmerLayer.swift and ShimmerEffect.swift differ. Baseline versions of those files come from commit 68117c309. Other worktree sources are copied identically to both modules. Shared dependency paths are recorded. Test-only inspectors expose images, animation state and cache counters; production contains no inspection API or raster probes.

The separate mask-regression generator restores the earlier mask baseline from ShimmerRenderLab and reruns its tests against the new production implementation. This retains the baseline bug reproductions rather than replacing them with assertions that merely mirror the new code.

## Coverage and fixture findings

Thirteen focused tests cover:

- 220 exact bitmap pairs across background/foreground colors, P3 inputs, both orientations, default/custom/fractional/zero lengths, and reused views.
- 100 bitmap pairs through eviction while other images remain live; duration-only updates reuse unchanged bitmap content.
- 512 concurrent requests across 16 keys, checking identity sharing and 16 reference bitmap pairs.
- Six bitmap/format comparisons through installed sRGB/P3/sRGB settings changes.
- Dynamic color changes without changing the NSColor object, plus sub-byte alpha changes that the old layer cache aliases.
- Square gradients with different directions; matching gradients shared across layer/view implementations.
- Frames, contents gravity, clipping and animation values through 12 layout transitions and detachment.
- Live view image sharing, native hosted-layer lifetimes, recent-entry eviction, oversized-image release, metadata bounds and mixed-size pixel-budget checks.

The dynamic-color reference must clear the old cache before rendering the expected new result: its mutable color keys can otherwise return a stale bitmap even to a fresh foreground layer. Initial unhosted-layer lifetime tests also observed native image references after the outer layer released. The final retained-storage comparison attaches and detaches through a real NSView/NSWindow; separate cache-only tests distinguish cache ownership from native ownership. Device-RGB fixture colors keep all 256 baseline colors distinct under its 8-bit comparison. Initial failing fixtures and their logs are retained under Experiments.

The first candidate used weak references only. It shared live bitmaps and released all cached pixel storage after native owners disappeared, but made layer recreation about 31.7 µs slower (6.7 → 38.4 µs). The bounded recent set addresses that measured regression. The rejected source, tests and timings remain under Experiments/weak-only.

## Measurement scope

Release timings use nine alternating paired batches and a separate reversed-order process. All native transactions and object releases occur outside the timed construction batches. Recreation cases explicitly verify that the previous owner released. They allow the cache's intended recent-image retention. Layer measurements include the identical test harness wrapper in both variants. Complete sticker-placeholder construction includes its real views, rounded or detailed path mask, and foreground gradient; the detailed path has 60 encoded commands.

Pixel storage is calculated from unique CGImage identities and bytesPerRow × height. This excludes cache metadata, NSColor/CGColor objects, image wrappers, GPU surfaces and total process memory. The 64 KiB limit applies to strongly retained gradient pixel buffers, not the whole cache allocation. Bitmap format changes invalidate shared cache entries; this change does not add settings tracking to existing foreground instances' unchanged-input guards.

The full Telegram app, chat-opening latency and scrolling FPS are outside these fixtures. Existing animation lifecycle and duration-change behavior are preserved and are separate potential follow-ups.

## Final results

All 13 focused release tests pass, as do all 13 under Address Sanitizer and Thread Sanitizer. The 12 earlier shimmer-mask regressions pass against the new implementation. The complete frozen TGUIKit suite passes 420 functional tests, with 18 optional measurements skipped. Address Sanitizer leak detection is disabled.

Fresh generators reproduce 521 Swift files and three manifests for both the gradient fixture and the separate mask-regression fixture after temporary-path normalization. All 1,778 recorded inputs and 259 production source/test files remain unchanged. The timing fixture adds full sticker-construction cases to the sanitizer fixture's benchmark file; production and functional-regression sources are identical. That earlier optional benchmark source is archived as well. The mask implementation and the foreground geometry/animation code are verified byte-identical to their respective original suffixes.

Both accepted final timing orders had no matching swift-frontend, xcodebuild or clang processes in their pre/post checks. Measurements ran on arm64 macOS with Apple Swift 6.3.3. The full table and all batches are in [results/medians.md](results/medians.md) and the JSON files.

| Workload | Baseline → candidate | Less time across both orders |
| --- | --- | ---: |
| Complete sticker placeholder, rounded mask | 79.0–84.7 → 49.4–53.0 µs | 37.3–37.5% |
| Complete sticker placeholder, detailed path | 223.2–229.0 → 194.0–197.1 µs | 13.1–13.9% |
| Shared foreground-layer construction | 6.73–7.10 → 1.85–2.00 µs | 71.9–72.5% |
| Shared foreground-view construction | 58.0–59.0 → 16.0–16.2 µs | 72.3–72.5% |
| Layer recreation after owner release | 6.26–6.83 → 2.51–2.70 µs | 60.0–60.4% |
| View recreation after owner release | 52.3–52.4 → 18.1–18.2 µs | 65.2–65.5% |
| Duration-only view updates | 39.7–40.4 → 0.76–0.78 µs | 98.1% |

Unique layer colors are 18.8–20.8% faster because the original string-based key was expensive. Unique view colors are 2.8–4.3% slower, adding 1.5–2.3 µs for cache lookup/maintenance alongside rasterization. Already-unchanged calls add approximately 0.008–0.014 µs for the named/dynamic-color check. These controls are retained rather than omitted from the results.

For 32 simultaneously retained matching foreground views, unique source-pixel storage falls from 655,360 bytes to 20,480 bytes (640 KiB → 20 KiB, 96.9% less). After 256 unique device-RGB layer gradients are hosted and detached, the original cache retains 5,242,880 bytes, while the candidate retains 61,440 bytes in its three recent images (5 MiB → 60 KiB, 98.8% less). This is a controlled cache-retention fixture, not a measurement of typical app savings. The global recent-image pixel limit is 65,536 bytes; weak entries do not retain their image buffers.

Foreground-layer runtime/allocator sizes remain 176/192 bytes, and foreground-view sizes remain 1,056/1,280 bytes in both modules. Cache metadata is additional bounded global storage. No total process-memory or whole-app FPS improvement is claimed, and the complete Telegram app was not built.
