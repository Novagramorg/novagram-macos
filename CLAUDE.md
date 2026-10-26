@AGENTS.md

# Novagram (fork of Telegram macOS 13.1)

Brand **Novagram**, internal codename **Fenixuz**. Team **Vipads MCHJ**, Team ID `ZDBP5RSRZF`, bundle id `uz.fenixuz.app` (share extension `uz.fenixuz.app.TelegramShare`), App Store app `id6768202244`. The old fork (Telegram macOS 12.x base) is `../macOS`; the port plan is `../PORT_MAP_macOS13.md`. The iOS app is `../Telegram-iOS`.

## Rules

- Never put "Telegram" in the App Store name, subtitle or keywords (rejected under 4.1 Copycats twice). In-app the product is "Novagram"; strings are rebranded at runtime by `FenixuzBranding.rebrand`.
- Novagram code lives in our own files: `packages/FenixuzCore` (products `FenixuzCore` and the light `FenixuzShare` for the share extension), `Telegram-Mac/novagram/`, `Telegram-Mac/packages-integration/hooks/Novagram*HooksInstall.swift`, and `Fenixuz*.swift` / `Novagram*.swift` files inside Telegram packages. Telegram files get short call sites only.
- Every line we change in a Telegram file ends with `// Fenixuz`, and every change is listed in `FENIXUZ_HOOKS.md` in the same commit. Exact line edits only; never run a formatter over a Telegram file.
- Packages that FenixuzCore depends on (AlertsUI, GeneralRows, InputDataUI, InAppSettings, TelegramUtils, AvatarUI, ...) must never import FenixuzCore (dependency cycle).
- `APP_STORE` is false inside packages in Xcode builds. App Store archives must pass `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) APP_STORE'` on the xcodebuild command line (`fenix-publish.sh` does).
- `scripts/xcode27.sh apply` changes (deployment target 12.0, Metal, ImplicitStrongCapture) stay local: `scripts/xcode27.sh revert` before staging those files, `apply` after.
- TelegramCore fork changes live in `fork-patches/` (new files + `telegramcore-hooks.patch`); `git submodule update` deletes them, re-run `./fork-patches/apply-telegramcore-patches.sh`.
- Shared settings use the `pro_messager` UserDefaults suite with the same keys as iOS.
- Commits: short, lowercase, first person, English ("added …", "fixed …"). Never push to `upstream`.

## Build

- `./fenix-build.sh` (Debug, real pass/fail, DerivedData `/tmp/tgmac13-dd`), `./fenix-build.sh run` launches, `./fenix-build.sh appstore` also sets `APP_STORE` in packages.
- Fresh clone: `git submodule update --init --recursive`, `scripts/xcode27.sh apply`, `./fork-patches/apply-telegramcore-patches.sh`, `sh scripts/configure_frameworks.sh`, then `./fenix-build.sh`.
