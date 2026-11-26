import Foundation
import SwiftSignalKit
import TelegramCore
import WalletContext
import CurrencyFormat
import Localization

public func walletLogoutConfirmationText(balance: Int64?, defaultText: String) -> String {
    guard let balance else {
        return defaultText
    }
    return strings().walletLogoutWarningBackupsWillBeDeleted(formatGramsText(balance, maxDecimalPositions: 1))
}

@available(macOS 10.15, *)
public func walletLogoutConfirmationText(walletContext: WalletContext?, appConfiguration: AppConfiguration, defaultText: String) -> Signal<String, NoError> {
    guard WalletConfiguration.with(appConfiguration: appConfiguration).isAvailable, let walletContext else {
        return .single(defaultText)
    }
    return walletContext.logoutWarningBalance()
    |> map { balance in
        walletLogoutConfirmationText(balance: balance, defaultText: defaultText)
    }
}
