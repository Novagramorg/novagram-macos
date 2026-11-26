import Cocoa
import TelegramCallsCore
import TGUIKit
import TelegramMedia
import SwiftSignalKit
import TelegramCore
import Postbox
import AvatarUI
import GeneralRows
import InlineStickers
import SceneEffects
import TelegramContext
import TelegramTheme
import TelegramUtils
import EmojiReplacements
import Strings
import InlineStickerLayer

private struct Entry: Identifiable, Comparable {
    static func < (lhs: Entry, rhs: Entry) -> Bool {
        return lhs.index < rhs.index
    }
    
    var index: Int32
    var message: GroupCallMessagesContext.Message
    
    var stableId: AnyHashable {
        return message.id
    }
}

fileprivate class Arguments {
    let context: any AccountContextProtocol
    let contextMenuItems:(GroupCallMessagesContext.Message)->[ContextMenuItem]
    init(context: any AccountContextProtocol, contextMenuItems:@escaping(GroupCallMessagesContext.Message)->[ContextMenuItem]) {
        self.context = context
        self.contextMenuItems = contextMenuItems
    }
}

private final class MessageItemRow : TableRowItem {
    fileprivate let arguments: Arguments
    fileprivate let message: GroupCallMessagesContext.Message
    fileprivate let textLayout: TextViewLayout
    fileprivate let nameLayout: TextViewLayout
    
    let inset: CGFloat
    
    init(_ initialSize: NSSize, stableId: AnyHashable, message: GroupCallMessagesContext.Message, reactions: AvailableReactions?, arguments: Arguments) {
        self.arguments = arguments
        self.message = message
        
        let entities = message.entities
        let text = message.text
        
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
        
        
                
        let textAttr = GroupCallScreenUIHooks.shared.formatMessageText(entities, text, arguments.context, 13, TelegramThemeHooks.shared.darkAppearance().colors.text, TelegramThemeHooks.shared.darkAppearance().colors.accent).mutableCopy() as! NSMutableAttributedString
        
        InlineStickerItem.apply(to: textAttr, associatedMedia: files, entities: entities, isPremium: true, playPolicy: .onceEnd)
        
        
        textAttr.fixUndefinedEmojies()
        
        let peerName = (message.author?._asPeer().compactDisplayTitle ?? "").prefixWithDots(30)
        
        self.nameLayout = .init(.initialize(string: peerName, color: TelegramThemeHooks.shared.darkAppearance().colors.text, font: .medium(.text)))
        self.nameLayout.measure(width: .greatestFiniteMagnitude)
                
//        let text = message.text.makeAttributeString().mutableCopy() as! NSMutableAttributedString
//        text.addAttribute(.foregroundColor, value: GroupCallTheme.titleColor, range: text.range)
//        text.addAttribute(.font, value: NSFont.normal(.text), range: text.range)
        
        self.textLayout = .init(textAttr , cutout: .init(topLeft: NSMakeSize(nameLayout.layoutSize.width + 5, 20)))
        super.init(initialSize, stableId: stableId)
        
        _ = makeSize(initialSize.width)
        
    }
    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        return .single(arguments.contextMenuItems(self.message))
    }

    override var accessibilityLabel: String? {
        return nameLayout.attributedString.string
    }

    override func makeSize(_ width: CGFloat = CGFloat.greatestFiniteMagnitude, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.textLayout.measure(width: 240)
        return true
    }
    
    override func viewClass() -> AnyClass {
        return MessageItemView.self
    }
    
    override var height: CGFloat {
        return max(40, 18 + self.textLayout.layoutSize.height)
    }
}

private final class MessageItemView: TableRowView {

    private let containerView = VisualEffect()
    private let dataView = View()
    private let containerBackground = View()
    private var glassBackgroundView: NSView?
    let textView = InteractiveTextView()
    private let avatarView = AvatarControl(font: .avatar(13))

    private let nameView = TextView()

    let overlay = View()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        overlay.isEventLess = true


        avatarView.set(handler: { [weak self] _ in
            if let event = NSApp.currentEvent {
                self?.showContextMenu(event)
            }
        }, for: .Click)


        textView.textView.userInteractionEnabled = true

        self.layer?.masksToBounds = false
        overlay.layer?.masksToBounds = false


