# TON Wallet (macOS) — security audit vs iOS

Date: 2026-10-07. Branch: beta. telegram-ios pin ff054f7a10 (581 commits **ahead** of public
`peter-iakovlev/new-wallet`, 0 behind — no newer public iOS wallet fixes to pull).

**Scope reality.** The hand-ported `packages/Wallet` is gone; the Mac links the shared
`WalletContext` / `WalletBackupCrypto` and the Rust `wallet-engine` directly from
`submodules/telegram-ios`. So "compare with iOS" = (a) macOS-conditional divergences that weaken
security, (b) genuine vulns in the surface the Mac exercises. The exact divergence set is the
`#if os(macOS)` / `#if os(iOS)` branches plus the Mac-only `packages/WalletUI` + `Telegram-Mac/`
wiring + entitlements.

Method: mechanical divergence scan + 3 read-only audit agents (secret leakage / auth gating /
deep-links+TonConnect); **every finding re-verified against current code.** Where a finding compares
to iOS, the comparison was verified from the shared code's `#else` branch or the iOS app layer;
where it was not, that is stated.

## Verified clean (no action)
- **Clipboard:** only the wallet address is ever copied; the phrase/mnemonic/private key/DEK is never put on NSPasteboard.
- **Logging:** the `log:` sink (`AccountContext.swift:580`) writes to the on-disk `Logger.shared` (exportable via Send Logs) but logs only event names, op-ids, addresses, hashes, counts — no secrets, no signed BOC (hashed only).
- **Authorization bypass:** none. Every reveal/sign path funnels through `WalletVault.access` → a validated `PasscodeSession` TaskLocal; the gate is **crypto-enforced**, not just UI. No WalletUI screen reaches a reveal/sign engine API directly (only read-only `getUserAddresses`/balance).
- **TonConnect:** approval sheet shows dApp origin + exact op (dest/amount/comment/BOC/fee); no auto-approve; close/decline correctly rejects; sessions bound to the manifest key that decrypted the request; return `.url` rejects file/data/javascript + embedded creds; signData shows text verbatim and a blind-sign warning for opaque payloads.
- **Deep links** (`ton://transfer`, gram t.me/tg): pre-fill a form only, never auto-send; amount>0 enforced; address/username charset validated; `.ton` names resolve via engine and the resolved address is shown before signing.
- **Biometrics fallback / session scope:** a cancelled/failed Touch ID never leaves an op authorized; sessions are namespace- and scope-bound (no cross-wallet/cross-purpose reuse).

## Findings (ordered: fixable bugs first, architecture last)

