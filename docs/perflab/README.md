# PerfLab

PerfLab runs scripted performance scenarios inside the real Debug app, signed in to your Debug account, and writes a JSON report per run. Use it to measure a change instead of scrolling by hand.

## Pieces

| Piece | Where | What it does |
|---|---|---|
| `PerfLab` package | `packages/PerfLab` | Frame clock (display link gaps on the main thread), scroll driver (pixel scroll-wheel events at a scripted velocity), process monitor (CPU, main-thread CPU, footprint), report writer |
| Labs | e.g. `packages/EntertainmentUI/Sources/EntertainmentUI/EmojiPanelLab.swift` | Host a real screen in its own window and run named scenarios |
| Hook | `Telegram-Mac/app/AppDelegate.swift` (`#if DEBUG`) | Starts a lab when the app is launched with `-PerfLab <lab>` |
| Runner | `tools/perflab/run.sh` | Launches the Debug app outside Xcode, samples WindowServer CPU and GPU utilization next to it, waits for the lab to quit, prints a summary |

Rendering happens in WindowServer, not in the app, so a placeholder or animation that is expensive to composite does not show up in the app's own CPU or main-thread numbers. `wsCores` and `gpu%` in the summary cover that side.

## Running

1. Build the Debug app (`xcodebuild -workspace Telegram-Mac.xcworkspace -scheme Telegram -configuration Debug build`).
2. Quit any running Debug Telegram. Do not run a lab under Xcode: queue debugging (backtrace recording) and attached lldb distort every number.
3. Leave the Mac alone while it runs. Animated content only plays while the lab window is the key window.

```sh
tools/perflab/run.sh emoji-panel baseline -PerfLabScenarios shimmer,shimmeridle,warm,idle,cold -PerfLabRuns 3
```

Reports go to `~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/debug/perf-lab/` and are copied with the system samples and the summary to `tools/perflab/results/` (ignored by git).

## Launch arguments

| Argument | Default | Meaning |
|---|---|---|
| `-PerfLab <lab>` | | Lab to run; nothing happens without it |
| `-PerfLabScenarios a,b` | lab specific | Scenarios in order |
| `-PerfLabRuns n` | 1 | Runs per scenario |
| `-PerfLabLabel name` | | Goes into the report name |
| `-PerfLabQuit` | | Quit the app when done |
| `-PerfLabStartDelay s` | 4 | Delay after the account context is ready |
| `-PerfLabSpeed x` | 1 | Scales every scroll velocity |

## Emoji panel lab

Hosts `EmojiesController(mode: .emoji)` in a 360x520 window.

| Scenario | What it measures |
|---|---|
| `warm` | Scroll after every visible emoji was loaded |
| `idle` | 8 s without input, everything loaded (animation cost) |
| `shimmer` | Scroll with the panel's emoji caches dropped and fetching disabled: placeholders only |
| `shimmeridle` | 8 s without input on placeholders only |
| `cold` | Scroll with caches dropped and real fetching, then time until every on-screen emoji loaded (`settle`) |

`shimmer`, `shimmeridle` and `cold` delete the panel's emoji files from the Debug account's media cache; they download again when needed.

Extra arguments: `-PerfLabPlaceholder shimmer|static|silhouette` selects the placeholder variant, `-PerfLabIdleSeconds`, `-PerfLabWidth`, `-PerfLabHeight`.

## Metrics

| Key | Meaning |
|---|---|
| `hitches` | Main-thread display-link gaps longer than 1.5 frames |
| `h33` | Gaps longer than 33 ms |
| `hitch%` | Time lost to gaps, percent of the window |
| `cpu` | App CPU, cores |
| `main%` | Main-thread CPU, percent of the window |
| `wsCores` | WindowServer CPU during the window, cores (includes other apps; compare runs, not absolutes) |
| `gpu%` | Average GPU device utilization during the window |
| `vis`, `ph` | On-screen emoji and how many of them are still placeholders |
| `settle`, `phLeft` | Seconds until no on-screen placeholder is left, and how many were left after 20 s |

## RenderBench (offscreen)

`tools/perflab/RenderBench` renders a synthetic emoji panel (360x520 at 2x, 8 per line, 6 sections of 30 lines) with `CARenderer` into a Metal texture and measures render time per frame. It links the real TGUIKit, needs no account or window, and also works with the screen locked.

