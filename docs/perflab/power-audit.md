# Power audit (2026-10-11)

Goal: Telegram should use almost no energy in daily use and never show up under "Using Significant Energy".
Branch `power-diet`. Every change needs a measurement or a test that shows the before and after.

## How energy is spent on macOS

| Cost | What causes it | How we see it |
|---|---|---|
| CPU time | work on any thread | `ps -o time`, Time Profiler |
| Wakeups | every timer fire, display-link tick, dispatch hop that wakes a sleeping core | System Trace context switches, `TASK_POWER_INFO` (`task_interrupt_wakeups`, `task_platform_idle_wakeups`) |
| Compositing | any animation, emitter or layer change in a visible window makes WindowServer render a frame | WindowServer CPU, GPU % (`tools/perflab/sysmon.py`) |
| Network radio | every request keeps Wi-Fi out of its low-power state for a while | request counts per minute |

Wakeups matter as much as CPU: a timer that fires and does nothing still pulls a core out of idle.
macOS can only coalesce timers that have leeway. Not one repeating timer in the app or in SwiftSignalKit sets leeway.

## Baseline

Measured 2026-10-11 on an M5 Pro, 120 Hz built-in display, battery.

| Instance | State | CPU | Notes |
|---|---|---|---|
| App Store build 283306 | frontmost, user away for a few seconds | 0.3 % | |
| Debug (beta HEAD + local work) | user typing in a chat, 15 s System Trace | 17 % of one core on workers | 2,200 thread dispatches/s; 570 ms of 15 s in `_internal_searchEmoji` (emoji suggestions decode every installed emoji pack on each keystroke), 740 ms rlottie, 330 ms CoreML model load (QR detector) |

An idle-gated sampler (`scratchpad/power/tools/sampler.py`) logs CPU and idle wakeups per minute together with HID idle time, the frontmost app and the lock state.

## Findings by severity

Severity reflects how often it runs in daily use multiplied by its cost. S1 runs all the time, or on every routine event, for every user.
"Hidden" means it keeps running when the app is hidden, minimized, occluded or the screen is locked.

### S1: always on or on every routine event

