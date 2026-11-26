# Spinner timer and color-cycle work

SpinningProgressView rebuilt twelve alpha-adjusted colors on every 40 ms tick. ProgressIndicator also called startAnimation during geometry and visibility updates, which replaced the timer and reset its phase even when it was already running. Repeated stop calls moved the fade deadline forward. Changing alwaysAnimate did not apply the new policy until another lifecycle event.

## Changes

Steady animation rotates the existing twelve colors. Initial start, direct color assignment, setColor and fading retain their color-recalculation paths. The phase counter is now bounded to the twelve-fin cycle. Repeated starts preserve the running timer and phase; repeated stops preserve the initial fade deadline. Restarting during a fade keeps the original restart behavior. Updating alwaysAnimate immediately reevaluates the existing visibility policy.

No drawing primitive or fin geometry changed. One cache-validity Boolean fits within existing instance padding on the measured platform: both the frozen reference and current view have a 984-byte runtime instance size and a 1,024-byte allocator block. These figures exclude referenced objects and framework storage.

## Evidence and scope

SpinnerLifecycleTests exercise the actual production controls. The frozen complete SpinningProgressView reference comes from commit 4d6b435eb, renamed only to compile beside the current class. Tests access the private SwiftSignalKit timer callback using reflection to drive deterministic ticks without adding production test hooks. Real timer waits exercise fade completion and hidden-window lifecycle. A counting NSColor subclass measures calls to withAlphaComponent; native NSColor values are used in timing and rendering tests.

The initial six regression cases produced seven expected assertion failures against the original production files. The final expanded baseline ran eleven functional cases and produced eleven expected assertions, with zero unexpected failures. The expanded harness also covers dynamic appearance changes, direct color invalidation, fading/restart, bounded phase and timer release. Seventy-five nonblank pixel comparisons match exactly: 72 across normal phases and color changes at 1x/2x, plus three light/dark/light appearance captures.

The ordinary color test performs an initial start and 120 ticks. Calls to withAlphaComponent fall from 1,452 to 12. This counts eliminated requests, not measured heap allocations. During fading, the original twelve-per-tick calculation remains because alpha values change with time.

## Paired release measurements

Nine paired batches alternate reference/current order after warmup. Each batch uses 10,000 steady callbacks or 500 repeated starts. Both implementations use real SwiftSignalKit timers and native TGUIKit/AppKit objects. Timer callbacks are captured once outside timed loops. Autorelease pools bound temporary objects between batches.

| Operation | Reference median | Current median |
| --- | ---: | ---: |
| Steady timer callback | 3.625 µs | 0.352 µs |
| Repeated start on an already-running spinner | 5.690 µs | 0.004 µs |

Steady callback work fell by about 90% in this fixture. At 25 ticks per second, the absolute saving per spinner is small; the change primarily removes repeated color work and timer replacement. It is not an application-wide CPU, power, memory or scrolling-speed measurement.

## Run

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter SpinnerLifecycleTests
SPINNER_BENCHMARK=1 swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter SpinnerLifecycleTests.testTickAndRepeatedStartBenchmark
```

Run benchmarks after other compiler/test work has finished. The JSON report is written to /tmp/spinner-benchmark.json. Full-suite and sanitizer evidence, source hashes and original-source snapshots are archived alongside this document. No full Telegram application build or account/network test is performed by this lab.

Validation uses the current worktree, including unrelated pending changes; it is not a clean-checkout application build.

## Final validation

The complete TGUIKit suite passed all 371 functional tests in release and Address Sanitizer builds (389 total, 18 optional tests skipped). The chat-layer mini-app passed all 134 functional tests in both configurations (148 total, 14 skipped): 505 functional tests per configuration in total. Focused spinner and hidden-container checks passed all 12 functional tests under Thread Sanitizer (13 total, one optional benchmark skipped), with no reported races. Final source hashes remained unchanged throughout these runs.
