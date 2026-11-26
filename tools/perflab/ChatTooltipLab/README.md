# ChatTooltipLab

This isolated AppKit harness verifies countdown tooltips and binding work without building Telegram or creating an account. `prepare.py` extracts the current tooltip methods from `ChatRightView` and `ChatRowItem`. `Reference.swift.txt` preserves the previous behavior from `9c646ac2a`.

Previously, each message model held a timer, a view-update callback and a duplicate base-date field. A hovered row could be rebound without stopping the previous model's timer, allowing that message to overwrite the new row's tooltip. Media transition copies also called `ChatRightView.set` with the same item and replaced its single callback, stealing countdown updates from the original view. Detaching a view did not cancel its model's timer.

Timers now belong to `ChatRightView`. Rebinding cancels the old timer; mouse exit, window detachment and deinitialization cancel it too. Hidden or clipped views and views no longer under the pointer stop on their next tick. Two views of the same item have independent timers. The model retains only its base date and computes countdown text on request, removing the three stored fields and the callback allocation on every binding. Hovering no longer changes `fullDate`, which is also used by copied-message headers.

The current countdown is shown immediately on hover, updates once per second and returns to the base date after expiry. Repeated mouse movement keeps one timer. Identical tooltip strings are not assigned again to AppKit. Countdown arithmetic widens the timestamp operands before adding them, avoiding the previous Int32 overflow near timestamp limits.

## Validation

Twelve regression tests pass in debug, release and Address Sanitizer configurations. Release additionally runs the optional binding benchmark.

- The preserved baseline reproduces both wrong-message tooltip updates after reuse and stolen callbacks after creating a copied media view.
- Real AppKit attachment/detachment, two views of one item, reattachment, mouse exit/re-entry, hidden ancestors, clipping, expiry, missing countdowns, plain-message reuse, and item/view deallocation are exercised.
- 1,000 repeated bindings and mouse movements retain one timer. KVO records 1,000 native tooltip assignments for repeated baseline binding and zero for the candidate. Changed and nil dates still update correctly.
- Unchanged countdown text does not reassign the native tooltip; changed clock values do.
- Int32 boundary cases produce the expected remaining time without overflow.
- In a 30-message scroll-reuse reproduction using actual one-second repeating timers, the baseline keeps 30 timers active after detachment and fires 30 callbacks during the next 1.3 seconds. The candidate has zero active timers and zero callbacks after detachment.

The harness uses real TGUIKit `View`, AppKit `NSWindow`, and SwiftSignalKit dispatch timers. It substitutes a recording wrapper for the timer type; all other extracted method bodies are unchanged. Most lifecycle tests shorten the timer interval to 10 ms; the 30-message reproduction retains the production one-second interval. The wrapper records starts, cancellation and callbacks without retaining the view or item. Account/message data, localization and pointer position are supplied by fixtures. This does not compile the complete ChatUI package, test real pointer hit testing, or render a full chat. Production files also pass Swift frontend parsing. Full Telegram compilation and app-wide FPS or resident-memory measurements were not performed.

## Binding measurements

Apple Silicon, Swift 6.3.3, optimized build. Median of nine alternating batches of 5,000 bindings, with both views attached to AppKit windows. Times are nanoseconds per tooltip binding and exclude other `ChatRightView.set` work.

| Scenario | Before | After |
|---|---:|---:|
| Same item | 247.575 | 152.092 |
| Different items with the same date | 186.525 | 149.867 |
| Different dates | 141.808 | 179.150 |

Same-item binding is about 1.6× faster; changing dates costs approximately 37 ns more per binding. These sub-microsecond measurements are not whole-row or scrolling speedups. Avoiding stale timers is the larger background-work improvement. Three stored fields are removed from each chat item; a timer reference is added to each status view. No resident-memory reduction is claimed from these tests.

Raw trial data is in `binding-results.json`; the one-second timer reproduction is in `timer-results.json`. Source and generated-code hashes are in `provenance.json`, with test summaries and validation hashes in `validation.json`.

## Run

```sh
python3 tools/perflab/ChatTooltipLab/prepare.py
swift test --package-path tools/perflab/ChatTooltipLab --scratch-path /tmp/ChatTooltipLab-debug
CHAT_TOOLTIP_BENCHMARK=1 swift test -c release --package-path tools/perflab/ChatTooltipLab --scratch-path /tmp/ChatTooltipLab-release
swift test --sanitize address --package-path tools/perflab/ChatTooltipLab --scratch-path /tmp/ChatTooltipLab-asan
```

Tests write `/tmp/chat-tooltip-timers.json`; the optional benchmark writes `/tmp/chat-tooltip-binding-benchmark.json`. Generated sources and build output are ignored.
