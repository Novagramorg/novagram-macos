# Theme optimization log (2026-10-06, /loop)

Goal: better performance + lower memory for themes, wallpapers, animated background; find leaks
(themes hold images). Cover changes with tests / lab. Verify in lab, never on the user account.
Package `swift build` only — do NOT build the app (user builds/tests). Commit per round; push on request.

Packages: TelegramTheme (+ TelegramThemeShare copy), TelegramIconsTheme (14,253 lines!), ColorPalette,
WallpaperUI, ThemeSettings. No existing tests for any of these.

## Research findings

### PhotoCache / theme image caches (agent, 2026-10-06)
Files: `packages/TelegramTheme/Sources/TelegramTheme/PhotoCache.swift` (+ byte-identical `TelegramThemeShare` copy),
`packages/TGUIKit/Sources/ScopedImageCache.swift`.

Premise reframe: theme **CGImages already route through the budgeted `ScopedImageCache`** (byte budgets +
idle expiry + scroll-scope expiry). The outlier is the **wallpaper** path.

Ranked:
1. **wallpaperCache: full-res wallpaper NSImages, byte-unbounded, never purged.** `WallpaperCache` (PhotoCache.swift:290-315)
   = plain `NSCache<NSNumber, WallpaperCachedRecord>`, only `countLimit=20`, **no `totalCostLimit`**. Stores
   `TableBackgroundMode` whose `.background`/`.tiled` carry a full `NSImage` loaded at NATIVE resolution
   (`NSImage(contentsOf:)` TelegramPresentationTheme.swift:206/213/227, not downscaled to the 1040×1580 hint).
   ~26 MB/entry @2× → up to ~0.5 GB uncounted. `purgeImageCachesForMemoryPressure()` (PhotoCache.swift:349-356)
   clears the 6 ScopedImageCaches but **OMITS wallpaperCache** → largest retainer survives memory pressure
   (MemoryPressureMonitor.swift:44). Keyed `.background(Wallpaper, palette.name)`; written `cacheBackground`
   (478-481), read `cachedBackground` (482-484), driven by `TelegramPresentationTheme.backgroundMode` (598-621).
2. **No clear-on-theme-switch.** `telegramUpdateTheme` (Appearance.swift:2239-2274) / `updateTheme(with:)` (2201-2235)
   clear no cache; old-theme wallpaper NSImages linger (keyed by palette.name) until count-evict(20) or OS pressure.
   Media caches self-heal (TransformImageArguments embeds emptyColor/corners → key rotates). themeThums are
   other-theme previews → correct to keep.
3. **Scroll hot-path:** `cachedMedia` (377-396) recomputes `key.hashValue` up to 3× (sticker→photos→thumbs) and
   `.single(…)`-allocates per call; `.media` hash does `resource.id.stringRepresentation` + full TransformImageArguments
   hash. 46 callsites (ChatUI/ChatListUI/StoriesUI/…). Micro-win: hash once, avoid Signal alloc.
4. **Dead double-work:** `cachedThemeThumb` (507) re-queries the same themeThums that returned nil; `cacheThemeThumb`
   (520-524) identical if/else. Unused: `WallpaperCache.maxCount` (292), `WallpaperCachedRecord.date` (17/20), `removeRecord` (308).
5. **TelegramChatColors.cacheDict** (ChatPresentationUtils.swift:242, per-theme so no cross-theme leak): `messageSecretTimer`
   colors from GLOBAL `theme.colors.darkGrayText` not `self.palette` (latent staleness) + unbounded per distinct digit string.
6. extensionImageCache (ThumbUtils.swift:5) unbounded but harmless (small extension set, Atomic).

Latent correctness (facts, dead due to hashValue-only keying): inverted `.avatar ==` (210-212); SHARE `#if !SHARE`
hash collisions (111-115/131-138); ScopedImageCache cost ignores `sampleBuffer` video bytes (ScopedImageCache.swift:63);
PhotoCache.swift exists as 2 byte-identical copies.

Candidates: (1) byte-budget wallpaperCache (totalCostLimit + cost: on set, or route via ScopedImageCache);
(2) add wallpaperCache.clearAll() to purgeImageCachesForMemoryPressure(); (3) trim wallpaperCache to the new
palette on theme switch; (4) hash-once hot path; (5) dead-code cleanup; (6) cacheDict palette-keying + bound.