```sh
cd tools/perflab/RenderBench && swift build -c release
.build/release/RenderBench --variants shimmer,tguikit,loaded --frames 600 --runs 3
.build/release/RenderBench --mode idle
.build/release/RenderBench --compare shimmer,tguikit --size 30 --snapshots /tmp/rb
```

`--compare a,b` renders both variants at the same 31 timestamps across one shimmer cycle and prints the largest channel difference. `--placeholders 0.5` mixes in loaded emoji.

Under `CARenderer`, animations attached before the layer tree joins the renderer never play. Populate the scene after attaching, and flush the transaction after every change.

## GIF panel lab

`-PerfLab gif-panel` hosts `GifKeyboardController` in the same kind of window. Scenarios: `idle` (10 s of playback after a 6 s warm-up) and `scroll`. `-PerfLabGifDecode hw|sw` switches `SoftwareVideoLayerFrameManager.usesHardwareDecoding`. Reports add `gifViews`, `gifsTicking` and `gifsRendering`.

```sh
tools/perflab/run.sh gif-panel hw -PerfLabScenarios idle,scroll -PerfLabRuns 3 -PerfLabGifDecode hw
tools/perflab/run.sh gif-panel sw -PerfLabScenarios idle,scroll -PerfLabRuns 3 -PerfLabGifDecode sw
```

## Call video lab

`-PerfLab call-video` opens a window with a grid of `MetalCallVideoView` tiles, each fed at 30 fps (`-PerfLabFps`) from synthetic NV12 IOSurface buffers through the same texture path as decoded group-call video. Scenario name parts: `g<N>` (tile count, laid out as a square grid in a 1440 pt wide window, `-PerfLabWindowWidth`), a stream size (`180p`, `360p`, `720p`, `1080p`, `portrait` 540x960, `screen` 1660x1076), `fit` (tiles match the stream aspect, so the blurred background is hidden), `rot90`/`rot180`/`rot270`, `mirror`, and `still` (one frame, and the window is captured after warm-up to `call-video-<label>-<scenario>-<W>x<H>.rgba` next to the report). Reports add `deliveredFps`.

Compare two builds by copying the baseline `Telegram.app` into a path that ends in `Debug/Telegram.app` and pointing `PERFLAB_APP` at it. Compare `still` captures with `tools/perflab/compare_rgba.py`, which prints mean and max difference and can write baseline, candidate and amplified-diff PNGs:

```sh
PERFLAB_APP=/path/baseline/Debug/Telegram.app tools/perflab/run.sh call-video base -PerfLabScenarios g9-180p,g4-720p,g4-portrait
tools/perflab/run.sh call-video new -PerfLabScenarios g9-180p,g4-720p,g4-portrait
tools/perflab/run.sh call-video newStill -PerfLabScenarios g4-720p-still,g4-360p-still-rot90 -PerfLabSeconds 2
python3 tools/perflab/compare_rgba.py base.rgba new.rgba /tmp/out
```

## Video player lab

`-PerfLab video-player` resolves a public channel (`-PerfLabChannel`, default `bezposhady`), searches its videos and plays each one in a real `SVideoController` in a 1280x720 window. Scenarios are video kinds: `hls` (files with `application/x-mpegurl` alternatives, played by `HLSVideoJSNativeContentView`) and `direct` (everything else). `-PerfLabVideoCount` picks the newest N of each kind at least `-PerfLabMinDuration` seconds long (default 40); pass `-PerfLabMessageIds a,b,c` to pin the same videos across builds.

Every video runs one script, and each phase is its own report entry named `<kind><index>-<phase>`:
- `open`: time to first frame (`ttffSeconds`);
- `play` (10 s), `paused` (6 s, `positionDrift`), `resume` (5 s);
- `seekForward` to 50% and `seekBack` to 10% (`seekLatency`, `seekLandingError`);
- `scrub`: 12 seeks 120 ms apart across 20–80%, then `scrubSettleLatency`, `scrubLandingError`;
- `rate2x` (6 s);
- `quality`: switch to the lowest HLS level when there is more than one (`qualitySwitchLatency`, `qualityApplied`);
- `afterEnd`: seek to the last 3 s and wait for the end (`endLatency`, `reachedEnd`), then 5 s idle;
- `closed`: 3 s after the controller is released.

