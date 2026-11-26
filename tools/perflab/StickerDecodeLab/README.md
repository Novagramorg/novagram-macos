# Compact sticker-thumbnail decoding

The compact-thumbnail decoder previously built an SVG-style string by formatting each coordinate and repeatedly appending small strings. It now counts the exact output length, then writes ASCII commands and decimal digits directly into the returned String's buffer on macOS 11 and newer. The buffer is initialized before writing. Every input byte produces one to three ASCII bytes, with an initial M and final z; bounds-checked output writes preserve the original mapping.

Older macOS versions use an exactly sized temporary byte array and the same writer. An empty input returns Mz before either path. The command table stores 64 bytes instead of 64 small Strings. No new cache, public API or dependency is introduced. Only StickerThumbnailPath.swift changes; parsing, geometry, drawing and consumer code remain unchanged.

The direct String initializer is guarded by its SDK-declared macOS 11 availability. The production source was also compiled as an Intel macOS 10.13 module. The fallback is explicitly exercised on the current host; this is not a runtime test on an older macOS installation.

## Reproduce

```sh
python3 tools/perflab/StickerDecodeLab/prepare-isolated.py /tmp/StickerDecodeValidation
swift test --package-path /tmp/StickerDecodeValidation --scratch-path /tmp/StickerDecodeValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/StickerDecodeValidation --scratch-path /tmp/StickerDecodeValidation-asan --sanitize address --filter 'DecodeTests.(DecodeTests|PathTests|ExtendedPathTests)'
swift test --package-path /tmp/StickerDecodeValidation --scratch-path /tmp/StickerDecodeValidation-tsan --sanitize thread --filter 'DecodeTests.(DecodeTests|PathTests|ExtendedPathTests)'
swift test --package-path /tmp/StickerDecodeValidation/TGUIKit --scratch-path /tmp/StickerDecodeValidation-kit -c release
STICKER_DECODE_BENCHMARK=1 STICKER_PATH_BENCHMARK=1 swift test --package-path /tmp/StickerDecodeValidation --scratch-path /tmp/StickerDecodeValidation-build -c release --skip-build --filter 'DecodeBenchmarkTests|PathBenchmarkTests'
cp /tmp/sticker-decode-benchmark.json /tmp/decode-forward.json
cp /tmp/sticker-path-benchmark.json /tmp/pipeline-forward.json
STICKER_DECODE_BENCHMARK=1 STICKER_DECODE_REVERSE=1 STICKER_PATH_BENCHMARK=1 STICKER_PATH_REVERSE=1 swift test --package-path /tmp/StickerDecodeValidation --scratch-path /tmp/StickerDecodeValidation-build -c release --skip-build --filter 'DecodeBenchmarkTests|PathBenchmarkTests'
cp /tmp/sticker-decode-benchmark.json /tmp/decode-reverse.json
cp /tmp/sticker-path-benchmark.json /tmp/pipeline-reverse.json
STICKER_DECODE_MEMORY=1 swift test --package-path /tmp/StickerDecodeValidation --scratch-path /tmp/StickerDecodeValidation-build -c release --skip-build --filter DecodeMemoryTests
```

Use fresh output directories and run builds sequentially. Run timing and allocator observations without competing compilers. The generator freezes two complete TGUIKit modules, differing only in the decoder. Its reference is commit fce7c808c; other worktree files are copied identically, including local changes. Test-only accessors expose images and the private fallback/length/table helpers. They do not instrument production decoding or drawing. All measured source and dependency hashes are recorded with the results.

`python3 tools/perflab/StickerDecodeLab/prepare-standalone.py /tmp/StickerDecodeQuick` generates a smaller Foundation-only package for the three exhaustive decoder tests, timings and allocator observations.

## Coverage

Sixteen functional tests include:

- All 256 single-byte values and all 65,536 byte pairs, checking native and forced fallback output against the original decoder and verifying the exact length calculation.
- 5,000 randomized payloads, including nonzero-index Data slices, plus bridged NSData and ordered/reversed/repeated payloads up to 65,536 bytes.
- 1,024 concurrent native/fallback/length comparisons; returned-string ownership after input mutation and release; command-table element storage.
- 99 forced-fallback pixel pairs, including compact-coordinate thumbnails spanning a 512-point image.
- The previous path lab's numeric and Unicode recovery cases, random parser inputs, packed argument arrays, input ownership, 90 direct-render pixel pairs, 432 complete-placeholder/consumer pairs, and 512 concurrent parser/render comparisons.

