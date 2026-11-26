# TextViewLayerLab

`TextViewLayer` draws an already measured `TextViewLayout` without creating a view, installing tracking areas, setting tooltips, preparing ink views, or changing primary selection. `TextView` uses the same renderer while retaining its input handling, accessibility, embedded content, selection state and subclass drawing hook. Chat metadata layers use the renderer directly instead of rebinding a shared full TextView on every redraw.

This is the renderer foundation. The chat metadata already used layers, so that migration removes one shared TextView and redundant update work; it does not remove one view per timestamp. Plain label migrations must separately preserve accessibility, scale changes, geometry, animations and any embedded content.

## API and ownership

Call `update` with a measured layout. It always invalidates drawing, including when the same mutable layout is rebound. It does not measure text or resize the layer. `textSize` is the logical text viewport; the drawing bounds can be larger to allow glyph overhang. The owner controls frame, scale, accessibility and interaction. Use the main thread as with TextView and the existing UI layer tree.

For a standalone label in a flipped view's layer tree:

```swift
let text = TextViewLayer()
text.update(layout, size: rect.size)
text.bounds = CGRect(origin: .zero, size: rect.size).insetBy(dx: -2, dy: -3)
text.position = CGPoint(x: rect.midX, y: rect.midY)
text.contentsScale = view.backingScaleFactor
view.layer?.addSublayer(text)
```

Keep the logical size, padded bounds and position in sync when resizing, and update `contentsScale` when the host changes displays. A logical wrapper layer, as in `ChatRightTextLayer`, can animate the label without changing the padded drawing layer's bounds origin. `update(nil)` releases the layout and clears the next draw. Layer copies preserve standalone drawing inputs and scale.

The layer is suitable for decorative text. It does not provide TextView's accessibility element, selection interactions, link handling, inline animated emoji overlays, animated spoiler reveal or blurred backgrounds. Existing TextViews keep those behaviors through their shared drawing callback. Standalone output suppresses primary selection by default and retains additional-selection drawing, matching a nonselectable TextView. Interaction owners can enable primary-selection drawing with `isTextSelectable`; the distinct name avoids Quartz/ImageKit’s `NSObject.isSelectable` getter.

## Validation

The preparation script copies actual production TGUIKit sources into a temporary package, and appends the preserved draw method from `bce10beff` as a reference subclass in the same source file. This retains private helper access without widening production APIs. Two reference bookkeeping writes are redirected to test accessors. The current and previous chat text-layer classes are extracted verbatim apart from class renaming. The reference uses current TextView hosting/update code; it isolates drawing changes and the chat wrapper migration, not the entire historical TGUIKit implementation.

Initial foundation validation: nine functional tests passed in debug, release and Address Sanitizer, with one opt-in benchmark skipped. There are 1,680 exact bitmap comparisons across the rendering matrices, plus a copied-layer comparison:

- Existing TextView: 504 comparisons covering 14 text fixtures, three scales, three alignments, two widths and selection states.
- Standalone layer: 504 comparisons including glyph limits and repeated bindings.
- Actual chat metadata wrappers: 600 comparisons across rebindings, resizing and scales, with exact geometry checks.
- Spoiler reveal flags, code/quote blocks, blurred backgrounds and code-header hit rectangles: 48 comparisons.
- Key/nonkey window selection and subclass dispatch: eight comparisons.
- Additional selections, block toggles and remeasurement: 16 comparisons.

Fixtures include RTL, CJK, combining characters, emoji, truncation, font/color changes, underlines, strikethroughs, quotes, code and embedded placeholders. Nonblank assertions cover nonempty ordinary view fixtures. Separate tests cover layout release, selection preservation, mutable layout invalidation and view/closure lifetimes. The new standalone layer copy test caught an initial contents-scale mismatch, which is fixed.

The full TGUIKit suite passes 216 functional tests, with two optional tests skipped. Three focused layer API tests live in the production package. No full Telegram build, live VoiceOver session or end-to-end scrolling measurement was performed. Bitmap equality exercises CoreText drawing directly, not GPU compositing or frame pacing.

## Measurements

See `results.json` for medians and all nine alternating batches of 2,000 operations. Timings measure actual Swift/AppKit/CoreText code in an optimized build. Run CPU benchmarks after builds and other rendering work finish. `view_redraw` compares the preserved draw function against the shared implementation; `timestamp_redraw` and `timestamp_bind` use the extracted old/new production wrappers. Decorative creation and bind/draw scenarios show potential for subsequent migrations; they are not already achieved per-row savings or resident-memory measurements.


| Path | Before (µs) | After (µs) |
|---|---:|---:|
| view_redraw | 3.008 | 3.026 |
| timestamp_redraw | 1.770 | 1.052 |
| timestamp_bind | 0.033 | 0.051 |
| decorative_bind_draw | 1.688 | 0.961 |
| cold_decorative | 17.766 | 0.365 |

Timestamp binds add a small invalidation cost (about 0.02 µs) while redraw avoids full-view update work. The ordinary view renderer is essentially unchanged. These timings are local microbenchmarks, not whole-app speedups.

## Run

```sh
python3 tools/perflab/TextViewLayerLab/prepare.py /tmp/TextViewLayerLab-work
swift test --package-path /tmp/TextViewLayerLab-work/TextViewLayerLab --scratch-path /tmp/TextViewLayerLab-debug
swift test -c release --package-path /tmp/TextViewLayerLab-work/TextViewLayerLab --scratch-path /tmp/TextViewLayerLab-release
swift test --sanitize address --package-path /tmp/TextViewLayerLab-work/TextViewLayerLab --scratch-path /tmp/TextViewLayerLab-asan
TEXT_LAYER_BENCHMARK=1 swift test -c release --skip-build --package-path /tmp/TextViewLayerLab-work/TextViewLayerLab --scratch-path /tmp/TextViewLayerLab-release --filter LayerTests.testBenchmark
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-debug
```

The benchmark writes `/tmp/text-layer-benchmark.json`. Use separate scratch directories for each package, and do not rerun preparation while builds read that copy. `provenance.json` records production/reference hashes. Logs and final measurements are saved alongside this document.

## Mixed view/layer migration limit

The [forwarded-header experiment](experiments/ForwardHeader/README.md) is excluded from production. Its text, accessibility and animation comparisons passed, but an overlapping native sibling exposed different stacking after AppKit reordered the layer tree. The archived fixture deliberately reproduces that failure. The normal renderer lab remains green; the forwarded header remains a TextView until its stacking can also be preserved.

## Subsequent renderer optimization

The [selection/quote traversal pass](selection-work/README.md) removes temporary selection-array construction and unnecessary per-line queries. It adds 600 exact pixel comparisons against the immediately previous renderer, bringing the lab to 10 functional tests and two optional benchmarks. Its measurements and logs are separate from the original foundation results above.
