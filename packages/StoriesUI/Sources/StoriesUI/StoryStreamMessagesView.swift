import Cocoa
import TelegramCallsCore
import TGUIKit
import TelegramMedia
import SwiftSignalKit
import TelegramCore
import Postbox
import AvatarUI
import ChatUI
import GeneralRows
import LocalAnimations
import Localization
import StarsUI
import TelegramContext
import TelegramTheme
import TelegramUtils
import EmojiReplacements
import Strings
import InlineStickerLayer
import InputDataUI

extension GroupCallMessagesContext.Message {
    func withPaidStars(_ paidStars: Int64?) -> GroupCallMessagesContext.Message {
        return .init(id: self.id, stableId: self.stableId, isIncoming: self.isIncoming, author: self.author, isFromAdmin: self.isFromAdmin, text: self.text, entities: self.entities, date: self.date, lifetime: self.lifetime, paidStars: paidStars)
    }
}

struct StoryLiveStreamStarConfig {
    let period: Int
    let length: Int
    let emojis: Int
}



func getEffectiveStarConfig(for value: Int64) -> StoryLiveStreamStarConfig {
    if value >= 10_000 {
        return .init(period: 3600, length: 400, emojis: 20)
    }
    if value >= 2_000 {
        return .init(period: 1800, length: 280, emojis: 10)
    }
    if value >= 500 {
        return .init(period: 900, length: 200, emojis: 7)
    }
    if value >= 250 {
        return .init(period: 600, length: 150, emojis: 4)
    }
    if value >= 100 {
        return .init(period: 300, length: 110, emojis: 3)
    }
    if value >= 50 {
        return .init(period: 120, length: 80, emojis: 2)
    }
    if value >= 10 {
        return .init(period: 60, length: 60, emojis: 1)
    }
    return .init(period: 30, length: 30, emojis: 0)
}




private enum Entry: Identifiable, Comparable {
    static func < (lhs: Entry, rhs: Entry) -> Bool {
        return lhs.index < rhs.index
    }
    
    case message(index: Int32, message: GroupCallMessagesContext.Message, Int32?)
    case empty(index: Int32)
    var index: Int32 {
        switch self {
        case let .message(index, _, _):
            return index
        case let .empty(index):
            return index
        }
    }
    
    var stableId: AnyHashable {
        switch self {
        case let .message(_, message, _):
            return message.stableId
        case .empty:
            return -1
        }
    }
    
    var message: GroupCallMessagesContext.Message? {
        switch self {
        case let .message(_, message, _):
            return message
        case .empty:
            return nil
        }
    }
}

public class StoryMessageArguments {
    let context: any AccountContextProtocol
    let contextMenuItems:(GroupCallMessagesContext.Message, NSAttributedString, Bool)->[ContextMenuItem]
    let focusMessage:(GroupCallMessagesContext.Message)->Void
    public init(context: any AccountContextProtocol, contextMenuItems:@escaping(GroupCallMessagesContext.Message, NSAttributedString, Bool)->[ContextMenuItem], focusMessage:@escaping(GroupCallMessagesContext.Message)->Void) {
        self.context = context
        self.contextMenuItems = contextMenuItems
        self.focusMessage = focusMessage
    }
}

public final class StoryMessageItemRow : TableRowItem {
    fileprivate let arguments: StoryMessageArguments
    fileprivate let message: GroupCallMessagesContext.Message
    fileprivate let textLayout: TextViewLayout
    fileprivate let nameLayout: TextViewLayout
    fileprivate let starsLayout: TextViewLayout?
    fileprivate let adminBadge: TextViewLayout?
    fileprivate let starBadgeLayout: TextViewLayout?
    
    fileprivate var position: TextViewLayout?

    let inset: CGFloat
    
    let preview: Bool
    
    let isAdmin: Bool
    
    let insertDelay: Double?
    
