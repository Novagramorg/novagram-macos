# Text context menu request lifecycle

TextView kept its menu subscription when update or set(layout:) replaced the displayed layout, and when its window detached. The default menu callback retained the old layout while waiting for its additional window. Reentrant startup/disposal could also install an older subscription over a newer request. Once a default menu was presented, its Copy action called TextView.copy on the view's current layout, so a reused view could copy different content from the original click.

## Change

A lazy, reusable TextViewMenuState replaces the lazy MetaDisposable. It owns the subscription, request version, weak layout identity, pending text snapshot and weak identity of the latest presented menu. Layout replacement, source-text changes, detachment, another right click and dismissal cancel obsolete work. Factories, deliveries, completion and subscription installation check request ownership. An unchanged layout update preserves its pending menu.

Cancellation clears owned state before invoking disposal callbacks, so callbacks may safely bind new text or start another menu. A close callback from an older menu cannot cancel a newer request or a newer presentation from the same stream. The ordering also preserves menus started by preview disposal and previews started by menu disposal.

Default Copy actions capture the selected attributed text and the original copy callbacks. They continue to target the original content after selection changes or view reuse, instead of consulting the recycled view's layout. Captured callbacks may retain their own application data; the action does not directly retain the old TextViewLayout. Pending snapshots are released on cancellation and completion. Resolved-URL Copy actions capture only the URL and a weak view reference, avoiding unused selected-text and copy-hook retention.

No popup renderer, public package API or source-file membership changes are required. The existing deferred-interaction tests still check lazy creation and holder reuse. Their reflection helper now accepts the Disposable protocol because the text holder is no longer a MetaDisposable; the row/pressure checks remain in place.

## Reproduction and validation scope

The initial 14 functional cases produced 25 expected assertions against the unmodified production source at c65ece0a7. After refining Copy to preserve its original target and extending the tests, the final baseline harness ran 19 functional cases plus its opt-in benchmark and produced 33 expected assertions, zero unexpected failures. The final candidate adds snapshot-attribute release and URL-only action retention cases, for 21 functional tests in total. The URL retention test failed against the intermediate candidate and passes after separating URL actions from attributed-text Copy actions.

The harness covers custom and default requests, both layout setters, unchanged-layout refreshes, layout retention, window detachment, reset during source startup, reentrant startup/disposal/completion, factory rebinding, streaming-menu dismissal, old menu callbacks, background results queued for main-thread delivery, mutable text with and without an update call, captured Copy callbacks and selection, interaction with hover previews, and snapshot-resource release.

Tests invoke the actual TextView and SwiftSignalKit code. A test-local Objective-C replacement captures NSMenu.popUpContextMenu calls without opening a popup, and restores the original implementation after each test. Menu close callbacks are invoked explicitly. Hidden AppKit windows exercise real detachment. Tests do not write to the clipboard: Copy is observed through its supplied callbacks. They do not post system mouse events, perform network requests or build the full Telegram app.

The source versions and regression harnesses used for baseline runs are archived in results. The initial archive includes the allocation benchmark added after the initial regression run; its 14 functional cases are unchanged. The final baseline archive precedes the additional snapshot-release and URL-retention cases. The intermediate candidate that failed URL retention is also archived. Tests run against a worktree containing unrelated pending changes, not an isolated clean checkout.

## Allocation and update samples

The opt-in benchmark performs 1,000 warmup pairs of updates on a real TextView, then nine batches of 5,000 pairs. It measures an unused view and then the holder after the first eligible menu request. Production versions were built separately, so these short samples do not establish a CPU speedup.

| Measurement | Original | Candidate |
| --- | ---: | ---: |
| TextView runtime instance size | 1,584 bytes | 1,584 bytes |
| TextView allocator block | 1,792 bytes | 1,792 bytes |
| Holder before any menu use | None | None |
| Holder after first menu use | 48 bytes | 80 bytes |
| Initial idle-update median | 0.496 microseconds | 0.573 microseconds |
| Additional idle-update sample | 0.565 microseconds | 0.416 microseconds |
| Final candidate idle-update sample | — | 0.575 microseconds |

The holder costs 32 additional allocated bytes for views that have opened a menu. It remains one object and is reused. Object-size figures exclude referenced storage and weak-reference bookkeeping. Pending work also retains a text snapshot, whose backing storage is not included in the holder measurement. Mutable attributed strings require a snapshot copy. This bounded cost is retained for request ownership and stale-content detection.

The direct improvement is cancellation of obsolete subscriptions and release of the old layout/snapshot data, plus correct Copy targets. No total application memory saving, network saving or scrolling percentage was measured. Idle-update timing differences are too small and variable to attribute to this change.

## Running the checks

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-text-menu-release -c release --filter TextViewMenuLifecycleTests
TEXT_MENU_BENCHMARK=sample swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-text-menu-release -c release --filter TextViewMenuLifecycleTests.testMenuStateAllocationAndUpdateCost
```

The benchmark writes /tmp/text-menu-sample.json.

## Final validation

The final source passed all 360 TGUIKit functional tests in release and Address Sanitizer builds (377 total, 17 opt-in tests skipped). The chat-layer mini-app passed all 134 functional tests in both configurations (148 total, 14 skipped). The focused menu suite passed all 21 functional cases under Thread Sanitizer (22 total, one benchmark skipped), with no reported races. The opt-in final allocation benchmark passed separately.

That is 494 functional tests per full configuration. No full Telegram application build was run. Source hashes, exact baseline identity, archived regression failures, final test logs and allocation samples are recorded in provenance.json and results/.
