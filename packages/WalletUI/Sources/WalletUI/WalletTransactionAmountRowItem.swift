import Cocoa
import TGUIKit
import TelegramMedia
import WalletContext
import TelegramTheme
import TelegramContext
import GeneralRows
import Localization

private let walletTransactionHeroSize = NSMakeSize(110, 110)
private let walletTransactionHeroTopTrim: CGFloat = 22
private let walletTransactionHeroAmountOverlap: CGFloat = 14
private let walletTransactionAmountFiatSpacing: CGFloat = 1
private let walletTransactionBottomInset: CGFloat = 8
private let walletTransactionIntegralFontSize: CGFloat = 48
private let walletTransactionFractionalFontSize: CGFloat = 32

enum WalletTransactionIntro {
    static let rollDuration: Double = 0.42
    static let minimumRollDuration: Double = 0.3
    static let fiatDelay: Double = 0.05
    static let addressScrambleDuration: Double = 0.08
    static let addressRevealSpeed: Double = 1.5
    static let duration: Double = 0.5
}

@available(macOS 10.15, *)
private func walletAmountRoundedFont(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .bold)
    if let descriptor = base.fontDescriptor.withDesign(.rounded), let font = NSFont(descriptor: descriptor, size: size) {
        return font
    }
    return base
}

private func formatWalletTokenAmountText(_ value: Int64, decimalDigits: Int) -> String {
    let decimalSeparator = Locale.current.decimalSeparator ?? "."
    var digits = String(value.magnitude)
    while digits.count <= decimalDigits {
        digits.insert("0", at: digits.startIndex)
    }

    let fractionStart = digits.index(digits.endIndex, offsetBy: -decimalDigits)
    let integralPart = String(digits[..<fractionStart])
    var fractionalPart = String(digits[fractionStart...])
    while fractionalPart.last == "0" {
        fractionalPart.removeLast()
    }

    var result = integralPart
    if !fractionalPart.isEmpty {
        result.append(decimalSeparator)
        result.append(fractionalPart)
    }
    return result
}

@available(macOS 10.15, *)
private func walletTransactionAmountAttributedString(amountText: String, amountColor: NSColor, currencyText: String, currencyColor: NSColor, integralFontSize: CGFloat, fractionalFontSize: CGFloat) -> NSAttributedString {
    let result = NSMutableAttributedString()
    result.append(tonAmountAttributedString(amountText, integralFont: walletAmountRoundedFont(integralFontSize), fractionalFont: walletAmountRoundedFont(fractionalFontSize), color: amountColor))
    result.append(.initialize(string: " " + currencyText, color: currencyColor, font: walletAmountRoundedFont(fractionalFontSize)))
    return result
}

private func walletTransactionHeroImage(_ name: String) -> CGImage? {
    guard let image = NSImage(named: name)?.copy() as? NSImage else {
        return nil
    }
    let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
    image.size = NSMakeSize(floor(walletTransactionHeroSize.height * aspect), walletTransactionHeroSize.height)
    return image.precomposed()
}

public final class WalletTransactionAmountRowItem: GeneralRowItem {
    fileprivate enum Hero {
        case animation
        case image(CGImage?)
    }

    fileprivate private(set) var amountLayout: TextViewLayout
    fileprivate let fiatLayout: TextViewLayout?
    fileprivate let processingDotLayout: TextViewLayout?
    fileprivate let processingLayout: TextViewLayout?
    fileprivate let hero: Hero
    fileprivate let isPending: Bool
    var intro: WalletOpenIntro?

    private let amountText: String
    private let amountColor: NSColor
    private let currencyText: String
    private let currencyColor: NSColor

