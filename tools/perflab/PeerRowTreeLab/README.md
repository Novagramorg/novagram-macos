# Peer-row hierarchy updates

`ShortPeerRowView.set(item:)` previously called `addSubview` for both status badges and the activity view on every binding. With multiple controls, those calls repeatedly move each control to the front, firing `viewDidMoveToSuperview` even though the parent is unchanged. This repeats tracking/visibility/observer work and changes the backing-layer hierarchy before returning it to its original order.

The candidate attaches controls only when their parent differs, then checks the desired frontmost sequence once. A correct sequence needs no hierarchy mutations. Changed sequences retain the original right-badge, left-badge, activity order, including when older badges remain attached during fade-out. Empty rows return immediately. A single control uses AppKit's existing fast path for adding an already-frontmost view. All control updates and activity callbacks still execute. No persistent cache or new dependency is introduced.

## Validation

Nine functional tests pass in debug, release, and Address Sanitizer configurations. A tenth test is an opt-in release benchmark.

- Across 1,000 unchanged bindings with three controls, baseline reattachment callbacks total 3,000; the candidate produces zero. All 3,000 control updates still execute.
- All eight presence combinations transition to each other, with immediate and deferred removal at 1×, 2×, and 3× scales. Additional transitions cover repeated state, all controls, no controls, and finishing pending removals.
- 2,402 byte-for-byte, nonblank raster pairs match. Fixtures deliberately overlap colored controls so incorrect stacking changes the image. Six hit-test positions per comparison also match.
- External children and reparented controls restore the baseline order. Selection/theme updates, saved-message rules, activity detach/reuse, window attachment, geometry observer delivery, and object release are covered.
- Production Swift frontend parsing passes in normal and `SHARE` configurations.

`prepare.py` extracts the exact current status and activity binding blocks plus the ordering helper. It verifies the original blocks against `623601c18`. Both implementations use real TGUIKit `Control`, `AnimatableContentObserver`, AppKit view/window lifecycle, and Core Animation layers. Source hashes are recorded in `provenance.json`.

Peer/account/theme data, premium badges, and activity models are small fixtures. Their updates use real controls and observers but do not load Telegram accounts, animated emoji, or activity text. Deferred removal is simulated by retaining the fading control at partial opacity until explicit completion; production animation timing is outside this test. Raster captures initialize the real backing-layer tree in a reusable offscreen window, then render its model layers. These prove hierarchy behavior, not full profile screenshots or compositor performance. The full application was not built.

The nonblank check initially rejected captures of detached layer trees. The helper was corrected to attach them to a window. An initial full run that created a fresh window per capture was stopped because of excessive harness overhead; the final tests reuse one window per test and retain the same matrix. Checked-in logs contain the final successful runs.

## Reproduce

From the repository root:

```sh
python3 tools/perflab/PeerRowTreeLab/prepare.py
swift test --package-path tools/perflab/PeerRowTreeLab --scratch-path /tmp/PeerRowTreeLab-debug
swift test --package-path tools/perflab/PeerRowTreeLab --scratch-path /tmp/PeerRowTreeLab-release -c release
swift test --package-path tools/perflab/PeerRowTreeLab --scratch-path /tmp/PeerRowTreeLab-asan --sanitize address
TREE_BENCHMARK=1 swift test --package-path tools/perflab/PeerRowTreeLab --scratch-path /tmp/PeerRowTreeLab-release -c release --skip-build --filter TreeTests.testBenchmark
swiftc -frontend -parse packages/ShortPeerRow/Sources/ShortPeerRow/ShortPeerRowView.swift
swiftc -frontend -parse -D SHARE packages/ShortPeerRow/Sources/ShortPeerRow/ShortPeerRowView.swift
```

## Performance evidence

Apple Silicon, Swift 6.3.3, release optimization. Each result is the median of five passes of 5,000 bindings, alternating original/candidate order. Compilation and functional tests finish before benchmarking. Except the explicitly attached case, rows are detached from windows. Raw samples and logs are included.

| Binding scenario | Original µs | Candidate µs |
|---|---:|---:|
| Empty row | 0.096 | 0.105 |
| One badge | 0.167 | 0.209 |
| Two badges | 3.052 | 0.471 |
| Two badges and activity | 4.970 | 1.115 |
| Two badges and activity, attached to window | 10.505 | 1.086 |
| Changing presence every binding | 13.255 | 13.525 |
| New row every binding | 78.098 | 79.016 |

These measure the extracted hierarchy binding blocks with lightweight content fixtures, not full row construction, account subscriptions, text measurement, animated emoji decoding, or application FPS. Multiple-control rows benefit from eliminating repeated hierarchy mutations. Empty/single-control rows and content-presence changes retain small key/check overhead; cold construction is effectively unchanged at this scale. A single already-frontmost view was already cheap in AppKit, so the candidate deliberately preserves that fast path.
