import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme

func walletPreviousWalletAddressText(_ address: String) -> String {
    let groups = walletAddressGroups(address)
    guard groups.count > 6 else {
        return groups.joined(separator: " ")
    }
    var lines: [String] = []
    for lineStart in stride(from: 0, to: groups.count, by: 6) {
        let lineEnd = min(lineStart + 6, groups.count)
        lines.append(groups[lineStart ..< lineEnd].joined(separator: " "))
    }
    return lines.joined(separator: "\n")
}

final class WalletPreviousWalletRowItem: GeneralRowItem {
    fileprivate let addressLayout: TextViewLayout
    fileprivate let subtitleLayout: TextViewLayout

    init(_ initialSize: NSSize, stableId: AnyHashable, address: String, subtitle: String, viewType: GeneralViewType, action: @escaping () -> Void) {
        self.addressLayout = TextViewLayout(.initialize(string: walletPreviousWalletAddressText(address), color: theme.colors.text, font: .code(.text)), alwaysStaticItems: true)
        self.subtitleLayout = TextViewLayout(.initialize(string: subtitle, color: theme.colors.grayText, font: .normal(.short)), maximumNumberOfLines: 1)
        super.init(initialSize, stableId: stableId, viewType: viewType, action: action)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        let textWidth = self.blockWidth - self.viewType.innerInset.left - self.viewType.innerInset.right - 24
        self.addressLayout.measure(width: textWidth)
        self.subtitleLayout.measure(width: textWidth)
        return result
    }

    override var height: CGFloat {
        return self.viewType.innerInset.top + self.addressLayout.layoutSize.height + 4 + self.subtitleLayout.layoutSize.height + self.viewType.innerInset.bottom
    }

    override func viewClass() -> AnyClass {
        return WalletPreviousWalletRowView.self
    }

    override var accessibilityLabel: String? {
        return addressLayout.attributedString.string.replacingOccurrences(of: "\n", with: " ")
    }

    override var accessibilityValue: String? {
        let subtitle = subtitleLayout.attributedString.string
        return subtitle.isEmpty ? nil : subtitle
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

private final class WalletPreviousWalletRowView: GeneralContainableRowView {
    private let addressView = TextView()
    private let subtitleView = TextView()
    private let nextView = ImageView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addressView.userInteractionEnabled = false
        addressView.isSelectable = false
        addressView.isEventLess = true
        subtitleView.userInteractionEnabled = false
        subtitleView.isSelectable = false
        subtitleView.isEventLess = true
        nextView.isEventLess = true
        nextView.isAccessibilityDecorative = true
        addSubview(addressView)
        addSubview(subtitleView)
        addSubview(nextView)
        containerView.set(handler: { [weak self] _ in
            guard let item = self?.item as? WalletPreviousWalletRowItem else {
                return
            }
            item.action()
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletPreviousWalletRowItem else {
            return
        }
        addressView.update(item.addressLayout)
        subtitleView.update(item.subtitleLayout)
        nextView.image = theme.icons.generalNext
        nextView.sizeToFit()
        borderView.isHidden = !item.hasBorder
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletPreviousWalletRowItem else {
            return
        }
        let leftInset = item.viewType.innerInset.left
        let rightInset = item.viewType.innerInset.right
        addressView.setFrameOrigin(NSMakePoint(leftInset, item.viewType.innerInset.top))
        subtitleView.setFrameOrigin(NSMakePoint(leftInset, addressView.frame.maxY + 4))
        nextView.centerY(x: containerView.frame.width - rightInset - nextView.frame.width)
    }
}
