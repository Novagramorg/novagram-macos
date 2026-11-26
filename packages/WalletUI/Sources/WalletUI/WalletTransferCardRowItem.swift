import Cocoa
import TGUIKit
import TelegramTheme
import GeneralRows
import CurrencyFormat
import Localization

@available(macOS 10.15, *)
final class WalletTransferCardRowItem: GeneralRowItem {
    fileprivate let amount: Int64
    fileprivate let amountText: String?
    fileprivate let fiatText: String?
    fileprivate let recipient: String
    fileprivate let recipientTitle: String?
    fileprivate let infoAction: () -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, amount: Int64, amountText: String?, fiatText: String?, recipient: String, recipientTitle: String?, viewType: GeneralViewType = .singleItem, infoAction: @escaping () -> Void) {
        self.amount = amount
        self.amountText = amountText
        self.fiatText = fiatText
        self.recipient = recipient
        self.recipientTitle = recipientTitle
        self.infoAction = infoAction
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    var cardSize: NSSize {
        let width = min(walletTransferCardReferenceSize.width, blockWidth)
        return NSMakeSize(width, ceil(width * walletTransferCardReferenceSize.height / walletTransferCardReferenceSize.width))
    }

    fileprivate var recipientText: String {
        return recipientTitle ?? walletTransferCardRecipientText(recipient)
    }

    override var height: CGFloat {
        return cardSize.height + inset.top + inset.bottom
    }

    override func viewClass() -> AnyClass {
        return WalletTransferCardRowView.self
    }

    override var accessibilityLabel: String? {
        if let amountText, !amountText.isEmpty {
            return amountText
        }
        return walletTonAccessibilityText(formatTonAmountText(amount, maxDecimalPositions: 9))
    }

    override var accessibilityValue: String? {
        let parts = [fiatText, recipientText].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        let action = infoAction
        return [NSAccessibilityCustomAction(name: strings().voiceOverCommonInfo, handler: {
            action()
            return true
        })]
    }
}

@available(macOS 10.15, *)
private final class WalletTransferCardRowView: TableRowView {
    private let cardView = WalletCardView(frame: NSZeroRect)

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        layer?.zPosition = 10
        addSubview(cardView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        guard let item = item as? GeneralRowItem else {
            return theme.colors.listBackground
        }
        return item.viewType.rowBackground
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletTransferCardRowItem else {
            return
        }
        let size = item.cardSize
        cardView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - size.width) / 2), item.inset.top, size.width, size.height)
        cardView.layoutSubtreeIfNeeded()
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletTransferCardRowItem else {
            return
        }
        cardView.updateTransfer(amount: item.amount, amountText: item.amountText, fiatText: item.fiatText, recipientText: item.recipientText)
        cardView.transferInfoAction = { [weak item] in
            item?.infoAction()
        }
        needsLayout = true
    }
}
