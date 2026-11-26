import Cocoa
import TGUIKit
import TelegramCore
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import AlertsUI
import InAppSettings
import ColorPalette
import FoundationUtils
import LocalAnimations
import Translate
import SwiftSignalKit
import Postbox

public class LanguageRowItem: GeneralRowItem {
    fileprivate let selected:Bool
    fileprivate let locale:TextViewLayout
    fileprivate let title:TextViewLayout
    fileprivate let deleteAction: ()->Void
    fileprivate let deletable: Bool

    fileprivate let _stableId:AnyHashable
    public override var stableId: AnyHashable {
        return _stableId
    }
    
    public init(initialSize: NSSize, stableId: AnyHashable, selected: Bool, deletable: Bool, value:LocalizationInfo, viewType: GeneralViewType = .legacy, action:@escaping()->Void, deleteAction: @escaping()->Void = {}, reversed: Bool = false) {
        self._stableId = stableId
        self.selected = selected
        self.title = TextViewLayout(.initialize(string: reversed ? value.localizedTitle : value.title, color: theme.colors.text, font: .normal(.title)), maximumNumberOfLines: 1)
        self.locale = TextViewLayout(.initialize(string: reversed ? value.title : value.localizedTitle, color: reversed ? theme.colors.grayText : theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
        self.deletable = deletable
        self.deleteAction = deleteAction
        super.init(initialSize, viewType: viewType, action: action)
        
        _ = makeSize(initialSize.width, oldWidth: initialSize.width)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        locale.measure(width: width - 100)
        title.measure(width: width - 100)
        return true
    }
    
    public override var height: CGFloat {
        return 48
    }
    
    public override func viewClass() -> AnyClass {
        return LanguageRowView.self
    }
    
    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }
    
    public override var accessibilityValue: String? {
        let value = locale.attributedString.string
        return value.isEmpty ? nil : value
    }
    
    public override var accessibilityRole: NSAccessibility.Role? {
        return .radioButton
    }
    
    public override var accessibilityToggleState: Bool? {
        return selected
    }
    
    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        guard deletable, !selected else {
            return nil
        }
        let deleteAction = self.deleteAction
        return [NSAccessibilityCustomAction(name: strings().voiceOverCommonDelete, handler: {
            deleteAction()
            return true
        })]
    }
    
    public override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}


public class LanguageRowView : TableRowView {
    private let localeTextView:TextView = TextView()
    private let titleTextView:TextView = TextView()
    private let selectedImage:ImageView = ImageView()
    private let overalay:OverlayControl = OverlayControl()
    private let deleteButton = ImageButton()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleTextView)
        addSubview(localeTextView)
        addSubview(selectedImage)
       
        selectedImage.isAccessibilityDecorative = true
        deleteButton.setAccessibilityLabel(strings().voiceOverCommonDelete)
        selectedImage.sizeToFit()
        localeTextView.isSelectable = false
        titleTextView.isSelectable = false
        addSubview(overalay)
        overalay.set(background: .grayTransparent, for: .Highlight)
        addSubview(deleteButton)
        overalay.set(handler: { [weak self] _ in
            if let item = self?.item as? LanguageRowItem {
                item.action()
            }
        }, for: .Click)
        
        deleteButton.set(handler: { [weak self] _ in
            if let item = self?.item as? LanguageRowItem {
                item.deleteAction()
            }
        }, for: .Click)
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.background
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        overalay.setFrameSize(newSize)
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        if let item = item as? LanguageRowItem {
            titleTextView.update(item.title)
            localeTextView.update(item.locale)
            
            deleteButton.set(image: theme.icons.customLocalizationDelete, for: .Normal)
            _ = deleteButton.sizeToFit()
            
            selectedImage.image = theme.icons.generalSelect
            selectedImage.sizeToFit()
            titleTextView.backgroundColor = theme.colors.background
            localeTextView.backgroundColor = theme.colors.background
            selectedImage.isHidden = !item.selected
            
            deleteButton.isHidden = !item.deletable || item.selected
            
            needsLayout = true
        }
    }

    
    public override func layout() {
        super.layout()
        selectedImage.centerY(x: frame.width - 25 - selectedImage.frame.width)
        deleteButton.centerY(x: frame.width - 18 - deleteButton.frame.width)
        if let item = item as? LanguageRowItem {
            titleTextView.update(item.title, origin: NSMakePoint(25, 5))
            localeTextView.update(item.locale, origin: NSMakePoint(25, frame.height - titleTextView.frame.height - 5))
        }
    }
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        
        ctx.setFillColor(theme.colors.border.cgColor)
        ctx.fill(NSMakeRect(25, frame.height - .borderSize, frame.width - 50, .borderSize))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
