# Premium status observer and playback lifetime

`PremiumStatusControl` is used in chat rows, the chat list, chat headers, profile headers, peer rows, and other peer displays. Static verified, premium, fake, and scam badges previously allocated animation observers and subscribed to scrolling despite having no animation. The observer now exists only while the control is attached and has an emoji or particle layer.

This pass also fixes three lifecycle problems:

- Removed or replaced emoji stop playing and disconnect their file-update callback before removal. A late file update previously changed a reused control's opacity from 1.0 to 0.4 in the regression test.
- Stopping a real `InlineStickerItemLayer` can restore its preview image. The control preserves the displayed `contents` around this stop so the removal fade keeps the same frame.
- Gift particles use intersection with their own frame to determine visibility. A nonempty `visibleRect` alone is insufficient: the native offscreen test returned `(0, 400, 300, 300)` for a 16-point badge. Particles now stop emitting offscreen, remain active while their larger frame is partly visible, and stop emitting when removed.

## Native validation

`prepare.py` extracts the complete `PremiumStatusControl` class from baseline `df79cde92` and the working tree, changing only class names. Both versions compile against real TGUIKit controls, SimpleLayer, notification observers, and removal animations. Tests use native windows, scroll views, hierarchy changes, visible rectangles, and Core Animation contents.

Account services, peer observation, media files, icons, and animation implementations are fixtures. Emoji fixtures record playback, expose the file-update callback, and model the real layer's preview restoration on stop. Particle fixtures record `isPlaying`; actual emitter simulation and Lottie decoding are outside this harness. Geometry comparisons use fixture icons, not pixel snapshots of production assets. The complete PremiumStatusUI package and Telegram application are not built.

Fourteen functional tests cover static allocation, deferred attachment, animated replacement, tinted selection changes, obsolete callbacks, fade-frame preservation, transition to static content, particle-only content, reuse, Lite mode, key and non-key-capable windows, scrolling, frame changes, particle visibility boundaries, detachment, reparenting, and left-side verification. Sixteen baseline/candidate geometry combinations also check size, opacity, image/emoji/particle placement, and playback state.

The initial eleven tests reproduced 23 baseline failures. A separate late-callback test reproduced four more failures. Review of the real playback implementation led to a further regression test, which caught two preview-frame substitutions in the first candidate; preserving `contents` fixes them.

## Benchmark

Forty controls attach to native scroll views. Each batch posts 1,000 bounds-change notifications; nine paired batches alternate order after warmup. A separate run reverses the initial ordering. Every batch verifies exact playback-write counts, and observer counts are checked outside timed regions. Raw samples and medians are in `results/benchmark-first.json` and `results/benchmark-repeat.json`.

| Animated controls / 40 | Before µs/post, first / repeat | After µs/post, first / repeat | Observer helpers |
|---|---:|---:|---:|
| 0 | 3.060 / 3.089 | 0.116 / 0.116 | 40 → 0 |
| 20 | 3.886 / 3.795 | 2.304 / 2.197 | 40 → 20 |
| 40 | 4.468 / 4.432 | 4.733 / 4.605 | 40 → 40 |

The all-animated case is about 0.17–0.27 µs slower per notification across forty controls in these runs (roughly 4–6%). No notification work is removed in that case. The static and mixed cases reduce dispatch work; the lifecycle fixes also stop obsolete playback and offscreen particle emission. This tradeoff is reported rather than claiming a universal speedup.

These measurements cover notification dispatch and lightweight playback-state decisions. They do not estimate complete chat scrolling, real animation CPU usage, whole-app memory, or frame times. Static controls eliminate their observer helpers and registrations; animated controls retain their original notification sources and delivery mechanism.

## Reproduce

```sh
python3 tools/perflab/PremiumStatusLifecycleLab/prepare.py
swift test --package-path tools/perflab/PremiumStatusLifecycleLab -c release
PREMIUM_STATUS_BENCHMARK=1 swift test --package-path tools/perflab/PremiumStatusLifecycleLab -c release
PREMIUM_STATUS_BENCHMARK=1 PREMIUM_STATUS_REVERSE=1 swift test --package-path tools/perflab/PremiumStatusLifecycleLab -c release
swift test --package-path tools/perflab/PremiumStatusLifecycleLab --sanitize address
swift test --package-path tools/perflab/PremiumStatusLifecycleLab --sanitize thread
swift test --package-path packages/TGUIKit -c release --filter 'AnimatableContentObserverTests|AnimationObserverWorkTests|AnimationObserverLifecycleTests'
```

Use separate scratch paths and sequential builds. Save `/tmp/premium-status-lifecycle-benchmark.json` after each benchmark run. `results/` contains logs, generated source, production changes, hashes, and the final validation record. Whole-file parsing separately checks the production source.

Final checks passed: 14 functional lifecycle tests and 20 existing TGUIKit observer regressions in release; the 14 lifecycle tests also passed under each of Address Sanitizer and Thread Sanitizer. Both final benchmark orders passed all assertions, and whole-file parsing succeeded. No sanitizer errors were reported.
