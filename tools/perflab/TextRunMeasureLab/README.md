# Core Text run inspection during measurement

TextViewLayout used bridged NSArray enumeration for direction detection, a Swift array conversion for truncated-line run inspection, and an NSDictionary lookup to test one run attribute. The candidate traverses the immutable CFArray returned by CTLineGetGlyphRuns directly and uses CFDictionaryContainsKey for the context-color attribute.

The existing rules are preserved: ordinary lines inspect only the first run's RTL status; terminal lines inspect every run until an RTL run is found. Truncation still stops at the first run containing the context-color key, including a false attribute value. A native test verifies that kCTForegroundColorFromContextAttributeName has the same string value as the original literal.

Only objects returned by Core Text's glyph-run array are converted to CTRun. The owning CTLine remains alive and is used after each inspection loop; the array owns its run elements. The borrowed dictionary key points to Core Text's global CFString constant. This follows the existing direct traversal used by drawTextLineRuns. No raw pointer is retained between calls. No new layout/view fields, persistent cache, public API, shaping rule or drawing algorithm is introduced.

## Reproduce

```sh
python3 tools/perflab/TextRunMeasureLab/prepare-isolated.py /tmp/TextRunMeasureValidation
swift test --package-path /tmp/TextRunMeasureValidation --scratch-path /tmp/TextRunMeasureValidation-build -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path /tmp/TextRunMeasureValidation --scratch-path /tmp/TextRunMeasureValidation-asan --sanitize address --filter RunMeasureTests
swift test --package-path /tmp/TextRunMeasureValidation --scratch-path /tmp/TextRunMeasureValidation-tsan --sanitize thread --filter RunMeasureTests
swift test --package-path /tmp/TextRunMeasureValidation/TGUIKit --scratch-path /tmp/TextRunMeasureValidation-kit -c release
RUN_MEASURE_BENCHMARK=1 swift test --package-path /tmp/TextRunMeasureValidation --scratch-path /tmp/TextRunMeasureValidation-build -c release --skip-build --filter RunMeasureBenchmarkTests
cp /tmp/run-measure-benchmark.json /tmp/run-forward.json
RUN_MEASURE_BENCHMARK=1 RUN_MEASURE_REVERSE=1 swift test --package-path /tmp/TextRunMeasureValidation --scratch-path /tmp/TextRunMeasureValidation-build -c release --skip-build --filter RunMeasureBenchmarkTests
cp /tmp/run-measure-benchmark.json /tmp/run-reverse.json
```

Use a fresh output directory. Build, test and benchmark sequentially. Timings should run without competing builds. The baseline is commit 3a4df7194. The generator freezes two complete TGUIKit modules differing only in the production TextView.swift change. Its source guard intentionally requires the recorded original or candidate revision; rerun a historical lab from its recorded checkout when later TextView.swift changes exist. Both receive identical test-only fixture/snapshot helpers reused from QuoteMeasureLab; those helpers are not added to production. Named theme icons use identical placeholders in both modules. The lab uses real Core Text shaping and TextViewLayer bitmap drawing.

## Validation

Seven focused tests pass in release, Address Sanitizer and Thread Sanitizer. Address Sanitizer leak detection is disabled. The full frozen TGUIKit suite passes 420 functional tests, with 18 optional measurements/captures skipped (438 total).

The differential checks include:

- 4,546 matching layout/glyph snapshots, including line/block frames and ranges, RTL flags, alignment, decoration/embedded-item frames, glyph identifiers, positions, advances and indexes.
- 412 exact bitmap pairs at 1x/2x using the actual layer renderer, with explicit nonblank assertions.
- 810 targeted combinations of five mixed-script strings, six attribute modes, three widths, three line limits and three truncation modes. These include mixed fonts/colors, context-color true/false values, embedded items, underline and strikethrough, and combinations of those attributes.
- 1,000 temporary-layout lifetimes, plus 256 concurrent independent measurements.
- Empty text, trailing newlines, Arabic/Hebrew, CJK, emoji families and combining characters; quotes/code headers, alignment, cutouts, seeded random cases and mutable-source transitions.

An unchanged quote-lookup control also retains the 15,360 range/enumeration comparisons from QuoteMeasureLab; those are not additional run-traversal coverage.

A fresh generator reproduces 521 Swift files and three manifests, after normalizing the temporary directory in manifests. All 674 recorded compiler/dependency inputs remain unchanged. Production input hashes, source snapshots, exact replacements, raw measurements and test logs are retained. No full Telegram build, onscreen scrolling FPS, GPU timing or process-memory measurement is claimed.

## Measurement method

Release medians use nine alternating paired batches, repeated in a separate process with reversed initial ordering. Attributed strings are prepared outside timing; cold cases construct and measure a real TextViewLayout, while resize cases reuse one layout and alternate widths 280/290. Fixture iteration counts are recorded in RunMeasureBenchmarkTests.swift. The environment is arm64 macOS 26.4 (25E246), Apple Swift 6.3.3.

Cases prefixed immutable_ copy the attributed string once before timing, matching the immutable boundary of the app's shared attributed-text factory. Other cases deliberately keep mutable strings so content-equality costs remain represented. Truncated cases use a one-line limit; other cases use unlimited lines. The complete table is in [results/medians.md](results/medians.md).

Both final runs had no matching compiler processes in their pre/post checks.

| Workload | Less measurement time across both orders |
| --- | ---: |
| Truncated plain text, resize (mutable) | 7.1–8.5% |
| Truncated plain text, resize (immutable) | 6.9–7.8% |
| Truncated mixed-script text, resize | 5.3–7.3% |
| Ordinary paragraph, resize | 2.5–2.7% |
| Immutable paragraph, resize | 1.8–2.3% |
| Short label, cold (mutable / immutable) | 1.4–3.5% / 2.2–3.9% |

Truncated plain-text resizing decreases from 4.44–4.46 µs to 4.08–4.13 µs for mutable inputs and from 4.33–4.38 µs to 3.99–4.07 µs for immutable inputs. Mixed-script truncated resizing decreases from 12.54–12.76 µs to 11.83–11.88 µs. These absolute savings are small.

Most long, colored and heavily decorated cases are approximately flat. Colored plain-text resizing is flat in the forward run and 1.1% slower in reverse, about 0.37 µs more; rich plain-text resizing ranges from 0.5% less to 0.4% more time. There is no universal speedup. The full median table and raw batches retain all cases, including regressions.

The change avoids explicit run-array conversions and dictionary bridging. No allocation-byte count or whole-process memory reduction is claimed. Percentages apply to layout measurement, not complete message rendering or scrolling.

## Alternatives

Experiments/direct-array records changing only array traversal. Experiments/direct-array-and-dictionary adds the native attribute-presence check. Exploratory timings are retained separately and are not used for final claims. The expanded final benchmark adds immutable-input controls; the final tests add combinations of context-color attributes with embedded items and decorations.

Archived text logs normalize trailing whitespace without changing test content or timing batches.
