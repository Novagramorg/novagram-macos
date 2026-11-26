import Foundation
import TelegramCore
import PasscodeCore
import BuildConfig
#if !SHARE
import WalletContext
#endif

let unscopedWalletPasscodeCredentialManagedKey = "wallet.passcodeCredentialManaged"

var walletPasscodeCredentialManagedKey: String {
    if let scope = PasscodeEnvironment.shared.keychainScope {
        return unscopedWalletPasscodeCredentialManagedKey + "." + scope
    }
    return unscopedWalletPasscodeCredentialManagedKey
}

#if !SHARE
@available(macOS 10.15, *)
private func migrateWalletKeychainScopeIfNeeded(basePath: String, isFreshInstallation: Bool) {
    guard PasscodeEnvironment.shared.keychainScope != nil else {
        return
    }
    let marker = ((basePath as NSString).deletingLastPathComponent as NSString).appendingPathComponent("keychain-scope-v1")
    if FileManager.default.fileExists(atPath: marker) {
        return
    }
    if !isFreshInstallation {
        let migration = migrateWalletKeychainScope()
        Logger.shared.log("KeychainScope", "migration: \(migration)")
        switch migration {
        case .keychainLocked, .failed:
            PasscodeCredentialStore.shared.requireExistingCredential()
            return
        case .migrated:
            if UserDefaults.standard.bool(forKey: unscopedWalletPasscodeCredentialManagedKey) {
                UserDefaults.standard.set(true, forKey: walletPasscodeCredentialManagedKey)
            }
        case .nothingToMigrate:
            break
        }
    }
    FileManager.default.createFile(atPath: marker, contents: Data())
}
#endif

func makeAccountManagerAccessChallenge(basePath: String, isTemporary: Bool, isReadOnly: Bool) -> AccountManagerAccessChallenge {
    let isMainProcess = PasscodeEnvironment.shared.isMainApp
    return AccountManagerAccessChallenge(prepare: { isFreshInstallation in
        guard #available(macOS 10.15, *) else {
            return
        }
        _ = try PasscodeEnvironment.shared.sharedAccessGroup()
        PasscodeCredentialStore.shared.configureLock(directory: basePath)
        #if !SHARE
        if isMainProcess && !isTemporary && !isReadOnly {
            migrateWalletKeychainScopeIfNeeded(basePath: basePath, isFreshInstallation: isFreshInstallation)
        }
        if isMainProcess && !isTemporary && !isReadOnly && isFreshInstallation {
            try resetWalletLocalSecrets()
        }
        if isMainProcess, UserDefaults.standard.bool(forKey: walletPasscodeCredentialManagedKey) {
            if try PasscodeCredentialStore.shared.hasStoredCredential() {
                PasscodeCredentialStore.shared.requireExistingCredential()
            } else if !isTemporary && !isReadOnly {
                try resetWalletLocalSecrets()
            }
        }
        #endif
    }, resolve: { current, _ in
        guard current == nil else {
            return nil
        }
        let encryption = AppEncryptionParameters(path: (basePath as NSString).deletingLastPathComponent)
        let challenge: PostboxAccessChallengeData = encryption.hasPasscode() ? .plaintextPassword(value: "") : .none
        return challenge
    }, finishInitialization: {
        guard #available(macOS 10.15, *), isMainProcess else {
            return
        }
        try PasscodeCredentialStore.shared.resumeCleanup()
    })
}