        nameView.userInteractionEnabled = false
        nameView.isSelectable = false

        dataView.addSubview(nameView)
        dataView.addSubview(textView)
        dataView.addSubview(avatarView)


        avatarView.setFrameSize(NSMakeSize(26, 26))


        addSubview(containerView)
        containerView.addSubview(containerBackground)
        containerView.addSubview(dataView)
        self.addSubview(overlay)

        containerBackground.backgroundColor = .clear
        let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 15, hasShadow: true, hasBorder: true, forceAppearance: .forceDark)
        containerView.addSubview(glass, positioned: .below, relativeTo: containerBackground)
        glassBackgroundView = glass
    }
    
    var nameOffset: CGFloat {
        return nameView.frame.width - 10
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func onRemove(_ animation: NSTableView.AnimationOptions) {
        if animation.contains(.effectFade) {
            self.containerView.layer?.animateScaleSpring(from: 1, to: 0.1, duration: 0.6, removeOnCompletion: false, bounce: false)
        }
    }
    
    override func onInsert(_ animation: NSTableView.AnimationOptions, appearAnimated: Bool) {
        if animation.contains(.effectFade) {
            self.containerView.layer?.animateScaleSpring(from: 0.1, to: 1.0, duration: 0.6, removeOnCompletion: false, bounce: false)
        }
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        
        let previous = self.item as? MessageItemRow
        
        super.set(item: item, animated: animated)
        
        guard let item = item as? MessageItemRow else {
            return
        }
        textView.set(text: item.textLayout, context: item.arguments.context,insetEmoji: item.inset)
        avatarView.setPeer(account: item.arguments.context.account, peer: item.message.author?._asPeer())
        nameView.update(item.nameLayout)
        
        containerView.layer?.cornerRadius = 15
        containerBackground.layer?.cornerRadius = 15
        layout()

        
        if previous?.stableId != item.stableId, animated {
            containerView.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
        }
        
    }
//
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        
        transition.updateFrame(view: containerView, frame: focus(NSMakeSize(2 + avatarView.frame.width + 8 + textView.frame.width + 8, size.height - 10)))

        transition.updateFrame(view: dataView, frame: containerView.bounds)
        transition.updateFrame(view: overlay, frame: containerView.frame)
        transition.updateFrame(view: containerBackground, frame: containerView.bounds)
        if let glassBackgroundView {
            transition.updateFrame(view: glassBackgroundView, frame: containerView.bounds)
            (glassBackgroundView as? LiquidGlassView)?.updateLayout(size: containerView.bounds.size, transition: transition)
        }
        
        
        
        transition.updateFrame(view: textView, frame: textView.centerFrameY(x: avatarView.frame.maxX + 8))
        
        if size.height == 40 {
            transition.updateFrame(view: avatarView, frame: CGRect(origin: NSMakePoint(2, 2), size: avatarView.frame.size))
        } else {
            transition.updateFrame(view: avatarView, frame: CGRect(origin: NSMakePoint(2, textView.frame.minY), size: avatarView.frame.size))
        }

        transition.updateFrame(view: nameView, frame: CGRect(origin: NSMakePoint(avatarView.frame.maxX + 8, textView.frame.minY), size: nameView.frame.size))
        
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
}


public final class GroupCallMessagesView : View {
    private let tableView: TableView

    private var messages: [Entry] = []
    private var arguments: GroupCallUIArguments?
    
    public var controlsRect: NSRect = .zero
    
