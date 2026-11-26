import Cocoa
import TGUIKit
import CurrencyFormat
import SwiftSignalKit
import CoreText
import Metal
import MetalEngine
import WalletContext
import TelegramMedia
import TelegramTheme
import TelegramContext
import GeneralRows
import SceneEffects
import Localization

public enum WalletSendInputMode: Equatable {
    case gram
    case fiat
}

private var walletAmountDecimalSeparator: String {
    return Locale.current.decimalSeparator ?? "."
}

@available(macOS 10.15, *)
public func walletFiatFractionDigits(_ currency: WalletContext.FiatCurrency) -> Int {
    return currencyDecimalDigits(currency.code)
}

public func walletAmountGrouped(_ text: String) -> String {
    let separator = walletGroupingSeparator
    guard !separator.isEmpty, separator != walletAmountDecimalSeparator else {
        return text
    }
    let integerText: Substring
    let fractionalText: Substring
    if let range = text.range(of: walletAmountDecimalSeparator) {
        integerText = text[..<range.lowerBound]
        fractionalText = text[range.lowerBound...]
    } else {
        integerText = text[...]
        fractionalText = ""
    }
    guard integerText.count > 3 else {
        return text
    }
    var grouped = ""
    for (offset, character) in integerText.enumerated() {
        if offset > 0, (integerText.count - offset).isMultiple(of: 3) {
            grouped += separator
        }
        grouped.append(character)
    }
    return grouped + fractionalText
}


@available(macOS 10.15, *)
private func walletAmountRoundedFont(_ size: CGFloat, monospacedDigits: Bool = true, alternateDollarSign: Bool = false) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .bold)
    var descriptor = base.fontDescriptor
    if let rounded = descriptor.withDesign(.rounded) {
        descriptor = rounded
    }
    var featureSettings: [[NSFontDescriptor.FeatureKey: Any]] = []
    if monospacedDigits {
        featureSettings.append([.typeIdentifier: kNumberSpacingType, .selectorIdentifier: kMonospacedNumbersSelector])
    }
    if alternateDollarSign {
        featureSettings.append([NSFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureTag as String): "cv09", NSFontDescriptor.FeatureKey(rawValue: kCTFontOpenTypeFeatureValue as String): 1])
    }
    if !featureSettings.isEmpty {
        descriptor = descriptor.addingAttributes([.featureSettings: featureSettings])
    }
    return NSFont(descriptor: descriptor, size: size) ?? base
}

@available(macOS 10.15, *)
func walletAmountFiatSymbolFont() -> NSFont {
    return walletAmountRoundedFont(walletAmountFiatSymbolFontSize, monospacedDigits: false, alternateDollarSign: true)
}

let walletAmountInputHorizontalInset: CGFloat = 3
private let walletAmountInputVerticalInset: CGFloat = 1
private let walletAmountFractionalFontScale: CGFloat = 2.0 / 3.0
let walletAmountParagraphStyle: NSParagraphStyle = {
    let style = NSMutableParagraphStyle()
    style.alignment = .left
    style.baseWritingDirection = .leftToRight
    return style
}()
private let walletAmountDiamondCanvas: CGFloat = 34
private let walletAmountDiamondWidthRatio: CGFloat = 0.66
private let walletAmountDiamondCenterRatio: CGFloat = 0.553
private let walletAmountDiamondSpacing: CGFloat = 6
let walletAmountMainFontSize: CGFloat = 34
let walletAmountFieldScale: CGFloat = walletAmountMainFontSize / 48
let walletAmountInteractiveDiamondCanvas: CGFloat = 96 * walletAmountFieldScale
let walletAmountInteractiveDiamondWidth: CGFloat = 34 * walletAmountFieldScale
let walletAmountInteractiveDiamondNudge: CGFloat = 1 * walletAmountFieldScale
let walletAmountFiatSymbolFontSize: CGFloat = 34 * walletAmountFieldScale
let walletAmountFiatSymbolGap: CGFloat = 8.3 * walletAmountFieldScale
let walletAmountFiatSymbolOpticalShift: CGFloat = 3.45 * walletAmountFieldScale

func walletAmountInkBounds(_ text: String, font: NSFont) -> CGRect {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    return CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
}

struct WalletAmountGlyphMask {
    let text: String
    let font: NSFont
    let scale: CGFloat
    let texture: MTLTexture
    let rect: CGRect
}

func walletAmountGlyphWidth(_ text: String, font: NSFont) -> CGFloat {
    return (text as NSString).size(withAttributes: [.font: font]).width
}

func walletAmountRefractionDigit(_ text: String, mode: WalletSendInputMode, decimalSeparator: String) -> (offset: Int, text: String)? {
    guard mode == .gram else { return nil }
    let fractionOffset = (text as NSString).range(of: decimalSeparator).location
    var offset = 0
    for character in text {
        let string = String(character)
        if fractionOffset != NSNotFound && offset >= fractionOffset { return nil }
        if string.first?.wholeNumberValue != nil { return (offset, string) }
        offset += string.utf16.count
    }
    return nil
}

func walletAmountGlyphMask(_ text: String, font: NSFont, scale: CGFloat, device: MTLDevice) -> WalletAmountGlyphMask? {
    let width = walletAmountGlyphWidth(text, font: font)
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
                path.addPath(outline, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: positions[i].x - width / 2, ty: -positions[i].y))
            }
        }
    }
    guard !path.isEmpty, scale > 0 else { return nil }
    let ink = path.boundingBoxOfPath.insetBy(dx: -2 / scale, dy: -2 / scale)
    let rect = CGRect(x: floor(ink.minX * scale) / scale, y: floor(ink.minY * scale) / scale, width: ceil(ink.width * scale + 1) / scale, height: ceil(ink.height * scale + 1) / scale)
    let pixelWidth = max(1, Int(round(rect.width * scale)))
    let pixelHeight = max(1, Int(round(rect.height * scale)))
    var bytes = [UInt8](repeating: 0, count: pixelWidth * pixelHeight)
    let drawn = bytes.withUnsafeMutableBytes { storage -> Bool in
        guard let context = CGContext(data: storage.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(gray: 1, alpha: 1)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        context.addPath(path)
        context.fillPath()
        return true
    }
    guard drawn else { return nil }
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: pixelWidth, height: pixelHeight, mipmapped: false)
    descriptor.usage = .shaderRead
    guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
    bytes.withUnsafeBytes { storage in
        if let base = storage.baseAddress {
            texture.replace(region: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight), mipmapLevel: 0, withBytes: base, bytesPerRow: pixelWidth)
        }
    }
    return WalletAmountGlyphMask(text: text, font: font, scale: scale, texture: texture, rect: rect)
}

private let walletMilligram: Int64 = 1_000_000

public func walletMilligramTruncated(_ amount: Int64) -> Int64 {
    return (amount / walletMilligram) * walletMilligram
}

func walletSendNormalizedDigits(_ text: String) -> String {
    return String(text.unicodeScalars.map { scalar -> Character in
        let character = Character(String(scalar))
        if CharacterSet.decimalDigits.contains(scalar), let digit = character.wholeNumberValue {
            return Character(String(digit))
        }
        return character
    })
}

