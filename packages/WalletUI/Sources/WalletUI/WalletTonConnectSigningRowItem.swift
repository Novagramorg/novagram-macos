import Cocoa
import TGUIKit
import TelegramTheme
import GeneralRows
import Localization

@available(macOS 10.15, *)
private func walletTonConnectSigningAttributedText(_ content: WalletTransferPresentation.SigningContent) -> NSAttributedString {
    let text = NSMutableAttributedString()
    switch content {
    case let .text(value):
        text.append(string: value, color: theme.colors.text, font: .code(.text))
    case let .message(groups):
        let font: NSFont = .code(.short)
        for (groupIndex, fields) in groups.enumerated() {
            if groupIndex != 0 {
                text.append(string: "\n\n", color: theme.colors.text, font: font)
            }
            for (fieldIndex, field) in fields.enumerated() {
                if fieldIndex != 0 {
                    text.append(string: "\n", color: theme.colors.text, font: font)
                }
                text.append(string: field.name + ": ", color: theme.colors.grayText, font: font)
                text.append(string: field.value, color: theme.colors.text, font: font)
            }
        }
    case .binary:
        break
    }
    return text
}

@available(macOS 10.15, *)
final class WalletTonConnectSigningRowItem: GeneralRowItem {
    fileprivate let titleLayout: TextViewLayout
    fileprivate let contentLayout: TextViewLayout?
    fileprivate let binaryTitleLayout: TextViewLayout?
    fileprivate let binaryTextLayout: TextViewLayout?

    fileprivate let titleSpacing: CGFloat = 12
    fileprivate let horizontalPadding: CGFloat = 16
    fileprivate let verticalPadding: CGFloat = 14
    fileprivate let iconSize: CGFloat = 16
    fileprivate let iconSpacing: CGFloat = 6
    fileprivate let binaryTextSpacing: CGFloat = 2
    fileprivate let cornerRadius: CGFloat = 20

    private var cardHeight: CGFloat = 0

    init(_ initialSize: NSSize, stableId: AnyHashable, title: String, content: WalletTransferPresentation.SigningContent, viewType: GeneralViewType = .singleItem) {
        self.titleLayout = TextViewLayout(.initialize(string: title, color: theme.colors.grayText, font: .semibold(.title)), maximumNumberOfLines: 1)
        switch content {
        case .binary:
            self.contentLayout = nil
            self.binaryTitleLayout = TextViewLayout(.initialize(string: strings().walletTonConnectSigningRowItemBinaryTitle, color: theme.colors.text, font: .normal(.title)))
            self.binaryTextLayout = TextViewLayout(.initialize(string: strings().walletTonConnectSigningRowItemBinaryWarning, color: theme.colors.text, font: .normal(.title)))
        case .text, .message:
            let layout = TextViewLayout(walletTonConnectSigningAttributedText(content))
            layout.interactions = GeneralRowsHooks.shared.linkExecutor()
            self.contentLayout = layout
            self.binaryTitleLayout = nil
            self.binaryTextLayout = nil
        }
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    fileprivate var innerWidth: CGFloat {
        return max(1, blockWidth - horizontalPadding * 2)
    }

    fileprivate var cardY: CGFloat {
        return titleLayout.layoutSize.height + titleSpacing
    }

    override var height: CGFloat {
        return cardY + cardHeight
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        titleLayout.measure(width: innerWidth)

        if let contentLayout {
            contentLayout.measure(width: innerWidth)
            cardHeight = verticalPadding + contentLayout.layoutSize.height + verticalPadding
        } else if let binaryTitleLayout, let binaryTextLayout {
            binaryTitleLayout.measure(width: max(1, innerWidth - iconSize - iconSpacing))
            binaryTextLayout.measure(width: innerWidth)
            cardHeight = verticalPadding + binaryTitleLayout.layoutSize.height + binaryTextSpacing + binaryTextLayout.layoutSize.height + verticalPadding
        } else {
            cardHeight = verticalPadding * 2
        }
        return true
    }

    override func viewClass() -> AnyClass {
        return WalletTonConnectSigningRowView.self
    }

    override var accessibilityLabel: String? {
        let title = titleLayout.attributedString.string
        return title.isEmpty ? nil : title
    }
}

@available(macOS 10.15, *)
private final class WalletTonConnectSigningRowView: TableRowView {
    private let titleView = TextView()
    private let cardView = View()
    private let contentView = TextView()
    private let iconView = ImageView()
    private let binaryTitleView = TextView()
    private let binaryTextView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        titleView.isAccessibilityDecorative = true

        cardView.layer?.cornerCurve = .continuous
        cardView.layer?.masksToBounds = true

        contentView.userInteractionEnabled = true
        contentView.isSelectable = true

        iconView.contentGravity = .resizeAspect
        iconView.isAccessibilityDecorative = true
        binaryTitleView.userInteractionEnabled = false
        binaryTitleView.isSelectable = false
        binaryTextView.userInteractionEnabled = false
        binaryTextView.isSelectable = false

        cardView.addSubview(contentView)
        cardView.addSubview(iconView)
        cardView.addSubview(binaryTitleView)
        cardView.addSubview(binaryTextView)

        addSubview(titleView)
        addSubview(cardView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func updateColors() {
        super.updateColors()
        cardView.backgroundColor = theme.colors.background
        contentView.backgroundColor = theme.colors.background
        binaryTitleView.backgroundColor = theme.colors.background
        binaryTextView.backgroundColor = theme.colors.background
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? WalletTonConnectSigningRowItem else {
            return
        }

        cardView.layer?.cornerRadius = item.cornerRadius
        titleView.update(item.titleLayout)

        if let contentLayout = item.contentLayout {
            contentView.update(contentLayout)
            contentView.isHidden = false
        } else {
            contentView.isHidden = true
        }

        let isBinary = item.binaryTitleLayout != nil
        iconView.isHidden = !isBinary
        binaryTitleView.isHidden = !isBinary
        binaryTextView.isHidden = !isBinary
        if let binaryTitleLayout = item.binaryTitleLayout, let binaryTextLayout = item.binaryTextLayout {
            iconView.image = theme.icons.errorImage
            iconView.setFrameSize(NSMakeSize(item.iconSize, item.iconSize))
            binaryTitleView.update(binaryTitleLayout)
            binaryTextView.update(binaryTextLayout)
        }

        updateColors()
        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let item = item as? WalletTonConnectSigningRowItem else {
            return
        }

        let cardX = floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2)
        titleView.setFrameOrigin(NSMakePoint(cardX + item.horizontalPadding, 0))
        cardView.frame = NSMakeRect(cardX, item.cardY, item.blockWidth, frame.height - item.cardY)

        if item.contentLayout != nil {
            contentView.setFrameOrigin(NSMakePoint(item.horizontalPadding, item.verticalPadding))
        }

        if item.binaryTitleLayout != nil {
            let titleX = item.horizontalPadding + item.iconSize + item.iconSpacing
            binaryTitleView.setFrameOrigin(NSMakePoint(titleX, item.verticalPadding))
            iconView.setFrameOrigin(NSMakePoint(item.horizontalPadding, item.verticalPadding + floorToScreenPixels(backingScaleFactor, (binaryTitleView.frame.height - item.iconSize) / 2)))
            binaryTextView.setFrameOrigin(NSMakePoint(item.horizontalPadding, binaryTitleView.frame.maxY + item.binaryTextSpacing))
        }
    }
}
