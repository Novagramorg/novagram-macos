# FENIXUZ_HOOKS.md — Novagram changes to Telegram-owned files

Base: official Telegram macOS 13.1.0 (`TelegramMessenger/telegram-macos` @ `272d85dd7`, 2026-10-25).
Old fork (overtake base, July 2025): `../macOS`, its hook list is `../macOS/FENIXUZ_HOOKS.md`.

## Rules

- Novagram code lives in our own packages (`packages/FenixuzCore`, more later). Telegram files get only short call sites.
- Every line we change in a Telegram file ends with `// Fenixuz` (Swift) or is listed here (plist, pbxproj, entitlements, xcconfig), so `grep -rn "// Fenixuz"` finds all code hooks after an upstream pull.
- Edit Telegram files with exact line edits only. A formatter run over a Telegram file rewrites the whole file and breaks the next merge.
- `scripts/xcode27.sh apply` changes are local only (Xcode 27), never commit them (`scripts/xcode27.sh revert` before staging those files).
- Never push to `upstream` (push URL is disabled on purpose).

## Branding (2026-10-26)

### New files (ours)

| File                                                      | What                                                                                                                                              |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages/FenixuzCore/`                                   | Novagram SDK package. `FenixuzBranding` (Telegram → Novagram for texts we do not own, app menu), `installFenixuzHooks()`                          |
| `Telegram-Mac/Novagram.xcconfig`                          | Sparkle feed pointed at a dead local URL (the upstream feed would install official Telegram over us); Release = `APP_STORE` source and Swift flag |
| `Telegram-Mac/Assets.xcassets/NovagramAppIcon.appiconset` | Novagram app icon (copied from the old fork). Telegram's `AppIcon.icon` stays untouched and unused                                                |

### Telegram files

| File                                                                                                                               | Change                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages/ApiCredentials/Sources/ApiCredentials/Config.swift`                                                                      | `apiId`, `apiHash`, `bundleId = "uz.fenixuz.app"`, `teamId = "ZDBP5RSRZF"` (4 return values)                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `Telegram-Mac/Telegram-Mac.entitlements`, `Telegram-Mac/Telegram-Sandbox.entitlements`, `TelegramShare/TelegramShare.entitlements` | app groups and keychain groups `6N38VWS5BX.ru.keepcoder.Telegram[.TelegramShare]` / `6N38VWS5BX.ru.keepcoder.TelegramShare` → `ZDBP5RSRZF.uz.fenixuz.app[.TelegramShare]`                                                                                                                                                                                                                                                                                                                                                    |
| `Telegram.xcodeproj/project.pbxproj`                                                                                               | Telegram + TelegramShare targets: `DEVELOPMENT_TEAM = ZDBP5RSRZF` (×4), `PRODUCT_BUNDLE_IDENTIFIER = uz.fenixuz.app` / `uz.fenixuz.app.TelegramShare` (×4). Telegram target: `PRODUCT_NAME = Novagram` + `PRODUCT_MODULE_NAME = Telegram` (×2, module name kept so code and xibs still resolve `Telegram.*`), `ASSETCATALOG_COMPILER_APPICON_NAME = NovagramAppIcon` (×2). `FenixuzCore` local package linked to both targets (folder reference, 2 build files, 2 product dependencies, IDs `FE10DEC04E14C190FEFE0001…0005`) |
| `Telegram-Mac/Debug.xcconfig`, `Telegram-Mac/Release.xcconfig`                                                                     | last line `#include "Novagram.xcconfig"`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `Telegram-Mac/Info.plist`                                                                                                          | `NSHumanReadableCopyright` = `Copyright © 2026 Novagram. All rights reserved.`, `CFBundleIconName` = `NovagramAppIcon`                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `TelegramShare/Info.plist`                                                                                                         | `CFBundleDisplayName` = `Novagram`, same copyright                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| `packages/Localization/Sources/Localization/LocalizableExtension.swift`                                                            | `public var localizedValueTransform: (String) -> String = { $0 }` before `dictFromLocalization`; `dictFromLocalization` returns `dict.mapValues(localizedValueTransform)`; both bundle fallback returns in `_LocalizedStringFor` return `localizedValueTransform(resolved)`                                                                                                                                                                                                                                                  |
| `Telegram-Mac/app/main.swift`                                                                                                      | `import FenixuzCore` after `import CrashRecoveryUI`; `installFenixuzHooks()` before `installTelegramThemeHooks()`                                                                                                                                                                                                                                                                                                                                                                                                            |
| `TelegramShare/ShareViewController.swift`                                                                                          | `import FenixuzCore` after `import PasscodeCore`; `localizedValueTransform = FenixuzBranding.rebrand` before `applyUILocalization(localization)`                                                                                                                                                                                                                                                                                                                                                                             |
| `packages/TelegramUtils/Sources/TelegramUtils/AppConstants.swift` | `itunesAppLink` = `https://apps.apple.com/app/id6768202244` (Novagram). Upstream pointed the "Update" button and other App Store links at Telegram |
| `Telegram-Mac/updater/AppUpdateViewController.swift` | `import FenixuzCore`; first line of `updater_resetWithUpdaterSource`: `guard FenixuzBranding.allowsTelegramUpdater else { return }`. Telegram's updater (non App Store builds) downloads official Telegram from a Telegram channel (`requestUpdatesXml(... updates_channel_xml)`, it ignores `SUFeedURL`) and would install it over Novagram |

