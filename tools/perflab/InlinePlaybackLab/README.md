# Inline emoji visibility lab

Inline emoji in folding message text, shared inline text controls and reply/header text previously requested the same parent view's visible rectangle for every emoji, even while playback was disabled. The shared feature helper now resolves window/Lite Mode eligibility once, skips geometry when playback is disabled, and reuses the last parent's visible rectangle within one update. Current callers group layers by text view. Interleaved parents still get correct geometry, but do not receive the same lookup reduction.

There is no persistent visibility cache, dictionary allocation or retained parent between updates. Layer frames and AppKit intersection semantics are preserved. A layer whose weak parent has disappeared is now marked unplayable instead of retaining its previous playback state. The helper is inlinable across its package boundary and leaves empty collections untouched.

## Validation

`prepare.py` copies the exact production helper and verifies all three integrations. The reference preserves the original loop from `7904949a9`. The harness uses real AppKit windows, scroll views, nested views, Core Animation layers and `visibleRect`. Window key state is controlled by a fixture; sticker decoding/fetching is replaced by a playback-flag recorder with the same changed-value behavior. It does not build the complete app or exercise a real Lottie decoder.

Eight functional tests pass in debug, release and Address Sanitizer. They cover:

- 1,000 seeded scrolling, resizing and frame-change cases with 240 layers, comparing every playback decision with the original loop.
- Exactly one visible-rectangle read for 200 layers sharing a parent, versus 200 before.
- Zero geometry reads in inactive-window, detached-window and Lite Mode updates.
- Empty collections, mixed sticker/avatar layers, interleaved parents, clipping boundaries and fractional intersections.
- Stopping layers when their parent disappears, resuming after reparenting, and release of temporary parent views.

The four changed production Swift files pass syntax parsing. The production helper compiles through the mini-app, including its public inlinable body. Complete account-backed feature modules and the main app were not built. No rendering code changed; the evidence compares playback decisions, not screenshots or end-to-end chat frame rate.

## Measurements

Apple Silicon, Swift 6.3.3, optimized build, nine alternating batches of 3,000 updates after warmup. The hierarchy has eight ancestor views inside a real scroll view. Getter counters are present in both implementations. Values are microseconds per update:

| Emoji layers / mode | Before | After |
|---|---:|---:|
| 0 / active | 0.0105 | 0.0111 |
| 1 / active | 0.0515 | 0.0551 |
| 4 / active | 0.1788 | 0.1322 |
| 16 / active | 0.6630 | 0.4337 |
| 64 / active | 2.7608 | 1.7089 |
| 256 / active | 10.7832 | 7.4087 |
| 64 / changing AppKit scroll position | 6.4797 | 5.7758 |
| 64 / inactive window | 2.8250 | 0.3749 |
| 64 / Lite Mode | 2.8051 | 0.3596 |

The single-emoji path costs about four nanoseconds more. Multiple-emoji updates improve by approximately 1.35–1.62× in this fixture; the pass including actual scroll-position changes improves by about 12%. Disabled playback updates improve by about 7.5–7.8×. These timings exclude emoji decoding, fetching, drawing and the rest of the chat scroll pipeline. The operation-count reduction is independent of those timing limits.

`results.json` contains every timing batch; `provenance.json` and `validation.json` record source and test-log hashes.

## Reproduce

From the repository root:

```sh
python3 tools/perflab/InlinePlaybackLab/prepare.py
swift test --package-path tools/perflab/InlinePlaybackLab --scratch-path /tmp/InlinePlaybackLab-debug
swift test -c release --package-path tools/perflab/InlinePlaybackLab --scratch-path /tmp/InlinePlaybackLab-release
swift test --sanitize address --package-path tools/perflab/InlinePlaybackLab --scratch-path /tmp/InlinePlaybackLab-asan
INLINE_PLAYBACK_BENCHMARK=1 swift test -c release --skip-build --package-path tools/perflab/InlinePlaybackLab --scratch-path /tmp/InlinePlaybackLab-release --filter PlaybackTests.testPlaybackBenchmark
```

Run timing after the builds finish. The benchmark writes `/tmp/inline-playback-benchmark.json`.