| # | Finding | Where | Cost | Fix |
|---|---|---|---|---|
| 1 | `suspendAwareDelay(N)` is not one timer. For N > 4.4 s it fires a 4 s repeating timer (no leeway) that only checks the clock until the deadline. About 45-50 polling loops per account (AccountTaskManager 1-12 h refreshes, story polls, chat themes, disk space, notification permission) are always armed. | `SwiftSignalKit2/Source/Signal_Timing.swift:35` | ~12 wakeups/s per account, hidden | one wall-clock deadline (`schedule(wallDeadline:)` keeps the "fire after sleep" behaviour) with leeway |
| 2 | The shared display link wakes the main thread on every vsync (120 Hz) and skips frames afterwards; 25 fps GIFs and 30 fps loops still cost 120 main wakeups/s | `TGUIKit/Sources/DisplayLinkAnimator.swift:5-303` | 120 wakeups/s whenever anything animates | skip on the CVDisplayLink thread when no request is due; never signal the main queue for a skipped frame |
| 3 | Star-gift emoji status sparkles (`StarsEffectLayer`, CAEmitterLayer) never pause: not on resign key, not when the app is in the background, not in lite mode | `PremiumStatusUI/PremiumStatusControl.swift:17-78, 274` | continuous WindowServer compositing at display rate for every visible collectible status (chat list rows, author names, chat title, own status) | stop the emitter (`birthRate = 0`) with the existing `updateAnimatableContent` gating |
| 4 | Paid-star reaction sparkles (`StarsButtonEffectLayer`) on every message with a star reaction, ungated | `ChatUI/ChatReactionsView.swift:1085`, `StarsUI/StarsWidgets.swift:19` | same as #3, one per visible message | same gating |
| 5 | Reactions and fact-check managers re-add their own batch after every run, forever. Every message with reactions the chat has ever shown (not only visible ones) is re-requested about every 20 s, fact checks every 2 s, while the chat exists, also in background. iOS has no such loop; it re-runs the visible pass every 10 s. | `ChatUI/ChatMessageThrottledProcessingManager.swift:75` | 1 request / 20 s per open chat, growing payload | drop the self re-add; refresh the visible range every 10 s while key and visible (iOS parity) |
| 6 | Chat list rebuilds a whole `ChatListRowItem` (attributed text, 4+ text layouts, badges) on any change of the entry, including partner presence and reaction/view counts of the top message, and measures it twice (`premeasuredWidth` never set) | `ChatListUI/ChatListController.swift:339, 541`, `TGUIKit/TableView.swift:3575` | per presence/typing/reaction event | set `premeasuredWidth`; project the entry to what the row draws |
| 7 | Every `PeerListState` change (typing anywhere, connection status, stories, downloads, search) re-runs the 14-input chat list pipeline and a full diff | `ChatListUI/PeersListController.swift:2653`, `ChatListController.swift:960` | per event, heavy accounts hundreds/min | `map` to a projection + `distinctUntilChanged`; filter activities to loaded peers |
| 8 | No chat list or chat history transition is skipped or coalesced while the window is hidden or occluded | `ChatListController`, `ChatController.applyTransition` | all of the above runs in background | occlusion-aware coalescing (latest transition only) |
| 9 | Settings is loaded at startup and keeps a 14-input pipeline (own presence, stories, balances, sessions) alive offscreen forever | `SettingsUI/AccountViewController.swift:1150` | every emission rebuilds ~30 rows offscreen | subscribe on appear, dispose on disappear |
| 10 | Presence heartbeat every 5 s on main: IOKit idle read + `presentAccountStatus.set(...)` without dedupe, so SharedWakeupManager re-sets 4 promises per account | `Telegram-Mac/app/AppDelegate.swift:1264`, `account/SharedWakeupManager.swift:69` | 0.2 Hz main + re-subscriptions, hidden | `distinctUntilChanged`; leeway |
| 11 | Clock offset recomputed every 5 s on main | `Telegram-Mac/account/AccountContext.swift:813` | 0.2 Hz per account, hidden | leeway / event-driven |
| 12 | Emoji suggestions scan and decode every installed emoji pack on every typing pause (SwiftSignalKit `delay` delays the subscription, so fast typing is already skipped; corrected 2026-10-11) | `ChatUI/ChatInterfaceStateContextQueries.swift:106`, `TelegramCore/SearchStickers.swift:1529` | 570 ms CPU in 15 s of typing, measured on Debug (-Onone; Release is cheaper, confirm before ranking) | delay the start, not the result; index in TelegramCore later |
| 13a | A paused or finished `MediaPlayer` (voice note, music, sound-emoji, recording preview) keeps its AUGraph pulling silence until the player is deallocated; `setRate(0)` never stops the graph | `TelegramMedia/MediaPlayerAudioRenderer.swift:274`, `MediaPlayer.swift:613, 878` | CoreAudio IO stays awake: no audio-hardware idle, coreaudiod CPU | stop the graph after a short grace period while paused, restart on play |
| 13b | The Rust engine pings about every 2-3 s per session while the user is online, and worker/download sessions also get `online` and stay connected 20 min | `mtproto-engine/crates/mtproto-core/src/session/mod.rs:1296-1316, 2887` | network radio and CPU never idle during active use | floor the online keepalive; don't forward `online` to non-main sessions (engine change, needs the engine harness) |
| 13c | Sleep observers are swapped (`willSleep` → wake handler, `didWake` → sleep handler) and the 5 s presence timer re-sets `shouldBeServiceTaskMaster(.always)`, so the display-sleep network pause lasts at most 5 s | `Telegram-Mac/account/SharedWakeupManager.swift:61, 69, 172` | network stays up while the display sleeps | swap, dedupe, respect `isSleeping` |
| 13d | Animated emoji per-frame cost: video emoji ≤ 40 pt (inline text, reactions, emoji panel) are VP9-decoded in software on every frame forever (never cached); tinted emoji (`paintToText`, default statuses) skip the frame cache and rasterize in rlottie every frame; cached frames are re-converted to the display colour space on every loop | `TelegramMedia/LottiePlayer.swift:1800, 1771, 469`, `InlineStickerLayer/InlineStickerItemLayer.swift:778` | full decode/rasterize per frame at up to 30 fps per visible emoji | cache small webm and tinted animations; cache display-converted frames |
| 13e | Spoiler dust emitters (text and media, up to ~14k live particles for a media spoiler) keep simulating after reveal at alpha 0 and when the window is not key | `TGUIKit/InvisibleInkDustView.swift:63-388` | WindowServer particles for every spoiler ever shown in the visible window | `birthRate = 0`/remove on reveal and when not key |