    @available(macOS 10.15, *)
    public init(_ initialSize: NSSize, stableId: AnyHashable, amount: Int64, direction: WalletContext.Transaction.Direction, currency: WalletContext.Transaction.Currency, fiatText: String?, isPending: Bool, isFailed: Bool = false, viewType: GeneralViewType) {
        self.isPending = isPending
        let formattedAmount: String
        let absoluteAmount = abs(amount)
        switch currency {
        case .ton:
            formattedAmount = formatTonAmountText(absoluteAmount, maxDecimalPositions: nil)
            self.currencyText = strings().walletTransactionAmountRowItemGram
            self.hero = .animation
        case .usdt:
            formattedAmount = formatWalletTokenAmountText(absoluteAmount, decimalDigits: 6)
            self.currencyText = strings().walletTransactionAmountRowItemUsdt
            self.hero = .image(walletTransactionHeroImage("Wallet_TransactionUsdtLarge"))
        }

        let amountText: String
        let regularAmountColor: NSColor
        switch direction {
        case .incoming:
            amountText = "+\(formattedAmount)"
            switch currency {
            case .ton:
                regularAmountColor = theme.colors.greenUI
            case .usdt:
                regularAmountColor = NSColor(rgb: 0x0B9696)
            }
        case .outgoing:
            amountText = "–\(formattedAmount)"
            regularAmountColor = theme.colors.text
        case .unknown:
            amountText = formattedAmount
            regularAmountColor = theme.colors.text
        }

        self.amountText = amountText
        self.amountColor = isPending ? theme.colors.grayText : regularAmountColor
        let regularCurrencyColor: NSColor
        switch currency {
        case .ton:
            regularCurrencyColor = walletGramColor(for: theme.colors)
        case .usdt:
            regularCurrencyColor = walletClassicAccent
        }
        self.currencyColor = isPending ? regularCurrencyColor.withAlphaComponent(0.5) : regularCurrencyColor
        self.amountLayout = TextViewLayout(walletTransactionAmountAttributedString(amountText: amountText, amountColor: self.amountColor, currencyText: self.currencyText, currencyColor: self.currencyColor, integralFontSize: walletTransactionIntegralFontSize, fractionalFontSize: walletTransactionFractionalFontSize), maximumNumberOfLines: 1)

        if let fiatText = fiatText ?? (isPending ? "—" : nil) {
            self.fiatLayout = TextViewLayout(.initialize(string: fiatText, color: theme.colors.grayText, font: .normal(15)), maximumNumberOfLines: 1)
        } else {
            self.fiatLayout = nil
        }
        if isPending || isFailed {
            self.processingDotLayout = TextViewLayout(.initialize(string: "•", color: theme.colors.grayText, font: .normal(15)), maximumNumberOfLines: 1)
            if isFailed {
                self.processingLayout = TextViewLayout(.initialize(string: strings().walletTransactionAmountRowItemFailed, color: theme.colors.redUI, font: .normal(15)), maximumNumberOfLines: 1)
            } else {
                self.processingLayout = TextViewLayout(.initialize(string: strings().walletTransactionAmountRowItemProcessing, color: walletClassicAccent, font: .normal(15)), maximumNumberOfLines: 1)
            }
        } else {
            self.processingDotLayout = nil
            self.processingLayout = nil
        }

        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        let availableWidth = max(80, width - 60)
        if #available(macOS 10.15, *) {
            amountLayout.measure(width: .greatestFiniteMagnitude)
            if amountLayout.layoutSize.width > availableWidth {
                let scale = availableWidth / amountLayout.layoutSize.width
                let integralFontSize = max(22, floor(walletTransactionIntegralFontSize * scale))
                let fractionalFontSize = max(15, floor(walletTransactionFractionalFontSize * scale))
                amountLayout = TextViewLayout(walletTransactionAmountAttributedString(amountText: amountText, amountColor: amountColor, currencyText: currencyText, currencyColor: currencyColor, integralFontSize: integralFontSize, fractionalFontSize: fractionalFontSize), maximumNumberOfLines: 1)
            }
        }
        amountLayout.measure(width: availableWidth)
        fiatLayout?.measure(width: .greatestFiniteMagnitude)
        processingDotLayout?.measure(width: .greatestFiniteMagnitude)
        processingLayout?.measure(width: .greatestFiniteMagnitude)
        return true
    }

    public override var height: CGFloat {
        var height: CGFloat = walletTransactionHeroSize.height - walletTransactionHeroTopTrim - walletTransactionHeroAmountOverlap + amountLayout.layoutSize.height
        if let fiatLayout = fiatLayout {
            height += walletTransactionAmountFiatSpacing + fiatLayout.layoutSize.height
        }
        return height + walletTransactionBottomInset
    }

    public override func viewClass() -> AnyClass {
        return WalletTransactionAmountRowView.self
    }

    public override var accessibilityLabel: String? {
        let text = amountLayout.attributedString.string
        return text.isEmpty ? nil : text
    }

    public override var accessibilityValue: String? {
        let parts = [fiatLayout?.attributedString.string, processingLayout?.attributedString.string].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class WalletPendingAmountShimmerView: View {
    public let contentView = View()
    private let maskLayer = CAGradientLayer()
    private var shouldAnimate = false

    public override init() {
        super.init()

        userInteractionEnabled = false
        contentView.userInteractionEnabled = false
        maskLayer.colors = [
            NSColor.white.withAlphaComponent(1.0).cgColor,
            NSColor.white.withAlphaComponent(0.3).cgColor,
            NSColor.white.withAlphaComponent(1.0).cgColor
        ]
        maskLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        maskLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        addSubview(contentView)
        contentView.layer?.mask = maskLayer
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setAnimating(_ value: Bool) {
        shouldAnimate = value
        updateAnimation()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    public override func layout() {
        super.layout()
        contentView.frame = bounds

        let gradientWidth: CGFloat = 80.0
        let travelDistance = bounds.width + gradientWidth
        let maskWidth = bounds.width + 2.0 * travelDistance
        let dipHalfFraction = maskWidth > 0.0 ? (gradientWidth * 0.5) / maskWidth : 0.0
        maskLayer.locations = [
            NSNumber(value: 0.5 - dipHalfFraction),
            0.5,
            NSNumber(value: 0.5 + dipHalfFraction)
        ]
        maskLayer.bounds = NSMakeRect(0.0, 0.0, maskWidth, bounds.height)
        maskLayer.position = NSMakePoint(-gradientWidth * 0.5, bounds.height * 0.5)
        maskLayer.removeAnimation(forKey: "walletPendingShimmer")
        if shouldAnimate, window != nil {
            addAnimation()
        }
    }

    private func updateAnimation() {
        if shouldAnimate, window != nil {
            addAnimation()
        } else {
            maskLayer.removeAnimation(forKey: "walletPendingShimmer")
        }
    }

    private func addAnimation() {
        guard maskLayer.animation(forKey: "walletPendingShimmer") == nil else {
            return
        }
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = 0.0
        animation.toValue = bounds.width + 80.0
        animation.isAdditive = true
        animation.duration = 1.0
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        maskLayer.add(animation, forKey: "walletPendingShimmer")
    }
}

final class WalletTransactionAmountRowView: GeneralRowView, WalletIntroParticipant {
    private enum IntroPhase {
        case idle
        case pending
        case playing
    }

    private let amountView = TextView()
    private let heroImageView = ImageView(frame: walletTransactionHeroSize.bounds)
    private let heroDiamondView = WalletDiamondHeroView(frame: walletTransactionHeroSize.bounds)
    private let fiatView = TextView()
    private let processingDotView = TextView()
    private let processingView = TextView()
    private let pendingShimmerView = WalletPendingAmountShimmerView()
    private var introPhase: IntroPhase = .idle
    private var digitRolls: [WalletDigitRoll] = []

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        heroImageView.contentGravity = .resizeAspect
        heroImageView.isAccessibilityDecorative = true

        for textView in [amountView, fiatView, processingDotView, processingView] {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
        }

        addSubview(heroImageView)
        addSubview(heroDiamondView)
        addSubview(amountView)
        addSubview(fiatView)
        addSubview(processingDotView)
        addSubview(processingView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if arch(arm64)
    @available(macOS 10.15, *)
    func takeTransferDiamond() -> WalletSendTransferAnimationSource? {
        return heroDiamondView.isHidden ? nil : heroDiamondView.takeTransferDiamond()
    }
    #endif

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? WalletTransactionAmountRowItem else {
            return
        }

        amountView.update(item.amountLayout)

        switch item.hero {
        case .animation:
            heroImageView.isHidden = true
            heroDiamondView.isHidden = false
            heroDiamondView.layer?.opacity = item.isPending ? 0.5 : 1.0
            heroDiamondView.isActive = true
        case let .image(image):
            heroDiamondView.isActive = false
            heroDiamondView.isHidden = true
            heroImageView.isHidden = image == nil
            heroImageView.image = image
            heroImageView.layer?.opacity = item.isPending ? 0.5 : 1.0
        }

        if let fiatLayout = item.fiatLayout {
            fiatView.isHidden = false
            fiatView.update(fiatLayout)
        } else {
            fiatView.isHidden = true
        }

        if let processingDotLayout = item.processingDotLayout, let processingLayout = item.processingLayout {
            processingDotView.isHidden = false
            processingView.isHidden = false
            processingDotView.update(processingDotLayout)
            processingView.update(processingLayout)
        } else {
            processingDotView.isHidden = true
            processingView.isHidden = true
        }
        if item.isPending {
            if pendingShimmerView.superview == nil {
                addSubview(pendingShimmerView)
            }
            if amountView.superview !== pendingShimmerView.contentView {
                pendingShimmerView.contentView.addSubview(amountView)
            }
        } else {
            if amountView.superview !== self {
                addSubview(amountView)
            }
            pendingShimmerView.removeFromSuperview()
        }
        pendingShimmerView.setAnimating(item.isPending)

        item.intro?.attach(self)
        refreshDigitRolls()

        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, introPhase == .playing {
            introPhase = .idle
            removeDigitRolls()
        }
    }

    private var rollingViews: [TextView] {
        return [amountView, fiatView].filter { !$0.isHidden }
    }

    private func refreshDigitRolls() {
        switch introPhase {
        case .idle:
            break
        case .pending:
            removeDigitRolls()
            digitRolls = rollingViews.compactMap { WalletDigitRoll(textView: $0, mode: .fromZero(maxTurns: 2)) }
        case .playing:
            if !digitRolls.allSatisfy({ roll in rollingViews.contains(where: { roll.matches($0) }) }) {
                introPhase = .idle
                removeDigitRolls()
            }
        }
    }

    private func removeDigitRolls() {
        for roll in digitRolls {
            roll.remove()
        }
        digitRolls = []
    }

    func prepareIntro() {
        introPhase = .pending
        refreshDigitRolls()
    }

    func cancelIntro() {
        introPhase = .idle
        removeDigitRolls()
    }

    func playIntro(at time: CFTimeInterval, pace: Double) {
        guard introPhase == .pending else {
            return
        }
        refreshDigitRolls()
        guard !digitRolls.isEmpty else {
            introPhase = .idle
            return
        }
        introPhase = .playing
        for roll in digitRolls {
            let delay = roll.matches(fiatView) ? WalletTransactionIntro.fiatDelay * pace : 0.0
            roll.play(at: time + delay, duration: WalletTransactionIntro.rollDuration * pace - delay, timingFunction: CAMediaTimingFunction(controlPoints: 0.25, 0.0, 0.2, 1.0), completion: { [weak self, weak roll] in
                guard let self, let roll, let index = self.digitRolls.firstIndex(where: { $0 === roll }) else {
                    return
                }
                roll.remove()
                self.digitRolls.remove(at: index)
                if self.digitRolls.isEmpty {
                    self.introPhase = .idle
                }
            })
        }
    }

    public override func layout() {
        super.layout()

        guard let item = item as? WalletTransactionAmountRowItem else {
            return
        }

        let heroFrame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - walletTransactionHeroSize.width) / 2), -walletTransactionHeroTopTrim, walletTransactionHeroSize.width, walletTransactionHeroSize.height)
        heroImageView.frame = heroFrame
        heroDiamondView.frame = heroFrame

        let amountFrame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.amountLayout.layoutSize.width) / 2), heroFrame.maxY - walletTransactionHeroAmountOverlap, amountView.frame.width, amountView.frame.height)
        if item.isPending {
            pendingShimmerView.frame = amountFrame
            amountView.frame = amountFrame.offsetBy(dx: -amountFrame.minX, dy: -amountFrame.minY)
        } else {
            amountView.frame = amountFrame
        }

        if !fiatView.isHidden {
            let statusWidth: CGFloat
            if !processingDotView.isHidden, !processingView.isHidden {
                statusWidth = 6 + processingDotView.frame.width + 4 + processingView.frame.width
            } else {
                statusWidth = 0
            }
            let lineWidth = fiatView.frame.width + statusWidth
            let lineX = floorToScreenPixels(backingScaleFactor, (frame.width - lineWidth) / 2)
            let lineY = amountFrame.maxY + walletTransactionAmountFiatSpacing
            fiatView.setFrameOrigin(NSMakePoint(lineX, lineY))
            if statusWidth > 0 {
                processingDotView.setFrameOrigin(NSMakePoint(fiatView.frame.maxX + 6, lineY))
                processingView.setFrameOrigin(NSMakePoint(processingDotView.frame.maxX + 4, lineY))
            }
        }
    }
}
