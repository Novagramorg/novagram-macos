# Inline sticker observer lifetime

`InlineStickerView` previously allocated a notification observer for every instance and registered attached views even when `controlContent` was false. Those callbacks immediately returned without doing anything. Callers that own playback include story reaction effects, chat star reaction undo, gift previews, and static star widgets.

The observer is now created only for attached, automatically managed views. Detachment releases it. Automatic playback retains the existing token-based observer, main-queue notification delivery, visibility rule, and special handling for windows that cannot become key. Both constructors and their initial playback behavior remain unchanged. Automatically managed views with `isPlayable: false` continue observing: those callbacks enforce disabled playback if the publicly exposed animation layer is changed elsewhere.

## Native harness

`prepare.py` extracts the complete production `InlineStickerView` class from baseline `828654359` and the working tree, changing only the class names. Both compile against the real TGUIKit `Control`, `SimpleLayer`, and `AnimatableContentTokenObserver`. Tests use native AppKit windows, scroll views, clipping, hierarchy callbacks, and notifications. Account/media types and the animation layer implementation are fixtures: the layer records playback assignments and constructor arguments without fetching or decoding media.

Ten functional tests cover deferred allocation, external playback ownership, attachment/removal/reattachment, key-window changes, non-key-capable windows, real scroll clipping, reparenting, duplicate registration prevention, resize fallback, disabled playback enforcement, constructor/geometry parity, and weak release of views and observers. The unchanged implementation reproduced 12 failed assertions for unwanted allocations, subscriptions, and helper retention. The candidate passes all ten.

Rendering and decoding are untouched by this change; the harness does not validate real Lottie playback or build the complete InlineStickerLayer package or Telegram application.

## Measurements

Forty views attach to real scroll views. Each notification batch posts 1,000 bounds notifications. Nine paired batches alternate order after warmup, followed by a separate run starting in reverse order. Every batch checks the exact number of playback writes. Reflection checks the real observer and token counts outside timed regions. Attachment measurements repeatedly attach and remove each of the same 40 views, 50 cycles per batch, with per-cycle autorelease pools.

| Automatically managed views / 40 | Before µs/post, first / repeat | After µs/post, first / repeat | Observer helpers | Notification tokens |
|---|---:|---:|---:|---:|
| 0 | 5.426 / 5.637 | 0.115 / 0.117 | 40 → 0 | 160 → 0 |
| 20 | 5.975 / 6.041 | 3.307 / 3.234 | 40 → 20 | 160 → 80 |
| 40 | 6.409 / 6.365 | 6.378 / 6.458 | 40 → 40 | 160 → 160 |

| Automatically managed views / 40 | Before µs/attach-remove, first / repeat | After µs/attach-remove, first / repeat |
|---|---:|---:|
| 0 | 11.682 / 11.715 | 6.380 / 6.353 |
| 20 | 11.914 / 11.841 | 9.248 / 9.118 |
| 40 | 11.761 / 11.671 | 11.603 / 11.508 |

The automatically managed case remains near baseline in these runs. Forty unneeded helpers account for 3,200 allocated bytes according to `malloc_size`, excluding token allocations and associated closure/storage costs. This is a targeted removal of idle work, not an estimate of whole-app memory or scrolling improvement. Detached views also retain no helper; reattachment creates one if automatic management is needed.

## Reproduce

```sh
python3 tools/perflab/InlineStickerLifecycleLab/prepare.py
swift test --package-path tools/perflab/InlineStickerLifecycleLab -c release
INLINE_STICKER_BENCHMARK=1 swift test --package-path tools/perflab/InlineStickerLifecycleLab -c release
INLINE_STICKER_BENCHMARK=1 INLINE_STICKER_REVERSE=1 swift test --package-path tools/perflab/InlineStickerLifecycleLab -c release
swift test --package-path tools/perflab/InlineStickerLifecycleLab --sanitize address
swift test --package-path tools/perflab/InlineStickerLifecycleLab --sanitize thread
swift test --package-path packages/TGUIKit -c release --filter 'AnimatableContentObserverTests|AnimationObserverWorkTests|AnimationObserverLifecycleTests'
```

Use separate scratch paths and run sequentially. The benchmark writes raw batches to `/tmp/inline-sticker-benchmark.json`; save each run before repeating. Preserved logs, timings, generated classes, the production delta, and hashes live in `results/`. Source parsing checks the entire production file separately. `results/validation.json` records final check results.

Final validation passed: 10 functional lifecycle tests and 20 existing TGUIKit observer regressions in release, plus the 10 lifecycle tests under each of Address Sanitizer and Thread Sanitizer. Both benchmark orders passed their count assertions, and whole-file parsing passed. No sanitizer failures were reported.
