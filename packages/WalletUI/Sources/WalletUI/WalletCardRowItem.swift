import Cocoa
import TGUIKit
import TelegramTheme
import TelegramContext
import GeneralRows
import CurrencyFormat

@available(macOS 10.15, *)
public final class WalletCardRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let balance: Int64
    fileprivate let fiatText: String?
    fileprivate let name: String
    fileprivate let address: String
    fileprivate let cardDidLayout: ((WalletCardView) -> Void)?
    fileprivate let receiveAction: ((() -> NSView?)?) -> Void

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, balance: Int64, fiatText: String?, name: String, address: String, viewType: GeneralViewType = .singleItem, cardDidLayout: ((WalletCardView) -> Void)? = nil, receiveAction: @escaping ((() -> NSView?)?) -> Void) {
        self.cardDidLayout = cardDidLayout
        self.context = context
        self.balance = balance
        self.fiatText = fiatText
        self.name = name
        self.address = address
        self.receiveAction = receiveAction
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    public var cardSize: NSSize {
        let width = blockWidth
        return NSMakeSize(width, ceil(width * walletCardReferenceSize.height / walletCardReferenceSize.width))
    }

    public override var height: CGFloat {
        return cardSize.height + inset.top + inset.bottom
    }

    public override func viewClass() -> AnyClass {
        return WalletCardRowView.self
    }

    public override var accessibilityLabel: String? {
        return walletTonAccessibilityText(formatTonAmountText(balance, maxDecimalPositions: 9))
    }

    public override var accessibilityValue: String? {
        let parts = [fiatText, name].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    public override var accessibilityHelp: String? {
        return address.isEmpty ? nil : address
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        receiveAction(nil)
        return true
    }
}

@available(macOS 10.15, *)
private final class WalletCardRowView: TableRowView {
    private let cardView = WalletCardView(frame: NSZeroRect)

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        layer?.zPosition = 10
        addSubview(cardView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        guard let item = item as? GeneralRowItem else {
            return theme.colors.listBackground
        }
        return item.viewType.rowBackground
    }

    public override func layout() {
        super.layout()
        guard let item = item as? WalletCardRowItem else {
            return
        }
        let size = item.cardSize
        cardView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - size.width) / 2), item.inset.top, size.width, size.height)
        cardView.layoutSubtreeIfNeeded()
        item.cardDidLayout?(cardView)
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletCardRowItem else {
            return
        }
        cardView.update(balance: item.balance, fiatText: item.fiatText, name: item.name, address: item.address, animated: animated)
        cardView.receiveAction = { [weak item, weak self] in
            item?.receiveAction({ [weak self] in self?.cardView })
        }
        needsLayout = true
    }
}
