//
//  NovagramAdsAdminAuth.swift
//  Telegram-Mac
//
//  Admin check for the hidden "Remove all ads" row. The 10-click gesture used to reveal the ads toggle
//  to anyone. Ads are now shown to every user (Telegram Premium included), so only an admin may reveal
//  it: after the 10 clicks the app asks for the admin login + password and reveals the row only when
//  they match. Hiding the row again needs no password.
//
//  Only a PBKDF2-HMAC-SHA256 digest of "<login>|<password>" (random salt, 600k rounds) ships in the
//  binary, never the credentials. The rounds make an offline guess from the binary expensive; the UI
//  also throttles: 5 wrong tries lock the prompt for 5 minutes. The typed values are never stored.
//
//  Port of iOS submodules/Novagram/ProMessager/Sources/NovagramAdsAdminAuth.swift — same salt, rounds and
//  digests, so one admin credential works on both apps. Same UserDefaults keys (pro_messager suite).
//
//  Each login has its own digest and role (NovagramDeveloperRole): the developer's and the director's.
//

import Cocoa
import CommonCrypto
import TGUIKit
import NovagramCore

enum NovagramAdsAdminAuth {
    private static let saltHex = "6ced8c7f8279470c768f8739196a445b"
    private static let rounds: UInt32 = 600_000
    private static let credentials: [(digest: String, role: NovagramDeveloperRole)] = [
        ("bf0445f7b4c37604336598ba977f8065c2e90da61c1bbd933d64d018077203eb", .developer),
        ("17ca3795cd21c510e781c68eec2df12e1038f8e599cc80751f626a736d7d6fca", .director)
    ]
    private static let derivedKeyLength = 32

    private static let maxFailedAttempts = 5
    private static let lockoutDuration: TimeInterval = 5 * 60
    private static let secondsPerMinute: Double = 60
    private static let fieldWidth: CGFloat = 260
    private static let fieldHeight: CGFloat = 24
    private static let fieldSpacing: CGFloat = 8

    private static let udSuite = "pro_messager"
    private static let failedAttemptsKey = "fenix_ads_admin_failed_attempts"
    private static let lockedUntilKey = "fenix_ads_admin_locked_until"
    private static let legacyMigrationKey = "fenix_ads_admin_migrated_v1"
    private static let sectionRevealedKey = "fenix_ads_section_revealed"
    private static let showAdsKey = "fenix_show_ads"

    // MARK: - Verification

    /// The role whose login (case-insensitive, trimmed) and exact password match, or nil.
    /// Slow on purpose (600k PBKDF2 rounds) — call it off the main thread.
    static func verify(login: String, password: String) -> NovagramDeveloperRole? {
        let normalizedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let digest = derive(secret: "\(normalizedLogin)|\(password)") else {
            return nil
        }
        var matched: NovagramDeveloperRole?
        for credential in credentials where constantTimeEquals(digest, credential.digest) {
            matched = credential.role
        }
        return matched
    }

