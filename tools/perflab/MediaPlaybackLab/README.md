# Chat media playback lifecycle lab

This pass fixes Live Photo playback and removes repeated timer allocation from `ChatInteractiveContentView`.

## Changes

Live Photos use a separate player and explicitly clear the ordinary autoplay-video player. The previous `updatePlayerIfNeeded` returned immediately when that ordinary player was absent, so the Live Photo branch could not run in its normal configuration. It now evaluates either player and applies the same active-window, visible-area, dynamic-content lock and Lite Mode/hover eligibility. Live Photos play once per eligible interval, pause and hide when eligibility ends, and can restart on a later eligible interval. Removing or replacing Live Photo media also cancels its outstanding fetch subscription.

The ordinary video's accessory timer is now created once while playing, instead of on every playing-status update. The existing dispatch timer is rescheduled on each status, preserving the original half-second quiet period and subsequent repeat interval. Pause/buffering and loss of playback eligibility invalidate and clear the timer, allowing a later playing status to create a fresh one. Its callback uses the current media, status and animation flag, checks the player identity, and weakly captures the owner and player. It cannot update a replacement player or retain the old media object. Immediate accessory updates still run for every received status.

## Validation

The harness extracts the production playback protocol, dispatch-timer helper, player wrapper, status handler, playback eligibility handler and Live Photo cleanup method. `Reference.swift.txt` preserves the three previous handlers from `fd83dc917`; both handler variants use the same player wrapper, with a timer protocol allowing the two timer types. Visibility, window key state, player commands and accessory rendering are controlled fixtures. Recording adapters delegate scheduling to real SwiftSignalKit and dispatch timers; no interval is accelerated. The real `MetaDisposable` and `ActionDisposable` are also used.

Twelve functional tests pass in debug, release and Address Sanitizer. They verify:

- The baseline issues no command for a Live Photo-only view; the candidate seeks to zero with playback enabled exactly once across 1,000 unchanged eligibility updates.
- Offscreen/detached windows, inactive windows, content locks and Lite Mode without hover stop or suppress playback; eligible transitions restart once.
- Ordinary video player command traces and progress visibility match the baseline for all 64 combinations of eligibility inputs.
- 1,000 consecutive playing statuses create 1,000 baseline timers and one candidate timer, with identical immediate accessory updates.
- Both real timers suppress periodic redraws during status updates every 0.1 seconds, then fire after the same 0.5-second quiet period and repeat interval. The candidate reschedules its single source 1,000 times without recreating it.
- Paused/buffering states, player replacement, owner destruction, removed media, latest callback data and cancellation of Live Photo fetch/status subscriptions.
- Weak-reference checks show that the candidate timer does not retain replaced media, its owner or its player.

The edited production file passes Swift syntax parsing, and the extracted methods compile and execute. The uninstrumented production timer and player wrapper also pass standalone type checking with real Cocoa/SwiftSignalKit and media type fixtures. The main app, actual media decoding, account-backed fetching and Live Photo visual transitions were not exercised. These tests establish command/lifecycle behavior, not end-to-end playback or scrolling FPS.

## Measurements

Apple Silicon, Swift 6.3.3, optimized build, nine alternating batches of 3,000 status updates after warmup. Values are microseconds per update:

| Scenario | Before | After |
|---|---:|---:|
| Repeated playing status | 0.986 | 0.326 |
| Repeated paused status | 0.035 | 0.037 |
| Alternating playing/paused | 0.471 | 0.483 |
| New player for each update | 3.904 | 4.065 |

Repeated playing-status handling is about 3× faster in this isolated harness. Alternating states cost roughly 0.012 microseconds more per update, and new players about 0.161 microseconds more. The benchmark includes timer-recording instrumentation and lightweight accessory/player fixtures, excludes actual accessory drawing and decoding, and shares the player wrapper between variants. It does not measure full chat status-update latency. The timer allocation reduction is verified independently of timing.

Raw trials and source/test-log hashes are in `results.json`, `provenance.json` and `validation.json`.

## Reproduce

```sh
python3 tools/perflab/MediaPlaybackLab/prepare.py
swift test --package-path tools/perflab/MediaPlaybackLab --scratch-path /tmp/MediaPlaybackLab-debug
swift test -c release --package-path tools/perflab/MediaPlaybackLab --scratch-path /tmp/MediaPlaybackLab-release
swift test --sanitize address --package-path tools/perflab/MediaPlaybackLab --scratch-path /tmp/MediaPlaybackLab-asan
MEDIA_PLAYBACK_BENCHMARK=1 swift test -c release --skip-build --package-path tools/perflab/MediaPlaybackLab --scratch-path /tmp/MediaPlaybackLab-release --filter PlaybackTests.testStatusTimerBenchmark
```

Run the benchmark after builds finish. It writes `/tmp/media-playback-benchmark.json`.
