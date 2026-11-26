# Shared inline-text lifecycle

`InteractiveTextView` and `InlineTextView` previously created their renderer and animation observer eagerly, including for plain text. Both controls subscribed plain text to scroll/window/frame notifications and retained the helpers after clearing embedded content. Their `set` methods did not refresh playback after binding new emoji or changing Lite mode.

The controls now create a renderer only when a measured layout has embedded items and a context, and create an observer only while that renderer is attached to a window. Clearing inline content stops playback, clears the renderer, and releases both helpers before frame changes can deliver an obsolete callback. Binding content refreshes playback immediately; InteractiveTextView refreshes again after centering its child during layout. Embedded avatars and other static items conservatively retain the renderer/observer path because the renderer protocol does not expose animation presence.

A compile error was also found: InlineTextView overrides TextView.viewDidMoveToWindow outside TGUIKit, while the base override was public rather than open. The base method is now open. The harness imports TGUIKit normally in its generated control source, so compiling the complete subclass verifies that access boundary.

## Validation

`prepare.py` copies both complete production control classes, changing only their names to compile reference and candidate together. The baseline is `343bbb304`. Both versions use real TGUIKit text rendering, AppKit windows/scroll views, and the actual selector-based observer. Account context and the renderer protocol are represented by fixtures that record factory calls, binding parameters, playback requests, cleanup, and release. No Lottie decoding or media fetching is tested.

The first compilation reproduced the non-open override error. After correcting the shared base declaration for both reference and candidate, six baseline lifecycle tests produced 26 assertion failures. An intermediate candidate exposed an own-frame notification during clear; cleanup was moved before text-frame changes.

Ten functional tests now cover both controls:

- Plain text avoids renderer and observer construction, including while attached.
- Newly bound emoji gets a playback update immediately, with all inline offsets forwarded unchanged.
- Clear and missing-context paths stop playback before removing/releasing the renderer and observer.
- Repeated embedded content reuses the renderer; Lite-mode changes apply immediately.
- Detached views have no observer; attachment, detachment, and reparenting correctly scope callbacks.
- InteractiveTextView preserves plain-text Lite state and refreshes playback after child centering.
- Plain, long/truncated, and Arabic text match original geometry and pixels: 24 exact raster pairs across 1x and 2x drawing transforms, with nonzero output required. Clearing also preserves original sizing behavior.

These tests compile the complete controls, but not the complete GeneralRows package or application. Hook-backed media behavior is checked at the renderer interface, not with account-backed decoders. Both runtime versions use the corrected shared TextView access declaration; that declaration has no changed method body.

## Measurements and tradeoff

Forty controls are attached to real scroll views. Each batch posts 1,000 bounds notifications; nine alternating paired batches follow warmup. A second run reverses the first measured side. The renderer recorder counts calls without appending event traces during timing. Every batch checks exact callback counts.

Microseconds per notification, first / repeat run:

| Control / embedded count | Baseline | Candidate | Renderer / observer objects |
|---|---:|---:|---:|
| Inline / 0 | 3.364 / 3.409 | 0.122 / 0.122 | 40 / 40 → 0 / 0 |
| Inline / 20 | 3.333 / 3.507 | 1.983 / 2.108 | 40 / 40 → 20 / 20 |
| Inline / 40 | 3.512 / 3.595 | 3.982 / 4.402 | 40 / 40 → 40 / 40 |
| Interactive / 0 | 3.560 / 3.595 | 0.124 / 0.126 | 40 / 40 → 0 / 0 |
| Interactive / 20 | 3.650 / 3.656 | 2.219 / 2.220 | 40 / 40 → 20 / 20 |
| Interactive / 40 | 3.810 / 3.638 | 4.315 / 4.506 | 40 / 40 → 40 / 40 |

The plain case removes all 40,000 renderer callbacks per 1,000 posts and avoids 80 helper objects. The mixed case removes half. Fully embedded controls cost about 0.5–0.9 microseconds more per post across all 40 controls in this minimal-recorder benchmark. Explicitly binding the optional renderer to a local reduced the first candidate's active-path overhead, but did not eliminate it. This tradeoff is retained for the plain/mixed allocation and dispatch reduction, immediate playback correctness, and release on clearing. It is not presented as an across-the-board speedup.

Timings exclude real renderer/decoder work and do not establish app frame times or resident-memory savings. Creation/release and callback counts are verified directly; object byte sizes were not measured.

## Reproduce

```sh
python3 tools/perflab/InlineTextLifecycleLab/prepare.py
swift test --package-path tools/perflab/InlineTextLifecycleLab -c release
INLINE_TEXT_BENCHMARK=1 swift test --package-path tools/perflab/InlineTextLifecycleLab -c release
INLINE_TEXT_BENCHMARK=1 INLINE_TEXT_REVERSE=1 swift test --package-path tools/perflab/InlineTextLifecycleLab -c release
swift test --package-path tools/perflab/InlineTextLifecycleLab --sanitize address
swift test --package-path tools/perflab/InlineTextLifecycleLab --sanitize thread
```

Use separate scratch paths and sequential builds. Raw logs, timing batches, frozen generated classes, source delta, and source hashes are in `results/`. All changed source files are parsed separately. Full TGUIKit and chat-layer regression suites are run after the final source changes.

Validation passed: 515 functional release tests (10 inline-control, 371 TGUIKit, 134 chat-layer), plus all 10 inline-control tests under each of Address Sanitizer and Thread Sanitizer. All changed sources parsed successfully; benchmark-only tests were skipped in sanitizer runs.