    var isCreator: Bool {
        return isAdmin && message.paidStars == nil
    }
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, message: GroupCallMessagesContext.Message, reactions: AvailableReactions?, arguments: StoryMessageArguments, preview: Bool = false, isAdmin: Bool = false, position: Int32? = nil, insertDelay: Double? = nil) {
        self.arguments = arguments
        self.message = message
        self.preview = preview
        self.insertDelay = insertDelay
        
        if let position {
            self.position = .init(.initialize(string: "\(position)", color: .black, font: .normal(10)))
            self.position?.measure(width: .greatestFiniteMagnitude)
        } else {
            self.position = nil
        }
        
        self.isAdmin = isAdmin && message.paidStars == nil && arc4random() % 2 == 0
        
        
        let entities = message.entities
        let text = message.text.isEmpty ? " " : message.text.fullTrimmed.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        
        if message.text.isEmpty, let paidStars = message.paidStars {
            let attr = NSMutableAttributedString()
            attr.append(string: "\(clown)" + "\(paidStars)", color: .white, font: .normal(.text))
            attr.insertEmbedded(.embedded(name: "star_small", color: .white, resize: false), for: clown)
            self.starsLayout = .init(attr, alignment: .center)
            self.starsLayout?.measure(width: .greatestFiniteMagnitude)
        } else {
            self.starsLayout = nil
        }
        
        if !self.isAdmin, let stars = message.paidStars, !message.text.isEmpty {
            let attr = NSMutableAttributedString()
            attr.append(string: clown + stars.prettyNumber, color: NSColor.white.withAlphaComponent(0.6), font: .normal(.small))
            attr.insertEmbedded(.embedded(name: "star_small", color: NSColor.white.withAlphaComponent(0.6), resize: false), for: clown)
            self.starBadgeLayout = .init(attr)
            self.starBadgeLayout?.measure(width: .greatestFiniteMagnitude)
        } else {
            self.starBadgeLayout = nil
        }

        
        let files:[MediaId : Media] = reactions?.reactions.map {
            $0.centerAnimation?._parse() ?? $0.selectAnimation._parse()
        }.reduce([:], { current, value in
            var current = current
            current[value.fileId] = value
            return current
        }) ?? [:]
        
        
        if entities.count == 1, case let .CustomEmoji(_, fileId) = entities[0].type {
            let isNative = files.contains(where: { $0.value.id?.id == fileId })
            if isNative {
                self.inset = -4
            } else {
                self.inset = 0
            }
        } else {
            self.inset = 0
        }
        
        
        if self.isAdmin {
            adminBadge = .init(
                .initialize(
                    string: strings().storyLiveStreamMessageAdmin,
                    color: darkAppearance.colors.grayText,
                    font: .normal(.small)
                )
            )
            adminBadge?.measure(width: .greatestFiniteMagnitude)
        } else {
            adminBadge = nil
        }
        
                
        let textAttr = ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: text, message: nil, context: arguments.context, fontSize: 13, openInfo: { _, _, _, _ in }, textColor: darkAppearance.colors.text, linkColor: darkAppearance.colors.accent, isDark: true, bubbled: false).mutableCopy() as! NSMutableAttributedString
        
        InlineStickerItem.apply(to: textAttr, associatedMedia: files, entities: entities, isPremium: true, playPolicy: .onceEnd)
        
        
        textAttr.fixUndefinedEmojies()
        
        let peerName = (message.author?._asPeer().compactDisplayTitle ?? "").prefixWithDots(20, mode: .middle)
        
        self.nameLayout = .init(.initialize(string: (position != nil ? "     " : "") + peerName, color: darkAppearance.colors.text, font: .medium(.text)))
        self.nameLayout.measure(width: .greatestFiniteMagnitude)
                
