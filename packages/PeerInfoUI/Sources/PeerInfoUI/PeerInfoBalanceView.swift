import Cocoa
import TGUIKit
import TelegramTheme
import CurrencyFormat
import Localization

private func peerInfoBalanceIcon(_ color: NSColor, colorfull: Bool) -> CGImage? {
    let fill = colorfull ? color.withAlphaComponent(color.alphaComponent * 0.45) : color
    guard let icon = NSImage(named: "Wallet_TransactionGram")?.precomposed(fill), let sparkle = NSImage(named: "Wallet_TransactionGramHighlight")?.precomposed(color) else {
        return nil
    }
    return generateImage(NSMakeSize(14, 14), contextGenerator: { size, ctx in
        ctx.clear(size.bounds)
        ctx.draw(icon, in: size.bounds)
        ctx.setBlendMode(.destinationOut)
        ctx.draw(sparkle, in: size.bounds)
        if colorfull {
            ctx.setBlendMode(.normal)
            ctx.draw(sparkle, in: size.bounds)
        }
    })
}

public final class PeerInfoBalanceView: View {
    public static let height: CGFloat = 20
    static let spacing: CGFloat = 7
    private static let inset: CGFloat = 8

    private let titleView = TextView()
    private let iconView = ImageView()
    private let amountView = TextView()
    private let chevron = ImageView()
    private var glassView: LiquidGlassView?
    public let control = Control()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        control.layer?.masksToBounds = false
        addSubview(control)
        control.addSubview(titleView)
        control.addSubview(iconView)
        control.addSubview(amountView)
        control.addSubview(chevron)

        for textView in [titleView, amountView] {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            textView.isAccessibilityDecorative = true
        }
        iconView.isAccessibilityDecorative = true
        chevron.isAccessibilityDecorative = true

        control.scaleOnClick = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(balance: Int64, textColor: NSColor, iconColor: NSColor, backgroundColor: NSColor, colorfull: Bool, useGlass: Bool) {
        if useGlass {
            let glass: LiquidGlassView
            if let glassView {
                glass = glassView
            } else {
                glass = LiquidGlassView(frame: bounds, cornerRadius: PeerInfoBalanceView.height / 2, hasShadow: true, hasBorder: true, forceAppearance: .forceLight)
                glass.isEventLess = true
                glassView = glass
                addSubview(glass, positioned: .below, relativeTo: control)
            }
            glass.customTint = backgroundColor
            control.backgroundColor = .clear
            control.stretchTransformView = self
            control.stretchReferenceView = glass
        } else {
            control.stretchReferenceView = nil
            control.stretchTransformView = nil
            glassView?.removeFromSuperview()
            glassView = nil
            control.backgroundColor = backgroundColor
        }

        let titleLayout = TextViewLayout(.initialize(string: strings().peerInfoBalanceViewTitle, color: textColor, font: .normal(.short)), maximumNumberOfLines: 1)
        titleLayout.measure(width: .greatestFiniteMagnitude)
        titleView.update(titleLayout)

        var amountText = formatTonAmountText(balance, maxDecimalPositions: 2)
        if let separator = amountText.range(of: walletDecimalSeparator) {
            amountText += String(repeating: "0", count: max(0, 2 - amountText[separator.upperBound...].count))
        } else {
            amountText += walletDecimalSeparator + "00"
        }
        let amount = NSMutableAttributedString()
        if let separator = amountText.range(of: walletDecimalSeparator) {
            amount.append(string: String(amountText[..<separator.lowerBound]), color: textColor, font: .semibold(.short))
            amount.append(string: String(amountText[separator.lowerBound...]), color: textColor, font: .semibold(9))
        } else {
            amount.append(string: amountText, color: textColor, font: .semibold(.short))
        }
        let amountLayout = TextViewLayout(amount, maximumNumberOfLines: 1)
        amountLayout.measure(width: .greatestFiniteMagnitude)
        amountView.update(amountLayout)

        iconView.image = peerInfoBalanceIcon(iconColor, colorfull: colorfull)
        iconView.setFrameSize(NSMakeSize(14, 14))

        chevron.image = TelegramThemeHooks.shared.image(.iconPeerMusicChevron).precomposed(textColor)
        chevron.sizeToFit()

        control.setAccessibilityLabel(strings().peerInfoBalanceViewAccessibility(amountText))

        needsLayout = true
    }

    public var size: NSSize {
        let width = titleView.frame.width + 2 + iconView.frame.width + 1 + amountView.frame.width + 2 + chevron.frame.width
        return NSMakeSize(width + PeerInfoBalanceView.inset * 2, PeerInfoBalanceView.height)
    }

    public override func layout() {
        super.layout()

        control.frame = bounds
        control.layer?.cornerRadius = bounds.height / 2
        glassView?.frame = bounds
        glassView?.cornerRadius = bounds.height / 2
        glassView?.updateLayout(size: bounds.size, transition: .immediate)

        titleView.centerY(x: PeerInfoBalanceView.inset)
        iconView.centerY(x: titleView.frame.maxX + 2)
        amountView.centerY(x: iconView.frame.maxX + 1)
        chevron.centerY(x: amountView.frame.maxX + 2)
    }
}
