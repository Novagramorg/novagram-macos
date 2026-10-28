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
