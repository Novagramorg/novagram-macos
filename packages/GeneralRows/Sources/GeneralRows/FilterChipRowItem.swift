import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramTheme
import TelegramContext

public final class FilterChipRowItem : GeneralRowItem {
    fileprivate let layout: TextViewLayout
    fileprivate let context: any AccountContextProtocol
    fileprivate let selected: Bool
    public let select: ()->Void
    private let contextMenu: (()->[ContextMenuItem])?
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, text: NSAttributedString, selected: Bool, select: @escaping()->Void, contextMenu: (()->[ContextMenuItem])? = nil) {
        self.context = context
        self.selected = selected
        self.select = select
        self.contextMenu = contextMenu
        self.layout = .init(text, maximumNumberOfLines: 1)
        self.layout.measure(width: .greatestFiniteMagnitude)
        super.init(initialSize)
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        if let contextMenu = self.contextMenu {
            return .single(contextMenu())
        }
        return super.menuItems(in: location)
    }
    
    public override func viewClass() -> AnyClass {
        return FilterChipRowView.self
    }
    
    public override var height: CGFloat {
        return self.layout.layoutSize.width + 24
    }
    
    public override var width: CGFloat {
        return 40
    }

    public override var accessibilityLabel: String? {
        return layout.attributedString.string
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
}

private final class FilterChipRowView : HorizontalRowView {
    private let textView: InteractiveTextView = InteractiveTextView()
    private var selectedView: View?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.userInteractionEnabled = false
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? FilterChipRowItem else {
            return
        }
        
        self.textView.set(text: item.layout, context: item.context)
        self.textView.center()
        
        if item.selected {
            let current: View
            let isNew: Bool
            if let view = self.selectedView {
                current = view
                isNew = false
            } else {
                current = View()
                addSubview(current, positioned: .below, relativeTo: textView)
                self.selectedView = current
                isNew = true
            }
            current.backgroundColor = theme.colors.listGrayText.withAlphaComponent(0.15)
            current.frame = textView.frame.insetBy(dx: -10, dy: -5)
            current.layer?.cornerRadius = current.frame.height / 2
            if isNew, animated {
                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                current.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
            }
        } else if let selectedView {
            performSubviewRemoval(selectedView, animated: animated)
            self.selectedView = nil
        }
    }
    
    override func layout() {
        super.layout()
        self.textView.center()
    }
}
