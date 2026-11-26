import XCTest
import LocalAuthentication
@testable import PasscodeCore
import WalletContext

private func repositoryRoot() -> URL {
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private func source(_ path: String) throws -> String {
    return try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
}

private func block(from start: String, to end: String, in source: String) throws -> String {
    let startRange = try XCTUnwrap(source.range(of: start), start)
    let endRange = try XCTUnwrap(source.range(of: end, range: startRange.upperBound ..< source.endIndex), end)
    return String(source[startRange.lowerBound ..< endRange.upperBound])
}

private func normalized(_ text: String) -> String {
    return text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private final class MemoryPasscodeStorage: PasscodeStorage {
    private var items: [String: Data] = [:]

    func read(_ account: String, context: LAContext?) throws -> Data? {
        return self.items[account]
    }

    func write(_ data: Data, account: String, biometric: Bool) throws {
        self.items[account] = data
    }

    func remove(_ account: String) throws {
        self.items[account] = nil
    }
}

private enum PasscodeStartingState: CaseIterable {
    case noCredential
    case walletWithoutPasscode
    case passcodeRemoved
}

private struct PasscodeSetupOutcome: Equatable {
    let kind: PasscodeKind?
    let enabled: Bool
    let biometricsEnabled: Bool
    let managed: Bool
    let walletUnlocked: Bool
    let keptWalletKey: Bool?
}

private let walletNamespace = "wallet"
private let removedCode = "2468"
private let newCode = "135790"
private let changedCode = "975310"

@available(macOS 10.15, *)
private func makeStore(_ state: PasscodeStartingState) throws -> (store: PasscodeCredentialStore, walletKey: Data?) {
    let store = PasscodeCredentialStore(storage: MemoryPasscodeStorage(), iterations: { PasscodeCrypto.minimumIterations })
    switch state {
    case .noCredential:
        return (store, nil)
    case .walletWithoutPasscode:
        return (store, try store.unprotectedSession(namespace: walletNamespace).withKey { $0 })
    case .passcodeRemoved:
        _ = try store.setPasscode(removedCode, kind: .digits4, session: nil)
        try store.disablePasscode(session: try store.verify(removedCode, scope: .settings))
        return (store, try store.unprotectedSession(namespace: walletNamespace).withKey { $0 })
    }
}

@available(macOS 10.15, *)
private func outcome(_ store: PasscodeCredentialStore, code: String, walletKey: Data?) throws -> PasscodeSetupOutcome {
    let settings = try store.protectionSettings()
    let managed: Bool
    if case .some = try store.managedReference() {
        managed = true
    } else {
        managed = false
    }
    let walletUnlocked = (try? store.unprotectedSession(namespace: walletNamespace)) != nil
    let keptWalletKey = try walletKey.map { key in
        try store.verify(code, scope: .resource(namespace: walletNamespace)).withKey { $0 } == key
    }
    return PasscodeSetupOutcome(kind: settings.passcode?.kind, enabled: settings.enabled, biometricsEnabled: settings.biometricsEnabled, managed: managed, walletUnlocked: walletUnlocked, keptWalletKey: keptWalletKey)
}

@available(macOS 10.15, *)
private func submoduleSetUpPasscode(_ code: String, numerical: Bool, store: PasscodeCredentialStore, authorizationSession: PasscodeSession?) throws {
    let kind: PasscodeKind = numerical ? (code.count == 6 ? .digits6 : .digits4) : .alphanumeric
    let result = try store.setPasscodeWithSettingsSession(code, kind: kind, session: authorizationSession)
    result.session.invalidate()
}

@available(macOS 10.15, *)
private func submoduleMigrateLegacyNumericalPasscode(_ code: String, store: PasscodeCredentialStore) throws {
    let kind: PasscodeKind = code.count == 6 ? .digits6 : .digits4
    _ = try store.migrateLegacy(code: code, kind: kind)
}

private func actualPasscodeCredentialKind(for code: String) -> PasscodeKind {
    let normalized = PasscodeKind.digits4.normalize(code)
    if normalized.allSatisfy({ $0.isASCII && $0.isNumber }) {
        if normalized.count == 4 {
            return .digits4
        }
        if normalized.count == 6 {
            return .digits6
        }
    }
    return .alphanumeric
}

@available(macOS 10.15, *)
private func actualAdoptPasscodeCredential(code: String, isNewPasscode: Bool = false, store: PasscodeCredentialStore) throws {
    switch try store.managedReference() {
    case .none where !isNewPasscode:
        _ = try store.migrateLegacy(code: code, kind: actualPasscodeCredentialKind(for: code))
    case .none, .some(.none):
        _ = try store.setPasscode(code, kind: actualPasscodeCredentialKind(for: code), session: nil)
    case .some(.some):
        break
    }
}

@available(macOS 10.15, *)
private func actualInstallPasscode(_ code: String, store: PasscodeCredentialStore) throws {
    try actualAdoptPasscodeCredential(code: code, isNewPasscode: true, store: store)
}

@available(macOS 10.15, *)
private func actualChangePasscode(current: String, to code: String, store: PasscodeCredentialStore) throws {
    let session = try store.verify(current, scope: .settings)
    defer {
        session.invalidate()
    }
    _ = try store.setPasscode(code, kind: actualPasscodeCredentialKind(for: code), session: session)
}

@available(macOS 10.15, *)
final class WalletPasscodeSetupSubmoduleCompatibilityTests: XCTestCase {
    private let hooksPath = "Telegram-Mac/packages-integration/hooks/PasscodeUIHooksInstall.swift"
    private let storePath = "submodules/telegram-ios/submodules/PasscodeCore/Sources/Passcode.swift"
    private let setupPath = "submodules/telegram-ios/submodules/PasscodeUI/Sources/PasscodeSetupController.swift"
    private let optionsPath = "submodules/telegram-ios/submodules/SettingsUI/Sources/Privacy and Security/PasscodeOptionsController.swift"
    private let legacyPath = "submodules/telegram-ios/submodules/PasscodeCore/Sources/AccountManagerIntegration.swift"

    override func setUp() {
        super.setUp()
        PasscodeSession.setApplicationAvailable(true)
    }

    override func tearDown() {
        PasscodeSession.setApplicationAvailable(false)
        super.tearDown()
    }

    func testSubmoduleFirstPasscodeTurnsOnTheWalletLock() throws {
        let store = try source(storePath)
        let update = normalized(try block(from: "private func updatePasscode(", to: "record.managedPasscode = true", in: store))
        XCTAssertTrue(update.contains("let isInitialSetup = record.kind == nil"))
        XCTAssertTrue(update.contains("try self.wrap(code: code, kind: kind, key: key, record: &record) if isInitialSetup { record.protectionEnabled = true record.unprotectedKey = nil } record.managedPasscode = true"))

        let options = normalized(try source(optionsPath))
        XCTAssertTrue(options.contains("if current.passcode == nil { pushControllerImpl?(applicationPasscodeSetupController(context: context, session: nil, change: false, settingsSessionCompleted:"))

        let setup = normalized(try source(setupPath))
        XCTAssertTrue(setup.contains("let kind: PasscodeKind = numerical ? (code.count == 6 ? .digits6 : .digits4) : .alphanumeric if settingsSessionCompleted != nil { let result = try PasscodeCredentialStore.shared.setPasscodeWithSettingsSession(code, kind: kind, session: authorizationSession)"))

        let legacy = normalized(try source(legacyPath))
        XCTAssertTrue(legacy.contains("case let .numericalPassword(code): let kind: PasscodeKind = code.count == 6 ? .digits6 : .digits4 let reference = try credentials.migrateLegacy(code: code, kind: kind)"))
    }

    func testAppHooksUseTheCopiedRules() throws {
        let hooks = try source(hooksPath)
        XCTAssertEqual(normalized(try block(from: "func passcodeCredentialKind(for code: String) -> PasscodeKind {", to: "return .alphanumeric\n}", in: hooks)), "func passcodeCredentialKind(for code: String) -> PasscodeKind { let normalized = PasscodeKind.digits4.normalize(code) if normalized.allSatisfy({ $0.isASCII && $0.isNumber }) { if normalized.count == 4 { return .digits4 } if normalized.count == 6 { return .digits6 } } return .alphanumeric }")
        XCTAssertEqual(normalized(try block(from: "func adoptPasscodeCredential(", to: "UserDefaults.standard.set(true, forKey: walletPasscodeCredentialManagedKey)\n}", in: hooks)), "func adoptPasscodeCredential(code: String, isNewPasscode: Bool = false) throws { let store = PasscodeCredentialStore.shared switch try store.managedReference() { case .none where !isNewPasscode: _ = try store.migrateLegacy(code: code, kind: passcodeCredentialKind(for: code)) case .none, .some(.none): _ = try store.setPasscode(code, kind: passcodeCredentialKind(for: code), session: nil) case .some(.some): break } UserDefaults.standard.set(true, forKey: walletPasscodeCredentialManagedKey) }")

        let installed = normalized(try block(from: "hooks.passcodeInstalled = {", to: "hooks.passcodeChanged = {", in: hooks))
        XCTAssertTrue(installed.contains("passcodeCredentialOperation(completion) { try adoptPasscodeCredential(code: code, isNewPasscode: true) }"))
        XCTAssertEqual(hooks.components(separatedBy: "isNewPasscode: true").count - 1, 1)

        let synced = normalized(try block(from: "func syncPasscodeCredential(code: String, rootPath: String) {", to: "\n}\n", in: hooks))
        XCTAssertTrue(synced.hasSuffix("try? adoptPasscodeCredential(code: code) }"))

        let changed = normalized(try block(from: "hooks.passcodeChanged = {", to: "hooks.passcodeDisabled = {", in: hooks))
        XCTAssertTrue(changed.contains("_ = try PasscodeCredentialStore.shared.setPasscode(code, kind: passcodeCredentialKind(for: code), session: session)"))
    }

    func testNewPasscodeLocksTheWalletLikeTheSubmodule() throws {
        for state in PasscodeStartingState.allCases {
            let submodule = try makeStore(state)
            try submoduleSetUpPasscode(newCode, numerical: true, store: submodule.store, authorizationSession: nil)
            let expected = try outcome(submodule.store, code: newCode, walletKey: submodule.walletKey)

            let actual = try makeStore(state)
            try actualInstallPasscode(newCode, store: actual.store)
            let result = try outcome(actual.store, code: newCode, walletKey: actual.walletKey)

            XCTAssertEqual(result, expected, "\(state)")
            XCTAssertEqual(result.kind, .digits6, "\(state)")
            XCTAssertTrue(result.enabled, "\(state)")
            XCTAssertFalse(result.biometricsEnabled, "\(state)")
            XCTAssertTrue(result.managed, "\(state)")
            XCTAssertFalse(result.walletUnlocked, "\(state)")
            XCTAssertEqual(result.keptWalletKey, state == .noCredential ? nil : true, "\(state)")
        }
    }

    func testCarryingOverAnOldPasscodeKeepsTheWalletUnlockedLikeTheSubmodule() throws {
        let code = "1357"
        for state in [PasscodeStartingState.noCredential, .walletWithoutPasscode] {
            let submodule = try makeStore(state)
            try submoduleMigrateLegacyNumericalPasscode(code, store: submodule.store)
            let expected = try outcome(submodule.store, code: code, walletKey: submodule.walletKey)

            let actual = try makeStore(state)
            try actualAdoptPasscodeCredential(code: code, store: actual.store)
            let result = try outcome(actual.store, code: code, walletKey: actual.walletKey)

            XCTAssertEqual(result, expected, "\(state)")
            XCTAssertEqual(result.kind, .digits4, "\(state)")
            XCTAssertFalse(result.enabled, "\(state)")
            XCTAssertTrue(result.walletUnlocked, "\(state)")
        }
    }

    func testChangingThePasscodeKeepsTheWalletLockLikeTheSubmodule() throws {
        for lockEnabled in [true, false] {
            let submodule = try makeStore(.walletWithoutPasscode)
            try submoduleSetUpPasscode(newCode, numerical: true, store: submodule.store, authorizationSession: nil)
            if !lockEnabled {
                try setWalletProtectionEnabled(false, session: try submodule.store.verify(newCode, scope: .settings), credentials: submodule.store)
            }
            try submoduleSetUpPasscode(changedCode, numerical: true, store: submodule.store, authorizationSession: try submodule.store.verify(newCode, scope: .settings))
            let expected = try outcome(submodule.store, code: changedCode, walletKey: submodule.walletKey)

            let actual = try makeStore(.walletWithoutPasscode)
            try actualInstallPasscode(newCode, store: actual.store)
            if !lockEnabled {
                try setWalletProtectionEnabled(false, session: try actual.store.verify(newCode, scope: .settings), credentials: actual.store)
            }
            try actualChangePasscode(current: newCode, to: changedCode, store: actual.store)
            let result = try outcome(actual.store, code: changedCode, walletKey: actual.walletKey)

            XCTAssertEqual(result, expected, "lock \(lockEnabled)")
            XCTAssertEqual(result.enabled, lockEnabled)
            XCTAssertEqual(result.keptWalletKey, true)
        }
    }

    func testWalletSetupStillEndsLocked() throws {
        let actual = try makeStore(.walletWithoutPasscode)
        try actualInstallPasscode(newCode, store: actual.store)
        try setWalletProtectionEnabled(true, session: try actual.store.verify(newCode, scope: .settings), credentials: actual.store)
        let result = try outcome(actual.store, code: newCode, walletKey: actual.walletKey)
        XCTAssertTrue(result.enabled)
        XCTAssertFalse(result.walletUnlocked)
        XCTAssertEqual(result.keptWalletKey, true)
    }
}
