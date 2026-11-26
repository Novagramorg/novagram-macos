# Activity indicator playback lab

`ChatActivitiesView` is shared by peer rows and chat activity displays. Its previous `stopAnimation()` only changed `isAnimating`; playback considered window focus alone. Stopped indicators continued animating, and active indicators continued advancing after scrolling outside the viewport. Starting the same type and theme also failed to restore the intent flag after a stop.

The candidate gates its timeline on active intent, key-window eligibility, ancestor visibility, and a nonempty visible rectangle. It updates this gate on scoped scroll/geometry notifications, attachment, reparenting, hiding, layout, and window focus. The observer exists only while activity is requested and the view is attached. Stopping or detaching releases it. Existing keyframes and shapes remain in place when playback freezes, and restarting the same configuration resumes their phase without rebuilding them. A `.none` request stops playback.

## Validation

Eleven functional tests pass in debug, release, and Address Sanitizer builds. One additional benchmark is opt-in. The lab compiles the exact production activity view, indicator layer, theme value, and animation geometry with real TGUIKit/AppKit. Only production type names are prefixed to allow the preserved baseline from `4ae6313e0` to coexist. Account-backed activity-string construction is outside this lab.

Coverage includes:

- Reproduction of the old stopped/offscreen playback bug, stop/restart, `.none`, phase preservation, and shape identity.
- Scrolling out and back, focus changes, zero-sized views, hiding both the view and its ancestor, detach/reattach, and reparenting between scroll containers in the same or different windows.
- Type/theme changes while paused, cleanup after AppKit autorelease pools drain, and 100-row visibility checks across multiple scroll positions.
- Visibility notifications from the production TGUIKit `ScrollView` without custom notification settings.
- 927 byte-for-byte comparisons of sampled typing, recording, uploading, and choosing-sticker images at 1×/2×/3× scales. Every sample also requires nonblank output. These compare model-layer drawings; timing behavior is tested separately.

The existing ShortPeerRow key-window regression now supplies a visible frame, and a same-configuration restart regression was added there. Those package tests were not built as a complete ShortPeerRow target; equivalent behavior is exercised by the isolated lab. Production source passes Swift frontend parsing in normal and `SHARE` configurations.

One initial release build detected an unrelated concurrent edit to TGUIKit/ImageButton.swift and stopped. The retry and final suites passed against the current workspace. Other work was preserved.

## Performance evidence

The opt-in benchmark uses real CARenderer/Metal and the actual indicator layers. It stops eight visible indicators through their public view API, then measures their layers in an isolated render tree. Across three alternating baseline/candidate passes, all 360 sampled frames needed rendering in the original; the candidate needed zero. Each pass warms up for 60 frames. Per-frame timing includes a Metal command-buffer fence and is a component measurement, not application GPU utilization or frame rate.

A separate 100-row scroll stress test uses real AppKit scroll notifications. Only the six visible candidate indicators remain running; all 100 originals keep advancing. Visibility checks add a small CPU cost on active scrolling, recorded alongside the benefit in `benchmark.json`. Stopped rows release the observer and have essentially unchanged scroll cost. The benchmark does not simulate a full chat list, row drawing, account traffic, or the window server's offscreen culling.

Final release measurements on Apple Silicon with Swift 6.3.3:

| Measurement | Original | Candidate |
|---|---:|---:|
| Eight stopped indicators: frames requiring rendering | 360 / 360 | 0 / 360 |
| Mean renderer plus fence time per sampled frame | 205.3 µs | 24.7 µs |
| Scroll notification, 100 active rows | 3.34 µs | 24.53 µs |
| Scroll notification, 100 stopped rows | 3.36 µs | 3.38 µs |
| Running timelines after scrolling 100 active rows | 100 | 6 visible |

Renderer timing averages three passes with execution order alternated. Scroll timings are medians of nine alternating batches of 200 scrolls. The active-row visibility checks add about 21 µs per notification in this stress case; the tests do not establish an app-wide scrolling speedup.

Source hashes, test logs, every scroll timing trial, redraw counts, and render timings are retained. No full Telegram build, live-account scrolling, peak memory, or whole-app frame-rate measurement was performed.

## Reproduce

```sh
python3 tools/perflab/ActivityPlaybackLab/prepare.py
swift test --package-path tools/perflab/ActivityPlaybackLab --scratch-path /tmp/ActivityPlaybackLab-debug
swift test -c release --package-path tools/perflab/ActivityPlaybackLab --scratch-path /tmp/ActivityPlaybackLab-release
swift test --sanitize address --package-path tools/perflab/ActivityPlaybackLab --scratch-path /tmp/ActivityPlaybackLab-asan
ACTIVITY_PLAYBACK_BENCHMARK=1 swift test -c release --skip-build --package-path tools/perflab/ActivityPlaybackLab --scratch-path /tmp/ActivityPlaybackLab-release --filter testPlaybackBenchmark
```

Run the benchmark after all builds finish. It writes `/tmp/activity-playback-benchmark.json` and requires Metal. The lab uses real AppKit windows without presenting them onscreen; its test window supplies focus state so tests do not steal keyboard focus.