### S2: frequent, conditional, or cheaper per event

| # | Finding | Where | Fix |
|---|---|---|---|
| 13 | Notification pipeline: `combineLatest(messages, reactions)` re-runs the previous batch (avatar render, transactions, tone lookup) on every update batch, also typing-only ones | `Telegram-Mac/account/SharedNotificationManager.swift:409` | merge + filter empty |
| 14 | Dock badge and status-bar icon redrawn (CoreText + 2 bitmaps) on every emission without dedupe, also when the status item is off | `GeneralRows/GlobalBadgeNode.swift:185` | `distinctUntilChanged`, skip when hidden |
| 15 | Voice-chat indicator in chat list rows: endless `DisplayLinkAnimator` rebuilding a CGPath per frame on main | `ChatListUI/GCChatListIndicator.swift:39` | Core Animation path keyframes |
| 16 | Voice-chat header: 30 Hz timer creating a new `DisplayLinkAnimator` per tick even at level 0 | `ChatUI/ChatHeaderController.swift:1943`, `AvatarUI/AvatarContentView.swift:108` | skip unchanged levels, pause when not key |
| 17 | Spinners on 25 Hz timers check only their own `isHidden`; the inline-bot spinner keeps ticking hidden until the chat closes | `TGUIKit/SpinningProgressView.swift:81`, `ChatUI/ChatInputSendButton.swift:347` | stop when hidden or out of window |
| 18 | `FireTimerControl` / `PollTimerView` redraw a bitmap at 120 Hz until the deadline (invite links expiring in days, polls with deadlines) | `TGUIKit/FireTimerControl.swift:254`, `PollTimerView.swift:240` | redraw only when the arc moves a pixel |
| 19 | Slow-mode countdown runs a full interface-state update 5x/s | `ChatUI/ChatController.swift:10915` | 1 Hz on the second boundary |
| 20 | Paused AV1/HLS players keep a 5 Hz `Foundation.Timer` | `TelegramMedia/ChunkMediaPlayerV2.swift:345` | invalidate on pause |
| 21 | Relative-date rows keep ticking at 1 Hz for the row's lifetime | `ChatListUI/ChatListRowItem.swift:2337`, `ChatUI/ChatMessageItem.swift:602` | recompute the period each tick |
| 22 | Gift auction preview 10 Hz for a seconds countdown, never stops | `ChatUI/WPArticleContentView.swift:192` | 1 Hz, stop when finished |
| 23 | HTML bubble 1 Hz stats timer per bubble while the debug overlay is off | `HTMLBubbles/HTMLBubbleView.swift:219` | only with the overlay |
| 24 | Passcode auto-lock polls every 10 s with an account-manager transaction, also without a passcode | `Telegram-Mac/account/SharedNotificationManager.swift:208` | one timer for the remaining time |
| 25 | Draft custom emoji in the input loop forever, also when the window is not key | `InputTextView/UIInputView.swift:57` | key-window gating |
| 26 | Spoiler dust emitters never stop | `TGUIKit/InvisibleInkDustView.swift:127` | stop when not key |
| 27 | Custom emoji in chat list previews, reactions and messages loop forever while the window is key, even with the user away | `InlineStickerItemLayer`, `LottiePlayer.swift` | idle cap: pause loops after N s without input |
| 28 | Context menu polls its parent window at 20 Hz; popovers at 5 Hz | `TGUIKit/AppMenuController.swift:470`, `Popover.swift:312` | observe instead of polling |
| 29 | Battery level polled every 60 s through IOKit, `didSet` runs even when unchanged | `Telegram-Mac/account/SharedAccountContext.swift:275` | skip when the threshold is off |
| 30 | Day-change 60 s timer duplicates the `NSCalendarDayChanged` observer | `TelegramTheme/AppearanceGlobal.swift:80` | remove |
| 31a | `MediaPlayer` `.loop` (autoplay videos, GIFs-as-mp4, video avatars) builds a new frame source, thread and decoder on every loop; `MediaPlayerView` polls frames on a main-queue timer and hops to main per frame | `TelegramMedia/MediaPlayer.swift:871`, `MediaPlayerView.swift:205-361` | loop inside the source; enqueue with `requestMediaDataWhenReady` off main |
| 31b | MediaPlayer views (autoplay, video avatars, round videos) gate on key window only; they keep playing when the key window is on another Space, the display sleeps or the screen is locked with Telegram frontmost | `ChatUI/ChatInteractiveContentView.swift:359`, `ChatAvatarView.swift:152` and 6 more | add the app visibility state |
| 31c | 7 `AVAudioPlayer.prepareToPlay()` at launch whose players are discarded immediately | `Telegram-Mac/app/AppDelegate.swift:415` | delete |
| 31d | Lottie (4) and avatar (5) thread pools at `threadPriority 1.0` with default QoS keep sustained animation work on P-cores | `TelegramMedia/LottiePlayer.swift:67`, `TelegramUtils/PeerAvatarImage.swift:19` | `.utility` QoS (measure frame drops first) |
| 31e | Low Power Mode and thermal state are not observed; lite mode only reads a 60 s battery poll | `Telegram-Mac/account/SharedAccountContext.swift:66` | treat Low Power Mode as lite |
| 31f | Every WAL checkpoint does `F_FULLFSYNC` | `Postbox/SqliteValueBox.swift:627` | durability tradeoff, user decision |
| 31g | Paused ChunkMediaPlayerV2 (AV1, HLS, gallery) and the GIF panel's app-wide bounds/frame observers (`object: nil`) | `ChunkMediaPlayerV2.swift:345`, `TelegramMediaUtils/GIFContainerView.swift:140` | invalidate when paused; observe the enclosing clip view |
| 31 | Poll results: after the elapsed time (not remaining) the refresh drops to a 0.5 s loop until the server reports the poll closed (suspected) | `TelegramCore/AccountViewTracker.swift:549` | verify, then fix upstream |