//        let text = message.text.makeAttributeString().mutableCopy() as! NSMutableAttributedString
//        text.addAttribute(.foregroundColor, value: GroupCallTheme.titleColor, range: text.range)
//        text.addAttribute(.font, value: NSFont.normal(.text), range: text.range)
        
        self.textLayout = .init(textAttr , cutout: self.isAdmin ? nil : .init(topLeft: NSMakeSize(nameLayout.layoutSize.width + 5, 20)))
        super.init(initialSize, stableId: stableId)
        
        _ = makeSize(initialSize.width)
        
    }
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        return .single(arguments.contextMenuItems(self.message, textLayout.attributedString, true))
    }
    
    public override var menuPresentation: AppMenu.Presentation {
        return .init(colors: darkAppearance.colors)
    }
    
    public override func makeSize(_ width: CGFloat = CGFloat.greatestFiniteMagnitude, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.textLayout.measure(width: 200)
        return true
    }
    
    public override func viewClass() -> AnyClass {
        return MessageItemView.self
    }

    public override var accessibilityLabel: String? {
        return message.author?._asPeer().compactDisplayTitle
    }

    public override var accessibilityValue: String? {
        var parts: [String] = []
        if !message.text.isEmpty {
            parts.append(message.text)
        }
        if let paidStars = message.paidStars {
            parts.append("\(paidStars) " + strings().voiceOverCommonStars)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override var height: CGFloat {
        var height: CGFloat = max(32, 10 + self.textLayout.layoutSize.height)
        if isAdmin {
            height += nameLayout.layoutSize.height
        }
        return height
    }
}

private let crown = TelegramThemeHooks.shared.image(.iconLiveStreamTopCrown).precomposed(NSColor.white.withAlphaComponent(0.7))

private final class MessageItemView: TableRowView {
    
    class PositionView : View {
        private let imageView = ImageView()
        private let textView = TextView()
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(imageView)
            addSubview(textView)
            self.imageView.image = crown
            self.imageView.sizeToFit()
            self.imageView.isAccessibilityDecorative = true
            textView.userInteractionEnabled = false
            textView.isSelectable = false
            setFrameSize(self.imageView.frame.size)

        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(_ position: TextViewLayout) {
            textView.update(position)
            textView.center()
        }
    }
    
    
    private let containerView = View()
    private let dataView = View()
    private let containerBackground = VisualEffect()
    let textView = InteractiveTextView()
    private let avatarView = AvatarControl(font: .avatar(13))
    
    private var effetView: LottiePlayerView?
    private let effectDisposable = MetaDisposable()
    
    private var effect: StarsButtonEffectLayer?

    private var starsTextView: InteractiveTextView?
    private var starsBadgeView: InteractiveTextView?

    private let nameView = TextView()
    
    private var adminLiveView: ImageView?
    private var adminTextView: TextView?
    
    private var positionView: PositionView?
    
    let overlay = View()
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        overlay.isEventLess = true
        
        
        avatarView.set(handler: { [weak self] _ in
            if let event = NSApp.currentEvent {
                self?.showContextMenu(event)
            }
        }, for: .Click)
        
        
        textView.textView.userInteractionEnabled = false
        
        self.layer?.masksToBounds = false
        overlay.layer?.masksToBounds = false
        
        
        nameView.userInteractionEnabled = false
        nameView.isSelectable = false
        
        dataView.addSubview(nameView)
        dataView.addSubview(textView)
        dataView.addSubview(avatarView)
        
        
        avatarView.setFrameSize(NSMakeSize(22, 22))
        
        
        addSubview(containerView)
        containerView.addSubview(containerBackground)
        containerView.addSubview(dataView)
        self.addSubview(overlay)
        
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func onRemove(_ animation: NSTableView.AnimationOptions) {
        
    }
    
    override func onInsert(_ animation: NSTableView.AnimationOptions, appearAnimated: Bool) {
        if animation.contains(.effectFade), appearAnimated, let item = self.item as? StoryMessageItemRow, visibleRect != .zero {
            self.containerView.layer?.animateScaleSpring(from: 0.01, to: 1.0, duration: 0.6, delay: item.insertDelay ?? 0, removeOnCompletion: false, bounce: false)
        }
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        
        let previous = self.item as? StoryMessageItemRow
        
        super.set(item: item, animated: animated)
        
        guard let item = item as? StoryMessageItemRow else {
            return
        }
        
        containerBackground.isHidden = item.adminBadge == nil
        
        if item.adminBadge == nil, item.message.paidStars == nil {
            textView.textView.drawingLayer.shadowColor = NSColor.black.withAlphaComponent(0.8).cgColor
            nameView.drawingLayer.shadowColor = NSColor.black.withAlphaComponent(0.8).cgColor
        } else {
            textView.textView.drawingLayer.shadowColor = .clear
            nameView.drawingLayer.shadowColor = .clear
        }
        textView.textView.drawingLayer.shadowOpacity = 1
        textView.textView.drawingLayer.shadowOffset = NSMakeSize(0, 0)
        
        nameView.drawingLayer.shadowOpacity = 1
        nameView.drawingLayer.shadowOffset = NSMakeSize(0, 0)


        
        textView.set(text: item.textLayout, context: item.arguments.context,insetEmoji: item.inset)
        avatarView.setPeer(account: item.arguments.context.account, peer: item.message.author?._asPeer())
        nameView.update(item.nameLayout)
        
        if let paidStars = item.message.paidStars {
            let bgColor: NSColor
            if item.preview {
                bgColor = getStarAmountColorMapping(value: paidStars)
            } else {
                bgColor = getStarAmountColorMapping(value: paidStars).withAlphaComponent(0.6)
            }
            dataView.backgroundColor = bgColor
            let current: StarsButtonEffectLayer
            if let layer = self.effect {
                current = layer
            } else {
                current = StarsButtonEffectLayer()
                self.effect = current
                dataView.layer?.addSublayer(current)
            }
            current.color = .white
            current.update(size: dataView.bounds.size)
        } else {
            self.effect?.removeFromSuperlayer()
            self.effect = nil
            dataView.backgroundColor = .clear
        }
        
        if let layout = item.starsLayout {
            let current: InteractiveTextView
            if let view = starsTextView {
                current = view
            } else {
                current = InteractiveTextView()
                current.textView.isSelectable = false
                current.userInteractionEnabled = false
                dataView.addSubview(current)
                self.starsTextView = current
            }
            current.set(text: layout, context: item.arguments.context, emojiOffset: NSMakePoint(-1, 0))
            current.setFrameSize(NSMakeSize(layout.layoutSize.width + 6, layout.layoutSize.height + 4))
            current.backgroundColor = NSColor.black.withAlphaComponent(0.2)
            current.layer?.cornerRadius = current.frame.height / 2
        } else if let starsTextView {
            performSubviewRemoval(starsTextView, animated: animated)
            self.starsTextView = nil
        }
        
        if let layout = item.starBadgeLayout {
            let current: InteractiveTextView
            if let view = starsBadgeView {
                current = view
            } else {
                current = InteractiveTextView()
                current.textView.isSelectable = false
                current.userInteractionEnabled = false
                dataView.addSubview(current)
                self.starsBadgeView = current
            }
            current.set(text: layout, context: item.arguments.context, emojiOffset: NSMakePoint(0, 1))
        } else if let starsBadgeView {
            performSubviewRemoval(starsBadgeView, animated: animated)
            self.starsBadgeView = nil
        }
        
        if item.isCreator {
            let current: ImageView
            if let view = adminLiveView {
                current = view
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                self.adminLiveView = current
                dataView.addSubview(current)
            }
            current.image = StoriesHooks.shared.generateLiveStreamBadge(7, nil)
            current.sizeToFit()
        } else if let view = adminLiveView {
            performSubviewRemoval(view, animated: animated)
            self.adminLiveView = nil
        }
        
        if let adminBadge = item.adminBadge {
            let current: TextView
            if let view = self.adminTextView {
                current = view
            } else {
                current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                dataView.addSubview(current)
                self.adminTextView = current
            }
            current.update(adminBadge)
        } else if let adminTextView {
            performSubviewRemoval(adminTextView, animated: animated)
            self.adminTextView = nil
        }
        
        if let position = item.position {
            let current: PositionView
            if let view = self.positionView {
                current = view
            } else {
                current = PositionView(frame: .zero)
                dataView.addSubview(current)
                self.positionView = current
            }
            current.update(position)
        } else if let positionView {
            performSubviewRemoval(positionView, animated: animated)
            self.positionView = nil
        }
        
        
        containerView.layer?.cornerRadius = 13
        containerBackground.layer?.cornerRadius = 13
        layout()

        
        if previous?.stableId != item.stableId, animated {
            containerView.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
        }
        
    }
//
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        guard let item = item as? StoryMessageItemRow else {
            return
        }
        
        var content_w: CGFloat = textView.frame.width
        
        var sub: CGFloat = 0
        
        if let adminLiveView {
            sub += adminLiveView.frame.width + 2
        }
        if let adminTextView {
            sub += adminTextView.frame.width + 8
        }
        

        
        content_w = max(sub + nameView.frame.width, content_w)
        
        var containerSize = NSMakeSize(2 + avatarView.frame.width + 8 + content_w + 8, size.height - 6)
        if let starsTextView {
            containerSize.width += starsTextView.frame.width
        }
        if let starsBadgeView {
            containerSize.width += starsBadgeView.frame.width + 2
        }
        
        if item.preview {
            transition.updateFrame(view: containerView, frame: size.bounds.focus(containerSize))
        } else {
            transition.updateFrame(view: containerView, frame: size.bounds.focusY(containerSize, x: 10))
        }
        
        transition.updateFrame(view: dataView, frame: containerView.bounds)
        transition.updateFrame(view: overlay, frame: containerView.frame)
        transition.updateFrame(view: containerBackground, frame: containerView.bounds)
        
        
        
        effect?.update(size: dataView.bounds.size)

        let nameX: CGFloat = avatarView.frame.width + 10
//        if let positionView {
//            nameX = positionView.frame.width + 4
//        }
        
        if let positionView {
            transition.updateFrame(view: positionView, frame: CGRect(origin: NSMakePoint(nameX - 3, item.textLayout.lines.count == 1 ? 4 : 1), size: positionView.frame.size))
        }
        
        if item.isAdmin {
            transition.updateFrame(view: avatarView, frame: CGRect(origin: NSMakePoint(2, 2), size: avatarView.frame.size))
            transition.updateFrame(view: nameView, frame: CGRect(origin: NSMakePoint(nameX, 4), size: nameView.frame.size))
            transition.updateFrame(view: textView, frame: CGRect(origin: NSMakePoint(nameView.frame.minX, nameView.frame.maxY + 4), size: textView.frame.size))
            
            if let adminLiveView {
                transition.updateFrame(view: adminLiveView, frame: CGRect(origin: NSMakePoint(nameView.frame.maxX + 2, nameView.frame.minY + 2), size: adminLiveView.frame.size))
            }
            if let adminTextView {
                transition.updateFrame(view: adminTextView, frame: CGRect(origin: NSMakePoint(dataView.frame.width - adminTextView.frame.width - 6, nameView.frame.minY + 2), size: adminTextView.frame.size))
            }
            
        } else {
            transition.updateFrame(view: textView, frame: textView.centerFrameY(x: nameX))
            if size.height == 32 {
                transition.updateFrame(view: avatarView, frame: CGRect(origin: NSMakePoint(2, 2), size: avatarView.frame.size))
            } else {
                transition.updateFrame(view: avatarView, frame: CGRect(origin: NSMakePoint(2, textView.frame.minY), size: avatarView.frame.size))
            }

            transition.updateFrame(view: nameView, frame: CGRect(origin: NSMakePoint(nameX, textView.frame.minY), size: nameView.frame.size))
        }
        
        if let starsBadgeView {
            transition.updateFrame(view: starsBadgeView, frame: CGRect(origin: NSMakePoint(dataView.frame.width - starsBadgeView.frame.width - 8, dataView.frame.height - starsBadgeView.frame.height - 3), size: starsBadgeView.frame.size))
        }
        
        if let starsTextView {
            transition.updateFrame(view: starsTextView, frame: starsTextView.centerFrameY(x: nameView.frame.maxX + 4))
        }
        
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    override func focusAnimation(_ innerId: AnyHashable?, text: String?) {
        
        if let layer = containerView.layer {
            let fadeDown = makeSpringAnimation("opacity")
            fadeDown.fromValue = layer.presentation()?.opacity ?? 1.0
            fadeDown.toValue = 0.7
            fadeDown.duration = 0.35
            fadeDown.fillMode = .forwards
            fadeDown.isRemovedOnCompletion = false

            let fadeUp = makeSpringAnimation("opacity")
            fadeUp.fromValue = 0.7
            fadeUp.toValue = 1.0
            fadeUp.beginTime = CACurrentMediaTime() + 1.0
            fadeUp.duration = 0.35
            fadeUp.fillMode = .forwards
            fadeUp.isRemovedOnCompletion = false

            // Add both to layer
            layer.add(fadeDown, forKey: "fadeDown")
            layer.add(fadeUp, forKey: "fadeUp")
        }

        
    }
    
}



final class StoryMessageFixedItemRow : TableRowItem {
    fileprivate let arguments: StoryMessageArguments
    fileprivate let message: GroupCallMessagesContext.Message
    fileprivate let nameLayout: TextViewLayout
    
    let paidStars: Int64
    
    init(_ initialSize: NSSize, stableId: AnyHashable, message: GroupCallMessagesContext.Message, reactions: AvailableReactions?, arguments: StoryMessageArguments) {
        self.arguments = arguments
        self.message = message
        self.paidStars = message.paidStars!
        
        let peerName = (message.author?._asPeer().compactDisplayTitle ?? "").prefixWithDots(30)
        
        self.nameLayout = .init(.initialize(string: peerName, color: darkAppearance.colors.text, font: .medium(.text)))
        self.nameLayout.measure(width: .greatestFiniteMagnitude)

        super.init(initialSize, stableId: stableId)
        
        
    }
    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        return .single(arguments.contextMenuItems(self.message, NSAttributedString(), false))
    }
    
    override var menuPresentation: AppMenu.Presentation {
        return .init(colors: darkAppearance.colors)
    }
    
    override func makeSize(_ width: CGFloat = CGFloat.greatestFiniteMagnitude, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        return true
    }
    
    override func viewClass() -> AnyClass {
        return FixedMessageItemView.self
    }

    override var accessibilityLabel: String? {
        return message.author?._asPeer().compactDisplayTitle
    }

    override var accessibilityValue: String? {
        return "\(paidStars) " + strings().voiceOverCommonStars
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        arguments.focusMessage(message)
        return true
    }
    
    //WIDTH
    override var height: CGFloat {
        return 26 + 2 + 8 + nameLayout.layoutSize.width + 5 + 10 + 5
    }
    //HEIGHT
    override var width: CGFloat {
        return 26
    }
}

