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