### Product decisions (not changed without the user)

- "Loop animated stickers" is ignored on purpose since `23cb4f30d bugfix` (`MediaAnimatedStickerView.swift:326`).
- Big emoji statuses in Settings and profiles loop forever (`PremiumStatusControl.swift:241`).
- Custom emoji in chat list previews, custom reactions and messages loop forever (`MessageTextUtils/TextUtils.swift:280`, `GeneralRowsHooksInstall.swift:39`, `ChatReactionsView.swift:203`). Capping to two plays (as chat list statuses already do) is the largest animation saving but changes what users see.
- Group-chat video avatars loop forever at the first (largest) video representation (`ChatUI/ChatAvatarView.swift:45`).
- Online presence flips offline after 30 s without input and back on the next input; hysteresis would save RPCs and forced pings.
- Background polling done by TelegramCore for the whole account (stories every 60 s, channel difference polling) is shared with iOS.

## Proof per fix

| Fix | Proof |
|---|---|
| #1 `suspendAwareDelay` | measured end to end: process wakeups, legacy vs new |
| #2 display link | measured end to end: main deliveries per link mix, old vs new driver |
| #3/#4 sparkles, #13e spoilers | measured end to end: CARenderer frames needing a render; unit tests for the gating |
| #13a audio idle stop | measured end to end: coreaudiod CPU and power assertions; real-renderer test |
| #13d small video emoji | measured end to end: per-frame CPU on 60 real emoji, memory test |
| #5 reactions re-poll, #6 chat list measure | mechanism tests only (no in-app numbers yet) |
| #13 notification pipeline, #23 HTML stats | type-checked only, reasoning in the log |
| #15 voice chat indicator | measured: 20 indicators 6.91 % → 0.26 % CPU (legacy copy in the test) |
| #10 typing indicators | measured: CARenderer keyframes lab, 720 of 720 frames → 0; gating test |
| #17 spinners, #26 read metrics, #7 chat list projection | tests only |
| #14 dock badge, #24 passcode check, #16 silent speakers | type-checked only |

