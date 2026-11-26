import Cocoa
import TGUIKit
import ColorPalette

struct CrashRecoveryContent: Equatable {
    enum Symbol: Equatable {
        case activity
        case download
        case ready
        case upToDate
        case warning
        case appStore
        case website
    }
    var symbol: Symbol
    var title: String
    var detail: String
    var progress: CGFloat?
    var primaryTitle: String
    var primaryEnabled: Bool
    var secondaryEnabled: Bool
    var showsWebsite: Bool
    var showsReset: Bool
}

final class CrashRecoveryView: View {
    static let width: CGFloat = 420

    private static let topInset: CGFloat = 40
    private static let iconSize: CGFloat = 84
    private static let horizontalInset: CGFloat = 24
    private static let cardHeight: CGFloat = 76
    private static let cardTextInset: CGFloat = 56
    private static let buttonHeight: CGFloat = 34
    private static let buttonSpacing: CGFloat = 12
    private static let footerSpacing: CGFloat = 18
    private static let bottomInset: CGFloat = 20

    var primary: (() -> Void)?
    var secondary: (() -> Void)?
    var website: (() -> Void)?
    var reset: (() -> Void)?

    private let palette: ColorPalette
    private let glow = CAGradientLayer()
    private let iconView = NSImageView()
    private let titleView = TextView(frame: .zero)
    private let messageView = TextView(frame: .zero)
    private let card: LiquidGlassView
    private let statusView = View()
    private let spinner = ProgressIndicator(frame: NSMakeRect(0, 0, 22, 22))
    private let symbolView = NSImageView()
    private let statusTitleView = TextView(frame: .zero)
    private let statusDetailView = TextView(frame: .zero)
    private let progressView = LinearProgressControl(progressHeight: 4)
    private let primaryButton = TextButton()
    private let secondaryButton = TextButton()
    private let websiteButton = TextButton()
    private let resetButton = TextButton()

    private let titleLayout: TextViewLayout
    private let messageLayout: TextViewLayout
    private var statusTitleLayout: TextViewLayout?
    private var statusDetailLayout: TextViewLayout?
    private var content: CrashRecoveryContent?

    init(frame: NSRect, palette: ColorPalette, title: String, message: String, continueTitle: String, websiteTitle: String, resetTitle: String) {
        self.palette = palette
        let glassAppearance: LiquidGlassAppearance = palette.isDark ? .forceDark : .forceLight
        self.card = LiquidGlassView(frame: .zero, cornerRadius: 18, hasShadow: false, hasBorder: true, tintAlpha: 0.12, forceAppearance: glassAppearance)

        let textWidth = CrashRecoveryView.width - CrashRecoveryView.horizontalInset * 2 - 24
        self.titleLayout = TextViewLayout(.initialize(string: title, color: palette.text, font: .bold(20)), alignment: .center)
        self.titleLayout.measure(width: textWidth)
        self.messageLayout = TextViewLayout(.initialize(string: message, color: palette.grayText, font: .normal(13)), alignment: .center)
        self.messageLayout.measure(width: textWidth)

        super.init(frame: frame)

        if #available(macOS 10.14, *) {
            glow.type = .radial
            glow.colors = [palette.accent.withAlphaComponent(palette.isDark ? 0.32 : 0.2).cgColor, palette.accent.withAlphaComponent(0).cgColor]
            glow.startPoint = NSMakePoint(0.5, 0.5)
            glow.endPoint = NSMakePoint(1, 1)
            layer?.addSublayer(glow)
        }

        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        for textView in [titleView, messageView, statusTitleView, statusDetailView] {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
        }
        titleView.update(titleLayout)
        messageView.update(messageLayout)
        addSubview(titleView)
        addSubview(messageView)

        addSubview(card)
        card.addSubview(statusView)
        spinner.progressColor = palette.grayText
        statusView.addSubview(spinner)
        statusView.addSubview(symbolView)
        statusView.addSubview(statusTitleView)
        statusView.addSubview(statusDetailView)
        progressView.style = ControlStyle(foregroundColor: palette.accent, backgroundColor: .clear, highlightColor: .clear)
        progressView.containerBackground = palette.grayText.withAlphaComponent(0.2)
        progressView.roundCorners = true
        progressView.userInteractionEnabled = false
        statusView.addSubview(progressView)

