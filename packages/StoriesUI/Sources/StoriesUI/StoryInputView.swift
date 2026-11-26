import Cocoa
import TGUIKit
import TGModernGrowingTextView
import SwiftSignalKit
import Postbox
import TelegramCore
import ColorPalette
import InputView
import TelegramMedia
import TelegramMediaResources
import FoundationUtils
import ChatUI
import InAppSettings
import InputTextView
import LocalAnimations
import Localization
import SceneEffects
import ShortPeerRow
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import InlineStickerLayer

extension MessageReaction.Reaction {
    static var defaultStoryLike: MessageReaction.Reaction {
        return .builtin("❤️".withoutColorizer)
    }
}

private let placeholderColor = NSColor.white.withAlphaComponent(0.33)

enum StoryInputState : Equatable {
    case focus
    case none
}

private var send_image: CGImage {
    if System.liquidGlass {
        return TelegramThemeHooks.shared.image(.iconSendMessageSmall).precomposed(darkAppearance.colors.underSelectedColor)
    }
    return TelegramThemeHooks.shared.image(.iconSendMessage).precomposed(darkAppearance.colors.accent)
}
private var send_image_active: CGImage {
    if System.liquidGlass {
        return TelegramThemeHooks.shared.image(.iconSendMessageSmall).precomposed(darkAppearance.colors.underSelectedColor)
    }
    return TelegramThemeHooks.shared.image(.iconSendMessage).precomposed(darkAppearance.colors.accent.darker())
}

private let like_image: CGImage  = TelegramThemeHooks.shared.image(.iconStoryLike).precomposed(NSColor(0xffffff, 1))
private var like_image_active: CGImage  = TelegramThemeHooks.shared.image(.iconStoryLike).precomposed(NSColor(0xffffff, 0.8))


private let attach_image: CGImage  = TelegramThemeHooks.shared.image(.iconChatAttach).precomposed(NSColor(0xffffff, 1))
private let attach_image_active: CGImage  = TelegramThemeHooks.shared.image(.iconChatAttach).precomposed(NSColor(0xffffff, 0.8))

private let voice_image: CGImage  = TelegramThemeHooks.shared.image(.iconRecordVoice).precomposed(NSColor(0xffffff, 1))
private let voice_image_active: CGImage  = TelegramThemeHooks.shared.image(.iconRecordVoice).precomposed(NSColor(0xffffff, 0.8))

private let video_message_image: CGImage  = TelegramThemeHooks.shared.image(.iconRecordVideoMessage).precomposed(NSColor(0xffffff, 1))
private let video_message_image_active: CGImage  = TelegramThemeHooks.shared.image(.iconRecordVideoMessage).precomposed(NSColor(0xffffff, 0.8))


private let stickers_image: CGImage  = TelegramThemeHooks.shared.image(.iconChatEntertainmentSticker).precomposed(NSColor(0xffffff, 1))
private var stickers_image_active: CGImage  = TelegramThemeHooks.shared.image(.iconChatEntertainmentSticker).precomposed(NSColor(0xffffff, 0.8))

private let emoji_image: CGImage  = TelegramThemeHooks.shared.image(.iconEntertainments).precomposed(NSColor(0xffffff, 1))
private var emoji_image_active: CGImage  = TelegramThemeHooks.shared.image(.iconEntertainments).precomposed(NSColor(0xffffff, 0.8))



private let share_image: CGImage  = TelegramThemeHooks.shared.image(.iconStoryShare).precomposed(NSColor(0xffffff, 1))
private let share_image_active: CGImage  = TelegramThemeHooks.shared.image(.iconStoryShare).precomposed(NSColor(0xffffff, 0.8))


private let setprice_image: CGImage  = TelegramThemeHooks.shared.image(.iconInputSuggestPost).precomposed(NSColor(0xffffff, 1))
private let setprice_image_active: CGImage  = TelegramThemeHooks.shared.image(.iconInputSuggestPost).precomposed(NSColor(0xffffff, 0.8))


