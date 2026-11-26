# Avoid redundant terminal-line measurement in TextNode

TextNode is used for peer names and statuses, media filenames, search results, small labels and code-block headers. Its old measurement loop always created a CoreText typesetter and asked for a wrapping boundary, even on the final permitted line. That final line then consumed the entire remaining string for truncation, making the wrapping boundary unnecessary. When the line fitted, its width was also queried twice.

The final implementation skips the wrapping query on a nonempty terminal line with positive finite effective width. Eligible single-line layouts use CTLineCreateWithAttributedString directly. Other layouts retain the typesetter path. Eligibility checks include cutout subtraction so overflowing or nonfinite cutout arithmetic cannot leave the fallback without a typesetter. The original line width is reused when truncation is unnecessary. Truncation tokens, line frames, cutout offsets, selection transformation, source snapshots and layout-cache keys remain unchanged.

The terminal condition now checks that the line limit is positive before subtracting one. This also fixes an arithmetic-overflow crash for Int.min. Other nonpositive limits already behaved as unlimited; the new tests enforce that behavior consistently. The original crash is reproduced in a separate process, with only its relevant stack retained.

No persistent cache or instance field is added. The fast path avoids explicit typesetter construction, but this lab does not count CoreText's internal allocations or claim a whole-process memory reduction.

## Reproduce

```sh
python3 tools/perflab/TextNodeMeasureLab/prepare-isolated.py /tmp/TextNodeMeasureValidation
swift test --package-path /tmp/TextNodeMeasureValidation --scratch-path /tmp/TextNodeMeasureValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/TextNodeMeasureValidation --scratch-path /tmp/TextNodeMeasureValidation-asan --sanitize address
swift test --package-path /tmp/TextNodeMeasureValidation --scratch-path /tmp/TextNodeMeasureValidation-tsan --sanitize thread
swift test --package-path /tmp/TextNodeMeasureValidation/TGUIKit --scratch-path /tmp/TextNodeMeasureValidation-kit -c release
TEXTNODE_MEASURE_BENCHMARK=1 swift test --package-path /tmp/TextNodeMeasureValidation --scratch-path /tmp/TextNodeMeasureValidation-build -c release --skip-build --filter MeasureBenchmarkTests
cp /tmp/text-node-measure-benchmark.json /tmp/text-node-forward.json
TEXTNODE_MEASURE_BENCHMARK=1 TEXTNODE_MEASURE_REVERSE=1 swift test --package-path /tmp/TextNodeMeasureValidation --scratch-path /tmp/TextNodeMeasureValidation-build -c release --skip-build --filter MeasureBenchmarkTests
cp /tmp/text-node-measure-benchmark.json /tmp/text-node-reverse.json
```

Use new output directories and measure without competing builds. `TEXTNODE_BASELINE_CRASH=1` enables the deliberately crashing original regression test; leave it unset for ordinary validation. The generator freezes complete original and candidate TGUIKit libraries. Their only production-source difference is TextNode.swift. Both receive an identical test-only inspection extension that returns line frames, string ranges, glyph identifiers, glyph positions, advances and string indexes. No inspection code is shipped in the app.

## Performance

The [complete median table](results/medians.md) reports microseconds per operation. Positive percentages mean less CPU time. Nine alternating paired batches are repeated in a separate process with reversed initial order. Ordinary cases use 5,000 iterations per batch, measurement plus drawing uses 2,000, and unchanged reuse uses 200,000. Attributed strings and drawing contexts are prepared outside timing. Both final runs had no matching compiler processes in their pre/post checks.

Three-label construction decreases from 9.12–9.15 µs to 8.59–8.61 µs, about 5.9% less time in both orders. Measuring and drawing one label decreases from 4.83–4.91 µs to 4.57–4.65 µs, about 5.2–5.3% less. Single-line cases use about 2–11% less time: short fitting labels improve by 4–6%, unbounded labels by 5–7%, truncated filenames by about 5.4%, emoji by 6–10%, and narrow labels by 7–11%. RTL shaping remains the dominant cost in its fixture and improves by about 2%.

Two- and three-line capped layouts improve by 2.4–3.5% because their terminal wrapping query is skipped. Unlimited layout and unchanged cache reuse are approximately flat. The selected zero-width fallback is 0.3–0.8% slower, roughly 0.02–0.05 µs; its original CoreText path is retained.

These fixtures exercise real TextNode measurement and bitmap drawing. They do not include complete chat/peer row construction, caller attributed-string creation, media decoding, GPU presentation or full-app scrolling FPS. The three-label percentage must not be interpreted as a whole-row or whole-application speedup. No full application build was performed.

## Validation

Six functional tests pass in release, Address Sanitizer and Thread Sanitizer. Leak detection is disabled for the Address Sanitizer run. The suite includes:

- 5,616 exact geometry/glyph comparisons across 13 strings, four attribute modes, nine widths, four line limits and three truncation modes.
- 2,496 exact bitmap pairs at 1x and 2x, with explicit nonblank checks for ordinary labels.
- 180 control-only and complex-cluster cases, including directional isolates, zero-width characters, newline variants, soft hyphens and combining marks.
- 512 reproducible mixed-script paragraphs with right-side cutouts and varied truncation, alignment and selection.
- 24 mutable-input/width/selection transitions, each with an exact bitmap pair and layout-reuse checks. A separate assertion verifies that the real selected-color attribute changes pixels.
- Four extreme cutout cases, nine nil/empty/nonpositive-limit comparisons and 600 concurrent independent measurements against precomputed original glyph snapshots.

The total is 6,945 matching geometry/glyph snapshots and 2,520 matching bitmap pairs. The full frozen TGUIKit suite passes 415 functional tests with 18 optional measurements skipped. Two new production-target tests cover nonpositive line limits and transitions between limited, unlimited and reused layouts.

All 670 recorded source/dependency inputs are verified unchanged after validation. A fresh generator run reproduces 517 Swift sources and all three package manifests after output-path normalization. The tested, measured and production TextNode sources match, apart from the lab-only inspection extension. Final logs, raw timing batches, input hashes, source snapshots and sanitized baseline-crash evidence are retained in `results`.

## Exploration

The first candidate only skipped the terminal wrapping calculation. It improved the initial measurement cases by roughly 1–9%. Direct single-line construction improved that further; the final version additionally reuses the already measured width and guards extreme cutout arithmetic. Initial exploratory fixtures used an incorrect selected-color key, so their selected cases did not exercise color replacement. The final suite uses KSelectedColorAttributeName, verifies changed selection pixels, and reruns both benchmark orders and all validation. Preliminary logs and source replacements remain archived separately and are not used for final claims. Archived logs normalize trailing whitespace.