private final class FixedMessageItemView: HorizontalRowView {
    
    private let containerView = VisualEffect()
    private let dataView = View()
    private let containerBackground = View()
    private let avatarView = AvatarControl(font: .avatar(13))
    
    private var effetView: LottiePlayerView?
    private let effectDisposable = MetaDisposable()
    
    private let nameView = TextView()
    
    private let effect = StarsButtonEffectLayer()
    
    private let progress = View()
    
    
    let overlay = Control()
    
    private var animation: DisplayLinkAnimator?
    private var progressValue: Double = 1
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        
        self.avatarView.set(handler: { [weak self] _ in
            if let event = NSApp.currentEvent {
                self?.showContextMenu(event)
            }
        }, for: .Click)
        
        
        overlay.set(handler: { [weak self] _ in
            if let item = self?.item as? StoryMessageFixedItemRow {
                item.arguments.focusMessage(item.message)
            }
        }, for: .Click)
        overlay.setAccessibilityLabel(strings().voiceOverCommonOpen)
        
        self.layer?.masksToBounds = false
        self.overlay.layer?.masksToBounds = false
        
        
        nameView.userInteractionEnabled = false
        nameView.isSelectable = false
        
        dataView.addSubview(progress)
        
        dataView.addSubview(nameView)
        dataView.addSubview(avatarView)
        
        
        avatarView.setFrameSize(NSMakeSize(22, 22))
        
        
        addSubview(containerView)
        containerView.addSubview(containerBackground)
        containerView.addSubview(dataView)
        
