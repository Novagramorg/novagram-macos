# Avatar tracking reuse lab

This isolated AppKit fixture compares the captured immediate pre-change `AvatarControl` tracking implementation with the current implementation. The change retains an existing tracking area while attached to a window, removes it when detached, and refreshes tracking from `viewDidMoveToWindow` so ancestor attachment and removal are handled. The original options remain `.cursorUpdate`, `.mouseEnteredAndExited`, `.mouseMoved`, `.activeAlways`, and `.inVisibleRect`. Interaction disabling does not remove tracking, because disabled inner avatars forward events to their enclosing control. Hover scheduling is unchanged.

## Validation status

2026-10-19: the seven functional tests pass in Release, with Address Sanitizer and with Thread Sanitizer (`swift test ... --sanitize address|thread`). One fixture assumption was wrong on macOS 14+: views no longer clip to their bounds, so `visibleRect` of a scrolled-out avatar is not empty; the clipped-scroll test now derives visibility from the clip bounds and the avatar frame. Results in `Evidence/avatar-tracking-{forward,reverse}.json`, medians in microseconds per complete row-set operation (original → current):

| Operation | 1 avatar | 50 avatars | 200 avatars |
| --- | ---: | ---: | ---: |
| refresh | 0.245 → 0.024 | 13.8 → 1.0 | 60.0 → 3.9 |
| scroll + refresh | 3.5 → 3.2 | 17.3 → 4.2 | 65.0 → 7.2 |
| ancestor detach + attach | 14.6 → 14.8 | 101.7 → 108.1 (reverse 100.3 → 103.2) | 368.5 → 397.7 (reverse 370.6 → 385.7) |

Refreshing an attached avatar's tracking no longer replaces its area (9–15× less time); a detach/attach cycle costs 1–8 % more because `viewDidMoveToWindow` now refreshes tracking itself (about 1–2 µs per avatar). The app's Debug builds used for the 2026-10-19 chat measurements already contained this change.

Functional coverage includes:

- Tracking identity and exact options across 100 refreshes, with the captured implementation replacing its area on every refresh.
- Attachment through an ancestor, detached ancestor reparenting, same-window reparenting, migration between windows, and final detachment.
- Real scroll clipping and resize geometry, including zero size.
- Disabled event forwarding through registered tracking-area owners, with a deliberate registration-removal mutation proving why tracking cannot be pruned when interaction is disabled.
- Enabled single/double click callbacks, disabled click forwarding through actual hit testing, and inherited accessibility parity.
- Preservation of the image-display lifecycle callback invocation and release of detached avatars and tracking areas.

## Reproduction

Create a fresh immutable fixture before executing checks:

```sh
python3 tools/perflab/AvatarTrackingLab/prepare-isolated.py /tmp/AvatarTrackingCheck
swift test --package-path /tmp/AvatarTrackingCheck --scratch-path /tmp/AvatarTrackingCheck-release -c release
swift test --package-path /tmp/AvatarTrackingCheck --scratch-path /tmp/AvatarTrackingCheck-asan -c release --sanitize address
swift test --package-path /tmp/AvatarTrackingCheck --scratch-path /tmp/AvatarTrackingCheck-tsan -c release --sanitize thread
```

Run timing separately from sanitizer and compiler activity. Each invocation runs nine alternating batches after 20 warmup iterations. The reverse invocation starts each pair in the opposite order in a fresh process:

```sh
AVATAR_TRACKING_BENCHMARK=1 AVATAR_TRACKING_OUTPUT=/tmp/avatar-tracking-forward.json swift test --package-path /tmp/AvatarTrackingCheck --scratch-path /tmp/AvatarTrackingCheck-release -c release --skip-build --filter AvatarTrackingBenchmarkTests
AVATAR_TRACKING_BENCHMARK=1 AVATAR_TRACKING_REVERSE=1 AVATAR_TRACKING_OUTPUT=/tmp/avatar-tracking-reverse.json swift test --package-path /tmp/AvatarTrackingCheck --scratch-path /tmp/AvatarTrackingCheck-release -c release --skip-build --filter AvatarTrackingBenchmarkTests
```

The benchmark uses independently owned original/current row sets containing 1, 50, or 200 attached avatars. It records raw microseconds per complete row-set operation for explicit refresh, scrolling followed by explicit refresh, and ancestor detach/attach followed by refresh. Timed refresh/scroll batches contain 100 operations; attachment batches contain 30. Add/remove counters are also checked and recorded separately over 100 refreshes. Registration counters are present on both variants during timing, so their callback overhead is included. This is a controlled lifecycle workload, not evidence that AppKit refreshes every avatar on every scrolling frame.

## Source boundaries and remaining integration checks

`Reference/AvatarLayer.swift.txt` is the complete production source captured immediately before this tracking change; `Reference/hashes.json` protects it. The generator extracts the actual initializers, event forwarding and dispatch, tracking, superview/window lifecycle, and deinitializer method bodies from original/current sources. `method-provenance.json` records their hashes. `provenance.json` records source and generated output hashes. The isolated preparation also freezes TGUIKit and records its source hashes; transitive dependencies remain linked from the repository and must remain stable during validation.

The fixture uses real AppKit `NSView`, `NSTrackingArea`, scrolling, hit testing, TGUIKit helpers, and SwiftSignalKit disposables/timers. It excludes account/media state and image rendering. `noteImageDisplayed` is replaced by a counter, so its test checks lifecycle invocation only, not `ScopedImageCache` behavior. The font property is plain storage and the avatar-specific frame override is omitted; AppKit frame/visible-rectangle behavior is exercised directly. These reductions make full avatar construction, object-size, memory-footprint, image rendering, and whole-app FPS claims inappropriate.

The entered-event test manually delivers a valid event through registered tracking-area owners. It proves registration and responder forwarding, including the negative mutation, but does not prove AppKit-generated enter/exit/cursor delivery after clipping or inactive-window transitions. Before shipping, type-check the complete production file against real production dependencies and smoke-test avatar hover/cursor behavior in chat/chat list and peer rows, including clipping, inactive windows, and the disabled inner avatar in `AvatarStoryControl`.
