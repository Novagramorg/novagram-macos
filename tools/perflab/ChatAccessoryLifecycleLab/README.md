# Reply accessory emoji lifecycle and observer work

`ChatAccessoryView` is shared by reply previews, editing/forward panels, URL previews, and other chat accessories. Previously it allocated an animation observer for every instance and subscribed attached plain-text previews to scroll and window notifications. Missing header/message layouts skipped emoji reconciliation entirely, retaining old emoji layers. Playback was updated twice during a model update, before final text positioning.

The change removes and stops obsolete layers, allocates/subscribes the observer only for attached views with inline emoji, releases it when the view detaches or becomes plain, and updates playback once after final positioning. Existing animated previews still use the same shared visibility helper and notification sources. Removed/replaced emoji are explicitly marked unplayable before removal, including reconciliation to a plain layout.

## Native validation

The lab extracts the production header/message reconciliation blocks, lifecycle callbacks, observer code, inline-layer binding method, and update tail verbatim. The baseline is `7a9252645`. `prepare.py` also copies the exact production `InlineStickerPlayback` and `InlineStickerKeyCollection` helpers.

Tests use real AppKit windows, NSScrollView, TextView, Core Animation hierarchy, visible rectangles, and TGUIKit notification observers. Window key state is controlled by a fixture. Account services and emoji decoding are replaced by lightweight fixtures; emoji layers use the same SimpleLayer superclass and record playback state. The fixture updates text frames to exercise ordering but does not compile the entire ChatAccessoryView or account-backed model. Rendering pixels, real Lottie decoder shutdown, and end-to-end app frame times are outside this lab's scope.

The initial eight tests reproduced 14 failures: retained layers after missing text, unused observer subscriptions, duplicate/pre-layout playback passes, and retained observer/layer objects. A first candidate still failed immediate weak-release assertions. The final fixture matches production's SimpleLayer base, and the release test flushes the Core Animation transaction before checking weak references.

Eleven functional tests cover:

- Plain previews allocate no observer and receive no scroll callbacks.
- Missing headers/messages clear the correct emoji layers without disturbing remaining layers.
- Both missing and plain layouts release obsolete emoji and the observer.
- Reused emoji retain layer and observer identity; replaced emoji stop playing.
- Playback updates once after text positioning.
- Key/resign-key notifications, Lite mode changes, clipping, and restored visibility update playback.
- Detached animated views defer observer allocation; attachment/reparenting/detachment maintain the correct notification scope and playback state.

## Measurements

A native benchmark attaches 40 extracted accessories to real scroll views and posts 1,000 bounds-change notifications per batch. Nine alternating paired batches follow warmup; a second run starts each alternating sequence in the opposite order. Every batch verifies exact callback counts. These timings measure notification plumbing and visibility checks with lightweight emoji layers, not decoding or full scrolling.

| Animated previews out of 40 | Before µs/post, first / repeat | After µs/post, first / repeat | Observer objects | Notification tokens |
|---|---:|---:|---:|---:|
| 0 | 6.442 / 6.348 | 0.123 / 0.126 | 40 → 0 | 160 → 0 |
| 20 | 8.240 / 8.461 | 4.898 / 4.941 | 40 → 20 | 160 → 80 |
| 40 | 9.642 / 10.200 | 10.048 / 10.057 | 40 → 40 | 160 → 160 |

Plain previews drop from 40,000 to zero playback callbacks per 1,000 posts; the mixed case drops to 20,000. Fully animated previews retain all 40,000 callbacks and their timing varies around the original cost. The 40 observer helper allocations occupy 3,200 bytes according to `malloc_size`; the plain case eliminates these allocations plus 160 notification tokens and their associated storage. Token memory and total process memory were not measured.

## Reproduce

```sh
python3 tools/perflab/ChatAccessoryLifecycleLab/prepare.py
swift test --package-path tools/perflab/ChatAccessoryLifecycleLab -c release
CHAT_ACCESSORY_BENCHMARK=1 swift test --package-path tools/perflab/ChatAccessoryLifecycleLab -c release
CHAT_ACCESSORY_BENCHMARK=1 CHAT_ACCESSORY_REVERSE=1 swift test --package-path tools/perflab/ChatAccessoryLifecycleLab -c release
swift test --package-path tools/perflab/ChatAccessoryLifecycleLab --sanitize address
swift test --package-path tools/perflab/ChatAccessoryLifecycleLab --sanitize thread
```

Use separate scratch paths and sequential builds. Wait for unrelated compiler activity before benchmarking. Generation/source hashes, extracted code, source delta, raw timing batches, and test logs are preserved in `results/`. The complete production source is syntax-parsed separately. The full Telegram application is not built.

Validation passed: 11 functional accessory tests in release and under each of Address Sanitizer and Thread Sanitizer; 25 existing TGUIKit observer and text-layer regression tests also passed. Both benchmark orders passed exact callback-count checks, and whole-file parsing passed.

## Accessory text and icon layers

Plain accessory headers and message previews now draw directly with `TextViewLayer`. Poll and quote icons use `SimpleLayer`. Custom emoji, spoilers (including revealed spoilers), tooltips, block quotes, and masked/block text retain native `TextView` rendering. The accessory remains a native `Button`; media thumbnails, summary controls, shimmer, and decoration services retain their existing implementations. Existing native text views and drawing layers are reused within each rendering mode, and obsolete emoji layers/observers are removed when switching modes.

