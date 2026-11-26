# Quote attributes during text measurement

TextViewLayout previously looked up the quote attribute at each line start and enumerated each nonterminal line's quote attributes to find its last nonempty value. This happened even for text with no quotes.

The final implementation keeps the current quote value and its longest effective attribute range in local variables for one calculateLayout call. Lines entirely inside that range reuse the value. Lines crossing a range boundary use the existing last-value lookup, now shared with the measurement path and explicitly passed the prepared attributed-string snapshot. This preserves the original last-nonempty-attribute rule, including a final unsupported value suppressing an earlier valid quote. The start-of-line and last-value lookups remain separate because they control different parts of layout.

No new layout/view fields, persistent cache, public API, shaping rule, drawing algorithm or interaction behavior is introduced. The range is discarded after each measurement. This removes repeated attribute queries/enumerations; it is not a measured percentage reduction in app memory.

## Reproduce

```sh
python3 tools/perflab/QuoteMeasureLab/prepare-isolated.py /tmp/QuoteMeasureValidation
swift test --package-path /tmp/QuoteMeasureValidation --scratch-path /tmp/QuoteMeasureValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/QuoteMeasureValidation --scratch-path /tmp/QuoteMeasureValidation-asan --sanitize address --filter QuoteMeasureTests
swift test --package-path /tmp/QuoteMeasureValidation --scratch-path /tmp/QuoteMeasureValidation-tsan --sanitize thread --filter QuoteMeasureTests
swift test --package-path /tmp/QuoteMeasureValidation/TGUIKit --scratch-path /tmp/QuoteMeasureValidation-kit -c release
QUOTE_MEASURE_BENCHMARK=1 swift test --package-path /tmp/QuoteMeasureValidation --scratch-path /tmp/QuoteMeasureValidation-build -c release --skip-build --filter QuoteBenchmarkTests
cp /tmp/quote-measure-benchmark.json /tmp/quote-forward.json
QUOTE_MEASURE_BENCHMARK=1 QUOTE_MEASURE_REVERSE=1 swift test --package-path /tmp/QuoteMeasureValidation --scratch-path /tmp/QuoteMeasureValidation-build -c release --skip-build --filter QuoteBenchmarkTests
cp /tmp/quote-measure-benchmark.json /tmp/quote-reverse.json
```

Use a fresh output directory. Build, test and benchmark sequentially. Timings should run without competing builds. The generator freezes two complete TGUIKit modules differing only in the production TextView.swift change. Both receive identical test-only fixture/snapshot helpers; those helpers are not added to production. Named theme icons use identical placeholders in both modules. The lab uses real Core Text shaping and TextViewLayer bitmap drawing.

## Validation

Five focused tests pass in release, Address Sanitizer and Thread Sanitizer. Address Sanitizer leak detection is disabled. The full frozen TGUIKit suite passes 420 functional tests, with 18 optional measurements/captures skipped (438 total). Three new production-target regressions cover last-nonempty quote selection, unsupported trailing values, and mutable source changes between measurements.

The differential checks include:

- All 1,024 five-character patterns of absent, regular quote, code/header quote and unsupported attributes, covering every nonempty subrange: 15,360 lookup comparisons against enumeration.
- 2,736 matching layout/glyph snapshots, including line/block frames and ranges, code headers, RTL flags, alignment, decoration/embedded-item frames, glyph identifiers, positions, advances and indexes. This includes 256 concurrent independent measurements.
- 232 exact bitmap pairs at 1x/2x using the actual layer renderer, with explicit nonblank assertions.
- Empty text, trailing newlines, Arabic/Hebrew, CJK, emoji families and combining characters; three widths, three line limits, three alignments, cutouts and dense decorations; 256 seeded random cases and 24 mutable-source transitions.

A fresh generator reproduces 521 Swift files and three manifests, after normalizing the temporary directory in manifests. All 674 recorded compiler/dependency inputs remain unchanged. Production input hashes, source snapshots, exact replacements, raw measurements and test logs are retained. No full Telegram build, onscreen scrolling FPS, GPU timing or process-memory measurement is claimed.

## Measurement method

Release medians use nine alternating paired batches, repeated in a separate process with reversed initial ordering. Attributed strings are prepared outside timing; cold cases construct and measure a real TextViewLayout, while resize cases reuse one layout and alternate widths 280/290. Fixture iteration counts are recorded in QuoteBenchmarkTests.swift. The final environment is arm64 macOS 26.4 (25E246), Apple Swift 6.3.3.

The complete table is in [results/medians.md](results/medians.md). Both final timing runs had no matching compiler processes in their pre/post checks.

| Workload | Less measurement time across both orders |
| --- | ---: |
| Ordinary chat paragraph, resize | 9.8–10.3% |
| Ordinary chat paragraph, cold | 3.0–3.4% |
| Mixed-script Unicode, resize | 6.3–7.2% |
| Code block, cold / resize | 6.4–6.8% / 5.9–6.0% |
| Regular quote, cold / resize | 4.1–4.7% / 3.8–4.1% |
| Short label, cold | 4.1–4.3% |
| Densely colored plain text, resize | 3.6–4.8% |
| Long plain/quoted text | 0.6–1.9% |

The paragraph resize fixture decreases from 14.65–14.81 µs to 13.22–13.28 µs. The code-block cold fixture decreases from 38.13–38.98 µs to 35.68–36.33 µs. Short-label resizing improves by 1.4–4.1%. Heavily decorated text is effectively flat: its cold measurement ranges from 0.2% less to 0.4% more time, and resizing ranges from 0.1% more to 0.4% less. Unicode cold measurement improves by only 0.3–0.5%, because shaping dominates that workload.

Percentages apply to layout measurement, not complete message rendering or scrolling. Long text and heavily decorated text remain dominated by other shaping/layout work.

## Alternatives

Experiments/targeted-only records replacing just the per-line enumeration with the existing last-value lookup. Experiments/effective-range adds a local cache bounded by ordinary effective attribute runs. The final longest-range version can reuse a quote value across unrelated font/color/style boundaries. All three exploratory versions passed the original four focused tests; their preliminary timings are retained separately and are not used for final claims. The final suite adds the concurrent test and benchmarks for densely colored text.

The previously tested image identity guard was not revisited: ImageContentsLab already records native regressions from that approach. TextViewLayout was selected instead.

Archived text logs normalize trailing whitespace without changing test content or timing batches.