Every phase also reports `cpuCores`, `mainThreadBusyPercent`, `footprintMB`, `statusPerSecond` (player status emissions), `positionRate` (1.0 while playing, 2.0 at double speed) and `bufferingSeconds`.

```sh
tools/perflab/run.sh video-player base -PerfLabScenarios hls,direct -PerfLabVideoCount 3
tools/perflab/run.sh video-player new -PerfLabScenarios hls,direct -PerfLabVideoCount 3 -PerfLabMessageIds 45896,45882,45877,45304,45240
```

## Peer media lab

`-PerfLab peer-media` opens a real `PeerInfoController` for a channel (`-PerfLabChannel <username>`, or `-PerfLabPeerTitle <title>` for a local search, default `Код.ру`) and scrolls its Media tab the way a person does. Wheel events are hit-tested at the centre of the profile, so they go through the outer info table, its handoff to the media grid (`PeerMediaBlockRowView`) and then the grid's own table. `-PerfLabWindowWidth`/`-PerfLabWindowHeight` pin the window size; keep them the same across builds, since they set the column count.

| Scenario | What it does |
|---|---|
| `enter` | From the top of the profile, scrolls through the info rows into the media grid (`-PerfLabEnterExtra` px past the handoff) |
| `scroll` | Inside the grid: down `-PerfLabScrollDuration` s at `-PerfLabScrollSpeed` px/s, then back up. The first pass is reported as `scroll-first` |
| `fling` | Same at `-PerfLabFlingSpeed` (8000) for `-PerfLabFlingDuration` (3) s |
| `deep` | `-PerfLabDeepDuration` (20) s at 3000 px/s, well past the loaded history window, then back |
| `settle` | `-PerfLabSettleSteps` jumps of `-PerfLabSettleJump` px, each followed by the time until no visible cell is blank (`settle-step` entries plus a `settle` summary) |
| `verify` | Scrolls the grid to `-PerfLabVerifyOffsets` (default `0,2500,6000,12000,20000`), waits until merges and loading stop, checks the invariants below and saves the grid area as `peer-media-<label>-verify<i>-<W>x<H>.rgba` |

Grid metrics, besides the common ones:

| Key | Meaning |
|---|---|
| `blankPercent`, `maxBlank` | Visible cells without an image, averaged over the pass, and the worst sample |
| `merges`, `mergeMs`, `worstMergeMs` | History transitions applied to the grid table and their main-thread time |
| `locationChanges` | History windows requested by the scroll handler |
| `jumpMerges`, `jumpCells` | Merges that moved or removed cells that were on screen, and how many; `jumps`/`jumpDetails` notes say which rows and how |
| `rowViewsCreated`, `cellsCreated`, `rowsSet` | Row views and cells allocated, and row configurations |
| `maxMissingRows` | Visible rows that had no row view in a sample |
| `distinctMessages` | Photos and videos that were on screen at some point in the pass; compare this rather than `scrolledRange`, because every merge that keeps the position lowers the offset by the rows it removed above |
| `avg_atBottom` | Percent of samples with the grid at the end of the loaded history window, waiting for the next page |

`verify` fails a position (`violations` > 0, details in `problems`) on duplicate or out-of-order messages, a row mixing two months, a month without a header, a partial row anywhere except the last row of a month or the top row of the loaded window, a cell showing a different message than its row item, or a blank cell after settling. A live channel can post between two runs, which shifts the top of the grid; compare captures from runs taken close together, or deeper positions.

The counters behind these metrics are `PeerMediaGridDebug` in PeerMediaUI and exist only in DEBUG.

The grid's table sets `TGClipView.skipsDisplayOnScroll`. AppKit marks a clip view as needing display on every scroll step, and the next display pass then walks every view under it asking whether it needs display; TGClipView draws nothing, so the walk is pure cost (about a quarter of the main thread while scrolling the grid). `-PerfLabClipNoDisplay 1` turns the skip on for every table in a DEBUG build, to measure other screens before enabling it there.

```sh
tools/perflab/run.sh peer-media base -PerfLabScenarios enter,scroll,fling,deep,settle,verify -PerfLabRuns 2 -PerfLabWindowWidth 1000 -PerfLabWindowHeight 1000
PERFLAB_APP=/path/baseline/Debug/Telegram.app tools/perflab/run.sh peer-media old -PerfLabScenarios scroll,verify -PerfLabWindowWidth 1000 -PerfLabWindowHeight 1000
python3 tools/perflab/compare_rgba.py old-verify1.rgba new-verify1.rgba /tmp/out
```