Notes:

- The data folder inside the app group depends on the build source: Debug uses `<group>/debug`, App Store uses `<group>/appstore`, so a debug run never touches the installed App Store app's data.
- In-app "Telegram" → "Novagram" covers server language packs and the bundled English strings (old fork: `dictFromLocalization` hook + `en.lproj` edits). Strings hard-coded in Swift are not covered.
- `tg://` and `telegram://` URL schemes stay, so Telegram links still open in Novagram.
- The "Check for Updates" menu item (tag 1000) is removed by `installFenixuzHooks()` in every build; upstream removes it only in `APP_STORE` builds.
- `MARKETING_VERSION` is still upstream's `13.1.0`. Our App Store line is `1.0.x` (last shipped 1.0.5, build 137); pick the version before the first upload.

## Port of the old fork (branch `feature/novagram-port`, 2026-10-26)

Plan: `../PORT_MAP_macOS13.md`. Build with `./fenix-build.sh` (`./fenix-build.sh appstore` also sets `APP_STORE` inside the packages, see "APP_STORE" below).

### Step 1: identity and App Store hygiene

| File | Change |
| ---- | ------ |
| `Telegram-Mac/Info.plist` | `CFBundleDisplayName` = `Novagram` (after `CFBundleDevelopmentRegion`) |
| `Telegram-Mac/Telegram-Sandbox.entitlements` | removed `com.apple.developer.associated-domains` (`webcredentials:telegram.org`, 13.1 passkeys). telegram.org does not list our app id, so it can never validate for team ZDBP5RSRZF |
| `Telegram.xcodeproj/project.pbxproj` | Telegram's `Resources/config/GoogleService-Info.plist` removed from the app Resources phase (build file `274DF1DB2DC0BE0400188E7A`; the file reference stays). Firebase is not used (`FirebaseApp.configure()` is commented out upstream). `PrivacyInfo.xcprivacy` added (file ref `FE10DEC04E14C190FFFFFFF0` in group `supporting-files`, Resources build file `FE10DEC04E14C190FFFFFFF1`) |
| `Telegram-Mac/PrivacyInfo.xcprivacy` (ours) | copied from the old fork (no tracking; required-reason APIs UserDefaults CA92.1, FileTimestamp C617.1, DiskSpace E174.1, SystemBootTime 35F9.1) |
| `Telegram.xcodeproj/xcshareddata/xcschemes/{Release,Telegram,TelegramShare}.xcscheme` | `BuildableName = "Telegram.app"` → `"Novagram.app"` |
| `.gitignore` | Novagram block (`.claude/`, `screenshots/`, `*.bak`, `*.tmp`, `DerivedData/`, `Telegram-Mac/NovagramAds.local.xcconfig`) |
| `fenix-build.sh` (ours) | Debug build with the real pass/fail result (DerivedData `/tmp/tgmac13-dd`, log `/tmp/fenix13-build.log`) |

Not ported: the old `uz.fenixuz.macapp` → `uz.fenixuz.app` container migration (`ApiCredentials`). A sandboxed app can only open app-group containers listed in its entitlements, so the move never had access to the old group.

### FenixuzCore package layout

Two products:

- `FenixuzShare` (target `Sources/FenixuzShare`, depends on Localization only): `FenixuzBranding`. Linked by the share extension, which must stay light (TGUIKit/AlertsUI pull ffmpeg and opus into the appex and break its link).
- `FenixuzCore` (re-exports `FenixuzShare`): everything else. Linked by the app and by the Telegram packages that host our hooks.

`FenixuzCore` contents copied from the old fork (app-target files there become `public` here): `FenixuzGhostMode`, `FenixuzL10n`, `FenixuzBrandColors`, `FenixuzSettingsIcons`, `FenixuzDemoCodeFetcher`, `FenixuzDeletedMessages` (temp `fenixdel.log` file logger dropped), `FenixuzEditedHistoryManager`, `FenixuzForeignUserBlock`, `FenixuzForeignUserBannerView`, `FenixuzHiddenChatsManager`, `FenixuzChatPincodeManager`, `FenixuzChatPincodeViewController`, `FenixuzAutoApproveManager` (takes `any AccountContextProtocol`), `FenixuzAutoProxy`, `FenixuzSpeechToTextManager`, `FenixuzAppStoreIAP`, `FenixuzTextStyle` (enum split out of the old text style screen). New: `NovagramHooks` (closures the app installs so packages can open our app-target screens).

