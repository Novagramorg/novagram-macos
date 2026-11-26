import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import Localization
import SwiftSignalKit
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif
import CurrencyFormat

public extension String {
    var prettyCurrencyNumber: String {
        let nsString = self as NSString
        let range = nsString.range(of: ".")
        var string = self
        if range.location != NSNotFound {
            var lastIndex = self.count - 1
            while lastIndex > range.location && (self[self.index(self.startIndex, offsetBy: lastIndex)] == "0" || self[self.index(self.startIndex, offsetBy: lastIndex)] == "." || lastIndex > range.location + 4) {
                lastIndex -= 1
            }
            string = String(self.prefix(lastIndex + 1))
        }
        if string.hasSuffix(".") {
            _ = string.removeLast()
        }
        return string
    }
    var prettyCurrencyNumberUsd: String {
        let nsString = self as NSString
        let range = nsString.range(of: ".")
        var string = self
        if range.location != NSNotFound {
            var lastIndex = self.count - 1
            while lastIndex > range.location && (self[self.index(self.startIndex, offsetBy: lastIndex)] == "0" || self[self.index(self.startIndex, offsetBy: lastIndex)] == "." || lastIndex > range.location + 2) {
                lastIndex -= 1
            }
            string = String(self.prefix(lastIndex + 1))
        }
        if string.hasSuffix(".") {
            _ = string.removeLast()
        }
        return string
    }
}
public extension StarsAmount {
    func string(_ currency: CurrencyAmount.Currency, abs _abs: Bool = false) -> String {
        switch currency {
        case .stars:
            return self.stringValue
        case .ton:
            return formatCurrencyAmount(_abs ? abs(self.value) : self.value, currency: "TON").prettyCurrencyNumberUsd
        }
    }
}


public extension CurrencyAmount.Currency {
    var stringValue: String {
        switch self {
        case .stars:
            return "XTR"
        case .ton:
            return "TON"
        }
    }
    init(_ stringValue: String) {
        switch stringValue {
        case "TON":
            self = .ton
        case "XTR":
            self = .stars
        default:
            self = .stars
        }
    }
}


public extension CurrencyAmount {
    var fullyFormatted: String {
        switch currency {
        case .ton:
            return self.amount.string(currency) + " " + "TON"
        case .stars:
            return strings().starListItemCountOther(Int(self.amount.value)).replacingOccurrences(of: "\(self.amount.value)", with: self.amount.value.separatedNumber)
        }
    }

    var formatted: String {
        return self.amount.string(currency)
    }
}
