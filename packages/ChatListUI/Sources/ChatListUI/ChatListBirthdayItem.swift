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
import AvatarUI
import ChatUI
import InputDataUI

public final class ChatListAddBirthdayItem : GeneralRowItem {
    public let title: TextViewLayout
    public let info: TextViewLayout
    public let context: any AccountContextProtocol
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol) {
        self.context = context
        self.title = .init(.initialize(string: strings().chatListBirthdayAddTitle, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
        self.info = .init(.initialize(string: strings().chatListBirthdayAddInfo, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 2)
        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.title.measure(width: max(300, width) - 20 - 15)
        self.info.measure(width: max(300, width) - 20 - 15)
        return true
    }
    
    public func invoke(_ date: Date) {
        FeatureNavigationHooks.shared.updateAccountBirthday(date, context)
        _ = context.engine.notices.dismissServerProvidedSuggestion(suggestion: ServerProvidedSuggestion.setupBirthday.id).startStandalone()
    }
    
    public func dismiss() {
        _ = context.engine.notices.dismissServerProvidedSuggestion(suggestion: ServerProvidedSuggestion.setupBirthday.id).startStandalone()
    }
    
    public override func viewClass() -> AnyClass {
        return ChatListAddBirthdayView.self
    }
    
    public override var height: CGFloat {
        return 5 + 8 + title.layoutSize.height + 3 + info.layoutSize.height + 8
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }
    
    public override var accessibilityValue: String? {
        return info.attributedString.string
    }
    
    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }
    
    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func accessibilityPerformPress() -> Bool {
        guard let view = view as? ChatListAddBirthdayView else {
            return false
        }
        view.overlay.send(event: .Click)
        return true
    }
    
    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        return [NSAccessibilityCustomAction(name: strings().voiceOverCommonClose, handler: { [weak self] in
            self?.dismiss()
            return true
        })]
    }
}

public final class ChatListBirthdayItem : GeneralRowItem {
    
    public let birthdays: [UIChatListBirthday]
    public let context: any AccountContextProtocol
    public let title: TextViewLayout
    public let info: TextViewLayout

    public init(_ initialSize: NSSize, stableId: AnyHashable, birthdays: [UIChatListBirthday], context: any AccountContextProtocol) {
        self.birthdays = birthdays
        self.context = context
        
        let titleAttr = NSMutableAttributedString()
        if birthdays.count == 1 {
            titleAttr.append(string: strings().chatListBirthdaySingleTitle(birthdays[0].peer._asPeer().compactDisplayTitle), color: theme.colors.text, font: .medium(.text))
        } else {
            titleAttr.append(string: strings().chatListBirthdayMultipleTitleOther(birthdays.count), color: theme.colors.text, font: .medium(.text))
        }
        titleAttr.detectBoldColorInString(with: .medium(.text), color: theme.colors.accent)
        
        self.title = .init(titleAttr, maximumNumberOfLines: 1)
        self.info = .init(.initialize(string: strings().chatListBirthdayInfoNewOther(birthdays.count), color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 2)

        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.title.measure(width: width - 20 - 20 - CGFloat(30 + (birthdays.prefix(2).count - 1) * 24))
        self.info.measure(width: width - 20 - 20 - CGFloat(30 + (birthdays.prefix(2).count - 1) * 24))
        return true
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        var items: [ContextMenuItem] = []
        let context = self.context
        for birthday in birthdays {
            items.append(ReactionPeerMenu(title: birthday.peer._asPeer().displayTitle, handler: { [weak self] in
                self?.context.bindings.rootNavigation().push(ChatListUIHooks.shared.makeChatAdditionController(context, .peer(birthday.peer.id)))
                
            }, peer: birthday.peer._asPeer(), context: context, reaction: nil))
        }
        
        return .single(items)
    }
    
    public func invoke(morphSource: (() -> NSView?)? = nil) {
        let context = self.context
        ChatListUIHooks.shared.multigift(context, self.birthdays.map { $0.peer.id }, morphSource)
    }
    
    public func dismiss() {
        _ = context.engine.notices.dismissServerProvidedSuggestion(suggestion: ServerProvidedSuggestion.todayBirthdays.id).startStandalone()
    }
    
    
    public override func viewClass() -> AnyClass {
        return ChatListBirthdayView.self
    }
    
    public override var height: CGFloat {
        return 5 + 8 + title.layoutSize.height + 3 + info.layoutSize.height + 8
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }
    
    public override var accessibilityValue: String? {
        return info.attributedString.string
    }
    
    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }
    
    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func accessibilityPerformPress() -> Bool {
        guard let view = view as? ChatListBirthdayView else {
            return false
        }
        view.overlay.send(event: .Click)
        return true
    }
    
    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        return [NSAccessibilityCustomAction(name: strings().voiceOverCommonClose, handler: { [weak self] in
            self?.dismiss()
            return true
        })]
    }
}