| File | Change |
| ---- | ------ |
| `Telegram.xcodeproj/project.pbxproj` | TelegramShare target links product `FenixuzShare` instead of `FenixuzCore` (build file `FE10DEC04E14C190FEFE0004`, product dependency `FE10DEC04E14C190FEFE0005`) |
| `TelegramShare/ShareViewController.swift` | `import FenixuzShare` (was `import FenixuzCore`) |

### APP_STORE

`APP_STORE` reaches the app target through `Novagram.xcconfig` (`TYPE[config=Release]`), but NOT the packages: 36 `#if APP_STORE` sites in packages (PremiumUI, StarsUI, AuthUI, SettingsUI, BoostUI, ChatUI, MessageUtils, TelegramTheme) need `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) APP_STORE'` on the `xcodebuild` command line, as `buildbox/build-mac.sh` does. Every App Store archive must pass it.

### Step 5: small package edits (no new hook structs)

Packages that now depend on `FenixuzCore` (`.package(name: "FenixuzCore", path: "../FenixuzCore")` + product, both lines `// Fenixuz`): ChatHistoryModel, SidebarUI, StoriesUI, PeerInfoUI, ChatListUI, ChatUI. ShortPeerRow depends on product `FenixuzShare` in its shared `common` list (its sources are symlinked into the `ShortPeerRowShare` target). Packages FenixuzCore itself depends on (AlertsUI, GeneralRows, InputDataUI, InAppSettings, TelegramUtils, AvatarUI, …) must never import it: run `deps.py`-style checks before adding one.

| Feature | File | Change |
| ------- | ---- | ------ |
| F30 whole-chat translate without Premium | `ChatHistoryModel/.../ChatLiveTranslateContext.swift` | `if !peer.isPremium && !FenixuzPremiumUnlock.wholeChatTranslate {`; both `return (…, peer?.isPremium == true || FenixuzPremiumUnlock.wholeChatTranslate, autoTranslate)` |
| F30 folder tags without Premium | `SidebarUI/.../ChatListFilterController.swift` (`toggleColor`), `ChatListFiltersListController.swift` (`toggleTags`) | `&& !FenixuzPremiumUnlock.folderTags` on the Premium check |
| F29 story save + HD without Premium | `StoriesUI/.../StoryModalController.swift` (HD item, save item), `StoryChatContent.swift` (`preferHighQualityStories`) | `context.isPremium \|\| FenixuzPremiumUnlock.storiesSaveAndHD`; `setting && (isPremium \|\| …)`. The old fork never changed `StoryChatContent`, so HD there was cosmetic |
| F31 ID row | `PeerInfoUI/.../{User,Group,Channel}InfoEntries.swift` `case .peerId` | label `ID`, copy menu "Copy ID", click copies too, toast "ID copied" (`FenixuzL10n.peerInfo_*`). Channel value `-100<id>`, legacy group `-<id>` |
| F31 ID row on by default | `InAppSettings/.../FastSettings.swift` `canViewPeerId` | reads `pro_messager/show_peer_id`, then `kCanViewPeerId`, default `true`; setter also writes `show_peer_id` |
| F31 Novagram Info | `PeerInfoUI/.../PeerInfoController.swift` | `getRightBarViewOnce` → `BarView(40, …)`; `viewDidLoad` adds the info button (`fenixuzAddInfoButton`); `requestUpdateRightBar` recolours it. New file `PeerInfoUI/.../FenixuzPeerInfoModal.swift` (modal + button helpers) |
| F43 auto-approve (peer info) | `PeerInfoController.swift` entries `mapToQueue` | `FenixuzAutoApproveManager.shared.checkAndApprove(...)` when `joinRequestsCount > 0` |
| F32 mutual contact 🤝 | `ChatListUI/.../ChatListRowItem.swift` (title), `ShortPeerRow/.../ShortPeerRowItem.swift` (title) | `FenixuzMutualContact.title(_, for:)` (in `FenixuzShare`) |
| F16 view first message | `ChatUI/.../ChatController.swift` chat "…" menu after Info | item when `pro_messager/show_view_first_message`, calls `chatInteraction.scrollToTheFirst()` |
| F41 phone retry | `ChatController.swift` phone-number menu | "Retry" item when the number did not resolve (`peer == nil`) |
| F10 chat list paging | `ChatListUI/.../ChatListController.swift` | `fenixPageRetry` property; scroll handler is now the `pageScrollHandler` constant; dropped request inside the 0.5 s guard is rescheduled. New file `ChatListUI/.../FenixuzChatListPageRetry.swift` |
| F23 app name | `TelegramUtils/.../System.swift` | `appName = "Novagram"` (alert headers etc.) |
| F23 archive name | `ChatHistoryModel/.../SenderController.swift` | `"Novagram Archive"` |
| F23 About | `SettingsUI/.../AboutModalController.swift` | `APP_VERSION_STRING` drops the build-type suffix (Stable/AppStore/Beta); copyright `Copyright © <year> NOVAGRAM` |
| F40 "Update app" | `ChatUI/.../ChatMessageItem.swift` `invokeUpdateApp` | `#if APP_STORE \|\| true`: always opens `itunesAppLink` (Novagram App Store page), never the Sparkle check |
| X-C2-2 crash recovery | `CrashRecoveryUI/.../CrashRecovery.swift` | App Store link → Novagram (`id6768202244`), website → `https://novagram.org` |

