# Lazy chat swipe containers and gesture-safe dismissal

`ChatRowView` previously allocated a layer-backed `View` for swipe-to-reply even when no swipe ever occurred. Every row layout visited that hidden view. Completed swipes retained the empty container. The old animation completion also removed whichever control was current when it ran, so a second gesture could disappear when the first gesture's animation finished. A reply callback that synchronously started another gesture could have its position reset by the old completion path.

The container is now created on the first valid gesture and released after dismissal. Idle layout and completion do not create views. A new gesture replaces the old container, cancels its row return animation, and installs a fresh control. Dismissal captures weak references to the expected container/control and checks their identity before cleanup. The reply callback is followed by the same identity/state check, preserving a newer gesture. Invalid rows do not shift their content.

## Validation scope

The mini-app compiles the complete production `ChatSwipeToReplyView`, the row's swipe properties/methods, and its swipe layout dispatch against real TGUIKit/AppKit/Core Animation. `prepare.py` extracts these regions from the current source and baseline `4d6b34ae4`; class renaming and visibility adjustments permit both implementations in one test target. A small native row shell and model/theme stand-ins replace unrelated chat machinery. The physical haptic call becomes a counter, allowing exact threshold assertions without triggering hardware.

The baseline reproduces ten failed assertions in seven tests, including premature cleanup of a new gesture, reentrant reply reset, unnecessary allocations, retained containers, and shifting an invalid row. The candidate adds four more functional tests for return-animation cancellation, resize geometry, weak release, and rendering. Nine exact bitmap comparisons cover three gesture distances at 1x/2x/3x. The fixture icon explicitly clears its transparent pixels because `generateImage` supplies an uninitialized drawing buffer.

Tests manually deliver real Core Animation delegate completion callbacks to exercise deterministic overlap order. They also cover duplicate completion, right/left reply thresholds, and haptic crossing counts. This does not replace a full app build, actual trackpad testing, or end-to-end scrolling profiling.

## Measurements

The timing fixture contains a native row shell and the exact swipe state, not a full chat row. Nine alternating batches of 600 constructions are repeated in reverse order. Idle swipe layout is called 60,000 times per batch. Detached-memory measurements retain 3,000 rows in fresh processes after warming both implementations. Layouts, media, and the rest of a real chat row are outside these measurements; fixture percentages must not be reported as whole-row or app-wide gains.

| Fixture measurement | Native, first / reversed | Candidate, first / reversed |
|---|---:|---:|
| Construction, µs per fixture row | 15.38 / 14.09 | 10.84 / 10.19 |
| Idle swipe layout, µs per call | 0.098 / 0.095 | 0.0046 / 0.0043 |
| Incremental memory, 3,000 idle rows | 24.90 / 24.76 MB | 16.78 / 16.79 MB |

The removed allocation saves approximately 2.65–2.71 KB per idle fixture row. Construction saves 3.9–4.5 µs in this shell. These are component-level measurements; full chat rows also construct and update many other objects.

All 11 functional tests pass in release, Address Sanitizer, and Thread Sanitizer. The release timing run executes 13 tests with one memory benchmark skipped; sanitizer runs skip both benchmarks. Whole-file parsing passes and all 409 frozen compiler inputs remain unchanged.

Raw timings, memory samples, test logs, source-region diff, and compiler-input hashes are in `results/`.

## Reproduce

```sh
python3 tools/perflab/ChatReplySwipeLab/prepare.py
swift test --package-path tools/perflab/ChatReplySwipeLab -c release
SWIPE_TIMING=1 swift test --package-path tools/perflab/ChatReplySwipeLab -c release
SWIPE_TIMING=1 SWIPE_REVERSE=1 swift test --package-path tools/perflab/ChatReplySwipeLab -c release
SWIPE_MEMORY=native swift test --package-path tools/perflab/ChatReplySwipeLab -c release --filter BenchmarkTests.testRetainedIdleRowMemory
SWIPE_MEMORY=candidate swift test --package-path tools/perflab/ChatReplySwipeLab -c release --filter BenchmarkTests.testRetainedIdleRowMemory
ASAN_OPTIONS=detect_leaks=0 swift test --package-path tools/perflab/ChatReplySwipeLab --sanitize address
swift test --package-path tools/perflab/ChatReplySwipeLab --sanitize thread
```

Use separate scratch paths and sequential builds. `SWIPE_RESULT_PREFIX` chooses a prefix for JSON measurement files. Timing/memory tests are opt-in and disabled during sanitizer runs. Explicit weak-reference assertions check owned-object release; Address Sanitizer runs with leak detection disabled.
