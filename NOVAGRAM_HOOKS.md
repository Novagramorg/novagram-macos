# NOVAGRAM_HOOKS.md — Novagram changes to Telegram-owned files

Base: official Telegram macOS 13.1.0 (`TelegramMessenger/telegram-macos` @ `272d85dd7`, 2026-10-25).
Old fork (overtake base, July 2025): removed on 2026-10-27, history in `~/Documents/Novagram-backups/macOS-old-fork-2026-10-27.bundle` (its hook list is `FENIXUZ_HOOKS.md` there).

## Rules

- Novagram code lives in our own packages (`packages/NovagramCore`, more later). Telegram files get only short call sites.
- Every line we change in a Telegram file ends with `// Novagram` (Swift) or is listed here (plist, pbxproj, entitlements, xcconfig), so `grep -rn "// Novagram"` finds all code hooks after an upstream pull.
- Edit Telegram files with exact line edits only. A formatter run over a Telegram file rewrites the whole file and breaks the next merge.
- `scripts/xcode27.sh apply` changes are local only (Xcode 27), never commit them (`scripts/xcode27.sh revert` before staging those files).
- Never push to `upstream` (push URL is disabled on purpose).
- Upstream updates go through `scripts/novagram-upstream-update.sh` (header explains the steps). It counts the `// Novagram` lines per file before and after the merge: a file with fewer lines means a hook was lost in the merge, restore it from this document.

## Easy upstream merges (owner's rules, 2026-10-28)

1. Never reformat a Telegram file; change only the lines a hook needs. `~/.claude/scripts/auto-lint.sh` (swiftlint --fix after every Edit/Write) reads `.claude/auto-lint-only` at the repo root: one bash glob per line against the path from the repo root, `*` also matches `/`, a leading `!` excludes, the first match wins, a file no line matches is not linted. The file is local (`.claude/` is gitignored); recreate it on a new machine:

   ```
   !submodules/*
   packages/NovagramCore/*.swift
   Telegram-Mac/novagram/*.swift
   fork-patches/*.swift
   */Novagram*.swift
   ```

   The telegram-ios submodule is excluded so the `fork-patches/` copies stay byte-identical for `scripts/novagram-upstream-update.sh`.
2. Thin hooks: a Telegram file gets an import and a 1–3 line call; the logic lives in NovagramCore or `Telegram-Mac/novagram/`. Whoever works on an existing fat hook thins it in the same change. On 2026-10-28 main had 83 Telegram Swift files with 389 added lines against the upstream merge base; the biggest: `ChatUI/ChatController.swift`, `ChatListUI/ChatListController.swift`, `AuthUI/AuthController.swift`, `ChatHistoryModel/SenderController.swift`.
3. Weekly upstream check: `~/Library/Application Support/Novagram/novagram-upstream-weekly.sh`, launchd job `uz.novagram.upstream-weekly`, Mondays 10:00. It fetches GitHub's main of both forks (macOS, iOS) and Telegram's master into small blobless mirrors (`~/Library/Caches/novagram-upstream/`) and trial-merges refs only, so it never touches a working copy or branch. The result is a macOS notification and `~/Library/Logs/novagram-upstream-weekly.log`. The update itself stays `scripts/novagram-upstream-update.sh`.

## Branding (2026-10-26)

### New files (ours)

| File                                                      | What                                                                                                                                              |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages/NovagramCore/`                                   | Novagram SDK package. `NovagramBranding` (Telegram → Novagram for texts we do not own, app menu), `installNovagramCoreHooks()`                          |
| `Telegram-Mac/Novagram.xcconfig`                          | Sparkle feed pointed at a dead local URL (the upstream feed would install official Telegram over us); Release = `APP_STORE` source and Swift flag |
| `Telegram-Mac/Assets.xcassets/NovagramAppIcon.appiconset` | Novagram app icon (copied from the old fork). Telegram's `AppIcon.icon` stays untouched and unused                                                |

### Telegram files

| File                                                                                                                               | Change                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages/ApiCredentials/Sources/ApiCredentials/Config.swift`                                                                      | `apiId`, `apiHash`, `bundleId = "uz.fenixuz.app"`, `teamId = "ZDBP5RSRZF"` (4 return values)                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `Telegram-Mac/Telegram-Mac.entitlements`, `Telegram-Mac/Telegram-Sandbox.entitlements`, `TelegramShare/TelegramShare.entitlements` | app groups and keychain groups `6N38VWS5BX.ru.keepcoder.Telegram[.TelegramShare]` / `6N38VWS5BX.ru.keepcoder.TelegramShare` → `ZDBP5RSRZF.uz.fenixuz.app[.TelegramShare]`                                                                                                                                                                                                                                                                                                                                                    |
| `Telegram.xcodeproj/project.pbxproj`                                                                                               | Telegram + TelegramShare targets: `DEVELOPMENT_TEAM = ZDBP5RSRZF` (×4), `PRODUCT_BUNDLE_IDENTIFIER = uz.fenixuz.app` / `uz.fenixuz.app.TelegramShare` (×4). Telegram target: `PRODUCT_NAME = Novagram` + `PRODUCT_MODULE_NAME = Telegram` (×2, module name kept so code and xibs still resolve `Telegram.*`), `ASSETCATALOG_COMPILER_APPICON_NAME = NovagramAppIcon` (×2). `NovagramCore` local package linked to both targets (folder reference, 2 build files, 2 product dependencies, IDs `FE10DEC04E14C190FEFE0001…0005`) |
| `Telegram-Mac/Debug.xcconfig`, `Telegram-Mac/Release.xcconfig`                                                                     | last line `#include "Novagram.xcconfig"`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `Telegram-Mac/Info.plist`                                                                                                          | `NSHumanReadableCopyright` = `Copyright © 2026 Novagram. All rights reserved.`, `CFBundleIconName` = `NovagramAppIcon`                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `TelegramShare/Info.plist`                                                                                                         | `CFBundleDisplayName` = `Novagram`, same copyright                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `packages/Localization/Sources/Localization/LocalizableExtension.swift`                                                            | `public var localizedValueTransform: (String) -> String = { $0 }` before `dictFromLocalization`; `dictFromLocalization` returns `dict.mapValues(localizedValueTransform)`; both bundle fallback returns in `_LocalizedStringFor` return `localizedValueTransform(resolved)`                                                                                                                                                                                                                                                  |
| `Telegram-Mac/app/main.swift`                                                                                                      | `import NovagramCore` after `import CrashRecoveryUI`; `installNovagramCoreHooks()` before `installTelegramThemeHooks()`                                                                                                                                                                                                                                                                                                                                                                                                            |
| `TelegramShare/ShareViewController.swift`                                                                                          | `import NovagramCore` after `import PasscodeCore`; `localizedValueTransform = NovagramBranding.rebrand` before `applyUILocalization(localization)`                                                                                                                                                                                                                                                                                                                                                                             |
| `packages/TelegramUtils/Sources/TelegramUtils/AppConstants.swift` | `itunesAppLink` = `https://apps.apple.com/app/id6768202244` (Novagram). Upstream pointed the "Update" button and other App Store links at Telegram |
| `Telegram-Mac/updater/AppUpdateViewController.swift` | `import NovagramCore`; first line of `updater_resetWithUpdaterSource`: `guard NovagramBranding.allowsTelegramUpdater else { return }`. Telegram's updater (non App Store builds) downloads official Telegram from a Telegram channel (`requestUpdatesXml(... updates_channel_xml)`, it ignores `SUFeedURL`) and would install it over Novagram |
| `Telegram-Mac/utils/Spotlight.swift` (2026-10-27) | `import TelegramUtils`; Spotlight contact items: `contentDescription` "Popular contact in \(appName)", `creator = appName` (were "telegram" / "Telegram"; old fork parity) |

Notes:

- The data folder inside the app group depends on the build source: Debug uses `<group>/debug`, App Store uses `<group>/appstore`, so a debug run never touches the installed App Store app's data.
- In-app "Telegram" → "Novagram" covers server language packs and the bundled English strings (old fork: `dictFromLocalization` hook + `en.lproj` edits). Strings hard-coded in Swift are not covered.
- `tg://` and `telegram://` URL schemes stay, so Telegram links still open in Novagram.
- The "Check for Updates" menu item (tag 1000) is removed by `installNovagramCoreHooks()` in every build; upstream removes it only in `APP_STORE` builds.
- `MARKETING_VERSION` is still upstream's `13.1.0`. Our App Store line is `1.0.x` (last shipped 1.0.5, build 137); pick the version before the first upload.

## Port of the old fork (branch `feature/novagram-port`, 2026-10-26)

Plan: `../PORT_MAP_macOS13.md`. Build with `./novagram-build.sh` (`./novagram-build.sh appstore` also sets `APP_STORE` inside the packages, see "APP_STORE" below).

### Step 1: identity and App Store hygiene

| File | Change |
| ---- | ------ |
| `Telegram-Mac/Info.plist` | `CFBundleDisplayName` = `Novagram` (after `CFBundleDevelopmentRegion`) |
| `Telegram-Mac/Telegram-Sandbox.entitlements` | removed `com.apple.developer.associated-domains` (`webcredentials:telegram.org`, 13.1 passkeys). telegram.org does not list our app id, so it can never validate for team ZDBP5RSRZF |
| `Telegram.xcodeproj/project.pbxproj` | Telegram's `Resources/config/GoogleService-Info.plist` removed from the app Resources phase (build file `274DF1DB2DC0BE0400188E7A`; the file reference stays). Firebase is not used (`FirebaseApp.configure()` is commented out upstream). `PrivacyInfo.xcprivacy` added (file ref `FE10DEC04E14C190FFFFFFF0` in group `supporting-files`, Resources build file `FE10DEC04E14C190FFFFFFF1`) |
| `Telegram-Mac/PrivacyInfo.xcprivacy` (ours) | copied from the old fork (no tracking; required-reason APIs UserDefaults CA92.1, FileTimestamp C617.1, DiskSpace E174.1, SystemBootTime 35F9.1) |
| `Telegram.xcodeproj/xcshareddata/xcschemes/{Release,Telegram,TelegramShare}.xcscheme` | `BuildableName = "Telegram.app"` → `"Novagram.app"` |
| `.gitignore` | Novagram block (`.claude/`, `screenshots/`, `*.bak`, `*.tmp`, `DerivedData/`, `Telegram-Mac/NovagramAds.local.xcconfig`) |
| `novagram-build.sh` (ours) | Debug build with the real pass/fail result (DerivedData `/tmp/tgmac13-dd`, log `/tmp/novagram13-build.log`) |

Not ported: the old `uz.fenixuz.macapp` → `uz.fenixuz.app` container migration (`ApiCredentials`). A sandboxed app can only open app-group containers listed in its entitlements, so the move never had access to the old group.

### NovagramCore package layout

Two products:

- `NovagramShare` (target `Sources/NovagramShare`, depends on Localization only): `NovagramBranding`. Linked by the share extension, which must stay light (TGUIKit/AlertsUI pull ffmpeg and opus into the appex and break its link).
- `NovagramCore` (re-exports `NovagramShare`): everything else. Linked by the app and by the Telegram packages that host our hooks.

`NovagramCore` contents copied from the old fork (app-target files there become `public` here): `NovagramGhostMode`, `NovagramL10n`, `NovagramBrandColors`, `NovagramSettingsIcons`, `NovagramDemoCodeFetcher`, `NovagramDeletedMessages` (temp `novagramdel.log` file logger dropped), `NovagramEditedHistoryManager`, `NovagramForeignUserBlock`, `NovagramForeignUserBannerView`, `NovagramHiddenChatsManager`, `NovagramChatPincodeManager`, `NovagramChatPincodeViewController`, `NovagramAutoApproveManager` (takes `any AccountContextProtocol`), `NovagramAutoProxy`, `NovagramSpeechToTextManager`, `NovagramAppStoreIAP`, `NovagramTextStyle` (enum split out of the old text style screen). New: `NovagramHooks` (closures the app installs so packages can open our app-target screens).

| File | Change |
| ---- | ------ |
| `Telegram.xcodeproj/project.pbxproj` | TelegramShare target links product `NovagramShare` instead of `NovagramCore` (build file `FE10DEC04E14C190FEFE0004`, product dependency `FE10DEC04E14C190FEFE0005`) |
| `TelegramShare/ShareViewController.swift` | `import NovagramShare` (was `import NovagramCore`) |

### APP_STORE

`APP_STORE` reaches the app target through `Novagram.xcconfig` (`TYPE[config=Release]`), but NOT the packages: 36 `#if APP_STORE` sites in packages (PremiumUI, StarsUI, AuthUI, SettingsUI, BoostUI, ChatUI, MessageUtils, TelegramTheme) need `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) APP_STORE'` on the `xcodebuild` command line, as `buildbox/build-mac.sh` does. Every App Store archive must pass it.

### Step 5: small package edits (no new hook structs)

Packages that now depend on `NovagramCore` (`.package(name: "NovagramCore", path: "../NovagramCore")` + product, both lines `// Novagram`): ChatHistoryModel, SidebarUI, StoriesUI, PeerInfoUI, ChatListUI, ChatUI. ShortPeerRow depends on product `NovagramShare` in its shared `common` list (its sources are symlinked into the `ShortPeerRowShare` target). Packages NovagramCore itself depends on (AlertsUI, GeneralRows, InputDataUI, InAppSettings, TelegramUtils, AvatarUI, …) must never import it: run `deps.py`-style checks before adding one.

| Feature | File | Change |
| ------- | ---- | ------ |
| F30 whole-chat translate without Premium | `ChatHistoryModel/.../ChatLiveTranslateContext.swift` | `if !peer.isPremium && !NovagramPremiumUnlock.wholeChatTranslate {`; both `return (…, peer?.isPremium == true || NovagramPremiumUnlock.wholeChatTranslate, autoTranslate)` |
| F30 folder tags without Premium | `SidebarUI/.../ChatListFilterController.swift` (`toggleColor`), `ChatListFiltersListController.swift` (`toggleTags`) | `&& !NovagramPremiumUnlock.folderTags` on the Premium check |
| F56 unlimited folders (2026-10-26) | `SidebarUI/.../ChatListFiltersListController.swift` (`let limit`, last-row `viewType`, "Add a Custom Folder" row), `ChatListUI/.../ChatListController.swift` (`updateFilter`) | client cap `NovagramPremiumUnlock.folderLimit`: 1000 when Settings → Novagram → "Unlimited folders" (`pro_messager/unlimited_folders`, default off) is on, else 0 so `max(...)` keeps the Telegram limits exactly. Same idea as the iOS `UserLimitsConfiguration` hook. When on: "Add a Custom Folder" no longer opens "Limit Reached" after 10 (free) / 30 (Premium) folders, and opening a folder past the 10th no longer shows the upsell. The server still applies its own cap when a folder is saved |
| F29 story save + HD without Premium | `StoriesUI/.../StoryModalController.swift` (HD item, save item), `StoryChatContent.swift` (`preferHighQualityStories`) | `context.isPremium \|\| NovagramPremiumUnlock.storiesSaveAndHD`; `setting && (isPremium \|\| …)`. The old fork never changed `StoryChatContent`, so HD there was cosmetic |
| F31 ID row | `PeerInfoUI/.../{User,Group,Channel}InfoEntries.swift` `case .peerId` | label `ID`, copy menu "Copy ID", click copies too, toast "ID copied" (`NovagramL10n.peerInfo_*`). Channel value `-100<id>`, legacy group `-<id>` |
| F31 ID row on by default | `InAppSettings/.../FastSettings.swift` `canViewPeerId` | reads `pro_messager/show_peer_id`, then `kCanViewPeerId`, default `true`; setter also writes `show_peer_id` |
| F31 Novagram Info | `PeerInfoUI/.../PeerInfoController.swift` | `getRightBarViewOnce` → `BarView(40, …)`; `viewDidLoad` adds the info button (`novagramAddInfoButton`); `requestUpdateRightBar` recolours it. New file `PeerInfoUI/.../NovagramPeerInfoModal.swift` (modal + button helpers). `viewDidLoad` takes `super.getRightBarViewOnce()`, which is the `StackedBarView` (the `BarView(40)` override is not used there), so the helper inserts the button with `stackedBar.insertButton(at: 0, …)`; a raw subview was drawn under "Edit" (2026-10-26) |
| F43 auto-approve (peer info) | `PeerInfoController.swift` entries `mapToQueue` | `NovagramAutoApproveManager.shared.checkAndApprove(...)` when `joinRequestsCount > 0` |
| F32 mutual contact 🤝 | `ChatListUI/.../ChatListRowItem.swift` (title), `ShortPeerRow/.../ShortPeerRowItem.swift` (title) | `NovagramMutualContact.title(_, for:)` (in `NovagramShare`) |
| F16 view first message | `ChatUI/.../ChatController.swift` chat "…" menu after Info | item when `pro_messager/show_view_first_message`, calls `chatInteraction.scrollToTheFirst()` |
| F41 phone retry | `ChatController.swift` phone-number menu | "Retry" item when the number did not resolve (`peer == nil`) |
| F10 chat list paging | `ChatListUI/.../ChatListController.swift` | `novagramPageRetry` property; scroll handler is now the `pageScrollHandler` constant; dropped request inside the 0.5 s guard is rescheduled. New file `ChatListUI/.../NovagramChatListPageRetry.swift` |
| F23 app name | `TelegramUtils/.../System.swift` | `appName = "Novagram"` (alert headers etc.) |
| F23 archive name | `ChatHistoryModel/.../SenderController.swift` | `"Novagram Archive"` |
| F23 About | `SettingsUI/.../AboutModalController.swift` | `APP_VERSION_STRING` drops the build-type suffix (Stable/AppStore/Beta); copyright `Copyright © <year> NOVAGRAM` |
| F40 "Update app" | `ChatUI/.../ChatMessageItem.swift` `invokeUpdateApp` | `#if APP_STORE \|\| true`: always opens `itunesAppLink` (Novagram App Store page), never the Sparkle check |
| X-C2-2 crash recovery | `CrashRecoveryUI/.../CrashRecovery.swift` | App Store link → Novagram (`id6768202244`), website → `https://novagram.org` |

Decision: the old Mac build's red accent palette (`#b40000` / `#ff3b30`, from the Novagram brand) is NOT ported. The Novagram icon and the iOS app are blue, and Telegram's own blue palette stays.

### Step 7: chat and chat list features

New dependency on NovagramCore (both Package.swift lines `// Novagram`): GalleryUI, AudioPlayerCore (ChatUI, ChatListUI, StoriesUI, ChatHistoryModel already had it).

New Novagram files inside Telegram packages (ours, whole file):

| File | What |
| ---- | ---- |
| `ChatUI/.../NovagramAskBeforeSend.swift` | `novagramConfirmBeforeSend` alert for stickers / voice |
| `ChatUI/.../NovagramMessageMenuItems.swift` | forward without sender name, edit before forward, edit history item |
| `ChatUI/.../NovagramRoundVideo.swift` | attach menu item + sender for round video from a file |
| `ChatListUI/.../NovagramGhostButton.swift` | Ghost toggle in the chat list header (assets `NovagramGhostActive/Inactive.imageset` in `Telegram-Mac/Assets.xcassets`) |
| `ChatListUI/.../NovagramChatListMenu.swift` | chat lock set/remove (when a master PIN exists) and hide/unhide items |
| `NovagramCore/NovagramOutgoing.swift`, `NovagramChatListFilter.swift`, `NovagramChatLockGate.swift` | helpers the hooks below call |