        configure(secondaryButton, title: continueTitle, font: .medium(13), color: palette.text)
        secondaryButton.setGlassEffect(forceAppearance: glassAppearance)
        secondaryButton.setAccessibilityLabel(continueTitle)
        secondaryButton.set(handler: { [weak self] _ in
            self?.secondary?()
        }, for: .Click)
        addSubview(secondaryButton)

        configure(primaryButton, title: " ", font: .medium(13), color: palette.text)
        primaryButton.setGlassEffect(tintColor: palette.accent, forceAppearance: glassAppearance)
        primaryButton.set(handler: { [weak self] _ in
            self?.primary?()
        }, for: .Click)
        addSubview(primaryButton)

        configure(websiteButton, title: websiteTitle, font: .normal(12), color: palette.accent)
        websiteButton.autoSizeToFit = true
        websiteButton.set(text: websiteTitle, for: .Normal)
        websiteButton.set(handler: { [weak self] _ in
            self?.website?()
        }, for: .Click)
        addSubview(websiteButton)

        configure(resetButton, title: resetTitle, font: .normal(12), color: palette.redUI)
        resetButton.autoSizeToFit = true
        resetButton.set(text: resetTitle, for: .Normal)
        resetButton.set(handler: { [weak self] _ in
            self?.reset?()
        }, for: .Click)
        addSubview(resetButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    private func configure(_ button: TextButton, title: String, font: NSFont, color: NSColor) {
        button.autoSizeToFit = false
        button.scaleOnClick = true
        button.set(font: font, for: .Normal)
        button.set(color: color, for: .Normal)
        button.set(background: .clear, for: .Normal)
        button.set(text: title, for: .Normal)
    }

    var requiredHeight: CGFloat {
        var height = CrashRecoveryView.topInset + CrashRecoveryView.iconSize + 16
        height += titleLayout.layoutSize.height + 6
        height += messageLayout.layoutSize.height + 20
        height += CrashRecoveryView.cardHeight + 20
        height += CrashRecoveryView.buttonHeight + 14
        height += max(websiteButton.frame.height, resetButton.frame.height)
        height += CrashRecoveryView.bottomInset
        return height
    }

    func update(content: CrashRecoveryContent, animated: Bool) {
        let previous = self.content
        self.content = content

        let textWidth = CrashRecoveryView.width - CrashRecoveryView.horizontalInset * 2 - CrashRecoveryView.cardTextInset - 16
        let statusTitleLayout = TextViewLayout(.initialize(string: content.title, color: palette.text, font: .medium(13)), maximumNumberOfLines: 1)
        statusTitleLayout.measure(width: textWidth)
        let statusDetailLayout = TextViewLayout(.initialize(string: content.detail, color: palette.grayText, font: .normal(12)), maximumNumberOfLines: 2)
        statusDetailLayout.measure(width: textWidth)
        self.statusTitleLayout = statusTitleLayout
        self.statusDetailLayout = statusDetailLayout
        statusTitleView.update(statusTitleLayout)
        statusDetailView.update(statusDetailLayout)

        spinner.isHidden = content.symbol != .activity
        applySymbol(content.symbol)

        if let progress = content.progress {
            progressView.isHidden = false
            progressView.set(progress: progress, animated: animated && previous?.progress != nil)
        } else {
            progressView.isHidden = true
        }

        primaryButton.set(text: content.primaryTitle, for: .Normal)
        primaryButton.isEnabled = content.primaryEnabled
        primaryButton.glassTintColor = content.primaryEnabled ? palette.accent : nil
        secondaryButton.isEnabled = content.secondaryEnabled
        websiteButton.isHidden = !content.showsWebsite
        resetButton.isHidden = !content.showsReset

        if animated, previous?.symbol != content.symbol || previous?.title != content.title {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.2
            statusView.layer?.add(transition, forKey: "content")
        }
        needsLayout = true
    }

    private func applySymbol(_ symbol: CrashRecoveryContent.Symbol) {
        guard #available(macOS 11.0, *), symbol != .activity else {
            symbolView.isHidden = true
            return
        }
        let names: [String]
        let color: NSColor
        switch symbol {
        case .activity:
            return
        case .download:
            names = ["arrow.down.circle.fill"]
            color = palette.accent
        case .ready:
            names = ["checkmark.seal.fill"]
            color = palette.accent
        case .upToDate:
            names = ["checkmark.circle.fill"]
            color = palette.greenUI
        case .warning:
            names = ["exclamationmark.triangle.fill"]
            color = NSColor.systemOrange
        case .appStore:
            names = ["arrow.down.app.fill", "arrow.down.circle.fill"]
            color = palette.accent
        case .website:
            names = ["safari.fill"]
            color = palette.accent
        }
        symbolView.image = names.lazy.compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }.first
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        symbolView.contentTintColor = color
        symbolView.isHidden = symbolView.image == nil
    }

    override func layout() {
        super.layout()
        let width = frame.width
        var y = CrashRecoveryView.topInset

        let iconFrame = NSMakeRect(floor((width - CrashRecoveryView.iconSize) / 2), y, CrashRecoveryView.iconSize, CrashRecoveryView.iconSize)
        iconView.frame = iconFrame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = NSMakeRect(iconFrame.midX - 170, iconFrame.midY - 170, 340, 340)
        CATransaction.commit()
        y += CrashRecoveryView.iconSize + 16

        titleView.frame = NSMakeRect(floor((width - titleLayout.layoutSize.width) / 2), y, titleLayout.layoutSize.width, titleLayout.layoutSize.height)
        y += titleLayout.layoutSize.height + 6
        messageView.frame = NSMakeRect(floor((width - messageLayout.layoutSize.width) / 2), y, messageLayout.layoutSize.width, messageLayout.layoutSize.height)
        y += messageLayout.layoutSize.height + 20

        card.frame = NSMakeRect(CrashRecoveryView.horizontalInset, y, width - CrashRecoveryView.horizontalInset * 2, CrashRecoveryView.cardHeight)
        statusView.frame = card.bounds
        layoutStatus(size: card.frame.size)
        y += CrashRecoveryView.cardHeight + 20

        let buttonWidth = floor((width - CrashRecoveryView.horizontalInset * 2 - CrashRecoveryView.buttonSpacing) / 2)
        secondaryButton.frame = NSMakeRect(CrashRecoveryView.horizontalInset, y, buttonWidth, CrashRecoveryView.buttonHeight)
        primaryButton.frame = NSMakeRect(width - CrashRecoveryView.horizontalInset - buttonWidth, y, buttonWidth, CrashRecoveryView.buttonHeight)
        y += CrashRecoveryView.buttonHeight + 14

        let footer = [websiteButton, resetButton].filter { !$0.isHidden }
        let footerWidth = footer.reduce(0, { $0 + $1.frame.width }) + CGFloat(max(0, footer.count - 1)) * CrashRecoveryView.footerSpacing
        var x = floor((width - footerWidth) / 2)
        for button in footer {
            button.setFrameOrigin(NSMakePoint(x, y))
            x += button.frame.width + CrashRecoveryView.footerSpacing
        }
    }

    private func layoutStatus(size: NSSize) {
        let slot = NSMakeRect(16, floor((size.height - 28) / 2), 28, 28)
        spinner.frame = slot.insetBy(dx: 3, dy: 3)
        symbolView.frame = slot

        let titleSize = statusTitleLayout?.layoutSize ?? .zero
        let detailSize = statusDetailLayout?.layoutSize ?? .zero
        let progressHeight: CGFloat = progressView.isHidden ? 0 : 14
        var y = floor((size.height - (titleSize.height + 3 + detailSize.height + progressHeight)) / 2)
        statusTitleView.frame = NSMakeRect(CrashRecoveryView.cardTextInset, y, titleSize.width, titleSize.height)
        y += titleSize.height + 3
        statusDetailView.frame = NSMakeRect(CrashRecoveryView.cardTextInset, y, detailSize.width, detailSize.height)
        y += detailSize.height + 10
        progressView.frame = NSMakeRect(CrashRecoveryView.cardTextInset, y, size.width - CrashRecoveryView.cardTextInset - 16, 4)
    }
}