public func walletSendNanograms(text: String, mode: WalletSendInputMode, rate: Double?, decimalSeparator: String) -> Int64? {
    guard !text.isEmpty else {
        return 0
    }

    guard !decimalSeparator.isEmpty else { return nil }
    let normalizedText = walletSendNormalizedDigits(text).replacingOccurrences(of: decimalSeparator, with: ".")
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

struct WalletSendAmountEdit: Equatable {
    let text: String
    let selection: NSRange
}

func walletSendReplacingAmountText(
    _ text: String,
    range: NSRange,
    replacement string: String,
    mode: WalletSendInputMode,
    rate: Double?,
    decimalSeparator: String
) -> WalletSendAmountEdit? {
    guard !decimalSeparator.isEmpty else { return nil }
    var replacement = walletSendNormalizedDigits(string)
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
    guard walletSendNanograms(
        text: updatedText,
        mode: mode,
        rate: rate,
        decimalSeparator: decimalSeparator
    ) != nil else {
        return nil
    }

    return WalletSendAmountEdit(text: updatedText, selection: NSRange(location: selectionOffset, length: 0))
}

enum WalletSendAmountEditResult: Equatable {
    case ignored
    case rejected
    case accepted(WalletSendAmountEdit)
}

func walletSendAmountEditResult(
    _ text: String,
    range: NSRange,
    replacement: String,
    mode: WalletSendInputMode,
    rate: Double?,
    decimalSeparator: String
) -> WalletSendAmountEditResult {
    if text == "0" + decimalSeparator, range.location == text.length, range.length == 0,
       replacement == decimalSeparator || replacement == "." || replacement == "," {
        return .ignored
    }
    guard let edit = walletSendReplacingAmountText(text, range: range, replacement: replacement, mode: mode, rate: rate, decimalSeparator: decimalSeparator) else {
        return .rejected
    }
    return .accepted(edit)
}

public func walletSendInputText(amount: Int64, mode: WalletSendInputMode, rate: Double?, fiatFractionDigits: Int = 2) -> String {
    guard amount > 0 else {
        return ""
    }
    let decimalSeparator = walletAmountDecimalSeparator
    switch mode {
    case .gram:
        var text = "\(amount)"
        while text.count < 10 {
            text.insert("0", at: text.startIndex)
        }
        text.insert(contentsOf: decimalSeparator, at: text.index(text.endIndex, offsetBy: -9))
        while true {
            if text.hasSuffix("0") {
                if text.hasSuffix(decimalSeparator + "0") {
                    text.removeLast(decimalSeparator.count + 1)
                    break
                } else {
                    text.removeLast()
                }
            } else {
                break
            }
        }
        return text
    case .fiat:
        guard let rate, rate.isFinite, rate > 0.0 else {
            return ""
        }
        let value = Double(amount) / 1_000_000_000.0 * rate
        guard value.isFinite else {
            return ""
        }
        var text = String(
            format: "%.\(max(0, fiatFractionDigits))f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
        if text.contains(".") {
            while text.hasSuffix("0") {
                text.removeLast()
            }
            if text.hasSuffix(".") {
                text.removeLast()
            }
        }
        return text.replacingOccurrences(of: ".", with: decimalSeparator)
    }
}

@available(macOS 10.15, *)
public final class WalletAmountRowItem: GeneralRowItem {
    fileprivate let amount: Int64
    fileprivate let mode: WalletSendInputMode
    fileprivate let rate: Double?
    fileprivate let currency: WalletContext.FiatCurrency
    fileprivate let revision: Int
    fileprivate let clock: WalletSendMotionClock
    fileprivate let opening: WalletSendOpening
    fileprivate let updated: (Int64) -> Void
    fileprivate let onReturn: () -> Void

    @available(macOS 10.15, *)
    init(_ initialSize: NSSize, stableId: AnyHashable, amount: Int64, mode: WalletSendInputMode, rate: Double?, currency: WalletContext.FiatCurrency, revision: Int, clock: WalletSendMotionClock, opening: WalletSendOpening, viewType: GeneralViewType, updated: @escaping (Int64) -> Void, onReturn: @escaping () -> Void) {
        self.amount = amount
        self.mode = mode
        self.rate = rate
        self.currency = currency
        self.revision = revision
        self.clock = clock
        self.opening = opening
        self.updated = updated
        self.onReturn = onReturn
        super.init(initialSize, height: 52, stableId: stableId, viewType: viewType, inset: NSEdgeInsets(left: 20, right: 20))
    }

    fileprivate var fiatFractionDigits: Int {
        return walletFiatFractionDigits(currency)
    }

    public override func viewClass() -> AnyClass {
        return WalletAmountRowView.self
    }

    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonAmount
    }

    public override var accessibilityValue: String? {
        guard amount > 0 else {
            return nil
        }
        switch mode {
        case .gram:
            return walletTonAccessibilityText(formatTonAmountText(amount, maxDecimalPositions: 9))
        case .fiat:
            return walletSendInputText(amount: amount, mode: .fiat, rate: rate, fiatFractionDigits: fiatFractionDigits) + " " + currency.code
        }
    }
}

private let walletAmountFiatColor = NSColor(rgb: 0x219949)
private let walletAmountCurrencyBlurRadius: CGFloat = 6.0
private let walletAmountCurrencyDuration: Double = 0.25

private func walletAmountApplyBlur(_ layer: CALayer, from: CGFloat, to: CGFloat, animated: Bool) {
    guard let blurFilter = ee2_makeBlurFilter() else {
        return
    }
    blurFilter.setValue(to as NSNumber, forKey: "inputRadius")
    layer.filters = [blurFilter]
    guard animated, from != to else {
        return
    }
    let animation = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
    animation.fromValue = from
    animation.toValue = to
    animation.duration = walletAmountCurrencyDuration
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: "walletAmountCurrencyBlur")
}

private let walletAmountSymbolPulseKey = "walletAmountSymbolPulse"
private let walletAmountInputRefusalKey = "walletAmountInputRefusal"
private let walletAmountSymbolTransitionKey = "walletAmountSymbolTransition"
let walletAmountSymbolDrop: CGFloat = 16 * walletAmountFieldScale
let walletAmountSymbolBlur: CGFloat = 6 * walletAmountFieldScale

struct WalletAmountSymbolState {
    var drop: CGFloat
    var tilt: CGFloat
    var blur: CGFloat
    var alpha: CGFloat

    var transform: CATransform3D {
        var transform = CATransform3DIdentity
        transform = CATransform3DRotate(transform, self.tilt, 0.0, 0.0, 1.0)
        return CATransform3DTranslate(transform, 0.0, self.drop, 0.0)
    }
}

struct WalletAmountSymbolTransition {
    let timing: WalletSendAmountMotionTiming
    let toGram: Bool
    var gramFrom: WalletAmountSymbolState?
    var fiatFrom: WalletAmountSymbolState?

    var duration: Double { return self.timing.reduced ? self.timing.duration : self.timing.duration + 1.5 }

    func state(gram: Bool, at time: Double) -> WalletAmountSymbolState {
        let elapsed = max(0.0, time - self.timing.start)
        let p = self.timing.layoutProgress(at: time)
        let arriving = gram == self.toGram
        let from = gram ? self.gramFrom : self.fiatFrom
        let toAlpha: CGFloat = arriving ? 1.0 : 0.0
        let fromAlpha = from?.alpha ?? (1.0 - toAlpha)
        let alpha = fromAlpha + (toAlpha - fromAlpha) * p
        if self.timing.reduced {
            return WalletAmountSymbolState(drop: 0.0, tilt: 0.0, blur: 0.0, alpha: alpha)
        }
        let tail = max(0.0, elapsed - 0.3)
        let fromDrop = from?.drop ?? (arriving ? walletAmountSymbolDrop : 0.0)
        let toDrop: CGFloat = arriving ? 0.0 : walletAmountSymbolDrop
        return WalletAmountSymbolState(
            drop: fromDrop + (toDrop - fromDrop) * p,
            tilt: CGFloat(20.0 * sin(2.0 * .pi * 1.6 * tail) * exp(-tail / 0.5)) * .pi / 180.0
                + (from?.tilt ?? 0.0) * (1.0 - p),
            blur: walletAmountSymbolBlur * sin(.pi * alpha),
            alpha: alpha
        )
    }
}

func walletAmountCenteredTransform(_ transform: CATransform3D, layer: CALayer) -> CATransform3D {
    let dx = layer.bounds.width * (0.5 - layer.anchorPoint.x)
    let dy = layer.bounds.height * (0.5 - layer.anchorPoint.y)
    return CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-dx, -dy, 0), transform), CATransform3DMakeTranslation(dx, dy, 0))
}