private final class ChatListBirthdayView : TableRowView {

    private var avatars:[AvatarContentView] = []
    private let avatarsContainer = View(frame: NSMakeRect(0, 0, 30 * 3, 30))

    private var peers:[Avatar] = []

    private let container = View()

    private let titleView = TextView()
    private let infoView = TextView()
    fileprivate let overlay = Control()
    private let dismiss = ImageButton()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        container.layer?.cornerRadius = 10
        if #available(macOS 10.15, *) {
            container.layer?.cornerCurve = .continuous
        }
        container.layer?.borderWidth = 1

        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)

        addSubview(container)
        container.addSubview(titleView)
        container.addSubview(infoView)

        container.addSubview(avatarsContainer)
        avatarsContainer.isEventLess = true

        container.addSubview(overlay)

        container.addSubview(dismiss)

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false

        infoView.userInteractionEnabled = false
        infoView.isSelectable = false
        
        overlay.set(handler: { [weak self] control in
            if let item = self?.item as? ChatListBirthdayItem {
                item.invoke(morphSource: { [weak self] in self?.container })
            }
        }, for: .Click)

        dismiss.set(handler: { [weak self] control in
            if let item = self?.item as? ChatListBirthdayItem {
                item.dismiss()
            }
        }, for: .Click)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 5
        let padding: CGFloat = 5
        container.frame = NSMakeRect(inset, padding, frame.width - inset * 2, frame.height - padding)
        overlay.frame = container.bounds

        self.avatarsContainer.centerY(x: 10)

        let maxX = CGFloat(30 + (avatarsContainer.subviews.count - 1) * 20) + 20
        titleView.setFrameOrigin(NSMakePoint(maxX, 8))
        infoView.setFrameOrigin(NSMakePoint(maxX, container.frame.height - infoView.frame.height - 8))

        dismiss.centerY(x: container.frame.width - 10 - dismiss.frame.width)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? ChatListBirthdayItem else {
            return
        }
        
        self.titleView.update(item.title)
        self.infoView.update(item.info)
        overlay.setAccessibilityLabel(item.title.attributedString.string)
        
        dismiss.set(image: TelegramThemeHooks.shared.image(.iconVoiceChatTooltipClose).precomposed(theme.colors.grayIcon), for: .Normal)
        dismiss.autohighlight = false
        dismiss.scaleOnClick = true
        dismiss.sizeToFit(NSMakeSize(10, 10))
        
        
        container.backgroundColor = theme.colors.background.withAlphaComponent(0.4)
        container.layer?.borderColor = theme.colors.border.cgColor

        let duration = Double(0.2)
        let timingFunction = CAMediaTimingFunctionName.easeOut
        
        
        let peers:[Avatar] = item.birthdays.prefix(2).reduce([], { current, value in
            var current = current
            current.append(.init(peer: value.peer._asPeer(), index: current.count))
            return current
        })
        
        let (removed, inserted, updated) = mergeListsStableWithUpdates(leftList: self.peers, rightList: peers)
        
        for removed in removed.reversed() {
            let control = avatars.remove(at: removed)
            let peer = self.peers[removed]
            let haveNext = peers.contains(where: { $0.stableId == peer.stableId })
            control.updateLayout(size: NSMakeSize(30, 30), isClipped: false, animated: animated)
            if animated && !haveNext {
                control.layer?.animateAlpha(from: 1, to: 0, duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: { [weak control] _ in
                    control?.removeFromSuperview()
                })
                control.layer?.animateScaleSpring(from: 1.0, to: 0.2, duration: duration)
            } else {
                control.removeFromSuperview()
            }
        }
        for inserted in inserted {
            let control = AvatarContentView(context: item.context, peer: inserted.1.peer, message: nil, synchronousLoad: false, size: NSMakeSize(30, 30), inset: 8)
            control.updateLayout(size: NSMakeSize(30, 30), isClipped: inserted.0 != 0, animated: animated)
            control.userInteractionEnabled = false
            control.setFrameSize(NSMakeSize(30, 30))
            control.setFrameOrigin(NSMakePoint(CGFloat(inserted.0) * 20, 0))
            avatars.insert(control, at: inserted.0)
            avatarsContainer.subviews.insert(control, at: inserted.0)
            if animated {
                if let index = inserted.2 {
                    control.layer?.animatePosition(from: NSMakePoint(CGFloat(index) * 22, 0), to: control.frame.origin, timingFunction: timingFunction)
                } else {
                    control.layer?.animateAlpha(from: 0, to: 1, duration: duration, timingFunction: timingFunction)
                    control.layer?.animateScaleSpring(from: 0.2, to: 1.0, duration: duration)
                }
            }
        }
        for updated in updated {
            let control = avatars[updated.0]
            control.updateLayout(size: NSMakeSize(30, 30), isClipped: updated.0 != 0, animated: animated)
            let updatedPoint = NSMakePoint(CGFloat(updated.0) * 20, 0)
            if animated {
                control.layer?.animatePosition(from: control.frame.origin - updatedPoint, to: .zero, duration: duration, timingFunction: timingFunction, additive: true)
            }
            control.setFrameOrigin(updatedPoint)
        }
        var index: CGFloat = 10
        for control in avatarsContainer.subviews.compactMap({ $0 as? AvatarContentView }) {
            control.layer?.zPosition = index
            index -= 1
        }
        
        self.peers = peers
        
        needsLayout = true
    }

}