private func generateStarsTextIcon(text: String, bgColor: NSColor, textColor: NSColor, fontSize: CGFloat = .small, round: Bool = false, borderColor: NSColor? = nil, small: Bool = false) -> CGImage {
    
    let textNode = TextNode.layoutText(.initialize(string: text, color: textColor, font: .avatar(fontSize)), nil, 2, .end, NSMakeSize(.greatestFiniteMagnitude, 20), nil, false, .center)
    var size = textNode.0.size
    
    let icon = TelegramThemeHooks.shared.image(.starSmall).precomposed(textColor, flipVertical: true)

    if !small {
        size.width = max(40, (size.width + 19 + icon.backingSize.width))
        size.height = 40
    } else {
        size.width = (size.width + 14 + icon.backingSize.width)
        size.height = 20
    }
    return generateImage(size, rotatedContext: { size, ctx in
        let rect = NSMakeRect(0, 0, size.width, size.height)
        ctx.clear(rect)
        
        ctx.round(size, round ? size.height / 2 : .cornerRadius)
        ctx.setFillColor(bgColor.cgColor)
        ctx.fill(rect)
        
        
        let iconRect = rect.focusY(icon.backingSize, x: small ? 5 : 7)
        ctx.draw(icon, in: iconRect)
        
        var textRect = rect.focusY(textNode.0.size, x: iconRect.maxX + 2)
        textRect.origin.y -= 1
        textNode.1.draw(textRect, in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
    })!
}

final class StoryLikeActionButton: Control {
    private let control: ImageButton = ImageButton(frame: NSMakeRect(0, 0, 50, 50))
    private var myReaction: MessageReaction.Reaction?
    private var story: StoryContentItem?
    private var state: StoryInteraction.State?
    private var reaction: InlineStickerItemLayer?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(control)
        self.layer?.masksToBounds = false
        control.userInteractionEnabled = false
        control.isAccessibilityDecorative = true
        setAccessibilityLabel(strings().voiceOverCommonLike)
    }
    
    override func stateDidUpdate(_ state: ControlState) {
        control.controlState = state
    }
    
    override var isSelected: Bool {
        didSet {
            control.isSelected = isSelected
        }
    }
    
    func react(_ reaction: StoryReactionAction, state: StoryInteraction.State, context: any AccountContextProtocol) {
        self.myReaction = reaction.item.reaction
        if let view = self.reaction {
            performSublayerRemoval(view, animated: true, scale: true)
        }
        let layer: InlineStickerItemLayer? = makeView(reaction.item.reaction, state: state, context: context, appear: true)
        if let layer = layer {
            layer.animateAlpha(from: 0, to: 1, duration: 0.2)
            layer.animateScale(from: 0.1, to: 1, duration: 0.2)

            layer.isPlayable = true
        }
        control.isHidden = layer != nil
        self.reaction = layer
        
        
        playReaction(reaction, context: context)
    }
    
    
    func playReaction(_ reaction: StoryReactionAction, context: any AccountContextProtocol) -> Void {
         
                  
         var file: TelegramMediaFile?
         var effectFileId: Int64?
         var effectFile: TelegramMediaFile?
         switch reaction.item {
         case let .custom(fileId, f):
             file = f
             effectFileId = fileId
         case let .builtin(string):
             let reaction = context.reactions.available?.reactions.first(where: { $0.value.string.withoutColorizer == string.withoutColorizer })
             file = reaction?.selectAnimation._parse()
             effectFile = reaction?.aroundAnimation?._parse()
         case .stars:
             break
         }
         
         guard let icon = file else {
             return
         }
                
                 
         let finish:()->Void = {
             
         }
                  
         let play:(NSView, TelegramMediaFile)->Void = { container, icon in
             
             if let effectFileId = effectFileId {
                 let player = CustomReactionEffectView(frame: NSMakeSize(80, 80).bounds, context: context, fileId: effectFileId)
                 player.isEventLess = true
                 player.triggerOnFinish = { [weak player] in
                     player?.removeFromSuperview()
                     finish()
                 }
                 let rect = CGRect(origin: CGPoint(x: (container.frame.width - player.frame.width) / 2, y: (container.frame.height - player.frame.height) / 2), size: player.frame.size)
                 player.frame = rect
                 container.addSubview(player)
                 
             } else if let effectFile = effectFile {
                 let player = InlineStickerItemLayer(account: context.account, file: effectFile, size: NSMakeSize(80, 80), playPolicy: .playCount(1))
                 player.isPlayable = true
                 player.superview = container
                 player.frame = NSMakeRect((container.frame.width - player.frame.width) / 2, (container.frame.height - player.frame.height) / 2, player.frame.width, player.frame.height)
                 
                 container.layer?.addSublayer(player)
                 player.triggerOnState = (.finished, { [weak player] state in
                     player?.removeFromSuperlayer()
                     finish()
                 })
             }
         }
         
         let layer = InlineStickerItemLayer(account: context.account, file: icon, size: NSMakeSize(25, 25))

         let completed: (Bool)->Void = { [weak self]  _ in
             DispatchQueue.main.async {
                 if let container = self {
                     play(container, icon)
                 }
             }
         }
         if let fromRect = reaction.fromRect {
             let toRect = self.convert(self.frame.size.bounds, to: nil)
             
             let from = fromRect.origin.offsetBy(dx: fromRect.width / 2, dy: fromRect.height / 2)
             let to = toRect.origin.offsetBy(dx: toRect.width / 2, dy: toRect.height / 2)
             parabollicReactionAnimation(layer, fromPoint: from, toPoint: to, window: context.window, completion: completed)
         } else {
             play(self, icon)
         }
     }
     
    
    
    private func makeView(_ reaction: MessageReaction.Reaction, state: StoryInteraction.State, context: any AccountContextProtocol, appear: Bool = false) -> InlineStickerItemLayer? {
        let layer: InlineStickerItemLayer?
        var size = NSMakeSize(25, 25)
        switch reaction {
        case let .custom(fileId):
            layer = .init(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId, file: nil, emoji: ""), size: size, playPolicy: .onceEnd)
        case .builtin:
            if reaction == .defaultStoryLike {
                size = NSMakeSize(30, 30)
                let file = TelegramMediaFile(fileId: .init(namespace: 0, id: 0), partialReference: nil, resource: LocalBundleResource(name: "Icon_StoryLike_Holder", ext: "", color: darkAppearance.colors.redUI), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "bundle/jpeg", size: nil, attributes: [], alternativeRepresentations: [])
                layer = InlineStickerItemLayer(account: context.account, file: file, size: size, playPolicy: .onceEnd, textColor: NSColor(0xffffff))
            } else {
                if let animation = state.reactions?.reactions.first(where: { $0.value == reaction }) {
                    let file = appear ? animation.activateAnimation._parse() : animation.selectAnimation._parse()
                    layer = InlineStickerItemLayer(account: context.account, file: file, size: size, playPolicy: .onceEnd)
                } else {
                    layer = nil
                }
            }
        case .stars:
            layer = nil
        }
        if let layer = layer {
            layer.frame = focus(size)
            self.layer?.addSublayer(layer)
            layer.isPlayable = false
        }
        return layer
    }
    
    func update(_ story: StoryContentItem, state: StoryInteraction.State, context: any AccountContextProtocol, animated: Bool) {
        self.story = story
        self.state = state
        guard let state = self.state else {
            return
        }
        
        if let reaction = story.storyItem.myReaction, !state.wideInput {
            if self.myReaction != reaction {
                if let view = self.reaction {
                    performSublayerRemoval(view, animated: animated, scale: true)
                }
                let layer: InlineStickerItemLayer? = makeView(reaction, state: state, context: context)
                
                if let layer = layer {
                    if animated {
                        layer.animateAlpha(from: 0, to: 1, duration: 0.2)
                        layer.animateScale(from: 0.1, to: 1, duration: 0.35, timingFunction: .spring)
                    }
                }
                self.reaction = layer
            }
            self.myReaction = story.storyItem.myReaction
        } else if let view = reaction {
            performSublayerRemoval(view, animated: animated)
            self.reaction = nil
            self.myReaction = nil
        }
        
        if state.wideInput {
            control.set(image: state.emojiState == .emoji ? emoji_image : stickers_image, for: .Normal)
            control.set(image: state.emojiState == .emoji ? emoji_image_active : stickers_image_active, for: .Highlight)
        } else {
            control.set(image: like_image, for: .Normal)
            control.set(image: like_image_active, for: .Highlight)
        }
        control.isHidden = self.reaction != nil
        
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class StoryReplyActionButton : View {
    
    enum State : Equatable {
        case empty(isVoice: Bool)
        case text
        case share
        case emoji
        case setprice
        case starPrice(Int64)
        case starReactions(Int64, Bool, Int64?)
        
        func isSameType(as other: State?) -> Bool {
            switch (self, other) {
            case (.empty, .empty),
                 (.text, .text),
                 (.share, .share),
                 (.emoji, .emoji),
                 (.setprice, .setprice),
                 (.starPrice, .starPrice),
                 (.starReactions, .starReactions):
                return true
            default:
                return false
            }
        }
    }
    
    private var current: Control?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.masksToBounds = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    private var state: State?
    private var story: StoryContentItem?
    
    func update(state: State, arguments: StoryArguments, story: StoryContentItem?, animated: Bool) {
        let previous = self.state
        self.story = story
        
        var size: NSSize = NSMakeSize(self.current?.frame.width ?? 46, frame.height)
        
        let animated = animated// && previous != state && previous?.isSameType(as: state) == false
        
        if previous != state {
            
            size = NSMakeSize(46, frame.height)
            
            if let view = self.current, !state.isSameType(as: previous) {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.current = nil
            }

            let sendPaidMessageStars = arguments.chatInteraction.presentation.sendPaidMessageStars

            if let sendPaidMessageStars, state == .text {
                let current: StarsSendActionView
                current = StarsSendActionView(frame: .zero)
                self.current = current
                current.update(price: sendPaidMessageStars.value, context: arguments.context, animated: animated)
                size = NSMakeSize(current.frame.width, size.height)
                
                addSubview(current)
                current.centerY(x: 0)
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    current.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2, bounce: false)
                }
                
            } else {
                
                let current: ImageButton = self.current as? ImageButton ?? ImageButton()
                current.autohighlight = false
                current.animates = false
                current.scaleOnClick = true
                switch state {
                case .text:
                    current.set(image: send_image, for: .Normal)
                    current.set(image: send_image_active, for: .Highlight)
                    if System.liquidGlass {
                        current.setGlassEffect(size: NSMakeSize(26, 26), tintColor: darkAppearance.colors.accent)
                        current.sizeToFit(.zero, NSMakeSize(26, 26), thatFit: true)
                    }
                case let .empty(isVoice: isVoice):
                    current.set(image: isVoice ? voice_image : video_message_image, for: .Normal)
                    current.set(image: isVoice ? voice_image_active : video_message_image_active, for: .Highlight)
                case .share:
                    current.set(image: share_image, for: .Normal)
                    current.set(image: share_image_active, for: .Highlight)
                case .setprice:
                    current.set(image: setprice_image, for: .Normal)
                    current.set(image: setprice_image_active, for: .Highlight)
                case .emoji:
                    current.set(image: emoji_image, for: .Normal)
                    current.set(image: emoji_image_active, for: .Highlight)
                case let .starPrice(value):
                    let color = getStarAmountColorMapping(value: value)
                    let badge = generateStarsTextIcon(text: "\(value.prettyNumber)", bgColor: color, textColor: .white, fontSize: .text, round: true)
                    current.set(image: badge, for: .Normal)
                    size = NSMakeSize(badge.backingSize.width, size.height)
                case let .starReactions(value, hasPending, _):
                    var badge: CGImage
                    let bgColor = darkAppearance.colors.grayBackground.withAlphaComponent(0.8)
                    if value > 0 {
                        badge = generateImage(NSMakeSize(40, 40), contextGenerator: { size, ctx in
                            ctx.clear(size.bounds)
                            ctx.round(size, size.height / 2)
                            ctx.setFillColor((hasPending ? NSColor(0xFFAC04) : bgColor).cgColor)
                            ctx.fill(size.bounds)
                            let star = TelegramThemeHooks.shared.image(.iconPeerPremium).precomposed(.white)
                            ctx.draw(star, in: size.bounds.focus(star.backingSize))
                        })!
                        
                        let myStars = generateStarsTextIcon(text: "\(value.prettyNumber)", bgColor: hasPending ? NSColor(0xFFAC04) : bgColor, textColor: .white, fontSize: .text, round: true, small: true)
                        
                        var size = badge.backingSize
                        size.height += 10
                        
                        var myStarsRect = myStars.backingSize.bounds
                        myStarsRect.size.width *= 0.8
                        myStarsRect.size.height *= 0.8

                        
                        size.width = max(myStarsRect.width, size.width)
                        badge = generateImage(size, contextGenerator: { size, ctx in
                            ctx.clear(size.bounds)
                            
                            ctx.draw(badge, in: size.bounds.focus(badge.backingSize))
                            

                            myStarsRect.origin.x = (size.width - myStarsRect.width) / 2
                            myStarsRect.origin.y = badge.backingSize.height - myStarsRect.height / 2

                            
                            ctx.saveGState()
                            
                            let ellipseRect = myStarsRect.insetBy(dx: -1, dy: -1)
                            let path = CGMutablePath()
                            path.addRoundedRect(in: ellipseRect, cornerWidth: ellipseRect.height / 2, cornerHeight: ellipseRect.height / 2)
                            ctx.addPath(path)
                            ctx.closePath()
                            ctx.clip()
                            ctx.clear(ellipseRect)
                            ctx.restoreGState()
                            

                            
                            ctx.draw(myStars, in: myStarsRect)
                            
                        })!
                    } else {
                        badge = generateImage(NSMakeSize(40, 40), contextGenerator: { size, ctx in
                            ctx.clear(size.bounds)
                            ctx.round(size, size.height / 2)
                            ctx.setFillColor(bgColor.cgColor)
                            ctx.fill(size.bounds)
                            let star = TelegramThemeHooks.shared.image(.iconPeerPremium).precomposed(.white)
                            ctx.draw(star, in: size.bounds.focus(star.backingSize))
                        })!
                    }
                    current.set(image: badge, for: .Normal)
                    size = NSMakeSize(badge.backingSize.width, size.height)

                }
                
                switch state {
                case .text:
                    current.setAccessibilityLabel(strings().voiceOverMessageContextSend)
                case let .empty(isVoice):
                    current.setAccessibilityLabel(isVoice ? strings().voiceOverChatRecordModeVoiceMessage : strings().voiceOverChatRecordModeVideoMessage)
                case .share:
                    current.setAccessibilityLabel(strings().voiceOverCommonShare)
                case .setprice:
                    current.setAccessibilityLabel(strings().voiceOverCommonSetPrice)
                case .emoji:
                    current.setAccessibilityLabel(strings().voiceOverCommonEmoji)
                case .starPrice, .starReactions:
                    current.setAccessibilityLabel(strings().voiceOverCommonStars)
                }
                
                self.current = current
                current.frame = size.bounds
                current.layer?.masksToBounds = false
                addSubview(current, positioned: .below, relativeTo: self.effetView)
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    current.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2, bounce: false)
                }
            }
            
        }
        
        setFrameSize(size)
                
        self.state = state

        guard let current = self.current else {
            return
        }
        current.removeAllHandlers()
        
        if state == .share, story?.storyItem.isForwardingDisabled == true {
            if story?.canCopyLink == false {
                current.appTooltip = strings().storyInputCantShare
            } else {
                current.appTooltip = nil
                current.contextMenu = { [arguments, story] in
                    let menu = ContextMenu()
                    menu.addItem(ContextMenuItem(strings().modalCopyLink, handler: { [weak arguments, weak story] in
                        if let story = story {
                            arguments?.copyLink(story)
                        }
                    }, itemImage: MenuAnimation.menu_copy_link.value))
                    return menu
                }
            }
            
        } else {
            current.appTooltip = nil
            current.contextMenu = nil
                        
            if case .starPrice = state {
                current.contextMenu = { [weak arguments, weak self] in
                    let menu = ContextMenu(presentation: .current(darkPalette))
                    if let story = self?.story, let peerId = story.peerId {
                        menu.addItem(ContextMenuItem(strings().storyLiveStreamInputSend, handler: {
                            arguments?.sendMessage(peerId, story.storyItem.id)
                        }, itemImage: MenuAnimation.menu_send_now.value))
                    }
                    menu.addItem(ContextSeparatorItem())
                    menu.addItem(ContextMenuItem(strings().storyLiveStreamInputEdit, handler: {
                        arguments?.setMessagePrice()
                    }, itemImage: MenuAnimation.menu_change_colors.value))

                    menu.addItem(ContextMenuItem(strings().storyLiveStreamInputReset, handler: {
                        arguments?.resetMessagePrice()
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_reset.value))
                    return menu
                }
            } else {
                current.set(handler: { [weak arguments, weak self] control in
                    if state == .text {
                        if let story = self?.story, let peerId = story.peerId {
                            arguments?.sendMessage(peerId, story.storyItem.id)
                        }
                    } else if state == .share {
                        if let story = self?.story {
                            arguments?.share(story)
                        }
                    } else if case .starReactions = state {
                        arguments?.reactStars(true)
                        self?.playEffect()
                    } else if state == .setprice {
                        arguments?.setMessagePrice()
                    } else if state == .emoji {
                        arguments?.showEmojiPanel(control)
                    } else {
                        arguments?.toggleRecordType()
                    }
                }, for: .Click)
                
                if case .starReactions = state {
                    current.set(handler: { [weak arguments] _ in
                        arguments?.reactStars(false)
                    }, for: .RightDown)
                    
                    current.set(handler: { [weak arguments] _ in
                        arguments?.reactStars(false)
                    }, for: .LongMouseDown)
                }
                
                
                current.contextMenu = nil
            }
            
            if case .empty = state {
                current.set(handler: { [weak arguments] _ in
                    if state == .text {
                    } else {
                        arguments?.startRecording(false)
                    }
                }, for: .LongMouseDown)
            }
        }
    }
    
    private let effectDisposable = MetaDisposable()
    private var effetView: LottiePlayerView? = nil
    
    deinit {
        effectDisposable.dispose()
    }
    
    
    func playEffect() {
        
        guard let current else {
            return
        }
        
        self.layer?.masksToBounds = false
        
        let size: NSSize = current.frame.insetBy(dx: -5, dy: -5).size
        
        let file = LocalAnimatedSticker.premium_reaction_effect_5.file
        
        if TelegramUtilsHooks.shared.isLite(.emoji_effects) {
            return
        }

        let fileSignal: Signal<MediaResourceData, NoError>
        if let resource = file.resource as? LocalBundleResource, let path = resource.path {
            fileSignal = .single(MediaResourceData(path: path, offset: 0, size: 0, complete: true))
        } else {
            fileSignal = .complete()
        }
        let signal: Signal<LottieAnimation?, NoError> = fileSignal
        |> filter { $0.complete }
        |> map { value -> Data? in
            return try? Data(contentsOf: URL(fileURLWithPath: value.path))
        }
        |> filter {
            $0 != nil
        }
        |> map {
            $0!
        }
        |> take(1)
        |> map { data in
            return LottieAnimation(compressed: data, key: .init(key: .bundle("_live_stream_effect"), size: size), cachePurpose: .none, playPolicy: .once, metalSupport: false)
        } |> deliverOnMainQueue

        self.effectDisposable.set(signal.start(next: { [weak self] animation in
            if let animation = animation {
                self?.runAnimationEffect(animation)
            }
        }))
        
    }
    
    private func runAnimationEffect(_ animation: LottieAnimation) {
        
        guard let current else {
            return
        }
        
        let point: NSPoint
        point = current.frame.origin.offsetBy(dx: -2, dy: -2)
        
        let player = LottiePlayerView(frame: CGRect(origin: point, size: animation.size))

        
        
        player.set(animation, reset: true)
        
        self.effetView = player
        
        player.isEventLess = true
        player.userInteractionEnabled = false
        
        addSubview(player)
        
        player.center()
        
        animation.triggerOn = (LottiePlayerTriggerFrame.last, { [weak self, weak player] in
            if let player = player {
                performSubviewRemoval(player, animated: false)
                if self?.effetView == player {
                    self?.effetView = nil
                }
            }
        }, {})
    }
}

