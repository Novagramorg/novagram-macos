import Cocoa
import TelegramCore

import Postbox
import SwiftSignalKit
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif







public func upgradedAccounts(accountManager: AccountManager<TelegramAccountManagerTypes>, rootPath: String, encryptionParameters: ValueBoxEncryptionParameters) -> Signal<Float, NoError> {
    return .complete()
}
