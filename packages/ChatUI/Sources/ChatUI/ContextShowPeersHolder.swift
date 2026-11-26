import Cocoa
import TGUIKit
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif
import GeneralRows


open class ContextShowPeersHolderItem: GeneralRowItem {
    fileprivate let textLayout: TextViewLayout
    public init(_ initialSize: NSSize, stableId: AnyHashable, action: @escaping()->Void) {
        textLayout = TextViewLayout.init(.initialize(string: "Show All Users", color: theme.colors.accent, font: .normal(.text)), maximumNumberOfLines: 1)
        super.init(initialSize, height: 40, stableId: stableId, action: action)
    }
    
    open override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.textLayout.measure(width: width - 60)
        return true
    }
    
    open override func viewClass() -> AnyClass {
        return ContextShowPeersHolderView.self
    }

    open override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }

    open override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    open override var accessibilityIncludesChildren: Bool {
        return false
    }
}


private final class ContextShowPeersHolderView : TableRowView {
    private let textView: TextView = TextView()
    private let borderView = View()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        addSubview(borderView)
        textView.isSelectable = false
        textView.userInteractionEnabled = false
    }
    
    public override func updateColors() {
        super.updateColors()
        self.textView.backgroundColor = theme.colors.background
        borderView.backgroundColor = theme.colors.border
    }
    
    public override func layout() {
        super.layout()
        self.textView.center()
        self.borderView.frame = NSMakeRect(0, frame.height - .borderSize, frame.width, .borderSize)
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? ContextShowPeersHolderItem else {
            return
        }
        self.textView.update(item.textLayout)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