private final class ChatListAddBirthdayView : TableRowView {
    private let container = View()
    private let titleView = TextView()
    private let infoView = TextView()
    fileprivate let overlay = Control()
    private let dismiss = ImageButton()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        container.layer?.cornerRadius = 10
        if #available(macOS 10.15, *) {
            container.layer?.cornerCurve = .continuous
        }
        container.layer?.borderWidth = 1

        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)

        addSubview(container)
        container.addSubview(titleView)
        container.addSubview(infoView)
        container.addSubview(overlay)
        container.addSubview(dismiss)
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false

        infoView.userInteractionEnabled = false
        infoView.isSelectable = false
        
        overlay.set(handler: { [weak self] control in
            guard let self, let item = self.item as? ChatListAddBirthdayItem else {
                return
            }
            guard let controller = FeatureNavigationHooks.shared.makeCalendarController(item.context.window, Date(), 1900, true, { date in
                item.invoke(date)
            }) else {
                return
            }
            let nav = NavigationViewController(controller, item.context.window)
            nav._frameRect = NSMakeRect(0, 0, 300, 330)
            showModal(with: nav, for: item.context.window, morphSource: { [weak self] in self?.container })

        }, for: .Click)
        
        dismiss.set(handler: { [weak self] control in
            if let item = self?.item as? ChatListAddBirthdayItem {
                item.dismiss()
            }
        }, for: .Click)
    }
    
    override func layout() {
        super.layout()
        let inset: CGFloat = 5
        let padding: CGFloat = 5
        container.frame = NSMakeRect(inset, padding, frame.width - inset * 2, frame.height - padding)
        overlay.frame = container.bounds
        titleView.setFrameOrigin(NSMakePoint(10, 8))
        infoView.setFrameOrigin(NSMakePoint(10, container.frame.height - infoView.frame.height - 8))

        dismiss.centerY(x: container.frame.width - 10 - dismiss.frame.width)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? ChatListAddBirthdayItem else {
            return
        }

        self.titleView.update(item.title)
        self.infoView.update(item.info)
        overlay.setAccessibilityLabel(item.title.attributedString.string)

        dismiss.set(image: TelegramThemeHooks.shared.image(.iconVoiceChatTooltipClose).precomposed(theme.colors.grayIcon), for: .Normal)
        dismiss.autohighlight = false
        dismiss.scaleOnClick = true
        dismiss.sizeToFit(NSMakeSize(10, 10))

        container.backgroundColor = theme.colors.background.withAlphaComponent(0.4)
        container.layer?.borderColor = theme.colors.border.cgColor
    }
}