    private static func derive(secret: String) -> String? {
        let salt = hexBytes(saltHex)
        var derived = [UInt8](repeating: 0, count: derivedKeyLength)
        // The String bridges to the C `const char *` password parameter (UTF-8).
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            secret, secret.utf8.count,
            salt, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            rounds,
            &derived, derived.count
        )
        guard Int(status) == kCCSuccess else {
            return nil
        }
        return derived.map { String(format: "%02x", $0) }.joined()
    }

    private static func hexBytes(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex, let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
            if let byte = UInt8(hex[index ..< next], radix: 16) {
                bytes.append(byte)
            }
            index = next
        }
        return bytes
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else {
            return false
        }
        var difference: UInt8 = 0
        for index in 0 ..< lhsBytes.count {
            difference |= lhsBytes[index] ^ rhsBytes[index]
        }
        return difference == 0
    }

    // MARK: - Throttling

    /// When the prompt unlocks again, or nil if it is not locked.
    static var lockedUntil: Date? {
        guard let timestamp = UserDefaults(suiteName: udSuite)?.object(forKey: lockedUntilKey) as? Double else {
            return nil
        }
        let date = Date(timeIntervalSince1970: timestamp)
        return date > Date() ? date : nil
    }

    private static func registerFailure() {
        let defaults = UserDefaults(suiteName: udSuite)
        let failures = (defaults?.integer(forKey: failedAttemptsKey) ?? 0) + 1
        if failures >= maxFailedAttempts {
            defaults?.set(Date().addingTimeInterval(lockoutDuration).timeIntervalSince1970, forKey: lockedUntilKey)
            defaults?.set(0, forKey: failedAttemptsKey)
        } else {
            defaults?.set(failures, forKey: failedAttemptsKey)
        }
    }

    private static func registerSuccess() {
        let defaults = UserDefaults(suiteName: udSuite)
        defaults?.removeObject(forKey: failedAttemptsKey)
        defaults?.removeObject(forKey: lockedUntilKey)
    }

    // MARK: - Legacy state

    /// Before the admin check, anyone could reveal the row and switch ads off with the old 10-click egg.
    /// Run once: hide a row revealed that way and switch ads back on, so only an admin can hide ads now.
    static func migrateLegacyRevealIfNeeded() {
        guard let defaults = UserDefaults(suiteName: udSuite), !defaults.bool(forKey: legacyMigrationKey) else {
            return
        }
        defaults.set(true, forKey: legacyMigrationKey)
        let wasRevealed = defaults.object(forKey: sectionRevealedKey) as? Bool ?? false
        let adsWereOff = (defaults.object(forKey: showAdsKey) as? Bool) == false
        guard wasRevealed || adsWereOff else {
            return
        }
        defaults.set(false, forKey: sectionRevealedKey)
        defaults.set(true, forKey: showAdsKey)
    }

    // MARK: - Prompt

    /// Asks for the admin login + password. `completion(role)` only on a match; cancel, a wrong entry and
    /// an active lockout all end in `completion(nil)` (after explaining why). Main thread.
    static func presentPrompt(window: Window, completion: @escaping (NovagramDeveloperRole?) -> Void) {
        let strings = NovagramL10n.current
        if let lockedUntil {
            let minutes = max(1, Int((lockedUntil.timeIntervalSinceNow / secondsPerMinute).rounded(.up)))
            alert(for: window, info: strings.ads_admin_locked(minutes: minutes))
            completion(nil)
            return
        }

        let loginField = NSTextField(frame: NSRect(x: 0, y: fieldHeight + fieldSpacing, width: fieldWidth, height: fieldHeight))
        loginField.placeholderString = strings.ads_admin_login
        loginField.isAutomaticTextCompletionEnabled = false
        loginField.contentType = .username
        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: fieldWidth, height: fieldHeight))
        passwordField.placeholderString = strings.ads_admin_password
        passwordField.contentType = .password
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: fieldWidth, height: fieldHeight * 2 + fieldSpacing))
        fields.addSubview(loginField)
        fields.addSubview(passwordField)

        let prompt = NSAlert()
        prompt.messageText = strings.ads_admin_title
        prompt.informativeText = strings.ads_admin_message
        prompt.accessoryView = fields
        prompt.addButton(withTitle: strings.ads_admin_confirm)
        let cancel = prompt.addButton(withTitle: strings.ads_admin_cancel)
        cancel.keyEquivalent = "\u{1b}"
        prompt.window.initialFirstResponder = loginField
        // Return in the login field moves to the password field instead of submitting.
        loginField.nextKeyView = passwordField

        prompt.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                completion(nil)
                return
            }
            let login = loginField.stringValue
            let password = passwordField.stringValue
            passwordField.stringValue = ""
            // The key derivation is deliberately slow; keep it off the main thread.
            Task.detached(priority: .userInitiated) {
                let role = verify(login: login, password: password)
                await MainActor.run {
                    if let role {
                        registerSuccess()
                        completion(role)
                    } else {
                        registerFailure()
                        let text = lockedUntil != nil ? strings.ads_admin_locked(minutes: Int(lockoutDuration / secondsPerMinute)) : strings.ads_admin_wrong
                        alert(for: window, info: text)
                        completion(nil)
                    }
                }
            }
        }
    }
}
