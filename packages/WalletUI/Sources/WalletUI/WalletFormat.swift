import Cocoa
import ColorPalette
@_exported import CurrencyFormat
import TGUIKit
import WalletContext
import TelegramTheme
import TelegramContext
import GeneralRows
import Localization

public let walletAddressLength: Int = 48




public func formatTonAddress(_ address: String) -> String {
    return String(address.prefix(4)) + "..." + String(address.suffix(4))
}

@available(macOS 10.15, *)
func walletUniquePreviousWallets(_ wallets: [WalletContext.PreviousWallet]) -> [WalletContext.PreviousWallet] {
    var seenAddresses = Set<String>()
    return wallets
        .sorted { $0.lastUsedAt > $1.lastUsedAt }
        .filter { seenAddresses.insert($0.address).inserted }
}

public func walletAddressGroups(_ address: String) -> [String] {
    var groups: [String] = []
    var index = address.startIndex
    while index < address.endIndex {
        let endIndex = address.index(index, offsetBy: 4, limitedBy: address.endIndex) ?? address.endIndex
        groups.append(String(address[index ..< endIndex]))
        index = endIndex
    }
    return groups
}

public func walletAddressGrid(_ address: String, font: NSFont, columnCount: Int = 4, secondaryColor: NSColor = theme.colors.grayText) -> NSAttributedString {
    let text = NSMutableAttributedString()
    for (position, group) in walletAddressGroups(address).enumerated() {
        let column = position % columnCount
        if position > 0 {
            text.append(string: column == 0 ? "\n" : " ", color: theme.colors.text, font: font)
        }
        let isPrimary = (position / columnCount + column).isMultiple(of: 2)
        text.append(string: group, color: isPrimary ? theme.colors.text : secondaryColor, font: font)
    }
    return text
}

public func walletCopyAddress(_ address: String, environment: WalletUIEnvironment, window: Window) {
    environment.copyToClipboard(address)
    let copiedText = strings().walletFormatAddressCopied
    environment.showModalText(for: window, text: copiedText)
}

private let invalidAddressCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=").inverted

/// The address alphabet widened by the characters `ton://transfer/...` links are made of, so a
/// pasted link survives the filter long enough to be parsed into its address.
private let recipientInputCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_=:/?&%.+")

public func walletFilteredRecipientInput(_ value: String) -> String {
    return String(String.UnicodeScalarView(value.unicodeScalars.filter { recipientInputCharacters.contains($0) }))
}

public func isValidTonAddress(_ address: String, exactLength: Bool = false) -> Bool {
    if address.count > walletAddressLength || address.rangeOfCharacter(from: invalidAddressCharacters) != nil {
        return false
    }
    if exactLength && address.count != walletAddressLength {
        return false
    }
    return true
}

public func tonAmountAttributedString(_ string: String, integralFont: NSFont, fractionalFont: NSFont, color: NSColor) -> NSAttributedString {
    let decimalSeparator = walletDecimalSeparator
    let result = NSMutableAttributedString()
    if let range = string.range(of: decimalSeparator) {
        let integralPart = String(string[..<range.lowerBound])
        let fractionalPart = String(string[range.lowerBound...])
        result.append(NSAttributedString(string: integralPart, font: integralFont, textColor: color))
        result.append(NSAttributedString(string: fractionalPart, font: fractionalFont, textColor: color))
    } else {
        result.append(NSAttributedString(string: string, font: integralFont, textColor: color))
    }
    return result
}

@available(macOS 10.15, *)
public func walletCurrencyName(_ currency: WalletContext.FiatCurrency) -> String {
    let code = currency.code
    if let name = appAppearance.locale.localizedString(forCurrencyCode: code)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.caseInsensitiveCompare(code) != .orderedSame {
        return name
    }
    return Locale(identifier: "en").localizedString(forCurrencyCode: code) ?? code
}