## What users can notice

- Reactions of messages that scrolled out of view are no longer refreshed every 20 s, and nothing is re-polled while Telegram is in the background (iOS behaves the same).
- Gift status and star reaction sparkles stop when Telegram is not focused, the row is not visible, or lite mode for emoji is on; spoiler dust freezes in place when Telegram is not focused.
- Pressing play after more than 3 s of pause restarts the audio output (`AUGraphStart`, a few ms) instead of resuming an output that kept running.
- Typing, recording and sticker-choosing indicators and the voice chat indicator in the chat list freeze on their current frame when Telegram is not focused.
- Read-metric times sent to the server are now added up on events instead of sampled every 0.2 s (differences stay within the old 0.2 s sampling error); nothing on screen changes.
- Small video emoji are written to the frame cache: about 290 KB of disk per emoji, removed after about 2.8 days like every other cached animation.

## Open decisions for the user

- **Network while the display sleeps.** `SharedWakeupManager` observes `willSleep` with the wake handler and `didWake` with the sleep handler (swapped), and the 5 s presence timer re-sets `shouldBeServiceTaskMaster(.always)`, so the display-sleep network pause never lasts more than 5 s. Making it real would stop new-message notifications while the screen is off. Leaving both as they are until decided.
- Capping looping custom emoji in chat list previews, custom reactions and message text (the largest remaining animation cost).
- Honoring the "Loop animated stickers" setting, which `23cb4f30d` turned off on purpose.

## Log

Each fix: what, proof, result.

### #1 `suspendAwareDelay` (telegram-ios `a1a9b16495`, branch `power-diet`, needs a submodule bump)