Decision: the old Mac build's red accent palette (`#b40000` / `#ff3b30`, from the Fenixuz brand) is NOT ported. The Novagram icon and the iOS app are blue, and Telegram's own blue palette stays.

### Step 7: chat and chat list features

New dependency on FenixuzCore (both Package.swift lines `// Fenixuz`): GalleryUI, AudioPlayerCore (ChatUI, ChatListUI, StoriesUI, ChatHistoryModel already had it).

New Novagram files inside Telegram packages (ours, whole file):

| File | What |
| ---- | ---- |
| `ChatUI/.../FenixuzAskBeforeSend.swift` | `fenixuzConfirmBeforeSend` alert for stickers / voice |
| `ChatUI/.../FenixuzMessageMenuItems.swift` | forward without sender name, edit before forward, edit history item |
| `ChatUI/.../FenixuzRoundVideo.swift` | attach menu item + sender for round video from a file |
| `ChatListUI/.../FenixuzGhostButton.swift` | Ghost toggle in the chat list header (assets `FenixGhostActive/Inactive.imageset` in `Telegram-Mac/Assets.xcassets`) |
| `ChatListUI/.../FenixuzChatListMenu.swift` | chat lock set/remove (when a master PIN exists) and hide/unhide items |
| `FenixuzCore/FenixuzOutgoing.swift`, `FenixuzChatListFilter.swift`, `FenixuzChatLockGate.swift` | helpers the hooks below call |

| Feature | File | Change |
| ------- | ---- | ------ |
| F14 deleted messages | `ChatUI/.../ChatController.swift` | `deletedMessagesDisposable` (+ dispose in deinit); `viewDidLoad` subscribes to `account.stateManager.deletedMessages` → `FenixuzDeletedMessages.recordDeleted`, re-sets the location when a tombstone was created; history pass `let msgEntries = FenixuzDeletedMessages.shared.process(view.entries, ...)` |
| F15 edit history | `ChatController.swift` history pass | `FenixuzEditedHistoryManager.shared.processMessages(...)` |
| F15 edit history menu | `ChatUI/.../ChatMessageMenuItems.swift` edited-at block | `fenixuzEditedHistoryMenuItem` → `NovagramHooks.presentEditedHistory` |
| X-A-1 / X-A-2 | `ChatMessageMenuItems.swift` after `secondBlock.append(forwardItem)` | `fenixuzForwardMenuItems` |
| F13 Ghost (chat) | `ChatController.swift` | passive read `applyMaxReadIndex` gated; send path applies the read index while Ghost is on (replying implies reading); `canInteractiveRead` returns false; `clearMentions`, `clearReactions`, view counts, mention seen, reaction seen (reaction animation still plays), live location seen, recording activity gated |
| F13 Ghost (typing) | `ChatUI/.../ChatInputView.swift` | `.typingText` only when Ghost is off or `isPresent == false` |
| F13 Ghost (media) | `GalleryUI/.../GalleryViewer.swift`, `ChatUI/.../SingleTimeMediaViewer.swift`, `AudioPlayerCore/.../AudioPlayerController.swift` | `markMessageContentAsConsumedInteractively` skipped while Ghost is on |
| F13 Ghost (stories) | `StoriesUI/.../StoryChatContent.swift` | the three `markAsSeen(id:)` return early |
| F13 Ghost (chat list) | `ChatListUI/.../ChatListRowItem.swift` `markAsRead` | `clearPeerUnseenPersonalMessagesInteractively` gated; `PeersListController.swift` header: `ghost` button next to proxy (update, title width, layout) |
| F21 ask before send | `ChatController.swift` | `sendAppFile` and `sendMedias`: the original `invoke` closure is renamed (`fenixuzSendAppFile` / `fenixuzSendMedias`) and `invoke` now asks first; `sendMedia` (recorded voice) is renamed `fenixuzSendMedia` and the new `chatInteraction.sendMedia` asks first (cancel also cancels the voice send animation). The old fork only gated `sendMedias`, so recorded voice was never confirmed |
| F17 outgoing transforms | `ChatHistoryModel/.../SenderController.swift` | text `enqueue` gains `skipAutoTranslate: Bool = false`; auto text + auto translate after the media preview block; style entity appended to the text entities; heart effect (`FenixuzOutgoing.effectId`) in the text path and in `enqueue(media:[Media]...)`; `recordSent(media)` remembers the last sticker; `sendAutoSticker` after the text messages are enqueued |
| F19 round video | `ChatUI/.../ChatInputAttachView.swift` | item after the File item (hidden when the channel bans round videos) |
| F11 / F12 hidden chats, foreign block | `ChatListUI/.../ChatListController.swift` | one `prepare.removeAll(where: FenixuzChatListFilter.isFiltered...)` after the pending-removals filter (covers additional items too); Cmd+Shift+H installed once (`FenixuzHiddenChatsShortcut.install()` in `viewDidLoad`; the old fork added a monitor per chat list) |
| F28 hide folders | `ChatListController.swift` | `fenixLastFolderTabs`, both tab subscriptions use `FenixuzChatListFilter.hideFolders ? [] : filters.list`; a block observer of `FenixSettingsChanged` (generic class, no `@objc`) re-applies tabs and stories; removed in `deinit` |
| F29 hide stories | `ChatListController.swift` (archive/stories group row), `PeersListController.swift` `hasStories` | `FenixuzChatListFilter.showStories` |
| F20 chat lock | `PeersListController.swift` `open(with:...)` first line | `FenixuzChatPincode.requiresUnlock(...)` reopens with all arguments (incl. `fullWidthTopics`) after the PIN; unlocked chats stay open for the session |
| F20 / F11 row menu | `ChatListRowItem.swift` before `let blocks` | `thirdGroup.append(contentsOf: fenixuzChatListMenuItems(...))` |

