# Glyph-run drawing lab

This AppKit mini-app builds the complete baseline and candidate TGUIKit renderers in separate temporary packages. The baseline is `8557150e7`; only `TextView.swift`, `TextNode.swift` and the new internal `TextRunDrawing.swift` differ. Source hashes are retained with the results. The working checkout is never switched.

The change keeps `CTRunDraw` and the existing run order, text positions and partial-glyph accounting. It traverses Core Text's own run array directly, removes an unused string-range query, and checks for a partial-glyph limit once per line. Explicit glyph counts are retained: although a zero-length range gives identical pixels, an in-process experiment found that it slows emoji and mixed-text rendering. An internal helper is inlined at its two production call sites so the optional position and glyph-limit arguments can be specialized. No retained cache or per-view/layout storage is added.

The array returned by `CTLineGetGlyphRuns` contains `CTRun` objects; only pointers obtained from that array are converted to `CTRun`. The line and array own the objects during drawing. Sanitizer tests exercise temporary lines repeatedly, and pixel tests cover both callers' context-position behavior.

An initial `CTLineDraw` experiment was rejected: whole-line drawing changes underline/strikethrough behavior and some emoji pixels at 1× and 3×. The shipped path continues drawing individual runs.

## Validation

- TGUIKit regression tests cover the complete toolkit in debug and release, with focused Address Sanitizer checks; exact counts, log hashes and source hashes are recorded in `Evidence/validation.json`.
- 756 byte-for-byte pixel/context comparisons cover seven text corpora, nine styles, 1×/2×/3× drawing, normal/flipped text matrices and both callers' position-reset behavior. They include Arabic/Hebrew, CJK, combining marks, ligatures, emoji, empty text, color/font changes, underline, strikethrough, kerning, baseline offsets, stroke and transparent glyphs.
- Partial-glyph limits are checked from below zero to beyond the total glyph count across multiple runs and lines, including the returned count and resulting text position.
- 1,000 temporary-line draws exercise Core Text object lifetimes.
- 252 matching SHA-256 pixel-buffer hashes compare the complete old/new `TextView` and `TextNode` renderers. Fixtures cover selections, decorations, spoilers, embedded text, cutouts, multiple scales and partial-glyph limits. Nonempty fixtures assert that drawing produced nonzero pixels.
- The helper typechecks against the macOS 10.13 deployment target on x86_64.

The mini-app draws real production views and nodes into bitmap contexts. It does not build Telegram or measure end-to-end chat scrolling, frame latency or application memory. Temporary drawing overhead is reduced; no retained-memory reduction is claimed.

## Measurements

`Evidence/alternating.json` contains nine alternating in-process baseline/candidate batches of 2,000 glyph-run draws each. This isolates enumeration and run-drawing overhead using the real production helper. `Evidence/comparison.json` compares complete-view/node benchmarks in both execution orders, with all individual trials retained.

Final full-TextView results across the two execution orders:

| Fixture | Speedup range |
|---|---:|
| Short timestamp | 1.025–1.082× |
| Plain mixed text | 1.005–1.026× |
| Emoji | 1.013–1.017× |
| Arabic/Hebrew mixed text | 1.046–1.055× |
| CJK mixed text | 1.041–1.071× |
| Many styled runs | 1.048–1.055× |
| Spoiler-heavy text | 0.985–0.987× |

The spoiler fixture was approximately 1.3–1.5% slower in both orders; this pass does not improve its dominant clipping/rectangle work. Other tested TextView fixtures improved, but whole-app impact is unmeasured. The alternating run-loop benchmark improved by 1.048–1.092× for one to 64 runs.

The full-render benchmarks use nine batches of 2,000 draws per fixture, after warmup, with identical dependencies and fixtures. Short text and emoji can be dominated by context setup or Core Text rasterization and are sensitive to run-to-run timing variation. Treat the results as fixture-specific CPU timings, not an app-wide performance claim.

## Reproduce

From the repository root:

```sh
python3 tools/perflab/TextRunDrawingLab/prepare.py baseline /tmp/text-run-drawing-lab/baseline
python3 tools/perflab/TextRunDrawingLab/prepare.py candidate /tmp/text-run-drawing-lab/candidate
swift build -c release --package-path /tmp/text-run-drawing-lab/baseline/TextRunDrawingLab
swift build -c release --package-path /tmp/text-run-drawing-lab/candidate/TextRunDrawingLab
mkdir -p /tmp/text-run-results
```

For each variant, run its built executable with `--snapshots /tmp/text-run-results/<variant>-snapshots.json` to record output hashes. Run without `--snapshots` to record timings, first baseline then candidate into `<variant>-results.json`, then candidate before baseline into `<variant>-repeat.json`. Finish with:

```sh
python3 tools/perflab/TextRunDrawingLab/compare.py /tmp/text-run-results
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-debug
TEXT_RUN_BENCHMARK=1 swift test -c release --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release
swift test --sanitize address --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-asan --filter 'TextRunDrawingTests|TextHitTestingTests|TextViewUpdateRegressionTests|TextViewUpdateTests|TableScrollGeometryTests'
```

The opt-in test writes `/tmp/text-run-alternating.json`. Run benchmarks sequentially and separately from builds/tests. Theme image placeholders initialize TGUIKit; both variants receive the same images.

The rejected zero-range alternative is reproducible with `Experiments/RunRangeChoices.swift`. Its three timing columns are the original NSArray loop, direct CFArray traversal with a zero-length range, and direct traversal with an explicit glyph count. `Evidence/range-choice-experiment.txt` records the measurements that led to retaining explicit counts.
