# Text link preview lifecycle

TextView cleared its remembered link as soon as the hover timer fired. The next movement over the same link disposed the preview subscription and scheduled another timer. This could repeat resolution work or abort an in-flight request. Layout replacement through update or set(layout:), and detachment from a window, did not cancel this work.

The app's link-preview implementation in Telegram-Mac/utils/InAppLinks.swift resolves peer names or invite links, constructs menu items and avatars, and captures the source view in the result callback. An outstanding subscription can therefore retain its source view. The final baseline regression harness reproduces that retention after detachment, using a real SwiftSignalKit subscription with the same ownership pattern.

## Change

A text view now attempts one preview per continuous hover over the same link, including when the handler returns nil. Leaving and re-entering permits another attempt. Changing links cancels the previous request. Movement to a spoiler, formatted date, color marker or block header also cancels pending preview work.

Replacing a layout, changing its attributed text, detaching the view or resetting it for reuse cancels the old timer and subscription. Updating an unchanged layout preserves its preview. The existing timer identifies the pending request, so a factory that changes the layout or starts a new hover cannot install its obsolete returned disposable. Cancellation clears state before calling external disposal code, preserving work that those callbacks start.

The view stores the hovered range and a snapshot of its attributed text instead of an Any link value. The snapshot detects replacement and in-place mutation of attributed strings. An immutable string can reuse its object when copied; a mutable string needs an immutable snapshot during the hover. This is a scoped memory tradeoff, not a claim that previews allocate less memory. No separate request-state object is introduced.

## Regression evidence

The initial nine functional cases produced 15 assertion failures on the unmodified source. After expanding and correcting the harness, all 18 final functional cases and the opt-in benchmark ran against the exact original source at ecddd795f. They produced 29 expected assertions, zero unexpected failures. The final baseline includes direct proof that detachment left the view retained and did not dispose its subscription.

The final harness covers repeated movement over string and Swift-value links; leaving/re-entering; switching links; pending and active work across both layout setters and window detachment; unchanged-layout updates; reentrant factories and disposal; reset interrupted by a newer binding; nil results; spoiler/date transitions; source replacement and mutable attributed strings; and actual subscription retention of the view.

Two intermediate expansions exposed test-fixture issues (an expectation fulfilled more than once and an expectation created in a branch that did not wait for it). These were corrected before the archived final baseline-proof run. The initial and final baseline logs are the reproduction evidence; the intermediate runs are not counted as validation. The final functional harness is the committed TextViewLinkHoverTests.swift.

## Cost and allocation observations

The opt-in test performs 1,000 warmup pairs of real TextView updates, then nine batches of 5,000 pairs. It also observes pending timer identity across 100 cursor checks for both string and Swift-value links. Each source version is built separately, so timing differences are not evidence of a CPU speedup.

| Observation | Original | Candidate |
| --- | ---: | ---: |
| Runtime instance size | 1,592 bytes | 1,584 bytes |
| Allocator block for a TextView | 1,792 bytes | 1,792 bytes |
| Isolated update median | 0.963 microseconds | 0.935 microseconds |
| Pending timer replacements over 100 moves, string/value links | 0 / 0 | 0 / 0 |

The expanded baseline's update median was 0.966 microseconds; the first candidate sample was 1.035 microseconds. The later isolated candidate repeat was 0.935 microseconds. The spread does not establish an update speedup or slowdown. These samples cover idle updates. A separate candidate-only comparison below measures the additional work while a preview is active. Snapshot creation itself is outside those timed update loops.

Both versions already deduplicated movement while a timer was pending. The demonstrated work reduction occurs after the preview fires: the functional scenario starts two previews in the original and one in the candidate after another sequence of same-link movements. Detachment also releases a view that the original kept alive through the subscription. No whole-app memory quantity, network saving or scrolling percentage was measured. The smaller runtime instance does not reduce the measured allocator block on this host.

## Active-hover update tradeoff

The final opt-in benchmark also compares identical candidate views with and without an active preview. They share a mutable attributed-text source, use one-line layouts so their links remain visible in the hidden fixture windows, and alternate nine batches of 1,000 updates after 1,000 warmup pairs. This compares active versus idle candidate state, not old versus new production implementations.

| Source characters | Idle update median | Active update median | Additional time |
| --- | ---: | ---: | ---: |
| 43 | 1.078 microseconds | 1.146 microseconds | 0.068 microseconds |
| 1,035 | 0.941 microseconds | 1.043 microseconds | 0.103 microseconds |
| 8,203 | 1.653 microseconds | 2.020 microseconds | 0.367 microseconds |

The text-snapshot validation adds measurable work to the hovered view's updates. This is retained for correctness with mutable text. These samples do not include rendering multiline messages, network work, snapshot creation or full-app scrolling.

## Reproduction

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-link-hover-release -c release --filter TextViewLinkHoverTests
TEXT_HOVER_BENCHMARK=sample swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-link-hover-release -c release --filter TextViewLinkHoverTests.testAllocationAndUpdateCosts
```

The benchmark writes /tmp/text-hover-sample.json. Tests use hidden AppKit windows, real timers, synthetic events passed directly to the views and real SwiftSignalKit subscriptions. No system mouse events are posted and no network request or visible preview popup is opened. Tests run against a worktree with unrelated pending changes; this is not a clean-checkout or full Telegram build.

## Validation provenance

The full TGUIKit release run passed 339 functional tests (355 total, 16 optional tests skipped). The final benchmark expansion happened afterward; production and every functional test/helper remained byte-for-byte unchanged. The exact pre-expansion harness is archived as baseline-and-release-tests.swift.gz and the expanded benchmark passed separately.

The full TGUIKit AddressSanitizer suite also passed all 339 functional tests. The chat layer mini-app passed 134 functional tests in release and AddressSanitizer (148 total, 14 optional tests skipped). Together, 473 functional tests passed in each configuration.

All 18 new lifecycle tests passed under ThreadSanitizer (19 total, one optional benchmark skipped), with no race reports.