The grid layout itself (month grouping, row chunking, display order and the diff the table applies) is covered by unit tests: `packages/PeerMediaUI/Tests/run-tests.sh`. It runs `xcodebuild test` on the `PeerMediaUITests` workspace scheme and links the native libraries from `core-xprojects`. `swift test` can't resolve the package graph, because `MediaPlayer` refers to a `RingBuffer` package that only the workspace provides.

## DecodeBench (offline)

`tools/perflab/DecodeBench` compiles the app's real decoder files (`SoftwareVideoSource`, `FFMpegMediaVideoFrameDecoder` and helpers, symlinked from `submodules/telegram-ios/submodules/MediaPlayer/Sources`) against the prebuilt FFmpeg in `core-xprojects`. Feed it files copied out of a media cache.

```sh
cd tools/perflab/DecodeBench && swift build -c release
.build/release/DecodeBench scan --input <dir of .mp4> --output gifs.txt
.build/release/DecodeBench decode --input gifs.txt --mode sw|hw --concurrent 12 --frames 200 --threads 3
.build/release/DecodeBench compare --input gifs.txt
.build/release/DecodeBench sequence --input gifs.txt --frames 400
.build/release/DecodeBench webm --input webms.txt --mode create|pool --concurrent 60 --side 60
.build/release/DecodeBench webm-sequence --input webms.txt --frames 200
```

- `decode` reports CPU per decoded frame and footprint while N sources play on 3 threads like the app's worker pool.
- `compare` renders one frame per file from both paths and diffs the pixels. `sequence` and `webm-sequence` compare whole frame sequences across loops: timestamps, loop flags and plane bytes.
- `scan` also prints the declared color tags; VideoToolbox guesses BT.709 for untagged files, which is why the hardware path strips its tags.

## CaptureBench (screen sharing)

`tools/perflab/CaptureBench` is a standalone app (`org.telegram.perflab.capturebench`, signed with the local Apple Development identity so the Screen Recording grant survives rebuilds) that runs tgcalls' real capture code against the prebuilt WebRTC in `core-xprojects`:

- `legacy`: `DesktopCaptureSourceHelper` (CGDisplayStream / CGWindowListCreateImage on the main thread, libyuv scale and I420), as `DesktopSharingCapturer` uses it without ScreenCaptureKit.
- `tgsck`: `tgcalls/platform/darwin/ScreenCaptureKitCapturer.mm`, frames converted with `toI420` like the VP8 path.
- `sck`: a bare ScreenCaptureKit stream scaled to 1920x1080.
- `thumb<fps>` (`thumb24`, `thumb5`): `tgsck` frames halved and fed to WebRTC's OpenH264 encoder configured like the group-call screen-share thumbnail layer (screen-content mode, 75 kbps target, 100 kbps max, frame dropping on), keeping at most `<fps>` frames per second like `CustomSimulcastEncoderAdapter`. The line adds encoder input and output fps, skipped percent, kbps and the OpenH264 skip warnings counted through an `rtc::LogSink`.

