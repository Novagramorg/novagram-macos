# Animation observer lifecycle and table-row scoping

This mini-app compiles real TGUIKit twice. The baseline restores `AnimatableContentObserver.swift` and `TableRowView.swift` from `70b45f289`; all other sources are shared. It creates real AppKit windows and 40 `TableRowView` subclasses, then posts 1,000 geometry notifications per batch, with 100 warm-up posts and nine measured batches. Each row overrides the animation callback with a counter. These numbers measure notification plumbing, not animation rendering or app frame rate.

## Changes

Selector observers no longer retain notification sources through a registrations array. A private forwarding target holds the actual target weakly, so unregistering one helper cannot remove another listener on that target. Rebinding includes view, selector and options in its identity checks, and destruction unregisters its callbacks. Forwarding takes `NSNotification` directly to avoid a Swift notification round trip.

Token observers unregister when a view detaches, replace handlers during unchanged-context updates, and remove tokens on destruction. A registration generation prevents an obsolete callback from invoking the handler for a new context.

Table rows use the scoped observer and update it on superview changes. Missing scroll containers no longer register with `object: nil`, which previously subscribed to geometry changes from every view. Independent subclass listeners survive attachment and rebinding.

## Evidence

`Evidence` contains both benchmark orders, source hashes, and validation summaries. On Apple Silicon with Swift 6.3.3, the first pass measured:

| Scenario | Before, ns/post | After, ns/post | Callbacks per 1,000 posts |
|---|---:|---:|---:|
| Unrelated frame, rows outside a scroll view | 2,276 | 154 | 40,000 → 0 |
| Unrelated bounds, rows outside a scroll view | 2,105 | 170 | 40,000 → 0 |
| One row's frame outside a scroll view | 1,815 | 208 | 41,000 → 1,000 |
| Relevant scroll bounds | 1,958 | 3,099 | 40,000 → 40,000 |
| Relevant document frame | 1,823 | 2,732 | 40,000 → 40,000 |

The reverse-order run confirms the same result: irrelevant posts become 12–15× cheaper, while relevant posts cost approximately 0.8–1.2 microseconds more across all 40 rows. This is a correctness/lifecycle tradeoff, not a speedup for normal scroll notifications. The callback body is deliberately minimal. Every run checks that detached rows receive no further animation callbacks. The baseline removes all 40 independent listeners during attachment; the candidate preserves them.

Ten additional lifecycle regression tests reproduce retained source views and callbacks after detach, and cover retargeting, changed options/selectors, changed handlers, 1,000 unchanged updates, independent listeners, reparenting between scroll views, and release of targets/captured payloads. Existing TGUIKit tests also exercise real AppKit scrolling and resizing. No full Telegram build or resident-memory measurement is claimed.

The complete TGUIKit suite passes in debug and release: 202 tests, including 200 functional tests and two skipped opt-in benchmarks, with zero failures in each configuration. The 15 focused observer and table-scroll tests also pass under Address Sanitizer.

## Reproduce

From the repository root:

```sh
python3 tools/perflab/AnimationObserverLab/prepare.py baseline /tmp/animation-observer-lab/baseline
python3 tools/perflab/AnimationObserverLab/prepare.py candidate /tmp/animation-observer-lab/candidate
swift build -c release --package-path /tmp/animation-observer-lab/baseline/AnimationObserverLab
swift build -c release --package-path /tmp/animation-observer-lab/candidate/AnimationObserverLab
/tmp/animation-observer-lab/baseline/AnimationObserverLab/.build/release/AnimationObserverLab /tmp/observer-before.json
/tmp/animation-observer-lab/candidate/AnimationObserverLab/.build/release/AnimationObserverLab /tmp/observer-after.json
python3 tools/perflab/AnimationObserverLab/compare.py /tmp/observer-before.json /tmp/observer-after.json
swift test --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-debug
swift test -c release --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-release
swift test --sanitize address --package-path packages/TGUIKit --scratch-path /tmp/TGUIKit-goal-asan --filter 'AnimationObserverLifecycleTests|AnimatableContentObserverTests|TableScroll'
```

Wait for builds and other CPU-heavy work to finish before timing. Repeat the measurements in reverse order. Initialization uses placeholder theme images; no image rendering is benchmarked.

A later pass removes redundant hierarchy lookups and defers unused receiver allocation. See [Observer construction and hierarchy lookup work](Work.md) for its measurements and the rejected receiver-consolidation experiment.
