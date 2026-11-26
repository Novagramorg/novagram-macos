import XCTest
import Cocoa
import WalletContext
import TelegramCore
import Postbox
import ColorPalette
import TGUIKit
import GZIP
import SwiftSignalKit
import CurrencyFormat
import CoreText
import QuartzCore
import Metal
@testable import WalletUI

private func submoduleShimmerBand(width: CGFloat, frame: CGRect, cardWidth: CGFloat) -> [(keyPath: String, from: CGPoint, to: CGPoint)] {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        return CGPoint(x: (x - 4.0 - frame.minX) / frame.width, y: (y - 4.0 - frame.minY) / frame.height)
    }
    let fromX = -0.6 * cardWidth
    let toX = 1.6 * cardWidth
    return [
        ("startPoint", point(fromX - width, 0.0), point(toX - width, 0.0)),
        ("endPoint", point(fromX + width, width * 0.7), point(toX + width, width * 0.7))
    ]
}

private func submoduleNormalizedDigits(_ text: String) -> String {
    return String(text.unicodeScalars.map { scalar -> Character in
        let character = Character(String(scalar))
        if CharacterSet.decimalDigits.contains(scalar), let digit = character.wholeNumberValue {
            return Character(String(digit))
        }
        return character
    })
}

private func submoduleNanograms(text: String, mode: WalletSendInputMode, rate: Double?, decimalSeparator: String) -> Int64? {
    guard !text.isEmpty else {
        return 0
    }
    guard !decimalSeparator.isEmpty else { return nil }
    let normalizedText = submoduleNormalizedDigits(text).replacingOccurrences(of: decimalSeparator, with: ".")
    let parts = normalizedText.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2,
          parts.allSatisfy({ $0.utf8.allSatisfy({ (48 ... 57).contains($0) }) }) else {
        return nil
    }
    switch mode {
    case .gram:
        let wholeText = parts.first.map(String.init) ?? ""
        let whole: Int64
        if wholeText.isEmpty {
            whole = 0
        } else if let value = Int64(wholeText) {
            whole = value
        } else {
            return nil
        }
        guard whole >= 0 else {
            return nil
        }
        let scale: Int64 = 1_000_000_000
        let (scaledWhole, didOverflow) = whole.multipliedReportingOverflow(by: scale)
        guard !didOverflow else {
            return nil
        }
        var fractionalText = parts.count == 2 ? String(parts[1]) : ""
        guard fractionalText.count <= 9 else {
            return nil
        }
        fractionalText = fractionalText.padding(toLength: 9, withPad: "0", startingAt: 0)
        guard let fractional = Int64(fractionalText) else { return nil }
        let (result, didAddOverflow) = scaledWhole.addingReportingOverflow(fractional)
        return didAddOverflow ? nil : result
    case .fiat:
        guard let rate, rate.isFinite, rate > 0.0,
              let fiatValue = Double(normalizedText), fiatValue.isFinite, fiatValue >= 0.0 else {
            return nil
        }
        let nanograms = fiatValue / rate * 1_000_000_000.0
        let roundedNanograms = nanograms.rounded()
        guard roundedNanograms.isFinite,
              roundedNanograms >= 0.0,
              roundedNanograms < Double(Int64.max) else {
            return nil
        }
        return Int64(roundedNanograms)
    }
}

private func submoduleReplacingAmountText(_ text: String, range: NSRange, replacement string: String, mode: WalletSendInputMode, rate: Double?, decimalSeparator: String) -> (text: String, selection: NSRange)? {
    guard !decimalSeparator.isEmpty else { return nil }
    var replacement = submoduleNormalizedDigits(string)
    if replacement == "." || replacement == "," {
        replacement = decimalSeparator
    }
    let previousText = text as NSString
    guard range.location != NSNotFound, range.location >= 0, range.location <= previousText.length,
          range.length >= 0, range.length <= previousText.length - range.location else { return nil }
    var updatedText = previousText.replacingCharacters(in: range, with: replacement)
    var selectionOffset = range.location + replacement.utf16.count
    let allowedCharacters = CharacterSet(charactersIn: "0123456789" + decimalSeparator)
    guard updatedText.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
        return nil
    }
    guard updatedText.components(separatedBy: decimalSeparator).count <= 2 else {
        return nil
    }
    let maximumFractionalDigits = mode == .gram ? 9 : 2
    if let range = updatedText.range(of: decimalSeparator) {
        let fractionalCount = updatedText[range.upperBound...].count
        guard fractionalCount <= maximumFractionalDigits else {
            return nil
        }
    }
    if updatedText == decimalSeparator {
        updatedText = "0" + decimalSeparator
        selectionOffset += 1
    }
    if updatedText.count > 1 && updatedText.hasPrefix("0") && !updatedText.hasPrefix("0" + decimalSeparator) {
        updatedText.removeFirst()
        selectionOffset = max(0, selectionOffset - 1)
    }
    let shouldAppendDecimalSeparator = !replacement.isEmpty && updatedText == "0"
    if shouldAppendDecimalSeparator {
        updatedText += decimalSeparator
        selectionOffset = updatedText.utf16.count
    }
    guard submoduleNanograms(text: updatedText, mode: mode, rate: rate, decimalSeparator: decimalSeparator) != nil else {
        return nil
    }
    return (updatedText, NSRange(location: selectionOffset, length: 0))
}

private enum SubmoduleAmountReplaceOutcome: Equatable {
    case ignored
    case rejected
    case accepted(String, NSRange)
}

private func submoduleReplaceText(_ text: String, range: NSRange, string: String, mode: WalletSendInputMode, rate: Double?, decimalSeparator: String) -> SubmoduleAmountReplaceOutcome {
    let length = (text as NSString).length
    guard range.location != NSNotFound, range.location >= 0, range.location <= length,
          range.length >= 0, range.length <= length - range.location,
          !string.isEmpty || range.length > 0 else { return .ignored }

    if text == "0" + decimalSeparator, range.location == length, range.length == 0,
       string == decimalSeparator || string == "." || string == "," {
        return .ignored
    }

    guard let edit = submoduleReplacingAmountText(text, range: range, replacement: string, mode: mode, rate: rate, decimalSeparator: decimalSeparator) else {
        return .rejected
    }
    return .accepted(edit.text, edit.selection)
}

private func actualAmountEditOutcome(_ text: String, range: NSRange, string: String, mode: WalletSendInputMode, rate: Double?, decimalSeparator: String) -> SubmoduleAmountReplaceOutcome {
    switch walletSendAmountEditResult(text, range: range, replacement: string, mode: mode, rate: rate, decimalSeparator: decimalSeparator) {
    case .ignored:
        return .ignored
    case .rejected:
        return .rejected
    case let .accepted(edit):
        return .accepted(edit.text, edit.selection)
    }
}

private func submoduleCardBalanceText(balance: Int64?, formattedBalance: String, decimalSeparator: String) -> (integral: String, fractional: String) {
    let integralText: String
    let fractionalText: String
    if balance == nil || balance == 0 {
        integralText = formattedBalance
        fractionalText = ""
    } else if let decimalRange = formattedBalance.range(of: decimalSeparator) {
        integralText = String(formattedBalance[..<decimalRange.lowerBound])
        fractionalText = String(formattedBalance[decimalRange.lowerBound...])
    } else {
        integralText = formattedBalance
        fractionalText = ""
    }
    return (integralText, fractionalText)
}

private func compactSource(_ source: String) -> String {
    return source.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

private let submoduleCollectibleLottieMaximumSize = 5 * 1024 * 1024

private func submoduleCollectibleLottieData(_ data: Data) -> Data? {
    guard data.count <= submoduleCollectibleLottieMaximumSize else { return nil }
    let decoded: Data
    if data.starts(with: [0x1f, 0x8b]) {
        guard let unpacked = TGGUnzipData(data, UInt32(submoduleCollectibleLottieMaximumSize)) else { return nil }
        decoded = unpacked
    } else {
        decoded = data
    }
    guard decoded.count <= submoduleCollectibleLottieMaximumSize,
          (try? JSONSerialization.jsonObject(with: decoded)) is [String: Any] else { return nil }
    return decoded
}

private func submoduleRequestLoadMorePage(collectiblesCount: Int, index: Int, state: WalletContext.CollectiblesState, requestedPage: WalletContext.CollectiblesState.PageId?, failedPage: WalletContext.CollectiblesState.PageId?, hasActiveOperation: Bool) -> WalletContext.CollectiblesState.PageId? {
    guard collectiblesCount > 0,
          index >= max(0, collectiblesCount - 2),
          let page = state.nextPage,
          !state.isRefreshing,
          !state.isLoadingMore,
          state.error == nil || failedPage == nil,
          !hasActiveOperation else {
        return nil
    }
    guard requestedPage != page else {
        return nil
    }
    return page
}

private func submoduleTonHashHex(fromBase64 hash: String) -> String? {
    guard let data = Data(base64Encoded: hash), data.count == 32 else {
        return nil
    }
    return data.map { String(format: "%02x", $0) }.joined()
}

private func submoduleTransactionExplorerUrl(explorerUrl: String, id: String) -> String? {
    guard let encodedId = submoduleTonHashHex(fromBase64: id) else {
        return nil
    }
    let baseUrl = explorerUrl.hasSuffix("/") ? explorerUrl : explorerUrl + "/"
    return "\(baseUrl)transaction/\(encodedId)"
}

private func submoduleCollectibleExplorerUrl(explorerUrl: String, address: String) -> String? {
    guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !encodedAddress.isEmpty else {
        return nil
    }
    let baseUrl = explorerUrl.hasSuffix("/") ? explorerUrl : explorerUrl + "/"
    return "\(baseUrl)\(encodedAddress)"
}

private func submodulePreviewAmount(preparedAmount: Int64?, amount: Int64, isSendAll: Bool, displayedFee: Int64?) -> Int64 {
    return preparedAmount ?? (isSendAll ? max(0, amount - (displayedFee ?? 0)) : amount)
}

private func submodulePreviewGasless(isCollectible: Bool, isSelfTransfer: Bool, isSendAll: Bool, isPrepared: Bool, displayedFee: Int64?, amount: Int64, gaslessInfo: WalletGaslessInfo?, minimumAmount: Int64) -> Bool {
    if !isCollectible, !isSelfTransfer, !isSendAll || isPrepared || displayedFee != nil {
        return WalletContext.isGaslessEligible(amount: amount, gaslessInfo: gaslessInfo, minimumAmount: minimumAmount)
    }
    return false
}

private enum SubmoduleFeeRow: Equatable {
    case fee(Int64)
    case placeholder
    case gaslessFree
}

private func submoduleFeeRows(isPreview: Bool, displayedFee: Int64?, transactionFee: Int64, isSelfTransfer: Bool, isOutgoing: Bool, gasless: Bool) -> [SubmoduleFeeRow] {
    var rows: [SubmoduleFeeRow] = []
    let displayed: Int64? = isPreview ? displayedFee : transactionFee
    let feeComponent: SubmoduleFeeRow?
    if let displayed {
        feeComponent = displayed > 0 ? .fee(displayed) : nil
    } else {
        feeComponent = .placeholder
    }
    if isSelfTransfer || (isOutgoing && !gasless), let feeComponent {
        rows.append(feeComponent)
    }
    if !isPreview, !isSelfTransfer, gasless && isOutgoing {
        rows.append(.gaslessFree)
    }
    return rows
}

private func actualFeeRows(_ display: WalletTransactionFeeDisplay) -> [SubmoduleFeeRow] {
    switch display {
    case .none:
        return []
    case .placeholder:
        return [.placeholder]
    case let .fee(fee):
        return [.fee(fee)]
    case .free:
        return [.gaslessFree]
    }
}

private func submoduleBalanceError(balance: Int64?, requestedAmount: Int64, sendAll: Bool) -> WalletContext.WalletError? {
    guard let balance, requestedAmount <= balance else {
        return .insufficientBalance(required: requestedAmount)
    }
    if sendAll && balance != requestedAmount {
        return .previewFailed
    }
    return nil
}

private enum SubmoduleDefaultAccent {
    case day
    case night
    case nightTinted
}

private func submoduleGramColor(overallDarkAppearance: Bool) -> UInt32 {
    return overallDarkAppearance ? 0x30A1F5 : 0x0088ff
}

private func submoduleDefaultAccent(for parent: TelegramBuiltinTheme, isDark: Bool) -> SubmoduleDefaultAccent {
    switch parent {
    case .day, .dayClassic:
        return .day
    case .dark:
        return .night
    case .nightAccent:
        return .nightTinted
    case .system:
        return isDark ? .night : .day
    }
}

private enum SubmodulePeerSelectionMode {
    case transfer
    case collectible(WalletContext.Collectible)
}

private enum SubmodulePeerSelectionRoute: Equatable {
    case sendScreen(address: String)
    case transactionPreview(address: String, collectible: WalletContext.Collectible)
    case errorAlert
}

private func submoduleOpenRecipient(_ recipient: WalletContext.ResolvedTransferRecipient, mode: SubmodulePeerSelectionMode) -> SubmodulePeerSelectionRoute {
    switch mode {
    case .transfer:
        return .sendScreen(address: recipient.transferInput)
    case let .collectible(collectible):
        return .transactionPreview(address: recipient.address, collectible: collectible)
    }
}

private func submoduleCollectiblePeerSelected(addresses: [WalletUserAddress], peerId: EnginePeer.Id, displayName: String, collectible: WalletContext.Collectible) -> SubmodulePeerSelectionRoute {
    let address: String? = {
        guard let result = addresses.first(where: { $0.userId == peerId }) else {
            return nil
        }
        let address = result.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            return nil
        }
        return address
    }()
    if let address {
        return submoduleOpenRecipient(WalletContext.ResolvedTransferRecipient(address: address, displayName: displayName), mode: .collectible(collectible))
    } else {
        return .errorAlert
    }
}