Not ported: F33 "Sneak peek" row item. 13.1 has a native Preview item (`chatListContextPreview`), and the old item only opened the chat normally (it did send read receipts).

### Login (AuthUI)

AuthUI depends on FenixuzCore (`// Fenixuz` on both Package.swift lines).

| Feature | File | Change |
| ------- | ---- | ------ |
| F22 NovagramProxy on login | `AuthUI/.../AuthController.swift` `AuthView` | `novagramProxyButton` (text link, top centre `y: 18`), styled in `updateLocalizationAndTheme`, excluded from the step-view stretch loop in `layout()` (without it the button got a full-height hit area that swallowed footer clicks); `AuthController` handler + `toggleNovagramProxy()` (FenixuzAutoProxyManager on/off + alert) |
| F37 demo login | `AuthController.swift` | `sendCode` first line `FenixuzDemoCodeFetcher.prewarmIfDemo`; after `code_entry_c.update(...)` `autoFillIfDemo(... applyExternalLoginCode)`; `.passwordEntry` first line `dismissIfActive()` |
| F23 login logo | `AuthUI/.../Auth_PhoneNumber.swift` (`logo`), `Auth_Token.swift` (`logoView`, QR centre) | `NSImageView` with `NSApp.applicationIconImage` instead of the Telegram airplane Lottie (4.1 copycat risk) |

Not ported: the old emerald Next button (`FenixuzBrandColors.primary`), same reason as the palette (blue brand).

### Novagram screens and managers (app target)

| File | What |
| --- | --- |
| `Telegram-Mac/novagram/` | Novagram Settings and its sub-screens (About, Tips, Text style, Auto-text, Auto-translate, Translation language, Bots, All accounts, Analytics, Edited history) and the app-side managers (UnreadReminder, SuggestedFolders, Analytics, StatisticsClient/Config). The screens use the concrete `AccountContext` and the bridge `TableViewController`. Auto-text is now an `InputDataController` (13.x has no `GeneralInputRowItem`); keys `auto_text_enabled` and `auto_text_content` are unchanged. The hidden "Remove all ads" section is left out until `FenixuzAdsGate` is ported |
| `Telegram-Mac/novagram/novagram_bots.json`, `russia_proxies.txt` | App resources read through `Bundle.main` (Bots catalogue, `FenixuzAutoProxy` pool) |
| `Telegram-Mac/novagram/NovagramSettingsLinks.swift` | `tg://novagrampro`, `tg://novagram/<f>`, `tg://fenixuz/<f>`, `tg://settings/novagrampro[/<f>]` (f = about, bots, tips, text_style, auto_text, auto_translate, translate_language, translation_language, language) |
| `Telegram-Mac/packages-integration/hooks/NovagramHooksInstall.swift` | `installNovagramHooks()`: `NovagramHooks.presentEditedHistory` pushes `FenixuzEditedHistoryController`; calls `installNovagramSettingsHooks()` |
| `Telegram-Mac/packages-integration/hooks/NovagramSettingsHooksInstall.swift` | Rows: Accounts 910, gold Novagram Settings 911, Novagram Bots 912, Analytics 913 (914 reserved for Ads Analytics). Hides paid rows and inline accounts |
| `packages/SettingsUI/Sources/SettingsUI/NovagramSettingsHooks.swift` | `NovagramSettingsHooks`: extra Settings rows (`rows(context, .accounts/.top)`, ids 900–998), `selectedRowId`, `rowsUpdated`, `hidePaidRows`, `showInlineAccounts`, `versionRowClick` (reserved for the ads gate). Neutral defaults |

### Settings, accounts and app shell (Telegram files, every line `// Fenixuz`)

