import Foundation
import SwiftSignalKit

public enum PasscodeCredentialSyncError: Error, Equatable {
    case invalidCode
    case cooldown(Int)
    case failed
}

public struct PasscodeWalletProtection: Equatable {
    public let enabled: Bool
    public let biometricsEnabled: Bool

    public init(enabled: Bool, biometricsEnabled: Bool) {
        self.enabled = enabled
        self.biometricsEnabled = biometricsEnabled
    }
}

public typealias PasscodeCredentialSyncCompletion = (Result<Void, PasscodeCredentialSyncError>) -> Void

public struct PasscodeCredentialHooks {
    public var passcodeInstalled: (String, @escaping PasscodeCredentialSyncCompletion) -> Void = { _, completion in completion(.success(())) }
    public var passcodeChanged: (String, String, @escaping PasscodeCredentialSyncCompletion) -> Void = { _, _, completion in completion(.success(())) }
    public var passcodeDisabled: (String, @escaping PasscodeCredentialSyncCompletion) -> Void = { _, completion in completion(.success(())) }
    public var passcodeUnlocked: (String) -> Void = { _ in }
    public var walletProtection: () -> Signal<PasscodeWalletProtection?, NoError> = { .single(nil) }
    public var setWalletProtection: (Bool, String, @escaping PasscodeCredentialSyncCompletion) -> Void = { _, _, completion in completion(.failure(.failed)) }
    public var setWalletBiometrics: (Bool, String, @escaping PasscodeCredentialSyncCompletion) -> Void = { _, _, completion in completion(.failure(.failed)) }

    public init() {
    }

    public private(set) static var shared = PasscodeCredentialHooks()

    public static func install(_ hooks: PasscodeCredentialHooks) {
        shared = hooks
    }
}