final class StoryInputView : Control, StoryInput {
    
    private let rtfAttachmentsDisposable = MetaDisposable()
    private var recordingView: StoryRecordingView?
    private var story: StoryContentItem?
    

    func updateInputText(_ state: ChatTextInputState, prevState: ChatTextInputState, animated: Bool) {
        self.textView.set(state)
        if prevState.inputText.isEmpty {
            self.textView.scrollToCursor()
        }
    }
    
    func updateState(_ state: StoryInteraction.State, animated: Bool) {
        guard let arguments = self.arguments else {
            return
        }
        self.action.update(state: !isFirstResponder && self.story?.sharable == true ? .share : textView.string().isEmpty ? .empty(isVoice: state.recordType == .voice) : .text, arguments: arguments, story: self.story, animated: animated)
        
        self.updateInputState(animated: animated)
        self.updateRecoringState(state, animated: animated)
        
        if let story = self.story {
            self.likeAction.update(story, state: state, context: arguments.context, animated: animated)
        }
   
        self.updatePlaceholder()
    }
    
    private let stealthDisposable = MetaDisposable()
    private func updatePlaceholder() {
        guard let arguments = self.arguments else {
            return
        }
        let text: String
        if let slowmode = arguments.interaction.presentation.slowMode, let timeout = slowmode.timeout {
            let timer = smartTimeleftText(Int(timeout))
            text = strings().storySlowModePlaceholder(timer)
        } else if let cooldown = arguments.interaction.presentation.stealthMode.activeUntilTimestamp {
            stealthDisposable.set(delaySignal(0.3).start(completed: { [weak self] in
                self?.updatePlaceholder()
            }))
            
            let timer = smartTimeleftText(Int(cooldown - arguments.context.timestamp))
            text = strings().storyStealthModePlaceholder(timer)
        } else {
            stealthDisposable.set(nil)
            if arguments.interaction.presentation.entryId?.namespace == Namespaces.Peer.CloudChannel {
                text = strings().storyInputGroupPlaceholder
            } else {
                text = strings().storyInputPlaceholder
            }
        }
        textView.placeholder = text
    }
    
