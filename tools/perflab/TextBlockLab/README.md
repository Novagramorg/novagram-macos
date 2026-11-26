# Text background mask lab

`TextViewLayout.generateBlock(backgroundColor:)` builds mask images for chat text, poll and to-do labels, and translations. Previously it constructed an attributed substring for every line to exclude newline-only lines. The candidate checks the UTF-16 range length and code unit instead, with an early return for empty layouts. Range-specific masks also reuse the line references already returned alongside their rectangles instead of building another array.

No geometry is cached. Line ordering, width normalization, alignment, corner rounding, image placement, colors, and scale handling are unchanged.

## Validation

The real TGUIKit renderer is tested, without a Telegram account:

- All 204 functional TGUIKit tests pass in debug and release (206 total, two opt-in benchmarks skipped).
- 24 focused functional tests pass under Address Sanitizer (26 total, two benchmark skips).
- Four new tests compare exact image pixels, size, origin, and nil behavior against the preserved implementation. They cover wrapping, blank lines, CRLF, Unicode separators, emoji, combining sequences, RTL, three alignments, 1×/2×/3× scales, transparent masks, every range boundary in a mixed Unicode string, and 200 seeded cases with truncation, cutouts, reordered/mutated geometry, remeasurement, and text replacement.
- A real NSAttributedString subclass confirms that whole-block generation changes from one temporary attributed substring per line to zero.
- Separate baseline and candidate mini-apps produce identical hashes and metadata for all 144 mask snapshots. Both build the complete TGUIKit renderer; the only library difference is `TextView.swift` from baseline `314247f46` versus the working tree.

`LegacyTextBlock.swift` preserves both original methods and the private whole-block rasterizer. The range-specific reference uses the unchanged public rasterizer. `prepare.py` verifies the reference against the baseline commit, allowing only identifier substitutions, removed comments, and whitespace differences. Evidence includes source provenance, raw benchmark trials, snapshot hashes, and test summaries.

Full Telegram compilation, live-account chat scrolling, peak memory, and GPU timing were not measured. This measures mask generation, not whole-message rendering or application frame rate.

## Measurements

Median microseconds per whole-block mask, shown for the first run and the repeat with process order reversed:

| Fixture | Original | Candidate | Original repeat | Candidate repeat |
|---|---:|---:|---:|---:|
| Empty | 0.042 | 0.033 | 0.040 | 0.033 |
| Newlines only | 2.015 | 0.070 | 1.904 | 0.072 |
| Short poll question | 16.803 | 15.592 | 16.069 | 15.809 |
| Wrapped paragraph | 192.904 | 164.466 | 184.645 | 165.057 |
| Densely styled text | 241.956 | 42.814 | 252.445 | 42.990 |
| Many explicit lines | 647.107 | 594.701 | 658.575 | 570.272 |
| RTL and Latin | 28.425 | 20.930 | 28.403 | 20.995 |
| Emoji and combining characters | 27.590 | 19.741 | 27.613 | 19.702 |

The styled fixture is 5.65–5.87× faster; wrapped paragraphs take 11–15% less time, RTL about 26% less, and emoji about 29% less. Short plain labels improve by 2–7%, so their gain is small. Range-specific masks are generally close in timing (mostly 1–6% faster), with one fewer temporary line-reference array. Those small timing differences should be treated cautiously. The large newline-only speedup has a small absolute impact and produces no bitmap.

## Reproduce

From the repository root:

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-debug
swift test -c release --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release
swift test --sanitize address --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-asan --filter 'TextBlockTests|TextRunDrawingTests|SpoilerGeometryTests|TextViewUpdateRegressionTests|TextViewUpdateTests'
python3 tools/perflab/TextBlockLab/prepare.py baseline /tmp/text-block-lab/baseline
python3 tools/perflab/TextBlockLab/prepare.py candidate /tmp/text-block-lab/candidate
swift build -c release --package-path /tmp/text-block-lab/baseline/TextBlockLab
swift build -c release --package-path /tmp/text-block-lab/candidate/TextBlockLab
```

Use dedicated temporary output directories: preparation replaces their generated Sources and Tests directories. Run each `.build/release/TextBlockLab` executable with `--snapshots <variant>-snapshots.json` to record image hashes, or `<variant>.json` for timings. Run sequentially after builds finish, then repeat timings in reverse process order, naming the files `<variant>-repeat.json`. Put all six files in one directory and run:

```sh
python3 tools/perflab/TextBlockLab/compare.py <results-directory>
```

Measurements use Apple Silicon, optimized Swift 6.3.3 builds, nine batches of 300 complete mask generations after warmup, and autorelease pools. Layout measurement and image hashing are outside the timed region. `Evidence/comparison.json` reports both execution orders; the larger fixtures are synthetic workloads.
