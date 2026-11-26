import Cocoa
import TGUIKit
import TelegramCore
import TelegramTheme
import Localization

public class ContextInlineSetupQuickReplyRowItem: TableRowItem {
    fileprivate let account:Account
    fileprivate let layout:TextViewLayout
    fileprivate let callback:()->Void
    public init(_ initialSize:NSSize, account:Account, callback:@escaping()->Void) {
        self.account = account
        self.callback = callback
        layout = TextViewLayout(.initialize(string: strings().chatInputContextEditQuickReply, color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1, truncationType: .end)
        layout.measure(width: initialSize.width - 40)
        super.init(initialSize)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        layout.measure(width: width - 40)
        return success
    }
    
    public override func viewClass() -> AnyClass {
        return ContextInlineSetupQuickReplyRowView.self
    }

    public override var accessibilityLabel: String? {
        return layout.attributedString.string
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        callback()
        return true
    }
    
    public override var height: CGFloat {
        return 40
    }
    
}

class ContextInlineSetupQuickReplyRowView: TableRowView {
    private let textView:TextView = TextView()
    private let overlay:OverlayControl = OverlayControl()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        addSubview(overlay)
        overlay.addSubview(textView)
        
        overlay.scaleOnClick = true
        
        overlay.set(handler: { [weak self] _ in
            if let item = self?.item as? ContextInlineSetupQuickReplyRowItem {
                item.callback()
            }
        }, for: .Click)
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        needsDisplay = true
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        if let item = item as? ContextInlineSetupQuickReplyRowItem {
            overlay.setFrameSize(frame.size)
            textView.update(item.layout)
            textView.center()
        }
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        
        if let item = item, let table = item.table {
            if item.index != table.count - 1 {
                ctx.setFillColor(theme.colors.border.cgColor)
                ctx.fill(NSMakeRect(0, frame.height - .borderSize, frame.width, .borderSize))
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}



