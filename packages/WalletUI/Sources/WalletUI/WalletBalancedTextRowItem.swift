import Cocoa
import TGUIKit
import GeneralRows

func walletMeasureBalanced(_ layout: TextViewLayout, width: CGFloat) {
    layout.measure(width: width)
    let lineCount = layout.lines.count
    guard lineCount > 1 else {
        return
    }
    var low: CGFloat = 1
    var high = width
    while high - low > 1 {
        let middle = floor((low + high) / 2)
        layout.measure(width: middle)
        if layout.lines.count > lineCount {
            low = middle
        } else {
            high = middle
        }
    }
    layout.measure(width: high)
}

final class WalletBalancedTextRowItem: GeneralRowItem {
    fileprivate let textLayout: TextViewLayout
    private let horizontalInset: CGFloat

    init(_ initialSize: NSSize, stableId: AnyHashable, text: NSAttributedString, horizontalInset: CGFloat = 24) {
        self.textLayout = TextViewLayout(text, alignment: .center)
        self.horizontalInset = horizontalInset
        super.init(initialSize, stableId: stableId, viewType: .singleItem)
    }

    override var height: CGFloat {
        return textLayout.layoutSize.height
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        walletMeasureBalanced(textLayout, width: max(1, blockWidth - horizontalInset * 2))
        return true
    }

    override func viewClass() -> AnyClass {
        return WalletBalancedTextRowView.self
    }

    override var accessibilityLabel: String? {
        let text = textLayout.attributedString.string
        return text.isEmpty ? nil : text
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class WalletBalancedTextRowView: TableRowView {
    private let textView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletBalancedTextRowItem else {
            return
        }
        textView.update(item.textLayout)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        textView.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (frame.width - textView.frame.width) / 2), 0))
    }
}
