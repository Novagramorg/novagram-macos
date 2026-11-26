import Cocoa
import TGUIKit
import TelegramContext
import TelegramTheme
import ColorPalette
import Localization
import SwiftSignalKit

public enum SeparatorBlockState : Equatable {
    
    
    public struct DropdownAction : Equatable {
        public static func == (lhs: DropdownAction, rhs: DropdownAction) -> Bool {
            return lhs.title == rhs.title
        }
        public var title: String
        public var selected: Bool
        public var action:()->Void
        public init(title: String, selected: Bool, action: @escaping ()->Void) {
            self.title = title
            self.selected = selected
            self.action = action
        }
    }
    
    
    public enum Action : Equatable {
      
        case showAsMessages(onlyMy: Bool)
        case showPublicPosts(CachedSearchMessages)
    }
    case short
    case all
    case none
    case clear
    case custom(String, Action)
    case dropdown(String, [DropdownAction])
}



public class SeparatorRowItem: GeneralRowItem {
    public var text:NSAttributedString;
    
    public let rightText:NSAttributedString?
    public let state:SeparatorBlockState
    
    public let leftInset: CGFloat?
    public let itemAction: (()->Void)?
    public let _menuItems: ()->[ContextMenuItem]
    public init(_ initialSize:NSSize, _ stableId:AnyHashable, string:String, right:String? = nil, state: SeparatorBlockState = .none, height:CGFloat = 20.0, action: (()->Void)? = nil, leftInset: CGFloat? = nil, border:BorderType = [], customTheme: GeneralRowItem.Theme = GeneralRowItem.Theme(), menuItems: @escaping()->[ContextMenuItem] = { return [] }) {
        self.leftInset = leftInset
        self.state = state
        self.itemAction = action
        self._menuItems = menuItems
        text = .initialize(string: string, color: customTheme.grayTextColor, font:.normal(.short))
        if let right = right {
            self.rightText = .initialize(string: right, color: customTheme.grayTextColor, font:.normal(.short))
        } else {
            rightText = nil
        }
        
        
        super.init(initialSize, height: height, stableId: stableId, type: .none, viewType: .legacy, border: border, error: nil, customTheme: customTheme)
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        return .single(_menuItems())
    }
    
    public override var instantlyResize: Bool {
        return true
    }
    
    
    public override func viewClass() -> AnyClass {
        return SeparatorRowView.self
    }

    public override var accessibilityIsSpacer: Bool {
        return text.string.isEmpty && (rightText?.string.isEmpty ?? true)
    }

    public override var accessibilityLabel: String? {
        let string = text.string.isEmpty ? (rightText?.string ?? "") : text.string
        return string.isEmpty ? nil : string
    }

    public override var accessibilityValue: String? {
        guard !text.string.isEmpty, let right = rightText?.string, !right.isEmpty else {
            return nil
        }
        return right
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        guard let right = rightText?.string, !right.isEmpty, let itemAction = itemAction else {
            return nil
        }
        return [NSAccessibilityCustomAction(name: right, handler: {
            itemAction()
            return true
        })]
    }
}


public class SeparatorRowView: TableRowView {
    
    private var text:TextNode = TextNode()
    private var stateText:TextNode = TextNode()
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
    
    public override var backdorColor: NSColor {
        if let item = item as? GeneralRowItem, let customTheme = item.customTheme {
            return customTheme.grayBackground
        }
        if let backgroundColor = (item as? SeparatorRowItem)?.backgroundColor {
            return backgroundColor
        }
        return theme.colors.grayBackground
    }
    
    public override var isOpaque: Bool {
        return false
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func mouseDown(with event: NSEvent) {
        guard let item = item as? SeparatorRowItem else {return}
        let point = convert(event.locationInWindow, from: nil)
        
        if let text = item.rightText {
            let (layout, _) = TextNode.layoutText(maybeNode: stateText, text, nil, 1, .end, NSMakeSize(frame.width, frame.height), nil, false, .left)

            let rect = NSMakeRect(frame.width - 10 - layout.size.width, round((frame.height - layout.size.height)/2.0), layout.size.width, frame.height)
            if NSPointInRect(point, rect) {
                if let itemAction = item.itemAction {
                    itemAction()
                } else {
                    super.mouseDown(with: event)
                    showContextMenu(event)
                }
            } else {
                showContextMenu(event)
            }
        } else {
            super.mouseDown(with: event)
        }
    }
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        
        
        if let item = self.item as? SeparatorRowItem {
            let (layout, apply) = TextNode.layoutText(maybeNode: text, item.text, nil, 1, .end, NSMakeSize(frame.width, frame.height), nil,false, .left)
            let textPoint:NSPoint
            if let text = item.rightText {
                
                var inset: CGFloat = 0
                switch item.state {
                case .dropdown:
                    let image = TelegramThemeHooks.shared.image(.iconSearchMessagesChevron).precomposed(theme.colors.grayText, flipVertical: true)
                    ctx.draw(image, in: NSMakeRect(frame.width - 10 - image.backingSize.width, round((frame.height - image.backingSize.height)/2.0), image.backingSize.width, image.backingSize.height))
                    inset += image.backingSize.width + 2
                default:
                    break
                }
                
                textPoint = NSMakePoint(item.leftInset ?? 10, round((frame.height - layout.size.height)/2.0) - 1)
                let (layout, apply) = TextNode.layoutText(maybeNode: stateText, text, nil, 1, .end, NSMakeSize(frame.width, frame.height), nil, false, .left)
                apply.draw(NSMakeRect(frame.width - 10 - layout.size.width - inset, round((frame.height - layout.size.height)/2.0) - 1, layout.size.width, layout.size.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
                
            } else {
                textPoint = NSMakePoint(item.leftInset ?? 10, round((frame.height - layout.size.height)/2.0) - 1)
                
            }
            apply.draw(NSMakeRect(textPoint.x, textPoint.y, layout.size.width, layout.size.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
        }
    }
    
    public override func set(item:TableRowItem, animated:Bool = false) {
        super.set(item: item, animated: animated)
        if let item = item as? SeparatorRowItem {
            self.border = item.border
        }
        needsDisplay = true
    }
}