func walletAmountPulseScale(_ t: CGFloat, fromScale: CGFloat) -> CGFloat {
    return 1.0 + 0.14 * sin(.pi * t) * (1.0 - 0.3 * t) + (fromScale - 1.0) * (1.0 - WalletSendRolling.Motion.ease(Double(t)))
}

func walletAmountFiatSymbolSpacing(displayText: String, amountFont: NSFont) -> CGFloat {
    let firstDigitInk = walletAmountInkBounds(String(displayText.prefix(1)), font: amountFont)
    return walletAmountFiatSymbolGap - max(0, firstDigitInk.minX) - walletAmountInputHorizontalInset
}

func walletAmountFiatSymbolBaseline(amountBaseline: CGFloat, amountFont: NSFont, symbolFont: NSFont) -> CGFloat {
    return amountBaseline - amountFont.capHeight / 2 + symbolFont.capHeight / 2 + walletAmountFiatSymbolOpticalShift
}

func walletAmountSpinVelocity(_ insertedText: String) -> Float {
    if insertedText.isEmpty {
        return 6.5
    } else if let digit = insertedText.last(where: { $0.wholeNumberValue != nil })?.wholeNumberValue {
        return -(5.5 + 0.25 * Float(digit))
    } else {
        return -3.5
    }
}

private func walletAmountAnimateCurrencyChange(_ view: NSView) {
    guard let layer = view.layer else {
        return
    }
    layer.animateAlpha(from: 0.0, to: CGFloat(layer.opacity), duration: walletAmountCurrencyDuration)
    walletAmountApplyBlur(layer, from: walletAmountCurrencyBlurRadius, to: 0.0, animated: true)
}

private let walletAmountBlockedMenuActions: Set<Selector> = [
    Selector(("toggleAutomaticQuoteSubstitution:")),
    Selector(("toggleAutomaticDashSubstitution:")),
    Selector(("toggleAutomaticTextReplacement:")),
    Selector(("toggleSmartInsertDelete:")),
    Selector(("toggleContinuousSpellChecking:")),
    Selector(("toggleGrammarChecking:")),
    Selector(("toggleAutomaticSpellingCorrection:")),
    Selector(("toggleAutomaticLinkDetection:")),
    Selector(("toggleAutomaticDataDetection:")),
    Selector(("orderFrontSubstitutionsPanel:")),
    Selector(("showGuessPanel:")),
    Selector(("checkSpelling:")),
    Selector(("captureTextFromCamera:")),
    Selector(("importFromDevice:"))
]

private func walletAmountPruneMenu(_ menu: NSMenu) {
    for item in menu.items {
        if let submenu = item.submenu {
            walletAmountPruneMenu(submenu)
            if submenu.items.isEmpty {
                menu.removeItem(item)
            }
        } else if let action = item.action, walletAmountBlockedMenuActions.contains(action) {
            menu.removeItem(item)
        }
    }
}

final class WalletAmountTextView: BaseTextView {
    public var onTextChange: (() -> Void)?
    public var interactionBegan: (() -> Void)?
    private var ignoresTextChanges = false

    public override func mouseDown(with event: NSEvent) {
        interactionBegan?()
        super.mouseDown(with: event)
    }

    public override func accessibilityParent() -> Any? {
        return nil
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else {
            return nil
        }
        walletAmountPruneMenu(menu)
        return menu
    }

    public override var typingAttributes: [NSAttributedString.Key: Any] {
        get {
            return super.typingAttributes
        }
        set {
            var attributes = newValue
            attributes[.paragraphStyle] = walletAmountParagraphStyle
            super.typingAttributes = attributes
        }
    }

    public override func readSelection(from pboard: NSPasteboard) -> Bool {
        guard let string = pboard.string(forType: .string) else {
            return false
        }
        insertText(string, replacementRange: selectedRange())
        return true
    }

    public func setText(_ text: String) {
        guard string != text else {
            return
        }
        setAttributedText(NSAttributedString(string: text), selectedRange: selectedRange())
    }

    public func setAttributedText(_ text: NSAttributedString, selectedRange: NSRange) {
        let maximumLocation = text.length
        let location = min(max(0, selectedRange.location), maximumLocation)
        let length = min(max(0, selectedRange.length), maximumLocation - location)
        guard !attributedString().isEqual(to: text) || self.selectedRange() != NSMakeRange(location, length) else {
            return
        }
        ignoresTextChanges = true
        textStorage?.setAttributedString(text)
        setSelectedRange(NSMakeRange(location, length))
        if let layoutManager, let textContainer {
            layoutManager.ensureLayout(for: textContainer)
            updateInsertionPointStateAndRestartTimer(true)
        }
        ignoresTextChanges = false
    }

    public override func didChangeText() {
        super.didChangeText()
        guard !ignoresTextChanges else {
            return
        }
        onTextChange?()
    }
}

private final class WalletAmountGroupingView: NSView {
    var separators: [(text: NSAttributedString, origin: NSPoint)] = [] {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        for separator in separators {
            separator.text.draw(at: separator.origin)
        }
    }
}

private final class WalletAmountContentView: NSView {
    override var isFlipped: Bool {
        return true
    }
}

@available(macOS 10.15, *)
final class WalletAmountRowView: GeneralRowView, NSTextViewDelegate {
    private struct Layout {
        var width: CGFloat
        var height: CGFloat
        var gram: CGRect
        var fiat: CGRect
        var caret: CGRect

        func interpolate(to other: Layout, progress p: CGFloat) -> Layout {
            return Layout(
                width: self.width + (other.width - self.width) * p,
                height: self.height + (other.height - self.height) * p,
                gram: walletSendAmountMotionRect(self.gram, other.gram, p),
                fiat: walletSendAmountMotionRect(self.fiat, other.fiat, p),
                caret: walletSendAmountMotionRect(self.caret, other.caret, p)
            )
        }
    }

    #if arch(arm64)
    private var diamondView = InteractiveDiamondView(frame: NSMakeRect(0, 0, walletAmountInteractiveDiamondCanvas, walletAmountInteractiveDiamondCanvas))
    private var hasTransferredDiamond = false
    #else
    private let iconView = LottiePlayerView(frame: NSMakeRect(0, 0, walletAmountDiamondCanvas, walletAmountDiamondCanvas))
    #endif
    private let contentView = WalletAmountContentView()
    private let symbolView = TextView()
    private let inputView = WalletAmountTextView()
    private let groupingView = WalletAmountGroupingView()
    private let placeholderInputView = WalletAmountTextView()
    private let suffixView = TextView()
    private let canvas = WalletSendAmountCanvas(frame: .zero)
    private let motion = WalletSendAmountMotion(liquid: true)
    private lazy var animator = ConstantDisplayLinkAnimator(update: { [weak self] in
        self?.tick()
    }, fps: 120)
    private var appliedRevision: Int = .min
    private var appliedMode: WalletSendInputMode? = nil
    private var lastValidText: String = ""
    private var didAutofocus = false
    private var didStartAnimation = false
    private var currentSuffixText: String?
    private var symbolTransition: WalletAmountSymbolTransition?
    #if arch(arm64)
    private var refractionMask: WalletAmountGlyphMask?
    #endif
    private var previousMode: WalletSendInputMode?
    private var previousText = ""
    private var previousSelection: NSRange?
    private var layoutFrom: Layout?
    private var layoutTo: Layout?
    private var currentLayout: Layout?
    private var updating = false
    private var rendering = false
    private var nativeInteraction = false
    private var rendersNativeText = true
    private var availableWidth: CGFloat = 0
    private var frameDuration = 1.0 / 120.0
    private var lastFrameTime: Double?
    private var opening: WalletSendAmountIntro?
    private var diamondIsExpanded = false

    private var isSwitchingSymbols: Bool {
        guard let transition = symbolTransition else {
            return false
        }
        return transition.timing.progress(at: CACurrentMediaTime()) < 1.0
    }

    private var visible: Bool {
        return window != nil
    }

