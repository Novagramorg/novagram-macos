# Terminal-line text measurement

TextViewLayout previously asked Core Text for a wrapping boundary on every line, including the final allowed line. That final line is built from all remaining text and then truncated; its initial wrapping count is replaced before layout uses the line range. The candidate skips that unused query for nonempty terminal lines with positive finite effective width. A positive sentinel preserves the existing decoration validity gate. Context-color run inspection and its string-index override are unchanged.

Empty/end-of-source inputs, nonpositive or nonfinite effective widths, nonterminal lines and unlimited layouts retain the native wrapping query. Effective width includes quote and cutout insets. Negative line limits remain unlimited. The terminal line still uses the existing shaping, truncation token and Core Text range logic. When the original line fits, its already calculated typographic width is reused instead of requesting bounds and trailing whitespace again. There are no added fields, persistent caches or public APIs.

## Reproduce

```sh
python3 tools/perflab/TextTerminalMeasureLab/prepare-isolated.py /tmp/TextTerminalMeasureValidation
swift test --package-path /tmp/TextTerminalMeasureValidation --scratch-path /tmp/TextTerminalMeasureValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/TextTerminalMeasureValidation --scratch-path /tmp/TextTerminalMeasureValidation-asan --sanitize address --filter TerminalMeasureTests
swift test --package-path /tmp/TextTerminalMeasureValidation --scratch-path /tmp/TextTerminalMeasureValidation-tsan --sanitize thread --filter TerminalMeasureTests
swift test --package-path /tmp/TextTerminalMeasureValidation/TGUIKit --scratch-path /tmp/TextTerminalMeasureValidation-kit -c release
TERMINAL_MEASURE_BENCHMARK=1 swift test --package-path /tmp/TextTerminalMeasureValidation --scratch-path /tmp/TextTerminalMeasureValidation-build -c release --skip-build --filter TerminalMeasureBenchmarkTests
cp /tmp/terminal-measure-benchmark.json /tmp/terminal-forward.json
TERMINAL_MEASURE_BENCHMARK=1 TERMINAL_MEASURE_REVERSE=1 swift test --package-path /tmp/TextTerminalMeasureValidation --scratch-path /tmp/TextTerminalMeasureValidation-build -c release --skip-build --filter TerminalMeasureBenchmarkTests
cp /tmp/terminal-measure-benchmark.json /tmp/terminal-reverse.json
```

Use a fresh output directory. Build, test and benchmark sequentially without competing builds. The baseline is commit 8a3e83047. The generator freezes two complete TGUIKit modules differing only in the production TextView.swift change. Its source guard requires the recorded original or candidate revision; use the recorded checkout when later TextView.swift changes exist. Both modules receive identical test-only snapshot helpers reused from QuoteMeasureLab. Named theme icons have identical placeholders. The lab uses real Core Text shaping and TextViewLayer bitmap drawing.

## Coverage

The differential fixtures cover 6,739 geometry/glyph snapshots and 505 exact bitmap pairs at 1x/2x, with nonblank assertions. They include line/block frames and ranges, RTL flags, alignment, decoration and embedded-item frames, glyph identifiers, positions, advances and indexes. Matching NaN positions in nonfinite geometry are treated as equivalent; nonfinite geometry is not rasterized.

- 1,575 combinations of control characters, paragraph styles, widths and line limits, including positive subnormal widths, zero-width characters, CR/CRLF, Unicode separators, NUL, soft hyphens, RTL, indents, tab stops, negative kerning and baseline offsets.
- 36 nonpositive/nonfinite-width cases with quote insets and cutouts.
- 42 line-limit transitions using prepared text, with 21 bitmap pairs.
- 540 native CTRunDelegate metric cases with leading/middle/standalone placeholders, widths from zero through oversized attachments and all three truncation modes, including 72 bitmap pairs. Callbacks follow the app's pure ascent/descent/width metric pattern.
- Mixed fonts/colors, context-color true/false, embedded items, underline/strikethrough, Arabic/Hebrew, CJK, emoji families, combining marks, quotes/code headers, trailing newlines, seeded random cases and source mutations.
- 1,000 temporary-layout lifetimes and 256 concurrent independent measurements.

An unchanged quote-lookup control also retains 15,360 range/enumeration comparisons; those are not extra terminal-fast-path coverage.

## Measurement method

Release medians use nine alternating paired batches, repeated in a separate process with reversed initial ordering. Attributed strings are prepared outside timing. Cold means a newly constructed TextViewLayout, not a cold application or font cache. Resize reuses one layout and alternates widths 280/290. Immutable-prefixed inputs are copied once outside timing; other fixtures deliberately retain mutable strings. Truncated and fitting-single fixtures allow one line; capped fixtures allow two or three; controls use unlimited lines. There are 22 fixtures and 44 timing rows. The environment is arm64 macOS 26.4 (25E246), Apple Swift 6.3.3.

Experiments/terminal-break records skipping the terminal wrapping query alone. Experiments/terminal-break-and-width adds fitting-width reuse. Their exploratory measurements are kept separate from final claims. The final native-delegate tests were added after the second exploratory timing, without changing production code.

No full Telegram build, onscreen scrolling FPS, GPU timing, allocation-byte count or process-memory improvement is claimed. Percentages describe text measurement, not complete message rendering or scrolling. Archived text logs normalize trailing whitespace.

## Final results

All 11 focused tests pass in release, Address Sanitizer and Thread Sanitizer. Address Sanitizer leak detection is disabled. The full frozen TGUIKit suite passes 420 functional tests, with 18 optional measurements/captures skipped (438 total). A fresh generator reproduces 521 Swift files and three manifests after temporary-path normalization. All 674 recorded compiler/dependency inputs remain unchanged. Exact replacements, source hashes, raw batches and test logs are retained in this lab.

Both final benchmark runs had no matching compiler processes in their pre/post checks. The complete 44-row table is in [results/medians.md](results/medians.md).

| Workload | Less measurement time across both orders |
| --- | ---: |
| One-line truncated plain text, resize (mutable) | 17.1–18.1% |
| One-line truncated plain text, resize (immutable) | 17.9–18.0% |
| Two-line plain preview, resize | 17.1–17.4% |
| Truncated mixed-script text, resize | 5.3–7.8% |
| Newly constructed truncated plain layout | 2.1–2.6% |
| Newly constructed two-line plain preview | 3.0% |
| Fitting one-line label, cold / resize | 0.9–1.8% / 1.0–1.7% |

Mutable truncated resizing decreases from 4.06–4.12 µs to 3.32–3.42 µs. Two-line plain resizing decreases from 5.49–5.54 µs to 4.55–4.58 µs. Mixed-script truncated resizing decreases from 11.75–11.81 µs to 10.84–11.18 µs. These are small absolute savings in a frequently used operation.

Most unlimited, long and richly decorated workloads are approximately flat. The three-line mixed-script fixture has a short fitting final line and improves only 1.2–1.5% on resize. The largest relative slowdown is unlimited short-label resize: 0.5–2.1%, adding 0.02–0.09 µs. Colored plain resize is 0.8–1.2% slower, adding 0.25–0.38 µs; code resize is 0.7–0.8% slower, adding 0.26–0.32 µs. Immutable ordinary paragraph resize is 0.5–0.6% slower. These small measured regressions remain in the published results; no universal speedup is claimed.