### F7 — Enabling wallet protection disables the app-wide idle auto-lock — HIGH, HIGH conf. One-line fix.
Setting a passcode via the wallet-protection entry forces `withUpdatedTimeout(nil)`
(`PasscodeControllers.swift:270`); the idle-lock pipeline maps nil → false
(`SharedNotificationManager.swift:225-227`), i.e. **no idle/resign auto-lock**. A user who turns on
protection *to secure the wallet* thereby turns OFF the app's idle auto-lock. Combined with F6
(`.ownerManaged` send/import/TonConnect sessions don't expire and survive backgrounding) and the 300 s
`.standard` sessions: "enable protection → open wallet → walk away" leaves a key-usable wallet session
with no idle lock to revoke it — the exact scenario a passcode exists to prevent (while the wallet UI
stays open). Whether decoupling the wallet passcode from app idle-lock was intended is a product
question; silently disabling an existing auto-lock is not defensible either way. Fix: don't force
`timeout(nil)` (use the app default / leave the user's choice).

### F1a — beta↔App Store signature change triggers a keychain-password prompt for existing wallet users — release-gate, HIGH conf.
Beta (Developer ID) and App Store builds share the *same unscoped* keychain names (only Debug is
scoped — `PasscodeKeychainScope.swift:5-9,43-48`). macOS login-keychain items are bound to the creating
code signature, so a user whose wallet items were created under one signature and who then runs a build
with a different signature (Developer ID direct ↔ App Store) hits the macOS keychain-password prompt
(observed 2026-10-02); `migrateLegacyItems` only covers the Debug scope, not this transition.
**Verify before shipping:** whether App Store and the Sparkle beta/stable channel actually share users
(if they are separate channels and users don't cross over, this is a switch-only migration-UX bug, not a
universal blocker). Either way it affects anyone who moves between build signatures with a live wallet.

### F3 — Secret phrase harvestable via the macOS Accessibility API — MEDIUM, HIGH conf. Local fix.
The words grid uses `TGUIKit.TextView` with `isSelectable=false`/`userInteractionEnabled=false`
(`WalletWordsGridRowItem.swift:131-141`) to block mouse-copy, but `TextView.accessibilityLabel()`
(`TextView.swift:3522`) still returns each word's full string, so VoiceOver or any
Accessibility-permitted process can read every word from the AX tree with no screenshot. `TextView` is
`open` (`TextView.swift:2384`), so the fix is local: a `WalletSecretWordView: TextView` overriding
`accessibilityLabel()->nil` / `isAccessibilityElement=false` — NOT a change in the TGUIKit hub (app-wide
AX change, ~90-pkg recompile). **Trade-off:** blocking AX outright breaks legitimate VoiceOver use;
prefer a secure-text treatment or an explicit "read aloud" affordance rather than silently hiding it.

### F1b — Wallet secrets in the macOS login keychain, not the Data Protection keychain — MEDIUM, HIGH conf. (shared telegram-ios; needs sam + full review)
`WalletVault.keychainAccessGroup()` returns nil on macOS (`WalletSecurity.swift:70`); all wallet items
are stored via `PasscodeKeychainScope` with `kSecUseDataProtectionKeychain:false` +
`WhenUnlockedThisDeviceOnly` + **no access group** (`WalletStorage.swift:121`,
`PasscodeKeychainScope.swift:204/210`). The app is not sandboxed (`Telegram-Mac.entitlements`). iOS uses
the DP keychain + app-group access group (+ biometry ACL) — verified from the `#else` branches
(`WalletSecurity.swift:73`, `Passcode.swift:172-173`) — which has no cross-app "prompt and allow"
escape hatch. With no wallet passcode (default), the wrapping key (`record.unprotectedKey`) sits in the
same login keychain as the ciphertext (`Passcode.swift:535`).
**Rate against the app's OWN baseline, not just iOS:** Telegram-Mac's account/DB secrets
(`AppEncryptionParameters`, `BuildConfig.m` — note the tempkey ACL at `BuildConfig.m:319`) set the real
threat floor. If the account auth keys / Postbox key share the login-keychain/FileVault model, an
attacker who can read the login keychain already owns the account, so hardening only the wallet keychain
buys little without hardening the account secrets too. Decide the keychain story for the App Store
rollout (DP keychain + app-group + migration, which also fixes F1a) or consciously accept the login
model. (This baseline comparison is partially traced — confirm the auth-key storage before committing.)

### F5 — Protection-off default: only the login session gates send/reveal/TonConnect — MEDIUM, product decision.
With no wallet passcode, `authorize()` returns nil and ops run with `unprotectedSession`
(`WalletSecurity.swift:284-287`); the wallet passcode is opt-in (= the shared Telegram app passcode).
With no Telegram passcode at all, the only boundary on a send/reveal is the macOS login session.
Whether iOS effectively *mandates* a wallet passcode was **not confirmed** in this pass — treat as a
product decision (should a passcode be required to enable the wallet?), not an asserted iOS gap.

### F2 — Removing one of several accounts does not wipe that account's wallet secret — MEDIUM, HIGH conf. (BOTH platforms)
The namespace is per-account (`telegram.<env>.<peerId>`, `AccountContext.swift:575`), but
`resetWalletLocalSecrets()` wipes **all** wallet items at once and fires only on fresh-install,
logout-all, missing-credential (`AccountManagerSetup.swift:59-67`, `SharedNotificationManager.swift:255`).
iOS wires the same function into the account-manager reset closure (`AppDelegate.swift:1054`), **not** a
per-account wipe — so this is shared behavior, not a Mac regression. A removed account's secret phrase
persists in the keychain until a full logout. Worth a targeted per-namespace wipe on single-account
removal (ideally upstream so both platforms benefit).

### F6 — Lock-on-background weaker than on iOS — LOW, HIGH conf.
`applicationIsVisible()` (`AccountContext.swift:453-478`) flips only on hidden/miniaturized, not on
resign-active (app switch) or macOS screen lock. Backgrounding revokes `.standard` sessions but not
`.ownerManaged`. Structurally weaker than iOS, where DP-keychain items become inaccessible on device
lock; the macOS login keychain stays unlocked for the whole login session. Not interactively
exploitable alone (signing needs a foreground modal behind the lock screen), but see F7 for the
compounding effect.

### F8 — Connected Apps opens a dApp-controlled `manifest.url` with no scheme allowlist — LOW, HIGH conf.
`WalletConnectedAppsController.swift:382-385` opens `manifest.url` via `openExternalURL` → generic
sanitizer → `NSWorkspace.open`. Scheme-less strings get `http://` prepended (so `javascript:` is
neutralized), but `scheme://host`-form URLs (`file://`, custom schemes) pass through. Needs an approved
connection + user tap. Fix: https allowlist before opening.

### F9 — `LockNotificationsData.==` typo — LOW, latent/masked, HIGH conf.
`SharedNotificationManager.swift:54` compares `lhs.passcodeLock == rhs.screenLock` (should be
`rhs.passcodeLock`). Currently harmless (the broken Equatable isn't consulted on the live path), but a
real correctness bug; fix before any `distinctUntilChanged`/`ignoreRepeated` is placed on the struct.

### F4 — New/replacement-phrase modal not auto-dismissed on hide/lock — LOW, HIGH conf.
`WalletBackupDisableWordsController` doesn't wire `dismissOnBackgroundOrLock`, unlike Settings "Show
Secret Phrase" (`WalletSettingsController.swift:651/665`); a freshly generated phrase stays on screen
across Cmd+H / lock.

## Out of scope / shared with iOS (not a Mac parity gap)
Rust engine crypto — signData domain-separation prefix, TonConnect session key isolation/replay — is in
`wallet-engine`, identical on iOS, not verifiable from Swift. Optional upstream review, not a release gate.

## Recommended before release
1. **F7** (one line) and **F3** (small local WalletUI fix) — real, cheap, ship them.
2. **F1a** — confirm the App Store/beta channel overlap, then decide the keychain migration story (DP keychain + app-group + migration fixes F1a and F1b together; needs sam + full review per the shared-code rule).
3. **F5 / F1b** — product decision: require a wallet passcode? move to the DP keychain? assess vs the app's own account-secret baseline.
4. **F2, F6, F8, F9** — low-cost hardening/correctness; F2 ideally upstream.