        progress.layer?.addSublayer(effect)
        
        self.addSubview(overlay)
        
        
        containerBackground.backgroundColor = GroupCallTheme.membersColor.withAlphaComponent(0.5)
                        
    }
    

    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func onRemove(_ animation: NSTableView.AnimationOptions) {
        if animation.contains(.effectFade) {
        }
    }
    
    override func onInsert(_ animation: NSTableView.AnimationOptions, appearAnimated: Bool) {
        if animation.contains(.effectFade), appearAnimated {
            self.containerView.layer?.animateScaleSpring(from: 0.1, to: 1.0, duration: 0.6, removeOnCompletion: false, bounce: false)
        }
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        
        let previous = self.item as? StoryMessageFixedItemRow
        
        super.set(item: item, animated: animated)
        
        guard let item = item as? StoryMessageFixedItemRow else {
            return
        }
        
        let color = getStarAmountColorMapping(value: item.paidStars)
        
        progress.backgroundColor = color
        dataView.backgroundColor = color.withAlphaComponent(0.2)

        
        let duration = item.message.date + item.message.lifetime - item.arguments.context.timestamp
        
        let currentValue = duration <= 0 ? 0 : min(1, Double(duration) / Double(item.message.lifetime))
        
        self.progressValue = item.message.id.space == .remote ? 1 : currentValue
        
        if item.message.id.space == .remote {
            self.animation = DisplayLinkAnimator(duration: Double(duration), from: currentValue, to: 0, update: { [weak self] value in
                
                guard let self else {
                    return
                }
                self.progressValue = value
                self.updateLayout(size: self.frame.size, transition: .animated(duration: 0.01, curve: .linear))
            }, completion: {
                
            })
        }
                
    
        
        avatarView.setPeer(account: item.arguments.context.account, peer: item.message.author?._asPeer())
        nameView.update(item.nameLayout)
        
        containerView.layer?.cornerRadius = 13
        containerBackground.layer?.cornerRadius = 13
        layout()

        
        if previous?.stableId != item.stableId, animated {
            containerView.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
        }
        
    }
//
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        let size = NSMakeSize(size.height, size.width)
        
        
        let containerSize = NSMakeSize(2 + avatarView.frame.width + 8 + nameView.frame.width + 10, size.height)
        
        transition.updateFrame(view: containerView, frame: size.bounds.focusY(containerSize, x: 10))
        
        transition.updateFrame(view: dataView, frame: containerView.bounds)
        transition.updateFrame(view: overlay, frame: containerView.frame)
        transition.updateFrame(view: containerBackground, frame: containerView.bounds)
        transition.updateFrame(view: progress, frame: CGRect(origin: .zero, size: NSMakeSize(floorToScreenPixels(containerView.bounds.width * progressValue), containerView.bounds.height)))
        
        self.effect.frame = self.dataView.bounds
        self.effect.color = .white
        self.effect.update(size: size)
        

        transition.updateFrame(view: avatarView, frame: avatarView.centerFrameY(x: 2))

        transition.updateFrame(view: nameView, frame: nameView.centerFrameY(x: avatarView.frame.maxX + 8))
        
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
}