private struct SubmoduleSendPeerAddressResolution {
    enum State: Equatable {
        case notRequested
        case loading
        case resolved
        case failed
        case errorPresented
        case cancelled
    }

    var state: State = .notRequested
    private(set) var recipient: WalletUserAddress?
    private var generation = 0

    mutating func reset(resolvedAddress: WalletUserAddress?) {
        self.generation &+= 1
        self.recipient = resolvedAddress
        self.state = resolvedAddress == nil ? .notRequested : .resolved
    }

    mutating func begin() -> Int? {
        guard self.state == .notRequested else {
            return nil
        }
        self.generation &+= 1
        self.state = .loading
        return self.generation
    }

    mutating func complete(generation: Int, recipient: WalletUserAddress?) -> Bool {
        guard self.state == .loading, self.generation == generation else {
            return false
        }
        let address = recipient?.address.trimmingCharacters(in: .whitespacesAndNewlines)
        if let recipient, let address, !address.isEmpty {
            self.recipient = WalletUserAddress(userId: recipient.userId, address: address, publicKey: recipient.publicKey)
            self.state = .resolved
        } else {
            self.recipient = nil
            self.state = .failed
        }
        return true
    }
}

private enum SubmoduleSendFeeDisplay: Equatable {
    case hidden
    case loading
    case unavailable
}

private func submoduleSendRecipientIsLoading(recipientAddress: String, resolution: SubmoduleSendPeerAddressResolution.State) -> Bool {
    return recipientAddress.isEmpty && (resolution == .notRequested || resolution == .loading)
}

private func submoduleSendRecipientAddressText(address: String, hasPeer: Bool, isLoading: Bool) -> String {
    let displaysPlaceholder = hasPeer && (isLoading || address.isEmpty)
    return displaysPlaceholder ? String(repeating: "0", count: 48) : (address.isEmpty ? "—" : address)
}

private func submoduleSendCanOpenRecipientInfo(address: String, isLoading: Bool) -> Bool {
    return !isLoading && !address.isEmpty
}

private func submoduleSendFeeDisplayWithoutRecipient(amount: Int64, shouldSendAll: Bool, gaslessInfo: WalletGaslessInfo?, minimumAmount: Int64, resolution: SubmoduleSendPeerAddressResolution.State, walletIsLoading: Bool) -> SubmoduleSendFeeDisplay {
    guard amount > 0 else {
        return .hidden
    }
    guard gaslessInfo != nil else {
        return .hidden
    }
    if !shouldSendAll && WalletContext.isGaslessEligible(amount: amount, gaslessInfo: gaslessInfo, minimumAmount: minimumAmount) {
        return .hidden
    }
    if resolution == .failed || resolution == .errorPresented || resolution == .cancelled {
        return .unavailable
    }
    if !walletIsLoading {
        return .unavailable
    }
    return .loading
}

@available(macOS 10.15, *)
private func actualSendFeeDisplay(_ display: WalletSendFeeDisplay?) -> SubmoduleSendFeeDisplay? {
    switch display {
    case .none:
        return .hidden
    case .loading:
        return .loading
    case .unavailable:
        return .unavailable
    case .value:
        return nil
    }
}

@available(macOS 10.15, *)
private func actualRoute(_ destination: WalletRecipientDestination?) -> SubmodulePeerSelectionRoute {
    switch destination {
    case let .send(address, _):
        return .sendScreen(address: address)
    case let .collectiblePreview(address, collectible):
        return .transactionPreview(address: address, collectible: collectible)
    case .none:
        return .errorAlert
    }
}

@available(macOS 10.15, *)
private func submoduleFormatTonAmountText(_ value: Int64, decimalSeparator: String, groupingSeparator: String, showPlus: Bool = false, maxDecimalPositions: Int? = 2, formatString: ((Int32) -> String)? = nil) -> String {
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

    var balanceText = String(integerPart)
    if !groupingSeparator.isEmpty {
        var groupingOffset = balanceText.count - 3
        while groupingOffset > 0 {
            balanceText.insert(contentsOf: groupingSeparator, at: balanceText.index(balanceText.startIndex, offsetBy: groupingOffset))
            groupingOffset -= 3
        }
    }
    if !fractionalPartString.isEmpty {
        balanceText += decimalSeparator + fractionalPartString
    }

    if value < 0 {
        balanceText.insert("-", at: balanceText.startIndex)
    } else if showPlus {
        balanceText.insert("+", at: balanceText.startIndex)
    }

    if let formatString {
        let pluralizationValue: Int32 = (integerPart == 1 && fractionalPartString.isEmpty) ? 1 : 100
        return formatString(pluralizationValue).replacingOccurrences(of: "\(pluralizationValue)", with: balanceText)
    }
    return balanceText
}

private func submoduleLogoutConfirmationText(balance: Int64?, strings: [String: String], defaultText: String, decimalSeparator: String, groupingSeparator: String) -> String {
    guard let balance else {
        return defaultText
    }
    let amount = submoduleFormatTonAmountText(
        balance,
        decimalSeparator: decimalSeparator,
        groupingSeparator: groupingSeparator,
        maxDecimalPositions: 1,
        formatString: { count in
            let format = count == 1 ? strings["Currency.Grams_1"]! : strings["Currency.Grams_any"]!
            return format.replacingOccurrences(of: "%@", with: "\(count)")
        }
    )
    return strings["Settings.LogoutConfirmationTextWithWallets"]!.replacingOccurrences(of: "%@", with: amount)
}

private func submoduleCheckFirstGramsOnAppear(_ transaction: WalletContext.Transaction, decryptCommentOnOpen: Bool) -> Bool {
    return !decryptCommentOnOpen && transaction.direction == .incoming && transaction.currency == .ton && transaction.collectible == nil
}

private func submoduleHasPendingCommentDecryption(_ initialTransaction: WalletContext.Transaction, decryptCommentOnOpen: Bool) -> Bool {
    return decryptCommentOnOpen && initialTransaction.commentEncrypted && initialTransaction.comment?.isEmpty == false
}

private let submoduleAmountIntegralFontSize: CGFloat = 48.0
private let submoduleGramAnimationSide: CGFloat = 96.0
private let submoduleDiamondWidth: CGFloat = 34.0
private let submoduleDiamondNudge: CGFloat = 1.0
private let submoduleFiatSymbolFontSize: CGFloat = 34.0
private let submoduleFiatSymbolGap: CGFloat = 8.3
private let submoduleFiatSymbolOpticalShift: CGFloat = 3.45
private let submoduleSymbolDrop: CGFloat = 16.0
private let submoduleSymbolBlur: CGFloat = 6.0
private let submoduleSwitchingDuration: Double = 0.46

private func submoduleSpinVelocity(_ insertedText: String) -> Float {
    let velocity: Float
    if insertedText.isEmpty {
        velocity = 6.5
    } else if let digit = insertedText.last(where: { $0.wholeNumberValue != nil })?.wholeNumberValue {
        velocity = -(5.5 + 0.25 * Float(digit))
    } else {
        velocity = -3.5
    }
    return velocity
}

private func submoduleMotionEase(_ raw: Double) -> CGFloat {
    let t = min(max(raw, 0), 1)
    return CGFloat(1 - pow(1 - t, 2.2))
}

private struct SubmoduleSymbolState: Equatable {
    var drop: CGFloat
    var tilt: CGFloat
    var blur: CGFloat
    var alpha: CGFloat
}

private struct SubmoduleSymbolTransition {
    let start: Double
    let duration: Double
    let reduced: Bool
    let toGram: Bool
    var gramFrom: SubmoduleSymbolState?
    var fiatFrom: SubmoduleSymbolState?

    var totalDuration: Double { return self.reduced ? self.duration : self.duration + 1.5 }

    func layoutProgress(at time: Double) -> CGFloat {
        return submoduleMotionEase(min(1, max(0, (time - self.start) / self.duration)))
    }

    func state(gram: Bool, at time: Double) -> SubmoduleSymbolState {
        let elapsed = max(0.0, time - self.start)
        let p = self.layoutProgress(at: time)
        let arriving = gram == self.toGram
        let from = gram ? self.gramFrom : self.fiatFrom
        let toAlpha: CGFloat = arriving ? 1.0 : 0.0
        let fromAlpha = from?.alpha ?? (1.0 - toAlpha)
        let alpha = fromAlpha + (toAlpha - fromAlpha) * p
        if self.reduced {
            return SubmoduleSymbolState(drop: 0.0, tilt: 0.0, blur: 0.0, alpha: alpha)
        }
        let tail = max(0.0, elapsed - 0.3)
        let fromDrop = from?.drop ?? (arriving ? submoduleSymbolDrop : 0.0)
        let toDrop: CGFloat = arriving ? 0.0 : submoduleSymbolDrop
        return SubmoduleSymbolState(
            drop: fromDrop + (toDrop - fromDrop) * p,
            tilt: CGFloat(20.0 * sin(2.0 * .pi * 1.6 * tail) * exp(-tail / 0.5)) * .pi / 180.0
                + (from?.tilt ?? 0.0) * (1.0 - p),
            blur: submoduleSymbolBlur * sin(.pi * alpha),
            alpha: alpha
        )
    }
}

private func submodulePulseScale(_ t: CGFloat, fromScale: CGFloat) -> CGFloat {
    return 1.0 + 0.14 * sin(.pi * t) * (1.0 - 0.3 * t) + (fromScale - 1.0) * (1.0 - submoduleMotionEase(Double(t)))
}

private func submoduleInkBounds(_ text: String, font: NSFont) -> CGRect {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    return CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
}

private func submoduleFiatSymbolSpacing(displayText: String, integralFont: NSFont, textInset: CGFloat) -> CGFloat {
    let firstDigitBounds = submoduleInkBounds(String(displayText.prefix(1)), font: integralFont)
    return submoduleFiatSymbolGap - max(0.0, firstDigitBounds.minX) - textInset
}

private func submoduleFiatSymbolBaseline(amountBaseline: CGFloat, integralFont: NSFont, fiatSymbolFont: NSFont) -> CGFloat {
    return amountBaseline - integralFont.capHeight / 2.0 + fiatSymbolFont.capHeight / 2.0 + submoduleFiatSymbolOpticalShift
}

private func submoduleRoundedBoldFont(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .bold)
    guard let descriptor = base.fontDescriptor.withDesign(.rounded) else {
        return base
    }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

private func submoduleFiatSymbolFont(_ size: CGFloat) -> NSFont {
    let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor
    var updatedDescriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits)
    let featureSettings: [[String: Any]] = [[
        kCTFontOpenTypeFeatureTag as String: "cv09",
        kCTFontOpenTypeFeatureValue as String: 1
    ]]
    updatedDescriptor = updatedDescriptor.addingAttributes([.featureSettings: featureSettings])
    updatedDescriptor = updatedDescriptor.withDesign(.rounded) ?? updatedDescriptor
    updatedDescriptor = updatedDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: NSFont.Weight.bold]])
    return NSFont(descriptor: updatedDescriptor, size: size) ?? NSFont.systemFont(ofSize: size, weight: .bold)
}

