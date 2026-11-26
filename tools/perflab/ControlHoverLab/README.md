# Control hover isolation and deferred allocation

The earlier full TGUIKit sanitizer runs intermittently missed hover callbacks. The fixtures supplied a synthetic pointer position but still used Control's real NSEvent.pressedMouseButtons input. A held left button makes updateState choose Highlight instead of Hover, preventing the hover timer from being scheduled. A test-local Objective-C method override reproduces this deterministically: the old fixture reports Highlight when it expects Hover. This reproduces one concrete source of the missing-hover assertions; the physical button state was not captured during the earlier failures, so it does not establish the cause of every historical failure.

The fixture now sets canHighlight to false and waits for actual positive hover delivery rather than assuming delivery within 0.4 seconds. Cancellation and non-repetition checks retain a bounded observation interval. Separate tests prove that ordinary production controls still highlight when pressed, and that the isolated fixture delivers hover while the test-local button getter reports a press. The override is restored after each case and never posts mouse events or changes system input state.

The local Control.swift already contained a pending per-control hover fix: mouse movement can start hover when an entered event was missed, unrelated controls cannot cancel one another, controls without LongOver handlers do not create timers, and cancellation occurs on exit, clicking and detachment. This pass validates and commits those hover changes while preserving unrelated event-source tracking in the working tree.

The pending implementation eagerly created a MetaDisposable for every Control. It is now an optional, lazily created holder, allocated only when a hover handler is actually scheduled and reused thereafter. Only two production sites currently register LongOver handlers: ChatInputActionsView and ChatMessageDateHeader. This avoids an unused heap allocation for the many controls that never schedule hover and retains the original reference-sized field. An explored direct Disposable holder also removed the allocation, but uses a wider protocol-reference field; the final optional concrete holder keeps the control's storage compact.

## Baseline and measurements

BeforeControl.swift.txt captures the pre-existing local Control.swift, including the eager per-control holder. It is not pristine HEAD. BeforeTests.swift.txt retains the original local fixtures. LegacyHoverControl.swift reproduces the captured control with renamed classes/handler structs, public event/state enums imported from TGUIKit, a testable import and whitespace normalization. provenance.json records capture, candidate and test hashes. The actual dependency is SwiftSignalKit2/Source, as specified by SSignalKit's package manifest.

The release benchmark alternates nine batches after warmup. It measures 2,000 construction/destruction operations, 20,000 mouse-movement operations without a hover handler, or 5,000 schedule/cancel pairs per batch. It uses actual AppKit controls and invokes their event methods directly with valid synthetic mouse events. Hover scheduling is cancelled before the deadline, and both variants must report zero callbacks.

Median microseconds per operation from the repeat run:

| Operation | Eager holder | Lazy holder |
| --- | ---: | ---: |
| Construct/destroy Control | 5.9635 | 5.8255 |
| Movement without a hover handler | 0.3993 | 0.4014 |
| Schedule/cancel hover | 2.9596 | 2.9194 |

Differences are small: the first run measured 1.1% faster construction, 0.6% faster movement and 0.1% slower schedule/cancel. Treat this as essentially unchanged CPU cost, not a meaningful app-speed percentage.

The allocation check inspects the actual eager holder and uses malloc_size on live objects. Both tested base Control instances occupy 1,280 bytes; the eager MetaDisposable occupies another 48 bytes. The lazy control has no holder until hover is scheduled, saving one allocation and 48 measured object bytes in this fixture. This is an object-allocation measurement, not a resident-memory or whole-app measurement. Once a control schedules hover, its holder is retained for reuse.

Thirteen functional hover tests cover initial movement, unrelated controls, nested controls, non-repetition until reentry, exit cancellation, disabled interaction, click cancellation, fixture isolation from physical buttons, unchanged production pressed-state behavior, delivery under a simulated press, callback reentrancy and deallocation. The original input-isolation failure and final logs are retained under results/.

The complete TGUIKit suite passed all 286 functional tests (11 optional benchmarks skipped) in release and in two consecutive AddressSanitizer runs, with zero failures. The chat mini-app suite also passed all 134 functional tests in release and AddressSanitizer (14 optional benchmarks skipped), for 420 functional tests across the two suites. These runs validate the recorded working-tree sources, including unrelated pending changes; they are not an isolated clean-checkout build. The full Telegram application was not built or benchmarked.

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter ControlHoverTests
CONTROL_HOVER_BENCHMARK=1 swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter ControlHoverBenchmarkTests
```