    private let mainFont = walletAmountRoundedFont(walletAmountMainFontSize, monospacedDigits: false)
    private let suffixFont = walletAmountRoundedFont(22, monospacedDigits: false)
    private let fiatSymbolFont = walletAmountFiatSymbolFont()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = false
        addSubview(contentView)

        #if arch(arm64)
        diamondView.onExpansionChanged = { [weak self] expanded in
            guard let self else {
                return
            }
            self.diamondIsExpanded = expanded
            self.layer?.masksToBounds = !expanded && self.opening == nil
            self.layer?.zPosition = expanded || self.opening != nil ? 1 : 0
            if expanded {
                self.currentItem?.opening.finish(animated: true)
                self.diamondView.layer?.removeAnimation(forKey: walletAmountSymbolPulseKey)
            }
        }
        #else
        iconView.isEventLess = true
        #endif
        contentView.addSubview(gramIconView)

        symbolView.userInteractionEnabled = false
        symbolView.isSelectable = false
        contentView.addSubview(symbolView)

        configureAmountTextView(placeholderInputView, isEditable: false)
        contentView.addSubview(placeholderInputView)

        configureAmountTextView(inputView, isEditable: true)
        inputView.delegate = self
        inputView.onTextChange = { [weak self] in
            self?.handleTextChange()
        }
        inputView.interactionBegan = { [weak self] in
            self?.currentItem?.opening.finish(animated: true)
            self?.nativeInteraction = true
            self?.finishMotion()
        }
        contentView.addSubview(inputView)
        contentView.addSubview(groupingView)

        suffixView.userInteractionEnabled = false
        suffixView.isSelectable = false
        contentView.addSubview(suffixView)

        canvas.isHidden = true
        canvas.onFrameReady = { [weak self] in
            guard let self, self.visible, !self.nativeInteraction else {
                return
            }
            self.setNativeTextVisible(false)
        }
        contentView.addSubview(canvas)

        #if arch(arm64)
        diamondView.layer?.zPosition = 1
        #endif

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(reduceMotionChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func reduceMotionChanged() {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            layer?.removeAnimation(forKey: walletAmountInputRefusalKey)
        }
        stopSymbolAnimations()
        finishMotion()
    }

    public func textDidEndEditing(_ notification: Notification) {
        #if arch(arm64)
        diamondView.cancelInteraction()
        #endif
        layer?.removeAnimation(forKey: walletAmountInputRefusalKey)
        finishMotion()
    }

    #if arch(arm64)
    func spinForTransfer() {
        guard !hasTransferredDiamond, diamondView.window != nil else {
            return
        }
        diamondView.spin(walletSendTransferSpin.velocity, decay: walletSendTransferSpin.decay)
    }