| File | Change |
| --- | --- |
| `Telegram-Mac/app/main.swift` | `installNovagramHooks()` after `installFenixuzHooks()` |
| `packages/SettingsUI/.../AccountViewController.swift` | `case novagram(index:viewType:row:)` + stableId/index/item lines; Novagram rows before Add Account and before My Profile; inline account loop gated by `showInlineAccounts`; Premium/Stars/TON/Business/Gift block gated by `!hidePaidRows` (F01, Apple 3.1.1); version row asks `versionRowClick` first; `appUpdateState` combined with `rowsUpdated`; selection branch from `selectedRowId` |
| `packages/SettingsUI/.../EditAccountInfoController.swift`, `LogoutViewController.swift` | literal `3` account limit → `maximumNumberOfAccounts` (2 lines each) |
| `packages/TelegramUtils/.../AccountUtils.swift` | `maximumNumberOfAccounts = 999` |
| `packages/InAppSettings/.../AccountsLimit.swift` | `normalAccountsLimit = 999` |
| `Telegram-Mac/packages-integration/hooks/SettingsHooksInstall.swift` | `appUpdateState = .single(nil)` (no Sparkle "Update" row) |
| `Telegram-Mac/app/MainViewController.swift` | `UpdateTabController`: both update-pill branches behind the never-set `FENIXUZ_UPDATE_PILL` (2 `#if` lines) |
| `Telegram-Mac/app/AppDelegate.swift` | `import FenixuzCore`; `applyMaxReadIndexInteractively` skipped in Ghost mode; `FenixuzAnalyticsManager.shared.start(sharedContext:)` and `FenixuzAutoProxyManager.shared.start(accountManager:)` after `sharedApplicationContextValue`; `Dock.setCustomAppIcon(path: nil)` before `launchInterface()` |
| `Telegram-Mac/app/ApplicationContext.swift` | `import FenixuzCore`; unread reminder start (after `AppMenu.closeAll()`), clear (in `clearReadNotifiesDisposable`), stop (deinit); hide folders also hides the folder rail: `fenixEffectiveSidebar(_:)`, `fenixEffectiveSidebarShown`, used in `updateLeftSidebar` (bar position, current/previous), split-view insets and `applyWindowChrome`; `FenixuzChatListFilter.settingsChanged` observer → `fenixHideFoldersRailChanged` |
| `Telegram-Mac/account/SharedWakeupManager.swift` | `import FenixuzCore`; no online presence in Ghost mode; `FenixuzGhostMode.didChangeNotification` observer → `updateAccounts()` |
| `Telegram-Mac/account/AccountContext.swift` | `requestApplicationIcons` commented out (no server app icons) |
| `Telegram-Mac/utils/UNUserNotifications.swift` | `import FenixuzCore`; notification dismiss does not mark read in Ghost mode |
| `Telegram-Mac/utils/InAppLinks.swift` | `case novagramSettings(link:context:feature:)`, its `link` accessor, `execute` case, and the pre-check in `inApp(for:)` before `parseInAppLink` |
| `Telegram.xcodeproj/project.pbxproj` | group `novagram` (`FE304E0B0000000000000001`) under `Telegram-Mac`; all app files above as `FE304E0B…0002`–`…002B` (Sources / Resources of target `Telegram`) |

### F18 speech-to-text button

| File | Change |
| --- | --- |
| `ChatUI/.../FenixuzSpeechToTextButton.swift` (ours) | button + `FenixuzSpeechToTextManager` driver. Sits inside the message field, left of the emoji/actions buttons (13.1 rebuilt the input around the glass row, so the old slot next to the send button is gone). Dictated text replaces the input; any manual change of the input stops dictation. Setting `pro_messager/stt_enabled` (default on, as in the old Mac build) |
| `ChatUI/.../ChatInputView.swift` `ChatInputContainerView` | `fenixSpeechToText` lazy property; `textViewSize` reserves `FenixuzSpeechToTextButton.reservedWidth`; `updateLayout` places the button after the actions view (hidden for rich drafts and non-text input states) |

### App Store gates and Release hygiene

