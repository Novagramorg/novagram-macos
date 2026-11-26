# Selection and quote traversal work

This pass changes only the shared text drawing function in `TextView.swift`. It stops constructing a temporary array of primary and additional selections on every redraw, asks CoreText for selection alignment only on intersecting lines, and skips quote membership searches for left-to-right glyph lines. Selection order, colors, geometry and RTL indentation remain unchanged. Both TextView and standalone TextViewLayer use the improved function.

## Reference and coverage

The lab preparation script preserves the complete shared drawing function and view wrapper from `f23a0ca31` as `PreviousTextRenderer`, compiled inside the copied production TGUIKit source. Only names and test bookkeeping accessors change. This isolates this pass from the earlier TextViewLayer extraction and chat metadata migration. The original `bce10beff` renderer comparisons also continue to run.

A new 600-case matrix compares full, nonblank bitmaps exactly: five fixtures (plain, LTR quotes, RTL quotes, mixed-direction quotes and code blocks), three scales, five primary selections, four additional-selection arrays, and selectable/nonselectable views. It covers missing and zero-length selections, overlapping/reversed-order additional highlights, and selections spanning lines. Quote fixtures assert that they contain 14 distinct blocks. Adjacent quote attributes initially coalesced into one block; unquoted separator lines correct that fixture. Render bounds are asserted large enough for every complete layout.

All 10 functional lab tests pass in debug, release and Address Sanitizer, with two optional benchmarks skipped. This includes the previous 1,681 bitmap comparisons plus the new 600 comparisons. The shared TGUIKit suite also passes 216 functional tests, with two optional tests skipped. Production interaction, accessibility, layout measurement and view/layer hierarchy code are untouched.

## Benchmark

`results.json` contains all nine alternating batches of 1,000 redraws per implementation. Both variants draw real CoreText/AppKit content into the same-size reusable bitmap context. Assertions ensure the complete layout fits. Runs are optimized builds on Apple Silicon and start after compilation and other tests finish. Unselected text is effectively unchanged; the useful gain is on multiple highlighted ranges, where the renderer avoids querying alignment for every unselected line of every range. These are isolated draw timings, not app-wide frame rates or measured resident-memory savings.


| Path | Before (µs) | After (µs) |
|---|---:|---:|
| plain_short | 1.595 | 1.566 |
| plain_long | 58.839 | 58.753 |
| many_quotes_ltr | 487.646 | 482.661 |
| many_quotes_rtl | 443.838 | 444.291 |
| selected_tail | 61.530 | 60.476 |
| additional_selections | 106.098 | 94.202 |

Multiple additional selections improve by about 11.2%; a tail selection by 1.7%. The other timings are effectively flat at this scale.

## Run

```sh
python3 tools/perflab/TextViewLayerLab/prepare.py /tmp/TextViewLayerLab-work
swift test --package-path /tmp/TextViewLayerLab-work/TextViewLayerLab --scratch-path /tmp/TextViewLayerLab-debug
swift test -c release --package-path /tmp/TextViewLayerLab-work/TextViewLayerLab --scratch-path /tmp/TextViewLayerLab-release
swift test --sanitize address --package-path /tmp/TextViewLayerLab-work/TextViewLayerLab --scratch-path /tmp/TextViewLayerLab-asan
SELECTION_WORK_BENCHMARK=1 swift test -c release --skip-build --package-path /tmp/TextViewLayerLab-work/TextViewLayerLab --scratch-path /tmp/TextViewLayerLab-release --filter LayerTests.testSelectionWorkBenchmark
```

The benchmark writes `/tmp/selection-work-benchmark.json`. The full Telegram app was not built and live scrolling was not measured. No wider TextView-to-layer replacement is included; the rejected header experiment remains separate.
