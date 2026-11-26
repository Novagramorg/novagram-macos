# SpoilerGeometryLab

This standalone mini-app builds the real TGUIKit text renderer twice: a baseline with `TextView.swift` from `7b573a350`, and the current implementation. Other sources are identical. No Telegram account or full app build is required.

The optimization removes per-line spoiler filtering and per-intersection range arrays, queries typographic bounds once per affected line, and produces frames directly for callers that do not need spoiler metadata. Hit testing stops at the first match without constructing all rectangles. For more than eight spoilers, each line uses binary search to skip earlier ranges. Spoiler ranges are immutable and originate from forward attributed-string enumeration, so they are sorted and nonoverlapping. Line order and frames may still change; the implementation does not assume ordered lines or retain geometry across queries.

Selection boundaries, rectangle ordering, reveal state, RTL offsets and floating-point operation order are preserved, including existing zero-length intersections and selection-range calculations. This change does not attempt to redesign spoiler selection behavior. It introduces no persistent layout cache.

## Verification

- All 190 functional TGUIKit tests pass in debug and release. Debug has 192 total tests with two opt-in benchmarks skipped; release runs the spoiler benchmark and skips the other benchmark.
- 31 focused functional tests pass with Address Sanitizer, including spoiler geometry, dust playback, text drawing, hit testing, view updates and scrolling geometry (33 tests including two benchmark skips).
- Differential geometry tests compare the preserved implementation with the candidate across 1,200 seeded cases, scripts, wrapping, truncation, cutouts, selections, reveal states, reversed lines, mutated frames, remeasurement and empty layouts.
- Hit tests cover rectangle centers, edges, selection gaps and outside points, preserving spoiler identity.
- The independent mini-app binaries produce identical SHA-256 hashes for all 192 full `TextView` drawings: eight fixtures, hidden/revealed states, 1×/2×/3× scales and four selection states. Revealed nonempty fixtures require nonblank output.
- Interactive preview checks confirmed click-to-reveal for ordinary, wrapped, mixed-direction and emoji text, selection across hidden spans, and scrolling. The preview uses TGUIKit's `Window` so the real mouse handlers execute.

`Evidence/validation.json` records source hashes and test-log summaries. Each binary's source provenance, every raw timing trial, rendered-output hashes and comparisons are retained in `Evidence/`. Pixel comparisons cover the text drawing layer, not animated dust particles. Dust playback is covered separately by the regression suite. Full Telegram compilation, live-account chat scrolling, retained memory and GPU timing were not measured.

## Measurements

Apple Silicon, Swift 6.3.3, optimized builds. Geometry medians use nine alternating batches of 1,000 queries in one process. Times below are microseconds per query for hidden spoilers.

| Query | Spoilers / lines | Before | After |
|---|---:|---:|---:|
| Frames | 1 / 1 | 0.601 | 0.324 |
| Frames | 8 / 4 | 3.185 | 1.851 |
| Frames | 64 / 32 | 40.372 | 10.291 |
| Frames | 256 / 128 | 414.814 | 42.498 |
| First hit | 8 / 4 | 2.671 | 0.112 |
| Miss | 64 / 32 | 40.600 | 9.722 |

The 256-spoiler fixture is a stress case. Early hits benefit from avoiding work for the rest of the message; misses still traverse affected lines. The raw file also includes fully revealed layouts and all first-hit/miss cases.

Whole-render timing uses nine batches of 500 draws per fixture in separate baseline/candidate binaries, then repeats with process order reversed. Dense hidden spoilers render about 2.8% faster in both execution orders. Most other fixtures change by only a few percent, with noise and some small regressions; plain text is 2.7% slower in one order and 1% faster in the other. Core Graphics clipping still dominates hidden-text drawing. The larger geometry-query speedups are not whole-render or app-wide speedups.

## Reproduce

From the repository root:

```sh
python3 tools/perflab/SpoilerGeometryLab/prepare.py baseline /tmp/spoiler-lab/baseline
python3 tools/perflab/SpoilerGeometryLab/prepare.py candidate /tmp/spoiler-lab/candidate
swift build -c release --package-path /tmp/spoiler-lab/baseline/SpoilerGeometryLab
swift build -c release --package-path /tmp/spoiler-lab/candidate/SpoilerGeometryLab
```

Run each binary with `--snapshots /tmp/<variant>-snapshots.json` for rendered hashes, or just `/tmp/<variant>-results.json` for draw timings. Run timings sequentially; repeat in reverse order with output names `<variant>-repeat.json`. Collect the six output files into one directory and run `python3 tools/perflab/SpoilerGeometryLab/compare.py <directory>` to verify hashes and compare timings.

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-spoiler-debug
SPOILER_GEOMETRY_BENCHMARK=1 swift test -c release --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-spoiler-release
swift test --sanitize address --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-spoiler-asan --filter 'SpoilerGeometryTests|SpoilerDustPlaybackTests|TextRunDrawingTests|TextHitTestingTests|TextViewUpdateRegressionTests|TextViewUpdateTests|TableScrollGeometryTests'
swift run -c release --package-path tools/perflab/SpoilerGeometryLab SpoilerGeometryLab --preview
```

The geometry benchmark writes `/tmp/spoiler-geometry-benchmark.json`. `prepare.py` replaces the generated `Sources` and `Tests` directories inside the specified temporary output, so use a dedicated directory.