private func submoduleGlyphNames(_ text: String, font: NSFont) -> [String] {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    var names: [String] = []
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        names.append(contentsOf: glyphs.map { (CTFontCopyNameForGlyph(runFont, $0) as String?) ?? "\($0)" })
    }
    return names
}

private struct SubmoduleAmountGlyph {
    enum Group: Equatable {
        case integer, fraction, grouping, suffix, prefix
    }

    let text: String
    let font: NSFont
    var position: CGPoint
    var group: Group
    let width: CGFloat

    init(text: String, font: NSFont, position: CGPoint, group: Group) {
        self.text = text
        self.font = font
        self.position = position
        self.group = group
        self.width = submoduleGlyphWidth(text, font: font)
    }

    static func text(_ text: NSAttributedString, origin: CGPoint, group: Group) -> [SubmoduleAmountGlyph] {
        guard text.length > 0 else { return [] }
        let line = CTLineCreateWithAttributedString(text)
        var positionsByIndex: [Int: CGPoint] = [:]
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetPositions(run, CFRangeMake(0, count), &positions)
            CTRunGetStringIndices(run, CFRangeMake(0, count), &indices)
            for i in 0 ..< count where positionsByIndex[indices[i]] == nil {
                positionsByIndex[indices[i]] = positions[i]
            }
        }
        var offset = 0
        return text.string.map { character in
            let string = String(character)
            let attributes = text.attributes(at: offset, effectiveRange: nil)
            let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 13.0)
            let width = submoduleGlyphWidth(string, font: font)
            let position = positionsByIndex[offset] ?? CGPoint(x: CTLineGetOffsetForStringIndex(line, offset, nil), y: 0.0)
            offset += string.utf16.count
            return SubmoduleAmountGlyph(
                text: string, font: font,
                position: CGPoint(x: origin.x + position.x + width / 2.0, y: origin.y - position.y), group: group
            )
        }
    }
}

private func submoduleGlyphWidth(_ text: String, font: NSFont) -> CGFloat {
    return (text as NSString).size(withAttributes: [.font: font]).width
}

private func submoduleAmountGlyphs(_ attributedText: NSAttributedString, origin: CGPoint, decimal: String) -> [SubmoduleAmountGlyph] {
    var glyphs = SubmoduleAmountGlyph.text(attributedText, origin: origin, group: .integer)
    let fractionOffset = (attributedText.string as NSString).range(of: decimal).location
    var offset = 0
    for i in glyphs.indices {
        if fractionOffset != NSNotFound && offset >= fractionOffset { glyphs[i].group = .fraction }
        offset += glyphs[i].text.utf16.count
    }
    return glyphs
}

private func submoduleRefractionGlyph(_ target: [SubmoduleAmountGlyph], mode: WalletSendInputMode) -> SubmoduleAmountGlyph? {
    guard mode == .gram,
          let glyph = target.first(where: { $0.group == .integer && $0.text.first?.wholeNumberValue != nil }) else {
        return nil
    }
    return glyph
}

private struct SubmoduleGlyphMask {
    let rect: CGRect
    let width: Int
    let height: Int
    let bytes: [UInt8]
}

private func submoduleGlyphMask(_ text: String, font: NSFont, scale: CGFloat) -> SubmoduleGlyphMask? {
    let width = submoduleGlyphWidth(text, font: font)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        var indices = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRangeMake(0, count), &indices)
        CTRunGetPositions(run, CFRangeMake(0, count), &positions)
        for i in 0 ..< count {
            if let outline = CTFontCreatePathForGlyph(runFont, indices[i], nil) {
                path.addPath(outline, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                    tx: positions[i].x - width / 2, ty: -positions[i].y))
            }
        }
    }
    guard !path.isEmpty else { return nil }
    let ink = path.boundingBoxOfPath.insetBy(dx: -2 / scale, dy: -2 / scale)
    let rect = CGRect(x: floor(ink.minX * scale) / scale, y: floor(ink.minY * scale) / scale,
                      width: ceil(ink.width * scale + 1) / scale, height: ceil(ink.height * scale + 1) / scale)
    let tileWidth = max(1, Int(round(rect.width * scale)))
    let tileHeight = max(1, Int(round(rect.height * scale)))
    var bytes = [UInt8](repeating: 0, count: tileWidth * tileHeight)
    let drawn = bytes.withUnsafeMutableBytes { storage -> Bool in
        guard let context = CGContext(data: storage.baseAddress, width: tileWidth, height: tileHeight,
            bitsPerComponent: 8, bytesPerRow: tileWidth, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        context.translateBy(x: 0, y: CGFloat(tileHeight))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(gray: 1, alpha: 1)
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
        return true
    }
    guard drawn else { return nil }
    return SubmoduleGlyphMask(rect: rect, width: tileWidth, height: tileHeight, bytes: bytes)
}

private func submoduleApply(_ m: CATransform3D, _ p: CGPoint) -> CGPoint {
    return CGPoint(x: p.x * m.m11 + p.y * m.m21 + m.m41, y: p.x * m.m12 + p.y * m.m22 + m.m42)
}

private func submoduleInfoParagraphTextOriginY(textTopInset: CGFloat, textHeight: CGFloat) -> (textOriginY: CGFloat, iconCenterY: CGFloat) {
    let textOriginY: CGFloat
    let iconCenterY: CGFloat
    iconCenterY = textTopInset + 14.0
    if textHeight <= 20.0 {
        textOriginY = iconCenterY - textHeight / 2.0 + 1.0
    } else {
        textOriginY = textTopInset
    }
    return (textOriginY, iconCenterY)
}

private enum SubmoduleCollectibleTransferRoute: Equatable {
    case routeToTransfer
    case restoreSigningAccess
    case importRecoveryPhrase
}

private func submoduleCollectibleOpenTransfer(_ phase: WalletContext.Phase) -> SubmoduleCollectibleTransferRoute? {
    guard case let .wallet(info) = phase else { return nil }
    if info.canSign {
        return .routeToTransfer
    } else if info.canExportPhrase {
        return .restoreSigningAccess
    } else {
        return .importRecoveryPhrase
    }
}

private struct SubmoduleSuppressedCollectibles {
    var walletState: WalletContext.State?
    var suppressedCollectibleAddresses = Set<String>()
    var suppressedCollectiblesWalletAddress: String?

    mutating func updateSuppressedCollectibles(_ state: WalletContext.State) {
        switch state.phase {
        case let .wallet(info):
            if let currentAddress = self.suppressedCollectiblesWalletAddress, currentAddress != info.address {
                self.suppressedCollectibleAddresses.removeAll()
            }
            self.suppressedCollectiblesWalletAddress = info.address
            let collectibles = state.collectibles
            if let previous = self.walletState?.collectibles,
               previous.generation == collectibles.generation,
               previous.isRefreshing || previous.isLoadingMore,
               !collectibles.isRefreshing, !collectibles.isLoadingMore,
               collectibles.error == nil, collectibles.nextOffset == nil {
                self.suppressedCollectibleAddresses.formIntersection(collectibles.items.map(\.address))
            }
        case .restoring:
            break
        case .creating, .empty, .failed:
            self.suppressedCollectibleAddresses.removeAll()
            self.suppressedCollectiblesWalletAddress = nil
        }
    }

    mutating func walletStateUpdated(_ walletState: WalletContext.State) {
        self.updateSuppressedCollectibles(walletState)
        self.walletState = walletState
    }
}

final class WalletSubmoduleCompatibilityTests: XCTestCase {
    private let walletAddress = "0:" + String(repeating: "1", count: 64)
    private let otherAddress = "0:" + String(repeating: "2", count: 64)

    override func setUp() {
        super.setUp()
        applyMacEnglishStrings()
    }

    override func tearDown() {
        applyMacEnglishStrings([:])
        super.tearDown()
    }

    private func file(_ name: String, mimeType: String = "image/png") -> WalletNftFile {
        return WalletNftFile(url: "https://nft.fragment.com/\(name)", accessHash: Int64(name.count) * 1_000, size: 100 + Int32(name.count), mimeType: mimeType)
    }

    private func nft(image: WalletNftFile?, imageSmall: WalletNftFile?, lottie: WalletNftFile?) -> WalletNftItem {
        return WalletNftItem(collectionAddress: nil, address: "nft", ownerAddress: walletAddress, index: "1", name: "Gift", description: nil, image: image, imageSmall: imageSmall, contentUrl: nil, lottie: lottie, attributes: nil, extra: nil)
    }

    private func collectiblesState(nextOffset: String?, generation: UInt64 = 0, isRefreshing: Bool = false, isLoadingMore: Bool = false, error: WalletContext.SynchronizationError? = nil) -> WalletContext.CollectiblesState {
        return WalletContext.CollectiblesState(items: [], nextOffset: nextOffset, generation: generation, isRefreshing: isRefreshing, isLoadingMore: isLoadingMore, error: error)
    }

    private func gaslessInfo(left: Int32 = 5) -> WalletGaslessInfo {
        return WalletGaslessInfo(available: true, left: left, resetAt: 0, minAmount: 1_000_000_000, relayerAddress: otherAddress)
    }

    private func repositoryRoot() -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testCollectibleWebFileKeepsTelegramFile() {
        let nftFile = file("gift.webp", mimeType: "image/webp")
        let webFile = walletCollectibleWebFile(nftFile)
        let resource = webFile?.resource as? WebFileReferenceMediaResource
        XCTAssertEqual(resource?.url, nftFile.url)
        XCTAssertEqual(resource?.accessHash, nftFile.accessHash)
        XCTAssertEqual(resource?.actualSize, Int64(nftFile.size))
        XCTAssertEqual(webFile?.mimeType, "image/webp")
        XCTAssertEqual(webFile?.size, nftFile.size)
        XCTAssertNil(walletCollectibleWebFile(nil))
    }

    func testCollectibleMediaPrefersServerFilesLikeSubmodule() {
        let large = file("large.png")
        let small = file("small.png")
        let animation = file("gift.tgs", mimeType: "application/x-tgsticker")
        let collectible = WalletContext.Collectible(address: "nft", name: "Gift", kind: .gift, nft: nft(image: large, imageSmall: small, lottie: animation))
        XCTAssertEqual(collectible.thumbnail, small)
        XCTAssertEqual(collectible.image, large)
        XCTAssertEqual(collectible.lottie, animation)

        let transfer = WalletContext.Transaction.CollectibleTransfer(collectible: collectible)
        XCTAssertEqual(transfer.image, large)
        XCTAssertEqual(transfer.thumbnail, small)
        XCTAssertEqual(transfer.lottie, animation)
        XCTAssertEqual(transfer.thumbnail ?? transfer.image, small)

        let onlyLarge = WalletContext.Collectible(address: "nft", name: "Gift", kind: .gift, nft: nft(image: large, imageSmall: nil, lottie: nil))
        XCTAssertEqual(onlyLarge.thumbnail, large)
        XCTAssertNil(WalletContext.Collectible(address: "nft", name: "Gift", kind: .gift).image)
    }

    func testCollectibleLottieDataMatchesSubmodule() throws {
        let json = try JSONSerialization.data(withJSONObject: ["v": "5.7", "fr": 60, "layers": []])
        let gzipped = try XCTUnwrap(TGGZipData(json, -1))
        let array = try JSONSerialization.data(withJSONObject: [1, 2, 3])
        let text = Data("not json".utf8)
        let oversized = Data(repeating: 0x20, count: 5 * 1024 * 1024 + 1)
        for data in [json, gzipped, array, text, oversized, Data()] {
            XCTAssertEqual(walletCollectibleLottieData(data), submoduleCollectibleLottieData(data))
        }
        XCTAssertEqual(walletCollectibleLottieData(json), json)
        XCTAssertEqual(walletCollectibleLottieData(gzipped), json)
        XCTAssertNil(walletCollectibleLottieData(array))
        XCTAssertNil(walletCollectibleLottieData(text))
        XCTAssertNil(walletCollectibleLottieData(oversized))
    }

