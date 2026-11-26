# Premium status peer observation lab

Premium/verified status controls are reused in peer rows and other screens. Previously each `set` cancelled and recreated a Postbox combined-view subscription, even when the same peer was rebound for selection or presentation changes. In Postbox, subscription creation builds a mutable view and registers it with the view tracker; disposal schedules its removal.

The candidate keeps one subscription when account identity, peer ID, and peer contents are equivalent. It replaces the callback on every binding, so updates use the current selection, color, inline-sticker context, size, animation, Lite Mode, and playback options. Changed caller-provided peer contents still restart observation, preserving the refresh of the authoritative Postbox snapshot. Received updates advance the comparison peer before rendering, allowing the resulting rebind to reuse the subscription.

Disabling automatic updates or releasing the observer cancels the subscription and releases its peer and callback. The subscription's mapping closure captures only the peer ID, so equivalent rebindings can release older peer objects. There is no global cache or retained history. One small observer object per control holds the existing disposable plus the current weak account, peer, callback, and generation.

A generation check also protects replacement during an immediate callback: if that callback disables updates or switches accounts, the outer registration is disposed instead of replacing the newer subscription. A regression reproduces the opposite behavior in the preserved original code. This tests reentrant behavior of the subscription pattern; it is not evidence that a live Postbox database delivers its initial snapshot synchronously.

## Validation

Thirteen functional tests pass in debug, release, and Address Sanitizer builds. One additional benchmark is opt-in. Tests cover:

- 1,000 equivalent bindings retaining one subscription and delivering through the latest callback; the original creates 1,000 subscriptions.
- 1,000 live peer revisions reaching the extracted control binding without creating new subscriptions.
- Account changes, peer changes, changed caller snapshots, disabling/re-enabling, absent peers, and duplicate emissions.
- Background deliveries queued before rebinding, stale deliveries after cancellation, and immediate callback replacement/disable behavior.
- Every presentation parameter forwarded by the actual production callback.
- Release of prior peer objects, replaced callbacks, disabled observations, removed controls, and subscriptions.

`prepare.py` compiles the production observer without changing its implementation, removing only TelegramCore/Postbox imports. It extracts the actual control method signature and callback forwarding into a recording adapter. Foundation, AppKit, and SwiftSignalKit are real; Account, Peer, and the Postbox combined-view publisher are fixtures. `Reference.swift.txt` preserves the old observation block from `904aa8224`, verified against that commit before generation. The baseline replaces the UI-rendering callback with an equivalent test callback.

Both modified production Swift files pass frontend parsing. The complete PremiumStatusUI package, full Telegram app, real database, sticker renderer, UI drawing, live-account scrolling, and peak memory were not tested by this harness. The rendering body is unchanged. Source hashes, logs, and raw trials are included.

## Release measurements

Apple Silicon, Swift 6.3.3. Median microseconds per observation binding, nine alternating batches of 5,000 operations after warmup. The recording Postbox uses real SwiftSignalKit subscriptions and disposal, without database work or UI rendering. Initial snapshot emission is disabled for timings; synchronous and queued delivery are tested separately.

| Scenario | Original µs | Candidate µs |
|---|---:|---:|
| Same peer object | 2.242 | 0.060 |
| Equivalent new peer object | 2.255 | 0.079 |
| Changing peer contents | 2.285 | 2.295 |
| Automatic updates disabled | 0.016 | 0.019 |
| New observer | 2.308 | 2.362 |

Unchanged bindings are about 29–37× faster in this isolated path. Across each warmup-plus-measurement run, subscription starts fall from 50,000 to one. Changing peers stays essentially unchanged; new observers cost about 2% more, and disabled updates add about three nanoseconds. These are not row-binding, scrolling, or app-wide speedups. Removing database registration churn is supported by the production call path and subscription-count tests, not a real-database timing measurement.

## Reproduce

```sh
python3 tools/perflab/PremiumStatusLab/prepare.py
swift test --package-path tools/perflab/PremiumStatusLab --scratch-path /tmp/PremiumStatusLab-debug
swift test -c release --package-path tools/perflab/PremiumStatusLab --scratch-path /tmp/PremiumStatusLab-release
swift test --sanitize address --package-path tools/perflab/PremiumStatusLab --scratch-path /tmp/PremiumStatusLab-asan
PREMIUM_STATUS_BENCHMARK=1 swift test -c release --skip-build --package-path tools/perflab/PremiumStatusLab --scratch-path /tmp/PremiumStatusLab-release --filter testObservationBenchmark
```

Run the benchmark after builds finish. It writes `/tmp/premium-status-benchmark.json`.