Grant it Screen Recording once, then launch it through LaunchServices (a shell-launched binary inherits the terminal's permission):

```sh
tools/perflab/CaptureBench/build.sh
open -W -n --stdout out.jsonl CaptureBench.app --args --scenarios legacy-static,tgsck-static,legacy-busy,tgsck-busy
open -n CaptureBench.app --args --host-window [--resize|--lifecycle|--pattern [--fullscreen]]
open -W -n --stdout out.jsonl CaptureBench.app --args --scenarios legacy-window,tgsck-window
open -W -n --stdout out.jsonl CaptureBench.app --args --scenarios legacy-keep,tgsck-keep
open -W -n --stdout out.jsonl CaptureBench.app --args --scenarios thumb24-scroll,thumb5-scroll,thumb24-busy,thumb5-busy
```

Scenario name parts: `static` (nothing changes), `busy` (an animated window on screen), `scroll` (a window of continuously scrolling text, the worst case for screen-content encoding), `window` (capture the `CaptureBenchHost` window of the host process; WebRTC never lists the capturing process's own windows), `keep` (store the last frame; the run ends with a plane-by-plane parity line between `legacy` and `tgsck`). The host modes resize the window every 4 s, hide/show/exit it (pause and fatal-error checks), or draw a static color pattern for parity.

## ProgressLab (download control)

`tools/perflab/ProgressLab` opens a small borderless window with the real `RadialProgressView` in every configuration the app uses: incoming and outgoing (cut-out) file and voice bubbles, the file thumbnail, photo and video overlays, the 30 pt album overlay, 22 pt and 18 pt controls and the 24 pt streaming control with its own cancel icon. It needs no account.

```sh
cd tools/perflab/ProgressLab && swift build
.build/debug/ProgressLab --out /tmp/plab
.build/debug/ProgressLab --out /tmp/plab --only download,cancel,toggle --range 0.12,0.62
```

Scenarios: `download` (start, progress, finish), `cancel`, `toggle` (download and cancel interrupting each other mid-morph), `upload`, `instant` (remote straight to local), `reduce-motion` and `reuse` (non-animated changes stay immediate). Each one writes `<scenario>.png`, a contact sheet with one row per configuration and one column per sample of the composited window, and adds a section to `report.txt`. The report lists the display-link sample rate, updates and largest per-frame steps for each configuration, and whether the end state is at rest. `--range` zooms the columns into a time window (`<scenario>-zoom.png`), and `--closeup` crops every row tightly around its control so small sizes can be checked for overlaps (`-closeup.png`). The display link follows the key window's screen, and the lab never activates, so it runs at the rate of the menu-bar screen.

## Main app component lab

[MainAppLab](../../tools/perflab/MainAppLab/README.md) is a standalone executable and test suite for date grouping, spoilers, image-cache lifecycle, and hashtag album selection. It compiles the actual production files through relative symlinks, needs no account or Telegram build, and has no telegram-ios dependency. It includes frozen baselines, release benchmarks, regression tests, and sanitizer commands.

```sh
tools/perflab/MainAppLab/run.sh test
tools/perflab/MainAppLab/run.sh bench > /tmp/mainapp-benchmarks.json
```

The lab's README records the measurements, correctness evidence, and remaining full-app validation.

## Adding a lab

Create a `<Name>Lab` next to the screen it measures, parse `PerfLabConfiguration.fromLaunchArguments`, drive the screen with `PerfLabScrollMeasurement` or `PerfLabFrameClock`, record with `PerfLabReport`, and start it from the `#if DEBUG` hook in `AppDelegate`. Put `startUnixTime` and `endUnixTime` in every entry so `merge.py` can attribute the system samples.

## ChatController standalone opening and scrolling lab

`tools/perflab/ChatControllerLab` extracts the current controller selection and scroll-control code into an independent AppKit mini-app, with frozen baselines, randomized transition tests, native table geometry and pixel comparisons, sanitizer runs, and paired text-layout benchmarks. It requires no account or telegram-ios build. See [the lab README](../../tools/perflab/ChatControllerLab/README.md) for commands, measured results, tradeoffs, and remaining full-app validation.

## Text layout measurement lab

[TextLayoutLab](../../tools/perflab/TextLayoutLab/README.md) extracts the production `TextViewLayout` measurement code into a standalone AppKit/Core Text executable. It compares cold and repeated measurements against a frozen baseline, checks randomized Unicode layouts and glyph pixels, runs both sanitizers, and records rejected wrapping and interval-math experiments. It requires no account or telegram-ios build.

## Row parity lab (`chat-navigation` scenario `parity`)

Proves that a row-rendering migration is pixel-identical on real rows of a real chat. For each loaded `ChatRowItem` (up to `-PerfLabParityRows`, default 80) the lab creates the row view four times in a borderless capture window, with `ChatRowView.usesLegacyRowChrome` set to true (native path), false (layer path), true and false again, waits `-PerfLabParityWait` seconds (default 0.7) for media to load, and captures the window through WindowServer (`CGWindowListCreateImage`, so z-order, blur and media are the real composition). Rows whose two native captures differ are self-animating and counted as `unstable`; for the rest the layer capture must equal the native one byte for byte. Differing rows are saved as `parity<i>-legacy.png` / `parity<i>-layers.png` next to the report. `-PerfLabParityMutate <pt>` shifts the hosted layer by that many points in DEBUG to prove the oracle catches a mistake; `-PerfLabParityMutateEmoji <pt>`, `-PerfLabParityMutateAvatar <pt>` and `-PerfLabParityMutateStatus <pt>` shift only the reaction emoji, the reactor avatar container or the sender status. Each path is captured twice, and rows where one path changes between its two captures are listed in the `playback` note (animations started on one path only). `avatarLayers` / `avatarViews` and `statusLayers` / `statusViews` count the reactor avatars and sender statuses found on each path, so a run shows the slice was actually exercised; `replyNodes` / `replyViews` / `replyNodeThumbnails` / `replyViewThumbnails` / `replyHitOK` / `replyHitTotal` cover reply previews (`-PerfLabParityMutateReply <pt>` shifts the reply node, `-PerfLabParityReplyFallback 1` rejects every layer-hosted reply on its first update to exercise the rebuild as a view), `photoLayers` / `photoViews` count chat photos on `TransformImageLayer` vs `TransformImageView` (`-PerfLabParityMutateMedia <pt>` shifts the photo layer) and `snapshotEqual` / `snapshotDifferent` compare the gallery snapshot (`copy()`) of each photo on both paths, `badgeNodes` / `badgeViews` do the same for admin badges, and `badgeHitOK` / `badgeHitTotal` check that the window's hit test reaches each interactive badge node at its center. `-PerfLabParityMutateBadge <pt>` shifts only the badge and its background. Few chats have badges among their loaded rows, so `-PerfLabParityFakeBadge 1` gives every row with a sender name a green rank badge with background (interactive) and `-PerfLabParityFakeBadge 2` a plain gray one (not interactive), both through the item's real badge fields, restored after the run.

```sh
tools/perflab/run.sh chat-navigation parity -PerfLabScenarios parity -PerfLabParityRows 60 -PerfLabPeerTitle "Telegram macOS Talk"
tools/perflab/run.sh chat-navigation parity-saved -PerfLabScenarios parity -PerfLabParityRows 60 -PerfLabSavedMessages 1
tools/perflab/run.sh chat-navigation mutant -PerfLabScenarios parity -PerfLabParityRows 40 -PerfLabParityMutate 1 -PerfLabPeerTitle "Telegram macOS Talk"
```

## Floating avatar parity lab (`chat-navigation` scenario `floatparity`)

Proves that the layer-hosted floating avatars (`ChatFloatingAvatarScene` / `ChatFloatingAvatarNode`) look exactly like the `ChatAvatarView` path in the real chat window. At `-PerfLabFloatPositions` evenly spaced scroll offsets of the loaded history (default 12) the lab rebuilds the chat's floating avatars four times (views, nodes, views, nodes; `ChatFloatingAvatar.usesNodes`), waits `-PerfLabParityWait` (default 0.8 s), and captures the main window through WindowServer, cropped to the avatar column (the table's left inset plus 38 pt, full table height). Positions where one path differs between its two captures are `unstable`; the rest must match byte for byte. `-PerfLabFloatMutate <pt>` shifts every node by that many points in DEBUG as the negative control; `-PerfLabParitySaveAll 1` saves every crop. `avatarNodes` / `avatarViewsNodesPath` / `avatarViewsLegacy` count what each path put on screen (story-ring and video avatars stay views on purpose), `avatarHitOK` / `avatarHitTotal` check that the window's hit test reaches each node at its center, and `viewHitOK` / `viewHitTotal` run the same check on the legacy views (misses are avatars whose center is outside the visible table or under the pinned bar / header; `misses` lists them). The `scroll` scenario takes `-PerfLabFloatNodes 0` to run the view path for A/B.

```sh
tools/perflab/run.sh chat-navigation float -PerfLabScenarios floatparity -PerfLabPeerTitle "Telegram macOS Talk"
tools/perflab/run.sh chat-navigation floatmut -PerfLabScenarios floatparity -PerfLabFloatMutate 1 -PerfLabPeerTitle "Telegram macOS Talk"
```

## View census drawing metrics

The `census` scenario reports `censusDrawingViews`, `censusDrawingMPixels` (backing pixels of visible views on the drawing path, i.e. views with a bitmap backing store) and `censusDrawingClasses` (kilopixels per class). The `rowbacking` scenario that compared table rows with and without a backing store is parked with its patch in `evidence/2026-10-19-table-row-backing-parked`.

