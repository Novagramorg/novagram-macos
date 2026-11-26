import Foundation
import AppKit
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import InAppSettings
import BuildConfig

public protocol SharedAccountContextProtocol: AnyObject {
    var accountManager: AccountManager<TelegramAccountManagerTypes> { get }
    var appEncryptionValue: AppEncryptionParameters { get }
    var activeAccounts: Signal<(primary: Account?, accounts: [(AccountRecordId, Account, Int32)], currentAuth: UnauthorizedAccount?), NoError> { get }
    var activeAccountsWithInfo: Signal<(primary: AccountRecordId?, accounts: [AccountWithInfo]), NoError> { get }
    func updateAppEncryption(_ f: (AppEncryptionParameters) -> AppEncryptionParameters)

    #if !SHARE
    var baseSettings: BaseApplicationSettings { get }
    var baseApplicationSettings: Signal<BaseApplicationSettings, NoError> { get }
    func isLite(_ key: LiteModeKey) -> Bool
    func beginNewAuth(testingEnvironment: Bool)
    func switchToAccount(id: AccountRecordId, action: LaunchNavigation?)
    var hasActiveCall: Bool { get }
    var callStatusBarMenuItems: (() -> [ContextMenuItem])? { get set }
    func dropCrossCall()
    func endCurrentCall() -> Signal<Bool, NoError>
    func endGroupCall(terminate: Bool) -> Signal<Bool, NoError>
    func updateStatusBarImage(_ image: NSImage?) -> Void
    #endif
}

#if !SHARE
public extension SharedAccountContextProtocol {
    func isLite() -> Bool {
        return isLite(.any)
    }
}
#endif
