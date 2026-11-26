import Cocoa
import TGUIKit
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

public final class GeneralActionButtonRowItem : GeneralRowItem {
    fileprivate let text: String
    public init(_ initialSize: NSSize, stableId: AnyHashable, text: String, viewType: GeneralViewType, action: @escaping()->Void, inset: NSEdgeInsets = NSEdgeInsetsMake(0, 20, 0, 20)) {
        self.text = text
        super.init(initialSize, stableId: stableId, viewType: viewType, action: action, inset: inset)
    }
    public override func viewClass() -> AnyClass {
        return GeneralActionButtonView.self
    }
    
    public override var height: CGFloat {
        return 60
    }

    public override var accessibilityLabel: String? {
        return text
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
    
    public override var backdorColor: NSColor {
        switch viewType {
        case .legacy:
            return .clear
        default:
            return super.backdorColor
        }
    }
    
    public override var blockWidth: CGFloat {
        switch viewType {
        case .legacy:
            return width
        default:
            return super.blockWidth
        }
    }
}


private final class GeneralActionButtonView: GeneralContainableRowView {
    private let button = TextButton()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(button)
    }
    
    public override var backdorColor: NSColor {
        guard let item = item as? GeneralRowItem else {
            return .clear
        }
        return item.backdorColor
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? GeneralActionButtonRowItem else {
            return
        }
        
        button.set(font: .medium(.text), for: .Normal)
        button.set(text: item.text, for: .Normal)
        button.set(background: .clear, for: .Normal)
        button.set(color: theme.colors.underSelectedColor, for: .Normal)
        button.setGlassEffect(tintColor: theme.colors.accent)
        button.sizeToFit(NSMakeSize(item.blockWidth - 20, item.height - 20))
        button.layer?.cornerRadius = 20
        button.autohighlight = false
        button.scaleOnClick = true
        button.removeAllHandlers()
        button.set(handler: { [weak item] _ in
            item?.action()
        }, for: .Click)
        
        needsLayout = true
    }
    public override func layout() {
        super.layout()
        button.frame = containerView.focus(NSMakeSize(containerView.frame.width - 20, containerView.frame.height - 20))
    }
}
