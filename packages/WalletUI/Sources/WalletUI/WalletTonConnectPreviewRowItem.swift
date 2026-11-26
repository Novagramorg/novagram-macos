import Cocoa
import TGUIKit
import TelegramTheme
import GeneralRows
import CurrencyFormat

private let walletTonConnectPreviewAvatarSize: CGFloat = 40
private let walletTonConnectPreviewAvatarSpacing: CGFloat = 12
private let walletTonConnectPreviewVerticalInset: CGFloat = 10
private let walletTonConnectPreviewAmountIconSize: CGFloat = 18
private let walletTonConnectPreviewCommentHorizontalInset: CGFloat = 14
private let walletTonConnectPreviewCommentVerticalInset: CGFloat = 8

final class WalletTonConnectPreviewRowItem: GeneralRowItem {
    fileprivate let avatar: CGImage?
    fileprivate let titleLayout: TextViewLayout
    fileprivate let subtitleLayout: TextViewLayout?
    fileprivate let amountLayout: TextViewLayout?
    fileprivate let amountIcon: CGImage?
    fileprivate let commentLayout: TextViewLayout?

    init(_ initialSize: NSSize, stableId: AnyHashable, avatar: CGImage?, title: String, subtitle: String?, subtitleColor: NSColor = theme.colors.text, amount: String? = nil, amountColor: NSColor = theme.colors.text, comment: String? = nil, viewType: GeneralViewType) {
        self.avatar = avatar
        self.titleLayout = TextViewLayout(.initialize(string: title, color: theme.colors.text, font: .medium(.title)), maximumNumberOfLines: 1)
        self.subtitleLayout = subtitle.map {
            TextViewLayout(.initialize(string: $0, color: subtitleColor, font: .normal(.text)), maximumNumberOfLines: 1)
        }
        self.amountLayout = amount.map {
            TextViewLayout(.initialize(string: $0, color: amountColor, font: .semibold(.text)), maximumNumberOfLines: 1)
        }
        self.amountIcon = amount == nil ? nil : NSImage(named: "Wallet_TransactionGram")?.precomposed()
        self.commentLayout = comment.map {
            TextViewLayout(.initialize(string: $0, color: theme.colors.text, font: .normal(.text)))
        }
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    fileprivate var textHeight: CGFloat {
        var height = titleLayout.layoutSize.height
        if let subtitleLayout {
            height += 2 + subtitleLayout.layoutSize.height
        }
        return height
    }

    fileprivate var headerHeight: CGFloat {
        return max(walletTonConnectPreviewAvatarSize, textHeight)
    }

    fileprivate var commentSize: NSSize {
        guard let commentLayout else {
            return .zero
        }
        return NSMakeSize(commentLayout.layoutSize.width + walletTonConnectPreviewCommentHorizontalInset * 2, commentLayout.layoutSize.height + walletTonConnectPreviewCommentVerticalInset * 2)
    }

    override var height: CGFloat {
        var height = walletTonConnectPreviewVerticalInset + headerHeight + walletTonConnectPreviewVerticalInset
        if commentLayout != nil {
            height += commentSize.height + 8
        }
        return max(60, height)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        let textWidth = blockWidth - viewType.innerInset.left - walletTonConnectPreviewAvatarSize - walletTonConnectPreviewAvatarSpacing - viewType.innerInset.right
        var amountZone: CGFloat = 0
        if let amountLayout {
            amountLayout.measure(width: .greatestFiniteMagnitude)
            amountZone = amountLayout.layoutSize.width + 2 + walletTonConnectPreviewAmountIconSize + 8
        }
        titleLayout.measure(width: max(0, textWidth - amountZone))
        subtitleLayout?.measure(width: max(0, textWidth))
        commentLayout?.measure(width: max(0, textWidth - walletTonConnectPreviewCommentHorizontalInset * 2))
        return true
    }

    override func viewClass() -> AnyClass {
        return WalletTonConnectPreviewRowView.self
    }

    override var accessibilityLabel: String? {
        let title = titleLayout.attributedString.string
        return title.isEmpty ? nil : title
    }

    override var accessibilityValue: String? {
        let amount = amountLayout.map { walletTonAccessibilityText($0.attributedString.string) }
        let parts = [subtitleLayout?.attributedString.string, amount, commentLayout?.attributedString.string].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class WalletTonConnectPreviewRowView: GeneralContainableRowView {
    private let avatarView = ImageView(frame: NSMakeRect(0, 0, walletTonConnectPreviewAvatarSize, walletTonConnectPreviewAvatarSize))
    private let titleView = TextView()
    private let subtitleView = TextView()
    private let amountView = TextView()
    private let amountIconView = ImageView(frame: NSMakeRect(0, 0, walletTonConnectPreviewAmountIconSize, walletTonConnectPreviewAmountIconSize))
    private let commentBackgroundView = View()
    private let commentView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        amountIconView.contentGravity = .resizeAspect
        amountIconView.isAccessibilityDecorative = true
        avatarView.isAccessibilityDecorative = true
        for textView in [titleView, subtitleView, amountView, commentView] {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
        }
        commentBackgroundView.userInteractionEnabled = false

        addSubview(avatarView)
        addSubview(titleView)
        addSubview(subtitleView)
        addSubview(amountView)
        addSubview(amountIconView)
        addSubview(commentBackgroundView)
        addSubview(commentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateColors() {
        super.updateColors()
        commentBackgroundView.backgroundColor = theme.colors.grayBackground
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? WalletTonConnectPreviewRowItem else {
            return
        }

        avatarView.image = item.avatar
        titleView.update(item.titleLayout)
        subtitleView.update(item.subtitleLayout)
        subtitleView.isHidden = item.subtitleLayout == nil
        amountView.update(item.amountLayout)
        amountView.isHidden = item.amountLayout == nil
        amountIconView.image = item.amountIcon
        amountIconView.isHidden = item.amountIcon == nil
        commentView.update(item.commentLayout)
        commentView.isHidden = item.commentLayout == nil
        commentBackgroundView.isHidden = item.commentLayout == nil

        needsLayout = true
    }

    override func layout() {
        super.layout()

        guard let item = item as? WalletTonConnectPreviewRowItem else {
            return
        }

        let leftInset = item.viewType.innerInset.left
        let rightInset = item.viewType.innerInset.right
        let top = walletTonConnectPreviewVerticalInset
        let textX = leftInset + walletTonConnectPreviewAvatarSize + walletTonConnectPreviewAvatarSpacing

        avatarView.setFrameOrigin(NSMakePoint(leftInset, top + floorToScreenPixels(backingScaleFactor, (item.headerHeight - walletTonConnectPreviewAvatarSize) / 2)))

        let textTop = top + floorToScreenPixels(backingScaleFactor, (item.headerHeight - item.textHeight) / 2)
        titleView.setFrameOrigin(NSMakePoint(textX, textTop))
        subtitleView.setFrameOrigin(NSMakePoint(textX, titleView.frame.maxY + 2))

        let amountIconX = containerView.frame.width - rightInset - walletTonConnectPreviewAmountIconSize
        let amountX = amountIconX - 2 - amountView.frame.width
        let amountY = textTop + floorToScreenPixels(backingScaleFactor, (titleView.frame.height - amountView.frame.height) / 2)
        amountView.setFrameOrigin(NSMakePoint(amountX, amountY))
        amountIconView.setFrameOrigin(NSMakePoint(amountIconX, amountY + floorToScreenPixels(backingScaleFactor, (amountView.frame.height - walletTonConnectPreviewAmountIconSize) / 2)))

        if item.commentLayout != nil {
            let commentSize = item.commentSize
            commentBackgroundView.frame = NSMakeRect(textX, top + item.headerHeight + 8, commentSize.width, commentSize.height)
            commentBackgroundView.layer?.cornerRadius = min(16, commentSize.height / 2)
            commentView.setFrameOrigin(NSMakePoint(commentBackgroundView.frame.minX + walletTonConnectPreviewCommentHorizontalInset, commentBackgroundView.frame.minY + walletTonConnectPreviewCommentVerticalInset))
        }
    }

    override var additionBorderInset: CGFloat {
        return walletTonConnectPreviewAvatarSize + walletTonConnectPreviewAvatarSpacing
    }
}