The adapter uses one drawing layer per plain label, without a container layer. Its logical text rectangle remains separate from the expanded drawing bounds. Explicit position/bounds animations preserve those drawing insets at the animation endpoint. Native fallback retains its original text rendering and event behavior.

Both helper types live in `ChatAccessoryModel.swift`, so an existing Xcode package source list compiles them with their caller. Sizing uses `TextViewLayer.textSize`; spoiler detection reads the public attributed-string key. Neither accesses fileprivate TGUIKit properties, and no shared-library API changes are needed.

### Full accessory validation

The expanded fixture compiles the complete current `ChatAccessoryView`, `StarsView`, and text/icon helpers against real TGUIKit, alongside the native accessory from `9953e0ace`. The original lifecycle fixture remains pinned to `9953e0ace`; its tests alone do not validate the new view implementation. Account, model, theme, and media services are explicit stand-ins. Test-only accessors expose geometry, observer state, and pattern-image injection without changing production algorithms.

There are 26 functional tests and three opt-in benchmarks. Fifteen tests exercise the full current view/helper: sizing, empty text, concealed/revealed spoiler fallback, block quotes, rich-to-plain transitions, native view reuse, custom emoji/observer cleanup, accessibility, scale changes, click handlers, summary info actions, animation endpoints, and object release. Thirty-seven bitmap pairs match the native baseline exactly: 12 text comparisons at 1x/2x/3x with RTL/CJK/family emoji, 24 poll/quote/style/geometry variants at those scales, and one patterned-background comparison. The snapshot harness preserves existing image contents without drawing them a second time.

The suite uses real AppKit, Core Animation, and Core Text. It does not validate actual account-backed models, decoded Lottie/video output, or a complete Telegram app build. Its results are specific to accessory rendering and must not be presented as app-wide scrolling gains.

### Full accessory measurements

Construction and rebinding use premeasured unique layouts, with native/current batches alternated nine times and repeated in reverse order. Retained-memory measurements create 2,000 detached accessories in separate processes after premeasuring layouts and warming both implementations. This isolates incremental accessory memory; it excludes layout generation, window backing stores, and real emoji decoding.

| Rich previews | Native construction µs | Layer construction µs | Native rebind µs | Layer rebind µs |
|---|---:|---:|---:|---:|
| 0% | 28.73 / 27.99 | 11.33 / 10.77 | 4.25 / 4.13 | 1.96 / 1.93 |
| 50% | 31.26 / 30.66 | 22.86 / 22.58 | 4.80 / 4.71 | 3.79 / 3.64 |
| 100% | 33.48 / 32.59 | 33.79 / 32.80 | 5.23 / 4.90 | 5.28 / 4.91 |

Each pair shows the initial/reversed-order run. Plain construction improves 61–62%; mixed construction improves 26–27%. Fully rich timing is within about 1% of baseline. Incremental plain memory drops 57.7–57.8% (26.54–26.56 MB to 11.21–11.22 MB). Fully rich memory increases 1.0–3.1% (31.01–31.31 MB to 31.62–31.97 MB), a retained-state tradeoff rather than a universal saving.

All 26 functional tests pass in release, Address Sanitizer, and Thread Sanitizer. All 415 frozen compiler inputs remain unchanged; whole-source parsing passes. The release benchmark run executes 29 tests, skips the two inactive benchmarks, and has zero failures. Sanitizers skip all three opt-in benchmarks. Address Sanitizer uses `detect_leaks=0`; explicit weak-release assertions cover accessory-owned objects.

The native path holds three views per plain accessory; the layer path holds one. Fully rich accessories retain all three native views and pay a small adapter-state overhead. Raw timing batches, process-memory samples, validation logs, source hashes, and the final source delta are in `results/text-layers/`.

```sh
python3 tools/perflab/ChatAccessoryLifecycleLab/prepare.py
swift test --package-path tools/perflab/ChatAccessoryLifecycleLab -c release
ACCESSORY_TIMING=1 swift test --package-path tools/perflab/ChatAccessoryLifecycleLab -c release
ACCESSORY_TIMING=1 ACCESSORY_REVERSE=1 swift test --package-path tools/perflab/ChatAccessoryLifecycleLab -c release
ACCESSORY_MEMORY=native swift test --package-path tools/perflab/ChatAccessoryLifecycleLab -c release --filter FullAccessoryBenchmarkTests/testRetainedMemory
ACCESSORY_MEMORY=layers swift test --package-path tools/perflab/ChatAccessoryLifecycleLab -c release --filter FullAccessoryBenchmarkTests/testRetainedMemory
ACCESSORY_MEMORY=native ACCESSORY_RICH=1 swift test --package-path tools/perflab/ChatAccessoryLifecycleLab -c release --filter FullAccessoryBenchmarkTests/testRetainedMemory
ACCESSORY_MEMORY=layers ACCESSORY_RICH=1 swift test --package-path tools/perflab/ChatAccessoryLifecycleLab -c release --filter FullAccessoryBenchmarkTests/testRetainedMemory
```

Use `ACCESSORY_RESULT_PREFIX` to choose a result-file prefix. Run builds and benchmark processes sequentially. Reuse the sanitizer commands above with separate scratch paths; benchmarks stay disabled under sanitizers.
