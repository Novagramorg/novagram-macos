# Table row menu request lifecycle

TableRowView cancelled menu subscriptions when another menu opened or the row was destroyed, but not when the row was recycled for a different item or detached from its window. Both the menu-item source and the additional-view source could remain subscribed. Reentrant subscription startup could also replace a newer subscription with an older one; reentrant disposal could start an unnecessary third request and cancel the second.

The row now cancels pending sources when its stable ID changes or it leaves its window. Same-ID model refreshes preserve pending requests. A request version prevents superseded factories, startup, delivery and installation from taking ownership again. The pending flag avoids comparing stable IDs after work completes or is cancelled. The existing disposable holder is still allocated only on demand and reused.

Menu callbacks check the identity of the current menu. A late show/close callback from an older menu cannot update or clear a newer menu. Closing the current menu cancels its remaining source subscriptions, preventing later additional-view emissions from reopening it. This change does not explicitly close already-presented menus on a stable-ID change; it cancels pending work. Existing AppMenu presentation/dismissal behavior remains responsible for displayed menu windows.

## Evidence

The initial ten functional tests produced 18 expected assertion failures against the unmodified production source at 2816be920. In particular, both pending subscriptions survived reuse, and reentrant startup cancelled request 2 instead of request 1. The original source and reconstructed initial test harness are archived in results; the final test file adds five cases and uses empty modern menus to exercise real AppMenuController callbacks without displaying a popup.

Fifteen functional cases cover:

- Cancellation of both pending sources on reuse and window detachment.
- Preservation across same-ID refreshes and cancellation on later different-ID reuse.
- Reuse during item/additional-view factories, source startup and menu presentation.
- Newer requests created during source startup or disposal.
- Nested item binding during disposal, and row deallocation.
- Old menu callbacks, cancellation on dismissal, and synchronous source completion.
- A background emission queued for the main thread before the row is rebound.

The tests use real TableRowView, AppMenu and SwiftSignalKit components. They verify subscription disposal and callback ownership, not network cancellation inside every concrete source. They do not present an interactive menu or build the full Telegram application.

## Allocation and binding samples

The opt-in benchmark runs 1,000 warmup pairs and nine batches of 10,000 pairs of real row bindings, alternating between two item IDs. It measures a row that has never opened a menu and one that previously started a pending request. Production was built separately before and after the change. Sources and test setup changed between these builds, so these samples are an overhead check rather than a rigorous CPU speedup claim.

| Scenario | Before median | After median |
| --- | ---: | ---: |
| Menu never used | 0.182 microseconds | 0.168 microseconds |
| Menu previously used | 0.182 microseconds | 0.171 microseconds |
| TableRowView allocation | 896 bytes | 896 bytes |

No foreign Swift compiler/test processes were observed immediately before the baseline benchmark or after either benchmark. These short measurements establish neither a whole-app scrolling gain nor a total memory saving. The direct improvement is that obsolete source subscriptions stop on reuse/detachment instead of continuing until another menu request or row destruction.

## Reproduction

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-menu-release -c release --filter TableRowMenuLifecycleTests
ROW_MENU_BENCHMARK=sample swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-menu-release -c release --filter TableRowMenuLifecycleTests.testBindingCost
```

The benchmark writes /tmp/row-menu-sample.json. The test fixture restores the global legacy-menu setting after each case and closes every created empty menu controller. Tests and benchmarks run against the working tree, including unrelated pending changes; this is not an isolated clean-checkout validation.

## Full-suite validation

TGUIKit passed 321 functional tests in release and AddressSanitizer (336 total, 15 opt-in tests skipped). The chat layer mini-app passed 134 functional tests in each configuration (148 total, 14 opt-in tests skipped). Together, 455 functional tests passed in each configuration. Production and functional test sources were unchanged between these final suite runs.

All 15 new lifecycle tests also passed under ThreadSanitizer (16 total, one opt-in benchmark skipped), with no race reports.