    func takeTransferDiamond() -> WalletSendTransferAnimationSource? {
        guard !hasTransferredDiamond, currentItem?.mode == .gram,
              let source = WalletSendTransferAnimationSource.capture(diamond: diamondView, width: walletAmountInteractiveDiamondWidth) else {
            return nil
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        stopSymbolAnimations()
        hasTransferredDiamond = true
        let diamond = diamondView
        diamondView = InteractiveDiamondView(frame: NSMakeRect(0, 0, walletAmountInteractiveDiamondCanvas, walletAmountInteractiveDiamondCanvas))
        diamond.prepareForWalletTransfer()
        return source
    }
    #endif

    private var gramIconView: NSView {
        #if arch(arm64)
        return diamondView
        #else
        return iconView
        #endif
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var currentItem: WalletAmountRowItem? {
        return item as? WalletAmountRowItem
    }

    func updateOpening(_ value: WalletSendAmountIntro?) {
        let wasOpening = opening != nil
        guard value != nil || wasOpening else {
            return
        }
        opening = value
        if value != nil {
            animator.isPaused = true
        }
        updateCaretOpacity()
        guard currentLayout != nil, canvas.isAvailable else {
            return
        }
        let now = CACurrentMediaTime()
        if value != nil || motion.isAnimating(at: now) {
            renderFrame(at: now)
            setNativeTextVisible(false)
            if value == nil {
                animator.isPaused = false
            }
        } else {
            finishMotion()
        }
        if value == nil {
            #if arch(arm64)
            diamondView.updateOpeningScale(nil)
            #endif
            layer?.masksToBounds = !diamondIsExpanded
            layer?.zPosition = diamondIsExpanded ? 1 : 0
        }
    }

    private func updateCaretOpacity() {
        let alpha = canvas.isAvailable ? (opening?.caret ?? 1.0) : 1.0
        let color = (currentItem?.mode == .fiat ? walletAmountFiatColor : walletGramColor(for: theme.colors)).withAlphaComponent(alpha)
        if inputView.insertionPointColor != color {
            inputView.insertionPointColor = color
        }
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    private func configureAmountTextView(_ textView: NSTextView, isEditable: Bool) {
        textView.isFieldEditor = false
        textView.isRichText = true
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFontPanel = false
        textView.isEditable = isEditable
        textView.isSelectable = isEditable
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.focusRingType = .none
        textView.font = mainFont
        textView.alignment = .left
        textView.textContainerInset = NSMakeSize(walletAmountInputHorizontalInset, walletAmountInputVerticalInset)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.maximumNumberOfLines = 1
        textView.textContainer?.lineBreakMode = .byClipping
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
    }

    @available(macOS 10.15, *)
    private func fractionalFont(for integralFont: NSFont) -> NSFont {
        return walletAmountRoundedFont(integralFont.pointSize * walletAmountFractionalFontScale, monospacedDigits: false)
    }

    private var amountTextColor: NSColor {
        return rendersNativeText ? theme.colors.text : .clear
    }

    private func amountAttributedText(_ text: String, integralFont: NSFont, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let fractionalFont = fractionalFont(for: integralFont)
        if let separatorRange = text.range(of: walletAmountDecimalSeparator) {
            result.append(NSAttributedString(string: String(text[..<separatorRange.lowerBound]), attributes: [
                .font: integralFont,
                .foregroundColor: color
            ]))
            result.append(NSAttributedString(string: String(text[separatorRange.lowerBound...]), attributes: [
                .font: fractionalFont,
                .foregroundColor: color
            ]))
        } else {
            result.append(NSAttributedString(string: text, attributes: [
                .font: integralFont,
                .foregroundColor: color
            ]))
        }
        let separatorWidth = ceil(groupingSeparatorText(integralFont: integralFont, color: color).size().width)
        for offset in groupingOffsets(text) {
            result.addAttribute(.kern, value: separatorWidth, range: NSMakeRange(offset - 1, 1))
        }
        result.addAttribute(.paragraphStyle, value: walletAmountParagraphStyle, range: NSMakeRange(0, result.length))
        return result
    }

    private func groupingOffsets(_ text: String) -> [Int] {
        let separator = walletGroupingSeparator
        guard !separator.isEmpty, separator != walletAmountDecimalSeparator else {
            return []
        }
        let decimalRange = (text as NSString).range(of: walletAmountDecimalSeparator)
        let integralLength = decimalRange.location == NSNotFound ? (text as NSString).length : decimalRange.location
        guard integralLength > 3 else {
            return []
        }
        return Array(stride(from: integralLength - 3, through: 1, by: -3).reversed())
    }

    private func groupingSeparatorText(integralFont: NSFont, color: NSColor) -> NSAttributedString {
        return NSAttributedString(string: walletGroupingSeparator, attributes: [
            .font: integralFont,
            .foregroundColor: color
        ])
    }

    private func groupingSeparatorOrigins() -> [NSPoint] {
        let offsets = groupingOffsets(inputView.string)
        guard !offsets.isEmpty, let layoutManager = inputView.layoutManager, let textContainer = inputView.textContainer else {
            return []
        }
        layoutManager.ensureLayout(for: textContainer)
        let separatorWidth = ceil(groupingSeparatorText(integralFont: mainFont, color: theme.colors.text).size().width)
        let containerOrigin = inputView.textContainerOrigin
        return offsets.map { offset in
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: offset)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let location = layoutManager.location(forGlyphAt: glyphIndex)
            return NSMakePoint(containerOrigin.x + lineRect.minX + location.x - separatorWidth, containerOrigin.y + lineRect.minY + location.y)
        }
    }

    private func updateGroupingSeparators() {
        groupingView.frame = inputView.frame
        let separatorText = groupingSeparatorText(integralFont: mainFont, color: theme.colors.text)
        groupingView.separators = groupingSeparatorOrigins().map { origin in
            return (separatorText, NSMakePoint(origin.x, origin.y - mainFont.ascender))
        }
    }

    private func applyAmountPresentation(preserving selection: NSRange? = nil) {
        let selectedRange = selection ?? inputView.selectedRange()
        inputView.setAttributedText(amountAttributedText(inputView.string, integralFont: mainFont, color: amountTextColor), selectedRange: selectedRange)
        updateTypingAttributes()
    }

    private func applyPlaceholderPresentation() {
        placeholderInputView.setAttributedText(amountAttributedText("0", integralFont: mainFont, color: amountTextColor), selectedRange: NSMakeRange(0, 0))
    }

    private func updateTypingAttributes() {
        let selection = inputView.selectedRange()
        let decimalRange = (inputView.string as NSString).range(of: walletAmountDecimalSeparator)
        let isFractional = decimalRange.location != NSNotFound && selection.location >= NSMaxRange(decimalRange)
        inputView.typingAttributes = [
            .font: isFractional ? fractionalFont(for: mainFont) : mainFont,
            .foregroundColor: amountTextColor
        ]
    }

    private func measuredAmountWidth(_ text: String, integralFont: NSFont) -> CGFloat {
        let textStorage = NSTextStorage(attributedString: amountAttributedText(text, integralFont: integralFont, color: theme.colors.text))
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSMakeSize(10_000, 10_000))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = .byClipping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).width) + walletAmountInputHorizontalInset * 2
    }

    private func setCursorToEnd() {
        inputView.setSelectedRange(NSRange(location: inputView.string.length, length: 0))
    }

    private func focusInput() {
        let wasUpdating = updating
        updating = true
        defer { updating = wasUpdating }
        window?.makeFirstResponder(inputView)
        setCursorToEnd()
    }

    private func autofocusIfNeeded() {
        guard !didAutofocus, window != nil, currentItem != nil else {
            return
        }
        didAutofocus = true
        focusInput()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            layer?.removeAnimation(forKey: walletAmountInputRefusalKey)
            stopSymbolAnimations()
            finishMotion()
        } else {
            needsLayout = true
            currentItem?.opening.update()
        }
        updateGramIcon()
        autofocusIfNeeded()
    }

    private func updateGramIcon() {
        let isGram = currentItem?.mode == .gram
        #if arch(arm64)
        guard !hasTransferredDiamond else {
            return
        }
        diamondView.update(size: NSMakeSize(walletAmountInteractiveDiamondCanvas, walletAmountInteractiveDiamondCanvas), diamondWidth: walletAmountInteractiveDiamondWidth, isVisible: visible && (isGram || isSwitchingSymbols), lightBackground: !theme.colors.isDark, metricsScale: walletAmountFieldScale)
        diamondView.isInteractionEnabled = visible && isGram && !isSwitchingSymbols
        #else
        if window != nil, isGram {
            startAnimationIfNeeded()
        } else {
            stopAnimation()
        }
        #endif
    }

    #if !arch(arm64)
    private func stopAnimation() {
        iconView.set(nil)
        didStartAnimation = false
    }

    private func startAnimationIfNeeded() {
        guard window != nil, !didStartAnimation else {
            return
        }
        guard let url = Bundle.main.url(forResource: "wallet_diamond", withExtension: "tgs"), let data = try? Data(contentsOf: url) else {
            return
        }
        didStartAnimation = true
        let size = NSMakeSize(walletAmountDiamondCanvas, walletAmountDiamondCanvas)
        iconView.set(LottieAnimation(compressed: data, key: .init(key: .bundle("wallet_diamond"), size: size), cachePurpose: .none, playPolicy: .onceEnd, maximumFps: 60))
    }
    #endif

    private func updatePlaceholderVisibility() {
        placeholderInputView.isHidden = !inputView.string.isEmpty
    }

    public override func updateColors() {
        super.updateColors()
        inputView.drawsBackground = false
        inputView.backgroundColor = .clear
        inputView.textColor = amountTextColor
        updateCaretOpacity()
        placeholderInputView.drawsBackground = false
        placeholderInputView.backgroundColor = .clear
        placeholderInputView.textColor = amountTextColor
        applyAmountPresentation()
        applyPlaceholderPresentation()
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = currentItem else {
            return
        }
        updating = true
        defer { updating = false }

        let isEditing = window?.firstResponder === inputView
        refreshRestingCaret()
        if appliedRevision != item.revision || appliedMode != item.mode || !isEditing {
            let text = walletSendInputText(amount: item.amount, mode: item.mode, rate: item.rate, fiatFractionDigits: item.fiatFractionDigits)
            if inputView.string != text {
                inputView.setText(text)
                setCursorToEnd()
            }
            lastValidText = text
        }
        appliedRevision = item.revision
        appliedMode = item.mode

        updatePlaceholderVisibility()

        let symbolLayout = TextViewLayout(.initialize(string: item.currency.symbol, color: walletAmountFiatColor, font: fiatSymbolFont), maximumNumberOfLines: 1)
        symbolLayout.measure(width: 60)
        symbolView.update(symbolLayout)
        updateGramIcon()

        let suffixText: String
        switch item.mode {
        case .gram:
            suffixText = strings().walletAmountRowItemGram
        case .fiat:
            suffixText = item.currency.code
        }
        let suffixColor = item.mode == .gram ? walletGramColor(for: theme.colors) : walletAmountFiatColor
        let suffixLayout = TextViewLayout(.initialize(string: suffixText, color: suffixColor, font: suffixFont), maximumNumberOfLines: 1)
        suffixLayout.measure(width: 150)
        let suffixChanged = currentSuffixText != nil && currentSuffixText != suffixText
        currentSuffixText = suffixText
        suffixView.update(suffixLayout)
        if animated, suffixChanged, rendersNativeText {
            walletAmountAnimateCurrencyChange(suffixView)
        }
        canvas.prepareGlyphs([
            WalletSendAmountGlyphAtlas.FontCharacters(font: mainFont, characters: "0123456789" + walletAmountDecimalSeparator + walletGroupingSeparator),
            WalletSendAmountGlyphAtlas.FontCharacters(font: fractionalFont(for: mainFont), characters: "0123456789" + walletAmountDecimalSeparator + walletGroupingSeparator),
            WalletSendAmountGlyphAtlas.FontCharacters(font: suffixFont, characters: "GRAM" + item.currency.code)
        ])

        updateColors()
        layoutAmount()
        updateOpening(item.opening.amount)
        autofocusIfNeeded()
    }

    public override func layout() {
        super.layout()
        layoutAmount()
        currentItem?.opening.update()
    }

    private var fieldWidth: CGFloat {
        return max(1, frame.width - 32)
    }

    private func layoutTarget(_ item: WalletAmountRowItem) -> Layout {
        let displayText = inputView.string.isEmpty ? "0" : inputView.string
        let amountFont = mainFont
        let measuredWidth = measuredAmountWidth(displayText, integralFont: amountFont)
        let textWidth = max(26, measuredWidth)
        let height = frame.height
        let fieldHeight = ceil(amountFont.ascender + abs(amountFont.descender)) + walletAmountInputVerticalInset * 2

        let symbolInk = walletAmountInkBounds(item.currency.symbol, font: fiatSymbolFont)
        let prefixWidth: CGFloat
        let prefixSpacing: CGFloat
        if item.mode == .gram {
            #if arch(arm64)
            prefixWidth = walletAmountInteractiveDiamondWidth
            #else
            prefixWidth = walletAmountDiamondCanvas * walletAmountDiamondWidthRatio
            #endif
            prefixSpacing = walletAmountDiamondSpacing - walletAmountInputHorizontalInset
        } else {
            prefixWidth = symbolInk.width
            prefixSpacing = walletAmountFiatSymbolSpacing(displayText: displayText, amountFont: amountFont)
        }
        let suffixSpacing: CGFloat = 4
        let totalWidth = prefixWidth + prefixSpacing + textWidth + suffixSpacing + suffixView.frame.width

        var x: CGFloat = 0
        let centerY = height / 2
        let fieldY = floorToScreenPixels(backingScaleFactor, centerY - fieldHeight / 2)

        #if arch(arm64)
        let gramFrame = NSMakeRect(floorToScreenPixels(backingScaleFactor, x + (prefixWidth - walletAmountInteractiveDiamondCanvas) / 2 - walletAmountInteractiveDiamondNudge), floorToScreenPixels(backingScaleFactor, centerY - walletAmountInteractiveDiamondCanvas / 2 - walletAmountInteractiveDiamondNudge), walletAmountInteractiveDiamondCanvas, walletAmountInteractiveDiamondCanvas)
        #else
        let gramFrame = NSMakeRect(x + floorToScreenPixels(backingScaleFactor, (prefixWidth - walletAmountDiamondCanvas) / 2), floorToScreenPixels(backingScaleFactor, centerY - walletAmountDiamondCanvas * walletAmountDiamondCenterRatio), walletAmountDiamondCanvas, walletAmountDiamondCanvas)
        #endif
        let amountBaseline = fieldY + walletAmountInputVerticalInset + amountFont.ascender
        let symbolBaseline = walletAmountFiatSymbolBaseline(amountBaseline: amountBaseline, amountFont: amountFont, symbolFont: fiatSymbolFont)
        let symbolLine = symbolView.textLayout?.lines.first?.frame ?? .zero
        let fiatFrame = NSRect(origin: NSMakePoint(x - symbolInk.minX - symbolLine.minX, floorToScreenPixels(backingScaleFactor, symbolBaseline - symbolLine.minY)), size: symbolView.frame.size)
        gramIconView.frame = gramFrame
        symbolView.frame = fiatFrame
        x += prefixWidth + prefixSpacing

        let inputFrame = NSMakeRect(x, fieldY, textWidth, fieldHeight)
        placeholderInputView.frame = inputFrame
        let emptyInputOffset = inputView.string.isEmpty ? max(0, measuredWidth - walletAmountInputHorizontalInset * 2) : 0
        inputView.frame = inputFrame.offsetBy(dx: emptyInputOffset, dy: 0)
        updateGroupingSeparators()
        x += textWidth + suffixSpacing

        suffixView.setFrameOrigin(NSMakePoint(x, floorToScreenPixels(backingScaleFactor, centerY - suffixView.frame.height / 2 + 5)))

        return Layout(width: totalWidth, height: height, gram: gramFrame, fiat: fiatFrame, caret: caretRect())
    }

    private var insertionIndicator: NSView? {
        if #available(macOS 14.0, *) {
            return inputView.subviews.first(where: { $0 is NSTextInsertionIndicator })
        }
        return nil
    }

    private func caretRect() -> CGRect {
        let fieldHeight = ceil(mainFont.ascender + abs(mainFont.descender)) + walletAmountInputVerticalInset * 2
        let indicatorFrame = insertionIndicator?.frame
        let y = indicatorFrame?.minY ?? 0
        let height = indicatorFrame?.height ?? fieldHeight
        guard let layoutManager = inputView.layoutManager, let textContainer = inputView.textContainer else {
            return NSMakeRect(inputView.frame.minX, inputView.frame.minY + y, 0, height)
        }
        layoutManager.ensureLayout(for: textContainer)
        let location = min(NSMaxRange(inputView.selectedRange()), inputView.string.length)
        let x: CGFloat
        if location < inputView.string.length {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: location)
            x = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil).minX + layoutManager.location(forGlyphAt: glyphIndex).x
        } else {
            x = layoutManager.usedRect(for: textContainer).maxX
        }
        return NSMakeRect(inputView.frame.minX + inputView.textContainerOrigin.x + x, inputView.frame.minY + y, 0, height)
    }

    private func amountGlyphs(_ item: WalletAmountRowItem) -> [WalletSendAmountGlyph] {
        let textView = inputView.string.isEmpty ? placeholderInputView : inputView
        let text = textView.string
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer, let storage = textView.textStorage else {
            return []
        }
        layoutManager.ensureLayout(for: textContainer)
        let color = theme.colors.text
        let fractionOffset = (text as NSString).range(of: walletAmountDecimalSeparator).location
        let containerOrigin = textView.textContainerOrigin
        var glyphs: [WalletSendAmountGlyph] = []
        var offset = 0
        for character in text {
            let string = String(character)
            let font = storage.attribute(.font, at: offset, effectiveRange: nil) as? NSFont ?? mainFont
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: offset)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let location = layoutManager.location(forGlyphAt: glyphIndex)
            let width = WalletSendAmountGlyphMetrics.width(string, font: font)
            let group: WalletSendAmountGlyph.Group = fractionOffset != NSNotFound && offset >= fractionOffset ? .fraction : .integer
            glyphs.append(WalletSendAmountGlyph(text: string, font: font, color: color, position: CGPoint(x: textView.frame.minX + containerOrigin.x + lineRect.minX + location.x + width / 2, y: textView.frame.minY + containerOrigin.y + lineRect.minY + location.y), group: group))
            offset += string.utf16.count
        }
        if textView === inputView {
            let separator = walletGroupingSeparator
            for origin in groupingSeparatorOrigins() {
                glyphs += WalletSendAmountGlyph.text(NSAttributedString(string: separator, attributes: [.font: mainFont, .foregroundColor: color]), origin: CGPoint(x: inputView.frame.minX + origin.x, y: inputView.frame.minY + origin.y), group: .grouping)
            }
        }
        if let suffixLayout = suffixView.textLayout, let line = suffixLayout.lines.first {
            glyphs += WalletSendAmountGlyph.text(suffixLayout.attributedString, origin: CGPoint(x: suffixView.frame.minX + line.frame.minX, y: suffixView.frame.minY + line.frame.minY), group: .suffix)
        }
        return glyphs
    }

    private func layoutAmount() {
        guard !rendering, let item = currentItem else {
            return
        }
        rendering = true
        defer { rendering = false }
        let now = CACurrentMediaTime()
        let sourceLayout = presentationLayout(at: now)
        let targetLayout = layoutTarget(item)
        let rawText = inputView.string
        let glyphs = amountGlyphs(item)
        let selection = inputView.selectedRange()
        let modeChanged = previousMode != nil && previousMode != item.mode
        let sizeChanged = availableWidth != frame.width
        availableWidth = frame.width
        if glyphs != motion.target {
            let contentChanged = previousText != rawText || modeChanged || glyphs.count != motion.target.count
                || zip(glyphs, motion.target).contains { lhs, rhs in
                    lhs.text != rhs.text || lhs.font != rhs.font || lhs.color != rhs.color || lhs.group != rhs.group
                }
            let mayAnimate = contentChanged && previousMode != nil && visible && canvas.isAvailable && !sizeChanged && selection.length == 0
            let oldValue = Double(previousText.replacingOccurrences(of: walletAmountDecimalSeparator, with: ".")) ?? 0.0
            let newValue = Double(rawText.replacingOccurrences(of: walletAmountDecimalSeparator, with: ".")) ?? 0.0
            let timing = mayAnimate ? WalletSendAmountMotionTiming(spin: modeChanged, up: newValue >= oldValue, start: now) : nil
            layoutFrom = sourceLayout ?? targetLayout
            layoutTo = targetLayout
            motion.update(glyphs, width: targetLayout.width, timing: timing, at: now, frameDuration: frameDuration,
                fromPlaceholder: previousText.isEmpty && !rawText.isEmpty && !modeChanged)
            item.clock.timing = timing
            if modeChanged {
                switchSymbols(timing: timing, at: now)
            } else if previousMode == nil {
                stopSymbolAnimations()
            }
        } else if previousSelection != selection {
            motion.finish()
        }
        previousText = rawText
        previousMode = item.mode
        previousSelection = selection
        if motion.isAnimating(at: now), visible, !sizeChanged {
            setNativeTextVisible(false)
            renderFrame(at: now)
            animator.isPaused = opening != nil
        } else {
            layoutTo = targetLayout
            currentLayout = targetLayout
            finishMotion()
        }
    }

    private func setNativeTextVisible(_ visible: Bool) {
        let wasRendering = rendering
        rendering = true
        defer { rendering = wasRendering }
        let visible = !canvas.isAvailable || (opening == nil && (visible || !canvas.hasFrame))
        if rendersNativeText != visible {
            rendersNativeText = visible
            inputView.textColor = amountTextColor
            placeholderInputView.textColor = amountTextColor
            applyAmountPresentation()
            applyPlaceholderPresentation()
        }
        groupingView.isHidden = !visible
        suffixView.isHidden = !visible
        canvas.isHidden = visible
    }

    private func presentationLayout(at time: Double) -> Layout? {
        if let timing = motion.timing, let from = layoutFrom, let to = layoutTo {
            var layout = from.interpolate(to: to, progress: timing.layoutProgress(at: time))
            layout.width += motion.widthAdjustment(at: time)
            layout.caret.origin.x = motion.caretPosition(at: time, fromX: from.caret.midX, toX: to.caret.midX) - layout.caret.width / 2.0
            return layout
        }
        return currentLayout
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if let lastFrameTime {
            frameDuration += (min(max(now - lastFrameTime, 1.0 / 240.0), 1.0 / 30.0) - frameDuration) * 0.3
        }
        lastFrameTime = now
        renderFrame(at: now)
    }

    private func renderFrame(at now: Double = CACurrentMediaTime()) {
        guard opening != nil || motion.isAnimating(at: now), let layout = presentationLayout(at: now) else {
            finishMotion()
            return
        }
        let wasRendering = rendering
        rendering = true
        defer { rendering = wasRendering }
        currentLayout = layout
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(layout: layout)
        drawText(layout: layout, at: now)
        moveCaret(to: layout.caret)
        CATransaction.commit()
    }

    private func drawText(layout: Layout, at now: Double) {
        canvas.isRenderingEnabled = visible
        let width = ceil(max(fieldWidth, layout.width, layoutFrom?.width ?? 0, layoutTo?.width ?? 0) / 64.0) * 64.0
        canvas.frame = CGRect(x: -32.0, y: -32.0, width: width + 64.0, height: layout.height + 64.0)
        canvas.frameDuration = frameDuration
        let frameSprites = motion.frame(at: now, frameDuration: frameDuration)
        let openingText = walletSendAmountOpeningText(opening, width: layout.width, gramMidX: layout.gram.midX, textMinX: frameSprites.map { $0.glyph.leadingEdge }.min() ?? 0.0, textMaxX: frameSprites.map { $0.glyph.leadingEdge + $0.glyph.width }.max() ?? 0.0, scale: walletAmountFieldScale)
        let sprites = frameSprites.map { sprite in
            var sprite = sprite
            sprite.glyph.position.x += 32.0 + openingText.shift
            sprite.glyph.position.y += 32.0
            sprite.alpha *= openingText.alpha
            return sprite
        }
        canvas.update(sprites: sprites, isAnimating: opening != nil || motion.isAnimating(at: now), reveal: openingText.reveal)
        #if arch(arm64)
        updateDiamondRefraction(textOffset: openingText.shift)
        #endif
    }

    private func apply(layout: Layout) {
        let scale = min(1.0, fieldWidth / max(1.0, layout.width))
        let size = NSMakeSize(layout.width * scale, layout.height * scale)
        contentView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - size.width) / 2), floorToScreenPixels(backingScaleFactor, (frame.height - size.height) / 2), size.width, size.height)
        contentView.bounds = NSMakeRect(0, 0, layout.width, layout.height)
        for (view, rect) in [(gramIconView, layout.gram), (symbolView as NSView, layout.fiat)] {
            let center = walletSendAmountOpeningCenter(canvas.isAvailable ? opening : nil, rect: rect, width: layout.width, scale: walletAmountFieldScale)
            view.setFrameOrigin(NSMakePoint(center.x - view.frame.width / 2, center.y - view.frame.height / 2))
        }
        #if arch(arm64)
        diamondView.updateOpeningScale(canvas.isAvailable ? opening?.scale : nil)
        #endif
        if opening != nil {
            layer?.masksToBounds = false
            layer?.zPosition = 1
        }
    }

    private func refreshRestingCaret() {
        guard !motion.isAnimating(at: CACurrentMediaTime()), var layout = currentLayout else {
            return
        }
        layout.caret = caretRect()
        currentLayout = layout
    }

    private func moveCaret(to caret: CGRect) {
        guard let indicator = insertionIndicator else {
            return
        }
        var frame = indicator.frame
        frame.origin.x = caret.minX - inputView.frame.minX
        indicator.frame = frame
    }

    private func finishMotion() {
        let wasRendering = rendering
        rendering = true
        defer { rendering = wasRendering }
        animator.isPaused = true
        lastFrameTime = nil
        motion.finish()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let layout = layoutTo {
            currentLayout = layout
            apply(layout: layout)
        }
        if let layout = currentLayout, visible {
            drawText(layout: layout, at: CACurrentMediaTime())
        }
        CATransaction.commit()
        setNativeTextVisible(nativeInteraction || !visible)
        if var layout = currentLayout {
            layout.caret = caretRect()
            moveCaret(to: layout.caret)
            currentLayout = layout
            layoutTo = layout
        }
        previousSelection = inputView.selectedRange()
        updateGramIcon()
    }

    #if arch(arm64)
    private func updateDiamondRefraction(textOffset: CGFloat) {
        let displayText = inputView.string.isEmpty ? "0" : inputView.string
        guard let item = currentItem, let digit = walletAmountRefractionDigit(displayText, mode: item.mode, decimalSeparator: walletAmountDecimalSeparator) else {
            diamondView.updateRefractionSource(nil)
            return
        }
        let index = (displayText as NSString).substring(to: digit.offset).count
        guard index < motion.target.count, motion.target[index].text == digit.text else {
            diamondView.updateRefractionSource(nil)
            return
        }
        let glyph = motion.target[index]
        let scale = backingScaleFactor
        if refractionMask?.text != glyph.text || refractionMask?.font != glyph.font || refractionMask?.scale != scale {
            refractionMask = walletAmountGlyphMask(glyph.text, font: glyph.font, scale: scale, device: MetalEngine.shared.device)
        }
        guard let mask = refractionMask else {
            diamondView.updateRefractionSource(nil)
            return
        }
        let dx = glyph.position.x + textOffset - diamondView.frame.midX
        let dy = glyph.position.y - diamondView.frame.midY
        diamondView.updateRefractionSource(InteractiveDiamondView.RefractionSource(texture: mask.texture, uv: SIMD4(0, 0, 1, 1), rect: mask.rect.offsetBy(dx: dx, dy: dy)))
    }
    #endif

    public override func hasFirstResponder() -> Bool {
        return true
    }

    public override var firstResponder: NSResponder? {
        return inputView
    }

    var hasInputText: Bool {
        return !inputView.string.isEmpty
    }

    public override var mouseInsideField: Bool {
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        currentItem?.opening.finish(animated: true)
        if window?.firstResponder !== inputView {
            focusInput()
        } else {
            super.mouseDown(with: event)
        }
    }

    public override func shakeView() {
        shake(beep: true)
    }

    private func inputRejected() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = self.layer else {
            return
        }
        let key = walletAmountInputRefusalKey
        let initialOffset: CGFloat
        if layer.animation(forKey: key) != nil {
            initialOffset = (layer.presentation()?.transform.m41 ?? layer.transform.m41) - layer.transform.m41
        } else {
            initialOffset = 0
        }
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = (0 ... 60).map { step -> NSNumber in
            let t = CGFloat(step) / 60
            let carry = max(0, 1 - 6 * t)
            let x = 9 * sin(6 * .pi * t) * (1 - t) + initialOffset * carry * carry
            return NSNumber(value: Double(x))
        }
        animation.duration = 0.42
        animation.calculationMode = .linear
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isAdditive = true
        layer.add(animation, forKey: key)
    }

    private var canEditAmount: Bool {
        guard let item = currentItem, !walletAmountDecimalSeparator.isEmpty else {
            return false
        }
        if item.mode == .fiat {
            guard let rate = item.rate, rate.isFinite, rate > 0.0 else {
                return false
            }
        }
        return true
    }

    private var isHandlingTextChange = false

    private func applyInputText(_ text: String, selection: NSRange) {
        guard let item = currentItem, let nanograms = walletSendNanograms(text: text, mode: item.mode, rate: item.rate, decimalSeparator: walletAmountDecimalSeparator) else {
            return
        }
        isHandlingTextChange = true
        defer {
            isHandlingTextChange = false
        }
        refreshRestingCaret()
        if text != inputView.string || selection != inputView.selectedRange() {
            nativeInteraction = false
        }
        inputView.setAttributedText(NSAttributedString(string: text), selectedRange: selection)
        lastValidText = text
        item.updated(nanograms)
        applyAmountPresentation()
        updatePlaceholderVisibility()
        layoutAmount()
    }

    private func handleTextChange() {
        guard !isHandlingTextChange, let item = currentItem else {
            return
        }
        let previousText = lastValidText
        let previousLength = (previousText as NSString).length
        if let edit = walletSendReplacingAmountText(previousText, range: NSRange(location: 0, length: previousLength), replacement: inputView.string, mode: item.mode, rate: item.rate, decimalSeparator: walletAmountDecimalSeparator) {
            applyInputText(edit.text, selection: edit.selection)
        } else {
            applyInputText(previousText, selection: NSRange(location: previousLength, length: 0))
        }
    }

    public func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard textView === inputView, let item = currentItem, let replacementString else {
            return true
        }
        guard canEditAmount, !replacementString.isEmpty || affectedCharRange.length > 0 else {
            return false
        }
        switch walletSendAmountEditResult(textView.string, range: affectedCharRange, replacement: replacementString, mode: item.mode, rate: item.rate, decimalSeparator: walletAmountDecimalSeparator) {
        case .ignored:
            break
        case .rejected:
            inputRejected()
        case let .accepted(edit):
            applyInputText(edit.text, selection: edit.selection)
            inputAccepted(replacementString)
        }
        return false
    }

    private func inputAccepted(_ insertedText: String) {
        guard window != nil else {
            return
        }
        #if arch(arm64)
        if currentItem?.mode == .gram {
            diamondView.spin(walletAmountSpinVelocity(insertedText), decay: 0.7)
        }
        #endif
        pulseSymbols(at: CACurrentMediaTime())
    }

    private var symbolViews: [(NSView, Bool)] {
        return [(gramIconView, true), (symbolView, false)]
    }

    private func switchSymbols(timing: WalletSendAmountMotionTiming?, at now: Double) {
        guard let timing, let item = currentItem else {
            stopSymbolAnimations()
            return
        }
        var transition = WalletAmountSymbolTransition(timing: timing, toGram: item.mode == .gram)
        if let previous = symbolTransition {
            transition.gramFrom = previous.state(gram: true, at: now)
            transition.fiatFrom = previous.state(gram: false, at: now)
        }
        symbolTransition = transition
        updateGramIcon()
        #if arch(arm64)
        diamondView.spin(timing.up ? -9.0 : 9.0, decay: 0.8)
        #endif

        for (view, gram) in symbolViews {
            guard let layer = view.layer else {
                continue
            }
            let arriving = gram == transition.toGram
            let duration = arriving ? transition.duration : timing.duration
            let count = Int(ceil(duration * 120.0))
            let states = (0 ... count).map { index in
                transition.state(gram: gram, at: timing.start + duration * Double(index) / Double(count))
            }
            let transform = CAKeyframeAnimation(keyPath: "transform")
            transform.values = states.map { NSValue(caTransform3D: walletAmountCenteredTransform($0.transform, layer: layer)) }
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = states.map { NSNumber(value: Double($0.alpha)) }
            let blur = CAKeyframeAnimation(keyPath: "filters.gaussianBlur.inputRadius")
            blur.values = states.map { NSNumber(value: Double($0.blur)) }
            let animations = timing.reduced ? [opacity] : [transform, opacity, blur]
            for animation in animations {
                animation.duration = duration
                animation.calculationMode = .linear
            }
            view.isHidden = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.removeAnimation(forKey: "walletAmountCurrencyBlur")
            layer.transform = CATransform3DIdentity
            layer.opacity = arriving ? 1.0 : 0.0
            if !timing.reduced, let filter = ee2_makeBlurFilter() {
                filter.setValue(0.0 as NSNumber, forKey: "inputRadius")
                layer.filters = [filter]
            }
            CATransaction.commit()
            let group = CAAnimationGroup()
            group.animations = animations
            group.duration = duration
            group.beginTime = layer.convertTime(timing.start, from: nil)
            group.timingFunction = CAMediaTimingFunction(name: .linear)
            group.completion = { [weak self, weak layer] completed in
                guard let self, completed, self.symbolTransition?.timing.start == timing.start else {
                    return
                }
                layer?.filters = nil
                if arriving {
                    self.symbolTransition = nil
                }
                self.updateGramIcon()
            }
            layer.add(group, forKey: walletAmountSymbolTransitionKey)
        }
        pulseSymbols(at: now)
    }

    private func stopSymbolAnimations() {
        symbolTransition = nil
        let isGram = currentItem?.mode == .gram
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (view, gram) in symbolViews {
            guard let layer = view.layer else {
                continue
            }
            layer.removeAnimation(forKey: walletAmountSymbolTransitionKey)
            layer.removeAnimation(forKey: walletAmountSymbolPulseKey)
            layer.transform = CATransform3DIdentity
            layer.sublayerTransform = CATransform3DIdentity
            layer.filters = nil
            layer.opacity = gram == isGram ? 1.0 : 0.0
            view.isHidden = false
        }
        CATransaction.commit()
        updateGramIcon()
    }

    private func pulseSymbols(at now: Double) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }
        for view in [gramIconView, symbolView as NSView] {
            guard let layer = view.layer else {
                continue
            }
            #if arch(arm64)
            if view === diamondView, diamondView.isExpanded {
                continue
            }
            #endif
            let fromScale = layer.presentation()?.sublayerTransform.m11 ?? 1.0
            let pulse = CAKeyframeAnimation(keyPath: "sublayerTransform")
            pulse.values = (0 ... 51).map { index -> NSValue in
                let t = CGFloat(index) / 51.0
                let scale = walletAmountPulseScale(t, fromScale: fromScale)
                return NSValue(caTransform3D: walletAmountCenteredTransform(CATransform3DMakeScale(scale, scale, 1.0), layer: layer))
            }
            pulse.duration = 0.42
            pulse.beginTime = layer.convertTime(now, from: nil)
            pulse.calculationMode = .linear
            layer.add(pulse, forKey: walletAmountSymbolPulseKey)
        }
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView, textView === inputView else {
            return
        }
        updateTypingAttributes()
        if !isHandlingTextChange, !rendering, !updating, previousText == inputView.string, previousSelection != inputView.selectedRange() {
            nativeInteraction = true
            finishMotion()
        }
    }

    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let item = currentItem else {
            return false
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            item.onReturn()
            return true
        }
        if commandSelector == #selector(NSResponder.deleteBackward(_:)), textView.string.isEmpty {
            if canEditAmount {
                inputRejected()
            }
            return true
        }
        return false
    }
}
