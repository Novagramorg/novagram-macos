import Foundation
import Localization

public var walletDecimalSeparator: String {
    return Locale.current.decimalSeparator ?? "."
}

public var walletGroupingSeparator: String {
    return Locale.current.groupingSeparator ?? ","
}

public func walletFormattedNumber(_ count: Int64, _ groupingSeparator: String) -> String {
    let sign = count < 0 ? "-" : ""
    let digits = "\(count.magnitude)"
    guard !groupingSeparator.isEmpty, digits.count > 3 else {
        return sign + digits
    }
    var grouped = ""
    for (offset, character) in digits.enumerated() {
        if offset > 0, (digits.count - offset).isMultiple(of: 3) {
            grouped += groupingSeparator
        }
        grouped.append(character)
    }
    return sign + grouped
}

public func formatTonAmountText(_ value: Int64, showPlus: Bool = false, maxDecimalPositions: Int? = 2) -> String {
    let magnitude = value.magnitude
    let integerPart = magnitude / 1_000_000_000
    let fractionalPart = magnitude % 1_000_000_000
    let decimalPositions = min(9, max(0, maxDecimalPositions ?? 9))

    let fractionalDigits = String(fractionalPart)
    let fullFractionalPart = String(repeating: "0", count: 9 - fractionalDigits.count) + fractionalDigits
    var fractionalPartString = String(fullFractionalPart.prefix(decimalPositions))
    if integerPart == 0 && magnitude != 0 && fractionalPartString.allSatisfy({ $0 == "0" }) {
        fractionalPartString = fullFractionalPart
    }
    while fractionalPartString.hasSuffix("0") {
        fractionalPartString.removeLast()
    }

    var balanceText = walletFormattedNumber(Int64(integerPart), walletGroupingSeparator)
    if !fractionalPartString.isEmpty {
        balanceText += walletDecimalSeparator + fractionalPartString
    }

    if value < 0 {
        balanceText.insert("-", at: balanceText.startIndex)
    } else if showPlus {
        balanceText.insert("+", at: balanceText.startIndex)
    }

    return balanceText
}

public func walletGramsUnitText(_ value: String) -> String {
    return value == "1" ? strings().tonAmountFormatGram(value) : strings().tonAmountFormatGrams(value)
}

public func formatGramsText(_ amount: Int64, maxDecimalPositions: Int) -> String {
    return walletGramsUnitText(formatTonAmountText(amount, maxDecimalPositions: maxDecimalPositions))
}

private let walletFullDecimalPositions = 9

private func walletValueRoundsToZero(_ value: Double, decimalPositions: Int) -> Bool {
    return abs(value) < 0.5 / pow(10.0, Double(decimalPositions))
}

public func formatFiatValue(_ value: Double, currencySymbol: String, maxDecimalPositions: Int = 2) -> String {
    let decimalSeparator = walletDecimalSeparator
    let groupingSeparator = walletGroupingSeparator
    var decimalPositions = maxDecimalPositions
    var dropsTrailingZeros = false
    if maxDecimalPositions < walletFullDecimalPositions,
       walletValueRoundsToZero(value, decimalPositions: maxDecimalPositions),
       !walletValueRoundsToZero(value, decimalPositions: walletFullDecimalPositions) {
        decimalPositions = walletFullDecimalPositions
        dropsTrailingZeros = true
    }
    var formattedValue = String(
        format: "%0.\(decimalPositions)f",
        locale: Locale(identifier: "en_US_POSIX"),
        value
    )
    if dropsTrailingZeros {
        while formattedValue.hasSuffix("0") {
            formattedValue.removeLast()
        }
    }
    formattedValue = formattedValue.replacingOccurrences(of: ".", with: decimalSeparator)
    if let separatorCharacter = decimalSeparator.first, let dotIndex = formattedValue.firstIndex(of: separatorCharacter) {
        let integerPartString = formattedValue[..<dotIndex]
        if let integerPart = Int64(integerPartString) {
            var modifiedIntegerPart = walletFormattedNumber(integerPart, groupingSeparator)
            if integerPart == 0, integerPartString.hasPrefix("-") {
                modifiedIntegerPart.insert("-", at: modifiedIntegerPart.startIndex)
            }
            let resultString = "\(currencySymbol)\(modifiedIntegerPart)\(formattedValue[dotIndex...])"
            return resultString
        }
    }
    if let integerPart = Int64(formattedValue) {
        return "\(currencySymbol)\(walletFormattedNumber(integerPart, groupingSeparator))"
    }
    return "\(currencySymbol)\(formattedValue)"
}

public func formatTonFiatValue(_ value: Int64, divide: Bool = true, rate: Double = 1.0, currencySymbol: String, maxDecimalPositions: Int = 2) -> String {
    let normalizedValue: Double = divide ? Double(value) / 1000000000 : Double(value)
    return formatFiatValue(
        normalizedValue * rate,
        currencySymbol: currencySymbol,
        maxDecimalPositions: maxDecimalPositions
    )
}

public func formatTonFiatValuePrecise(_ value: Int64, divide: Bool = true, rate: Double = 1.0, currencySymbol: String, minDecimalPositions: Int = 2, maxDecimalPositions: Int = 8, significantDigits: Int = 2) -> String {
    let normalizedValue: Double = divide ? Double(value) / 1000000000 : Double(value)
    let converted = normalizedValue * rate
    var positions = minDecimalPositions
    if converted.isFinite, converted != 0 {
        let exponent = Int(floor(log10(abs(converted))))
        positions = max(minDecimalPositions, significantDigits - 1 - exponent)
        positions = min(positions, maxDecimalPositions)
    }
    return formatFiatValue(converted, currencySymbol: currencySymbol, maxDecimalPositions: positions)
}

public func formatTonUsdValue(_ value: Int64, divide: Bool = true, rate: Double = 1.0, maxDecimalPositions: Int = 2) -> String {
    return formatTonFiatValue(
        value,
        divide: divide,
        rate: rate,
        currencySymbol: "$",
        maxDecimalPositions: maxDecimalPositions
    )
}
