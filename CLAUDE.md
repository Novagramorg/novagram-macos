@AGENTS.md

# Novagram (fork of Telegram macOS 13.1)

Brand **Novagram** (formerly Fenixuz: all code is named Novagram now; persisted keys such as `pro_messager`, `fenix_show_ads`, `__fenix_master__` and every Apple identifier keep their old values). Team **Vipads MCHJ**, Team ID `ZDBP5RSRZF`, bundle id `uz.fenixuz.app` (share extension `uz.fenixuz.app.TelegramShare`), App Store app `id6768202244`. This repo is `~/Documents/Telegram/macOS` (it was `macOS-13` until 2026-10-27). The old fork (Telegram macOS 12.x base) was removed on 2026-10-27; its full history is in `~/Documents/Novagram-backups/macOS-old-fork-2026-10-27.bundle` (`git clone <bundle>` to read it); the port plan is `../PORT_MAP_macOS13.md`. The iOS app is `../Telegram-iOS`.

## Rules

- Never put "Telegram" in the App Store name, subtitle or keywords (rejected under 4.1 Copycats twice). In-app the product is "Novagram"; strings are rebranded at runtime by `NovagramBranding.rebrand`.
- Novagram code lives in our own files: `packages/NovagramCore` (products `NovagramCore` and the light `NovagramShare` for the share extension), `Telegram-Mac/novagram/`, `Telegram-Mac/packages-integration/hooks/Novagram*HooksInstall.swift`, and `Novagram*.swift` files inside Telegram packages. Telegram files get short call sites only.
- Every line we change in a Telegram file ends with `// Novagram`, and every change is listed in `NOVAGRAM_HOOKS.md` in the same commit. Exact line edits only; never run a formatter over a Telegram file.
- Thin hooks: a Telegram file gets an import and a 1–3 line call, the logic lives in NovagramCore or `Telegram-Mac/novagram/`. Thin an existing fat hook when you work on it anyway; never reformat the lines around a hook.
- Auto-lint (swiftlint --fix after Edit/Write) only touches the files in `.claude/auto-lint-only` (local, gitignored: recreate it on a new machine from `NOVAGRAM_HOOKS.md`, "Easy upstream merges").
- Packages that NovagramCore depends on (AlertsUI, GeneralRows, InputDataUI, InAppSettings, TelegramUtils, AvatarUI, ...) must never import NovagramCore (dependency cycle).
- `APP_STORE` is false inside packages in Xcode builds. App Store archives must pass `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) APP_STORE'` on the xcodebuild command line (`novagram-publish.sh` does).
- `scripts/xcode27.sh apply` changes (deployment target 12.0, Metal, ImplicitStrongCapture) stay local: `scripts/xcode27.sh revert` before staging those files, `apply` after.
- `scripts/novagram-local.sh hide` keeps the local-only changes out of `git status` (Xcode 27 changes, `.claude/settings.local.json`, submodule work trees); a file with any other change stays visible. To stage one of those files: `scripts/novagram-local.sh show && scripts/xcode27.sh revert`, `git add`, then `scripts/xcode27.sh apply && scripts/novagram-local.sh hide`. The pre-commit hook it installs stops a commit while a hidden file has other changes.
- TelegramCore fork changes live in `fork-patches/` (new files + `telegramcore-hooks.patch`); `git submodule update` deletes them, re-run `./fork-patches/apply-telegramcore-patches.sh`.
- Shared settings use the `pro_messager` UserDefaults suite with the same keys as iOS.
- Commits: short, lowercase, first person, English ("added …", "fixed …"). Never push to `upstream`.
- Branches: only `main` exists, locally and on GitHub. Every task: a new branch from `main`, work, build and test, then merge into `main`, push `main` and delete the branch.

## iOS features

- `docs/IOS_FEATURES_AND_HOOKS.md`: every Novagram iOS feature and iOS hook (a copy of the iOS repo's list, taken from the old fork on 2026-10-27). Read it before porting an iOS feature; iOS code is in `../Telegram-iOS/submodules/Fenixuz/<Module>/Sources/`.

## Upstream updates

- `scripts/novagram-upstream-update.sh` merges the latest `upstream/master` on a new `feature/upstream-<date>` branch: reverts the local Xcode 27 changes, merges, updates moved submodules, re-applies the TelegramCore patches, checks that no `// Novagram` hook was lost, builds. `--check` only reports what upstream has; `--finish` continues after conflicts were resolved by hand. Never merge upstream on `main` by hand. Run it often (weekly): small merges rarely conflict. A launchd job (`uz.novagram.upstream-weekly`, Mondays 10:00) only trial-merges and reports in a macOS notification and `~/Library/Logs/novagram-upstream-weekly.log`.

## Build

- `./novagram-build.sh` (Debug, real pass/fail, DerivedData `/tmp/tgmac13-dd`), `./novagram-build.sh run` launches, `./novagram-build.sh appstore` also sets `APP_STORE` in packages.
- App Store release: `NOVAGRAM_VERSION=<the iOS version> ./novagram-publish.sh` archives with `APP_STORE`, checks the archive and exports `build/export/<name>/Novagram.pkg` for Transporter (uploads nothing). The Mac version follows iOS 1:1 and is set only on the command line, never in `project.pbxproj`.
- Fresh clone: `git submodule update --init --recursive`, `scripts/xcode27.sh apply`, `./fork-patches/apply-telegramcore-patches.sh`, `sh scripts/configure_frameworks.sh`, `scripts/novagram-local.sh hide`, then `./novagram-build.sh`.