| Feature | File | Change |
| ------- | ---- | ------ |
| F14 deleted messages | `ChatUI/.../ChatController.swift` | `deletedMessagesDisposable` (+ dispose in deinit); `viewDidLoad` subscribes to `account.stateManager.deletedMessages` → `NovagramDeletedMessages.recordDeleted`, re-sets the location when a tombstone was created; history pass `let msgEntries = NovagramDeletedMessages.shared.process(view.entries, ...)` |
| F15 edit history | `ChatController.swift` history pass | `NovagramEditedHistoryManager.shared.processMessages(...)` |
| F15 edit history menu | `ChatUI/.../ChatMessageMenuItems.swift` edited-at block | `novagramEditedHistoryMenuItem` → `NovagramHooks.presentEditedHistory` |
| X-A-1 / X-A-2 | `ChatMessageMenuItems.swift` after `secondBlock.append(forwardItem)` | `novagramForwardMenuItems` |
| F13 Ghost (chat) | `ChatController.swift` | passive read `applyMaxReadIndex` gated; send path applies the read index while Ghost is on (replying implies reading); `canInteractiveRead` returns false; `clearMentions`, `clearReactions`, view counts, mention seen, reaction seen (reaction animation still plays), live location seen, recording activity gated |
| F13 Ghost (typing) | `ChatUI/.../ChatInputView.swift` | `.typingText` only when Ghost is off or `isPresent == false` |
| F13 Ghost (media) | `GalleryUI/.../GalleryViewer.swift`, `ChatUI/.../SingleTimeMediaViewer.swift`, `AudioPlayerCore/.../AudioPlayerController.swift` | `markMessageContentAsConsumedInteractively` skipped while Ghost is on |
| F13 Ghost (stories) | `StoriesUI/.../StoryChatContent.swift` | the three `markAsSeen(id:)` return early |
| F13 Ghost (chat list) | `ChatListUI/.../ChatListRowItem.swift` `markAsRead` | `clearPeerUnseenPersonalMessagesInteractively` gated; `PeersListController.swift` header: `ghost` button next to proxy (update, title width, layout) |
| F21 ask before send | `ChatController.swift` | `sendAppFile` and `sendMedias`: the original `invoke` closure is renamed (`novagramSendAppFile` / `novagramSendMedias`) and `invoke` now asks first; `sendMedia` (recorded voice) is renamed `novagramSendMedia` and the new `chatInteraction.sendMedia` asks first (cancel also cancels the voice send animation). The old fork only gated `sendMedias`, so recorded voice was never confirmed |
| F17 outgoing transforms | `ChatHistoryModel/.../SenderController.swift` | text `enqueue` gains `skipAutoTranslate: Bool = false`; auto text + auto translate after the media preview block; style entity appended to the text entities; heart effect (`NovagramOutgoing.effectId`) in the text path and in `enqueue(media:[Media]...)`; `recordSent(media)` remembers the last sticker; `sendAutoSticker` after the text messages are enqueued |
| F19 round video | `ChatUI/.../ChatInputAttachView.swift` | item after the File item (hidden when the channel bans round videos) |
| F11 / F12 hidden chats, foreign block | `ChatListUI/.../ChatListController.swift` | one `prepare.removeAll(where: NovagramChatListFilter.isFiltered...)` after the pending-removals filter (covers additional items too); Cmd+Shift+H installed once (`NovagramHiddenChatsShortcut.install()` in `viewDidLoad`; the old fork added a monitor per chat list) |
| F28 hide folders | `ChatListController.swift` | `novagramLastFolderTabs`, both tab subscriptions use `NovagramChatListFilter.hideFolders ? [] : filters.list`; a block observer of `NovagramSettingsChanged` (generic class, no `@objc`) re-applies tabs and stories; removed in `deinit`. It calls `updateFilter` only when the tab list really changes: `updateFilter` runs the upstream non-Premium folder gate, so any Novagram switch opened "Limit Reached" while a folder past the 10th was selected (2026-10-26) |
| F29 hide stories | `ChatListController.swift` (archive/stories group row), `PeersListController.swift` `hasStories` | `NovagramChatListFilter.showStories`. `PeerListState.novagramSettingsRevision` (Int) is bumped by the `NovagramSettingsChanged` observer: the state promise ignores repeated values, so the old `updateState { $0 }` never redrew, and the stories header and the header ghost icon (quick menu / settings toggles) stayed stale until the next real state change (2026-10-26) |
| F20 chat lock | `PeersListController.swift` `open(with:...)` first line | `NovagramChatPincode.requiresUnlock(...)` reopens with all arguments (incl. `fullWidthTopics`) after the PIN; unlocked chats stay open for the session |
| F20 / F11 row menu | `ChatListRowItem.swift` before `let blocks` | `thirdGroup.append(contentsOf: novagramChatListMenuItems(...))` |

Not ported: F33 "Sneak peek" row item. 13.1 has a native Preview item (`chatListContextPreview`), and the old item only opened the chat normally (it did send read receipts).

### Login (AuthUI)

AuthUI depends on NovagramCore (`// Novagram` on both Package.swift lines).

| Feature | File | Change |
| ------- | ---- | ------ |
| F22 NovagramProxy on login | `AuthUI/.../AuthController.swift` `AuthView` | Removed in b42efb88 (owner: it belongs in Proxy Settings). Now a switch at the top of Proxy Settings, see "Novagram logo in QR codes, NovagramProxy in Proxy Settings" |
| F37 demo login | `AuthController.swift` | `sendCode` first line `NovagramDemoCodeFetcher.prewarmIfDemo`; after `code_entry_c.update(...)` `autoFillIfDemo(... applyExternalLoginCode)`; `.passwordEntry` first line `dismissIfActive()` |
| F23 login logo | `AuthUI/.../Auth_PhoneNumber.swift` (`logo`), `Auth_Token.swift` (`logoView`, QR centre) | `NSImageView` with `NSApp.applicationIconImage` instead of the Telegram airplane Lottie (4.1 copycat risk) |

Not ported: the old emerald Next button (`NovagramBrandColors.primary`), same reason as the palette (blue brand).

### Novagram screens and managers (app target)

| File | What |
| --- | --- |
| `Telegram-Mac/novagram/` | Novagram Settings and its sub-screens (About, Tips, Text style, Auto-text, Auto-translate, Translation language, Bots, All accounts, Analytics, Edited history) and the app-side managers (UnreadReminder, SuggestedFolders, Analytics; the Statistics client is in NovagramCore since 2026-10-27, see "NovagramServices SDK"). `NovagramSuggestedFolders.swift` also holds `NovagramAdminFoldersManager` (2026-10-26), a port of the iOS `FenixAdminFoldersManager`: the "Admin Folders" switch (`pro_messager/fenix_admin_folders`, same key as iOS) keeps 4 real folders (👑/🔑 groups and channels, explicit chats) in sync on launch, account switch and app activation. It replaces the old one-shot "Create admin folder" action, which put every group and channel into an "Admin" ⭐️ folder; that folder is removed as a previous layout. Unlike iOS it only creates a folder while the Telegram folder limit has room, because the server rejects the rest with `DIALOG_FILTERS_TOO_MUCH`. The screens use the concrete `AccountContext` and the bridge `TableViewController`. Auto-text is now an `InputDataController` (13.x has no `GeneralInputRowItem`); keys `auto_text_enabled` and `auto_text_content` are unchanged. The hidden "Remove all ads" section is left out until `NovagramAdsGate` is ported |
| `Telegram-Mac/novagram/novagram_bots.json`, `russia_proxies.txt` | App resources read through `Bundle.main` (Bots catalogue, `NovagramAutoProxy` pool) |
| `Telegram-Mac/novagram/NovagramSettingsLinks.swift` | `tg://novagrampro`, `tg://novagram/<f>`, `tg://fenixuz/<f>`, `tg://settings/novagrampro[/<f>]` (f = about, bots, tips, text_style, auto_text, auto_translate, translate_language, translation_language, language) |
| `Telegram-Mac/packages-integration/hooks/NovagramHooksInstall.swift` | `installNovagramHooks()`: `NovagramHooks.presentEditedHistory` pushes `NovagramEditedHistoryController`; `NovagramHooks.accountWillLogOut` calls `NovagramAnalyticsManager.shared.accountWillLogOut(accountId:)`; calls `installNovagramSettingsHooks()` |
| `Telegram-Mac/packages-integration/hooks/NovagramSettingsHooksInstall.swift` | Rows: Accounts 910, gold Novagram Settings 911, Novagram Bots 912, Analytics 913 (914 reserved for Ads Analytics). Hides paid rows and inline accounts |
| `packages/SettingsUI/Sources/SettingsUI/NovagramSettingsHooks.swift` | `NovagramSettingsHooks`: extra Settings rows (`rows(context, .accounts/.top)`, ids 900–998), `selectedRowId`, `rowsUpdated`, `hidePaidRows`, `showInlineAccounts`, `versionRowClick` (reserved for the ads gate). Neutral defaults |

### Settings, accounts and app shell (Telegram files, every line `// Novagram`)

