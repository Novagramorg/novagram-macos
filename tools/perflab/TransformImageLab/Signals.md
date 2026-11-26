# Image signal ownership during reuse

TransformImageView previously started a replacement signal before installing its disposable and cancelling the previous subscription. SwiftSignalKit can deliver synchronously on the main queue. If an initial image callback cleared, disposed, or rebound the view, the outer start call subsequently installed the obsolete disposable and could cancel the newer subscription. Old callbacks could also overwrite isFullyLoaded or continue with animation and caching after a nested replacement.

The view now increments a signal version and cancels the previous source before starting a replacement. Subscription installation checks that the version is still current; a superseded subscription is disposed instead of replacing the current one. Result delivery and callback continuations also check the version. Image quality and first-image state are committed before invoking image callbacks. Clear cancels before notifying that the image is empty, so a new binding created by that callback survives. A newer binding created by a disposal callback takes precedence over the interrupted operation.

This uses the existing MetaDisposable and one UInt64 version per view. It does not allocate another cancellation container per binding. Like the view's existing AppKit operations, binding and clearing are main-thread operations; background results reach the version checks through deliverOnMainQueue.

## Reproduction and work avoided

Eight initial regression tests failed with 23 assertions on the original implementation. Fourteen final lifecycle tests cover synchronous cached and transformed delivery, callback replacement, disposal, clear, replacement from source disposal, instant clearing, quality visibility, queued cached results, an in-flight background transformation, fully-loaded cache skips, deallocation, and an explicit original-versus-current work-count comparison.

The work-count fixture disposes the view from the first synchronous image callback, then changes its render arguments 100 times. The original view leaves the subscription installed and executes 101 transforms and cache callbacks in total. The current view executes only the initial transform, immediately disposes the source when start returns, and invokes no cache callback after cancellation. This is a regression scenario showing eliminated unwanted work, not a throughput comparison between two correct renderers.

A transformation that was already executing on a background worker is allowed to finish; its stale result cannot update or cache into the new binding. This change does not preempt image decoding or drawing already in progress.

## Normal-path measurements

LegacyImageSignalView.swift captures the complete production implementation from commit 1451533e1. Only class names, a testable import and trailing whitespace are changed. signal-provenance.json records the exact baseline and source hashes.

The release benchmark alternates nine batches of 20,000 operations after 100 warmup operations. Both variants must produce exactly 180,100 matching image notifications or transform cache callbacks, depending on the scenario. Cached cases alternate two actual images; transformed cases return nil after traversing the real signal pipeline, isolating subscription/delivery cost from decoding. These views are not attached to a window, so window-scoped cache scanning is outside this benchmark.

Median microseconds per operation from the repeat run:

| Operation | Original | Current | Difference |
| --- | ---: | ---: | ---: |
| Rebind cached-result signal | 1.0876 | 1.0772 | 1.0% faster |
| Deliver cached stream result | 0.3103 | 0.2896 | 6.7% faster |
| Rebind transformation signal | 4.5285 | 4.4407 | 1.9% faster |
| Deliver transformation stream result | 0.3858 | 0.3857 | Essentially unchanged |

The first uncontended run measured 8.3% faster cached-stream delivery; other cases were within 0.5% of the original. Treat the small rebinding differences as noise. Cached delivery now holds one strong reference to the view during the callback rather than repeatedly loading a weak reference. An earlier run overlapped an unrelated analytics build and was excluded from the reported measurements. No whole-app frame times or memory measurements were collected.

## Validation status

All 281 TGUIKit functional tests (10 optional benchmarks skipped) and all 134 chat mini-app functional tests (14 optional benchmarks skipped) passed in release, totaling 415 functional tests.

The full TGUIKit AddressSanitizer suite is not entirely green. Two runs each had one ControlHoverTests failure: testMovementDoesNotRepeatHoverUntilExitAndReentry at line 79, then testParentEntryCannotReplaceChildHover at line 61. The eight hover tests passed when run in isolation. The fixture waits a fixed 0.4 seconds for a 0.3-second delayed callback; timing sensitivity is a hypothesis, not an established root cause. These existing local hover files were not changed by this pass. Both full runs passed all fourteen new image lifecycle tests and reported no AddressSanitizer memory error. The failed logs and isolated hover result are retained rather than discarded.

All 134 chat mini-app functional tests also passed under AddressSanitizer. No full Telegram build, whole-app frame-time measurement or resident-memory measurement was performed.

```sh
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter 'TransformImageSignalTests|TransformImageAssignmentTests|TransformImageViewTests|ScopedImageCacheTests'
IMAGE_SIGNAL_BENCHMARK=1 swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release -c release --filter TransformImageSignalBenchmarkTests
```

The subsequent hover investigation, fixture isolation and successful full sanitizer reruns are documented in [ControlHoverLab](../ControlHoverLab/README.md). The original failed runs above remain preserved.
