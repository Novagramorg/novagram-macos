# Chat and chat list performance (2026-10-11)

Second pass after the power audit (`power-audit.md`), aimed at the chat and the chat list. Static audits of the chat list, the chat history and the TGUIKit primitives, then fixes one by one, each with a test that fails on the old code or a measurement.

## Log

### 1. App-wide geometry observers (TGUIKit `AnimatableContentObserver`)

Views that refresh their animated content on scrolling (custom emoji, emoji statuses, media, reactions; 18 files use the observers) subscribe to the enclosing scroll view's clip-view bounds and document frame. For a view outside any scroll view (chat title bar, headers, status controls) both were `nil`, and `NotificationCenter` treats a `nil` object as "any object": the view was called back for every frame and bounds change of every NSView in the app, on every row relayout and animation step. Unregistering also removed all of the target's observers, and a view leaving its window stayed registered.
Now: no `nil`-object registrations (a view without a scroll view follows its window's resize instead, plus its own frame and key state as before), unregistering removes exactly what was registered, and a view without a window unregisters.
Proof: `TGUIKitTests/AnimatableContentObserverTests` — 100 frame and bounds changes of an unrelated view called the old observer 198 times, the new one 0; window resize, own frame and scroll-view scrolling still update. TGUIKit 91/91.

### 2. Control background re-applied on every mouse move (TGUIKit `Control`)

`controlState` is re-assigned on every mouse move over a control (every TextView and button in rows), and its didSet always ran `apply(state:)`: a `layer.backgroundColor` write and, for animated controls, a new 0.2 s `backgroundColor` animation from the presentation value to the same model value, which keeps Core Animation rendering. The color write and the animation now happen only when the color actually changes; state handlers and cursor updates are untouched.
Proof: `TGUIKitTests/ControlStateApplyTests` fails on the old code (a background animation per unchanged update) and passes now; hover still animates.

### 3. Avatar cache hits wrote themselves back (TelegramUtils `peerAvatarImage`)

Every avatar served from the photo cache (chat list rows, message authors, headers) was stored again with `cachePeerPhoto`: under the cache lock, `setImage` removed the entry, re-inserted it without its display scopes and ran eviction. The lookup already refreshes `lastUsed`, and `AvatarLayer` re-attaches the display scope (clearing the orphan mark) whenever its contents are set, so a hit now just returns the image. Verified with the type-check harness.

### 4. TransformImageView set its layer contents twice (TGUIKit)

Every image set ended with `preventsCapture = preventsCapture`, which re-ran a didSet whose capture branch is commented out and wrote `layer.contents` a second time. Removed. TGUIKit 92/92.

### 5. Spoiler rects for text without spoilers (TGUIKit `TextViewLayout`)

`spoilerRects` walked every line and allocated a filtered spoiler array per line even when the text has no spoilers, and `TextView.update`/`layout`/`draw` call it 4-5 times per update (2-5 text views per row). It now returns `[]` immediately when there are no spoilers (the same result).
Proof, `TGUIKitTests/TextViewUpdateTests.testUpdateCost` (20 text views, 20,000 update + layout + flush, two interleaved rounds): 6.09 / 6.21 µs → 4.80 / 4.75 µs per update (−22 %). `testRepeatedUpdatesKeepTheLayerOrder` pins the layer order.
Rejected after measuring: skipping the `drawLayer`/`embeddedContainer` re-insert in `updateBackgroundBlur` when already in place made updates slower (7.30 vs 6.39 µs); re-inserting a layer at its own index is cheaper than checking.

### 6. Chat list rows resubscribed to their peer on every set (ChatListUI)

Each `ChatListRowView.set(item:)` (every rebuild, typing toggle, selection change, scroll-in) went through `PremiumStatusControl.control` twice with the default `autoupdate: true`, and each call replaced a `postbox.combinedView([.basicPeer])` subscription: a Postbox view removed and added, with its initial render, per call for every premium, verified or emoji-status peer. The chat list view already rebuilds the row when the peer changes, so the rows now pass `autoupdate: false`.

### 7. Presence timers for offline users (ChatListUI)

`if let _ = self.isOnline` is also true for `false`, so every row of a recently seen, offline user armed a `PeerPresenceStatusManager` that fired within a minute only to set `isOnline = false` again and redraw the row with an animation (a burst after launch, folder switches and paging). The timer is armed only for online users now.

### 8. Chat list title, date and topic layers redrew unchanged text (ChatListUI)

`ChatListTextLayer.update` always called `setNeedsDisplay`, a full CoreGraphics text draw through the shared `TextView` renderer, also when a row was re-set with the same layout instance (typing toggles, selection neighbours, presence). It now returns when the layout instance and size are unchanged and the layer has drawn contents.
Proof: `ChatListUITests/ChatListTextLayerTests.testSameLayoutDoesNotRedraw`; the pixel tests of the same suite pass. ChatListUITests 104/104.

### 9. Voice chat speaking activities rebuilt the chat list (ChatListUI)

Group-call "speaking" updates arrive as `.voiceChat` input activities and changed `ChatListStateProjection.activities`, re-running the chat list mapping and diff, but rows only read `.global` and `.thread` spaces. The projection now drops `.voiceChat` spaces.
Not done, on purpose: filtering activities to the loaded rows. With `distinctUntilChanged` the projection would keep a stale activity map for unloaded chats, and a chat paged into the list would show it.
Proof: `ChatListUITests/ChatListStateProjectionTests.testVoiceChatActivitiesDoNotRebuildTheList`.

### 10. Chat list main-thread tail after an empty transition (ChatListUI, TGUIKit)

Every chat list pipeline run (typing anywhere, story, birthday and suggestion emissions) ended in `enqueueTransition`, which after `TableView.merge` ran three full enumerations of the table, `afterTransaction` (a fourth enumeration plus a redraw of the space row and the table mask), a new `TableAutohide`, the pinned-items update and a new delayed preload signal, even when `merge` returned early because nothing changed. `TableView.merge(with:)` now reports whether it applied anything (`@discardableResult`, so other callers are unchanged), and the tail runs only when it did. Everything in the tail derives from the table items, which an unapplied merge leaves untouched; header-driven inset changes have their own `updateScrollerInset` call.
Proof: `TGUIKitTests/TableMergeResultTests`; TGUIKit 95/95, ChatListUITests 105/105.

### 11. Bubble backdrop reset on every row set (ChatUI)

`ChatRowView.set(item:)` calls `bubbleView.setType` every time, and it cleared the backdrop's position memo (`lastUpdate`) and applied cut, re-assigned the background contents and the mask data, so the next `update(rect:)` repositioned everything even for the same bubble images. `setType` now returns when the mask image and insets, border and background are the same instances as last time (nothing else mutates that state).
Proof: `ChatUITests/ChatBubbleBackdropTests` (the pixel tests pass); `testRepeatedIdenticalSetTypeCost`, 100,000 identical setType + update, two interleaved rounds: 0.91 / 0.86 µs → 0.32 / 0.33 µs. Small per call; layer commit savings are not included in that number.

### 12. Postbox history view (telegram-ios `6b5f5f6c67`, shared with iOS)

- `updateStoryStats` ran on every history change and read the story tables (uncached SQLite) once per entry instead of once per author: about 100-180 reads per open chat per change, now one per distinct author. Same result.
- `updatePeers` copied every associated message (two allocations each) for every entry whenever any peer updated, and kept the copies when the main message was rebuilt, which defeated the UI's `===` fast path. Only associated messages whose peers changed are copied now; contents are identical.
Verified: Postbox builds (`swift build`); the diff reads as identical results.

## In-app A/B (2026-10-11 13:28-13:34)

`ChatNavigationLab`, Debug builds, interleaved rounds (base, new, new, base). Base: the user's existing Debug build from DerivedData (beta plus their uncommitted local work, so not exactly `beta`). New: `power-diet` with the main checkout's submodules (the telegram-ios commits of this branch are not in it).

| Scenario | base r1 / r2 | power-diet r1 / r2 |
|---|---|---|
| Scroll, "Telegram macOS Talk": main thread | 20.0 % / 23.4 % | 20.9 % / 21.9 % |
| Scroll: process CPU (cores) | 0.37 / 0.46 | 0.44 / 0.44 |
| Typing, Saved Messages: main thread | 12.0 % / 12.2 % | 11.2 % / 12.1 % |
| Idle in a chat: main thread | 1.0 % / 1.3 % | 1.4 % / 1.0 % |

No difference beyond the run-to-run spread (about ±2 %). Expected: these scenarios exercise the paths earlier loops already optimized, while this round's fixes remove routine background work (chat list rebuilds on presence, status, typing and badge changes; app-wide geometry observers; Postbox reads; redundant redraws and resubscriptions) that a single-chat scroll does not trigger. A chat list update lab (simulated presence and typing bursts) would be needed to show those end to end.
