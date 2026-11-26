import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme
import CurrencyFormat

final class WalletBalanceBannerRowItem: GeneralRowItem {
    fileprivate let prefixLayout: TextViewLayout
    fileprivate let amountLayout: TextViewLayout?
    fileprivate let suffixLayout: TextViewLayout
    fileprivate let icon: CGImage?

    init(_ initialSize: NSSize, stableId: AnyHashable, prefix: String, amount: String?, suffix: String, viewType: GeneralViewType, action: @escaping () -> Void) {
        let font: NSFont = .medium(.title)
        self.prefixLayout = TextViewLayout(.initialize(string: prefix, color: theme.colors.text, font: font), maximumNumberOfLines: 1)
        self.amountLayout = amount.map { TextViewLayout(.initialize(string: $0, color: walletClassicAccent, font: font), maximumNumberOfLines: 1) }
        self.suffixLayout = TextViewLayout(.initialize(string: suffix, color: theme.colors.text, font: font), maximumNumberOfLines: 1)
        self.icon = amount == nil ? nil : NSImage(named: "Wallet_TransactionGram")?.precomposed()
        super.init(initialSize, height: 46, stableId: stableId, viewType: viewType, action: action)
        self.prefixLayout.measure(width: .greatestFiniteMagnitude)
        self.amountLayout?.measure(width: .greatestFiniteMagnitude)
        self.suffixLayout.measure(width: .greatestFiniteMagnitude)
    }

    override func viewClass() -> AnyClass {
        return WalletBalanceBannerRowView.self
    }

    override var accessibilityLabel: String? {
        let amount = amountLayout.map { walletTonAccessibilityText($0.attributedString.string) } ?? ""
        let text = (prefixLayout.attributedString.string + amount + suffixLayout.attributedString.string).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}

private final class WalletBalanceBannerRowView: GeneralContainableRowView {
    private let prefixView = TextView()
    private let amountView = TextView()
    private let suffixView = TextView()
    private let iconView = ImageView()
    private let nextView = ImageView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [prefixView, amountView, suffixView] {
            view.userInteractionEnabled = false
            view.isSelectable = false
            view.isEventLess = true
            addSubview(view)
        }
        iconView.isEventLess = true
        nextView.isEventLess = true
        iconView.isAccessibilityDecorative = true
        nextView.isAccessibilityDecorative = true
        addSubview(iconView)
        addSubview(nextView)
        containerView.set(handler: { [weak self] _ in
            (self?.item as? WalletBalanceBannerRowItem)?.action()
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletBalanceBannerRowItem else {
            return
        }
        prefixView.update(item.prefixLayout)
        suffixView.update(item.suffixLayout)
        if let amountLayout = item.amountLayout {
            amountView.isHidden = false
            amountView.update(amountLayout)
        } else {
            amountView.isHidden = true
        }
        iconView.isHidden = item.icon == nil
        iconView.image = item.icon
        iconView.sizeToFit()
        nextView.image = theme.icons.generalNext
        nextView.sizeToFit()
        borderView.isHidden = !item.hasBorder
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletBalanceBannerRowItem else {
            return
        }
        let leftInset = item.viewType.innerInset.left
        let rightInset = item.viewType.innerInset.right
        nextView.centerY(x: containerView.frame.width - rightInset - nextView.frame.width)
        prefixView.centerY(x: leftInset)
        var x = prefixView.frame.maxX
        if item.icon != nil {
            iconView.centerY(x: x)
            x = iconView.frame.maxX + 3
        }
        if !amountView.isHidden {
            amountView.centerY(x: x)
            x = amountView.frame.maxX
        }
        suffixView.centerY(x: x)
    }
}