All four placeholder consumers are included: StickerShimmerEffectView, ShimmerLayer, ShimmerView and SilhouetteShimmerLayer, along with generateStickerPlaceholderImage. Comparisons preserve existing parser/drawing semantics and do not claim complete SVG conformance.

## Experiments and scope

The growing-byte-array experiment improved larger decodes by 66–83%, but a one-byte payload was about 8 ns slower. Exact-size reservation improved the short case and made buffer capacity predictable. Direct writing into the String buffer then removed that temporary array on macOS 11+, improved the tiny-input case and reduced large-payload decode time further. These experiments and their measured sources are retained under Experiments.

Release timings use nine alternating paired batches and a separate reversed-order process. The decoder table includes a forced fallback on the current host, not an older operating system. Pipeline timings include decoding/parsing, image generation and complete native placeholder construction. Both compact coordinate encodings and character-table encodings are included; inputs are generated fixtures, not a captured production workload. Unedited parser, drawing, rounded-placeholder and unchanged-update controls remain in the report.

Memory observations warm both implementations, reserve a result array, retain 2,000 decoded strings, then release the strings while keeping the result-array capacity. They record changes in malloc size_in_use across all zones, using five alternating batches. These observations exclude source Data, the result-array allocation, VM/GPU memory and unrelated application work; they are not measurements of total app memory or typical retained placeholder memory. Command-table element storage excludes its array header and static literal storage.

The full Telegram app, chat-opening latency and scrolling FPS are outside these fixtures. Address Sanitizer leak detection is disabled.

## Final results

Release, Address Sanitizer and Thread Sanitizer each pass all 16 focused functional tests. The full frozen TGUIKit suite passes 420 functional tests (18 optional measurements skipped); the Foundation-only package passes its three functional tests. All 680 frozen compiler inputs and 259 production source/test files match the recorded hashes. Fresh generators reproduce 527 decoder-lab Swift files and three manifests, and 523 prior path-lab Swift files and three manifests. The earlier path lab explicitly restores its archived decoder in both modules, preserving that historical comparison after the decoder table's representation change.

The final measurements use two independent processes with opposite initial ordering. Each process alternates nine batches. Selected median ranges are below; complete per-workload results, including controls and the forced fallback, are in [results/medians.md](results/medians.md).

| Workload | Original µs | Native µs | Less time |
| --- | ---: | ---: | ---: |
| Decode 64 mixed bytes | 1.44–1.46 | 0.151–0.163 | 88.7–89.6% |
| Decode 256 mixed bytes | 5.49–5.66 | 0.398 | 92.8–93.0% |
| Decode 1,024 mixed bytes | 22.54–22.63 | 1.41–1.44 | 93.6–93.8% |
| Decode and parse compact curves | 24.36–24.38 | 15.48–15.98 | 34–36.5% |
| Complete compact-curve placeholder | 252.2–274.8 | 244.4–264.0 | 3.1–3.9% |
| Complete compact-line placeholder | 136.1–148.3 | 131.5–142.8 | 3.4–3.7% |
| Complete fractional-curve placeholder | 97.4–102.3 | 82.2–86.4 | 15.5–15.6% |

The complete-placeholder benefit is much smaller than the isolated decoder benefit when rasterization dominates. Across the other construction fixtures, time falls 1.8–10.8%. These are generated component workloads, not whole-app measurements.

Controls remain visible: some unedited parser-only rows take up to 5.3% longer (up to about 1.14 µs). Drawing is approximately flat. Rounded-placeholder construction ranges from 0.2% slower (+0.12 µs) to 1.3% faster. Unchanged updates take 5.8–7.4% longer, an absolute increase of about 0.004–0.005 µs. The measured decode-plus-parse and complete-construction workloads improve in both orders; the controls do not establish a cause for their variation.

The older-system fallback also improves larger payloads, but a one-byte decode takes approximately 0.027–0.031 µs longer than the original. The native path improves that case. Both implementations preserve all tested bytes and output ownership.

For 2,000 retained strings, allocator observations fall from 192,000 to 160,000 bytes for the 16-byte input, 1,536,000 to 1,280,000 for the 256-byte input, and 6,144,000 to 5,120,000 for the 1,024-byte input: about 16.7% less selected string storage. The one-byte and 64-byte cases are unchanged. All observed release deltas return to zero; this is not a general leak proof. The command table's element storage falls from 1,024 to 64 bytes. These figures exclude the rest of the app and do not predict total process memory savings.
