import Foundation
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import GeneralRows



public final class GroupCallInviteRowItem : GeneralRowItem {
    fileprivate let videoMode: Bool
    fileprivate let text: String
    fileprivate let share: Bool
    public init(_ initialSize: NSSize, height: CGFloat, stableId: AnyHashable, text: String, videoMode: Bool, share: Bool, viewType: GeneralViewType = .legacy, action: @escaping () -> Void) {
        self.videoMode = videoMode
        self.text = text
        self.share = share
        super.init(initialSize, height: height, stableId: stableId, viewType: viewType, action: action, inset: NSEdgeInsets())
    }
    
    public override var width: CGFloat {
        if let superview = table?.superview {
            return superview.frame.width
        } else {
            return super.width
        }
    }
    
    public var isVertical: Bool {
        return false
    }
    
    public override var hasBorder: Bool {
        return !isVertical && viewType.position != .last
    }
    
    public override var instantlyResize: Bool {
        return false
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
    
    public override func viewClass() -> AnyClass {
        return  GroupCallInviteRowView.self
    }
}


private final class GroupCallInviteRowView : GeneralContainableRowView {
    private let textView = TextView()
    private let thumbView = ImageView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(thumbView)
        addSubview(textView)
        
        thumbView.isEventLess = true
        thumbView.isAccessibilityDecorative = true
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        containerView.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Hover)
        
        containerView.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Normal)
        
        containerView.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Highlight)
        
        containerView.set(handler: { [weak self] _ in
            guard let item = self?.item as? GroupCallInviteRowItem else {
                return
            }
            item.action()
        }, for: .Click)
    }
    
    public override func updateColors() {
        super.updateColors()
        self.backgroundColor = .clear
        containerView.backgroundColor = .clear
        textView.backgroundColor = .clear

    }
    
    public override var borderColor: NSColor {
        return GroupCallUIHooks.shared.groupCallThemeCustomTheme().borderColor
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? GroupCallInviteRowItem else {
            return
        }
        
        thumbView.image = item.share ? GroupCallUIHooks.shared.groupCallThemeShareIcon() : GroupCallUIHooks.shared.groupCallThemeInviteIcon()
        thumbView.sizeToFit()
        
        textView.change(opacity: item.isVertical ? 0 : 1, animated: animated)
        
        let layout = TextViewLayout(.initialize(string: item.text, color: GroupCallUIHooks.shared.groupCallThemeCustomTheme().textColor, font: .normal(.title)))
        layout.measure(width: frame.width - 80)
        textView.update(layout)

        self.layout()
        
        if item.isVertical {
            thumbView.change(pos: NSMakePoint(floorToScreenPixels(backingScaleFactor, (160 - thumbView.frame.width) / 2), floorToScreenPixels(backingScaleFactor, (containerView.frame.height - thumbView.frame.height) / 2)), animated: animated)
        } else {
            thumbView.change(pos: NSMakePoint(item.viewType.innerInset.left, floorToScreenPixels(backingScaleFactor, (containerView.frame.height - thumbView.frame.height) / 2)), animated: animated)
            textView.change(pos: NSMakePoint(thumbView.frame.maxX + 20, floorToScreenPixels(backingScaleFactor, (containerView.frame.height - textView.frame.height) / 2)), animated: animated)
        }
        
    }

    public override var additionBorderInset: CGFloat {
        return 44
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
