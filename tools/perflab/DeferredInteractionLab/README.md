# Deferred text and row interaction state

TextView created a MetaDisposable for context menus during construction. TableRowView created two, for context menus and pressure-triggered actions. Most instances can display, scroll and be reused without starting these interactions.

These holders are now optional and allocated immediately before their first subscription. Once allocated, they are retained and reused. Cancellation, replacement, pressure thresholds and event delivery retain their existing ordering. Text reuse and deinitialization cancel existing subscriptions without allocating an unused holder. Table rows without an item do not allocate menu state when asked to show a menu.

## Allocation evidence

The baseline is the committed source at e95bed488. The same opt-in test ran against the original and updated production classes, using malloc_size on live view and holder instances and reflection to identify the actual private holders.

| Idle object | View allocation before / after | Holder allocations before / after | Removed object bytes |
| --- | ---: | ---: | ---: |
| TextView | 1,792 / 1,792 | 1 / 0 | 48 |
| TableRowView | 896 / 896 | 2 / 0 | 96 |

These are allocation sizes on the tested arm64 host, not whole-app resident memory. A holder is allocated when its interaction is first used, so the saving applies to instances that have not used that interaction. The optional reference fields do not increase the measured view allocations.

Construction timing samples are preserved in results/before.json and results/after.json, but are exploratory: other compiler processes were detected at the end of the candidate run. No CPU speedup or regression percentage is established by those timings. The allocation observations are the performance evidence for this change.

## Regression coverage

Five functional tests exercise idle construction and reset; row menu requests without an item; custom and default text-menu request replacement, reuse and deallocation; table-row menu request replacement and deallocation; and pressure scheduling, release cancellation, reuse and immediate deep-click behavior. The pressure test temporarily overrides the event's stage getter inside the test process and restores it afterward. It does not post system input events.

Before the change, the suite produced seven expected allocation assertions while the subscription lifecycle checks passed. Afterward, all five functional tests and the opt-in allocation benchmark passed. The tests use pending menu signals so they can observe cancellation without opening a real menu.

The full TGUIKit suite passed 291 functional tests in release and AddressSanitizer (12 optional benchmarks skipped). The chat mini-app passed 134 functional tests in both configurations (14 optional benchmarks skipped). Together, all 425 functional tests passed in each configuration.

Source hashes, baseline identity and raw logs are retained alongside this document. The suites run against the working tree, which includes unrelated pending changes. This is not an isolated clean-checkout or full Telegram application build.

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter DeferredInteractionTests
DEFERRED_INTERACTION_BENCHMARK=after swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter DeferredInteractionTests
```