    private func updateRecoringState(_ state: StoryInteraction.State, animated: Bool) {
        updateStoryRecordingView(state, arguments: self.arguments, animated: animated, in: self, recordingView: &self.recordingView)
    }
    
    func update(_ story: StoryContentItem, animated: Bool) {
        self.story = story
        guard let arguments = self.arguments else {
            return
        }
        self.likeAction.update(story, state: arguments.interaction.presentation, context: arguments.context, animated: animated)
    }
    

    
    private func updateInputSize(size: NSSize, animated: Bool) {
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        guard let window = self.window else {
            return
        }
                
        let wSize = NSMakeSize(window.contentView!.frame.width - 100, window.contentView!.frame.height - 110)
        let aspect = StoryLayoutView.size.aspectFitted(wSize)
        
        var size = size
        if self.inputState == .focus, let inputContextSize = self.inputContextSize {
            size.height += inputContextSize.height
        }

        transition.updateFrame(view: self, frame: CGRect(origin: CGPoint(x: 0, y: aspect.height + 10 - size.height + 50), size: size))
        self.updateLayout(size: size, transition: transition)

    }
    
    func textViewEnterPressed(_ event: NSEvent) -> Bool {
        if FastSettings.checkSendingAbility(for: event) {
            let text = textView.string().trimmed
            if !text.isEmpty {
                if let story = self.story, let peerId = story.peerId {
                    self.arguments?.sendMessage(peerId, story.storyItem.id)
                }
            }
            return true
        }
        return false

    }
    

    
    func processPaste(_ pasteboard: NSPasteboard) -> Bool {
        if let window = _window, let arguments = self.arguments {
            
            _ = arguments.context
            let chatInteraction = arguments.chatInteraction
            
            let result = InputPasteboardParser.proccess(pasteboard: pasteboard, chatInteraction: chatInteraction, window: window)
            if result {
                if let data = pasteboard.data(forType: .kInApp) {
                    let decoder = AdaptedPostboxDecoder()
                    if let decoded = try? decoder.decode(ChatTextInputState.self, from: data) {
                        let state = decoded.unique(isPremium: chatInteraction.interactionContext.isPremium)
                        chatInteraction.appendText(state.attributedString())
                        return true
                    }
                } else if let data = pasteboard.data(forType: .rtf) {
                    if let attributed = (try? NSAttributedString(data: data, options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtfd], documentAttributes: nil)) ?? (try? NSAttributedString(data: data, options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil))  {
                        
                        let (attributed, attachments) = attributed.applyRtf()
                        
                        if !attachments.isEmpty {
                            rtfAttachmentsDisposable.set((prepareTextAttachments(attachments) |> deliverOnMainQueue).start(next: { [weak chatInteraction] urls in
                                if !urls.isEmpty {
                                    chatInteraction?.showPreviewSender(urls, true, attributed)
                                }
                            }))
                        } else {
                            chatInteraction.appendText(attributed)
                        }
                        return true
                    }
                }
            }
            return !result
        }
        return false
    }
    
    func maxCharactersLimit(_ textView: TGModernGrowingTextView!) -> Int32 {
        return 255
    }
    
    func textViewSize(_ width: CGFloat) -> (NSSize, CGFloat) {
        let w = width
        let height = self.textView.height(for: w)
        let singleLine = textView.inputView.textContainer?.maximumNumberOfLines == 1
        return (NSMakeSize(w, singleLine ? 50 : min(max(height, textView.min_height), textView.max_height) + 16), singleLine ? 26 : height)
    }
    
    
    func textViewIsTypingEnabled() -> Bool {
        return self.arguments?.interaction.presentation.inputRecording == nil
    }
    
    func responderDidUpdate() {
        
        self.inputState = self.isFirstResponder ? .focus : .none
        self.updateInputState()
       // self.textView.update(true)
        DispatchQueue.main.async {
            self.textView.setToEnd()
        }
    }
    
    func canTransformInputText() -> Bool {
        return true
    }
    
    
    
    func updateInputState(animated: Bool = true) {
        
        guard let window = self.window, let arguments = self.arguments else {
            return
        }
        
        let wWdith = window.contentView!.frame.width
        
        let maxSize = NSMakeSize(wWdith - 100, window.contentView!.frame.height - 110)
        let supersize = StoryLayoutView.size.aspectFitted(maxSize)
        let size: NSSize

        let addition: CGFloat
        if arguments.interaction.presentation.inputRecording != nil {
            addition = 60
            textView.inputView.textContainer?.maximumNumberOfLines = 0
            textView.inputView.textContainer?.lineBreakMode = .byWordWrapping
            textView.inputView.isSelectable = true
            textView.inputView.isEditable = !arguments.interaction.presentation.inTransition
        } else {
            if arguments.interaction.presentation.wideInput {
                addition = 60
                textView.inputView.textContainer?.maximumNumberOfLines = 0
                textView.inputView.textContainer?.lineBreakMode = .byWordWrapping
                textView.inputView.isSelectable = true
                textView.inputView.isEditable = !arguments.interaction.presentation.inTransition
            } else {
                addition = 0
                textView.inputView.textContainer?.maximumNumberOfLines = 1
                textView.inputView.textContainer?.lineBreakMode = .byTruncatingTail
                textView.inputView.isSelectable = false
                textView.inputView.isEditable = !arguments.interaction.presentation.inTransition
            }
        }
        let width = min(supersize.width + addition, wWdith - 20)
        size = NSMakeSize(width, addition == 0 ? 50 : self.textViewSize(width - 150).0.height)

        
        self.action.update(state: !isFirstResponder && self.story?.sharable == true ? .share : textView.string().isEmpty ? .empty(isVoice: arguments.interaction.presentation.recordType == .voice) : .text, arguments: arguments, story: self.story, animated: animated)
        self.updateInputSize(size: size, animated: animated)
        
    }
    
    

    
    private(set) var inputState: StoryInputState = .none {
        didSet {
            if oldValue != inputState {
                inputStateDidUpdate?(inputState)
            }
        }
    }
    
    private var inputStateDidUpdate:((StoryInputState)->Void)? = nil
    
    func installInputStateUpdate(_ f: ((StoryInputState)->Void)?) {
        self.inputStateDidUpdate = f
    }
    
    func like(_ like: StoryReactionAction, resetIfNeeded: Bool) {
        guard let arguments = self.arguments, let story = self.story else {
            return
        }
        let state = arguments.interaction.presentation
        if story.storyItem.myReaction == like.item.reaction || (resetIfNeeded && story.storyItem.myReaction != nil) {
            self.arguments?.like(nil, state)
        } else {
            
            self.arguments?.like(like.item.reaction, state)
            self.likeAction.react(like, state: state, context: arguments.context)
        }
    }
    
    
    let textView: UITextView
    private let textContainer = View()
    private let inputContextContainer = View()
    private let inputContext_Relative = View()
    private let visualEffect: VisualEffect
    private let attach = ImageButton()
    private let action = StoryReplyActionButton(frame: NSMakeRect(0, 0, 50, 50))
    private let likeAction = StoryLikeActionButton(frame: NSMakeRect(0, 0, 50, 50))
    
    var actionControl: NSView {
        return action
    }
    
    fileprivate let textInteractions: TextView_Interactions = .init()
    
    func set(_ state: Updated_ChatTextInputState) {
        self.arguments?.chatInteraction.update({
            $0.withUpdatedEffectiveInputState(state.textInputState())
        })
    }
    
    required init(frame frameRect: NSRect) {
        self.textView = UITextView(frame: NSMakeRect(0, 0, 100, 34), interactions: textInteractions)
        self.visualEffect = VisualEffect()
        super.init(frame: frameRect)
        self.background = .blackTransparent
      //  addSubview(visualEffect)
        addSubview(attach)
        addSubview(action)
        addSubview(likeAction)
        addSubview(textContainer)
        addSubview(inputContextContainer)
        
        self.layer?.masksToBounds = false
        
        inputContextContainer.addSubview(inputContext_Relative)
        
        textContainer.addSubview(textView)
        
       
        
        self.set(handler: { [weak self] _ in
            self?.window?.makeFirstResponder(self?.input)
        }, for: .Click)
           
  
        visualEffect.bgColor = .blackTransparent
        
        attach.set(image: attach_image, for: .Normal)
        attach.set(image: attach_image_active, for: .Highlight)
        attach.sizeToFit(.zero, NSMakeSize(50, 50), thatFit: true)
        attach.setAccessibilityLabel(strings().voiceOverAttachMedia)
        
        attach.contextMenu = { [weak self] in
            
            let menu = ContextMenu(presentation: AppMenu.Presentation.current(darkAppearance.colors), betterInside: true)
            var items: [ContextMenuItem] = []
            
            
            
            items.append(ContextMenuItem(strings().storyInputAttach, handler: { [weak self] in
                self?.arguments?.attachPhotoOrVideo(nil)
            }, itemImage: MenuAnimation.menu_shared_media.value))
            
            items.append(ContextMenuItem(strings().storyInputFile, handler: { [weak self] in
                self?.arguments?.attachFile()
            }, itemImage: MenuAnimation.menu_file.value))
            
            for item in items {
                menu.addItem(item)
            }
            return menu
        }
                
        likeAction.set(handler: { [weak self] control in
            
            let control = control as! StoryLikeActionButton
            
            guard let arguments = self?.arguments else {
                return
            }
            let state = arguments.interaction.presentation
            if state.wideInput {
                self?.arguments?.showEmojiPanel(control)
            } else {
                self?.like(.init(item: .builtin("❤️".withoutColorizer), fromRect: nil), resetIfNeeded: true)
            }
        }, for: .Click)
        
        
        
        likeAction.set(handler: { [weak self] control in
            guard let arguments = self?.arguments, let story = self?.story else {
                return
            }
            arguments.showLikePanel(control, story)
        }, for: .RightDown)
        
        self.layer?.cornerRadius = 25

        self.textView.inputView.appearance = darkAppearance.appearance
        
        self.textView.interactions.max_height = 200
        self.textView.interactions.min_height = 34
        
        self.textView.interactions.inputDidUpdate = { [weak self] state in
            guard let `self` = self else {
                return
            }
            self.set(state)
            self.inputDidUpdateLayout(animated: true)

        }
        self.textView.interactions.responderDidUpdate = { [weak self] in
            self?.responderDidUpdate()
        }
        textInteractions.processEnter = { [weak self] event in
            return self?.textViewEnterPressed(event) ?? true
        }
        textInteractions.processPaste = { [weak self] pasteboard in
            return self?.processPaste(pasteboard) ?? false
        }
        textInteractions.processAttriburedCopy = { attributedString in
            return LinkHooks.shared.globalLinkExecutor().copyAttributedString(attributedString)
        }
    }
    
    func inputDidUpdateLayout(animated: Bool) {
        let size = NSMakeSize(frame.width, textViewSize(frame.width - 150).0.height)
        self.updateInputSize(size: size, animated: animated)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var isFirstResponder: Bool {
        return window?.firstResponder == textView.inputView
    }
    
    var input: NSTextView? {
        return self.textView.inputView
    }
    var text: UITextView? {
        return self.textView
    }
    
    var inputReactionsControl: Control? {
        return self.likeAction
    }
    
    func resetInputView() {
        window?.makeFirstResponder(nil)
    }

    
    private var arguments:StoryArguments? = nil
    private var groupId: PeerId? = nil
    
    func setArguments(_ arguments: StoryArguments?, groupId: PeerId?) -> Void {
        self.arguments = arguments
        self.groupId = groupId
        applyStoryInput(arguments, groupId: groupId, textView: textView)
    }
    
    private var inputContextSize: NSSize? = nil
    
    func updateInputContext(with result:ChatPresentationInputQueryResult?, context: InputContextHelper, animated:Bool) {
        context.updatedSize = { [weak self] size, animated in
            self?.inputContextSize = size
            self?.updateInputState(animated: animated)
        }
        context.getHeight = {
            return 150
        }
        context.getPresentation = {
            darkAppearance
        }
        context.getBackground = {
            .clear
        }
        context.onDisappear = { [weak self] in
            self?.inputContextSize = nil
            self?.updateInputState(animated: animated)
        }
        context.context(with: result, for: inputContextContainer, relativeView: inputContext_Relative, position: .above, animated: animated)
    }
    
    
    deinit {
        rtfAttachmentsDisposable.dispose()
        stealthDisposable.dispose()
    }
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        guard let window = self.window else {
            return
        }
        transition.updateFrame(view: action, frame: NSMakeRect(size.width - action.frame.width, size.height - action.frame.height, action.frame.width, action.frame.height))
        transition.updateFrame(view: likeAction, frame: NSMakeRect(action.frame.minX - likeAction.frame.width, size.height - action.frame.height, likeAction.frame.width, likeAction.frame.height))
                
        
        transition.updateFrame(view: attach, frame: NSMakeRect(0, size.height - attach.frame.height, attach.frame.width, attach.frame.height))
        transition.updateFrame(view: visualEffect, frame: focus(window.frame.size))
        
        
        let (textSize, textHeight) = textViewSize(size.width - 150)
        
        var textRect = textSize.bounds
        textRect.origin.x = 50
        textRect.origin.y = size.height - textRect.height
        
        transition.updateFrame(view: textContainer, frame: textRect)

        if let inputContextSize = self.inputContextSize {
            transition.updateFrame(view: inputContextContainer, frame: CGRect(origin: CGPoint.init(x: 0, y: textRect.minY - inputContextSize.height), size: NSMakeSize(size.width, inputContextSize.height)))
        } else {
            transition.updateFrame(view: inputContextContainer, frame: CGRect(origin: CGPoint(x: 0, y: textRect.minY - 1), size: NSMakeSize(size.width, 1)))
        }
        
        transition.updateFrame(view: inputContext_Relative, frame: CGRect(origin: CGPoint(x: 0, y: inputContextContainer.frame.height), size: NSMakeSize(size.width, 1)))
        
        transition.updateFrame(view: textView, frame: textRect.size.bounds)
        textView.updateLayout(size: textRect.size, textHeight: textHeight, transition: transition)
    }
    
    override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
}