### Theme core & icons memory (agent, 2026-10-06)
Pipeline: theme built OFF-main on `resourcesQueue` (AppDelegate.swift:661 `updateTheme(with:)`→`generateTheme`
Appearance.swift:2174/2201), swapped on MAIN (`telegramUpdateTheme`→`PresentationTheme.updateTheme` `_theme.swap`
PresentationTheme.swift:17 + `_themeSignal.set` Appearance.swift:2241). Change notify = Promise/Signal chain
`_themeSignal→themeSignal→appearanceSignal` (TelegramPresentationTheme.swift:755, AppearanceGlobal.swift:93-100);
NotificationCenter only for AppearanceDayContext day/clock (60s timer, AppearanceGlobal.swift:62-91). Icons are
**877 `()->CGImage` closures** (capture `palette`, a CLASS, not self), **LAZY** (rendered on first use, memoized in
`cached`/`cachedWithInset` Atomic dicts); no eager preheat. **No retain cycles** — old theme released (single-slot
globals); holders transient (globals, AccountContext._emoticonThemes/_chatThemes, per-ChatController promises).

Ranked:
1. **Eager wallpaper regen BYPASSES cache on every theme build.** TelegramPresentationTheme.swift:638-640 (init):
   on the normal off-main `generated` path it runs `generateBackgroundMode` directly, skipping `cachedBackground`
   (:604) / `cacheBackground` — decodes/renders the full backgroundSize (~1040×1580, ~26MB @2x) from scratch per
   build even when an identical cached bg exists. (Ties to PhotoCache #1/candidate — the cache it skips.)
2. **N emoticon (chat) themes rebuilt on MAIN on every appearanceSignal fire — incl. daily clock rollover.**
   AccountContext.swift:710-741: `combineLatest(appearanceSignal, getChatThemes)|>mapToSignal` on main; per server
   theme `withUpdatedColors` (fresh 877-closure TelegramIconsTheme + TelegramChatColors) + `withUpdatedWallpaper`
   (2nd theme). Restarted every 20min. Any appearance pulse (switch, language, once-a-day day pulse) rebuilds all N.
3. **Write-lock on every `theme`/`presentation` read.** PresentationTheme.swift:11-13 `_theme.modify {$0}` (write-style,
   not `with`); read per cell layout/draw on main AND prepareQueue.
4. **Unsynchronized lazy caches on a cross-thread-shared theme (DATA RACE/correctness).** ~12 `var _xxx:CGImage?`
   TelegramPresentationTheme.swift:296-474, `_chatServiceItemColor`:480, `_chatServiceItemTextColor`:524,
   `_backgroundMode`:597; + `TelegramChatColors.cacheDict` ChatPresentationUtils.swift:242. No locks (unlike
   TelegramIconsTheme's Atomic); theme read from main + prepareQueue → torn reads/double render/possible crash.
5. **Full theme + icon realloc on fontSize-only change.** AppDelegate.swift:665-666 rebuilds whole theme (empty icon
   cache) when only fontSize/scale changed; icons depend on palette/bubbled/scale not fontSize. `withUpdatedColors`
   (:718)/`withUpdatedChatMode`(:726) rebuild icons; `new()`/`withUpdatedWallpaper`/`withUpdatedEmoticonThemes` reuse.
6. **TelegramIconsTheme cache = O(n) COW per insert + lock+String-hash per read.** TelegramIconsTheme.swift:5-20
   (`cached.modify { var c=current; c[key]=img; return c }` copies whole dict), ×~869 accessors; benign check-then-insert race.
7. **Unbounded global messageBubbleImageCache, never evicted.** ChatMessageBubbleImages.swift:151-156/216; keyed
   fill/stroke argb+scale; +entries per theme forever (low magnitude ~12-24×~20KB/theme but monotonic).
8. extensionImageCache not theme-aware (ThumbUtils.swift:5) — stale file-type icon colors after switch (minor, not leak).
9. transparentBackground/lottieTransparentBackground alloc NSImage+pattern per access (TelegramPresentationTheme.swift:760-765).
10. withUpdatedBackgroundSize (:734-737) mutates shared `self`, leaves stale `_backgroundMode`.
PremiumBadgeImages: pure generators, NO cache — recompute per call (cost=recompute, not leak).

### Wallpapers & animated background (agent, 2026-10-06)
Decode point: `generateBackgroundMode` TelegramPresentationTheme.swift:195-243 — `.image`:206/`.file`:213/`.custom`:227
all `NSImage(contentsOf: wallpaperPath(...))` with NO downscale (maxSize plumbed :195/:595/:607 but IGNORED here).
View: TGUIKit ViewController.swift:55-457 `BackgroundView` (imageView SimpleLayer @System.backingScale; AnimatedGradient
for >2 colors, BackgroundGradientView ≤2; softLight filter :319; TileControl tiles pattern across N SimpleLayers :205).
Animated gradient: SoftwareGradientBackground.swift:205-499 — per-pixel CPU `generateGradientImage`:111-203 (malloc/free
per call), 8-entry GradientImageCache:73-109, pre-generates duration*fps 16×16 frames into a one-shot CAKeyframe
(:345-393, isRemovedOnCompletion), NO timer/displaylink, empty deinit.

Ranked:
1. **No decode-size cap — full-res wallpaper bitmap at backing scale.** TelegramPresentationTheme.swift:206/213/227
   decode native-size PNG (written native WallpaperCache.swift:169/181, can exceed 1040×1580); maxSize ignored.
   Single largest retained wallpaper bitmap (multi-MB–tens-of-MB). Fix: CGImageSourceCreateThumbnailAtIndex +
   kCGImageSourceThumbnailMaxPixelSize (pattern: MediaUtils.swift:2521-2524) to on-screen size / lower contentsScale.
2. **Decoded wallpapers never evicted under pressure + pinned per-theme.** wallpaperCache omitted from purge
   (PhotoCache.swift:349-356); every live theme memoizes `_backgroundMode` (:597-621) so global+each chat+each
   emoticon theme holds a decoded wallpaper the NSCache can't reclaim.
3. **Duplicate full-screen background: chat BackgroundView + nav backdropView both get the mode.** ChatController.swift:9094-9096
   (super→nav backdrop NavigationViewController.swift:418 + genericView.backgroundView). Chat view bg is .clear so backdrop
   occluded but still composited; push/pop → 2 containers each w/ backdrop → 3-4 concurrent full-screen wallpaper layers.
4. **softLight compositing filter replicated per tile** (ViewController.swift:319 + TileControl:205) → 2×(1+N) offscreen
   blend passes/frame. Static 1-2 color patterns could bake pattern+gradient to one bitmap (preview already does: MediaUtils.swift:2653-2659).
5. Animated gradient pre-generates duration*fps 16×16 frames synchronously on MAIN (malloc/free per frame) — small burst, only on trigger; not continuous, not a leak.
6. **Dimmed (saturation 1.7) gradient generated unconditionally for a DEAD feature.** SoftwareGradientBackground.swift:424/437
   always build the 2nd dimmed image; only animated path gates on needDimmedImages (:341). `CloneView` has ZERO external instantiations.
7. **Edge-color sampling forces a full wallpaper decode to read ONE pixel.** ChatController.swift:366-385 `sampleAverageColor`
   draws the full wallpaper into a 1×1 ctx → turns lazy NSImage into resident decoded bitmap per bg-mode change.
8. Off-main theme gen re-decodes from disk bypassing cache (TelegramPresentationTheme.swift:638-640) — same as core #1.
Non-findings (verified OK): pattern wallpapers rasterized once (disk-cached, 400×800/512×512); scrolling doesn't redraw bg
(TGClipView empty draw); NO retain cycle/leaked animator in bg views; BackgroundView reused across chat switches; .background
`==` blind-true harmless (NSCache keys on Int hashValue).

## Consolidated plan (impact × safety; hub blast radius matters — TGUIKit/TelegramTheme recompile ~90 pkgs)
MEMORY (user's main concern): M1 cap wallpaper decode size [wp#1]; M2 wallpaperCache byte budget [pc#1/wp#2];
M3 wallpaperCache in purge hook [pc#2/wp#2]; M4 drop _backgroundMode / trim wallpaperCache on theme switch & inactive
themes [pc#3/wp#2]; M5 eager regen route through cache [core#1/wp#8]; M6 messageBubbleImageCache eviction [core#7].
CPU: C1 emoticon rebuild gate+off-main [core#2, RISKY]; C2 lock-free theme read [core#3, hub]; C3 icon cache COW→in-place
[core#6, 14K-line file RISKY]; C4 fontSize-only reuse icons [core#5]; C5 collapse double bg [wp#3, RISKY]; C6 bake static
pattern / drop per-tile softLight [wp#4]; C7 edge-color from small img [wp#7]; C8 gate/remove dead CloneView dimmed gen [wp#6];
C9 cache transparentBackground [core#9]. CORRECTNESS: R1 sync lazy caches on shared theme [core#4]; R2 messageSecretTimer
palette-key+bound [pc#5]. DEADCODE: D1 themeThumb double-work [pc#4]; D2 unused WallpaperCache.maxCount/date/removeRecord; D3 CloneView.

Round order (safest high-value first, each tested/lab-verified, behavior-preserving): R1=M2+M3+M4+D2 (wallpaperCache
budget/purge/trim+cleanup) → M1 (decode cap) → M5+M6 → C8/D3 → R2 → C9 → then weigh the hub/concurrency/behavior ones
(C1/C2/C3/C5/R1) with the advisor + user real-app verify.
TEST INFRA NOTE: TelegramTheme likely won't `swift build` standalone (like GeneralRows). Extractable logic (byte-budget
eviction) can be unit-tested in TGUIKit (builds standalone, ModalMorphLab proved it) or a self-contained lab; cache-policy
+ decode-cap need a lab or the user's app run.

## Blockers resolved (advisor pass, 2026-10-06)
- **TelegramTheme BUILDS STANDALONE** (`swift build --package-path packages/TelegramTheme` → exit 0, ~104s). TGUIKit
  has a real XCTest target (Tests/TGUIKitTests/*, incl. ScopedImageCacheTests). → decode-cap helper + unit test go in
  TGUIKit (`swift test --package-path packages/TGUIKit`); wiring compile-verified with `swift build` on TelegramTheme.
- PhotoCache.swift the two trees are byte-IDENTICAL → every edit lands in BOTH (TelegramTheme + TelegramThemeShare); the
  wallpaper DECODE lives in TelegramPresentationTheme.swift inside `#if !SHARE` (Share returns .plain), so decode changes
  are no-ops in the Share build but keep the files in sync anyway.
- **Premise correction (advisor #1):** wallpaperCache is BYPASSED for production themes — init :638-640 sets `_backgroundMode`
  eagerly (off-main generated), so the lazy getter's cacheBackground (:604-614, the ONLY callers) never runs. Real retainer =
  per-theme `_backgroundMode` full-res NSImage. ⇒ **M1 first**; M2/M3/M4 only matter after M5 routes init through the cache.
- CloneView NEVER instantiated (grep clean) ⇒ C8/D3 safe; dimmed-image gen at SoftwareGradientBackground.swift:424/437 is dead work.

## Finalized round order
- R0 dead-code: D1 (cachedThemeThumb :507 double lookup, cacheThemeThumb :520-524 identical branches) + D2 (WallpaperCache.maxCount,
  WallpaperCachedRecord.date, removeRecord) — both PhotoCache trees. Zero behavior change.
- R1 **M1 decode cap**: TGUIKit helper `downsampledImage(contentsOfFile:maxPixelSize:)` (CGImageSourceCreateThumbnailAtIndex +
  kCGImageSourceShouldCacheImmediately=false, downsample ONLY if larger) + XCTest; wire into generateBackgroundMode .image/.file/.custom
  (:206/213/227) with cap = backgroundSize × System.backingScale. Patterns (small masks ≤400×800) are < cap ⇒ untouched (tiling safe).
- R2 cache story: M5 (route :638-640 through cachedBackground) + M2 (wallpaperCache totalCostLimit + cost:) + M3 (add to
  purgeImageCachesForMemoryPressure) + M4 (drop _backgroundMode on theme switch / inactive themes).
- R3 C8/D3 (remove CloneView + dead dimmed gen, TGUIKit, lab-verify gradient still renders) ; R2b M6 messageBubbleImageCache eviction.
- R4 R2(messageSecretTimer palette-key+bound), C9 (cache transparentBackground), C7 (edge color from small img).
- LATER/RISKY (need user real-app run): C1 emoticon rebuild gate+off-main (AccountContext, app target), C2 `_theme.modify{$0}`→`.with{$0}`
  (confirm SwiftSignalKit2 Atomic.with semantics first), C3 icon COW (869 accessors — check for a shared helper), C5 collapse double bg.

## Measurement recipe (for the USER to run; I can't build the app)
Baseline vs after on an App Store/Debug build (see [[memory-measurement-tools]]): open 3 chats each with a DISTINCT image
wallpaper, switch global theme twice (day↔night), then `footprint <pid>` and `heap <pid> | grep -iE "CGImage|NSImage|wallpaper"`
for count+bytes of image backing stores. Expect M1 to cut resident wallpaper bitmaps roughly by (native²)/(1040·1580·scale²).

## Done this loop (local commits on beta, NOT pushed — holding for user)
- Research (3 agents) + plan + advisor + blockers.
- **R0** `bbeb677b8` TelegramTheme: remove dead PhotoCache members (maxCount/date/removeRecord; themeThumb no-op lookups). Builds.
- **R1 (hero)** `fad045d27` TGUIKit downsampledImage + 4 XCTests (pass) ; `4aa9281fe` TelegramTheme cap wallpaper decode to
  maxSize×backingScale (=3160px longest side for the default 1040×1580 theme). Fixes the uncapped full-res wallpaper bitmap
  held in every live theme's `_backgroundMode` — the user's "holds images". Small pattern masks (≤~512×800) are < cap ⇒
  untouched (tiling safe). TelegramTheme builds standalone.
  - NOTE discovered: TelegramThemeShare/* are SYMLINKS to TelegramTheme/* (not copies) — editing one covers both; the
    two-copies trap is moot. Logged for future rounds.
  - CAVEAT (noted for user): backgroundSize is a FIXED 1040×1580 in production (updateTheme(with:)→generateTheme passes no
    size), so the cap is display-independent. On a very tall window (>1580pt, e.g. 6K XDR) a huge wallpaper could be marginally
    softer than full-native. Rare; if it matters, make backgroundSize screen-derived. Current behavior was uncapped (full native).

- **R3** `08f64d533` TGUIKit: animated-gradient dimmed image now lazy (the 2 non-animated paths rendered a wasted
  saturation-1.7 gradient every layout/size-change for CloneViews that are never created; visible gradient = contentView
  non-dimmed image, unchanged). +GradientBackgroundTests (2 pass).
- **M3+M6** `3bbae3f76` TelegramTheme: cap messageBubbleImageCache (was unbounded/process-lifetime) + add wallpaperCache
  & bubble cache to purgeImageCachesForMemoryPressure (both were skipped). Builds.

- **C2** `1ac609b9a` TGUIKit: `presentation` read `_theme.modify {$0}` (redundant re-store/retain-release per read on the
  per-draw hot path) → `.with {$0}` (read-only, same return). Verified via both Atomic impls' source. Builds.
- **R2** `6ccb493e3` TelegramTheme: messageSecretTimer colors from self.palette not global theme.colors (non-active-theme
  staleness). Builds.

## Assessed, NOT done (diminishing returns / risk — rejected or deferred)
- **C9** transparentBackground/lottieTransparentBackground per-access NSImage+pattern alloc: REJECTED — 24 callers are all
  one-time image-GENERATION paths (setFillColor inside generateImage), not draw loops; alloc dwarfed by the gen. Not worth it.
- **C7** edge-color sampleAverageColor full-decode-for-1px (ChatController:372): low value now — memoized per bg-mode change
  AND the decode is already capped by M1; ChatUI is a slow build. Skipped.
- **C3** icon-cache COW + per-read lock (TelegramIconsTheme.swift): the 869 accessors INLINE the `cached.modify {var c=current…}`
  COW (no shared helper); file is CODE-GENERATED by tools/generate-images.swift. Real cost is small (COW only on cold inserts
  = working set ~100-200, spread over session; read path is a pthread lock ~20ns). 14K-line regeneration = high risk / low
  reward. DEFERRED — fix in the generator template if ever revisited.
- **M5/M2 cache story**: MODEST post-M1 (real retainer = per-theme _backgroundMode, now capped). Clearing the cache (M3, done)
  doesn't free _backgroundMode anyway. Low priority.

## Confirmation pass (4th agent, 2026-10-06) — caught 2 REGRESSIONS I introduced + more
- **REGRESSION (fix)** `20482691d` withUpdatedBackgroundSize MUTATED the shared theme (`self.backgroundSize=size; return self`);
  harmless pre-M1 (size ignored) but post-M1 a 200×200 preview from Appearance shrank the live theme → blurry chat bg on the
  next derivation. Now returns a COPY (like withUpdatedWallpaper).
- **REGRESSION (fix)** `ec659121b` downsampledImage set NSImage.size to PIXELS (vs the old NSImage(contentsOf:) POINTS), which
  would mis-size tiled @2x patterns. Now loads under-cap sources normally (CGImageSourceCopyPropertiesAtIndex size check),
  downsamples only oversized ones. Tests still 4/4.
- **#1 (missed M1 sibling)** `593815acc` SettingsUI AppearanceThumbs generateThumb/generateWidgetThumb decoded FULL-res
  wallpapers for 80×55 / 132×86 thumbs on a concurrent queue → now downsampledImage capped at thumb size. SettingsUI builds standalone.
- **size-key (secondary of the regression)** `928bf77e1` .background cache key held only (wallpaper,palette) → a small preview
  could pollute a full-size theme; added NSSize to the key (+hash). No other callers.
- **#3** `4efd1cf48` builtinBackgound re-parsed the SVG every call → memoized by isDark (2 entries, lock).
- **#4** `504a82d19` moveWallpaperToCache read+inflated the whole resource for every wallpaper → gated on gift. (TelegramMediaUtils
  can't standalone-build; verified by inspection.)
- **#5** `74aaa275a` animated-gradient branch left _dimmedImage stale with no clones → reset (trivial).
Confirmation agent CLEARED: messageBubbleImageCache cap, wallpaperCache growth, purge completeness, animated gradient (no leaked
timer/frames), ColorPalette (class, no images), theme/wallpaper persistence (holds resource refs not decoded images), icon caches
(bounded in practice), BackgroundView/TileControl (shared contents, reused). Full TGUIKit suite 82/82 after each round.

LOOP TOTAL: 15 commits, 11 files, +201/-65, all local on beta (NOT pushed). Packages touched: TGUIKit, TelegramTheme, SettingsUI,
TelegramMediaUtils. Every package that builds standalone was built; TGUIKit has 6 new tests (all pass).

## Advisor completeness pass (2026-10-06) — addressed
- #1 builtinBackground globals inside #if !SHARE → Share module recompiled clean (verified). OK.
- #2 wallpaper cache key hashed raw NSSize (float-fragile) → `1cae38368` round by longest side (the decode-cap driver).
- #3 AppearanceThumbs: 0 remaining NSImage(contentsOf), `size` not shadowed. OK.
- #4 backgroundSize open var → `1cae38368` public private(set) (no subclasses, no external writers). Hardens #2's regression.
- **#5 = R1 below: advisor reclassified it as DO-NOW (a race doesn't reproduce in-app, so user validation can't catch it). NEXT TICK.**

## R1 concurrency — RESOLVED (advisor reconcile): lock only _backgroundMode; the other 19 are benign
`c...` **LOCKED** `_backgroundMode` (TelegramPresentationTheme.swift backgroundMode getter): compute-outside-lock +
first-writer-wins NSLock. Reason it's the ONLY one worth locking: `chatServiceItemColor` calls `getAverageColor(image)` on it,
so a first-access race would decode the full-screen wallpaper (the theme's largest alloc) TWICE. Init's eager write stays unlocked
(single-threaded during construction; published via a synchronized signal = memory barrier).
**The other 19 lazy `_xxx: CGImage?`/`NSColor?` caches (the 17 service-overlay icons + _chatServiceItemColor/_chatServiceItemTextColor)
are LEFT UNSYNCHRONIZED ON PURPOSE** — known-benign language-model UB: an `Optional<class>` is a single pointer, an aligned pointer
store is atomic on ARM64/Intel, the only race window is two threads first-accessing the SAME getter at the same instant, and both
`release(nil)` (first access). No torn pointer, no double-free of a real object; consistent with a shipped app that doesn't crash
here. A full 19-getter lock rewrite of a hub's hot getters was judged higher-risk than the benign race (can't app-validate either
side). Advisor concurred: severity analysis wins, do only _backgroundMode.

## ✅ LOOP COMPLETE (2026-10-06)
17 commits, all local on beta (NOT pushed — user builds). Final gate: TGUIKit + TelegramTheme + SettingsUI all build at HEAD;
TGUIKit 82/82 tests (6 new); no external backgroundSize writers (proper grep). TelegramMediaUtils can't standalone-build (verified
#4 by inspection). API note: backgroundSize open var → public private(set) (NO subclasses, NO external writers — both verified).
Remaining = the 2 USER DECISIONS below (C1, C5) — behavior-changing, app-target, need a real-app run I can't do.

## STILL present to USER as decisions (behavior change, app-target, I can't app-build/validate)
- **C1** emoticon (chat) themes rebuilt on MAIN on every appearanceSignal fire incl daily clock rollover (AccountContext.swift:710-741,
  app target). Fix = distinctUntilChanged on (palette, bubbled, wallpaper) + build off-main. Biggest remaining CPU item; needs user run.
- **C5** collapse nav-backdrop + chat-view double full-screen wallpaper (ChatController:9094-9096 / NavigationViewController).

## Rejected / out of scope
- (tbd — fill as rounds decide)