private func generateReaction(account: Account, _ item: StoryReactionsView.Item) -> Signal<CGImage?, NoError> {
    if let peer = item.message.author?._asPeer(), let stars = item.message.paidStars {
        return peerAvatarImage(account: account, photo: .peer(peer, peer.smallProfileImage, peer.namePeerColor, TelegramUtilsHooks.shared.peerLetters(peer), nil, nil), displayDimensions: NSMakeSize(14 * System.backingScale, 14 * System.backingScale), font: .avatar(9), genCap: false, synchronousLoad: false) |> take(1) |> map { avatar in
            
            if let avatar = avatar.0  {
                let textNode = TextNode.layoutText(.initialize(string: "\(stars)", color: .white, font: .avatar(10)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, 20), nil, false, .center)
                var size = textNode.0.size
                
                let icon = TelegramThemeHooks.shared.image(.starSmall).precomposed(.white, flipVertical: true, zoom: 0.9)

                size.width += 2 + (14 + icon.backingSize.width) + 4 + 2
                size.height = 16
                return generateImage(size, rotatedContext: { size, ctx in
                    let rect = NSMakeRect(0, 0, size.width, size.height)
                    ctx.clear(rect)
                    
                    ctx.round(size, size.height / 2)
                    ctx.setFillColor(NSColor(0xFFAC04).cgColor)
                    ctx.fill(rect)
                    
                    let avatarRect = rect.focusY(NSMakeSize(14, 14), x: 1)
                    ctx.saveGState()
                    ctx.translateBy(x: rect.width / 2.0, y: rect.height / 2.0)
                    ctx.scaleBy(x: 1, y: -1.0)
                    ctx.translateBy(x: -rect.width / 2.0, y: -rect.height / 2.0)

                    ctx.draw(avatar, in:avatarRect )
                    ctx.restoreGState()
                    
                    var iconRect = rect.focusY(icon.backingSize, x: avatarRect.maxX + 3)
                    iconRect.origin.y -= 1
                    ctx.draw(icon, in: iconRect)
                    
                    let textRect = rect.focusY(textNode.0.size, x: iconRect.maxX)
                    
                    textNode.1.draw(textRect, in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
                })
            } else {
                return nil
            }
        }
    } else {
        return .single(nil)
    }
}

private final class StoryReactionsView: NSView {

    struct Item: Equatable {
        var message: GroupCallMessagesContext.Message
    }

    private let maxActiveLayers = 60
    private let minDuration: CFTimeInterval = 5
    private let maxDuration: CFTimeInterval = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { nil }

    func add(items: [Item], account: Account, animated: Bool) {
        trimIfNeeded()

        for item in items {
            let signal = generateReaction(account: account, item) |> deliverOnMainQueue
            
            _ = signal.startStandalone(next: { [weak self] image in
                if let image {
                    self?.insert(image)
                }
            })
            
        }
    }
    
    private func insert(_ image: CGImage) {
        guard let host = layer else { return }

        let imgLayer = CALayer()
        imgLayer.contentsScale = backingScaleFactor
        imgLayer.contentsGravity = .resizeAspect
        imgLayer.bounds = CGRect(x: 0, y: 0, width: image.backingSize.width, height: image.backingSize.height)
        imgLayer.contents = image
        imgLayer.shouldRasterize = true
        imgLayer.rasterizationScale = imgLayer.contentsScale

        let startX = randomStartX(in: host.bounds)
        let startY = host.bounds.minY - imgLayer.bounds.height * 0.5

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imgLayer.position = CGPoint(x: startX, y: startY)
        imgLayer.opacity = 0
        host.addSublayer(imgLayer)
        CATransaction.commit()

        animate(layer: imgLayer, in: host.bounds)
    }

    // MARK: - Anim

    private func animate(layer l: CALayer, in bounds: CGRect) {
        
        l.animateScale(from: 0.1, to: 1, duration: 0.3, timingFunction: .easeInEaseOut)
        
        let duration = Double.random(in: minDuration...maxDuration)

        // Keyframe position along a bezier path with sideways “wind”
        let path = bubblePath(in: bounds, start: l.position, height: bounds.height, amplitude: bounds.width * 0.12)
        let pos = CAKeyframeAnimation(keyPath: "position")
        pos.path = path
        pos.duration = duration
        pos.calculationMode = .paced
        pos.timingFunctions = [CAMediaTimingFunction(name: .easeOut)]

        // Opacity fade
        let op = CAKeyframeAnimation(keyPath: "opacity")
        op.values = [0.5, 1.0, 0.8, 0.0]
        op.keyTimes = [0.0, 0.15, 0.7, 1.0] as [NSNumber]
        op.duration = duration

        // Slight scale up
        let sc = CAKeyframeAnimation(keyPath: "transform.scale")
        sc.values = [0.9, 1.05, 1.0]
        sc.keyTimes = [0.0, 0.25, 1.0] as [NSNumber]
        sc.duration = duration

        let group = CAAnimationGroup()
        group.animations = [pos, op, sc]
        group.duration = duration
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak l] in
            l?.removeFromSuperlayer()
        }
        l.add(group, forKey: "bubble")
        CATransaction.commit()
    }

    private func bubblePath(in bounds: CGRect, start: CGPoint, height: CGFloat, amplitude: CGFloat) -> CGPath {
        let margin: CGFloat = 24
        let A = min(amplitude, (bounds.width - 2*margin) * 0.5)

        // 0.6–1.2 lateral waves across full rise. Add small drift so it does not ping-pong.
        let cycles = Double.random(in: 0.6...1.2)
        let phase = Double.random(in: 0...(2 * .pi))
        let drift = CGFloat.random(in: -A*0.35...A*0.35)

        let samples = 48
        let p = CGMutablePath()
        p.move(to: start)

        func clampX(_ x: CGFloat) -> CGFloat {
            min(bounds.maxX - margin, max(bounds.minX + margin, x))
        }

        for i in 1...samples {
            let t = Double(i) / Double(samples)            // 0..1
            let y = start.y + CGFloat(t) * height
            let sine = sin(2 * .pi * cycles * t + phase)   // smooth left/right
            let x = clampX(start.x + drift * CGFloat(t) + CGFloat(sine) * A * (1.0 - 0.15 * CGFloat(t)))
            p.addLine(to: CGPoint(x: x, y: y))
        }
        return p
    }


    // MARK: - Utils

    private func randomStartX(in bounds: CGRect) -> CGFloat {
        let margin: CGFloat = 24
        return CGFloat.random(in: (bounds.minX + margin)...(bounds.maxX - margin))
    }

    private func trimIfNeeded() {
        guard let host = layer else { return }
        let active = host.sublayers?.count ?? 0
        if active <= maxActiveLayers { return }
        // Drop oldest
        let drop = active - maxActiveLayers
        host.sublayers?.prefix(drop).forEach { $0.removeFromSuperlayer() }
    }
}


