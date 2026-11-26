import Cocoa
import TGUIKit
import ChatHistoryModel
import GeneralRows
import Localization
import TelegramTheme

public class RepliesHeaderRowItem: GeneralRowItem {
    fileprivate var textLayout: TextViewLayout
    public init(_ initialSize: NSSize, entry: ChatHistoryEntry) {
        self.textLayout = TextViewLayout(.initialize(string: strings().chatRepliesDesc, color: theme.colors.text, font: .normal(.text)), alignment: .center)
        super.init(initialSize, stableId: entry.stableId, viewType: .singleItem, inset: NSEdgeInsetsMake(20, 30, 10, 30))
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.textLayout.measure(width: blockWidth - viewType.innerInset.left - viewType.innerInset.right)
        return true
    }
    
    public override var height: CGFloat {
        return self.textLayout.layoutSize.height + viewType.innerInset.top + viewType.innerInset.bottom + inset.top + inset.bottom
    }
    
    public override func viewClass() -> AnyClass {
        return RepliesHeaderRowView.self
    }

    public override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}


private final class RepliesHeaderRowView : GeneralContainableRowView {
    private let textView: TextView = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        
        textView.isSelectable = false
        textView.userInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        textView.center()
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? RepliesHeaderRowItem else {
            return
        }
        
        self.textView.update(item.textLayout)
    }
}
