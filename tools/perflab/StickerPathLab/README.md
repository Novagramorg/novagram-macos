# Sticker path parsing and drawing

Sticker loading placeholders decode compact thumbnail data into SVG-style path commands. The previous parser allocated a scalar array and a string for every number, collected all command arguments into an intermediate array, then copied each segment's arguments into another array. Drawing copied segment arrays and removed their prefixes to advance through commands.

The parser now scans the input's UTF-8 view once. All recognized commands, separators and numeric syntax are ASCII; continuation bytes cannot become commands. Integers with at most 15 digits are accumulated exactly in UInt64 and converted to Double, preserving negative zero. Other numeric forms use Swift's existing Double conversion on the original token. The parser preserves the existing grammar, including its handling of unsupported or malformed forms; it does not introduce a different decimal approximation.

Complete argument groups go directly into the output, reserving their final capacity. The renderer advances indices through immutable argument arrays. Its path operations, current-point behavior, curve reflection, per-`z` fill boundaries and unsupported commands remain unchanged. In particular, combining all subpaths into one fill could change blending and was not done.

Only PathDataReader.swift and the renderer portion of ShimmerLayer.swift change. There is no new cache, public API or dependency. The compact-data decoder is unchanged. The generator restores its recorded reference in both modules so later decoder changes do not alter this comparison. These paths serve StickerShimmerEffectView, ShimmerLayer, ShimmerView, SilhouetteShimmerLayer and generateStickerPlaceholderImage.

## Reproduce

```sh
python3 tools/perflab/StickerPathLab/prepare-isolated.py /tmp/StickerPathValidation
swift test --package-path /tmp/StickerPathValidation --scratch-path /tmp/StickerPathValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/StickerPathValidation --scratch-path /tmp/StickerPathValidation-asan --sanitize address --filter 'PathTests.(PathTests|ExtendedPathTests)'
swift test --package-path /tmp/StickerPathValidation --scratch-path /tmp/StickerPathValidation-tsan --sanitize thread --filter 'PathTests.(PathTests|ExtendedPathTests)'
swift test --package-path /tmp/StickerPathValidation/TGUIKit --scratch-path /tmp/StickerPathValidation-kit -c release
STICKER_PATH_BENCHMARK=1 swift test --package-path /tmp/StickerPathValidation --scratch-path /tmp/StickerPathValidation-build -c release --skip-build --filter PathBenchmarkTests
cp /tmp/sticker-path-benchmark.json /tmp/path-forward.json
STICKER_PATH_BENCHMARK=1 STICKER_PATH_REVERSE=1 swift test --package-path /tmp/StickerPathValidation --scratch-path /tmp/StickerPathValidation-build -c release --skip-build --filter PathBenchmarkTests
cp /tmp/sticker-path-benchmark.json /tmp/path-reverse.json
```

Use fresh output directories, run builds sequentially, and measure without competing compilers. The generator freezes two complete TGUIKit modules, differing only in the intended production files. Baselines come from commit 70200c4bc. Test-only properties expose placeholder images; they do not instrument parsing or drawing. Shared dependency paths and compiler inputs are recorded with the results. Source guards reject unrelated revisions of the two edited files.

`python3 tools/perflab/StickerPathLab/prepare-standalone.py /tmp/StickerPathQuick` creates the smaller exploratory package from `Standalone`, using complete parser/decoder sources and the exact PathSegment/renderPath suffix. It provides five fast differential tests and parser-only timings. The final validation and timings use the full TGUIKit modules and the expanded tests under `Tests`.

## Coverage

Ten focused tests cover:

- 2,106 explicit numeric/command/recovery combinations, comparing every Double bit pattern.
- 10,000 random grammar strings and 2,000 random compressed byte sequences, including malformed input.
- 5,000 numbers up to 350 digits, fractions and exponents; packed 2,000-argument commands, arc flags, incomplete groups and output-array capacities.
- Non-ASCII separators, combining characters, emoji, random Unicode scalars, NUL and bridged NSString inputs.
- 81 direct-render pixel pairs across scales and transforms, plus nine pairs with manually packed arrays and trailing incomplete arguments. Multiple fills and preexisting context paths are included.
- 216 complete generateStickerPlaceholderImage pixel pairs across sizes, scales, original image sizes and backgrounds.
- 216 image/frame pairs through all four placeholder consumers, including asynchronous delivery.
- 512 concurrent independent readers and renderers, comparing against reference signatures and pixels.
- Input ownership after caller scope ends, and repeated reads after exhaustion.

