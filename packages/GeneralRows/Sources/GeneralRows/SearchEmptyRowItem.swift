import Cocoa
import TGUIKit
import Localization
#if SHARE
import TelegramThemeShare
import ColorPalette
import TelegramIconsTheme
#else
import TelegramTheme
import TelegramIconsTheme
#endif

open class SearchEmptyRowItem: GeneralRowItem {
    
    public let isLoading:Bool
    public let icon:CGImage
    public let text:TextViewLayout?
    public let header: TextViewLayout?
    public struct Action {
        public var click:()->Void
        public var title: String
        public init(click: @escaping ()->Void, title: String) {
            self.click = click
            self.title = title
        }
    }
    
    public let buttonAction: Action?

    
    private let _heightValue: CGFloat?
    public init(_ initialSize: NSSize, stableId:AnyHashable, height: CGFloat? = nil, isLoading:Bool = false, icon:CGImage = theme.icons.emptySearch, header: String? = nil, text:String? = nil, border:BorderType = [], viewType: GeneralViewType = .legacy, customTheme: GeneralRowItem.Theme? = nil, action: Action? = nil) {
        self.isLoading = isLoading
        self.icon = icon
        self.buttonAction = action
        self._heightValue = height
        if let header = header {
            self.header = TextViewLayout(.initialize(string: header, color: customTheme?.textColor ?? theme.colors.text, font: .normal(.header)), alignment: .center)
            self.header?.measure(width: initialSize.width - 60)
        } else {
            self.header = nil
        }
        if let text = text {
            self.text = TextViewLayout(.initialize(string: text, color: customTheme?.grayTextColor ?? theme.colors.grayText, font: .normal(.title)), alignment: .center)
            self.text?.measure(width: initialSize.width - 60)
        } else {
            self.text = nil
        }
        super.init(initialSize, stableId: stableId, viewType: viewType, border: border, customTheme: customTheme)
    }
    
    open override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        text?.measure(width: width - 60)
        header?.measure(width: width - 60)
        return success
    }
    
    open override var height: CGFloat {
        if let height = _heightValue {
            return height
        }
        if let table = table {
            var basic:CGFloat = 0
            table.enumerateItems(with: { [weak self] item in
                if let strongSelf = self {
                    if item.index < strongSelf.index {
                        basic += item.height
                    }
                }
                return true
            })
            return table.frame.height - basic
        } else {
            return initialSize.height
        }
    }
    
    open override func viewClass() -> AnyClass {
        return SearchEmptyRowView.self
    }

    open override var accessibilityLabel: String? {
        if isLoading {
            return strings().voiceOverCommonLoading
        }
        if let header = header?.attributedString.string, !header.isEmpty {
            return header
        }
        if let text = text?.attributedString.string, !text.isEmpty {
            return text
        }
        return strings().requestJoinListSearchEmptyHeader
    }

    open override var accessibilityValue: String? {
        guard !isLoading, header != nil, let text = text?.attributedString.string, !text.isEmpty else {
            return nil
        }
        return text
    }

    open override var accessibilityRole: NSAccessibility.Role? {
        return isLoading ? .busyIndicator : .staticText
    }

    open override var accessibilityIncludesChildren: Bool {
        return !isLoading && buttonAction != nil
    }
}


open class SearchEmptyRowView : TableRowView {
    private let imageView:ImageView = ImageView()
    private let textView:TextView = TextView()
    private var headerView: TextView?
    private let indicator:ProgressIndicator = ProgressIndicator(frame: NSMakeRect(0, 0, 35, 35))
    private var action: TextButton?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(indicator)
        addSubview(imageView)
        addSubview(textView)
        textView.isSelectable = false
        textView.isAccessibilityDecorative = true
        imageView.isAccessibilityDecorative = true
        
    }
    
    open override var isOpaque: Bool {
        return false
    }
    

    open override var backdorColor: NSColor {
        if let item = item as? SearchEmptyRowItem {
            if let customTheme = item.customTheme {
                return customTheme.backgroundColor
            }
            return .clear
        } else {
            return super.backdorColor
        }
    }
    
    open override func layout() {
        super.layout()
        imageView.center()
        indicator.center()
        if let item = item as? SearchEmptyRowItem {
            
            textView.update(item.text)
            textView.center()
            
            if let headerView {
                headerView.centerX(y: textView.frame.minY - headerView.frame.height - 10)
            }
            
            if let action {
                var rect = focus(NSMakeSize(min(260, frame.width - 40), 40))
                rect.origin.y = textView.frame.maxY + 15
                action.frame = rect
            }
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item)
        
        if let item = item as? SearchEmptyRowItem {
            indicator.progressColor = item.customTheme?.textColor ?? theme.colors.text
            super.border = item.border
            imageView.image = item.icon
            imageView.sizeToFit()
            imageView.isHidden = item.isLoading || item.text != nil
            indicator.isHidden = !item.isLoading
            
            if item.isLoading {
                indicator.animates = true
            } else {
                indicator.animates = false
            }
            
            textView.isHidden = item.text == nil || item.isLoading
            textView.backgroundColor = backdorColor
            
            if let action = item.buttonAction {
                let current: TextButton
                if let view = self.action {
                    current = view
                } else {
                    current = TextButton()
                    self.action = current
                    self.addSubview(current)
                }
                current.set(font: .normal(.text), for: .Normal)
                current.set(color: theme.colors.underSelectedColor, for: .Normal)
                current.set(background: theme.colors.accent, for: .Normal)
                current.set(text: action.title, for: .Normal)
                current.sizeToFit(.zero, NSMakeSize(frame.width - 40, 40), thatFit: true)
                current.autoSizeToFit = false
                current.scaleOnClick = true
                current.layer?.cornerRadius = 10
                
                current.removeAllHandlers()
                
                current.set(handler: { _ in
                    action.click()
                }, for: .Click)
            } else if let action = self.action {
                action.removeAllHandlers()
                action.removeFromSuperview()
                self.action = nil
            }
            
            if let header = item.header {
                let current: TextView
                if let view = headerView {
                    current = view
                } else {
                    current = TextView()
                    current.isAccessibilityDecorative = true
                    current.isSelectable = false
                    current.userInteractionEnabled = false
                    addSubview(current)
                    self.headerView = current
                }
                current.update(header)
                
            } else if let headerView {
                performSubviewRemoval(headerView, animated: animated)
                self.headerView = nil
            }
            
            self.needsLayout = true
        }
    }
}
