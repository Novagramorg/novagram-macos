import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Cocoa
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows

public final class ChatListFolderUpdatedRowItem : GeneralRowItem {
    fileprivate let title: TextViewLayout
    public let hide: ()->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, updates: ChatFolderUpdates, action: @escaping()->Void, hide: @escaping()->Void) {
        
        self.hide = hide
        let text = strings().chatListFolderUpdatesTitleOther(updates.availableChatsToJoin)
        
        self.title = .init(.initialize(string: text, color: theme.colors.accent, font: .medium(.title)))

        super.init(initialSize, stableId: stableId, action: action)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        title.measure(width: width - 40)

        return true
    }
    
    public override var height: CGFloat {
        return 20 + title.layoutSize.height
    }
    
    public override func viewClass() -> AnyClass {
        return ChatListFolderUpdatedRowItemView.self
    }
    
    public override var accessibilityLabel: String? {
        return title.attributedString.string
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
    
    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        return [NSAccessibilityCustomAction(name: strings().voiceOverCommonClose, handler: { [weak self] in
            self?.hide()
            return true
        })]
    }
}

private final class ChatListFolderUpdatedRowItemView : TableRowView {
    private let title = TextView()
    private let control = Control()
    private let next = ImageButton()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(control)
        addSubview(title)
        addSubview(next)
        
        
        title.isSelectable = false
        title.userInteractionEnabled = false
        title.isEventLess = true
        
        
        control.border = [.Bottom]
        next.scaleOnClick = true
        next.setAccessibilityLabel(strings().voiceOverCommonClose)
        
        control.set(handler: { [weak self] control in
            if let item = self?.item as? GeneralRowItem {
                item.action()
            }
        }, for: .Click)
        
        next.set(handler: { [weak self] _ in
            if let item = self?.item as? ChatListFolderUpdatedRowItem {
                item.hide()
            }
        }, for: .Click)
        
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        transition.updateFrame(view: title, frame: title.centerFrame())
        transition.updateFrame(view: next, frame: next.centerFrameY(x: size.width - 10 - next.frame.width))
        transition.updateFrame(view: control, frame: size.bounds)

    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? ChatListFolderUpdatedRowItem else {
            return
        }
        title.update(item.title)
        control.setAccessibilityLabel(item.title.attributedString.string)
        
        control.set(background: theme.colors.background, for: .Normal)
        control.set(background: theme.colors.grayTransparent, for: .Highlight)

        control.borderColor = theme.colors.border
        next.set(image: theme.icons.modalClose, for: .Normal)
        next.sizeToFit()
        
       
        needsLayout = true
    }
}