    func testCollectiblePagingMatchesSubmodule() {
        let pageA = collectiblesState(nextOffset: "8").nextPage
        let pageB = collectiblesState(nextOffset: "16").nextPage
        let states = [
            collectiblesState(nextOffset: nil),
            collectiblesState(nextOffset: "8"),
            collectiblesState(nextOffset: "8", isRefreshing: true),
            collectiblesState(nextOffset: "8", isLoadingMore: true),
            collectiblesState(nextOffset: "8", error: .network),
            collectiblesState(nextOffset: "8", generation: 1),
        ]
        let pages: [WalletContext.CollectiblesState.PageId?] = [nil, pageA, pageB]
        var checked = 0
        for state in states {
            for count in [0, 1, 8] {
                for index in [0, 5, 6, 7] where count == 0 || index < count {
                    for requested in pages {
                        for failed in pages {
                            for active in [false, true] {
                                XCTAssertEqual(
                                    walletCollectiblesPageToRequest(index: index, count: count, state: state, requestedPage: requested, failedPage: failed, hasActiveOperation: active),
                                    submoduleRequestLoadMorePage(collectiblesCount: count, index: index, state: state, requestedPage: requested, failedPage: failed, hasActiveOperation: active)
                                )
                                checked += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 300)
    }

    func testCollectiblePagingWaitsForRefreshAndRetriesNewGeneration() {
        let loaded = collectiblesState(nextOffset: "8")
        XCTAssertEqual(walletCollectiblesPageToRequest(index: 7, count: 8, state: loaded, requestedPage: nil, failedPage: nil, hasActiveOperation: false), loaded.nextPage)
        XCTAssertNil(walletCollectiblesPageToRequest(index: 7, count: 8, state: collectiblesState(nextOffset: "8", isRefreshing: true), requestedPage: nil, failedPage: nil, hasActiveOperation: false))
        XCTAssertNil(walletCollectiblesPageToRequest(index: 7, count: 8, state: loaded, requestedPage: loaded.nextPage, failedPage: nil, hasActiveOperation: false))
        let refreshed = collectiblesState(nextOffset: "8", generation: 1)
        XCTAssertNotEqual(refreshed.nextPage, loaded.nextPage)
        XCTAssertEqual(walletCollectiblesPageToRequest(index: 7, count: 8, state: refreshed, requestedPage: loaded.nextPage, failedPage: loaded.nextPage, hasActiveOperation: false), refreshed.nextPage)
    }

    func testOutdatedRecoveryPhraseMessagesMatchSubmodule() {
        let message = walletAuthorizationErrorMessage(.recoveryPhraseOutdated)
        XCTAssertEqual(message?.title, "Secret Phrase Has Changed")
        XCTAssertEqual(message?.text, "The key for this wallet has changed. Enter the current 24-word secret phrase.")
        let backup = walletBackupEnableErrorMessage(.recoveryPhraseOutdated)
        let keyMismatch = walletBackupEnableErrorMessage(.walletKeyMismatch)
        XCTAssertEqual(backup.title, keyMismatch.title)
        XCTAssertEqual(backup.text, keyMismatch.text)
        XCTAssertEqual(backup.text, "This secret phrase may be outdated for your wallet. Enter the current secret phrase to enable backup.")
    }

    func testExplorerDefaultsToTonscanAndHonorsServer() {
        XCTAssertEqual(WalletConfiguration.defaultValue.explorerUrl, "https://tonscan.org")
        XCTAssertEqual(WalletConfiguration.with(appConfiguration: .defaultValue).explorerUrl, "https://tonscan.org")
        var configuration = AppConfiguration.defaultValue
        configuration.data = JSON(dictionary: ["ton_blockchain_explorer_url": "https://tonviewer.com"])
        XCTAssertEqual(WalletConfiguration.with(appConfiguration: configuration).explorerUrl, "https://tonviewer.com")
    }

    func testTransactionExplorerUrlMatchesSubmodule() {
        let bytes = Data((0 ..< 32).map { UInt8(($0 * 37 + 11) % 256) })
        let base64 = bytes.base64EncodedString()
        for explorer in ["https://tonscan.org", "https://tonscan.org/", "https://tonviewer.com"] {
            XCTAssertEqual(walletTransactionExplorerUrl(explorerUrl: explorer, hash: base64), submoduleTransactionExplorerUrl(explorerUrl: explorer, id: base64))
        }
        XCTAssertEqual(walletTransactionExplorerUrl(explorerUrl: "https://tonscan.org", hash: base64), "https://tonscan.org/transaction/" + bytes.map { String(format: "%02x", $0) }.joined())
        XCTAssertNil(walletTransactionExplorerUrl(explorerUrl: "https://tonscan.org", hash: Data(repeating: 1, count: 16).base64EncodedString()))
    }

    func testCollectibleExplorerUrlMatchesSubmodule() {
        for address in ["EQCollectibleAddress_-12", "0:" + String(repeating: "a", count: 64), "has space", ""] {
            for explorer in ["https://tonscan.org", "https://tonscan.org/"] {
                XCTAssertEqual(walletCollectibleExplorerUrl(explorerUrl: explorer, address: address), submoduleCollectibleExplorerUrl(explorerUrl: explorer, address: address))
            }
        }
        XCTAssertEqual(walletCollectibleExplorerUrl(explorerUrl: "https://tonscan.org", address: "EQabc"), "https://tonscan.org/EQabc")
    }

    func testGramIconsMatchSubmoduleAssets() throws {
        let root = repositoryRoot()
        let pairs = [
            ("Telegram-Mac/Assets.xcassets/Wallet_TopGram.imageset/Diamond 22.pdf", "submodules/telegram-ios/submodules/TelegramUI/Images.xcassets/Wallet/TopGram.imageset/Diamond 22.pdf"),
            ("Telegram-Mac/Assets.xcassets/Wallet_TransactionGram.imageset/Diamond 20.pdf", "submodules/telegram-ios/submodules/TelegramUI/Images.xcassets/Wallet/TransactionGram.imageset/Diamond 20.pdf"),
        ]
        for (actual, submodule) in pairs {
            let actualData = try Data(contentsOf: root.appendingPathComponent(actual))
            let submoduleData = try Data(contentsOf: root.appendingPathComponent(submodule))
            XCTAssertEqual(actualData, submoduleData, actual)
        }
        let contents = try String(contentsOf: root.appendingPathComponent("Telegram-Mac/Assets.xcassets/Wallet_TopGram.imageset/Contents.json"))
        XCTAssertTrue(contents.contains("Diamond 22.pdf"))
    }

    func testAmountEditRulesMatchSubmodule() {
        let texts = ["", "0", "0.", "1", "12", "1.5", "1.123456789", "999999999", "12.34", "100"]
        let replacements = ["0", "1", "5", ".", ",", "a", "12abc", "٣", "", "00", "1.2", "-1", "+5", " "]
        var checked = 0
        for separator in [".", ","] {
            for (mode, rate) in [(WalletSendInputMode.gram, nil), (.fiat, 2.0), (.fiat, nil)] as [(WalletSendInputMode, Double?)] {
                for rawText in texts {
                    let text = rawText.replacingOccurrences(of: ".", with: separator)
                    let length = (text as NSString).length
                    var ranges = [NSRange(location: length, length: 0), NSRange(location: 0, length: 0), NSRange(location: 0, length: length)]
                    if length > 0 {
                        ranges.append(NSRange(location: length - 1, length: 1))
                    }
                    for range in ranges {
                        for replacement in replacements {
                            let actual = walletSendReplacingAmountText(text, range: range, replacement: replacement, mode: mode, rate: rate, decimalSeparator: separator)
                            let submodule = submoduleReplacingAmountText(text, range: range, replacement: replacement, mode: mode, rate: rate, decimalSeparator: separator)
                            XCTAssertEqual(actual?.text, submodule?.text, "\(text) \(range) \(replacement) \(mode)")
                            XCTAssertEqual(actual?.selection, submodule?.selection, "\(text) \(range) \(replacement) \(mode)")
                            checked += 1
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 2000)
    }

    func testAmountRejectionsThatShakeLikeSubmodule() {
        func append(_ text: String, _ replacement: String, mode: WalletSendInputMode = .gram, rate: Double? = nil) -> String? {
            return walletSendReplacingAmountText(text, range: NSRange(location: (text as NSString).length, length: 0), replacement: replacement, mode: mode, rate: rate, decimalSeparator: ".")?.text
        }
        XCTAssertNil(append("1.123456789", "1"))
        XCTAssertNil(append("1.5", "."))
        XCTAssertNil(append("12", "a"))
        XCTAssertNil(append("", "12abc"))
        XCTAssertNil(append("999999999", "9"))
        XCTAssertNil(append("1.23", "4", mode: .fiat, rate: 2))
        XCTAssertNil(append("", "1", mode: .fiat, rate: nil))
        XCTAssertEqual(append("", "0"), "0.")
        XCTAssertEqual(append("", "."), "0.")
        XCTAssertEqual(append("", ","), "0.")
        XCTAssertEqual(append("", "٣"), "3")
        XCTAssertEqual(append("0.", "5"), "0.5")
        XCTAssertEqual(append("1.12345678", "9"), "1.123456789")
    }

    func testAmountEditOutcomesMatchSubmodule() {
        let texts = ["", "0", "0.", "1", "1.", "12", "1.5", "0.5", "1.123456789", "999999999", "12.34", "100"]
        let replacements = ["0", "1", "5", ".", ",", "٫", "a", "12abc", "٣", "", "00", "1.2", ".5", "-1", " "]
        var checked = 0
        var ignored = 0
        for separator in [".", ","] {
            for (mode, rate) in [(WalletSendInputMode.gram, nil), (.fiat, 2.0), (.fiat, nil)] as [(WalletSendInputMode, Double?)] {
                for rawText in texts {
                    let text = rawText.replacingOccurrences(of: ".", with: separator)
                    let length = (text as NSString).length
                    var ranges = [NSRange(location: length, length: 0), NSRange(location: 0, length: 0), NSRange(location: 0, length: length)]
                    if length > 0 {
                        ranges.append(NSRange(location: length - 1, length: 1))
                    }
                    for range in ranges {
                        for replacement in replacements {
                            if replacement.isEmpty && range.length == 0 {
                                continue
                            }
                            let actual = actualAmountEditOutcome(text, range: range, string: replacement, mode: mode, rate: rate, decimalSeparator: separator)
                            let submodule = submoduleReplaceText(text, range: range, string: replacement, mode: mode, rate: rate, decimalSeparator: separator)
                            XCTAssertEqual(actual, submodule, "\(text) \(range) \(replacement) \(mode)")
                            if actual == .ignored {
                                ignored += 1
                            }
                            checked += 1
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 2000)
        XCTAssertGreaterThan(ignored, 0)
    }

    func testSecondSeparatorAfterZeroIsIgnoredLikeSubmodule() {
        func outcome(_ text: String, _ replacement: String, at location: Int? = nil, separator: String = ".") -> SubmoduleAmountReplaceOutcome {
            let range = NSRange(location: location ?? (text as NSString).length, length: 0)
            let actual = actualAmountEditOutcome(text, range: range, string: replacement, mode: .gram, rate: nil, decimalSeparator: separator)
            XCTAssertEqual(actual, submoduleReplaceText(text, range: range, string: replacement, mode: .gram, rate: nil, decimalSeparator: separator), "\(text) \(replacement)")
            return actual
        }
        XCTAssertEqual(outcome("0.", "."), .ignored)
        XCTAssertEqual(outcome("0.", ","), .ignored)
        XCTAssertEqual(outcome("0,", ",", separator: ","), .ignored)
        XCTAssertEqual(outcome("0,", ".", separator: ","), .ignored)
        XCTAssertEqual(outcome("0.", "٫"), .rejected)
        XCTAssertEqual(outcome("0.", ".", at: 0), .rejected)
        XCTAssertEqual(outcome("0.", ".", at: 1), .rejected)
        XCTAssertEqual(outcome("1.", "."), .rejected)
        XCTAssertEqual(outcome("0.5", "."), .rejected)
        XCTAssertEqual(outcome("", "."), .accepted("0.", NSRange(location: 2, length: 0)))
        XCTAssertEqual(outcome("0.", "5"), .accepted("0.5", NSRange(location: 3, length: 0)))
    }

    func testSubmoduleAmountFieldStillIgnoresTheSecondSeparator() throws {
        let source = compactSource(try String(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletSendScreen/Sources/WalletSendAmountField.swift"), encoding: .utf8))
        let ignore = try XCTUnwrap(source.range(of: #"if text == "0" + dateTimeFormat.decimalSeparator, range.location == length, range.length == 0, string == dateTimeFormat.decimalSeparator || string == "." || string == "," { return false }"#))
        let guardRange = try XCTUnwrap(source.range(of: "!string.isEmpty || range.length > 0 else { return false }"))
        let replace = try XCTUnwrap(source.range(of: "guard let edit = walletSendReplacingAmountText( text, range: range, replacement: string,"))
        XCTAssertLessThan(guardRange.upperBound, ignore.lowerBound)
        XCTAssertLessThan(ignore.upperBound, replace.lowerBound)
        XCTAssertTrue(source[replace.upperBound...].hasPrefix(" mode: self.mode, rate: self.rate, decimalSeparator: dateTimeFormat.decimalSeparator ) else { self.inputRejected() return false }"))
    }

    func testCardBalanceTextMatchesSubmodule() {
        let separator = Locale.current.decimalSeparator ?? "."
        let balances: [Int64] = [0, 1, 4_999_999, 5_000_000, 9_999_999, 10_000_000, 990_000_000, 1_000_000_000, 1_004_000_000, 1_050_000_000, 1_500_000_000, 1_234_567_890, 5_000_000_000, 999_990_000_000, 1_000_000_000_000, 123_456_789_000_000_000]
        for balance in balances {
            let actual = splitWalletBalanceText(balance)
            let submodule = submoduleCardBalanceText(balance: balance, formattedBalance: formatTonAmountText(balance, maxDecimalPositions: 2), decimalSeparator: separator)
            XCTAssertEqual(actual.integral, submodule.integral, "\(balance)")
            XCTAssertEqual(actual.fractional, submodule.fractional, "\(balance)")
        }
        XCTAssertEqual(splitWalletBalanceText(5_000_000_000).fractional, "")
        XCTAssertEqual(splitWalletBalanceText(1_000_000_000_000).fractional, "")
        XCTAssertEqual(splitWalletBalanceText(1_500_000_000).fractional, separator + "5")
        XCTAssertEqual(splitWalletBalanceText(0).fractional, "")
    }

    func testSubmoduleCardStillDropsTheFractionForWholeBalances() throws {
        let source = compactSource(try String(contentsOf: repositoryRoot().appendingPathComponent("submodules/telegram-ios/submodules/TelegramUI/Components/Wallet/WalletCardComponent/Sources/WalletCardComponent.swift"), encoding: .utf8))
        XCTAssertTrue(source.contains(#"if component.balance == nil || component.balance == 0 { integralText = formattedBalance fractionalText = "" } else if let decimalRange = formattedBalance.range(of: component.dateTimeFormat.decimalSeparator) { integralText = String(formattedBalance[..<decimalRange.lowerBound]) fractionalText = String(formattedBalance[decimalRange.lowerBound...]) } else { integralText = formattedBalance fractionalText = "" }"#))
        XCTAssertTrue(source.contains("formatTonAmountText( balance, dateTimeFormat: component.dateTimeFormat, maxDecimalPositions: 2 )"))
    }

    func testNanogramsMatchSubmodule() {
        let inputs = ["", "0", "1", "1.5", "0.000000001", "1.0000000001", "9223372036", "9223372037", "-1", "+5", " 1", "1.2.3", "٣", ".5", "5.", "12abc", "1e3"]
        for separator in [".", ","] {
            for input in inputs {
                let text = input.replacingOccurrences(of: ".", with: separator)
                for (mode, rate) in [(WalletSendInputMode.gram, nil), (.fiat, 2.0), (.fiat, nil), (.fiat, 0)] as [(WalletSendInputMode, Double?)] {
                    XCTAssertEqual(walletSendNanograms(text: text, mode: mode, rate: rate, decimalSeparator: separator), submoduleNanograms(text: text, mode: mode, rate: rate, decimalSeparator: separator), "\(text) \(mode)")
                }
            }
        }
    }

    func testPreviewAmountMatchesSubmodule() {
        for prepared in [nil, Int64(700)] as [Int64?] {
            for amount in [Int64(0), 500, 1_000] {
                for sendAll in [false, true] {
                    for fee in [nil, Int64(0), 300, 2_000] as [Int64?] {
                        XCTAssertEqual(walletPreviewAmount(preparedAmount: prepared, amount: amount, sendAll: sendAll, displayedFee: fee), submodulePreviewAmount(preparedAmount: prepared, amount: amount, isSendAll: sendAll, displayedFee: fee))
                    }
                }
            }
        }
        XCTAssertEqual(walletPreviewAmount(preparedAmount: nil, amount: 137_000_000_000, sendAll: true, displayedFee: 3_100_000), 136_996_900_000)
    }

    func testPreviewGaslessMatchesSubmodule() {
        let infos: [WalletGaslessInfo?] = [nil, gaslessInfo(), gaslessInfo(left: 0)]
        for isSelf in [false, true] {
            for sendAll in [false, true] {
                for prepared in [false, true] {
                    for fee in [nil, Int64(3_100_000)] as [Int64?] {
                        for amount in [Int64(500_000_000), 2_000_000_000] {
                            for info in infos {
                                XCTAssertEqual(
                                    walletPreviewGasless(isSelfTransfer: isSelf, isSendAll: sendAll, isPrepared: prepared, displayedFee: fee, amount: amount, gaslessInfo: info, minimumAmount: 100_000_000),
                                    submodulePreviewGasless(isCollectible: false, isSelfTransfer: isSelf, isSendAll: sendAll, isPrepared: prepared, displayedFee: fee, amount: amount, gaslessInfo: info, minimumAmount: 100_000_000)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func testTransactionFeeRowsMatchSubmodule() {
        for isPreview in [false, true] {
            for displayed in [nil, Int64(0), 3_100_000] as [Int64?] {
                for transactionFee in [Int64(0), 3_100_000] {
                    for isSelf in [false, true] {
                        for isOutgoing in [false, true] {
                            for gasless in [false, true] {
                                XCTAssertEqual(
                                    actualFeeRows(walletTransactionFeeDisplay(isPreview: isPreview, displayedFee: displayed, transactionFee: transactionFee, isSelfTransfer: isSelf, isOutgoing: isOutgoing, gasless: gasless)),
                                    submoduleFeeRows(isPreview: isPreview, displayedFee: displayed, transactionFee: transactionFee, isSelfTransfer: isSelf, isOutgoing: isOutgoing, gasless: gasless),
                                    "preview \(isPreview) displayed \(String(describing: displayed)) fee \(transactionFee) self \(isSelf) out \(isOutgoing) gasless \(gasless)"
                                )
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(walletTransactionFeeDisplay(isPreview: true, displayedFee: 3_100_000, transactionFee: 0, isSelfTransfer: false, isOutgoing: true, gasless: true), .none)
        XCTAssertEqual(walletTransactionFeeDisplay(isPreview: false, displayedFee: nil, transactionFee: 0, isSelfTransfer: false, isOutgoing: true, gasless: true), .free)
    }

    func testPreviewBalanceCheckMatchesSubmodule() {
        for balance in [nil, Int64(0), 500, 1_000] as [Int64?] {
            for requested in [Int64(0), 500, 1_000, 1_500] {
                for sendAll in [false, true] {
                    XCTAssertEqual(walletPreviewBalanceError(balance: balance, requestedAmount: requested, sendAll: sendAll), submoduleBalanceError(balance: balance, requestedAmount: requested, sendAll: sendAll))
                }
            }
        }
        XCTAssertEqual(walletPreviewBalanceError(balance: 400, requestedAmount: 500, sendAll: false), .insufficientBalance(required: 500))
        XCTAssertEqual(walletPreviewBalanceError(balance: 400, requestedAmount: 500, sendAll: true), .insufficientBalance(required: 500))
        XCTAssertEqual(walletPreviewBalanceError(balance: 600, requestedAmount: 500, sendAll: true), .previewFailed)
        XCTAssertNil(walletPreviewBalanceError(balance: 500, requestedAmount: 500, sendAll: true))
    }

    func testInitialFeeIsTheCurrentEstimateOnly() {
        var state = WalletSendState()
        state.amount = 500_000_000
        state.balance = 137_000_000_000
        state.isLoading = false
        state.gaslessInfo = gaslessInfo()
        state.gaslessMinAmount = 100_000_000
        state.walletPhase = .wallet(.init(address: walletAddress, publicKey: "key"))
        state.walletAddress = walletAddress
        state.resolved = .init(address: otherAddress, displayName: nil)
        let request = walletSendFeeRequest(state)
        XCTAssertNotNil(request)
        state.feeEstimate = WalletSendFeeEstimate(request: request!, fee: 3_100_000)
        XCTAssertEqual(walletSendInitialFee(state), 3_100_000)
        state.amount = 600_000_000
        XCTAssertEqual(walletSendInitialFee(state), 3_100_000)
        state.amount = 2_000_000_000
        XCTAssertEqual(walletSendInitialFee(state), 3_100_000)
        state.comment = "Dinner"
        XCTAssertNil(walletSendInitialFee(state))
        state.comment = nil
        state.resolved = .init(address: walletAddress, displayName: nil)
        XCTAssertNil(walletSendInitialFee(state))
        state.resolved = .init(address: otherAddress, displayName: nil)
        state.feeEstimate = nil
        XCTAssertNil(walletSendInitialFee(state))
    }

    func testConfirmationFeeWhenOpenedMatchesSubmodule() {
        struct Scenario {
            let amount: Int64
            let isSelf: Bool
            let sendAll: Bool
        }
        let balance: Int64 = 137_000_000_000
        let cachedFee: Int64 = 3_100_000
        let scenarios = [
            Scenario(amount: 500_000_000, isSelf: false, sendAll: false),
            Scenario(amount: 2_000_000_000, isSelf: false, sendAll: false),
            Scenario(amount: 2_000_000_000, isSelf: true, sendAll: false),
            Scenario(amount: balance, isSelf: false, sendAll: true),
            Scenario(amount: balance, isSelf: true, sendAll: true),
        ]
        for scenario in scenarios {
            var state = WalletSendState()
            state.amount = scenario.amount
            state.balance = balance
            state.isLoading = false
            state.gaslessInfo = gaslessInfo()
            state.gaslessMinAmount = 100_000_000
            state.walletPhase = .wallet(.init(address: walletAddress, publicKey: "key"))
            state.walletAddress = walletAddress
            state.resolved = .init(address: scenario.isSelf ? walletAddress : otherAddress, displayName: nil)
            XCTAssertEqual(walletSendIsSelfTransfer(state), scenario.isSelf)
            if let request = walletSendFeeRequest(state) {
                state.feeEstimate = WalletSendFeeEstimate(request: request, fee: cachedFee)
            }
            let actualInitialFee = walletSendInitialFee(state)
            XCTAssertEqual(actualInitialFee, cachedFee, "amount \(scenario.amount) self \(scenario.isSelf) sendAll \(scenario.sendAll)")
            let actualAmount = walletPreviewAmount(preparedAmount: nil, amount: scenario.amount, sendAll: scenario.sendAll, displayedFee: actualInitialFee)
            let actualGasless = walletPreviewGasless(isSelfTransfer: scenario.isSelf, isSendAll: scenario.sendAll, isPrepared: false, displayedFee: actualInitialFee, amount: actualAmount, gaslessInfo: state.gaslessInfo, minimumAmount: 100_000_000)
            let actualRows = actualFeeRows(walletTransactionFeeDisplay(isPreview: true, displayedFee: actualInitialFee, transactionFee: actualInitialFee ?? 0, isSelfTransfer: scenario.isSelf, isOutgoing: true, gasless: actualGasless))

            let submoduleAmount = submodulePreviewAmount(preparedAmount: nil, amount: scenario.amount, isSendAll: scenario.sendAll, displayedFee: cachedFee)
            let submoduleGasless = submodulePreviewGasless(isCollectible: false, isSelfTransfer: scenario.isSelf, isSendAll: scenario.sendAll, isPrepared: false, displayedFee: cachedFee, amount: submoduleAmount, gaslessInfo: state.gaslessInfo, minimumAmount: 100_000_000)
            let submoduleRows = submoduleFeeRows(isPreview: true, displayedFee: cachedFee, transactionFee: cachedFee, isSelfTransfer: scenario.isSelf, isOutgoing: true, gasless: submoduleGasless)

            XCTAssertEqual(actualRows, submoduleRows, "amount \(scenario.amount) self \(scenario.isSelf) sendAll \(scenario.sendAll)")
            XCTAssertEqual(actualAmount, submoduleAmount)
        }
    }

    private func userId(_ value: Int64) -> EnginePeer.Id {
        return EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(value))
    }

    func testTypedRecipientRoutesByModeLikeSubmodule() {
        let collectible = WalletContext.Collectible(address: "nft", name: "Gift", kind: .gift, nft: nft(image: nil, imageSmall: nil, lottie: nil))
        let recipients = [
            WalletContext.ResolvedTransferRecipient(address: otherAddress, displayName: nil),
            WalletContext.ResolvedTransferRecipient(address: otherAddress, displayName: "alice.ton"),
            WalletContext.ResolvedTransferRecipient(address: otherAddress, displayName: nil, transferLink: "ton://transfer/\(otherAddress)?amount=1")
        ]
        for recipient in recipients {
            XCTAssertEqual(actualRoute(walletRecipientDestination(mode: .collectible(collectible), address: recipient.address, publicKey: nil)), submoduleOpenRecipient(recipient, mode: .collectible(collectible)))
            if recipient.transferLink == nil {
                XCTAssertEqual(actualRoute(walletRecipientDestination(mode: .transfer, address: recipient.address, publicKey: nil)), submoduleOpenRecipient(recipient, mode: .transfer))
            }
        }
        let publicKey = Data([1, 2, 3])
        XCTAssertEqual(walletRecipientDestination(mode: .transfer, address: otherAddress, publicKey: publicKey), .send(address: otherAddress, publicKey: publicKey))
    }

    func testCollectiblePeerSelectionMatchesSubmodule() {
        let collectible = WalletContext.Collectible(address: "nft", name: "Gift", kind: .gift, nft: nft(image: nil, imageSmall: nil, lottie: nil))
        let alice = userId(1)
        let bob = userId(2)
        let key = Data([7])
        let scenarios: [[WalletUserAddress]] = [
            [],
            [WalletUserAddress(userId: bob, address: otherAddress, publicKey: key)],
            [WalletUserAddress(userId: alice, address: otherAddress, publicKey: key)],
            [WalletUserAddress(userId: alice, address: "  \(otherAddress)\n", publicKey: Data())],
            [WalletUserAddress(userId: alice, address: " \n", publicKey: key)],
            [WalletUserAddress(userId: alice, address: "not-an-address", publicKey: key)],
            [WalletUserAddress(userId: bob, address: walletAddress, publicKey: key), WalletUserAddress(userId: alice, address: otherAddress, publicKey: key), WalletUserAddress(userId: alice, address: walletAddress, publicKey: key)]
        ]
        for addresses in scenarios {
            let actual = actualRoute(walletRecipientPeerAddress(addresses, peerId: alice).map { walletRecipientDestination(mode: .collectible(collectible), address: $0, publicKey: nil) })
            let submodule = submoduleCollectiblePeerSelected(addresses: addresses, peerId: alice, displayName: "Alice", collectible: collectible)
            XCTAssertEqual(actual, submodule, "\(addresses)")
        }
    }

    private func recipientPeer() -> EnginePeer {
        return .legacyGroup(TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(1)), title: "Alice", photo: [], participantCount: 1, role: .creator(rank: nil), membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0))
    }

    func testSendRecipientResolutionMatchesSubmodule() {
        let alice = userId(1)
        let normalized = WalletContext.transferAddress(from: otherAddress)!
        let outcomes: [WalletUserAddress?] = [nil, WalletUserAddress(userId: alice, address: " \n", publicKey: Data()), WalletUserAddress(userId: alice, address: otherAddress, publicKey: Data([7]))]
        for outcome in outcomes {
            var resolution = SubmoduleSendPeerAddressResolution()
            resolution.reset(resolvedAddress: nil)
            var state = WalletSendState()
            state.selectedPeer = recipientPeer()
            state.isResolving = true
            state.balance = 10_000_000_000
            state.isLoading = false

            XCTAssertEqual(walletSendRecipientIsLoading(state), submoduleSendRecipientIsLoading(recipientAddress: "", resolution: resolution.state))
            let generation = resolution.begin()!
            XCTAssertEqual(walletSendRecipientIsLoading(state), submoduleSendRecipientIsLoading(recipientAddress: "", resolution: resolution.state))
            XCTAssertEqual(walletRecipientAddressText(address: nil, hasPeer: true, isLoading: walletSendRecipientIsLoading(state)), submoduleSendRecipientAddressText(address: "", hasPeer: true, isLoading: true))
            state.amount = 1_000_000_000
            XCTAssertFalse(walletCanSend(state))

            XCTAssertTrue(resolution.complete(generation: generation, recipient: outcome))
            state.isResolving = false
            if let recipient = resolution.recipient {
                state.resolved = WalletContext.ResolvedTransferRecipient(address: WalletContext.transferAddress(from: recipient.address)!, displayName: "Alice")
                XCTAssertEqual(state.resolved?.address, normalized)
            }
            let submoduleAddress = resolution.recipient?.address ?? ""
            let isLoading = walletSendRecipientIsLoading(state)
            XCTAssertEqual(isLoading, submoduleSendRecipientIsLoading(recipientAddress: submoduleAddress, resolution: resolution.state), "\(String(describing: outcome))")
            XCTAssertEqual(walletRecipientAddressText(address: state.resolved?.address, hasPeer: true, isLoading: isLoading) == "—", submoduleSendRecipientAddressText(address: submoduleAddress, hasPeer: true, isLoading: isLoading) == "—")
            XCTAssertEqual(!isLoading && state.resolved != nil, submoduleSendCanOpenRecipientInfo(address: submoduleAddress, isLoading: isLoading))
            XCTAssertEqual(walletCanSend(state), resolution.state == .resolved)
        }
    }

    func testSendFeeWithoutRecipientMatchesSubmodule() {
        let covered = WalletGaslessInfo(available: true, left: 5, resetAt: 0, minAmount: 1_000_000_000, relayerAddress: otherAddress)
        let notCovered = WalletGaslessInfo(available: false, left: 0, resetAt: 0, minAmount: 1_000_000_000, relayerAddress: otherAddress)
        let resolutions: [(isResolving: Bool, submodule: SubmoduleSendPeerAddressResolution.State)] = [(true, .loading), (false, .failed)]
        for resolution in resolutions {
            for amount: Int64 in [0, 500_000_000, 2_000_000_000, 10_000_000_000] {
                for info in [nil, covered, notCovered] {
                    for walletIsLoading in [false, true] {
                        var state = WalletSendState()
                        state.selectedPeer = recipientPeer()
                        state.isResolving = resolution.isResolving
                        state.amount = amount
                        state.balance = 10_000_000_000
                        state.isLoading = walletIsLoading
                        state.gaslessInfo = info
                        state.gaslessMinAmount = 1_000_000_000
                        let submodule = submoduleSendFeeDisplayWithoutRecipient(amount: amount, shouldSendAll: walletShouldSendAll(state), gaslessInfo: info, minimumAmount: 1_000_000_000, resolution: resolution.submodule, walletIsLoading: walletIsLoading)
                        XCTAssertEqual(actualSendFeeDisplay(walletSendFeeDisplay(state)), submodule, "amount \(amount) info \(String(describing: info)) loading \(walletIsLoading) \(resolution.submodule)")
                    }
                }
            }
        }
    }

    func testWalletAccentUsesDefaultThemeAccentLikeSubmodule() {
        let palettes: [ColorPalette] = [whitePalette, dayClassicPalette, darkPalette, nightAccentPalette]
        for palette in palettes {
            let expected: NSColor
            switch submoduleDefaultAccent(for: palette.parent, isDark: palette.isDark) {
            case .day:
                expected = dayClassicPalette.accent
            case .night:
                expected = darkPalette.accent
            case .nightTinted:
                expected = nightAccentPalette.accent
            }
            XCTAssertEqual(walletDefaultAccent(for: palette).hexString, expected.hexString, palette.name)
            XCTAssertEqual(walletDefaultAccent(for: palette.withAccentColor(PaletteAccentColor(NSColor(0xff5ea5)))).hexString, expected.hexString, palette.name)
        }
    }

    func testWalletAlertsUseDefaultThemeAccentLikeSubmodule() {
        let palettes: [ColorPalette] = [whitePalette, dayClassicPalette, darkPalette, nightAccentPalette]
        for palette in palettes {
            let userPalette = palette.withAccentColor(PaletteAccentColor(NSColor(0xff5ea5)))
            let expected: NSColor
            switch submoduleDefaultAccent(for: palette.parent, isDark: palette.isDark) {
            case .day:
                expected = dayClassicPalette.accent
            case .night:
                expected = darkPalette.accent
            case .nightTinted:
                expected = nightAccentPalette.accent
            }
            let alertPalette = walletAlertPalette(userPalette)
            for color in [alertPalette.accent, alertPalette.link, alertPalette.accentIcon, alertPalette.accentSelect] {
                XCTAssertEqual(color.hexString, expected.hexString, palette.name)
            }
            XCTAssertEqual(alertPalette.background.hexString, userPalette.background.hexString, palette.name)
            XCTAssertEqual(alertPalette.listBackground.hexString, userPalette.listBackground.hexString, palette.name)
            XCTAssertEqual(alertPalette.text.hexString, userPalette.text.hexString, palette.name)
            XCTAssertEqual(alertPalette.isDark, userPalette.isDark, palette.name)
        }
    }

    func testGramColorFollowsTheAppearanceLikeSubmodule() {
        let palettes: [ColorPalette] = [whitePalette, dayClassicPalette, darkPalette, nightAccentPalette]
        for palette in palettes {
            let expected = NSColor(rgb: submoduleGramColor(overallDarkAppearance: palette.isDark))
            XCTAssertEqual(walletGramColor(for: palette).hexString, expected.hexString, palette.name)
            XCTAssertEqual(walletGramColor(for: palette.withAccentColor(PaletteAccentColor(NSColor(0xff5ea5)))).hexString, expected.hexString, palette.name)
        }
    }

    private func submoduleLocalizedStrings() throws -> [String: String] {
        let url = repositoryRoot().appendingPathComponent("submodules/telegram-ios/Telegram/Telegram-iOS/en.lproj/Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    func testLogoutConfirmationTextMatchesSubmodule() throws {
        let strings = try submoduleLocalizedStrings()
        XCTAssertNotNil(strings["Settings.LogoutConfirmationTextWithWallets"])
        let defaultText = "Remember, logging out cancels all your Secret Chats."
        XCTAssertEqual(walletLogoutConfirmationText(balance: nil, defaultText: defaultText), defaultText)
        let balances: [Int64] = [0, 1, 40_000_000, 50_000_000, 99_999_999, 100_000_000, 999_999_999, 1_000_000_000, 1_049_999_999, 1_050_000_000, 1_250_000_000, 2_000_000_000, 12_345_600_000_000, 1_234_567_890_123, Int64.max]
        for balance in balances {
            let expected = submoduleLogoutConfirmationText(balance: balance, strings: strings, defaultText: defaultText, decimalSeparator: walletDecimalSeparator, groupingSeparator: walletGroupingSeparator)
            XCTAssertEqual(walletLogoutConfirmationText(balance: balance, defaultText: defaultText), expected, "\(balance)")
        }
    }

    func testLogoutConfirmationTextNeedsAvailableWallet() {
        var available = AppConfiguration.defaultValue
        available.data = .dictionary(["wallet_available": .bool(true)])
        XCTAssertTrue(WalletConfiguration.with(appConfiguration: available).isAvailable)
        XCTAssertFalse(WalletConfiguration.with(appConfiguration: .defaultValue).isAvailable)
        for configuration in [AppConfiguration.defaultValue, available] {
            var values: [String] = []
            _ = walletLogoutConfirmationText(walletContext: nil, appConfiguration: configuration, defaultText: "default").start(next: { values.append($0) })
            XCTAssertEqual(values, ["default"])
        }
    }

    func testTransactionOpenActionsMatchSubmodule() {
        let directions: [WalletContext.Transaction.Direction] = [.incoming, .outgoing, .unknown]
        let currencies: [WalletContext.Transaction.Currency] = [.ton, .usdt]
        let collectibles: [WalletContext.Transaction.CollectibleTransfer?] = [nil, WalletContext.Transaction.CollectibleTransfer(address: "nft", name: "Gift", image: nil, kind: .gift)]
        let comments: [String?] = [nil, "", "Dinner"]
        var checked = 0
        for direction in directions {
            for currency in currencies {
                for collectible in collectibles {
                    for comment in comments {
                        for commentEncrypted in [false, true] {
                            for decryptCommentOnOpen in [false, true] {
                                let transaction = WalletContext.Transaction(id: "1", logicalTime: "1", timestamp: 0, direction: direction, amount: 1_000_000_000, fee: 0, peer: .address(otherAddress, domain: nil), comment: comment, commentEncrypted: commentEncrypted, currency: currency, collectible: collectible)
                                let actual = walletTransactionOpenActions(subject: .transaction(transaction), decryptCommentOnOpen: decryptCommentOnOpen)
                                let label = "\(direction) \(currency) \(collectible != nil) \(String(describing: comment)) \(commentEncrypted) \(decryptCommentOnOpen)"
                                XCTAssertEqual(actual.decryptComment, submoduleHasPendingCommentDecryption(transaction, decryptCommentOnOpen: decryptCommentOnOpen), label)
                                XCTAssertEqual(actual.checkFirstIncomingTransfer, submoduleCheckFirstGramsOnAppear(transaction, decryptCommentOnOpen: decryptCommentOnOpen), label)
                                checked += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(checked, 144)
        for decryptCommentOnOpen in [false, true] {
            let preview = walletTransactionOpenActions(subject: .preview(address: otherAddress, amount: 1, sendAll: false, comment: "Dinner", initialFee: nil), decryptCommentOnOpen: decryptCommentOnOpen)
            XCTAssertEqual(preview, WalletTransactionOpenActions(decryptComment: false, checkFirstIncomingTransfer: false))
        }
    }

    func testAmountFieldSizesAreTheSubmoduleSizesAtTheFieldScale() {
        let scale = walletAmountMainFontSize / submoduleAmountIntegralFontSize
        XCTAssertEqual(walletAmountFieldScale, scale)
        XCTAssertEqual(walletAmountInteractiveDiamondCanvas, submoduleGramAnimationSide * scale, accuracy: 1e-9)
        XCTAssertEqual(walletAmountInteractiveDiamondWidth, submoduleDiamondWidth * scale, accuracy: 1e-9)
        XCTAssertEqual(walletAmountInteractiveDiamondNudge, submoduleDiamondNudge * scale, accuracy: 1e-9)
        XCTAssertEqual(walletAmountFiatSymbolFontSize, submoduleFiatSymbolFontSize * scale, accuracy: 1e-9)
        XCTAssertEqual(walletAmountFiatSymbolGap, submoduleFiatSymbolGap * scale, accuracy: 1e-9)
        XCTAssertEqual(walletAmountFiatSymbolOpticalShift, submoduleFiatSymbolOpticalShift * scale, accuracy: 1e-9)
        XCTAssertEqual(walletAmountSymbolDrop, submoduleSymbolDrop * scale, accuracy: 1e-9)
        XCTAssertEqual(walletAmountSymbolBlur, submoduleSymbolBlur * scale, accuracy: 1e-9)
    }

    func testAmountSpinVelocityMatchesSubmodule() {
        let inputs = ["", "0", "1", "5", "9", ".", ",", "a", "12", "90", "1.5", "٣", " "]
        for input in inputs {
            XCTAssertEqual(walletAmountSpinVelocity(input), submoduleSpinVelocity(input), "\(input)")
        }
    }

    func testAmountMotionTimingMatchesSubmodule() {
        let start = 100.0
        let timing = WalletSendAmountMotionTiming(spin: true, up: true, start: start)
        XCTAssertEqual(timing.duration, timing.reduced ? 0.15 : submoduleSwitchingDuration)
        for step in 0 ... 40 {
            let time = start - 0.1 + Double(step) * 0.02
            let expected = submoduleMotionEase(min(1, max(0, (time - start) / timing.duration)))
            XCTAssertEqual(timing.layoutProgress(at: time), expected, accuracy: 1e-12)
        }
    }

    func testAmountSymbolTransitionMatchesSubmodule() {
        let scale = walletAmountFieldScale
        let start = 50.0
        let timing = WalletSendAmountMotionTiming(spin: true, up: false, start: start)
        var checked = 0
        for toGram in [true, false] {
            var actual = WalletAmountSymbolTransition(timing: timing, toGram: toGram)
            var submodule = SubmoduleSymbolTransition(start: start, duration: timing.duration, reduced: timing.reduced, toGram: toGram)
            XCTAssertEqual(actual.duration, submodule.totalDuration, accuracy: 1e-12)
            for interrupted in [false, true] {
                if interrupted {
                    let from = SubmoduleSymbolState(drop: 7.0, tilt: 0.12, blur: 2.0, alpha: 0.4)
                    submodule.gramFrom = from
                    submodule.fiatFrom = SubmoduleSymbolState(drop: 3.0, tilt: -0.05, blur: 1.0, alpha: 0.6)
                    actual.gramFrom = WalletAmountSymbolState(drop: 7.0 * scale, tilt: 0.12, blur: 2.0 * scale, alpha: 0.4)
                    actual.fiatFrom = WalletAmountSymbolState(drop: 3.0 * scale, tilt: -0.05, blur: 1.0 * scale, alpha: 0.6)
                }
                for gram in [true, false] {
                    for step in 0 ... 120 {
                        let time = start + submodule.totalDuration * Double(step) / 100.0 - 0.05
                        let a = actual.state(gram: gram, at: time)
                        let e = submodule.state(gram: gram, at: time)
                        let label = "toGram \(toGram) interrupted \(interrupted) gram \(gram) t \(time - start)"
                        XCTAssertEqual(a.drop, e.drop * scale, accuracy: 1e-9, label)
                        XCTAssertEqual(a.tilt, e.tilt, accuracy: 1e-12, label)
                        XCTAssertEqual(a.blur, e.blur * scale, accuracy: 1e-9, label)
                        XCTAssertEqual(a.alpha, e.alpha, accuracy: 1e-12, label)
                        checked += 1
                    }
                }
            }
        }
        XCTAssertEqual(checked, 968)
    }

    func testAmountSymbolTransformMatchesSubmoduleOrder() {
        let state = WalletAmountSymbolState(drop: 5.0, tilt: 0.3, blur: 0.0, alpha: 1.0)
        var expected = CATransform3DIdentity
        expected = CATransform3DRotate(expected, 0.3, 0.0, 0.0, 1.0)
        expected = CATransform3DTranslate(expected, 0.0, 5.0, 0.0)
        XCTAssertTrue(CATransform3DEqualToTransform(state.transform, expected))
    }

    func testAmountSymbolPulseMatchesSubmodule() {
        for fromScale: CGFloat in [1.0, 1.03, 1.08, 1.14] {
            for step in 0 ... 51 {
                let t = CGFloat(step) / 51.0
                XCTAssertEqual(walletAmountPulseScale(t, fromScale: fromScale), submodulePulseScale(t, fromScale: fromScale), accuracy: 1e-12)
            }
        }
        XCTAssertEqual(walletAmountPulseScale(0, fromScale: 1), 1, accuracy: 1e-12)
        XCTAssertEqual(walletAmountPulseScale(1, fromScale: 1.1), 1, accuracy: 1e-12)
    }

    func testCenteredTransformMatchesACenterAnchoredLayer() {
        let size = CGSize(width: 68.0, height: 40.0)
        let position = CGPoint(x: 30.0, y: 12.0)
        let transforms = [
            CATransform3DMakeScale(1.14, 1.14, 1.0),
            CATransform3DTranslate(CATransform3DRotate(CATransform3DIdentity, 0.25, 0, 0, 1), 0.0, 11.3, 0.0)
        ]
        let cornerLayer = CALayer()
        cornerLayer.anchorPoint = .zero
        cornerLayer.bounds = CGRect(origin: .zero, size: size)
        let centerLayer = CALayer()
        centerLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        centerLayer.bounds = CGRect(origin: .zero, size: size)
        for transform in transforms {
            let centered = walletAmountCenteredTransform(transform, layer: cornerLayer)
            XCTAssertTrue(CATransform3DEqualToTransform(walletAmountCenteredTransform(transform, layer: centerLayer), transform))
            for point in [CGPoint.zero, CGPoint(x: 34, y: 20), CGPoint(x: 68, y: 40), CGPoint(x: 5, y: 33)] {
                let corner = submoduleApply(centered, point)
                let cornerInSuperlayer = CGPoint(x: position.x + corner.x, y: position.y + corner.y)
                let local = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
                let center = submoduleApply(transform, local)
                let centerInSuperlayer = CGPoint(x: position.x + size.width / 2 + center.x, y: position.y + size.height / 2 + center.y)
                XCTAssertEqual(cornerInSuperlayer.x, centerInSuperlayer.x, accuracy: 1e-9)
                XCTAssertEqual(cornerInSuperlayer.y, centerInSuperlayer.y, accuracy: 1e-9)
            }
        }
    }

    func testFiatSymbolGapMatchesSubmodule() {
        let scale = walletAmountFieldScale
        let actualFont = submoduleRoundedBoldFont(walletAmountMainFontSize)
        let submoduleFont = submoduleRoundedBoldFont(submoduleAmountIntegralFontSize)
        for text in ["0", "1", "4", "7", "12", "105,5", ""] {
            let displayText = text.isEmpty ? "0" : text
            let actualSpacing = walletAmountFiatSymbolSpacing(displayText: displayText, amountFont: actualFont)
            let actualInk = walletAmountInkBounds(String(displayText.prefix(1)), font: actualFont)
            let actualVisibleGap = actualSpacing + walletAmountInputHorizontalInset + max(0, actualInk.minX)
            let submoduleSpacing = submoduleFiatSymbolSpacing(displayText: displayText, integralFont: submoduleFont, textInset: 0)
            let submoduleInk = submoduleInkBounds(String(displayText.prefix(1)), font: submoduleFont)
            let submoduleVisibleGap = submoduleSpacing + max(0, submoduleInk.minX)
            XCTAssertEqual(actualVisibleGap, submoduleVisibleGap * scale, accuracy: 1e-9, displayText)
            XCTAssertEqual(max(0, actualInk.minX), max(0, submoduleInk.minX) * scale, accuracy: 0.01, displayText)
        }
    }

    func testFiatSymbolBaselineMatchesSubmodule() {
        let scale = walletAmountFieldScale
        let actualAmountFont = submoduleRoundedBoldFont(walletAmountMainFontSize)
        let actualSymbolFont = submoduleRoundedBoldFont(walletAmountFiatSymbolFontSize)
        let submoduleAmountFont = submoduleRoundedBoldFont(submoduleAmountIntegralFontSize)
        let submoduleSymbolFont = submoduleRoundedBoldFont(submoduleFiatSymbolFontSize)
        let actualOffset = walletAmountFiatSymbolBaseline(amountBaseline: 0, amountFont: actualAmountFont, symbolFont: actualSymbolFont)
        let submoduleOffset = submoduleFiatSymbolBaseline(amountBaseline: 0, integralFont: submoduleAmountFont, fiatSymbolFont: submoduleSymbolFont)
        XCTAssertEqual(actualOffset, submoduleOffset * scale, accuracy: 0.01)
        XCTAssertEqual(walletAmountFiatSymbolBaseline(amountBaseline: 25, amountFont: actualAmountFont, symbolFont: actualSymbolFont), 25 + actualOffset, accuracy: 1e-9)
    }

    func testFiatSymbolFontMatchesSubmodule() {
        let scale = walletAmountFieldScale
        let actualFont = walletAmountFiatSymbolFont()
        let submoduleFont = submoduleFiatSymbolFont(submoduleFiatSymbolFontSize)
        let plainFont = submoduleRoundedBoldFont(walletAmountFiatSymbolFontSize)
        XCTAssertEqual(actualFont.pointSize, submoduleFont.pointSize * scale, accuracy: 1e-9)
        XCTAssertEqual(actualFont.fontName, submoduleFont.fontName)
        XCTAssertEqual(submoduleGlyphNames("$", font: actualFont), ["dollar.1"])
        XCTAssertNotEqual(submoduleGlyphNames("$", font: plainFont), submoduleGlyphNames("$", font: actualFont))
        for symbol in ["$", "US$", "CA$", "A$", "R$", "€", "£", "₽", "¥", "₸", "₹", "CHF", "0123456789"] {
            XCTAssertEqual(submoduleGlyphNames(symbol, font: actualFont), submoduleGlyphNames(symbol, font: submoduleFont), symbol)
            if symbol.count == 1 {
                let actualInk = walletAmountInkBounds(symbol, font: actualFont)
                let submoduleInk = submoduleInkBounds(symbol, font: submoduleFont)
                XCTAssertEqual(actualInk.width, submoduleInk.width * scale, accuracy: 0.01, symbol)
                XCTAssertEqual(actualInk.height, submoduleInk.height * scale, accuracy: 0.01, symbol)
            }
            if !symbol.contains("$") {
                XCTAssertEqual(submoduleGlyphNames(symbol, font: actualFont), submoduleGlyphNames(symbol, font: plainFont), symbol)
            }
        }
        XCTAssertEqual(actualFont.capHeight, submoduleFont.capHeight * scale, accuracy: 0.01)
    }

    private func amountText(_ text: String, integralFont: NSFont, decimal: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let fractionalFont = submoduleRoundedBoldFont(integralFont.pointSize * 2.0 / 3.0)
        if let range = text.range(of: decimal) {
            result.append(NSAttributedString(string: String(text[..<range.lowerBound]), attributes: [.font: integralFont]))
            result.append(NSAttributedString(string: String(text[range.lowerBound...]), attributes: [.font: fractionalFont]))
        } else {
            result.append(NSAttributedString(string: text, attributes: [.font: integralFont]))
        }
        return result
    }

    private let refractionTexts = ["0", "5", "12", "1234567", "0.5", "12.34", ".5", ".", "0,25", ",5", "٣٤.٥", "7.", ""]

    func testRefractionDigitMatchesSubmodule() {
        let font = submoduleRoundedBoldFont(walletAmountMainFontSize)
        for decimal in [".", ","] {
            for text in refractionTexts {
                let displayText = text.isEmpty ? "0" : text
                let glyphs = submoduleAmountGlyphs(amountText(displayText, integralFont: font, decimal: decimal), origin: .zero, decimal: decimal)
                for mode in [WalletSendInputMode.gram, .fiat] {
                    let expected = submoduleRefractionGlyph(glyphs, mode: mode)
                    let actual = walletAmountRefractionDigit(displayText, mode: mode, decimalSeparator: decimal)
                    XCTAssertEqual(actual?.text, expected?.text, "\(displayText) \(decimal) \(mode)")
                    if let expected, let actual {
                        let index = glyphs.firstIndex(where: { $0.position == expected.position && $0.text == expected.text })!
                        let offset = glyphs[..<index].reduce(0) { $0 + $1.text.utf16.count }
                        XCTAssertEqual(actual.offset, offset, "\(displayText) \(decimal)")
                    }
                }
            }
        }
    }

    func testRefractionDigitPositionMatchesSubmoduleGlyphPosition() {
        for size in [walletAmountMainFontSize, 22.5] {
            let font = submoduleRoundedBoldFont(size)
            for text in refractionTexts where text == walletSendNormalizedDigits(text) {
                let displayText = text.isEmpty ? "0" : text
                let attributed = amountText(displayText, integralFont: font, decimal: ".")
                guard let expected = submoduleRefractionGlyph(submoduleAmountGlyphs(attributed, origin: .zero, decimal: "."), mode: .gram),
                      let digit = walletAmountRefractionDigit(displayText, mode: .gram, decimalSeparator: ".") else {
                    continue
                }
                let storage = NSTextStorage(attributedString: attributed)
                let layoutManager = NSLayoutManager()
                let container = NSTextContainer(size: NSMakeSize(10_000, 10_000))
                container.lineFragmentPadding = 0
                layoutManager.addTextContainer(container)
                storage.addLayoutManager(layoutManager)
                layoutManager.ensureLayout(for: container)
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: digit.offset)
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
                let location = layoutManager.location(forGlyphAt: glyphIndex)
                let actualCenter = lineRect.minX + location.x + walletAmountGlyphWidth(digit.text, font: font) / 2
                XCTAssertEqual(actualCenter, expected.position.x, accuracy: 1e-3, displayText)
                XCTAssertEqual(walletAmountGlyphWidth(digit.text, font: font), expected.width, accuracy: 1e-9, displayText)
                XCTAssertEqual(lineRect.minY + location.y, font.ascender, accuracy: 0.5, displayText)
            }
        }
    }

    func testRefractionGlyphMaskMatchesSubmoduleAtlasTile() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        for size in [walletAmountMainFontSize, 22.5, submoduleAmountIntegralFontSize] {
            let font = submoduleRoundedBoldFont(size)
            for scale: CGFloat in [1.0, 2.0, 3.0] {
                for text in "0123456789".map(String.init) + ["٣"] {
                    let expected = try XCTUnwrap(submoduleGlyphMask(text, font: font, scale: scale))
                    let actual = try XCTUnwrap(walletAmountGlyphMask(text, font: font, scale: scale, device: device))
                    XCTAssertEqual(actual.rect, expected.rect, "\(text) \(size) \(scale)")
                    XCTAssertEqual(actual.texture.width, expected.width, "\(text) \(size) \(scale)")
                    XCTAssertEqual(actual.texture.height, expected.height, "\(text) \(size) \(scale)")
                    XCTAssertEqual(actual.texture.pixelFormat, .r8Unorm)
                    var bytes = [UInt8](repeating: 0, count: expected.width * expected.height)
                    bytes.withUnsafeMutableBytes { storage in
                        actual.texture.getBytes(storage.baseAddress!, bytesPerRow: expected.width, from: MTLRegionMake2D(0, 0, expected.width, expected.height), mipmapLevel: 0)
                    }
                    XCTAssertEqual(bytes, expected.bytes, "\(text) \(size) \(scale)")
                    XCTAssertGreaterThan(bytes.filter { $0 > 0 }.count, 0, "\(text) \(size) \(scale)")
                    XCTAssertEqual(actual.text, text)
                    XCTAssertEqual(actual.scale, scale)
                }
            }
        }
    }

    func testChatCardShimmerSweepMatchesSubmodule() {
        for size in [CGSize(width: 216, height: 148), CGSize(width: 300, height: 180)] {
            for width: CGFloat in [160, 128, 112] {
                let submodule = submoduleShimmerBand(width: width, frame: CGRect(origin: .zero, size: size), cardWidth: size.width + 8.0)
                let actual = walletChatCardShimmerBandPoints(width: width, size: size)
                XCTAssertEqual(submodule[0].keyPath, "startPoint")
                XCTAssertEqual(submodule[1].keyPath, "endPoint")
                XCTAssertEqual(actual.start.from, submodule[0].from, "\(size) \(width)")
                XCTAssertEqual(actual.start.to, submodule[0].to, "\(size) \(width)")
                XCTAssertEqual(actual.end.from, submodule[1].from, "\(size) \(width)")
                XCTAssertEqual(actual.end.to, submodule[1].to, "\(size) \(width)")
            }
        }
    }

    func testInfoParagraphTextPositionMatchesSubmodule() {
        for topInset: CGFloat in [9, 10] {
            for textHeight: CGFloat in [0, 13, 16, 18.5, 20, 20.5, 32, 48] {
                let submodule = submoduleInfoParagraphTextOriginY(textTopInset: topInset, textHeight: textHeight)
                XCTAssertEqual(walletInfoParagraphTextY(iconMidY: submodule.iconCenterY, textHeight: textHeight, topInset: topInset), submodule.textOriginY, "\(topInset) \(textHeight)")
            }
        }
    }

    func testCollectibleTransferRouteMatchesSubmodule() {
        let phases: [WalletContext.Phase] = [
            .restoring,
            .creating,
            .empty,
            .failed(.corrupted),
            .wallet(.init(address: walletAddress, publicKey: "key")),
            .wallet(.init(address: walletAddress, publicKey: "key", canSign: true)),
            .wallet(.init(address: walletAddress, publicKey: "key", canExportPhrase: true)),
            .wallet(.init(address: walletAddress, publicKey: "key", backupEnabled: true, canExportPhrase: true, canSign: true))
        ]
        for phase in phases {
            let submodule = submoduleCollectibleOpenTransfer(phase)
            let actual: SubmoduleCollectibleTransferRoute?
            switch walletCollectibleTransferRoute(phase) {
            case .transfer:
                actual = .routeToTransfer
            case .restoreSigningAccess:
                actual = .restoreSigningAccess
            case .enterRecoveryPhrase:
                actual = .importRecoveryPhrase
            case .unavailable:
                actual = nil
            }
            XCTAssertEqual(actual, submodule, "\(phase)")
        }
    }

    private func collectible(_ address: String) -> WalletContext.Collectible {
        return WalletContext.Collectible(address: address, name: address, kind: .gift, nft: nft(image: nil, imageSmall: nil, lottie: nil))
    }

    private func walletState(_ phase: WalletContext.Phase, items: [String] = [], nextOffset: String? = nil, generation: UInt64 = 1, isRefreshing: Bool = false, isLoadingMore: Bool = false, error: WalletContext.SynchronizationError? = nil) -> WalletContext.State {
        let collectibles = WalletContext.CollectiblesState(items: items.map(collectible), nextOffset: nextOffset, generation: generation, isRefreshing: isRefreshing, isLoadingMore: isLoadingMore, error: error)
        return WalletContext.State(phase: phase, balance: .idle, transactions: .init(items: [], offset: 0, canLoadMore: false, isLoadingMore: false, error: nil), collectibles: collectibles, pendingTransfers: [], activeOperation: nil)
    }

    func testSuppressedCollectiblesMatchSubmodule() {
        let walletA: WalletContext.Phase = .wallet(.init(address: walletAddress, publicKey: "key"))
        let walletB: WalletContext.Phase = .wallet(.init(address: otherAddress, publicKey: "key"))
        let scenarios: [[(state: WalletContext.State, suppress: [String])]] = [
            [(walletState(walletA, items: ["x", "y", "z"], isRefreshing: true), ["x", "z", "gone"]), (walletState(walletA, items: ["x", "y"]), [])],
            [(walletState(walletA, items: ["x"], isLoadingMore: true), ["x", "gone"]), (walletState(walletA, items: ["x"]), [])],
            [(walletState(walletA, items: ["x"], isRefreshing: true), ["gone"]), (walletState(walletA, items: ["x"], error: .network), [])],
            [(walletState(walletA, items: ["x"], isRefreshing: true), ["gone"]), (walletState(walletA, items: ["x"], nextOffset: "next"), [])],
            [(walletState(walletA, items: ["x"], generation: 1, isRefreshing: true), ["gone"]), (walletState(walletA, items: ["x"], generation: 2), [])],
            [(walletState(walletA, items: ["x"]), ["gone"]), (walletState(walletA, items: ["x"]), [])],
            [(walletState(walletA, items: ["x"], isRefreshing: true), ["gone"]), (walletState(walletA, items: ["x"], isRefreshing: true), []), (walletState(walletA, items: []), [])],
            [(walletState(walletA, items: ["x"]), ["x"]), (walletState(.restoring, items: ["x"], isRefreshing: true), []), (walletState(walletA, items: []), [])],
            [(walletState(walletA, items: ["x"]), ["x"]), (walletState(walletB, items: ["x"]), [])],
            [(walletState(walletA, items: ["x"]), ["x"]), (walletState(.empty), []), (walletState(walletA, items: ["x"]), [])]
        ]
        for (index, scenario) in scenarios.enumerated() {
            var submodule = SubmoduleSuppressedCollectibles()
            var actual = WalletHomeState()
            for (step, entry) in scenario.enumerated() {
                submodule.walletStateUpdated(entry.state)
                let previous = actual.walletState?.collectibles
                actual.walletState = entry.state
                actual.updateSuppressedCollectibles(previous: previous)
                for address in entry.suppress {
                    submodule.suppressedCollectibleAddresses.insert(address)
                    actual.suppressedCollectibleAddresses.insert(address)
                }
                XCTAssertEqual(actual.suppressedCollectibleAddresses, submodule.suppressedCollectibleAddresses, "scenario \(index) step \(step)")
                XCTAssertEqual(actual.suppressedCollectiblesWalletAddress, submodule.suppressedCollectiblesWalletAddress, "scenario \(index) step \(step)")
            }
        }
    }
}