    public init(frame frameRect: NSRect, controlsRect: CGRect) {
        self.controlsRect = controlsRect
        self.tableView = TableView(frame: NSMakeRect(0, 0, 320, frameRect.height) , isFlipped: false)
        super.init(frame: frameRect)
        
        isEventLess = true
        
        addSubview(tableView)
        
        tableView.layer?.masksToBounds = false
        tableView.contentView.layer?.masksToBounds = false
        tableView.documentView?.layer?.masksToBounds = false
        
        tableView.getBackgroundColor = {
            .clear
        }
        
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    
    public func update(state: GroupCallUIState.Messages, callState: GroupCallUIState, arguments: GroupCallUIArguments, animated: Bool) {
        
        
        
        self.arguments = arguments
        
        guard let context = arguments.getContext() else {
            return
        }
        
        let messageArguments = Arguments(context: context, contextMenuItems: { message in
            if let participant = callState.memberDatas.first(where: { $0.peer.id == message.author?.id }) {
                return arguments.contextMenuItems(participant)
            } else {
                return []
            }
        })
        
        let size = self.frame.size
        
        var index: Int32 = 0
        let getIndex:()->Int32 = {
            index += 1
            return index
        }
        
        let entries = state.messages.map { Entry(index: getIndex(), message: $0) }
        
        let (deleted,inserted,updated) = proccessEntries(messages, right: entries, { entry -> TableRowItem in
            return MessageItemRow(size, stableId: entry.stableId, message: entry.message, reactions: state.reactions, arguments: messageArguments)
        })
        
        let transition = TableUpdateTransition(deleted: deleted, inserted: inserted, updated:updated, animated: animated, state: .none(nil), grouping: false, animateVisibleOnly: false, searchState: nil)
        
        self.messages = entries
        
        tableView.merge(with: transition, appearAnimated: true)
        
        if inserted.count == 1, let action = state.nextMessageAction {
            arguments.resetNextMessageRect()
            
            let getColors:(TelegramMediaFile)->[LottieColor] = { file in
                var colors: [LottieColor] = []
                if isDefaultStatusesPackId(file.emojiReference) || file.isCustomTemplateEmoji {
                    colors.append(.init(keyPath: "", color: theme.colors.accent))
                }
                return colors
            }
            
            if let fileId = action.fileId, let fromRect = action.rect, let window = _window {
                
                
                if let view = (inserted[0].1.view as? MessageItemView) {
                    
                    let control = view.textView

                    tableView.tile()
                    
                    let layer = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId, file: action.file, emoji: ""), size: NSMakeSize(26, 26), getColors: getColors)
                    
                    control.isHidden = true
                    
                    let toRect = control.convert(control.frame.size.bounds, to: nil)
    
                    let from = fromRect.origin.offsetBy(dx: fromRect.width / 2, dy: fromRect.height / 2)
                    let to = toRect.origin.offsetBy(dx: toRect.width / 2 + view.nameOffset, dy: toRect.height / 2)
                    
                    
                    let play:(MessageItemView, TelegramMediaFile)->Void = { container, icon in
                        
                       
                        
                        if let effectFileId = action.effectFileId {
                            let player = CustomReactionEffectView(frame: NSMakeSize(160, 160).bounds, context: context, fileId: effectFileId)
                            player.isEventLess = true
                            player.triggerOnFinish = { [weak player] in
                                player?.removeFromSuperview()
                               // finish()
                            }
                            let rect = CGRect(origin: CGPoint(x: (container.overlay.frame.width - player.frame.width / 2 - 14), y: (container.overlay.frame.height - player.frame.height) / 2), size: player.frame.size)
                            player.frame = rect
                            container.overlay.addSubview(player)
                            
                        } else if let effectFile = action.effectFile {
                            let player = InlineStickerItemLayer(account: context.account, file: effectFile, size: NSMakeSize(80, 80), playPolicy: .playCount(1))
                            player.isPlayable = true
                            player.superview = container.overlay
                            player.frame = NSMakeRect((container.overlay.frame.width - player.frame.width / 2 - 14), (container.overlay.frame.height - player.frame.height) / 2, player.frame.width, player.frame.height)
                            
                            container.overlay.layer?.addSublayer(player)
                            player.triggerOnState = (.finished, { [weak player] state in
                                player?.removeFromSuperlayer()
                                //finish()
                            })
                        }
                    }
    
                    let completed: (Bool)->Void = { [weak view, weak control] _ in
                        control?.isHidden = false
                        if let file = action.file, let view {
                            play(view, file)
                        }
                    }
                    
                    parabollicReactionAnimation(layer, fromPoint: from, toPoint: to, window: window, completion: completed)
                }

                
            }
           
        }
        
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        let tableSize = NSMakeSize(360, min(size.height - controlsRect.minY - 75, tableView.listHeight))
        var tableRect = focus(tableSize)
        tableRect.origin.x = controlsRect.minX
        tableRect.origin.y = (controlsRect.minY + 110) - tableRect.height
        transition.updateFrame(view: tableView, frame: tableRect)
        
    }
    
}
