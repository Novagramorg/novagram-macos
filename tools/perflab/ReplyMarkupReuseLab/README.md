# Reply-markup button reuse

ChatRowView.fillReplyMarkup and ChatInputView.needUpdateReplyMarkup previously rebuilt every InteractiveTextView, child TextView, decorative ImageView and inline renderer whenever their node redrew. Measured text and actions already existed, but the native controls were discarded even when the number of buttons was unchanged.

A dedicated ReplyMarkupContainerView now enables reuse of idle button slots within the same account. Redraw updates handlers, text, inline content, background styling and decorative images. It resets masks and corner state before the existing layout logic applies the current rounding. Extra buttons and obsolete icons are removed; removed buttons lose their handlers. Growth allocates only missing slots. Plain View hosts retain reconstruction behavior. A pressed mouse button, highlighted control, active layer animation or account change prevents reuse. Both live chat-row and input-keyboard hosts use the new container. The buttons remain native controls; this is not a layer migration.

The container stores one optional account identifier. No global cache or persistent button pool is introduced. Steady-state view count is unchanged, and retained-process memory was not measured. The gain is reduced allocation and renderer setup during rebinding.

## Validation

The lab compiles the complete production ReplyMarkupNode and InteractiveTextView against real TGUIKit and AppKit. The baseline is 9c2a08831. The button-layout model, account, theme and inline renderer are explicit fixtures; emoji decoding and account-backed actions are not executed. Production node methods and control methods are copied without algorithm changes; only baseline/candidate node and path-helper names differ. generation.json records their hashes.

Eleven functional tests cover repeated redraw, new model/action binding, growth/shrink/removal, icon addition/removal, corner reset, same-account reuse and account isolation, highlighted/animating fallback, plain-host compatibility, Lite mode, inline-renderer cleanup, attached-window playback lifecycle, background blur/style transitions and ownership release. Nine exact raster comparisons cover three scales, RTL/CJK/emoji text, decorative images and square/input/bubble corner modes after rebinding. Nonblank output is required. Physical mouse-button state is conservatively checked in production; tests exercise the separate highlighted/animation exclusions rather than synthesizing system-wide mouse presses.

The original implementation fails seven assertions in the reuse regression: 303 inline-renderer constructions instead of three and replaced button/icon identities. The final candidate passes all 11 tests in release, Address Sanitizer and Thread Sanitizer. Address Sanitizer uses detect_leaks=0; explicit weak-release assertions remain enabled. All 416 frozen source/dependency inputs are unchanged across final validation. The three complete production files pass Swift syntax parsing. The main Telegram application has not been built or interactively validated in this pass.

## Measurements

Nine alternating paired batches follow warmup, with a second run reversing the initial order. Each batch redraws and lays out the same premeasured node 200 times. Views are attached to AppKit windows, layoutSubtreeIfNeeded completes child layout, and the batch flushes Core Animation. The inline renderer records counters without event-array allocations. Values below are microseconds per complete redraw plus layout, first/reversed run.

| Buttons | Embedded fixture | Before µs | After µs |
|---:|---|---:|---:|
| 1 | False | 53.15 / 53.68 | 5.84 / 5.74 |
| 1 | True | 54.71 / 54.52 | 6.10 / 5.90 |
| 6 | False | 294.75 / 304.85 | 29.07 / 29.16 |
| 6 | True | 310.60 / 321.94 | 32.02 / 32.77 |
| 24 | False | 1177.96 / 1208.84 | 113.02 / 113.64 |
| 24 | True | 1258.28 / 1300.65 | 124.79 / 127.09 |

Plain buttons take about 89–91% less redraw time in this workload. The same native controls and decorative images survive repeated redraws, and an embedded button keeps its renderer. These results exclude constructing a new ReplyMarkupNode, network requests, real decoder work and full chat scrolling. They do not establish an app-wide frame-rate or memory percentage.

The first unattached benchmark also improved but is superseded by these attached-window measurements. Raw logs, final timing batches, source delta and input hashes are in results/.

## Reproduce

```sh
python3 tools/perflab/ReplyMarkupReuseLab/prepare.py
MARKUP_BENCHMARK=1 swift test --package-path tools/perflab/ReplyMarkupReuseLab -c release
MARKUP_BENCHMARK=1 MARKUP_REVERSE=1 swift test --package-path tools/perflab/ReplyMarkupReuseLab -c release
ASAN_OPTIONS=detect_leaks=0 swift test --package-path tools/perflab/ReplyMarkupReuseLab --sanitize address
swift test --package-path tools/perflab/ReplyMarkupReuseLab --sanitize thread
```

Use separate scratch paths and sequential builds. Preparing with --baseline reproduces the old node under the candidate name; run MarkupTests/testRepeatedRedrawRetainsButtonsIconsAndInlineRenderer to reproduce the seven failures, then regenerate normally.