final class StoryStreamMessagesView : View {
    private let tableView: TableView
    private let maskLayer = CAGradientLayer()
    private let fixedTableView: HorizontalTableView

    private var messages: [Entry] = []
    private var fixed_messages: [Entry] = []
    private var arguments: StoryArguments?
    
    private let reactionsView: StoryReactionsView
    
    var messagesState:GroupCallMessagesContext.State? = nil
    
    required init(frame frameRect: NSRect) {
        self.fixedTableView = HorizontalTableView(frame: NSMakeRect(0, 0, frameRect.width, 30))
        self.tableView = TableView(frame: frameRect.size.bounds, isFlipped: false)
        self.reactionsView = StoryReactionsView(frame: NSMakeRect(0, 0, 100, frameRect.height))
        super.init(frame: frameRect)
        
        
        
        isEventLess = true
        
        addSubview(tableView)
        addSubview(fixedTableView)
        
        addSubview(reactionsView)
        
        tableView.layer?.masksToBounds = false
        tableView.contentView.layer?.masksToBounds = false
        tableView.documentView?.layer?.masksToBounds = false
        
        fixedTableView.layer?.masksToBounds = false
        fixedTableView.contentView.layer?.masksToBounds = false
        fixedTableView.documentView?.layer?.masksToBounds = false
        
        
        tableView.contentInsets = NSEdgeInsets(top: 35, left: 0, bottom: 0, right: 0)
        
        tableView.getBackgroundColor = {
            .clear
        }
        fixedTableView.getBackgroundColor = {
            .clear
        }
        
        
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
    func update(state: GroupCallMessagesContext.State, lastHideMessageId: Int64?, arguments: StoryArguments, animated: Bool) {
        
        
        
        let adminId = arguments.interaction.presentation.entryId
        
        let myPeerId = arguments.interaction.presentation.mediaCall?.state?.myPeerId ?? arguments.context.peerId
        
        self.arguments = arguments
        let context = arguments.context
        
        self.messagesState = state
        
        
        
       
        let messageArguments = StoryMessageArguments(context: context, contextMenuItems: { [weak self, weak arguments] message, attr, fullMessage in
            var items: [ContextMenuItem] = []
            
           
            
            if let peer = message.author {
                
                if let item = FeatureNavigationHooks.shared.makeGroupCallAvatarMenuItem(peer._asPeer(), context) { items.append(item) }
                
                items.append(ContextMenuItem(peer._asPeer().displayTitle, handler: {
                    arguments?.openPeerInfo(peer.id, nil)
                }, itemImage: MenuAnimation.menu_open_profile.value))
                
            }
            
            items.append(ContextSeparatorItem())
            
            if !attr.string.trimmingTrailingSpaces().isEmpty {
                items.append(ContextMenuItem(strings().textCopyText, handler: {
                    if let window = self?._window {
                        _ = LinkHooks.shared.globalLinkExecutor().copyAttributedString(attr)
                        showModalText(for: window, text: strings().shareLinkCopied)
                    }
                }, itemImage: MenuAnimation.menu_copy.value))
            }
            
            let isSelfMesssage = arguments?.interaction.presentation.mediaCall?.state?.sendAs.contains(where: {
                $0.peer.id == message.author?.id
            }) == true || message.author?.id == context.peerId
            
            if adminId == message.author?.id && !isSelfMesssage, fullMessage {
                
                items.append(ContextMenuItem(strings().reportReasonReport, handler: {
                    arguments?.reportMessage(message)
                }, itemImage: MenuAnimation.menu_report.value))
                
            }
            
            if adminId == message.author?.id || isSelfMesssage, fullMessage {
                items.append(ContextSeparatorItem())
                items.append(ContextMenuItem(strings().messageContextDelete, handler: {
                    arguments?.deleteMessage(message, isSelfMesssage)
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
            }
            
            return items
            
        }, focusMessage: { [weak self] message in
            if (self?.messages.first(where: { $0.message?.id == message.id })) != nil {
                self?.tableView.scroll(to: .center(id: message.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: 0))
            }
        })
        
        let size = self.frame.size
        
        var index: Int32 = 0
        let getIndex:()->Int32 = {
            index += 1
            return index
        }
        
        
        let fixed_entries: [Entry] = state.pinnedMessages
            .filter { value in
                if value.paidStars == nil {
                    return false
                } else {
                    let duration = value.date + value.lifetime - context.timestamp
                    return duration > 0
                }
            }
            .reduce([], { result, value in
                var result = result
                if let index = result.firstIndex(where: { $0.author?.id == value.author?.id }) {
                    let lhsPaidStars = value.paidStars ?? 0
                    let rhsPaidStars = result[index].paidStars ?? 0
                    if lhsPaidStars > rhsPaidStars {
                        result[index] = value
                    }
                } else {
                    result.append(value)
                }
                return result
            })
            .sorted { $0.paidStars! > $1.paidStars! }
            .map { .message(index: getIndex(), message: $0, nil) }

        
        let getPosition:(GroupCallMessagesContext.Message)->Int32? = { message in
            let topStars = arguments.interaction.presentation.mediaCall?.messages?.topStars ?? []
            for (i, top) in topStars.enumerated() {
                if top.peerId == message.author?.id {
                    return Int32(i + 1)
                }
            }
            return nil
        }
        
        var entries: [Entry] = []
        
        let minPrice = arguments.interaction.presentation.mediaCall?.state?.messagesEnabled?.sendPaidMessagesStars
                
        entries.append(contentsOf: state.messages.filter { message in
            let paidStars = message.paidStars ?? 0
            if let minPrice, paidStars < minPrice {
                return false
            } else {
                return true
            }
        }.map { .message(index: getIndex(), message: $0, getPosition($0)) })
        
        if !fixed_entries.isEmpty {
            entries.append(.empty(index: -1))
        }
        
        let isInit: Bool = self.tableView.isEmpty
        
        var insertDelay:Double = Double(entries.count) * 0.05
        
        let getInsertDelay:()->Double? = {
            if isInit {
                insertDelay -= 0.05
                return insertDelay
            } else {
                return nil
            }
        }
        
        let (deleted,inserted,updated) = proccessEntries(messages, right: entries, { entry -> TableRowItem in
            switch entry {
            case let .message(_, message, position):
                return StoryMessageItemRow(size, stableId: entry.stableId, message: message, reactions: nil, arguments: messageArguments, isAdmin: message.isFromAdmin, position: position, insertDelay: getInsertDelay())
            case .empty:
                return GeneralRowItem(size, height: 40, stableId: entry.stableId, backgroundColor: .clear)
            }
        })
        
        let (fixed_deleted, fixed_inserted, fixed_updated) = proccessEntries(fixed_messages, right: fixed_entries, { entry -> TableRowItem in
            switch entry {
            case let .message(_, message, _):
                return StoryMessageFixedItemRow(size, stableId: entry.stableId, message: message, reactions: nil, arguments: messageArguments)
            case .empty:
                fatalError()
            }
        })
        
        let scrollState: TableScrollState
        if inserted.contains(where: { ($0.1 as? StoryMessageItemRow)?.message.author?.id == myPeerId }) {
            scrollState = .down(true)
        } else {
            scrollState = .none(nil)
        }
        
        let transition = TableUpdateTransition(deleted: deleted, inserted: inserted, updated: updated, animated: animated, state: scrollState, grouping: true, animateVisibleOnly: true, searchState: nil)
        
        let fixed_transition = TableUpdateTransition(deleted: fixed_deleted, inserted:fixed_inserted, updated: fixed_updated, animated: animated, state: .none(nil), grouping: false, animateVisibleOnly: true, searchState: nil)

        
        var reactions = (transition.inserted)
            .compactMap {
                $0.1 as? StoryMessageItemRow
            }
            .map {
                $0.message
            }
            .filter {
                $0.paidStars != nil
            }
        
        let updated_reactions = transition.updated.compactMap {
            $0.1 as? StoryMessageItemRow
        }
        .map {
            $0.message
        }
        .filter {
            $0.paidStars != nil
        }
        
        let previous_messages = self.messages.compactMap { $0.message }
        
        for updatedMessage in updated_reactions {
            if let previousMessage = previous_messages.first(where: { $0.stableId == updatedMessage.stableId }) {
                if let prevStars = previousMessage.paidStars, let currentStars = updatedMessage.paidStars {
                    if prevStars < currentStars {
                        reactions.append(updatedMessage.withPaidStars(currentStars - prevStars))
                    }
                }
            }
        }
        
        
        if !self.tableView.isEmpty, !reactions.isEmpty {
            self.reactionsView.add(items: reactions.map(StoryReactionsView.Item.init), account: context.account, animated: true)
        }

        
        self.messages = entries
        self.fixed_messages = fixed_entries

        tableView.merge(with: transition, appearAnimated: true)
        fixedTableView.merge(with: fixed_transition, appearAnimated: true)
        
        fixedTableView.isHidden = fixedTableView.isEmpty
        
        tableView.change(opacity: lastHideMessageId != nil ? 0 : 1, animated: animated)

        self.updateLayout(size: self.frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
        
    }
    
    override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    
    private func updateMask() {
        guard let clipView = tableView.layer else { return }

        let gradientHeight: CGFloat = 35
        let h = clipView.bounds.height

        var bottomHiddenOffset: CGFloat = 0
        if !fixedTableView.isHidden {
            bottomHiddenOffset = fixedTableView.frame.height / 2
        }

        maskLayer.frame = clipView.bounds
        maskLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            fixedTableView.isHidden ? NSColor.black.cgColor : NSColor.clear.cgColor
        ]

        maskLayer.locations = [
            0.0,
            NSNumber(value: Float(gradientHeight / h)),
            NSNumber(value: Float((h - gradientHeight - bottomHiddenOffset) / h)),
            1.0
        ]

        maskLayer.startPoint = CGPoint(x: 0.5, y: 0)
        maskLayer.endPoint = CGPoint(x: 0.5, y: 1)

        clipView.mask = maskLayer
    }
    

    
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        transition.updateFrame(view: fixedTableView, frame: NSMakeRect(0, size.height - fixedTableView.frame.height - 10, size.width, fixedTableView.frame.height))
        
        transition.updateFrame(view: tableView, frame: NSMakeRect(0, 0, size.width, size.height - 5))
        
        transition.updateFrame(view: reactionsView, frame: NSMakeRect(size.width - 100, 0, 100, size.height))
        
        updateMask()
    }
    
}