| File | What |
| --- | --- |
| `Telegram-Mac/novagram/FenixuzBlockingPurchaseManager.swift` (ours) | 3.1.1 StoreKit chokepoint: `buyProduct` shows the blocked alert and fails with `.cantMakePayments`, `restorePurchases` alerts and returns `.succeed(false)`, products and `canMakePayments` forward to the real manager |
| `fenix-publish.sh` (ours) | App Store archive (`SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) APP_STORE'` on the command line so packages get it) into `build/archives/`, `--preflight` setting checks and `--check <xcarchive>` checks (sandbox, no get-task-allow, team, no Sparkle, no SU* keys, PrivacyInfo, bundle id). Uploads nothing |
| `Telegram-Mac/account/AccountContext.swift` | `inAppPurchaseManager` wrapped in `FenixuzBlockingPurchaseManager` |
| `Telegram-Mac/packages-integration/hooks/FeatureNavigationHooksInstall.swift` | `makePaymentsCheckoutController` and `...WithContext`: `shouldBlock(invoice:source:)` → alert, `completion?(.cancelled)`, `nil` (covers Premium boarding, gifting, star gifts, giveaways, Stars top-up) |
| `Telegram-Mac/packages-integration/hooks/ChatUIHooksInstall.swift` | `showPaymentsCheckout` and `...WithContext`: invoice gate (`.message`) |
| `Telegram-Mac/packages-integration/hooks/BrowserHooksInstall.swift` | `presentBrowserInvoice`: invoice gate (`.slug`), returns `cancelled` |
| `Telegram-Mac/utils/InAppLinks.swift` | `executeInvoiceLink` card branch: invoice gate (`.slug`) |
| `Telegram-Mac/packages-integration/hooks/TelegramLinksHooksInstall.swift` | `openExternalLink`: Fragment TON top-up (`fragmentTonAddFundsLink`) shows the blocked alert (Star_ListScreen, AddTonBalanceController). The same URL inside a chat message still opens |
| `packages/FenixuzCore/.../FenixuzAppStoreIAP.swift` (ours) | `shouldBlock(invoice:source:)` (non-XTR digital sources blocked; `.slug`/`.message` only when a subscription; TON resale open), `shouldBlockExternalPurchase(link:)`, generic alert text `iap_blockPurchases_*` (no link, no mention of official Telegram) |
| `Telegram-Mac/Novagram.xcconfig` (ours) | `OTHER_LDFLAGS[config=Release] = $(inherited) -Wl,-dead_strip_dylibs` (APP_STORE code never references Sparkle, so its load command goes) |
| `Telegram.xcodeproj/project.pbxproj` | Telegram Release `OTHER_LDFLAGS = ($(inherited), -ObjC)` so the xcconfig flag applies; Telegram and TelegramShare Release `CODE_SIGN_IDENTITY` = `Apple Development` (was empty: ad-hoc archive, "No Team Found in Archive"); Run Script phase `FE40A0B1C2D3E4F500000001` "Novagram: strip Sparkle (App Store)" after the Copy Files phases (Release only: removes `Sparkle.framework`, deletes `SUFeedURL`/`SUPublicDSAKeyFile`); `FenixuzBlockingPurchaseManager.swift` (`FE304E0B…002C/2D`) |
| `.gitignore` | `build/` (release archives) |

### TelegramCore fork patches (prepared, applied with F06)

`fork-patches/telegramcore/FenixuzBotAuthorization.swift` (13.1: `case let .authorization(authorizationData)`), `FenixuzBotSession.swift`, `fork-patches/telegramcore-hooks.patch` regenerated against `release-13.1.1` (AccountStateManagementUtils, ManagedChatListHoles, ManagedMessageHistoryHoles, ManagedPendingPeerNotificationSettings, ChatListFiltering), `fork-patches/apply-telegramcore-patches.sh`.

### F39 strings

`Telegram-Mac/novagram/FenixuzSettingsController.swift`: the rows the old fork hard-coded in Uzbek (ask before send, auto-approve, suggested/admin folders, footer) now use `FenixuzL10n` (en/uz/ru).

### F06 bot-token login and passkeys