| File | Change |
| --- | --- |
| `Telegram-Mac/app/main.swift` | `installNovagramHooks()` after `installNovagramCoreHooks()` |
| `packages/SettingsUI/.../AccountViewController.swift` | `case novagram(index:viewType:row:)` + stableId/index/item lines; Novagram rows before Add Account and before My Profile; inline account loop gated by `showInlineAccounts`; Premium/Stars/TON/Business/Gift block gated by `!hidePaidRows` (F01, Apple 3.1.1); version row asks `versionRowClick` first; `appUpdateState` combined with `rowsUpdated`; selection branch from `selectedRowId` |
| `packages/SettingsUI/.../EditAccountInfoController.swift`, `LogoutViewController.swift` | literal `3` account limit → `maximumNumberOfAccounts` (2 lines each) |
| `packages/TelegramUtils/.../AccountUtils.swift` | `maximumNumberOfAccounts = 999` |
| `packages/InAppSettings/.../AccountsLimit.swift` | `normalAccountsLimit = 999` |
| `Telegram-Mac/packages-integration/hooks/SettingsHooksInstall.swift` | `appUpdateState = .single(nil)` (no Sparkle "Update" row) |
| `Telegram-Mac/app/MainViewController.swift` | `UpdateTabController`: both update-pill branches behind the never-set `NOVAGRAM_UPDATE_PILL` (2 `#if` lines) |
| `Telegram-Mac/app/AppDelegate.swift` | `import NovagramCore`; `applyMaxReadIndexInteractively` skipped in Ghost mode; `NovagramAnalyticsManager.shared.start(sharedContext:)` and `NovagramAutoProxyManager.shared.start(accountManager:)` after `sharedApplicationContextValue`; `Dock.setCustomAppIcon(path: nil)` before `launchInterface()` |
| `packages/AlertsUI/Sources/AlertsUI/Alerts.swift` `alert(for:header:info:…)` (2026-10-26) | default `header` `"Telegram"` → `appName` (`"Novagram"`, TelegramUtils). Every info alert without an explicit header showed "Telegram" as its title; the literal never goes through `NovagramBranding.rebrand` |
| `Telegram-Mac/app/MainViewController.swift` (2026-10-26) | Settings tab quick menu (right click on the gear): after the upstream "Mute For 2 Hours" item, `items.append(contentsOf: novagramQuickMenuItems(context:selectSettingsTab:))` adds a separator, Enable/Disable Ghost Mode, Show/Hide Hidden Chats and Novagram Settings (no NovagramProxy item, owner's choice) (function in `novagram/NovagramSettingsLinks.swift`). `NovagramHiddenChatsManager.isRevealed` is now `public private(set)` for the menu title |
| `Telegram-Mac/app/ApplicationContext.swift` | `import NovagramCore`; unread reminder start (after `AppMenu.closeAll()`), then `NovagramAdminFoldersManager.startGlobalMonitor(context:)` (admin folders sync on launch and account switch, 2026-10-26), clear (in `clearReadNotifiesDisposable`), stop (deinit); hide folders also hides the folder rail: `novagramEffectiveSidebar(_:)`, `novagramEffectiveSidebarShown`, used in `updateLeftSidebar` (bar position, current/previous), split-view insets and `applyWindowChrome`; `NovagramChatListFilter.settingsChanged` observer → `novagramHideFoldersRailChanged` |
| `Telegram-Mac/account/SharedWakeupManager.swift` | `import NovagramCore`; no online presence in Ghost mode; `NovagramGhostMode.didChangeNotification` observer → `updateAccounts()` |
| `Telegram-Mac/account/AccountContext.swift` | `requestApplicationIcons` commented out (no server app icons) |
| `Telegram-Mac/utils/UNUserNotifications.swift` | `import NovagramCore`; notification dismiss does not mark read in Ghost mode |
| `Telegram-Mac/utils/InAppLinks.swift` | `case novagramSettings(link:context:feature:)`, its `link` accessor, `execute` case, and the pre-check in `inApp(for:)` before `parseInAppLink` |
| `Telegram.xcodeproj/project.pbxproj` | group `novagram` (`FE304E0B0000000000000001`) under `Telegram-Mac`; all app files above as `FE304E0B…0002`–`…002B` (Sources / Resources of target `Telegram`) |

### F18 speech-to-text button

| File | Change |
| --- | --- |
| `ChatUI/.../NovagramSpeechToTextButton.swift` (ours) | button + `NovagramSpeechToTextManager` driver. Sits inside the message field, left of the emoji/actions buttons (13.1 rebuilt the input around the glass row, so the old slot next to the send button is gone). Dictated text replaces the input; any manual change of the input stops dictation. Setting `pro_messager/stt_enabled` (default off since 2026-10-26, as on iOS; the old Mac build had it on) |
| `ChatUI/.../ChatInputView.swift` `ChatInputContainerView` | `novagramSpeechToText` lazy property; `textViewSize` reserves `NovagramSpeechToTextButton.reservedWidth`; `updateLayout` places the button after the actions view (hidden for rich drafts and non-text input states) |

### App Store gates and Release hygiene

| File | What |
| --- | --- |
| `Telegram-Mac/novagram/NovagramBlockingPurchaseManager.swift` (ours) | 3.1.1 StoreKit chokepoint: `buyProduct` shows the blocked alert and fails with `.cantMakePayments`, `restorePurchases` alerts and returns `.succeed(false)`, products and `canMakePayments` forward to the real manager |
| `novagram-publish.sh` (ours) | App Store archive (`SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) APP_STORE'` on the command line so packages get it) into `build/archives/`, `--preflight` setting checks and `--check <xcarchive>` checks (sandbox, no get-task-allow, team, no Sparkle, no SU* keys, PrivacyInfo, bundle id). Uploads nothing |
| `Telegram-Mac/account/AccountContext.swift` | `inAppPurchaseManager` wrapped in `NovagramBlockingPurchaseManager` |
| `Telegram-Mac/packages-integration/hooks/FeatureNavigationHooksInstall.swift` | `makePaymentsCheckoutController` and `...WithContext`: `shouldBlock(invoice:source:)` → alert, `completion?(.cancelled)`, `nil` (covers Premium boarding, gifting, star gifts, giveaways, Stars top-up) |
| `Telegram-Mac/packages-integration/hooks/ChatUIHooksInstall.swift` | `showPaymentsCheckout` and `...WithContext`: invoice gate (`.message`) |
| `Telegram-Mac/packages-integration/hooks/BrowserHooksInstall.swift` | `presentBrowserInvoice`: invoice gate (`.slug`), returns `cancelled` |
| `Telegram-Mac/utils/InAppLinks.swift` | `executeInvoiceLink` card branch: invoice gate (`.slug`) |
| `Telegram-Mac/packages-integration/hooks/TelegramLinksHooksInstall.swift` | `openExternalLink`: Fragment TON top-up (`fragmentTonAddFundsLink`) shows the blocked alert (Star_ListScreen, AddTonBalanceController). The same URL inside a chat message still opens |
| `packages/NovagramCore/.../NovagramAppStoreIAP.swift` (ours) | `shouldBlock(invoice:source:)` (non-XTR digital sources blocked; `.slug`/`.message` only when a subscription; TON resale open), `shouldBlockExternalPurchase(link:)`, generic alert text `iap_blockPurchases_*` (no link, no mention of official Telegram) |
| `Telegram-Mac/Novagram.xcconfig` (ours) | `OTHER_LDFLAGS[config=Release] = $(inherited) -Wl,-dead_strip_dylibs` (APP_STORE code never references Sparkle, so its load command goes) |
| `Telegram.xcodeproj/project.pbxproj` | Telegram Release `OTHER_LDFLAGS = ($(inherited), -ObjC)` so the xcconfig flag applies; Telegram and TelegramShare Release `CODE_SIGN_IDENTITY` = `Apple Development` (was empty: ad-hoc archive, "No Team Found in Archive"); Run Script phase `FE40A0B1C2D3E4F500000001` "Novagram: strip Sparkle (App Store)" after the Copy Files phases (Release only: removes `Sparkle.framework`, deletes `SUFeedURL`/`SUPublicDSAKeyFile`); `NovagramBlockingPurchaseManager.swift` (`FE304E0B…002C/2D`) |
| `.gitignore` | `build/` (release archives) |

### TelegramCore fork patches (prepared, applied with F06)

`fork-patches/telegramcore/NovagramBotAuthorization.swift` (13.1: `case let .authorization(authorizationData)`), `NovagramBotSession.swift`, `fork-patches/telegramcore-hooks.patch` regenerated against `release-13.1.1` (AccountStateManagementUtils, ManagedChatListHoles, ManagedMessageHistoryHoles, ManagedPendingPeerNotificationSettings, ChatListFiltering), `fork-patches/apply-telegramcore-patches.sh`.

### F39 strings

`Telegram-Mac/novagram/NovagramSettingsController.swift`: the rows the old fork hard-coded in Uzbek (ask before send, auto-approve, suggested/admin folders, footer) now use `NovagramL10n` (en/uz/ru).

### F06 bot-token login and passkeys

| File | Change |
| --- | --- |
| `fork-patches/` (applied to `submodules/telegram-ios`) | `NovagramBotAuthorization.swift` (`importBotAuthorization`, `ImportBotAuthorizationError`; 13.1 `internal import TelegramApi`, `case let .authorization(authorizationData)`), `NovagramBotSession.swift`, `telegramcore-hooks.patch`. Re-run `./fork-patches/apply-telegramcore-patches.sh` after every `git submodule update` |
| `packages/NovagramCore/.../NovagramLoginFeatures.swift` (ours) | `passkeys = false`, `botToken` (set by the app) |
| `Telegram-Mac/app/main.swift` | `#if !APP_STORE` `NovagramLoginFeatures.botToken = true` `#endif` (the package cannot see the app's flag reliably, so the app sets it) |
| `AuthUI/.../Auth_BotToken.swift` (ours) | bot token screen (header, token field, Next, help link to core.telegram.org/bots, Cancel, clipboard prefill) |
| `AuthUI/.../NovagramBotTokenLink.swift` (ours) | link styling + `novagramLoginWithBotToken` (import, 20 s timeout, connection-error retry alert) |
| `AuthUI/.../Auth_Token.swift`, `Auth_PhoneNumber.swift` | `botTokenButton` + `takeBotToken` (added only when `NovagramLoginFeatures.botToken`), styled in theme/measure, height added to the stack, placed under the passkey/QR buttons; controllers `novagramSetTakeBotToken` |
| `AuthUI/.../AuthController.swift` | `State.botTokenAvailable/botTokenError`; `bot_token_c`; `updateState` sets the link handlers and shows `bot_token_c` first when requested (`else if` keeps the upstream QR/phone flow); `loginWithBotToken`; `index(of:)` treats it like the QR screen; theme refresh |
| `AuthUI/.../AuthController.swift` `checkPasskeyAvailability` | `guard NovagramLoginFeatures.passkeys` — 13.1 App Store builds auto-open the macOS passkey sheet on the first screen; passkeys for telegram.org cannot work for our app id (the old published app had no passkeys) |
| `SettingsUI/.../PrivacyAndSecurityViewController.swift` | Passkeys row also requires `NovagramLoginFeatures.passkeys`; SettingsUI depends on NovagramCore (`// Novagram` Package.swift lines) |

### Novagram logo in QR codes, NovagramProxy in Proxy Settings

| File | Change |
| --- | --- |
| `packages/NovagramCore/.../NovagramQrLogo.swift` (ours) | app icon cut to a circle with a transparent ring (same as iOS `NovagramQrLogo`) |
| `AuthUI/.../Auth_Token.swift` | login QR centre `logoView` shows `NovagramQrLogo` |
| `InviteLinksUI/.../InviteLinkQrController.swift` | centre `logoView` is an `NSImageView` with `NovagramQrLogo` (was the airplane Lottie); exported QR image uses `.custom(NovagramQrLogo)` instead of `login_qr_cap` |
| `QrStudioUI/.../QrStudioExportStickers.swift` | `qrStudioDecodeExportPlane` returns the Novagram logo (one frame) instead of the airplane animation; covers the live QR Studio view and its export |
| `ProxyUI/.../NovagramProxyEntries.swift` (ours), `ProxyListController.swift` | NovagramProxy switch + description at the top of Proxy Settings; the data signal also listens to `NovagramAutoProxyManager.shared.uiState` |
| `AuthUI/.../AuthController.swift` | the "NovagramProxy" text link at the top of the login screen is removed (owner: it belongs in Proxy Settings). The login proxy icon still appears after 10 s without a connection (upstream), so blocked users reach Proxy Settings |

QrStudioUI, InviteLinksUI and ProxyUI depend on NovagramCore (`// Novagram` Package.swift lines).

### Novagram ads v2, app side

| File | What |
| --- | --- |
| `packages/NovagramAdsBinary/` | NovagramAds SDK 3.0 binary package (NovagramAds, NovagramInsights, NovagramInsightsUI xcframeworks, macos-arm64_x86_64, min macOS 12.0, Swift 6.4). Update with `scripts/vendor-novagram-sdk.sh <sdk build dir>` |
| `Telegram-Mac/novagram/NovagramAdsCenter.swift` + `NovagramAdActions`, `NovagramAdMenu`, `NovagramAdMessage`, `NovagramBannerAds`, `NovagramChatAds`, `NovagramSearchAds`, `NovagramVideoAds` | Ads logic (our ad first, Telegram's only as fallback and never for Premium, nothing while "Remove all ads" is on; events to our backend only). `NovagramAdsCenter`, not `NovagramAds`: that is the SDK module name |
| `Telegram-Mac/novagram/NovagramAdsGate.swift`, `NovagramAdsAdminAuth.swift` | "Remove all ads" gate (`pro_messager` keys `fenix_show_ads`, `fenix_ads_section_revealed`, same as iOS). Since 2026-10-27 the Developer section, like iOS: hold the Settings version row for 20 s, then release (`NovagramDeveloperSection.currentPressDuration`, measured from a local left-mouse-down monitor because Settings rows act on mouse up); revealing asks for the developer login ("Developer verification"), hiding needs nothing; an alert follows both ways. The old 10-click trigger is gone |
| `Telegram-Mac/novagram/NovagramInsightsEntry.swift` | F09 hidden "Ads Analytics" row (id 914; 20 quick clicks on "Novagram Settings" + admin login), opens the NovagramInsightsUI window. No GeneralRows hook (hub package): a click on another row no longer resets the count |
| `Telegram-Mac/packages-integration/hooks/NovagramAdsHooksInstall.swift` | installs every `NovagramAdsHooks` closure (from `installNovagramHooks()`); `openMediaIfOurs` returns early for non-ads |
| `scripts/novagram-ads-local-config.sh` | writes the git-ignored `Telegram-Mac/NovagramAds.local.xcconfig` (`NOVAGRAM_ADS_ENVIRONMENT`, default development) |
| `Telegram.xcodeproj/project.pbxproj` | `XCLocalSwiftPackageReference "packages/NovagramAdsBinary"` (`FE50AD500000000000000001`) in project `packageReferences`; products `…0002-0004` linked to the Telegram target only (build files `…0012-0014`); 12 Novagram sources (`…0020-0037`); Telegram target Debug + Release `MACOSX_DEPLOYMENT_TARGET = 14.0` (the SDK needs 12.0; 14.0 is the minimum the old Novagram shipped, and `scripts/xcode27.sh apply/revert` leaves it alone) |
| `Telegram-Mac/Info.plist` | `NovagramAdsEnvironment = $(NOVAGRAM_ADS_ENVIRONMENT)` |
| `Telegram-Mac/Novagram.xcconfig` | `NOVAGRAM_ADS_ENVIRONMENT = production`, `#include? "NovagramAds.local.xcconfig"`, `NOVAGRAM_ADS_ENVIRONMENT[config=Release] = production` |
| `packages/ChatListUI/.../SearchController.swift` (2026-10-27) | global peers section condition `if !remotePeers.1.isEmpty \|\| promoted != nil`: our SEARCH ad replaces Telegram's ad peers, so a query with no other global result still shows the section with our ad |
| `packages/NovagramCore/.../NovagramDeveloperFlags.swift` (2026-10-27) | Developer switches, iOS keys: `novagram_currency_rates_view`, `novagram_ads_panel`, plus the macOS-only `novagram_sticker_pack_save` (all off by default, per device), live signals on `.novagramDeveloperFlagsChanged`; `NovagramDeveloperSection` (20 s, press clock) |
| `Telegram-Mac/novagram/NovagramSettingsController.swift` (2026-10-27) | Developer section (header, "Remove all ads", "Show currency rates", "Novagram ads panel", "Save sticker packs", footer) while revealed |
| `packages/NovagramCore/.../NovagramStickerPackSaver.swift` (2026-10-27) | "Save All" for sticker and emoji packs (macOS only): folder picker, one subfolder per pack (short name), every file in its original format (`.tgs` / `.webm` / `.webp`) named `001_<emoji>.<ext>`, 60 s download timeout per file, result toast, Finder reveal. Texts `stickerPack_*`, `developer_stickerPackSave*` in `NovagramL10n` |
| `packages/EntertainmentUI/.../NovagramStickerPackSaveMenu.swift` (2026-10-27) | `novagramStickerPackSaveMenuItems`: the "Save All…" item (`MenuAnimation.menu_save_as`), empty while the "Save sticker packs" switch is off |
| `packages/EntertainmentUI/.../StickerPackPreviewModalController.swift` (2026-10-27) | header "…" menu, right after Share: `items.append(contentsOf: novagramStickerPackSaveMenuItems(context: context, packs: collections.map { ($0.info, $0.items) }))` |
| `packages/EntertainmentUI/Package.swift` (2026-10-27) | `("NovagramCore", "../NovagramCore")` in `deps` (NovagramCore does not depend on EntertainmentUI) |
| `Telegram-Mac/packages-integration/hooks/NovagramSettingsHooksInstall.swift` (2026-10-27) | "Currency rates" row (915) under Analytics while its switch is on; "Ads Analytics" row while F09 revealed it or the ads panel switch is on; `rowsUpdated` also watches both switches, so the rows come and go live; installs the press clock |
| `packages/NovagramCore/.../NovagramCurrencyRates.swift` (2026-10-27) | Currency rates page: SDK `CurrencyCalculatorView` (bar button → `MultiCurrencyView`), rates from `currencyRates.latest()`, state in `pro_messager` (`novagram_currency_converter_state`, `novagram_currency_favorites`, iOS keys), texts from iOS. NovagramCore now depends on TelegramTheme (theme colors) |
| `packages/ChatUI/.../ChatHeaderController.swift` `ChatAdHeaderView` (2026-10-27) | our bot ad photo (`NovagramAdAvatar`) gets `userInteractionEnabled = false`, so a click on it reaches the panel and opens the ad like a click on the text (iOS: the whole panel is one tap target) |

### NovagramServices SDK: review login and statistics (2026-10-27)

The review login endpoint, the demo phone and the Statistics API URL + key are no longer in this repo. They live (masked) in the private NovagramServices SDK (`Codingtech2/novagram-services-ios-sdk`, guide `docs/INTEGRATION.md`). Never paste them into this repo, a doc or a commit message.

| File | What |
| --- | --- |
| `packages/NovagramCore/Frameworks/NovagramServices.xcframework` | SDK v1.2.1 (core binary 1.2.0: answer cache, counts kept 1 h), dynamic, `macos-arm64_x86_64` slice only, min macOS 12.0; was v1.1.0 until 2026-10-27 |
| `packages/NovagramCore/Frameworks/NovagramServicesUI.xcframework` | SDK v1.2.1 SwiftUI cards (links NovagramServices, no copy of it), `macos-arm64_x86_64` slice only; `.binaryTarget(name: "NovagramServicesUI")`, a dependency of the `NovagramCore` target |
| `packages/NovagramCore/Sources/NovagramCore/NovagramStatisticsCardView.swift` | the only place that imports NovagramServicesUI: hosts `StatisticsCard` in an AppKit view, the app's header view (duck) goes into the card's header slot |
| `Telegram-Mac/novagram/NovagramAnalyticsController.swift` | Settings → Analytics like iOS: `gigagroup.tgs` duck (same file as iOS `BroadcastGroup.tgs`) over the SDK `StatisticsCard`; info icon shows a toast; texts in `NovagramL10n` (`analytics_*`) |
| `packages/NovagramCore/Package.swift` | `.binaryTarget(name: "NovagramServices", path: "Frameworks/NovagramServices.xcframework")`, a dependency of the `NovagramCore` target only (not `NovagramShare`). Xcode embeds and signs it; no pbxproj change for it |
| `packages/NovagramCore/Sources/NovagramCore/NovagramStatisticsClient.swift` | Bridge to `services.statistics` (completion API with `Bool` / counts, so the app never names an SDK type). Replaces the app-target `NovagramStatisticsClient.swift` + `NovagramStatisticsConfig.swift` (deleted; their 8 pbxproj lines `FE304E0B…001E`–`…0021` removed) |
| `packages/NovagramCore/Sources/NovagramCore/NovagramDemoCodeFetcher.swift` | `isDemoPhone` = `reviewLogin.isConfigured && reviewLogin.isReviewPhone(_:)`; each poll is `reviewLogin.fetchCode()` (`.invalidResponse` = no code yet, `CancellationError` = stopped by cancel / a new prewarm). Polling, timers, alert and tuned values are unchanged; `demoPhone`, the URL and `extractCode` are gone |
| `Telegram-Mac/novagram/NovagramAnalyticsManager.swift` | The SDK guide's rules (same as iOS): install "sent" flag in UserDefaults (`uz.fenixuz.app.Analytics.installRegistered`); `registerAccount` for every account added after launch; `accountWillLogOut(accountId:)` sends `deleteAccount`, then `registerAccount` if accounts remain; every account-list emission reconciles with the Keychain `deviceActive` flag. Device id unchanged (Keychain `uz.fenixuz.app.Analytics` / `deviceId`, UserDefaults fallback) |
| `packages/NovagramCore/.../NovagramHooks.swift` | `accountWillLogOut: (AccountRecordId) -> Void`, installed in `NovagramHooksInstall.swift` |
| `packages/SettingsUI/.../LogoutViewController.swift` | `import NovagramCore`; `NovagramHooks.shared.accountWillLogOut(context.account.id)` in the "Log out?" `successHandler`, before `logoutFromAccount` (2 lines) |
| `packages/SettingsUI/.../AccountViewController.swift` | `import NovagramCore`; the same call in the account row's log out `successHandler` (2 lines) |
| `Telegram-Mac/novagram/NovagramAccountsController.swift` (ours) | the same call (to the manager directly) in All accounts → log out |

Updating the SDK: build it in the SDK repo (`scripts/build-xcframework.sh`) or take the release zip, remove the old copy, then

```sh
xcodebuild -create-xcframework -framework <build>/NovagramServices.xcframework/macos-arm64_x86_64/NovagramServices.framework -output packages/NovagramCore/Frameworks/NovagramServices.xcframework
xcodebuild -create-xcframework -framework <build>/NovagramServicesUI.xcframework/macos-arm64_x86_64/NovagramServicesUI.framework -output packages/NovagramCore/Frameworks/NovagramServicesUI.xcframework
find packages/NovagramCore/Frameworks -type f -print0 | xargs -0 ../novagram-services-ios-sdk/scripts/generate-secrets.sh --scan
```

Commit the copy only when the scan exits 0.

### Fixes after the visual check (2026-10-26)

- `AuthUI/.../Auth_BotToken.swift` (ours): the token field is one scrolling line (`maximumNumberOfLines = 1`, `cell.wraps = false`, `isScrollable`); a 45+ character token used to wrap and get clipped.
- `NovagramL10n.botlogin_error_invalid`: shortened (`LoginErrorStateView` is a single line and cut the long text at both ends); `botlogin_info` and the NovagramProxy strings say Novagram instead of Telegram.

## iOS parity (branch `feature/ios-parity`, 2026-10-28)

iOS features that never reached the Mac, ported with the iOS `pro_messager` keys and iOS defaults. Plan: switches for features that were always on on Mac default to off, as on iOS.

### Phase 1: switches for code that already existed

| File | Change |
| --- | --- |
| `packages/ChatHistoryModel/.../SenderController.swift` | both heart-effect lines call `NovagramOutgoing.effectId(messageEffect?.id, peerId: peerId, isText: true/false)`: the heart goes only on text messages in private chats (iOS #34) |
| `packages/ChatUI/.../ChatMessageMenuItems.swift` | edited-history item: `if let item = novagramEditedHistoryMenuItem(...) { sevenBlock.append(item) }` (the item is nil while `edited_history_enabled` is off) |
| `Telegram-Mac/app/ApplicationContext.swift` | `NovagramSuggestedFolders.presentFirstLaunchPromptIfNeeded(context:)` after the admin folders monitor start |

Ours: `NovagramL10nParity.swift` (strings), `NovagramPremiumUnlock` (`wholeChatTranslate` = `fenix_translate_chats_unlock`, `storiesSaveAndHD` = `fenix_story_unlock_enabled`, both off by default), `NovagramOutgoing` (auto sticker kept in `auto_sticker_data`), `NovagramMessageMenuItems` (`forward_hide_names` gates "Forward without Quotes" only, `edited_history_enabled` default on), `NovagramRoundVideo` (`round_video_from_gallery`), `NovagramSuggestedFolders` (`fenix_features_folders_prompt_enabled`, once per install via `fenix_features_firstrun_done`), Novagram Settings rows.

### Phase 2: translation

| File | Change |
| --- | --- |
| `packages/ChatUI/.../ChatController.swift` | first line of `chatInteraction.sendMessage` (after the DEBUG block): `if let strongSelf = self, novagramTranslateConfirmIntercepts(chatInteraction:resend:) { return }` |

Ours: `NovagramTranslateConfirm.swift` ("Ask to translate on send", `translate_confirm_enabled`: three-button alert, Translate & Send / Send Original, Esc cancels; the answer re-runs the send once), `NovagramOutgoing.autoTranslateLanguage` is nil while that switch is on (iOS: the prompt wins over auto-translate), `NovagramSpeechToTextButton` translates the finished dictation (`voice_translate_enabled`, target `auto_translate_lang`, default `en`, skipped when the user edited the text). The two switches turn each other off.

### Phase 3: reminder time and sound

No Telegram file changed. Ours: `NovagramUnreadReminderManager` reads the iOS key `unread_reminder_minutes` (default 5; the old Mac key `unread_reminder_interval` is copied once and removed), follows `NovagramSettingsChanged` (the Settings switch now starts and stops the timer right away), localized notification text, `unread_reminder_sound`. The 12 iOS tones are NovagramCore resources (`Resources/ReminderSounds`, `resources: [.copy(...)]` in `packages/NovagramCore/Package.swift`, bundle `NovagramCore_NovagramCore.bundle`); a custom tone is played by the app (`NovagramReminderSounds.play`) and the notification goes out silent. The Mac repeating timer is unchanged. Settings: Reminder time (1–60 min menu) and Reminder sound (Default, 12 tones, None; picking one plays it).

### Phase 4: auto-download and light accent

| File | Change |
| --- | --- |
| `Telegram-Mac/app/ApplicationContext.swift` | `NovagramAutoDownload.applyIfNeeded(context:)` after the folders prompt (keeps a newly started account's auto-download off) |

Ours: `NovagramSettingsController.swift` `NovagramAutoDownload` (`auto_download_disabled` sets `AutomaticMediaDownloadSettings.automaticDownload` for every logged-in account; Mac has one switch for all networks) and `NovagramWhiteThemeAccent` (`white_theme_accent_enabled`: `LocalAccentColor` #0A9BF5 for `.day` and `.dayClassic`, re-applied with `installDefaultAccent()` when a light builtin theme is active; off removes only our accent). `NovagramBrandColors` now uses the iOS blue palette (was the old green, unused).

### Phase 5: chat list and folders

| File | Change |
| --- | --- |
| `packages/ChatListUI/.../ChatListRevealItem.swift` | `import NovagramCore`; folder tab `title` = `NovagramFolderStyle.tabTitle(tab.title, emoticon: tab.emoticon)`; tab entities dropped while the emoji is shown (3 lines) |
| `packages/ChatListUI/.../ChatListRowItem.swift` | menu call is now `novagramChatListMenuItems(peerId:peer:accountPeerId:savedMessages:context:)` |
| `packages/ChatUI/.../ChatController.swift` | `viewDidAppear`: `NovagramAutoApproveManager.shared.autoApproveIfNeeded(context:peer:)` |
| `Telegram-Mac/app/ApplicationContext.swift` | `NovagramAutoApproveManager.shared.start(context:)` after `applyIfNeeded`, `.stop()` after the reminder stop |

Ours: `NovagramFolderStyle` (`fenix_folder_display_style`: icon / text / auto, the header rebuilds the folders item on `novagramSettingsRevision`), "Recent actions" chat list menu item (`fenix_channel_history_button`, admin or creator of a channel / supergroup, `NovagramHooks.openRecentActions` → `ChannelEventLogController`), `NovagramAutoApproveManager` rewritten after iOS `NovagramAutoAcceptManager`: key `fenix_autoaccept_global` (old Mac key `auto_approve_join_requests` copied once), chat open + peer info + 60 s scan of the first 300 chats, 15 s cooldown per chat, importer contexts kept 30 s so `updateAll(.approve)` finishes.

### Phase 6: unlimited pins (TelegramCore)

New file `fork-patches/telegramcore/NovagramLocalPins.swift` (port of iOS `TelegramCore/Sources/Novagram/NovagramLocalPins.swift`, copied into `TelegramCore/Sources` by `apply-telegramcore-patches.sh`). Hooks, kept in `fork-patches/telegramcore-hooks.patch` (regenerated with `git -C submodules/telegram-ios diff -- submodules/TelegramCore/Sources/`):

| File (TelegramCore) | Change |
| --- | --- |
| `TelegramEngine/Peers/TogglePeerChatPinned.swift` | `var limitCount` (was `let`), `novagramServerLimit`, `limitCount = NovagramLocalPins.pinLimit(serverLimit:)` (1000 while `unlimited_pins` is on), `NovagramLocalPins.recordOverflow(...)` before the sync operation (4 lines) |
| `State/Holes.swift` | chat list hole: `setPinnedItemIds(... NovagramLocalPins.merged(serverItemIds:accountPeerId:groupId:))` |
| `State/ResetState.swift` | the same for `.root` after a state reset |
| `State/ManagedSynchronizePinnedChatsOperations.swift` | the same after the local/remote reconciliation |

App: Interface → Unlimited Pins switch; turning it off runs `novagramTrimPinnedChatsToServerLimit(account:)` for every logged-in account (unpins exactly the stored ids), then `NovagramLocalPins.clearAllAccounts()`. Known limit, same as iOS: drag reordering does not update the stored tail.

### Phase 7: Novagram Settings links

No Telegram file changed (the `tg://settings/novagrampro` routing in `InAppLinks.swift` already existed). Ours: `NovagramSettingsLinks.swift` takes the iOS kebab-case slugs (old underscore forms still work) and the `?f=<slug>` alias; a slug that is not a sub-screen scrolls to its row and highlights it (`NovagramSettingsController.focusSlug`). Every Novagram Settings row with a slug has a right-click menu: Copy link (toast) and Share link (`ShareModalController`). New row "Share Novagram Settings link" at the end of Automation, hint in its footer. The slug table (`novagramSettingsSlugs`) matches iOS `NovagramSettingsFeature`; Mac-only rows: `ghost-button`, `send-confirm-sticker`, `unlimited-folders`. The developer rows have no link, as on iOS.

### Phase 8: Spotlight and Siri

| File | Change |
| --- | --- |
| `Telegram-Mac/utils/Spotlight.swift` | `import NovagramCore`; `SpotlightContext` keeps a `NovagramSpotlightContacts(account:)` (property + init line); recent-peer items skip hidden / locked chats (`peers.filter { !NovagramSpotlightContacts.isExcluded($0.id) }`) |
| `Telegram-Mac/app/AppDelegate.swift` | first line of `application(_:continue:)`: `if novagramContinueSpotlight(userActivity, context: self.contextValue?.context) { return true }` |
| `Telegram-Mac/app/ApplicationContext.swift` | `novagramSpotlightAndSiriDidStart(context:)` after the auto-accept start |
| `Telegram.xcodeproj/project.pbxproj` | app target: `Telegram-Mac/novagram/NovagramAppIntents.swift` (Sources, ids `FE304E0B…2E/2F`) and `AppShortcuts.xcstrings` (Resources, ids `FE304E0B…30/31`) |

Ours:
- `NovagramSpotlightContacts` (NovagramCore): every contact of every account in Spotlight (name, @username, the cached small avatar), ids `novagram-profile:<accountId>:<peerId>`, domain `novagram.contacts.<accountId>` (deleted with the account). Hidden chats and locked chats are never indexed, and Telegram's own items for hidden chats are deleted. Opening a result shows the profile (another account: switches account and opens the chat).
- `NovagramAppIntents.swift`: App Intents (macOS 14+) Open Chat, Open Profile, Send Message (always asks first, text only, refuses hidden / locked chats), Set Ghost Mode, Unread Messages, Open Novagram Settings; `NovagramContactEntity` searches the current account's contacts; `NovagramShortcuts` (7 App Shortcuts, Siri phrases with the app name, English + Russian in `AppShortcuts.xcstrings`; Siri has no Uzbek). `updateAppShortcutParameters()` runs at account start.

## Apple font out of App Store builds (2026-10-28)

Transporter warned on 2.0.16 (ITMS 91182): `SFCompactRounded-Semibold.otf` (Telegram's bundled copy, in the app and twice in the share extension) is an Apple-provided font; uploads with it are rejected from 2027-10-01. Telegram only uses it before macOS 10.15 (`TGFont.avatar` / `roundTimer`); on 10.15+ the system rounded design is used, our minimum is macOS 14. No Telegram line is removed, so an upstream removal of the font merges cleanly and our steps become no-ops:

| File | Change |
| --- | --- |
| `Telegram.xcodeproj/project.pbxproj` | our app phase "Novagram: strip Sparkle (App Store)" (Release only) also deletes `Contents/Resources/SFCompactRounded-Semibold.otf` and the `UIAppFonts` key; new share-extension phase `FE40A0B1C2D3E4F500000002` "Novagram: remove the Apple font (App Store)" (Release only, after its fonts CopyFiles) deletes the font, the `fonts` folder and `ATSApplicationFontsPath` |
| `novagram-publish.sh` (ours) | preflight checks the new phase; archive check fails on any `SFCompact*.otf` in the bundle |

## Package asset catalogs compiled (2026-10-29)

2.0.16 crashed (EXC_BREAKPOINT in `EditImageControlsView.updateUserInterface`) when the photo editor opened: send a photo, right-click → Edit, 📎 → Edit. `ImageCanvasUI`, `CubeUI` and `PrivateCallScreen` declared `.copy("Resources/Assets.xcassets")`, so Xcode 27 copied the catalog as a raw folder (no `Assets.car`) and every `NSImage(resource:)` from those bundles trapped: the photo editor, the 1:1 call screen icons (`ic_microphoneoff` traps the same way), gift crafting. Checked outside the app: the shipped bundle traps, the same catalog compiled with `actool` loads.

| File | Change |
| --- | --- |
| `packages/ImageCanvasUI/Package.swift` | `resources: [.process("Resources/Assets.xcassets")]` (was `.copy`) |
| `packages/CubeUI/Package.swift` | the same |
| `packages/PrivateCallScreen/Package.swift` | the same |
| `novagram-publish.sh` (ours) | archive check: fails when a package bundle still holds a raw `.xcassets` folder (it fails on the 2.0.16 archive) |

Manual repro for regressions: send a photo to Saved Messages, right-click it → Edit, click 📎 → Edit: the photo editor must open. Start a 1:1 call: the call screen must show its buttons.

## Camera picker removed (2026-10-29)

The Novagram Settings "Camera picker" switch (`long_press_camera_selection`, iOS front/back camera on the video-message button) did nothing on the Mac: no Mac code read the key, and a Mac has one camera or none (Mac mini, Mac Studio). Removed the row, its link slug `camera-picker`, the About card and the strings. No Telegram file changed.

## Novagram Bots row only in the main Settings (2026-10-29)

Novagram Bots showed twice: in the main Settings list (`NovagramSettingsHooksInstall.swift`) and at the top of Novagram Settings. iOS has it only in the main Settings, so the Novagram Settings row is gone (About stays alone at the top). `tg://settings/novagrampro/bots` still opens the Bots screen. No Telegram file changed.

## Edited message history keeps media (2026-10-29)

Mac recorded only text versions, so a photo replaced by Edit showed "No previous versions recorded" and no picture. Now, like iOS (`EditedMessageHistoryAttribute` with media), a version is recorded when the text or the media changes (an upload that only turns a local photo into its cloud copy is skipped), with that version's own time. The media is kept as a base64 PostboxEncoder blob in the entry (`mediaData`, older entries decode without it). The Edit History screen shows every version with its time, text, photo or video thumbnail (other files as a line), and "Current" now shows the message's real edit time instead of the time the screen was opened. Only edits seen while the chat is open are recorded (unchanged). No Telegram file changed.

## Search results no longer vanish (2026-10-29)

Owner: search results appeared and then disappeared. Cause: our `NovagramAdsHooks.searchTelegramFallback` (SearchController line `adPeers = NovagramAdsHooks.shared.searchTelegramFallback(...)`) emitted twice for queries of 4+ characters: `[]` while our ads backend was still asking, then the settled value (log: `SEARCH source=none`, ~0.3 s later `served SEARCH → no ad`). SearchController's remote search map dedupes against a dictionary (`ids`) shared across emissions, so the second emission filtered out every remote and global result it had just shown. Fix in our files only: `NovagramAdsCenter.oursFirst(waitForOurs: true)` skips the pending value and `NovagramSearchAds.telegramFallback` sends exactly one value (`take(1)`, at most 1.5 s, then `[]`). Upstream `SearchController.swift` is unchanged (checked against upstream/master 30097e3be). No Telegram file changed.

## Developer switch "Don't send ad events" (2026-10-29)

Owner's rule: Ghost mode never touches ads (Telegram and Novagram ads work fully in Ghost mode; the Mac never gated them). For testing, Novagram Settings → Developer has a new switch `novagram_ads_events_off` (pro_messager, iOS key): while it is on, no ad view, click, action or video_open is reported, so an ad the backend shows once per user keeps showing for the developer.

| File | Change |
| --- | --- |
| `fork-patches/telegramcore/NovagramAdEvents.swift` (ours, copied into TelegramCore) | `novagramAdEventsOff()` reads the key |
| `TelegramCore/.../TelegramEngine/Messages/AdMessages.swift` (fork patch) | `if novagramAdEventsOff() { return }` first line of `AdMessagesHistoryContextImpl.markAsSeen`, `_internal_markAdAction`, `_internal_markAdAsSeen`: covers chat, video, gallery and search sponsored ads (3 lines) |

Ours: `NovagramDeveloperFlags.isAdEventsOff` / `adEventsOffSignal`, `NovagramAdsCenter.recordView` / `recordClick` / `recordVideoOpenIfOurs` return before the SDK call and before `markViewed` (so nothing is queued and the ad is not marked as seen; the click still opens the ad, no action watch starts), log line `… -> not sent (developer: ad events off)`. Settings row second in the Developer section. `NovagramAdActions` also checks the switch before `recordAction`, so a join / Start watch that began before the switch was turned on does not report (same as iOS).

Roles (2026-10-29), port of iOS: the developer login decides a role, `NovagramDeveloperRole` (NovagramCore, `NovagramDeveloperFlags.swift`), stored in `pro_messager` key `novagram_developer_role` as `"developer"` or `"director"`; no stored role or an unknown string means developer, so existing devices are unchanged. `developer` sees all five Developer rows; `director` sees only "Don't send ad events" and "Novagram ads panel". `NovagramAdsAdminAuth.verify` derives the PBKDF2 digest once (same salt, 600k rounds) and compares it in constant time with every digest in `credentials` (developer, director), returning the role or nil. A successful login from the 20 s hold (`NovagramAdsGate.logIn(as:)`) stores the role, then turns off every switch the role cannot see ("Remove all ads" off means `fenix_show_ads = true`, currency rates, sticker pack save) and posts `novagramDeveloperFlagsChanged`; the Settings list filters the rows live through `NovagramDeveloperRole.currentSignal`. The hidden Ads Analytics hold (`NovagramInsightsEntry`) accepts either login and does not change the role. No Telegram file changed.

## Local call recording (2026-10-29)

> 2026-10-30, owner rule "one unapproved feature = one switch, inside Developer": the `novagram_dev_call_recording` and `novagram_dev_call_data_saving` flags, their "(beta)" rows, strings (`developer_callRecording*`, `developer_callDataSaving*`) and signals are removed, and Settings → Calls is gone (`callRecording_section` removed). See "One switch per unapproved feature (2026-10-30)" below.

Owner: record 1:1 voice and video calls on the Mac, locally (Telegram has no 1:1 recording, nothing is sent to the other side). Novagram Settings → Calls: "Call recording" (`novagram_call_recording`, pro_messager, default off, Mac only, macOS 14+) and, while it is on, "Save to" (`novagram_call_recording_folder`, an app-scoped security-scoped bookmark; no folder = "Ask every time"). Turning the switch on opens a folder picker (Cancel keeps the switch on with "Ask every time"); the "Save to" row offers Choose Folder… / Ask Every Time. Link slugs `call-recording`, `call-recording-folder`. The first recording ever asks once about consent laws (`novagram_call_recording_warned`).

| File | Change |
| --- | --- |
| `packages/PrivateCallScreen/Sources/PeerCallAction.swift` | `case record = 94` in `PeerCallActionType`; `.record` cases in `title` (`novagramCallRecordTitle()`), `resource` (`novagramCallRecordResource`) and the VoiceOver label switch (7 lines); `needsLayout = true` after the button's text layout changes, so a new title (Record → Stop) is centered again (Telegram's titles never change, so it never re-laid out the label) (1 line) |
| `packages/PrivateCallScreen/Sources/PeerCallLogic.swift` | `specs.append(contentsOf: novagramCallRecordSpecs(external))` before the video specs (raw value 94 keeps the list sorted: Record comes first) |
| `packages/PrivateCallScreen/Sources/PeerCallScreen.swift` | first line of `setState`: `let signal = novagramCallRecordState(signal, window: self.window)` (re-renders the actions when recording starts/stops, reports call end and mute); `.record` callback in the actions switch → `novagramToggleCallRecording(self.window, self.external, external)` (3 lines) |
| `packages/PrivateCallScreen/Sources/Resources/Assets.xcassets/novagram_record.imageset` | new image: the Record button glyph (white, 1x/2x, same 30 pt size as `ic_video`) |
| `Telegram-Mac/Telegram-Sandbox.entitlements` | `com.apple.security.files.bookmarks.app-scope` = true (App Store build: the chosen folder survives relaunches). `Telegram-Mac.entitlements` (no sandbox) needs nothing |
| `Telegram-Mac/app/AppDelegate.swift` | first line of `applicationWillTerminate`: `NovagramCallRecording.shared.stopForQuit()` (before Telegram's `_exit(0)` for a running call), so quitting during a recording keeps the file |

Ours:
- `packages/PrivateCallScreen/Sources/NovagramCallRecordHooks.swift`: `NovagramCallRecordHooks` (installed in `Telegram-Mac/packages-integration/hooks/NovagramHooksInstall.swift`, defaults do nothing, so upstream tests see no new action) and the spec/toggle/state helpers. Record shows only while the switch is on (or a recording runs) and it is not a conference, in every call state before the end (waiting, requesting/ringing, connecting, active, reconnecting): the owner wants the recording to start with the ringback tone, which the app plays itself (`PCallSession.playTone`, `voip_ringback.caf`), so the app audio capture records it.
- `NovagramCallRecording` (NovagramCore, main thread): consent alert, Screen Recording permission (`CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`; denied → alert with System Settings → Privacy & Security → Screen & System Audio Recording and an Open Settings button, recording does not start; the very first request ever (`novagram_call_recording_capture_requested`) shows only the system prompt, not our alert), a red "REC mm:ss" badge on the call window (top left, after the window buttons; it is part of the window, so it is also in the video), auto stop on call end, window close or stream stop, saving (stored folder with `startAccessingSecurityScopedResource`, a stale bookmark is refreshed or falls back to the save panel; no folder → `NSSavePanel` with the file name; a failed folder save, a failed panel save or Cancel in the panel saves into ~/Downloads instead of deleting the recording), toast with "Show in Finder". Quit during a recording (`stopForQuit`, AppDelegate hook): the recorder stops and the app waits up to 3 s for the file, then moves it into the stored folder or ~/Downloads without any panel or toast. The microphone is the one chosen in Call Settings / the call device menu (`VoiceCallSettings.audioInputDeviceId`, read through `NovagramCallRecording.micDeviceId`, installed in `NovagramHooksInstall.swift`) at the moment the recording starts; a device change during a recording keeps recording the old microphone. File name `<peer name> <yyyy-MM-dd HH.mm>.mp4|m4a` (`/` and `:` → `-`), written to the container's temp folder first.
- `NovagramCallRecorder` + `NovagramCallAudioMixer` (NovagramCore, macOS 14+, own serial queue): ScreenCaptureKit on our call window (`SCContentFilter(desktopIndependentWindow:)`, app audio with `excludesCurrentProcessAudio = false` = the other side), microphone via SCK `captureMicrophone` (`microphoneCaptureDeviceID` = the call's input device) on macOS 15+ and `AVCaptureSession` (`AVCaptureDevice(uniqueID:)`) on macOS 14, the system default when the chosen device is missing, both mixed into one 48 kHz stereo AAC track by presentation time; video calls (our or the remote video active when Record is pressed) → H.264 mp4 of the window, ≤ 1280 px wide, ≤ 30 fps; voice calls → m4a. While the call is muted our microphone is silent in the file. Errors end the recording with a toast, never touch the call.

Manual repro for regressions: turn on Novagram Settings → Calls → Call recording, start a 1:1 call, press Record: REC timer runs; press again (or hang up): the file is saved (folder or save panel) and the toast offers Show in Finder; the file has both voices (and the picture for a video call).

## Call extras (2026-10-29)

> 2026-10-30, owner rule "one unapproved feature = one switch, inside Developer": the `novagram_dev_call_recording` and `novagram_dev_call_data_saving` flags, their "(beta)" rows, strings (`developer_callRecording*`, `developer_callDataSaving*`) and signals are removed, and Settings → Calls is gone (`callRecording_section` removed). See "One switch per unapproved feature (2026-10-30)" below.

Owner: four 1:1 call extras on the Mac. Novagram Settings → Calls: "Record every call automatically" (`novagram_call_recording_auto`, pro_messager, default off, shown only while Call recording is on, slug `call-recording-auto`) and "Use less data for calls" (`novagram_call_data_saving`, default off, slug `call-data-saving`; shown on every macOS, the recording rows stay macOS 14+). Noise suppression for 1:1 calls was not added: the 1:1 engine hard-codes WebRTC noise suppression on (`enableNS = true` in `tgcalls/macos/Sources/OngoingCallThreadLocalContext.mm`) and has no switch reachable from Swift.

| File | Change |
| --- | --- |
| `packages/PrivateCallScreen/Sources/PeerCallScreen.swift` | the existing `setState` hook now also passes `arguments: { [weak self] in self?.external }` (auto-record needs the engine and peer, the weak connection banner needs `toggleCamera`) |
| `packages/PrivateCallScreen/Sources/PeerCallScreenView.swift` | `settingsView.set(handler: …, for: .RightDown)` → `novagramShowCallDeviceMenu(control)`: right-click on the call screen's settings (gear) button opens the microphone / speaker quick menu (1 line) |
| `packages/TelegramCallsCore/Sources/TelegramCallsCore/PCallSession.swift` | `self.dataSaving = novagramCallDataSaving()` instead of `.never` (1 line) |

Ours:
- Auto-record: `NovagramCallRecordHooks.autoStart` (PrivateCallScreen) fires from `novagramCallRecordState` while the call is not a conference and is in `requesting(ringing: true)` (our ringback tone), `connecting`, `active` or `reconnecting` (an incoming call gets there only after it is accepted). `NovagramCallRecording.autoStart` starts once per call window (reset when the call ends, so a redial in the same window records again; a manual Stop is not undone), only while the window is visible, with the normal recorder and save rules. The consent alert shows at the first auto start if it was never accepted; Cancel turns auto-record off. Missing Screen Recording permission shows the existing explanation once per app run for auto starts (the Record button still shows it every time).
- Device menu: `NovagramCallExtrasHooks.showDeviceMenu` (PrivateCallScreen) → `novagramPresentCallDeviceMenu` (`packages/CallsUI/Sources/CallsUI/NovagramCallDeviceMenu.swift`): "Microphone: <current>" and "Speaker: <current>" submenus with System Default + every device, a checkmark on the current one. Choosing writes `VoiceCallSettings` (`withUpdatedAudioInputDeviceId` / `withUpdatedAudioOutputDeviceId`), the same setting as Settings → Voice & Video, so it persists; `DevicesContext.updater()` makes the running `PCallSession` switch at once.
- Weak connection banner: `NovagramCallWeakNetwork` + `NovagramCallWeakNetworkBanner` (`packages/PrivateCallScreen/Sources/NovagramCallExtras.swift`): when the call is `active` with reception ≤ 1 of 4 bars or `reconnecting` for 5 s, a pill "Weak connection" shows at the top center of the call window, with "Turn off my video" while our camera video is on (not paused, not a screencast); the button calls the call screen's own `toggleCamera`. It hides as soon as the connection recovers or the call ends.
- Data saving: `novagramCallDataSaving()` (`packages/TelegramCallsCore/Sources/TelegramCallsCore/NovagramCallDataSaving.swift`) reads `novagram_call_data_saving` (on = `.always`, off = `.never`); it is read when a `PCallSession` is created, so it applies to calls started after the change.
- Strings: `callRecording_auto_*`, `callDataSaving_*`, `callDevices_*`, `callWeakNetwork_*` in `NovagramL10nParity.swift`; hooks installed in `NovagramHooksInstall.swift` (`installNovagramCallExtrasHooks`, `hooks.autoStart`).

Manual repro for regressions: (1) turn on Call recording and Record every call automatically, call someone: REC starts with the ringback; answer an incoming call: REC starts on accept. (2) right-click the gear on the call screen: pick another microphone / speaker, the other side hears / you hear through it at once, Settings → Voice & Video shows the same choice. (3) Network Link Conditioner "Very Bad Network" during a video call: after ~5 s the banner shows, "Turn off my video" stops our camera. (4) Use less data for calls on, start a new call: the call log shows data saving `always`.
## Search plus, batch A (branch `feature/search-plus`, 2026-10-29)

> Dates / Unread only / Mentions only removed 2026-10-30 (manager scope), last on main at 9d9b178d4; logic in NovagramSearchKit. The hidden / locked chat privacy part of this section stays.

Plan: hidden chats were not filtered in global search (only `ChatListController.swift:1037` used the hidden-chats filter). Now they are, and they stay out even while hidden chats are revealed (owner's rule 2026-10-29: searching hidden chats defeats hiding them; `novagramSearchHides` and `NovagramSearchPrivacyPass` read `isPeerHiddenInStorage`). Search stays on the current account: an "Other accounts" section was built and removed the same day at the owner's request, and the Messages section gets a date range and "Unread only" / "Mentions only".

| File | Change |
| --- | --- |
| `packages/ChatListUI/.../SearchController.swift` | `novagramSearchFilter` promise (+ local capture); local peers `for rendered in peers.0 where !novagramSearchHides(rendered)`, link peer, both remote `let first = … && !novagramSearchHides(found.peer.id)`, top peers and recent peers skip hidden chats; hashtag and posts loops skip hidden / locked chats; Messages: `remoteSearch` combines the filter, `location…novagramDates(novagramFilter)`, `novagramFillFilteredPage(...)` after the request, the message loop goes through `novagramSearchKeptMessages(...)`; final combine gets the filter (9th argument); the Messages header stays while a filter is active (`|| novagramFilter.isActive`), its title shows the active filters and its dropdown gets `+ novagramSearchFilterActions(...)` (≈19 lines, each `// Novagram`) |

Ours: `packages/ChatListUI/.../NovagramSearchFilters.swift` (privacy checks; locked chats keep their name but not their messages; unread = incoming message after the peer's read index; mentions = `ConsumablePersonalMentionMessageAttribute` or `.unseenPersonalMessage`; up to 5 more pages are read while fewer than 20 messages pass; dates through `FeatureNavigationHooks.makeCalendarController`, "To" includes the whole day; `messages.searchGlobal` takes min/max dates, the Posts tab does not). Strings in `NovagramL10nParity.swift`.

## Search plus, batch B: translated query (branch `feature/search-plus`, 2026-10-29)

> Removed 2026-10-30 (manager scope), last on main at 9d9b178d4; logic in NovagramSearchKit.

With Settings → Novagram → Interface → "Search the translated query too" on (`pro_messager/novagram_search_translate`, default off), global search translates the query into the `auto_translate_lang` language (else `en`) and shows a "Translated: …" section of messages found by the translation. The switch text says the query is sent to Telegram's translation service.

| File | Change |
| --- | --- |
| `packages/ChatListUI/.../SearchController.swift` | final `combineLatest` gets `novagramTranslatedSearch(...)` as its 10th argument and the map a `novagramTranslated` parameter (`:1324–1325`, the 2 lines batch A already changed); one line before the Messages block adds the section (separator 19000, rows 19001+, highlighted with the translated text), deduped against the Messages section's message ids with its own `Set`, never through the shared `ids` (`:1386`) (3 lines, each `// Novagram`) |

Ours: `packages/NovagramCore/.../NovagramQueryTranslator.swift` (`engine.messages.translate(text:toLang:)`, only for 3+ characters, 600 ms debounce through a delayed start, in-memory cache keyed by language and query (200 entries, then cleared), no section when the translation equals the query ignoring case and spaces; while the switch is off the translate signal is never built or subscribed); `packages/ChatListUI/.../NovagramTranslatedSearch.swift` (common chat list search with messages, no tags, no `#`/`$`; its own `searchMessages(state: nil, limit: 20)` with the same "From" source and dates as the Messages section, no paging; messages go through `novagramSearchKeptMessages`, so hidden and locked chats and the unread / mentions filters apply as in batch A). The section sits at 19000, before Messages (not 25000 as planned): Messages pages more on scroll to the bottom, so a section after it would stay out of reach. Settings row in `Telegram-Mac/novagram/NovagramSettingsController.swift`, strings in `NovagramL10nParity.swift`.

## Search plus, review fixes (branch `feature/search-plus`, 2026-10-29)

> Unread / filter paging and the translated section removed 2026-10-30 (manager scope), last on main at 9d9b178d4; logic in NovagramSearchKit. The privacy lines of this section stay.

Hidden chats no longer show in the Apps and Channels tabs, the community search or "Show as messages"; locked chats' messages stay out of "Show as messages" too. "Unread only" keeps earlier pages, the filtered list keeps loading while it is short, the translated section no longer holds up the search.

| File | Change |
| --- | --- |
| `packages/ChatListUI/.../SearchController.swift` | `novagramAutoLoad` property and local capture (`:855`, `:927`); community linked peers `where !novagramSearchHides(peer.id)` (`:1233`); fill hook gets `previous:` and `autoLoad:` (`:1258`); `novagramWithReadStates(...)` after the cached-state line (`:1263`); the Messages and posts maps return `NovagramSearchPrivacy.keptResult(result.0)` (`:1287`, `:1664`), so the state kept for paging and for "Show as messages" has no hidden or locked messages; the two hashtag/posts loops use `novagramSearchPrivateMessages(...)` (`:1302`, `:1645`, one privacy pass per page instead of keychain calls per message); filter `update` also clears `searchMessagesStateValue` (`:1403`); Apps you use, popular apps, Channels you joined, recommended channels `where !novagramSearchHides(...)` (`:1505`, `:1528`, `:1565`, `:1590`); after the paging state is stored, `novagramAutoLoad.takeRequest()` loads the next page while the filtered list is short (`:1882`) (15 lines: 4 new, 11 changed, each `// Novagram`) |
| `packages/ChatHistoryModel/.../HashtagSearchGlobalChatContents.swift` | `import NovagramCore`; `updateHistoryView` drops hidden and locked messages with `NovagramSearchPrivacy.kept(...)`: covers the initial state and every loaded page (2 lines). ChatHistoryModel already depends on NovagramCore, so no hooks struct is needed |

Ours: `packages/NovagramCore/.../NovagramSearchPrivacy.swift` (`NovagramSearchPrivacyPass`: one `isMasterEnabled()` per pass, `isLocked` cached per peer; `kept`, `keptResult`). `NovagramSearchFilters.swift`: `novagramSearchPrivateMessages` replaces `novagramSearchHidesMessage`; `novagramSearchKeptMessages` uses the pass; `novagramWithReadStates` (Unread only) reads the read state of every peer the last page did not cover in one `postbox.transaction` (`getCombinedPeerReadState`), because TelegramCore keeps read states only for the last page; `novagramFillFilteredPage` counts matches added since the load started (each page with its own read states), still up to 5 extra pages per load; `NovagramFilterAutoLoad` asks for one more load when a load ends with fewer than 20 matches in total and the server is not done (at most 3 extra loads per query and filter, since a short list cannot scroll to trigger the next page). `NovagramTranslatedSearch.swift`: the section always starts with an empty value, so a cached translation cannot hold the other sections.

## Search plus, batch C: exact phrase and regex in a chat (branch `feature/search-batch-c`, 2026-10-29)

> Removed 2026-10-30 (manager scope), last on main at 9d9b178d4; logic in NovagramSearchKit.

Inside a chat's search, a query in double quotes (`"two words"`, curly quotes too) sends the words without quotes and keeps only messages containing the exact phrase (case- and diacritic-insensitive); `re:pattern` (lowercase `re:` only, so `Re: invoice` stays a plain search) scans the chat history (empty query, 100 per page, at most 2000 messages) with a case-insensitive `NSRegularExpression` (each message gets at most 50 ms, stopped through `enumerateMatches` with `.reportProgress`; each page at most 1 s, after that the search counts as finished), an invalid pattern falls back to a plain search for the text after `re:`. Normal queries make the same single request as before.

| File | Change |
| --- | --- |
| `packages/ChatUI/.../ChatController.swift` | `searchRequest:` closure: `context.engine.messages.searchMessages(...)` is passed to `NovagramChatSearchFilter.wrap(query:state:search:)`, the existing `map` stays (`:542`, 1 line changed, `// Novagram`) |

Ours: `packages/NovagramCore/.../NovagramChatSearchFilter.swift` (query parsing; filtering on `Queue.concurrentDefaultQueue()`; while a request adds fewer than 10 matches and the server has more, it fetches the next page, at most 5 extra pages per request; the result's `totalCount` is the number of matches loaded so far, so the header count shows them; messages already checked are not matched again on the next page; the last 8 paging states remember their match count, the checked message ids and whether they are finished (server done or 2000 messages scanned), so loading more after the cap returns the same result without a request; disposing the signal, when the query changes or search closes, cancels the paging). Hint sentence `about_searchHint` (en/uz/ru) in `NovagramL10nParity.swift`, appended to the About Novagram intro text in `Telegram-Mac/novagram/NovagramAboutController.swift`. The chat's in-message highlight still uses the typed query, so quoted and `re:` results are not highlighted inside bubbles.

## Search plus, batch C: saved searches (branch `feature/search-batch-c`, 2026-10-29)

> Removed 2026-10-30 (manager scope), last on main at 9d9b178d4; logic in NovagramSearchKit.

Global search remembers the query a result was opened from (trimmed, empty ignored, de-duplicated case-insensitively, last 20 plus unlimited pinned ones, per account). On the empty search screen a "Saved searches" section sits between the top peers strip and Recent: pinned first (marked "Pinned"), then recent. Clicking one puts the text back into the search field, which runs the search again; the right-click menu has Pin / Unpin and Remove. Text only: no tab, date or filter restore.

| File | Change |
| --- | --- |
| `packages/ChatListUI/.../SearchController.swift` | stable id `case novagramSavedSearch(String)` and its `hash` line (`:94`, `:137`); entry `case novagramSavedSearch(NovagramSavedSearchRow)` with its `stableId`, `index`, `==` and row lines (`:162`, `:198`, `:231`, `:344`, `:646`); `public var novagramSetQuery` (`:881`); the empty-screen `combineLatest` gets `NovagramSavedSearches.signal(accountPeerId:)` and the map a `novagramSearches` parameter (`:1754`, 1 line changed); after the top peers row one line adds the section and moves `i` past it, so Recent starts after it (`:1763`); first line of `selectionDidChange` runs a saved query through `novagramSetQuery` (`:2203`); before `self.open(id, messageId, close)` the current query is saved (`:2396`) (12 lines: 11 new, 1 changed, each `// Novagram`) |
| `packages/ChatListUI/.../PeersListController.swift` | `showSearchController`: `searchController.novagramSetQuery` calls `genericView.searchView.setString(_:)`, which fires the normal text-changed search (`:3245`, 1 line) |
| `Telegram-Mac/app/ApplicationContext.swift` | `NovagramSavedSearches.clear(accountRecordId:)` after `FastSettings.clear_uuid` in the `loggedOut` observer (session ended from another device) (1 line) |
| `Telegram-Mac/account/SharedNotificationManager.swift` | `import NovagramCore`; `logout()` clears saved searches of every active account after `appEncryption.remove()` (2 lines) |

Ours: `packages/NovagramCore/.../NovagramSavedSearches.swift` (JSON in the `pro_messager` suite under `novagram_saved_searches_<account peer id>`, holding the account record id too; `signal(accountPeerId:)` refreshes on every change; `clear(accountRecordId:)` removes the account's entry). `packages/ChatListUI/.../NovagramSavedSearchRows.swift` (rows with their own stable ids `novagramSavedSearch(query)`, the header is `novagramSavedSearch("")`, never `.separator(index)` and never the shared `ids` dictionary; header at `i + 1`, rows after it). Logout: `NovagramSavedSearches.clear` runs next to `NovagramAnalyticsManager.accountWillLogOut` in `Telegram-Mac/packages-integration/hooks/NovagramHooksInstall.swift` (Settings logout and the account menu) and `Telegram-Mac/novagram/NovagramAccountsController.swift`; the `loggedOut` observer in `ApplicationContext.swift` (session ended from another device) and `SharedNotificationManager.logout()` (log out of all accounts) clear it too. Strings `search_saved*` (en/uz/ru) in `NovagramL10nParity.swift`.

## Job search (branch `feature/job-search`, 2026-10-29)

A separate page for HR people and job seekers: "Find a job" (vacancies) / "Find candidates" (resumes), a role query with OR / NOT / exact phrase (`iOS | swift -junior "to'liq stavka"`), filters (City multi-select, Format, Period, default week, Only with salary), source switches, one merged list of matching posts newest first, deduplicated by `MessageId`, each as a card with avatar, chat, date, parsed title, salary / city / format / experience, a 3-line snippet and Open post / Write / Copy contact. Opened from the last tab "Jobs" of the global search category bar (see "Jobs tab" below; it replaced the first "Job search" row on the empty search screen). The tab is hidden while `pro_messager/novagram_search_features` is off (missing key = on; the Settings switch comes later on another branch); it reacts to `UserDefaults.didChangeNotification` without a relaunch. A page that is already open stays usable.

| File | Change |
| --- | --- |
| `packages/ChatListUI/.../SearchController.swift` | the empty-screen `combineLatest` takes `novagramSavedSearchSignal(context)` instead of `NovagramSavedSearches.signal(...)` (`:1754`); `selectionDidChange` runs `novagramSavedSearchSelect(item, context:setQuery:)` (`:2203`) (2 existing `// Novagram` lines changed, 0 new) |
| `Telegram-Mac/app/ApplicationContext.swift` | `novagramJobSearchDidStart(context:)` after the unread reminder start (`:515`), `novagramJobSearchDidStop(context:)` after its stop (`:1417`), `novagramJobSearchClear(accountRecordId:)` after `NovagramSavedSearches.clear` in the `loggedOut` observer (`:553`) (3 lines) |
| `Telegram-Mac/account/SharedNotificationManager.swift` | `logout()` clears the job search data of every active account after the saved searches line (`:327`, 1 line) |
| `Telegram-Mac/utils/UNUserNotifications.swift` | default action: `NovagramHooks.shared.handleNotificationClick(userInfo)` first; a job alert opens the page and returns (`:259`, 1 line) |
| `Telegram.xcodeproj/project.pbxproj` | `NovagramJobSearch` folder reference in Packages, `XCSwiftPackageProductDependency`, `PBXBuildFile` in the Telegram target's Frameworks phase, product dependency of the target (same shape as `GroupsInCommonUI`) |

Ours:
- `packages/NovagramJobSearch` (product `NovagramJobSearch`; deps TGUIKit, GeneralRows, Localization, TelegramContext, TelegramUtils, TelegramTheme, InputDataUI, AvatarUI, NovagramCore). Contract files: `NovagramJobModel.swift`, `NovagramJobQuery.swift`, `NovagramJobPostParser.swift`, `NovagramJobPresets.swift`, `NovagramJobText.swift`, `NovagramJobStore.swift`.
- `NovagramJobSearchEngine.swift`: sources (a) public hashtag posts `searchHashtagPosts` for the first 4 preset hashtags of the mode + the query's `#tags`; (b) my chats `searchMessages(.general(scope: .everywhere, minDate: period))` per server query (≤5; empty query → first 3 preset keywords); (c) watched channels `.peer(peerId:, minDate:)`, ≤15 channels, one request each (with one server query that query, else an empty query that lists the channel's recent posts and is filtered locally); (d) global posts `.globalPosts(allowPaidStars: nil)` only for Premium and only on the explicit "Search all public posts" tap, one request with the first server query; never pays Stars. At most 6 requests at a time, 400 ms debounce, a new filter cancels the previous run, 50 per page, "Load more" pages every unfinished source. Every page goes through `NovagramSearchPrivacy.kept` (hidden chats never, locked chats' messages never), then `NovagramJobPostParser.parse` and `filter.accepts(...)` on the engine's own queue. A source whose request ends without a result is shown as failed. The last filter is remembered (`NovagramJobStore.setLastFilter`).
- Free global-posts quota: `TelegramEngine.EngineData.Item.Messages.GlobalPostSearchState()` (`TelegramGlobalPostSearchState`: `remainingFreeSearches`, `totalFreeSearches`, `unlockTimestamp`), refreshed with `engine.messages.refreshGlobalPostSearchState()` (`channels.checkSearchPostsFlood`) when the page opens and after each global search. When the quota is used up the row is disabled and shows the reset time; there is no Stars offer.
- `NovagramJobSearchController.swift` (InputDataController): mode, query + syntax hint, filters, sources + global row with quota, results (`NovagramJobResultRowItem.swift` cards), "Saved job searches" (tap loads, switch toggles alerts, right-click Remove, "Save this search"), "Job channels" (watched: Open / Remove; "Find channels" = `searchRemotePeers(scope: .channels)` over `NovagramJobPresets.channelDiscoveryQueries` + the first server query, hidden chats dropped, each with Watch (local) / Open / Join (`joinChannel`, only on that tap)). Write = first `@username` contact resolved with `resolvePeerByName`, else the post author when it is a user.
- `NovagramJobSearchHooks.swift` (`openMessage`, `openPeer`), installed in `NovagramHooksInstall.swift` (`navigateToChat` with `focusTarget`).
- `NovagramJobAlertMonitor.swift`: started for the current account where the unread reminder starts; first check 2 min later, then every 30 min; only saved searches with alerts on, only sources (a)(b)(c), only posts newer than `lastSeenDate`; see the review fixes below for how a run fetches. New matches: local notification "N new: <title>" through `UNUserNotificationCenter` (like `NovagramUnreadReminderManager`), `lastSeenDate` updated, unseen count raised; clicking it opens the page with that search. Opening the page marks everything seen. While the search features key is off the checks are skipped and nothing is posted (saved data is kept).
- `packages/NovagramCore/.../NovagramHooks.swift`: `openJobSearch`, `jobSearchUnseenCount`, `handleNotificationClick`; `NovagramJobSearchAvailability.swift` (the `novagram_search_features` gate and its signal); strings `jobSearch_*` (en/uz/ru) in `NovagramL10nJobSearch.swift`.
- `packages/ChatListUI/.../NovagramSavedSearchRows.swift`: `novagramSavedSearchSignal` (the saved searches signal) and `novagramSavedSearchSelect` (saved query → `novagramSetQuery`); the two `SearchController.swift` lines call them.
- Logout: `NovagramJobStore.clear` next to every `NovagramSavedSearches.clear` (`NovagramHooksInstall.swift` `accountWillLogOut`, `NovagramAccountsController.swift`, the two Telegram lines above).

Manual repro for regressions: (1) empty global search shows "Job search" above "Saved searches"; set `defaults write <suite> novagram_search_features -bool NO` and it disappears without a relaunch. (2) Open it, type `iOS | swift`, results arrive from hashtag posts and your chats, newest first, no post from a hidden chat even while hidden chats are revealed. (3) Premium: "Search all public posts" uses one free search, the counter drops; at 0 it shows the reset time. (4) Save the search, turn alerts on: after 2 min / 30 min a notification "N new: …" opens the page.

## Job search, review fixes (branch `feature/job-search`, 2026-10-29)

| File | Change |
| --- | --- |
| `Telegram-Mac/app/ApplicationContext.swift` | the stop line passes the context: `novagramJobSearchDidStop(context: context)` (`:1418`, changed); the drop-auth alert calls `NovagramHooks.shared.accountWillLogOut(context.account.id)` before `logoutFromAccount` (`:585`, 1 new line) |
| `packages/AuthUI/.../TermsModalController.swift` | `import NovagramCore` (`:13`); declining the terms (account deleted) calls `NovagramHooks.shared.accountWillLogOut(context.account.id)` before `logoutFromAccount` (`:124`) (2 lines). AuthUI already depended on NovagramCore |

Ours:
- Account switch: `NovagramJobAlertMonitor.stop(context:)` does nothing unless the monitor runs for that account (`account.id`), so a late `deinit` of the old context cannot stop the new account's monitor; `start` resets unconditionally.
- Alerts: one shared fetch per run for at most 5 searches with alerts on (least recently checked first, in memory): the preset hashtags of each mode once, the query hashtags once, "my chats" once per distinct server query (or preset keywords), watched channels once (first 10, empty query, `minDate` = the oldest `lastSeenDate` / period start of the run), then each search filters the shared posts locally. A request that ends without a result, or a preset hashtag that returns no posts (TelegramCore turns a hashtag `FLOOD_WAIT` into an empty page, `automaticFloodWait: false`), marks every search that uses it incomplete: no notification and no `lastSeenDate` change for it. No run while a job search page is open.
- `NovagramJobRequestLimiter`: one limit of 6 concurrent requests shared by the page engine, the alert run, the global posts search and Find channels.
- Global posts results are kept apart from the free sources, survive filter changes and are re-filtered with `accepts`; the global search reads the newest filter at once, not after the 400 ms debounce. The last filter is written once per run (after the debounce), not per keystroke; the page reloads watched channel peers (one Postbox transaction through a `MetaDisposable`) only when the watched ids changed.
- Logout: `novagramJobSearchClear` also clears the account's unseen alert count; `accountWillLogOut` in `NovagramHooksInstall.swift` calls it, so the two new Telegram lines clear saved searches, job search data and the count together.
- Notification click: the account in the notification must be the current one (else nothing happens); if a job search page is open it loads that saved search, else a page is pushed.
- "Save this search": an equal filter updates the existing entry; at 20 entries a toast (`jobSearch_savedLimit`, en/uz/ru) and nothing is dropped.
- Link: `tg://novagram/jobs` and `tg://settings/novagrampro/jobs` open the page through `openJobSearch` (`Telegram-Mac/novagram/NovagramSettingsLinks.swift`); nothing happens while `novagram_search_features` is off.

## Job search, Jobs tab and card fixes (branch `feature/job-search`, 2026-10-29)

The entry point is the last tab of the search category bar ("Jobs" / "Ish" / "Работа", with the unseen alert count, e.g. "Jobs 3"), appended after whatever the bar ends with (Files, or the hashtag tabs). It shows only in the global search (no peer tag, no forum, not a community search) and while `novagram_search_features` is on (live). Clicking it opens the Job search page; the search state does not change, so the previous tab stays selected and the list is not filtered. The "Job search" row on the empty search screen is gone. No `SelectedSearchTag` case was added: the tab is an extra `ScrollableSegmentItem` with its own id (`-1_000_001`, outside the tag raw values and the -4…0 ids).

| File | Change |
| --- | --- |
| `packages/ChatListUI/.../PeersListController.swift` | `SearchContainer.update`: before `current.updateItems(...)` the items go through `novagramJobsTabItems(...)` (`:2223`); `didChangeSelectedItem` first runs `novagramJobsTabDidSelect(item, context:)` and returns when it was the Jobs tab (`:2228`) (2 lines, each `// Novagram`) |

Ours: `packages/ChatListUI/.../NovagramJobsTab.swift` (one binding per tag bar view and account: keeps the bar's last items and re-runs `updateItems` when the gate or the unseen count changes, so the tab title and visibility update without a new search state). `NovagramSavedSearchRows.swift` lost the entry row. Result cards: each card is its own section (the page's normal block gap), "Load more" too; the snippet starts after the title line and skips a line that is only the salary (the salary text plus at most 12 letters of label such as "Maosh:"), `novagramJobSnippet` in `NovagramJobResultRowItem.swift`. String `jobSearch_tab` in `NovagramL10nJobSearch.swift`.

## Job search, convert languages (branch `feature/job-search`, 2026-10-29)

Filters get "Convert languages": a multi-select over `NovagramSearchLanguage.allCases` (O'zbekcha (lotin), Ўзбекча (кирилл), Русский, English) plus "None", which clears the set; bound to `filter.languages`, an empty set shows "None". A note under it says translations go through Telegram's translation service, Uzbek Latin ↔ Cyrillic is converted locally, and None searches the query as typed. Only for a non-empty query: after the 400 ms debounce, `NovagramSearchConversion.plan(query:languages:)` lists `translationsNeeded`; each distinct `translationCode` is fetched once with `engine.messages.translate(text:toLang:)` through the shared 6-request limiter (one "uz" result serves both Uzbek scripts, `NovagramJobQuery.parse(_:languages:translations:)` transliterates it), cached in memory (`NovagramJobTranslations.swift`, 200 entries, then cleared; failures are not cached); a new filter cancels the pending translations; a failed translation is left out with no error UI. The query is then built with `NovagramJobQuery.parse(raw, languages:, translations:)`. Alert runs translate each saved filter's query the same way before the shared fetch. The existing `NovagramQueryTranslator` cache was not reused: it only works while the "Search the translated query too" switch is on and translates into one language. No Telegram file changed.

## TGUIKit: mouse wheel on the search category bar

`packages/TGUIKit/Sources/HorizontalTableView.swift` (2026-10-29, Telegram bug): `HorizontalScrollView.scrollWheel` added the vertical wheel delta as points, but a mouse wheel reports lines (1–3), so the search category bar moved 1–3 px per notch and looked stuck (Shift+wheel worked through AppKit). The two `scrollPoint.x` lines use `novagramWheelDeltaY(event)` (`NovagramWheelDelta.swift`: lines × `horizontalLineScroll` for non-precise devices, unchanged for trackpads). Manual repro: focus the chat list search, put the pointer on the category bar, turn a mouse wheel without Shift: the bar scrolls. The fix applies to every HorizontalScrollView with a mouse wheel (theme lists, reactions, gifts, chat theme selectors, …); trackpads are unchanged; `makeScrollPoint` is left as is.

## Job search, job channels rows and relevance (branch `feature/job-search`, 2026-10-29)

"Job channels" rows are `ShortPeerRowItem`s like Telegram's channel search: avatar, title and "@username · 12.3K subscribers" (`peerStatusSubscribersOther` with the count as `prettyNumber`; missing parts left out). Watched channels show "Watching" on the right; clicking a row opens its menu (watched: Open / Remove; found: Watch (local) / Open / Join (server, only on that tap)). Watched channels read their subscriber count from the cached `Peer.ParticipantCount`. Discovery pairs the user's first server query with job words ("<query> vakansiya", "<query> ish", "<query> вакансия") plus `NovagramJobPresets.channelDiscoveryQueries`, at most 6 searches through the shared limiter, and keeps a found channel only when its title or username has a job signal (`NovagramJobChannelRelevance.hasJobSignal`: vakansiya, vakansiyalar, ishbor, ish bor, ish e'lon, job, jobs, hr, hiring, career, работа, вакансии, вакансия; "hr" and "job" as whole words, "job" also inside a username). Watched channels always show. No Telegram file changed; `NovagramJobSearch` now depends on `ShortPeerRow`.

## Job search, feed, spam guard, contacts and Open post fix (branch `feature/job-search`, 2026-10-29)

- Feed: with an empty query the results header reads "Latest vacancies" / "Latest resumes" (no count) and a block of role chips sits above it (`NovagramJobRoleChipsRowItem.swift`, roles `jobSearch_roles` in the UI language: Sales, Developer, Driver, Accountant, Operator, Cook / Sotuvchi, Dasturchi, Haydovchi, Buxgalter, Operator, Oshpaz / Продавец, Разработчик, Водитель, Бухгалтер, Оператор, Повар). A chip puts the role into the query, which runs the normal search (Convert languages applies). With a query the header is "Results (N)" and the chips hide.
- Spam guard (`NovagramJobSpamGuard.swift`): a post is dropped when its chat's title or username has crypto / ads markers (altcoin, crypto, крипто, coin, token, pepe, pump, signals, сигналы, forex, binance, airdrop, trading, casino, казино, betting, ставки, bitcoin, ethereum, usdt, cryptocurrenc*, market data; whole words nft, btc, eth, trx, markets) or a promo domain (`name.com` etc.) together with "picks" / "guide"; or when its text has bitcoin, ethereum, usdt, cryptocurrenc*, market data, altcoin, the words btc / eth / markets, or a promo domain with picks / guide. Applied to the page sources, the global posts, the alert runs and the Job channels discovery.
- Contacts (`NovagramJobMessageContacts.swift`): besides the parser's plain-text contacts, the card collects contacts from `TextEntitiesMessageAttribute` (Url, TextUrl, Mention, TextMention, Email, PhoneNumber, in text order) and from URL buttons in `ReplyMarkupMessageAttribute`. `t.me/<name>` and `tg://resolve?domain=<name>` become `@name`; links to the posting channel itself, bots (`…bot`), `joinchat`, `+invite` and other reserved t.me paths, and t.me post links (`t.me/name/123`) are skipped; other web links are kept after the direct contacts. Merged with the parsed ones, deduplicated, at most 5. The Write button shows its target ("Write @name" / "@name ga yozish" / "Написать @name"); Copy contact copies the first contact.
- Open post bug ("open post qilsam open bo'lmayapti"): results from `searchHashtagPosts` / global posts are rendered from the server reply and not stored in Postbox. For a public channel the account has not joined, `navigateToChat` (`Telegram-Mac/app/ApplicationContext.swift:62`) reads the peer from Postbox (`engine.data.get(Peer.Peer)`), gets nil and silently does nothing. Telegram's own search calls `engine.messages.ensureMessagesAreLocallyAvailable` before opening a found message (`SearchController.selectionDidChange`). The `openMessage` hook (`NovagramJobSearchHooks`, now takes the `Message`) does the same before `navigateToChat`; Write stores the message too before opening the author. Debug builds log `NovagramJobSearch: open post <id>` there. Nothing was removed. Manual repro: Job search (`tg://novagram/jobs`), empty query, Find a job, "Open post" on a card from a channel you have not joined (e.g. "HoReCa jobs Uzbekistan"): the channel opens scrolled to that post.

No Telegram file changed in this round.

## Job search, pre-merge review fixes (branch `feature/job-search`, 2026-10-30)

- Open page tracking: the page registers with `NovagramJobAlertMonitor` in `didAppear` and unregisters in `didDisappear` (and on deinit), not for its whole life. A Job page left in the stack under a chat opened with "Open post" no longer blocks alert runs, and a notification click loads the search into the page only while it is the visible one; otherwise it pushes a new page.
- Seen posts: while the page shows a filter equal to a saved search's filter, that search's `lastSeenDate` moves to the newest shown post from the free sources (global posts are not counted), so alerts do not announce posts the user already saw.
- `NovagramJobAlertMonitor.stop(context:)` compares the context object (`===`), not `account.id`: a rebuilt context of the same account cannot stop the new monitor.
- Notification click: while `novagram_search_features` is off the click is swallowed (returns true, nothing opens).
- Spam guard (`NovagramJobSpamGuard.swift`, same change in `novagram-search-kit-sdk` `Jobs/NovagramJobSpamGuard.swift`, commit `e618ac7`, test `testSpamGuardUsesWholeWords`): "picks" / "guide" next to a promo domain count only as whole words ("guidelines" + "company.com" is kept); coin(s), token(s), pump and trading count only as whole words and only when two of them appear together ("X Trading vakansiya" and "coinbase_careers" are kept, "coin pump club" is dropped); the strong markers (crypto, altcoin, pepe, signals, forex, binance, airdrop, casino, betting, …) are unchanged.
- Translations (`NovagramJobTranslations.swift`): each language gets at most 8 s (after that the search runs without it), and only non-empty translations are cached, so a failure is retried next time.

No Telegram file changed.


## Search features switch (2026-10-30)

> Removed 2026-10-30 (manager scope), last on main at 9d9b178d4; logic in NovagramSearchKit. The Jobs tab now follows `novagram_dev_job_search`.

iOS parity (iOS commit `3517592085`). Settings → Novagram → a new SEARCH section right after Interface: "Search features" (`pro_messager/novagram_search_features`, Bool, a missing key counts as on, deep-link slug `search-features`), then "Search the translated query too", moved here from Interface (same key `novagram_search_translate`, same slug `search-translate`, shown only while Search features is on). The single reader of the key is `NovagramCore/NovagramSearchFeatures.swift` (`isEnabled`, `key`, `signal()` that follows `UserDefaults.didChangeNotification`); `NovagramJobSearchAvailability` now forwards to it.

While the switch is off:
- Global search (`ChatListUI/NovagramSearchFilters.swift`): the Messages "From:" menu has no dates / Unread only / Mentions only items, and a filter that is still set is ignored (`hasDates`, `filtersMessages`, `unreadActive`, `mentionsActive` read the switch, so the dates, the page fill, the read-state lookup, the kept messages and the header title all fall back to plain Telegram).
- Inside a chat (`NovagramCore/NovagramChatSearchFilter.swift`): `"..."` and `re:` are plain text.
- Saved searches (`NovagramCore/NovagramSavedSearches.swift`): `signal` gives an empty list (no section) and `record` saves nothing; the stored JSON stays.
- Translated query (`NovagramCore/NovagramQueryTranslator.swift`, `ChatListUI/NovagramTranslatedSearch.swift`): no translate request and no "Translated:" section; the translated signal follows `NovagramSearchFeatures.signal()`, so toggling also refreshes the open search results list.
- Jobs tab and job alerts: already gated by `NovagramJobSearchAvailability` (same key).
- Never gated: the hidden / locked chat privacy filter (`NovagramSearchPrivacy`, `novagramSearchHides`).

About (`Telegram-Mac/novagram/NovagramAboutController.swift`): the "Disable" texts of the exact phrase and regex entries point at the new switch (en/uz/ru; zh unchanged).

No Telegram file changed.

## Job search, custom hashtags and row colors (branch `feature/search-switch-and-job-hashtags`, 2026-10-30)

- Query hint: adds "#python: posts with this hashtag" (en/uz/ru, `jobSearch_queryHint`).
- Hashtag chips: while "Public hashtag posts" is on, a chip row under it shows the hashtags that source searches for the current mode (`#vakansiya ×`, …, `+`, and "Reset" when the list differs from the presets). × removes a tag; `+` opens an alert with a text field (`#` and spaces stripped, letters / digits / `_` only, at most 32 characters, invalid input shows a toast); at most 12 tags per list, an empty list is allowed (then only the query's `#tags` are searched). The chips reuse `NovagramJobRoleChipsRowItem`.
- Model: `NovagramJobFilter.jobHashtags` / `candidateHashtags: [String]?` (nil = presets, defaulted init parameters at the end, decoding without the keys gives nil, values are cleaned and capped on init / decode / `setHashtags`), `hashtags(for:)` (custom ?? `NovagramJobPresets.hashtags(for:)`), `hasCustomHashtags(for:)`, `setHashtags(_:for:)`, `normalizedHashtag(_:)`, `maxHashtags = 12`, `maxHashtagLength = 32`. Same change in `novagram-search-kit-sdk` (`Jobs/NovagramJobModel.swift`, test `testCustomHashtags`, commit `b80a9ef`, pushed); Mac checks in `packages/NovagramJobSearch/Checks/main.swift`.
- Engine and alerts: `NovagramJobSearchEngine.runHashtags(filter)` = the first 8 of `filter.hashtags(for: mode)` (was the first 4 presets), plus the query's `#tags`, all through the shared limiter. In alerts an empty page counts as a failed request only for preset tags; an empty custom tag is just empty.
- "Search all public posts" row: the title uses the normal text color (half-transparent when disabled) and the subtitle the secondary gray; the saved-search rows' "Alerts on/off" subtitle is gray too. Cause: `InputDataGeneralData.descTextColor` nil falls back to `theme.colors.text` in `InputDataControllerEntries.swift`, so the rows now pass `theme.colors.grayText`.

No Telegram file changed.

## NovagramSearchKit SDK (2026-10-30)

> NovagramCore and ChatListUI adapters removed 2026-10-30 (manager scope), last on main at 9d9b178d4; only NovagramJobSearch uses the SDK now.

The pure search logic now comes from the shared SDK `Novagramorg/novagram-search-kit-sdk` (module `NovagramSearchKit`, Foundation only, also used by iOS); the Mac keeps no copy of it, only thin adapters for Signals, Postbox and UI.

- Submodule: `packages/NovagramSearchKit` → https://github.com/Novagramorg/novagram-search-kit-sdk, pinned to `3751cf3`. Update: `git -C packages/NovagramSearchKit fetch && git -C packages/NovagramSearchKit checkout <sha>`, then `git add packages/NovagramSearchKit`. Never a bare `git submodule update` (it resets `submodules/telegram-ios` and wipes the TelegramCore fork patches); touch only this path. `scripts/novagram-local.sh hide` sets `ignore = dirty` on it like on every submodule in `.gitmodules`; `scripts/novagram-upstream-update.sh` (`update_moved_submodules`) only updates submodules whose checkout differs from the index, which upstream never moves for this one. Neither script needed a change.
- Dependency lines (local path package, no pbxproj change: it reaches the app through the packages that use it):
  - `packages/NovagramCore/Package.swift`: `.package(name: "NovagramSearchKit", path: "../NovagramSearchKit")` and `.product(name: "NovagramSearchKit", package: "NovagramSearchKit", condition: nil)` on the `NovagramCore` target (not `NovagramShare`).
  - `packages/NovagramJobSearch/Package.swift`: `("NovagramSearchKit", "../NovagramSearchKit")` in `deps`.
  - `packages/ChatListUI/Package.swift` (Telegram file, 2 lines, each `// Novagram`): the `.package(name: "NovagramSearchKit", path: "../NovagramSearchKit")` line after the `NovagramCore` package line and the `.product(name: "NovagramSearchKit", package: "NovagramSearchKit", condition: nil)` line after the `NovagramCore` product line.
- Removed (now in the SDK): `packages/NovagramJobSearch/Sources/NovagramJobSearch/` `NovagramJobText`, `NovagramJobQuery` (now `NovagramSearchQuery`, call sites renamed), `NovagramJobPostParser`, `NovagramJobPresets`, `NovagramJobStore`, `NovagramJobModel`, `NovagramJobRegex`, `NovagramJobSalaryParser`, `NovagramJobContactParser`, `NovagramSearchLanguage`, `NovagramSearchConversion`, `NovagramJobChannelRelevance`, `NovagramJobSpamGuard`; `packages/NovagramJobSearch/Checks/` (the SDK's XCTests replace it; before the removal its 205 checks passed against the SDK sources with only the type renames shimmed). `scripts/novagram-job-search-checks.sh` now runs `swift test` in `packages/NovagramSearchKit`.
- Adapters kept (same public API, so no hook line in a Telegram file changed):
  - `NovagramCore/NovagramSearchFeatures.swift`: `key`, `isEnabled` and `signal()` over `NovagramSearchSettings.shared` (the signal still follows `UserDefaults.didChangeNotification`). `NovagramJobSearchAvailability` is unchanged.
  - `NovagramCore/NovagramChatSearchFilter.swift`: `wrap(query:state:search:)` parses with `NovagramChatSearchQuery`, filters each page with `NovagramChatSearchMatcher` on `Queue.concurrentDefaultQueue()`, keeps the paging progress in a `NovagramChatSearchProgressCache` keyed by query and `SearchMessagesState`.
  - `NovagramCore/NovagramSavedSearches.swift`: `NovagramSavedSearch` is a typealias of the SDK type; `list` / `signal` / `record` / `setPinned` / `remove` / `clear` forward to `NovagramSavedSearchStore.shared` (PeerId and AccountRecordId as Int64); the signal follows `NovagramSavedSearchStore.didChangeNotification` and the features switch.
  - `NovagramCore/NovagramQueryTranslator.swift`: settings from `NovagramSearchSettings.shared`, same-as-query rule and the 200-entry cache from `NovagramQueryTranslation` / `NovagramQueryTranslationCache.shared`; the TelegramCore request, the 600 ms delay and the Signal stay here.
  - `ChatListUI/NovagramSearchFilters.swift`: `NovagramSearchFilterState` wraps the SDK state (`stored`; `active` = `stored.effective(isFeaturesEnabled:)`, so the switch still turns every filter off); day start / end through `setFromDay` / `setToDay`; header parts through `titleParts`, still printed with the locale's short date style (not the SDK's dd.MM.yy); unread through `NovagramSearchFilterState.isUnread` / `keeps`; page fill through `NovagramFilledLoad`; `NovagramFilterAutoLoad` is a typealias of `NovagramSearchAutoLoad`. Message read states, mentions attributes, Postbox and the dropdown stay here.
  - `ChatListUI/NovagramTranslatedSearch.swift`: the `#` / `$` prefixes and the 20-message limit come from `NovagramQueryTranslation.skippedPrefixes` and `NovagramSearchPaging.translatedResultLimit`.
  - `NovagramJobSearch/NovagramJobSearchData.swift`: `clear(accountRecordId:)` for the app target, which does not import the SDK; `Telegram-Mac/packages-integration/hooks/NovagramHooksInstall.swift` `novagramJobSearchClear` calls it instead of `NovagramJobStore.clear`.
- Behaviour changes that come with the SDK (accepted by the owner and the iOS session): `re:` followed directly by a non-space is a regex in any letter case (`Re:\d+` works), `re: invoice` with a space is a plain search of the whole text; the chat paging cache key is query + state; a page counts as timed out only when a message was really skipped. The regex "how to" text in `Telegram-Mac/novagram/NovagramAboutController.swift` says so (en/uz/ru/zh). The SDK's exact phrase match also unifies apostrophe variants and collapses whitespace runs (`to‘liq  stavka` finds `to'liq stavka`).
- Telegram files touched: `packages/ChatListUI/Package.swift` (the 2 lines above). No Swift hook line changed.

## Search translate languages (2026-10-30)

> Removed 2026-10-30 (manager scope), last on main at 9d9b178d4; logic in NovagramSearchKit.

iOS parity. The rules come from SDK `NovagramSearchSettings`: `translateTargets`, `setTranslateTargets`, `serverTranslationCodes(for:)`, `maxServerTranslations = 3`.

- Key `pro_messager/novagram_search_translate_langs` (`[String]` of `uz-Latn`, `uz-Cyrl`, `ru`, `en`, in tap order; empty = None). A missing key means today's single target from `auto_translate_lang` (`uz` → `uz-Latn`, other codes as they are); nothing is written until the row is used, and the first write keeps only the 4 allowed codes.
- Settings → Novagram → SEARCH: "Translate into" / "Tarjima tillari" / "Языки перевода" (`settings_searchTranslateLangs_title`) under "Search the translated query too", only while Search features and translate are on; slug `search-translate-langs`. A click opens a menu: None (clears the list), then O'zbekcha (lotin), Ўзбекча (кирилл), Русский, English with check marks; a language toggles in tap order. The value shows the selected names, the legacy `auto_translate_lang` name while the key is missing, or None (`search_translateNone`). Code: `Telegram-Mac/novagram/NovagramSettingsController.swift` (entry `searchTranslateLangs`, `novagramSearchTranslateLangChoices`, state `searchTranslateLangs`). The translate switch subtitle now says "the languages chosen below" (en/uz/ru).
- `NovagramCore/NovagramQueryTranslator.swift`: `targets`, `hasStoredTargets`, `toggleTarget`, `clearTargets`, `serverCode(for:)`, `serverCodes(for:)`, `targetName`, `targetsLabel`, `translatedQuery(engine:query:language:)` (same 600 ms delay, SDK cache keyed by language and query, no section when equal to the query).
- Global search (`ChatListUI/NovagramTranslatedSearch.swift`): one section per target in stored order, titled "Translated: <text> · <language>". Each target is routed with SDK `NovagramSearchConversion.plan(query:languages:)` (targets mapped to `NovagramSearchLanguage`; legacy codes such as `de` or `tr` go to the server as before): a target in the query's own language or script gets no section; the other Uzbek script of an Uzbek query is the query transliterated locally (`plan.transliterations`, no server call, same 600 ms delay); the rest (`plan.translationsNeeded`) is translated by the server, one call per server code (uz only when the query is not Uzbek), at most 3 real server calls: each code's translation runs once in a `Promise<String?>` that every section of that code reads (uz-Latn and uz-Cyrl share one uz call). A server `uz-Cyrl` is the uz result through `NovagramSearchTransliteration.uzbekLatinToCyrillic`; any section equal to the query is dropped. Queries shorter than 3 characters get no sections. Each section searches 20 messages with the Messages section's source, dates and filters. `novagramTranslatedBlocks` dedupes with one `Set` per emission across the sections and against the Messages section ids, never through SearchController's shared `ids`. Sections at 19000 + 25 × n (separator), messages after it.
- Chips: the first translated section gets a chip row under its header (`ChatListUI/NovagramTranslateChipsRowItem.swift`, one chip per target, accent when on, gray when off). A tap hides or shows that language for the current query only (`NovagramTranslateChipsState`, created per query inside `novagramTranslatedSearch`, never saved). When every section is hidden the row stays under a "Translate into" header so the language can be turned back on. The row reuses the existing `novagramSavedSearch` entry case: `NovagramSavedSearchRow` got an optional `chips` payload with its own stable key, `novagramSavedSearchRowItem` builds the chips row for it and `novagramSavedSearchSelect` ignores clicks on it.
- Search features off: no sections and no requests, as before.

| File | Change |
| --- | --- |
| `packages/ChatListUI/.../SearchController.swift` | the translated section line (`:1394`) loops over `novagramTranslatedBlocks(novagramTranslated, shown:)`: a separator per block, the chips entry `.novagramSavedSearch(chips)` for the first one, its messages from `firstMessageIndex` (1 existing `// Novagram` line changed, 0 new) |

## Developer flags for search and call recording (2026-10-30)

> 2026-10-30, owner rule "one unapproved feature = one switch, inside Developer": the `novagram_dev_call_recording` and `novagram_dev_call_data_saving` flags, their "(beta)" rows, strings (`developer_callRecording*`, `developer_callDataSaving*`) and signals are removed, and Settings → Calls is gone (`callRecording_section` removed). See "One switch per unapproved feature (2026-10-30)" below.

> The search flag `novagram_dev_search_features` removed 2026-10-30 (manager scope), last on main at 9d9b178d4; job search has its own flag `novagram_dev_job_search`. The call recording and call data saving flags stay.

Owner's rule: search features and call recording are hidden Developer features until the manager accepts them (same spec on iOS).

- `NovagramCore/NovagramDeveloperFlags.swift`: `novagram_dev_search_features` (`isSearchFeaturesEnabled`, `searchFeaturesSignal`) and `novagram_dev_call_recording` (`isCallRecordingEnabled`, `callRecordingSignal`), pro_messager, Bool, missing = off, posting `novagramDeveloperFlagsChanged`. `NovagramDeveloperRole.Switch` gained `searchFeatures` and `callRecording`: the director cannot see them and a director login turns them off.
- Developer section (`NovagramSettingsController.swift`): rows "Search features (beta)" / "Call recording (beta)" (`developer_searchFeatures*`, `developer_callRecording*` in `NovagramL10n.swift`, en/uz/ru), developer role only; the state follows the flag signals live.
- Search flag off: `NovagramSearchFeatures.isEnabled` is false whatever the user switch says (`isUserEnabled` keeps the switch value for the Settings row) and its signal also follows `novagramDeveloperFlagsChanged`; so the global search filters, `"..."` / `re:` in a chat, saved searches (signal and `record`), the translated sections (`translatedQuery` checks it too), the Jobs tab, `tg://novagram/jobs` and job alerts are off. The SEARCH section is hidden; `novagramSettingsSlugAllowed` makes `search-features`, `search-translate` and `search-translate-langs` do nothing (`openNovagramSettings` returns, `applyFocusSlug` finds nothing). The About entries "Exact phrase search in a chat" and "Regex search in a chat" are hidden (`novagramAboutFeatures`). The hidden / locked chat privacy filter is never gated.
- Call recording flag off: `NovagramCallRecordingSettings.isEnabled` is false (`isStoredEnabled` keeps the switch value for Settings), so auto-record is off (`isAutoEnabled`) and the Record button hides (`isAvailable` hook); the hook's `recordingSignal` also follows `callRecordingSignal`, so an open call screen redraws its buttons when the flag flips. The Call recording switch, auto-record and folder rows are hidden and the slugs `call-recording`, `call-recording-folder`, `call-recording-auto` do nothing; "Use less data for calls" stays. `NovagramCallRecording` watches the flag: when it turns off while a start is in progress it sets `stopWhenStarted` (the recording stops as soon as it has started), otherwise a running recording stops through the existing `stop()` and is saved as usual. `toggle` does not start a new one, and the consent alert's proceed paths re-check `isEnabled` (manual) and `isAutoEnabled` (auto).

- Third flag, "Use less data for calls" (owner, not approved by the manager either): `novagram_dev_call_data_saving` (`isCallDataSavingEnabled`, `callDataSavingSignal`, pro_messager, Bool, missing = off), "Use less data for calls (beta)" / "Qo'ng'iroqlarda kam trafik (beta)" / "Экономия трафика в звонках (бета)" (`developer_callDataSaving*`), developer role only (`NovagramDeveloperRole.Switch.callDataSaving`; a director login turns it off). Off: the "Use less data for calls" row in Novagram Settings → Calls is hidden and the slug `call-data-saving` does nothing; calls use upstream's `.never` (`TelegramCallsCore/NovagramCallDataSaving.swift` returns `.always` only while both the flag and `novagram_call_data_saving` are on; the hook line `PCallSession.swift:537` is unchanged, and upstream hard-codes `.never` there, so Telegram's own Data and Storage setting and `VoiceCallSettings` are not touched). The stored row value is kept for when the flag comes back.
- The Calls section (header included) shows only while call recording is available (flag on, macOS 14+) or the data saving flag is on. Its header is uppercase like the other sections: "CALLS" / "QO'NG'IROQLAR" / "ЗВОНКИ" (`callRecording_section`).
No Telegram file changed.

## Manager scope: rejected search UI removed (2026-10-30)

The manager approved search over all accounts and search in edit history / deleted messages, and rejected dates, Unread / Mentions only, the translated query (with translate languages), saved searches and "phrase" / `re:` inside a chat. The owner removed the rejected UI; all logic stays in NovagramSearchKit (SDK untouched). Branch `feature/search-manager-scope`, from main 9d9b178d4. Hidden / locked chat privacy in every search path is kept.

Telegram files (old line numbers at 9d9b178d4):

| File | Change |
| --- | --- |
| `packages/ChatListUI/.../SearchController.swift` | deleted: stable id `case novagramSavedSearch(String)` (`:94`) and its hash line (`:137`); entry `case novagramSavedSearch(...)` (`:162`) and its `stableId`, `index`, `==`, row item lines (`:198`, `:231`, `:344`, `:646`); `novagramSearchFilter` and `novagramAutoLoad` properties (`:861–862`); `public var novagramSetQuery` (`:881`); their local captures (`:934–935`); `novagramFillFilteredPage` (`:1266`) and `novagramWithReadStates` (`:1271`) lines; the translated sections line (`:1394`); the saved searches section line (`:1763`); `novagramAutoLoad.takeRequest()` (`:1891`); `novagramSavedSearchSelect` in `selectionDidChange` (`:2203`); `NovagramSavedSearches.record` before `open` (`:2396`). Restored to upstream: `remoteSearch` combine (`:1254`), the Messages `searchMessages` location (`:1263`), the Messages header `if !remoteMessages.0.isEmpty {` (`:1395`), the dropdown title (`:1400`) and its actions `})])` (`:1411`), the empty-screen `combineLatest` (`:1754`). Changed, still hooks: the Messages loop now uses `novagramSearchPrivateMessages(result.0.messages)` (`:1278`, privacy only); the final `combineLatest` keeps only the ads argument and the map only `promoted` (`:1332–1333`) |
| `packages/ChatUI/.../ChatController.swift` | `searchRequest` line restored to upstream (`:542`); `import NovagramCore` stays (other hooks) |
| `packages/ChatListUI/.../PeersListController.swift` | `searchController.novagramSetQuery` line deleted (`:3247`) |
| `Telegram-Mac/app/ApplicationContext.swift` | `NovagramSavedSearches.clear` in the `loggedOut` observer deleted (`:552`); the job search clear stays |
| `Telegram-Mac/account/SharedNotificationManager.swift` | `import NovagramCore` (`:11`) and the saved searches clear in `logout()` (`:326`) deleted; the job search clear stays |
| `packages/ChatListUI/Package.swift` | the two `NovagramSearchKit` lines deleted (`:57`, `:72`) |

Our files:
- Deleted: `ChatListUI/NovagramTranslatedSearch.swift`, `ChatListUI/NovagramTranslateChipsRowItem.swift`, `ChatListUI/NovagramSavedSearchRows.swift`, `NovagramCore/NovagramChatSearchFilter.swift`, `NovagramCore/NovagramSavedSearches.swift`, `NovagramCore/NovagramQueryTranslator.swift`, `NovagramCore/NovagramSearchFeatures.swift`.
- `ChatListUI/NovagramSearchFilters.swift`: only the privacy functions remain (`novagramSearchHides` ×2, `novagramSearchPrivateMessages`).
- `packages/NovagramCore/Package.swift`: the NovagramSearchKit dependency removed (NovagramCore no longer uses it). `NovagramJobSearch` keeps it.
- `Telegram-Mac/novagram/NovagramSettingsController.swift`: the SEARCH section (Search features, translate, Translate into), its state, defaults keys, menu, slugs `search-features`, `search-translate`, `search-translate-langs` and the Developer row "Search features (beta)" removed; new Developer row "Job search (beta)".
- `Telegram-Mac/novagram/NovagramAboutController.swift`: the "Exact phrase search in a chat" and "Regex search in a chat" entries removed.
- `Telegram-Mac/packages-integration/hooks/NovagramHooksInstall.swift` (`accountWillLogOut`) and `Telegram-Mac/novagram/NovagramAccountsController.swift`: the saved searches clear removed; `NovagramHooks.accountWillLogOut` and the job store clears stay. The stored `novagram_saved_searches_*` JSON is left on disk.
- Strings removed: `search_*` date / unread / mentions / translated / saved strings and `settings_section_search`, `settings_searchFeatures_*`, `settings_searchTranslate*` (`NovagramL10nParity.swift`), `developer_searchFeatures*` (`NovagramL10n.swift`).
- Job search flag: `NovagramDeveloperFlags.jobSearchKey` = `novagram_dev_job_search` (pro_messager, Bool, missing = off), `isJobSearchEnabled`, `jobSearchSignal`; `NovagramDeveloperRole.Switch.jobSearch` (developer only, a director login turns it off); strings `developer_jobSearchTitle` "Job search (beta)" / "Ish qidirish (beta)" / "Поиск работы (бета)" and `developer_jobSearchTip`. `NovagramJobSearchAvailability` reads only this flag, so it gates the Jobs tab, the page, `tg://novagram/jobs` and job alerts.

`// Novagram` lines in `packages` + `Telegram-Mac`: 496 before, 463 after (32 Telegram-file hook lines, plus one comment line in the trimmed `NovagramSearchFilters.swift`).

## Search all accounts, restored (2026-10-30, manager approved)

> Removed again 2026-10-30 at the manager's request (too much RAM / CPU), last in c26ae3169 + 794bce573. Restored: the `SearchController.swift` lines of this section are gone (stable id, hash, entry, `stableId`, `index`, `==`, row item and section lines deleted); the final `combineLatest` is back to 10 arguments (the 9 before this feature plus the archive search) and the map drops `novagramOtherAccounts`; the two selection lines keep only the archive part (`if novagramOpenArchiveSearchRow(item, context: context) { return }`, `if novagramIsArchiveSearchRow(item) { return navigationController?.modalAction == nil }`). Deleted `NovagramCrossAccountSearch.swift`, `NovagramOtherAccountsSearch.swift`, the settings row, key use and slug `search-all-accounts`, and the strings `search_otherAccounts`, `settings_searchAllAccounts_title` / `_subtitle`. `novagramIsOpenGesture` (used by the archive section) moved into `NovagramArchiveSearchSection.swift`. A stored `novagram_search_all_accounts` value is left in `pro_messager`. `// Novagram` lines: 483 before, 475 after.

The manager approved search over all logged-in accounts, so the "Other accounts" section removed in 2cdca31f4 (built in 23398ffee) is back, ported onto the trimmed SearchController. Global search shows local chat and contact matches from every other logged-in account (no network): up to 30 accounts, 3 hits per account, 15 in total, 250 ms debounce, the account name as the row status. A click switches to that account and opens the chat. Switch: Settings → Novagram → Interface → "Search all accounts" (`pro_messager/novagram_search_all_accounts`, Bool, missing = on, same key as iOS), slug `search-all-accounts`, no developer flag. Branch `feature/search-manager-scope`.

| File | Change |
| --- | --- |
| `packages/ChatListUI/.../SearchController.swift` | stable id `case novagramForeignPeerId(AccountRecordId, PeerId)` (`:94`) and its hash line (`:137`); entry `case novagramForeignPeer(NovagramForeignPeerHit, Int)` (`:162`) with its `stableId` (`:198`), `index` (`:231`), `==` (`:344`) and row item (`:646`) lines; the final `combineLatest` gets `novagramOtherAccountsSearch(...)` as its 10th argument and the map a `novagramOtherAccounts` parameter (`:1325–1326`, changed); one line before Global search adds the section through `novagramOtherAccountsEntries(...)` (separator 5000, rows 5001+), deduped against the current account's rows and by its own stable id with its own `Set`, never through the shared `ids` (`:1358`); `selectionDidChange`: `novagramOpenOtherAccountsRow` switches account and opens the chat (`:2201`); `selectionWillChange` first line: an other-account row is not selectable while a modal action (forward) is active (`:2393`) (12 lines: 10 new, 2 changed, each `// Novagram`) |

Ours: `packages/NovagramCore/.../NovagramCrossAccountSearch.swift` (`NovagramForeignPeerHit`; accounts from `sharedContext.activeAccountsWithInfo`, list order, current account skipped; `TelegramEngine(account:).contacts.searchLocalPeers` per account, query of 2+ characters, the search starts only after 250 ms (a delayed start, so typing does not run it per keystroke); skips the account's own user, secret chats, hidden chats even while revealed (`NovagramHiddenChatsManager.isPeerHiddenInStorage`; the hidden list is stored by peer id for all accounts, so a chat hidden in any account never shows), chats with a Chat Lock code (`NovagramSearchPrivacyPass`, one per account search) and peers whose main peer is hidden or locked; only peers, never message content); `packages/ChatListUI/.../NovagramOtherAccountsSearch.swift` (only for the common chat list search with chats, no tags, no `#`/`$`; `RecentPeerRowItem` bound to the other account's `Account` so the avatar loads from it, status = that account's name, no context menu; click = `sharedContext.switchToAccount(id:action: .chat(peerId, necessary: true))`). Settings row in `Telegram-Mac/novagram/NovagramSettingsController.swift` (Interface, after Unlimited Pins), strings `search_otherAccounts`, `settings_searchAllAccounts_title` / `_subtitle` in `NovagramL10nParity.swift`.

`// Novagram` lines in `packages` + `Telegram-Mac`: 463 before, 473 after.

## Search edited and deleted messages (2026-10-30, manager approved)

Global search gets a section "Edited & deleted" ("Tahrirlangan va o'chirilgan", "Изменённые и удалённые") with earlier versions of edited messages and deleted messages of the current account. It shows when the query has 2+ characters, something matches and at least one of the two existing switches is on (Novagram Settings → Chat → "Deleted messages" `show_deleted_messages`, default off; "Edited message history" `edited_history_enabled`, default on); a switch that is off also stops its kind from being recorded into the archive. Up to 20 rows, then "Show more" loads the next 20 by cursor (at most 50 pages). A row: chat avatar and title, an "edited" / "deleted" badge, the edit or deletion date, a one-line snippet with the first query term highlighted. Click on an edited row: the existing Edit History screen (`NovagramHooks.presentEditedHistory`, current text read from Postbox). Click on a deleted row: an alert with the chat name, deletion date and full text, "Open chat" / "Close". Hidden chats (storage check, even while revealed) and locked chats never appear (`isChatExcluded`). Secret chats are never archived. Search runs on the archive queue after 250 ms; while typing, the previous results are re-filtered with the new query at once, so the section does not blink. The index is cached per account and dropped when that account's archive changes. Branch `feature/search-manager-scope`.

Persistence: NovagramSearchKit `NovagramMessageArchiveStore` (SDK pin 3751cf3 → dba0ff0), one per app run, in `ApiEnvironment.containerURL/novagram-archive/` (the app group container plus the build prefix, so Debug `debug/` and App Store `appstore/` keep separate archives; works sandboxed), one `novagram-message-archive-<accountRecordId>.jsonl` per account, 20,000 records / 90 days per account. Dual-write: a new tombstone in `NovagramDeletedMessages.recordDeleted` saves `.deleted` (original text, deletion time = now); a new version in `NovagramEditedHistoryManager.processMessages` saves `.edited` with `editDate` = the new `EditedMessageAttribute.date`; both carry the account peer id and record id of the chat's `context.account`. The legacy edit history (`uz.fenixuz.app.editedHistory`) stays the viewer's source and is never deleted. One-time import of the legacy edit history on the first account start: each chat goes to the logged-in account that has it in its chat list, else the one that knows the peer (current account first on ties), else the current account; done is recorded in `pro_messager/novagram_archive_migrated_v1` as a list of migrated archive folder paths (one entry per build folder). Logout: `novagramJobSearchClear` (called by `NovagramHooks.accountWillLogOut`, the `loggedOut` observer, the terms decline, the drop-auth alert, Novagram Accounts and the passcode logout) also calls `NovagramMessageArchive.clear(accountRecordId:)`. Deleting a chat for yourself does not remove its records (no clean hook point; they expire after 90 days and the 20,000 cap).

| File | Change |
| --- | --- |
| `packages/ChatListUI/.../SearchController.swift` | stable id `case novagramArchiveId(String)` (`:95`) and its hash line (`:139`); entry `case novagramArchive(NovagramArchiveSearchItem, Int)` (`:165`) with its `stableId` (`:202`), `index` (`:236`), `==` (`:350`) and row item (`:653`) lines; the final `combineLatest` gets `novagramArchiveSearch(...)` as its 11th argument and the map a `novagramArchive` parameter (`:1332–1333`, changed); one line before the Messages section adds the section through `novagramArchiveSearchEntries(...)` (separator 17000, rows 17001+), with its own stable ids and its own dedupe, never through the shared `ids` (`:1395`); `selectionDidChange` also tries `novagramOpenArchiveSearchRow` (`:2209`, changed); `selectionWillChange`: an archive row is not selectable while a modal action is active (`:2401`, changed) (12 lines: 8 new, 4 changed) |
| `packages/ChatUI/.../ChatController.swift` | `recordDeleted(..., account: self.context.account)` (`:3034`), `process(..., account: context.account, ...)` (`:4140`, review fix) and `processMessages(..., account: context.account)` (`:4141`) (3 changed hook lines) |
| `Telegram-Mac/app/ApplicationContext.swift` | `novagramMessageArchiveDidStart(context: context)` after the Spotlight start (`:521`, 1 new line) |

Ours: `packages/NovagramCore/.../NovagramMessageArchive.swift` (store, dual-write, migration, paged search, privacy), `packages/ChatListUI/.../NovagramArchiveSearchSection.swift` (signal, entries, rows, "Show more", click actions), `NovagramDeletedMessagesManager.swift` and `NovagramEditedHistoryManager.swift` (optional `account:` parameter), `NovagramHooks.openChat` (installed in `NovagramHooksInstall.swift` with `navigateToChat`), `NovagramHooksInstall.swift` (archive folder from `ApiEnvironment.containerURL`, logout clear, `novagramMessageArchiveDidStart`), `packages/NovagramCore/Package.swift` (NovagramSearchKit dependency back), strings `search_archive*` in `NovagramL10nParity.swift`.

`// Novagram` lines in `packages` + `Telegram-Mac`: 473 before, 482 after.

Pre-merge review fixes (on top of e1c3ee96b):
- Per-account caches: `NovagramDeletedMessages` keys `live`, `liveOrder` and `tombstones` by account record id + peer id (`NovagramDeletedChatKey`), `process` and `recordDeleted` take the chat's `account`, and a `.global` deletion only matches messages cached by the same account. Before this, account A's deletion could tombstone account B's message with the same id and write B's text into A's archive. `NovagramEditedHistoryManager.lastSeen` is keyed by account record id + message id (`NovagramSeenKey`), so one account's text is never recorded as a previous version of another account's message. One account behaves as before. The legacy `msg_<peer>_<message>` storage key is unchanged.
- Orphan archives: at the first account start `NovagramMessageArchive.removeOrphans` takes the first `activeAccountsWithInfo` and the first `accountManager.accountRecords()` (records without `.loggedOut`) and deletes every `novagram-message-archive-<id>.jsonl` whose id is in neither (a session revoked while the app was closed, a crash during logout). A cleared account id is remembered for the run, so late `recordDeleted` / `recordEdited` saves and migration records for it are dropped.
- Keyboard moves: `novagramOpenOtherAccountsRow` and `novagramOpenArchiveSearchRow` act only on a mouse click or Return / Enter (`novagramIsOpenGesture`, from `NSApp.currentEvent`: `TableView.selectRow` sets `byClick` for clicks, while Return (`select(item: highlighted)`) and Option+Down / Ctrl+Tab (`selectNext`) both pass `byClick: false`, so `byClick` alone cannot tell them apart). On a keyboard highlight move they still claim the row (return true), so Telegram's code never opens another account's peer in the current account. No Telegram line changed for this.

`// Novagram` lines after the review fixes: 482 (one changed line, no new ones).

## Call recording notice (2026-10-30)

Owner's rule: the other person must know about a recording (same spec on iOS, same strings). No audible notice, nothing in tgcalls / tg_owt / the call audio device / native code. Behind the existing developer flag `novagram_dev_call_recording` (a recording can only start while it is on).

| File | Change |
| --- | --- |
| `packages/CallsUI/Sources/CallsUI/CallScreenController.swift` | `novagramSetCallId(arguments, session.internalId)` before `screen.update(arguments: arguments)` (`:315`, 1 new line): ties the call screen's `PeerCallArguments` to the call session id |

Ours:
- `packages/PrivateCallScreen/Sources/NovagramCallRecordHooks.swift`: `NovagramCallRecordRequest.callId` (`UUID?`); `novagramSetCallId` / `novagramCallId` keep a weak `PeerCallArguments` → `CallSessionInternalId` list (dead entries pruned on every set), so the Record button and auto-record pass the call id.
- `NovagramCallRecording` (NovagramCore): `toggle` / `autoStart` take `callId`; when the recorder has really started (manual or auto) `sendNotice` sends one text message to the call's peer through `enqueueMessages(account: engine.account, ...)` (the engine of the account in the call). Once per call: `noticeCallId` remembers the last call id that got the notice, so Stop → Record again in the same call sends nothing; a new call (also a redial in the same window) has a new session id and sends again. Only for `Namespaces.Peer.CloudUser` peers, never without a call id (the debug `PeerCallLab` has none), never for group calls or conferences (no Record there). Never secret (agreed with iOS): `start` first reads the peer's messaging state (`canSendMessagesToPeer` (deleted account), `Peer.IsBlocked`, `Peer.IsPremiumRequiredForMessaging`, `Peer.SendPaidMessageStars`) together with the peer and microphone; if the notice cannot be sent (or there is no call id) the recorder is not created, no file is written and the toast `callRecording_noticeFailed` shows (en "Couldn't notify the other person, so the call is not being recorded.", uz "Suhbatdoshga xabar berib bo'lmadi, shuning uchun qo'ng'iroq yozilmayapti.", ru "Не удалось уведомить собеседника, поэтому звонок не записывается."). The check is skipped when this call already got the notice. Fallback: if `enqueueMessages` returns no message id, the running recording (only if it is still the one the notice was for) stops through `stop(discard: true)` (the normal stop path; the finished temp file is deleted instead of saved, no save panel or saved toast), the same toast shows, `noticeCallId` is cleared so the next Record tries again, and debug builds log "recording notice was not sent". A later delivery failure (the message turns failed in the chat) does not stop the recording.
- REC badge always visible: the call screen hides its controls only by fading named views (`PeerCallScreenView.updateLayout`, `hideOutside` = video on + mouse outside + active: settings, add peer, status, video shadow, tooltips, secret key, actions). The badge is not one of them (a separate content-view subview, layer `zPosition` 1000, no hit testing). `NovagramCallRecordBadgeView` now follows the window, not a fixed view: it observes `window.contentView` (KVO) and, every timer tick, moves itself back into the current content view and to the top of its subviews, so a content view swap (`PeerCallScreen.show`, the present transition's `attach`) or a later subview (status tooltip, participants) never hides it.
- Strings (`NovagramL10nParity.swift`): `callRecording_notice` (en "🔴 I'm recording this call (Novagram)", uz "🔴 Men bu qo'ng'iroqni yozib olyapman (Novagram)", ru "🔴 Я записываю этот звонок (Novagram)"), `callRecording_warningText` (consent alert) and `callRecording_footer` (Settings → Calls footer) replaced: the other person gets a message, the REC mark stays visible; no more "the other person is not notified".

`// Novagram` lines in `packages` + `Telegram-Mac`: 482 before, 483 after.

Manual repro for regressions (test account only): developer flag and Call recording on, call a test contact, press Record: the contact's chat gets "🔴 I'm recording this call (Novagram)" once; Stop and Record again: no second message; hang up and call again, Record: a new message. Video call with the mouse outside the window: the controls fade, REC mm:ss stays.


## Call recording kit SDK (2026-10-30)

Owner: call recording is one shared SDK owned by the iOS session, `Novagramorg/novagram-call-recording-kit-sdk` (public, GPL-2.0-or-later), git submodule at `packages/NovagramCallRecordingKit`, pinned at c4468bf (no tags; update by moving the pin, never edit it here). NovagramCore depends on it as a local path package (`../NovagramCallRecordingKit`, products `NovagramCallRecordingCore` and `NovagramCallRecordingUI`). Every SDK use is behind `if #available(macOS 14, *)`. Never run a bare `git submodule update` (it wipes the TelegramCore fork patches); on a fresh clone `git submodule update --init -- packages/NovagramCallRecordingKit`.

No Telegram file changed (`// Novagram` lines: 483 before, 483 after).

SDK now owns:
- Writing: `CallRecordingCenter` (our own instance in `NovagramCallRecording`, no singleton; a new one when the target folder changes) with `CallRecordingConfiguration(videoSize: 1280x720)`: mixing to one AAC track, H.264 on a fixed 1280x720 canvas at ≤ 30 fps, letterboxed (the known change: before, the video had the window's own size), 2 s movie fragments, `.partial` recovery after a crash, `.m4a` when no video ever came, file name `<peer> yyyy-MM-dd HH.mm`, the duration extended attribute.
- `CallRecordingSettings`: keys `novagram_call_recording`, `novagram_call_recording_auto`, `novagram_call_recording_warned`, `novagram_dev_call_recording` (`NovagramCallRecordingSettings` and `NovagramDeveloperFlags` read the SDK's key constants and store through it).
- `CallRecordingNoticePolicy`: the once-per-call-session-id rule (`beginSending` / `markDelivered` / `markFailed` / `forget` when the call ends; `NovagramCallRecordCallState.callId` carries the id to `callDidUpdate`), the chat message and the failure toast in en/uz/ru/zh. Our `callRecording_notice`, `callRecording_noticeFailed` strings and `noticeCallId` are deleted.
- The recordings list UI (`CallRecordingsListView`).

The app keeps:
- `NovagramCallCapture` (new, replaces `NovagramCallRecorder` + `NovagramCallAudioMixer`, both deleted): ScreenCaptureKit on the call window; app audio → `session.audioTap.appendSampleBuffer(_, source: .remote)`, the microphone (SCK on macOS 15+, `AVCaptureSession` on macOS 14, the Call Settings device) → `.microphone`, complete window frames → `CallRecordingVideoFrame(sampleBuffer:)` as the `.remote` side. Window frames are forwarded from the start for a video call, or from the moment video turns on (the SDK switches the file to video halfway; the old "stays audio only" toast `callRecording_audioOnly` is deleted). Mute → `session.setMuted`. A stream stop stops the recording; `onDetach` of a session the app did not stop (the writer failed) cleans up and shows "Call recording failed".
- The developer flags, the consent alert, the Screen Recording permission flow, the "can notify" pre-check, stop + discard when the notice cannot be enqueued, the REC badge with its KVO, auto-record.
- The save folder: with a chosen folder (security-scoped bookmark) the center writes straight into it (access is held from start until the SDK has finished the file; if the SDK cannot start there, the recording goes to the default folder and the save panel instead); "Ask every time" records into `CallRecordingStorage.defaultDirectory` (Application Support/CallRecordings in the container) and then shows the save panel (Cancel or failure → ~/Downloads, as before). Quit during a recording: `stopAll(timeout: 3)` and a wait, then new files of the default folder go to ~/Downloads (chosen folder: they are already there).
- Recordings list: Novagram Settings → Calls → "Recordings" / "Yozuvlar" / "Записи" (`callRecording_list`, row id `callRecordingList`, sub key `call_recordings`), right under Call recording, only with the developer flag on and macOS 14+. `NovagramCallRecordingsController` (NovagramCore, `makeNovagramCallRecordingsController()`) hosts `CallRecordingsListView(storage:environment:)` in an `NSHostingView` for the chosen folder (security-scoped access while the screen lives) or the default folder; theme from `theme.colors` (rebuilt on `appearanceSignal`), the app language, a day header (Today / Yesterday from the SDK strings, otherwise a localized date), `ByteCountFormatter` sizes, `onPlay` = `NSWorkspace.open`, `onShare` = `NSSharingServicePicker`.

Our files: added `NovagramCallCapture.swift`, `NovagramCallRecordingsController.swift`; deleted `NovagramCallRecorder.swift`, `NovagramCallAudioMixer.swift`; changed `NovagramCallRecording.swift`, `NovagramCallRecordingSettings.swift`, `NovagramDeveloperFlags.swift`, `NovagramL10nParity.swift`, `NovagramCore/Package.swift`, `PrivateCallScreen/NovagramCallRecordHooks.swift`, `NovagramHooksInstall.swift`, `Telegram-Mac/novagram/NovagramSettingsController.swift`.

Manual repro for regressions (test account only): the earlier call recording repros, plus: video call → the file is 1280x720 letterboxed; a voice call that turns on video → the file becomes mp4; Settings → Calls → Recordings lists the files, double-click plays, Share opens the share menu.

Review fixes (2026-10-30, on top of ef6b3707c), all in our files:
- Discard keeps the security scope: `recordingDidFinish` releases the folder in a `defer`, so it runs last on every path (discard, save, failure). `discardFile` returns whether the file is gone and is tried twice; if the discarded file is still on disk, the app logs it, and it never shows any "saved" UI for a discarded recording.
- Share anchor: the SDK's rect (SwiftUI `.global`, top-left origin) is flipped against the window's content view height and converted with `host.convert(_, from: nil)`.
- Start race: `start` remembers `startingWindow`. `callDidUpdate` also handles a call end while a start is in progress (`capture != nil || isStarting`) and keeps the ids of ended calls (`endedCallIds`). The peer-lookup callback returns without starting when `stopWhenStarted` is set or the call has ended, and so does the capture start callback, before it opens a session (so no notice is sent after hang-up or flag-off). The manual and auto consent `proceed` blocks check that the call is still active (`isCallActive`, and the window is still visible for manual).
- Pre-check data: `engine.peers.fetchAndUpdateCachedPeerData(peerId:)` (at most 2 s, then go on) runs before blocked / premium-required / paid-messages are read. If the data is still unknown, the recording is allowed and the enqueue fallback stays.
- Quit: stops in flight are counted (`pendingStops`). `stopForQuit` starts `stopAll` and then runs the main run loop in 50 ms steps until both `stopAll` and the pending stops are done, or until 3 s have passed. While quitting, a finished recording gets no UI: "Ask every time" files go to ~/Downloads, a chosen folder already holds them, and failures are only logged.

Kit pin c9c508c (2026-10-30): `packages/NovagramCallRecordingKit` moved from c4468bf to c9c508c (b7cd526 `showsToolbar` and the select / clear-all API on the view model, af33aa8 `CallRecordingTheme.freeText`, c9c508c iOS-only row insets).
- `NovagramCallRecordingsController` owns the `CallRecordingsListViewModel` (`CallRecordingsListView(model:environment:)`), sets `showsToolbar = false` (the SwiftUI toolbar does not render in our `NSHostingView`) and sets `freeText` from `theme.colors.grayText`.
- The menu lives in Telegram's navigation bar: a right `ImageBarView` (`theme.icons.chatActions`) whose `contextMenu` holds:
  - the filter (All / Video / Voice, the current one checked);
  - Select, or, while selecting or with rows selected (the Mac list always allows multi-selection), Select All / Deselect All, Share (`NSSharingServicePicker` at the view centre), Delete N (our `verifyAlert` with the SDK's `deleteSelectedConfirm`, then `model.delete`) and Done;
  - Clear All (`model.requestClearAll()`: the list shows the SDK's own confirmation), only when rows are visible.

  The SDK's `CallRecordingStrings` (en/uz/ru/zh) provide every menu title. `NovagramMenu` (in `NovagramCallRecordingSettings.swift`) is a typealias for TGUIKit's `ContextMenu`, because SwiftUI also has a `ContextMenu` and the TGUIKit module has a `TGUIKit` struct.
- Deep link: `tg://settings/novagrampro/call-recordings` (slug `call-recordings`, `novagramCallRecordingsSlug`) opens the Recordings screen above Novagram Settings, only while the developer flag is on and on macOS 14+ (`novagramSettingsSlugAllowed`); the row's share link uses the same slug (`novagramSettingsSlugs`).

## One switch per unapproved feature (2026-10-30)

Owner rule (iOS does the same): an unapproved feature is one feature with one switch, inside the hidden Developer section (revealed by the 20 s hold on the version line). The developer role sees these rows; a director login turns their keys off (`NovagramDeveloperRole.didLogIn`: `novagram_call_recording`, `novagram_call_recording_auto` and `novagram_call_data_saving` set to false). No Telegram file changed (`// Novagram` lines: 475 before, 475 after; the 483 → 475 drop is the all-accounts search removal commit).

- Developer section (`Telegram-Mac/novagram/NovagramSettingsController.swift`): the first group keeps the existing switches, plus "Job search" (`novagram_dev_job_search`; the title has lost "(beta)") and "Use less data for calls" (`novagram_call_data_saving`), then the developer footer. Below it, on macOS 14+, a second group: "Call recording" (`novagram_call_recording`) and, while it is on, "Record every call automatically", "Save to" (`novagram_call_recording_folder`) and "Call recordings" (the list), with the call recording footer. The Calls section is gone.
- Removed: `NovagramDeveloperFlags.isCallRecordingEnabled` / `callRecordingSignal` / `isCallDataSavingEnabled` / `callDataSavingSignal`, the `devCallRecording` / `devCallDataSaving` rows, state and strings. `NovagramDeveloperRole.Switch.callRecording` / `.callDataSaving` stay and now gate the user-key rows.
- Gating is the user key alone: `NovagramCallRecordingSettings.isEnabled` = macOS 14+ and `novagram_call_recording`, so the Record button, auto-record, the notice and the capture follow this key alone. `TelegramCallsCore/NovagramCallDataSaving.swift` reads only `novagram_call_data_saving` (`.always` / `.never`); Telegram's `VoiceCallSettings.dataSaving` is never touched.
- `NovagramCallRecordingSettings.enabledSignal` emits the key on `UserDefaults.didChangeNotification`, `NovagramSettingsChanged` and `novagramDeveloperFlagsChanged`. The call screen's `recordingSignal` hook combines it in, and `NovagramCallRecording` watches it: when the key turns off during a recording, the recording stops through `stop()` and is saved, and a start in progress stops as soon as it starts (same as the old flag).
- Slugs `call-recording`, `call-recording-auto`, `call-recording-folder`, `call-recordings` and `call-data-saving` work only while the Developer section is revealed (`NovagramAdsGate.isRevealed`), the role can use the switch, and (for recording) macOS is 14+. Otherwise they do nothing.
- SDK: c9c508c's `CallRecordingSettings.isEnabled` / `isAutoEnabled` still AND `isDeveloperEnabled` (`CallRecordingCore/Settings/CallRecordingSettings.swift:47-54`). The Mac never reads them (only `isUserEnabled`, `isUserAutoEnabled`, `wasWarned`, the key constants, and our own `isRecordingEnabled` passed to the list), so it needs no new pin. Move the pin when iOS ships the user-key-only version, to stay in line.

## Call recording settings page (2026-10-31)

Owner (via the iOS session, iOS main e74695a3e0): the Developer section has one "Call recording" row (value On / Off) that opens its own page, laid out like the system Settings' Camera page: every setting in its own block with an explanation under it. No Telegram file changed.

- Kit pin `packages/NovagramCallRecordingKit` moved from addbfcc to d4291ae: `CallRecordingSettingsStrings(languageCode:)` (all page texts), and the list texts no longer name a device or say tap / click (owner rule: one neutral text for every platform, App Review).
- `NovagramCore/NovagramCallRecordingSettingsController.swift` (new, InputDataController): RECORDING header + "Call recording" switch + footer; while on, "Record every call automatically" + footer and the Mac-only "Save to" row (`callRecording_saveToFooter`, en/uz/ru); RECORDINGS header + "Call recordings" row (count as value, opens the list) + footer, always shown; PRIVACY header + text. Turning the switch on still opens the folder picker. The count is read off the main thread (`NovagramCallRecordingSettings.recordingCountSignal`) and refreshed when the page appears again. NovagramCore now depends on `GeneralRows` and `InputDataUI`.
- Developer section (`Telegram-Mac/novagram/NovagramSettingsController.swift`): the second call recording group is gone; one row after "Use less data for calls" (`pageRowTexts`, opens the page, macOS 14+, role `.callRecording`). The row follows `NovagramCallRecordingSettings.enabledSignal`.
- Slugs (`NovagramSettingsLinks.swift`): `call-recording` highlights the Developer row; `call-recording-auto` / `call-recording-folder` open the page and highlight that row; `call-recordings` opens the page, then the list. Gating is unchanged.
- Removed strings: `callRecording_title`, `_subtitle`, `_list`, `_footer`, `_auto_title`, `_auto_subtitle` (the SDK texts replace them). The list's title is the SDK's `CallRecordingStrings.title`.

Manual repro: reveal Developer (20 s hold), Novagram Settings → Developer → Call recording (shows Off) → the page; turn the switch on: folder picker, auto + Save to blocks appear, the Developer row shows On after Back; turn it off: auto + Save to hide, Call recordings stays and opens the list.

## App Store rating prompt (2026-10-31)

Owner request via the iOS session: the shared SDK `Novagramorg/novagram-review-prompt-kit-sdk` (public, GPL-2.0-or-later, owned by the iOS session), git submodule at `packages/NovagramReviewPromptKit`, pinned at ee588de (no tags; update by moving the pin, never edit it here). NovagramCore depends on it as a local path package (product `NovagramReviewPromptCore`). On a fresh clone: `git submodule update --init -- packages/NovagramReviewPromptKit`.

Owner decisions (fixed): every user, no Developer gate; Apple's system prompt only (no custom alert, no "Enjoying?" question, no age logic, no reward); the SDK defaults for the 11 counted features and the rules (5 successes of one feature, 3 days after start, 14 days apart, once per app version, 5 new successes after every request). State: `pro_messager`, key `novagram_review_prompt_state`.

- `NovagramCore/NovagramReviewPrompt.swift` (new): the one `ReviewPromptCenter` of the app. `record(_:)` (any thread), `loginScreenDidShow()` + `accountDidStart(accountId:)` (a login = an account start after the login screen, with another account than before → `noteFreshStart()`; launches, account switches and a cancelled "Add Account" do not count), `chatListDidAppear(window:isBusy:)`, `rateTitle` / `rateFooter` (SDK `ReviewPromptStrings`), `openWriteReview()` (`macappstore://…?action=write-review`). Logs every success and every request result to the unified log (subsystem `uz.fenixuz.app`, category `NovagramReviewPrompt`).
- Natural break (`NovagramHooksInstall.swift`, `novagramReviewPromptDidStart`, skipped for the support account window): `context.globalPeerHandler` becomes nil, which happens only when the empty right pane appears (dual layout), the chat list appears after closing a chat (single layout) and at account start. `isBusy`: a chat opened during the SDK's 2 s delay, passcode/screen lock (`notificationManager.isLocked`), `sharedContext.hasActiveCall`, `NovagramCallRecording.shared.isRecording`, the secret vault revealed, any modal (`hasModals(window)`, covers the chat lock PIN sheet).
- Settings: Novagram Settings top section, "Rate Novagram" row under About (`.topRate`, star icon) + the SDK footer. No "Send feedback" row (same as iOS).

Success points (11, verified 2026-10-31):

| Feature | Where | Counts when |
|---|---|---|
| editedHistory | `Telegram-Mac/novagram/NovagramEditedHistoryController.swift` | the history screen has loaded |
| translateMessage | `TranslateUI/.../TranslateModalController.swift` → `NovagramTranslateHooks.didTranslateMessage` (new `NovagramTranslateHooks.swift`, set in `installNovagramHooks`) | a chat message (`messageId` set; not the input AI modes, bio, link or gallery text) with a non-empty result |
| speechToText | `ChatUI/NovagramSpeechToTextButton.swift` | dictation stopped with text |
| voiceTranslate | same file, `translateDictated` | the translated text replaced the input |
| storySave | `StoriesUI/.../StoryModalController.swift` (others' stories, the Premium/Novagram save item) → `StoriesUI/NovagramStorySave.swift` (new: `saveAs(_:account:)` + the save panel completion) | the file exists at the saved path. Saving your own story is Telegram's and is not counted |
| roundVideoFromGallery | `ChatUI/NovagramRoundVideo.swift` | the round video was enqueued |
| forwardWithoutNames | `ChatUI/NovagramMessageMenuItems.swift` marks the ids, `ChatController.swift` send path → `novagramForwardDidSend` | the message put into the input by our last "Forward without Quotes" item is sent with hide names on. Telegram's own hide-sender toggle is not counted |
| ghostMode | `NovagramCore/NovagramGhostMode.swift` (`isActive` setter, every path) | turned on |
| chatLockUnlock | `NovagramCore/NovagramChatLockGate.swift` (`proceed`, also after master recovery) | correct PIN |
| secretVaultUnlock | `NovagramCore/NovagramHiddenChatsManager.swift` (`unlockDirectly`) | vault revealed |
| viewFirstMessage | `ChatController.swift` (existing Novagram menu line) | the item was chosen |

`autoTranslate` and `callRecordingSaved` are not reported (not counted by the SDK default anyway).

Telegram files (`// Novagram` lines 479 → 484): `Telegram-Mac/app/ApplicationContext.swift` (2: login screen, account start), `ChatUI/ChatController.swift` (1 new: forward send; the View First Message line changed), `StoriesUI/StoryModalController.swift` (1: `saveAs` → `novagramSaveStory`), `TranslateUI/TranslateModalController.swift` (1).

Testing: a Debug build shows the system sheet on every request, builds outside the App Store may show nothing, so check the log: `log stream --level default --predicate 'subsystem == "uz.fenixuz.app" AND category == "NovagramReviewPrompt"'`. To start over: `defaults delete <pro_messager suite> novagram_review_prompt_state` (app quit) or the SDK's `removeObject(forKey: ReviewPromptCenter.stateKey)`.

Manual repro: fresh state → use one feature 5 times (e.g. View First Message from the chat header menu) → the log shows `success viewFirstMessage, new 5`; close the chat → `request <version>: skipped(tooSoonAfterStart(until: …))` until 3 days after the start; with the start date moved back, closing a chat logs `requested` and the Debug build shows the sheet; during a call or with a sheet open it logs `busy`.