One wall-clock `DispatchSource` deadline with `granularity` as leeway instead of a 4 s re-check. Still fires right after system sleep.
Proof, `SwiftSignalKitTesting/Stress/IdleWakeupTests` plus a one-off 30 s run with 50 pending hour-long delays armed at staggered times (the app's shape): legacy 9.7 → 20.1 process wakeups/s (+10.4), v2 9.9 → 9.9 (+0). All 1,112 SwiftSignalKit tests pass, parity fuzzer included.

### #5 Reactions and fact-check re-polling (ChatUI)

The managers re-poll only the latest batch handed in by the visible pass (visible rows plus one screen) and stop while the chat window is not key or the chat is not shown; becoming key resumes with the latest batch.
Behavior change, iOS parity: reactions of messages that scrolled away are no longer re-requested every 20 s, and nothing is polled while Telegram is in the background. Visible messages still refresh every ~5 s (TelegramCore throttles requests to one per 20 s per message).
Proof: `ChatUITests/ThrottledProcessingManagerTests` (only the latest batch is re-polled, nothing while inactive, resume on activation, one-shot managers unchanged).

### #2 Display link wakeups (TGUIKit)

The CVDisplayLink thread now counts vsyncs and signals the main queue only when the next link is due; the main thread publishes "vsyncs until due" after every delivery and `.fps` links accumulate the real elapsed time. Every link keeps its exact cadence.
Proof, `TGUIKitTests/DisplayLinkRateTests` on the 120 Hz built-in display (old driver vs new, same harness):

| Active links | ticks/s per link | main deliveries/s old | new |
|---|---|---|---|
| `.fps(25)` (GIF) | 25 | 121 | 25 |
| `.fps(25)`, `.fps(30)`, `.fps(60)` | 24, 30, 60 | 121 | 73 |
| `.fps(25)`, `.max` | 25, 121 | 121 | 121 |

### #3/#4 Star sparkles (PremiumStatusUI, StarsUI, ChatUI)

`StarsEffectLayer` (gift emoji status) and `StarsButtonEffectLayer` (paid star reaction) get `isPlaying`, which sets the emitter `birthRate` to 0. They follow the same rule as the Lottie next to them: visible, key window, not lite.
Proof, `tools/perflab/PowerLabs/Emitter/offscreen.swift` (CARenderer, 12 status + 12 reaction emitters, 720 frames at 120 Hz, 3 rounds): playing 0.17 ms per frame and 720 of 720 frames need a render; paused 0.014 ms and 0 of 720. A visible sparkle kept its window recompositing at display rate forever; a paused one lets the compositor idle. The on-screen variant could not separate the signal from WindowServer noise while the Mac was in use (~40 % WindowServer in every phase).
Tests: `ChatUITests/StarsEmitterPauseTests`.

### #13a Paused audio kept the output running (TelegramMedia)

`setRate(0)` only switched the render callback to silence; the AUGraph and the HAL output kept running until the player was deallocated (header player, sound-emoji players, recording preview, stories). The renderer now stops the graph (`AUGraphStop`, still initialized) after 3 s paused and starts it again on play. Audio is identical: a paused graph only ever rendered zeros.
Proof, `tools/perflab/PowerLabs/Audio/idle-output.swift` (HAL output with a silent callback, 15 s phases, 2 rounds): running costs coreaudiod 6.4-6.8 % CPU plus 0.3-0.4 % in the app and holds `PreventUserIdleSystemSleep` (the Mac cannot idle-sleep); stopped costs 0.07-0.27 % and the assertion is released.
Test: `ChatUITests/AudioRendererIdleStopTests` drives the real `MediaPlayerAudioRenderer`: output running during the grace period, stopped after it, running again on play.

### #13e Spoiler dust (TGUIKit, DustLayer)

`InvisibleInkDustView` (text), `MediaDustView` (media, chat list, media grid) and `MediaDustView2` (paid media, invoices) freeze their emitter timeline (`speed = 0`) when the window is not key or the view has no window, and after a reveal once the 0.3 s fade-out is done. Frozen dust stays visible, the way paused Lottie keeps its frame. Revealed dust was simulating at alpha 0 until the message was reused.
Proof, `tools/perflab/PowerLabs/Emitter/offscreen.swift` (variants): playing 720 of 720 frames need a render; frozen 1 of 720 with the same particles on screen (984 vs 960 particle pixels); frozen right at creation also shows a full field (CA simulates the emitter's last `lifetime` seconds), so a spoiler that arrives while Telegram is in the background is not blank.
Tests: `TGUIKitTests/SpoilerDustPlaybackTests`. Shared helpers: `CALayer.setTimelineFrozen`, `WindowKeyObserver` (TGUIKit `LayerPlaybackGate.swift`).

### #13d Video custom emoji frame cache (TelegramMedia)

Video (webm) animations of 40 pt and less (inline custom emoji, reactions, emoji panel cells, statuses) were never frame-cached, so every visible one was VP9-decoded in software on every frame of every loop, forever. They now use the same LZFSE frame cache as larger ones. Small buffers (≤ 80×80 px) encode their first frame without the 668 KB persistent scratch (delta frames already used none), so caching many small emoji at once costs no extra memory.
Proof, `DecodeBench webm-cache` (60 real emoji from the media cache, 11,139 frames):

| Frame size | VP9 decode + scale | cached read (pread + LZFSE + XOR) | |
|---|---|---|---|
| 40×40 | 0.548 ms | 0.008 ms | 71× |
| 52×52 | 0.546 ms | 0.010 ms | 52× |
| 80×80 | 0.541 ms | 0.019 ms | 28× |

The first loop costs 0.69 ms per frame instead of 0.54 (it also encodes), every later loop 0.01 ms. An emoji panel with 100 visible video emoji at 30 fps drops from about 1.6 cores to about 0.03 after the first loop. Disk: about 290 KB per emoji at 52 px, removed by the existing cache lifetime (about 2.8 days).
Test: `ChatUITests/LottieFrameCacheMemoryTests.testSmallAnimationsCacheWithoutKeepingAnEncoderScratch` (40 small animations hold 355 KB instead of 26.7 MB; frames read back exactly).
Not changed: tinted emoji (`paintToText`, default statuses) also skip the cache, but their colors can change live through `setColors`, so a frame cache could show stale colors.

### #6 (part) Chat list rows measured twice (ChatListUI)

`ChatListRowItem.init` already measures at the table width, then `TableView.insert/replace` measured it again because the chat list never set `premeasuredWidth` (ChatController has since the 2026-09-28 loop). Every row rebuilt by a presence, typing, reaction or read-state change paid CoreText twice. `prepareEntries` now marks exact `ChatListRowItem`s as premeasured; subclasses (the HTML demo row) and other row types still measure in the table, and the table re-measures anyway when its width differs.
Proof: `TGUIKitTests/PremeasuredRowTests` (insert/replace skip `makeSize` at the same width, measure at a different one); ChatListUITests 99/99 pass.

### #23 HTML bubble stats timer (HTMLBubbles)

Every HTML bubble ran a 1 Hz main-thread timer (with a UserDefaults read per tick) for the debug stats overlay, also when the overlay is off. The timer now exists only while the overlay is enabled; toggling it posts `HTMLBubbleStatsOverlay.didChangeNotification` so open bubbles follow immediately.

### #13 Notification pipeline (app target)

TelegramCore emits `notificationMessages` and `reactionNotifications` for every update batch (typing, read states, ...), usually empty. The reactions branch then ran `resolveInlineStickers` and a Postbox transaction per batch, and `combineLatest` re-paired each batch with the other stream's previous value, so after any notification every following batch re-rendered that message's avatar, reloaded peers and looked up the tone, only to be dropped by `alreadyNotified` at the end.
Both streams now drop empty batches before any work and start from `[]`, so `combineLatest` still never waits and a cancelled in-flight run is still re-paired with its messages (no notification can be lost; an empty batch could never notify anything). The two in-app settings flags the pipeline used to refresh on every batch now come from their own settings subscription, so they stay current between notifications.
Verified with the DerivedData type-check harness (`Telegram-Mac` target, no new errors).

### #17 Spinners inside hidden containers (TGUIKit)

`ProgressIndicator` checked only its own `isHidden`, so a spinner whose container was hidden kept its 25 Hz main-thread timer and redraw. The inline-bot progress button is one: after the first inline query it stays in the input as a hidden view and spun until the chat closed. It now checks `isHiddenOrHasHiddenAncestor` (AppKit already sends `viewDidHide`/`viewDidUnhide` for ancestor changes).
Proof: `TGUIKitTests/ProgressIndicatorHiddenTests` fails on the old condition (still spinning in a hidden container) and passes now; unhiding restarts it.

### Measured and left alone

- Display colour conversion of cached Lottie frames: 3.8 µs at 40 px, 18 µs at 100 px, 188 µs at 400 px per frame (0.01-0.56 % of a core per animation at 30 fps). Caching converted pixels would need a cache keyed by display colour space; not worth it now (`scratchpad` lab `colorconv`).
- Rust engine ping cadence while online (about every 2-3 s per session): a line-for-line port of tdlib's online liveness timing (`rtt*1.5+1`, minimum 2 s), only while the user is active. A liveness tradeoff for the engine owners, not changed.
- `ChunkMediaPlayerV2` 5 Hz paused tick: drives part loading and status while paused in the iOS-synced player; changing it risks HLS behaviour.
- The 20 % CPU seen on the App Store build at 12:20 was an active call (capture, render and tgcalls threads).

### #14 Dock badge and status-bar icon (GeneralRows)

The dock badge label was set and the status-bar icon re-rendered (CoreText layout plus two bitmaps) on every unread-count emission, including the many that leave the total unchanged. Both are now skipped when the dock already shows the same label. The in-app badge still updates on every emission, so its theme-dependent colour is refreshed exactly as before; the icon's other inputs (status bar setting, system appearance) have their own forced updates (`SharedAccountContext` base settings, `AppleInterfaceThemeChangedNotification`).
Verified with the type-check harness.

### #10 Typing, recording and sticker-choosing indicators (ShortPeerRow)

`ChatActivitiesView` (chat list rows and chat header) ran infinite path/opacity keyframe animations regardless of focus; on a busy account someone is nearly always typing, so a visible Telegram window recomposited continuously while the user worked in another app. The indicator layer's timeline now freezes when the window is not key (same `WindowKeyObserver` + `setTimelineFrozen` as the spoilers), showing the current dot frame, and resumes on focus.
Proof, `tools/perflab/PowerLabs/Emitter/keyframes.swift` (8 indicators, 720 frames at 120 Hz, 2 rounds): playing 720 of 720 frames need a render (0.18-0.23 ms each offscreen), frozen 0 of 720. Test: `ShortPeerRowTests/ChatActivityPlaybackTests`.

### #15 Voice chat indicator in chat list rows (ChatListUI)

`GCChatListIndicator` chained a new `DisplayLinkAnimator` every 0.4 s forever and rebuilt its `CGPath` on the main thread every frame (120 Hz), also when Telegram was not focused. It is now one infinite `CAKeyframeAnimation` on `path`: the 8 stage boundaries as keyframes with an `easeOut` timing function per 0.4 s segment, the same curve `DisplayLinkAnimator` applied per stage. Every bar is a rounded rect with the same 10 path elements at all heights, so Core Animation interpolates the bars exactly as before. Its timeline freezes when the window is not key.
Proof: `ChatListUITests/GCChatListIndicatorTests` keeps the old view as `LegacyGCChatListIndicator` and measures 20 visible indicators for 2 s: display link 6.91 % CPU, Core Animation 0.26 % (Debug build); plus the key-window freeze. ChatListUITests 100/100.

### #16 (part) Silent speaker avatars in the voice chat header (AvatarUI)

The header samples fake audio levels at 30 Hz, and `AvatarContentView.updateAudioLevel` built a new 0.1 s `DisplayLinkAnimator` on every sample, also for silent avatars whose scale was already 1.0, so the shared display link never went idle while a voice chat with speakers was shown. The animator is now skipped when there is none running and the scale already equals the target; it clears itself on completion. Nothing visible changes (an animation from 1.0 to 1.0). The 30 Hz sampling and the voice blobs themselves are unchanged.
Verified with the type-check harness.

### #26 Read metrics 5 Hz tick (ChatUI)

`MessageReadMetricsManager` ran a 0.2 s repeating main-thread timer for as long as a focused chat showed cloud messages (most of the time a chat is open), only to add 200 ms to every tracked message and to finalize messages after 300 s. Time is now accumulated when something happens (user activity, pause, finalize), split at "last activity + 15 s" for the active part, and one timer waits for the next 300 s deadline. A focused chat goes from 5 main-thread wakeups per second to none between scrolls.
The reported numbers are server read metrics, not UI. They differ from the 5 Hz sampling by at most one 0.2 s slice per activity boundary (the sampling error the old code had).
Proof: `ChatUITests/ReadTimeSliceTests` (200 random timelines vs a simulation of the old sampling; the split at the end of activity).

### #24 Passcode auto-lock check (app target)

The 10 s auto-lock check opened an account-manager transaction on every tick, for every user, also without a passcode. It now reads "is a passcode set, and its timeout" from a value cached from the live `accessChallengeData()` and passcode-settings views (falling back to the transaction until the first value arrives). The 10 s cadence and every emission stay exactly as they were, because the free-space warning and the auto-archive suggestion re-check their conditions on these emissions.
Verified with the type-check harness.

### #7 (part) Chat list rebuilds from unrelated state (ChatListUI)

The chat list's 14-input pipeline took the whole `PeerListState`, so every change of a field it never reads re-ran the entry mapping, sorting and full diff on the prepare queue: connection status ("Connecting…", "Updating…", on every reconnect and wake), proxy settings, search query and state on every keystroke, stories, web apps, downloads, and the folder unread badges inside `filterData`. It now takes `ChatListStateProjection`, the exact fields the closure reads (activities, appear, controller appear, forum peer, hidden items, mode, selected forum, split state, and the folder filter, tabs, tag setting and request timestamp), with `distinctUntilChanged`. The closure body is unchanged.
Not done yet: typing anywhere still changes `activities` and rebuilds the list (filtering activities to the loaded rows is the next step).
Proof: `ChatListUITests/ChatListStateProjectionTests` (unread fields leave the projection equal, read fields change it); ChatListUITests 101/101.