| File | Change |
| --- | --- |
| `fork-patches/` (applied to `submodules/telegram-ios`) | `FenixuzBotAuthorization.swift` (`importBotAuthorization`, `ImportBotAuthorizationError`; 13.1 `internal import TelegramApi`, `case let .authorization(authorizationData)`), `FenixuzBotSession.swift`, `telegramcore-hooks.patch`. Re-run `./fork-patches/apply-telegramcore-patches.sh` after every `git submodule update` |
| `packages/FenixuzCore/.../FenixuzLoginFeatures.swift` (ours) | `passkeys = false`, `botToken` (set by the app) |
| `Telegram-Mac/app/main.swift` | `#if !APP_STORE` `FenixuzLoginFeatures.botToken = true` `#endif` (the package cannot see the app's flag reliably, so the app sets it) |
| `AuthUI/.../Auth_BotToken.swift` (ours) | bot token screen (header, token field, Next, help link to core.telegram.org/bots, Cancel, clipboard prefill) |
| `AuthUI/.../FenixuzBotTokenLink.swift` (ours) | link styling + `fenixuzLoginWithBotToken` (import, 20 s timeout, connection-error retry alert) |
| `AuthUI/.../Auth_Token.swift`, `Auth_PhoneNumber.swift` | `botTokenButton` + `takeBotToken` (added only when `FenixuzLoginFeatures.botToken`), styled in theme/measure, height added to the stack, placed under the passkey/QR buttons; controllers `fenixuzSetTakeBotToken` |
| `AuthUI/.../AuthController.swift` | `State.botTokenAvailable/botTokenError`; `bot_token_c`; `updateState` sets the link handlers and shows `bot_token_c` first when requested (`else if` keeps the upstream QR/phone flow); `loginWithBotToken`; `index(of:)` treats it like the QR screen; theme refresh |
| `AuthUI/.../AuthController.swift` `checkPasskeyAvailability` | `guard FenixuzLoginFeatures.passkeys` — 13.1 App Store builds auto-open the macOS passkey sheet on the first screen; passkeys for telegram.org cannot work for our app id (the old published app had no passkeys) |
| `SettingsUI/.../PrivacyAndSecurityViewController.swift` | Passkeys row also requires `FenixuzLoginFeatures.passkeys`; SettingsUI depends on FenixuzCore (`// Fenixuz` Package.swift lines) |

### Novagram logo in QR codes, NovagramProxy in Proxy Settings

| File | Change |
| --- | --- |
| `packages/FenixuzCore/.../FenixuzQrLogo.swift` (ours) | app icon cut to a circle with a transparent ring (same as iOS `FenixuzQrLogo`) |
| `AuthUI/.../Auth_Token.swift` | login QR centre `logoView` shows `FenixuzQrLogo` |
| `InviteLinksUI/.../InviteLinkQrController.swift` | centre `logoView` is an `NSImageView` with `FenixuzQrLogo` (was the airplane Lottie); exported QR image uses `.custom(FenixuzQrLogo)` instead of `login_qr_cap` |
| `QrStudioUI/.../QrStudioExportStickers.swift` | `qrStudioDecodeExportPlane` returns the Novagram logo (one frame) instead of the airplane animation; covers the live QR Studio view and its export |
| `ProxyUI/.../NovagramProxyEntries.swift` (ours), `ProxyListController.swift` | NovagramProxy switch + description at the top of Proxy Settings; the data signal also listens to `FenixuzAutoProxyManager.shared.uiState` |
| `AuthUI/.../AuthController.swift` | the "NovagramProxy" text link at the top of the login screen is removed (owner: it belongs in Proxy Settings). The login proxy icon still appears after 10 s without a connection (upstream), so blocked users reach Proxy Settings |

QrStudioUI, InviteLinksUI and ProxyUI depend on FenixuzCore (`// Fenixuz` Package.swift lines).

### Novagram ads v2, app side

| File | What |
| --- | --- |
| `packages/NovagramAdsBinary/` | NovagramAds SDK 3.0 binary package (NovagramAds, NovagramInsights, NovagramInsightsUI xcframeworks, macos-arm64_x86_64, min macOS 12.0, Swift 6.4). Update with `scripts/vendor-novagram-sdk.sh <sdk build dir>` |
| `Telegram-Mac/novagram/NovagramAdsCenter.swift` + `NovagramAdActions`, `NovagramAdMenu`, `NovagramAdMessage`, `NovagramBannerAds`, `NovagramChatAds`, `NovagramSearchAds`, `NovagramVideoAds` | Ads logic (our ad first, Telegram's only as fallback and never for Premium, nothing while "Remove all ads" is on; events to our backend only). `NovagramAdsCenter`, not `NovagramAds`: that is the SDK module name |
| `Telegram-Mac/novagram/NovagramAdsGate.swift`, `NovagramAdsAdminAuth.swift` | "Remove all ads" gate (`pro_messager` keys `fenix_show_ads`, `fenix_ads_section_revealed`), F08: 10 quick clicks on the Settings version row + admin login; the hidden section is back in Novagram Settings |
| `Telegram-Mac/novagram/NovagramInsightsEntry.swift` | F09 hidden "Ads Analytics" row (id 914; 20 quick clicks on "Novagram Settings" + admin login), opens the NovagramInsightsUI window. No GeneralRows hook (hub package): a click on another row no longer resets the count |
| `Telegram-Mac/packages-integration/hooks/NovagramAdsHooksInstall.swift` | installs every `NovagramAdsHooks` closure (from `installNovagramHooks()`); `openMediaIfOurs` returns early for non-ads |
| `scripts/novagram-ads-local-config.sh` | writes the git-ignored `Telegram-Mac/NovagramAds.local.xcconfig` (`NOVAGRAM_ADS_ENVIRONMENT`, default development) |
| `Telegram.xcodeproj/project.pbxproj` | `XCLocalSwiftPackageReference "packages/NovagramAdsBinary"` (`FE50AD500000000000000001`) in project `packageReferences`; products `…0002-0004` linked to the Telegram target only (build files `…0012-0014`); 12 Novagram sources (`…0020-0037`); Telegram target Debug + Release `MACOSX_DEPLOYMENT_TARGET = 14.0` (the SDK needs 12.0; 14.0 is the minimum the old Novagram shipped, and `scripts/xcode27.sh apply/revert` leaves it alone) |
| `Telegram-Mac/Info.plist` | `NovagramAdsEnvironment = $(NOVAGRAM_ADS_ENVIRONMENT)` |
| `Telegram-Mac/Novagram.xcconfig` | `NOVAGRAM_ADS_ENVIRONMENT = production`, `#include? "NovagramAds.local.xcconfig"`, `NOVAGRAM_ADS_ENVIRONMENT[config=Release] = production` |