These checks preserve the previous parser's behavior; they do not establish complete SVG conformance. Separate mutable readers are used for concurrent work, as in production.

## Experiments and measurement scope

The first integer fast path rewound and rescanned decimal tokens. It reduced integer parsing time by 72–82%, but long numeric input became 8% slower. It was rejected. Single-pass scalar and UTF-8 variants are retained under Experiments, with their measured standalone sources in tar.gz archives. The final version uses the UTF-8 view and direct segment assembly, with exact-capacity argument buffers. Initial full-module tests needed selective imports because the package also declares a type named TGUIKit; those compile diagnostics are retained as fixture failures.

Final release timings use nine alternating paired batches, then a separate process with the initial order reversed. Each result includes the same harness in both variants. Complete sticker construction includes real views, mask generation and the shimmer foreground. Rounded and unchanged controls do not use the edited parser. Standalone drawing measurements reuse pre-parsed segments.

The parser object's runtime and allocator sizes are measured separately. Neither object size nor array-capacity checks measure total process memory or GPU storage. The full Telegram app, chat-opening latency and scrolling FPS are outside this fixture.

## Final results

All ten focused tests pass in release, Address Sanitizer and Thread Sanitizer builds. The complete frozen TGUIKit suite passes 420 functional tests, with 18 optional measurements skipped. The small standalone reproduction passes its five differential tests. Address Sanitizer leak detection is disabled.

A fresh generator reproduces 523 Swift sources and three manifests after temporary-path normalization. All 676 recorded compiler/dependency inputs and 259 final production source/test files verify unchanged against their recorded hashes. The candidate differs from the baseline only in the two intended source files; code preceding the renderer's segment loop is byte-identical. Neither final benchmark run had matching swift-frontend, xcodebuild or clang processes in its pre/post checks. Measurements ran on arm64 macOS 26.4 (25E246), Apple Swift 6.3.3.

| Workload | Baseline → candidate | Less time across both orders |
| --- | --- | ---: |
| Parse 60 integer line commands | 43.3–43.7 → 10.2–10.4 µs | 76.2–76.5% |
| Parse 40 integer curve commands | 76.0–84.0 → 12.8–13.4 µs | 83.1–84.1% |
| Parse 40 fractional curve commands | 115.1–121.1 → 23.7–23.9 µs | 79.4–80.2% |
| Parse long numeric tokens | 99.9–102.2 → 20.9–21.6 µs | 78.9–79.1% |
| Parse exponent tokens | 102.1–106.9 → 21.7–21.8 µs | 78.7–79.7% |
| Complete sticker construction, line-heavy | 154.1–157.0 → 118.7–119.7 µs | 22.9–23.7% |
| Complete sticker construction, integer curves | 144.7–149.1 → 78.9–79.8 µs | 45.4–46.4% |
| Complete sticker construction, fractional curves | 196.7–204.0 → 100.0–100.7 µs | 49.1–50.6% |
| Complete sticker construction, short rectangle | 48.8–49.5 → 44.4–45.7 µs | 7.7–9.0% |

Direct drawing is 1.8–10.6% faster in these fixtures. Complete placeholder-image generation takes 31.7–63.1% less time. The rounded control is 0.5–1.7% slower, adding 0.28–0.82 µs. Already-unchanged calls are 4.1–5.5% slower, adding approximately 0.003–0.004 µs. These controls remain in the report. All 24 workload rows and raw batches are retained in [results/medians.md](results/medians.md) and the JSON files.

Parser runtime and allocator size both fall from 80 to 48 bytes, a 40% reduction for that transient object. Output argument-array capacity does not exceed the baseline in the numeric and packed-command tests. No global retention is added. This is not a measurement of total transient allocations, process memory or typical app memory savings.

The inputs are generated valid thumbnail paths and parser stress cases, not a captured production workload. Benefits apply while constructing/rasterizing path-based loading placeholders. Cached media, whole-message rendering, chat-opening latency and scrolling FPS were not measured here; the full app was not built.
