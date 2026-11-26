# Correct and cheaper alpha-aware image classification

Instant View's `instantPageImageFile` calls `imageRequiresInversion` to decide whether an image should be tinted to the supplied text color. The old code rendered a sample, created a CGImage wrapper, copied it into a vImage histogram buffer, unpremultiplied channels, allocated four histograms and constructed an NSColor for every pixel before checking saturation and brightness.

Two bugs affected that decision. The histogram chose an alpha index from alphaInfo without accounting for byte order; the default BGRA buffer was inspected as if its first byte were alpha. The pixel-to-NSColor initializer also discarded alpha and treated premultiplied RGB as opaque RGB. As a result, opaque black images, entirely transparent images, and sparse white or colored subjects on transparent padding could be marked for tinting. The tests reproduce these original failures and check corrected output through the real tint function.

The new code renders once into a known 8-bit device-RGB BGRA bitmap. Core Graphics still applies source color conversion, masks and decode arrays. An alpha-only scan rejects opaque samples early. The remaining scan ignores fully transparent pixels and classifies visible pixels directly from premultiplied channels. With maximum channel M, minimum channel m and alpha A, brightness below 0.25 is `4*M < A`; saturation below 0.1 is `10*(M-m) < M`, with black handled separately. These integer comparisons preserve strict mathematical thresholds without per-pixel color objects or floating-point division. The final visible-pixel ratio still must exceed 0.85.

The canonical format is independent of installed drawing-buffer settings. Allocation/size failures return false, row stride is respected, and the CGContext stays alive throughout pointer access. The existing sampling policy is preserved exactly: downscale with aspect fill only when both source dimensions exceed 128. This pass does not introduce a different sampling resolution or a retained cache.

The unused-in-production internal `imageHasTransparency` helper now uses the same canonical format and an alpha-only scan. Both functions retain the original exclusions for formats other than supported 8-bit/32-bit alpha images. The old histogram implementation is removed entirely, including its temporary array-pointer conversions.

## Reproduce

```sh
python3 tools/perflab/ImageAnalysisLab/prepare-isolated.py /tmp/ImageAnalysisValidation
swift test --package-path /tmp/ImageAnalysisValidation --scratch-path /tmp/ImageAnalysisValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/ImageAnalysisValidation --scratch-path /tmp/ImageAnalysisValidation-asan --sanitize address
swift test --package-path /tmp/ImageAnalysisValidation --scratch-path /tmp/ImageAnalysisValidation-tsan --sanitize thread
swift test --package-path /tmp/ImageAnalysisValidation/TGUIKit --scratch-path /tmp/ImageAnalysisValidation-kit -c release
IMAGE_ANALYSIS_BENCHMARK=1 swift test --package-path /tmp/ImageAnalysisValidation --scratch-path /tmp/ImageAnalysisValidation-build -c release --skip-build --filter AnalysisBenchmarkTests
cp /tmp/image-analysis-benchmark.json /tmp/image-forward.json
IMAGE_ANALYSIS_BENCHMARK=1 IMAGE_ANALYSIS_REVERSE=1 swift test --package-path /tmp/ImageAnalysisValidation --scratch-path /tmp/ImageAnalysisValidation-build -c release --skip-build --filter AnalysisBenchmarkTests
cp /tmp/image-analysis-benchmark.json /tmp/image-reverse.json
```

Use fresh output directories and time without competing builds. The generator freezes complete original and candidate TGUIKit libraries; ImageTransparency.swift is their only production-source difference. Test-only inspection wrappers expose the actual sampling-context dimensions. They are not shipped in the app. The telegram-ios implementation was read for context but is not modified.

## Measurements

The [full median table](results/medians.md) contains microseconds per call and the original/candidate decisions. Nine alternating paired batches are repeated in a fresh process with reversed initial order. Images are constructed outside timing. Each batch performs 128 calls, or 32 for the wide image. Both final runs had no matching compiler processes in their pre/post checks.

For the 128-pixel dark-logo fixture, the decision remains true and analysis falls from 431–458 µs to 14–16 µs, about 96.6–96.7% less time. White and colored 128-pixel logo fixtures with enough visible content to avoid the original bug also retain their decisions and use about 96.5–96.7% less time. A 512-pixel source sampled down to 128 uses about 96.7% less. The 2048×32 wide fixture retains the existing sampling dimensions and falls from 1.64–1.74 ms to 46–49 µs, about 97.2% less.

The 32-pixel inversion case improves by about 86%. Opaque white analysis improves by 71–73%. Empty and opaque-black fixtures now return false, correcting the original decision; their timings are recorded separately with that behavior change visible in the table.

Alpha-only analysis generally improves at 128 pixels and above, but the 32-pixel alpha-only case is 52–60% slower: 2.3–2.4 µs becomes 3.5–3.9 µs. The canonical Core Graphics draw costs more than the old histogram setup at that tiny size. This helper currently has no production caller in the repository; the used inversion path still improves at that size.

The implementation removes the explicit vImage scratch bitmap, histogram arrays, intermediate generated-image wrapper and per-pixel NSColor construction calls from inversion analysis. It retains one canonical sample bitmap and adds no persistent state. This is a code/resource-path reduction, not a measured total-process memory percentage. Complete image decoding, full Instant View rendering, GPU frame presentation and chat scrolling FPS were not measured. These component speedups are not whole-app speedups.

## Validation

Eleven focused tests pass in release, Address Sanitizer and Thread Sanitizer. Leak detection is disabled for Address Sanitizer. Coverage includes:

- Eight source layouts: premultiplied and straight RGBA, ARGB, BGRA and ABGR, including padded source rows.
- Opaque, empty, dark, white, colored and partially transparent artwork; exact 85% visible-pixel decisions and strict saturation/brightness boundaries.
- Reproduction of the old opaque-black, empty-image and sparse-white errors.
- Actual tint output: dark artwork still produces the same tinted pixels, while white/red artwork keeps its source pixels and transparent border.
- Eight unchanged sampling geometries, including wide/tall images and dimensions immediately around the 128-pixel threshold.
- Classification independent of installed drawing format and color space.
- 512 deterministic randomized images across alpha distributions, eight source layouts and device RGB/sRGB/Display P3.
- 400 concurrent classifications, masked images, decode arrays and excluded grayscale/opaque/16-bit source formats.

Two production-target tests cover the corrected tint decisions. The full frozen TGUIKit suite passes 417 functional tests, with 18 optional measurements skipped. All 673 recorded source/dependency inputs remain unchanged after validation, and the measured production source matches the worktree. A fresh generator run reproduces 520 Swift sources and all three package manifests after output-path normalization. Logs, raw batches, reference/final source snapshots and input hashes are retained in `results`. No full Telegram build was performed.

The first prototype combined alpha and color scanning. The final implementation checks alpha first so opaque samples skip color analysis. Its earlier source and probe logs are retained under `results/experiments`. Archived logs normalize trailing whitespace.
