import Cocoa
import TGUIKit
import TGModernGrowingTextView
import SwiftSignalKit
import Postbox
import TelegramCore
import ColorPalette
import InputView
import TelegramMedia
import ChatUI
import InAppSettings
import InputTextView
import Localization
import ShortPeerRow
import TelegramTheme
import TelegramUtils


private let toggle_image_down: CGImage = generateImage(NSMakeSize(24, 24), contextGenerator: { size, ctx in
    ctx.clear(size.bounds)
    let image = TelegramThemeHooks.shared.image(.iconLiveStreamMessageConceal).precomposed(.white)

    var imageRect = size.bounds.focus(image.backingSize)
    ctx.draw(image, in: imageRect)
    
})!

private let toggle_image_up: CGImage = generateImage(NSMakeSize(24, 24), contextGenerator: { size, ctx in
    ctx.clear(size.bounds)
    let image = TelegramThemeHooks.shared.image(.iconLiveStreamMessageReveal).precomposed(.white)

    var imageRect = size.bounds.focus(image.backingSize)
    ctx.draw(image, in: imageRect)
    
})!


private let toggle_image_up_unread: CGImage = generateImage(NSMakeSize(24, 24), contextGenerator: { size, ctx in
    ctx.clear(size.bounds)
    let image = TelegramThemeHooks.shared.image(.iconLiveStreamMessageReveal).precomposed(.white)
    
    var imageRect = size.bounds.focus(image.backingSize)
    ctx.draw(image, in: imageRect)

    
    let rect = NSMakeRect(image.backingSize.width - 6, image.backingSize.height / 2 - 8, 6, 6)
        
    ctx.saveGState()
    let ellipseRect = rect.insetBy(dx: -1, dy: -1)
    ctx.addEllipse(in: ellipseRect)
    ctx.clip()
    ctx.clear(ellipseRect)
    ctx.restoreGState()
    
    ctx.setFillColor(darkPalette.accent.cgColor)
    ctx.fillEllipse(in: rect)
    
})!


final class StoryLiveStreamInputView : Control, StoryInput {
    
    private let rtfAttachmentsDisposable = MetaDisposable()
    private var recordingView: StoryRecordingView?
    private var story: StoryContentItem?
    private var sendAsView: ChatInputSendAsView?

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
        
        let actionState: StoryReplyActionButton.State
        
        if let stars = state.messageStarPrice, !state.input.inputText.isEmpty {
            actionState = .starPrice(stars)
        } else {
            let totalStars = state.mediaCall?.messages?.totalStars ?? 0
            let pending = state.mediaCall?.messages?.pendingMyStars ?? 0
            let myStars = state.mediaCall?.messages?.topStars.first(where: { $0.isMy })?.amount
            actionState = textView.string().isEmpty ? .starReactions(totalStars + pending, pending > 0, myStars) : .text
        }
        
        self.action.update(state: actionState, arguments: arguments, story: self.story, animated: animated)
        
        
        if let story = self.story {
            self.likeAction.update(state: state.messageStarPrice != nil ? .emoji : .setprice, arguments: arguments, story: story, animated: animated)
            self.likeAction.isHidden = state.mediaCall?.inputEnabled == false
        }
        
        let image: CGImage
        if let lastHideMessageId = state.lastHideMessageId {
            let hasUnread = state.mediaCall?.messages?.messages.contains(where: { $0.id.id > lastHideMessageId }) ?? false
            if hasUnread {
                image = toggle_image_up_unread
            } else {
                image = toggle_image_up
            }
        } else {
            image = toggle_image_down
        }
        self.toggle.isHidden = state.inputInFocus || state.mediaCall?.messages?.messages.isEmpty == true
        self.toggle.set(image: image, for: .Normal)
        self.toggle.setAccessibilityLabel(state.lastHideMessageId != nil ? strings().voiceOverCommonShow : strings().voiceOverCommonHide)
        self.toggle.setAccessibilityValue(image == toggle_image_up_unread ? strings().voiceOverCommonUnread : nil)
        self.likeAction.isHidden = state.input.inputText.isEmpty
        
        if var sendAs = state.mediaCall?.state?.sendAs, !sendAs.isEmpty {
            sendAs.append(.init(peer: .init(arguments.context.myPeer!), subscribers: nil, isPremiumRequired: false))
                        
            let current: ChatInputSendAsView
            if let sendAsView {
                current = sendAsView
            } else {
                current = ChatInputSendAsView(frame: NSMakeRect(0, 0, 40, 40))
                self.sendAsView = current
                container.addSubview(current)
            }
            
            let currentPeerId = state.mediaCall?.state?.defaultSendAs ?? arguments.context.peerId
            
            current.menuPresentation = .init(colors: darkAppearance.colors)
            current.update(sendAs, currentPeerId: currentPeerId, chatInteraction: arguments.chatInteraction, animated: animated, photoSize: 28)
        } else if let sendAsView {
            performSubviewRemoval(sendAsView, animated: animated)
            self.sendAsView = nil
        }
        
        self.updateInputState(animated: animated)
        self.updateRecoringState(state, animated: animated)
        self.updatePlaceholder()
    }
    
    private func updatePlaceholder() {
        guard let arguments = self.arguments else {
            return
        }
        let isEnabled = arguments.interaction.presentation.mediaCall?.state?.messagesEnabled?.isEnabled == true
        
        let text: String
        if !isEnabled {
            text = strings().storyLiveStreamInputCommentsDisabled
        } else if let slowmode = arguments.interaction.presentation.slowMode, let timeout = slowmode.timeout {
            let timer = smartTimeleftText(Int(timeout))
            text = strings().storySlowModePlaceholder(timer)
        } else {
            text = strings().messagesPlaceholderSentMessageSmall
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
        self.likeAction.update(state: arguments.interaction.presentation.messageStarPrice != nil ? .emoji : .setprice, arguments: arguments, story: story, animated: animated)
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
                
        let wSize = NSMakeSize(window.contentView!.frame.width - 150, window.contentView!.frame.height - 110)
        let aspect = StoryLayoutView.size.aspectFitted(wSize)
        
        let size = size

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
                        
                        let (attributed, _) = attributed.applyRtf()
                        
                        chatInteraction.appendText(attributed)

                        return true
                    }
                }
            }
            return !result
        }
        return false
    }
    
    
    func textViewSize(_ width: CGFloat) -> (NSSize, CGFloat) {
        var w = width
        
        if !toggle.isHidden {
            w -= 50
        }
        if !likeAction.isHidden {
            w -= likeAction.frame.width
        }
        if !action.isHidden {
            w -= action.frame.width
            w -= 10
        }
        if let sendAsView {
            w -= sendAsView.frame.width
        }
        
        let height = self.textView.height(for: w)
        let singleLine = textView.inputView.textContainer?.maximumNumberOfLines == 1
        return (NSMakeSize(w, singleLine ? 40 : min(max(height, textView.min_height), textView.max_height) + 6), singleLine ? 26 : height)
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
        
        let maxSize = NSMakeSize(wWdith - 150, window.contentView!.frame.height - 110)
        let supersize = StoryLayoutView.size.aspectFitted(maxSize)
        let size: NSSize
        let isEnabled = arguments.interaction.presentation.mediaCall?.inputEnabled == true

        let addition: CGFloat
        if arguments.interaction.presentation.wideInput, isEnabled {
            addition = 60
            textView.inputView.textContainer?.maximumNumberOfLines = 0
            textView.inputView.textContainer?.lineBreakMode = .byWordWrapping
            textView.inputView.isSelectable = true
            textView.inputView.isEditable = !arguments.interaction.presentation.inTransition && isEnabled
        } else {
            addition = 0
            textView.inputView.textContainer?.maximumNumberOfLines = 1
            textView.inputView.textContainer?.lineBreakMode = .byTruncatingTail
            textView.inputView.isSelectable = false
            textView.inputView.isEditable = !arguments.interaction.presentation.inTransition && isEnabled
        }
        let width = min(supersize.width + addition, wWdith - 20)
        
        
                
        size = NSMakeSize(width, textViewSize(width).0.height)

        
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
     
    }
    
    let textView: UITextView
    private let textContainer = View()
    private let action = StoryReplyActionButton(frame: NSMakeRect(0, 0, 46, 40))
    private let likeAction = StoryReplyActionButton(frame: NSMakeRect(0, 0, 46, 40))
    
    private let toggle = ImageButton()
    
    var actionControl: NSView {
        return action
    }
    
    fileprivate let textInteractions: TextView_Interactions = .init()
    
    func set(_ state: Updated_ChatTextInputState) {
        
        guard let window = _window, let arguments = self.arguments else {
            return
        }
        
        let limit = arguments.interaction.presentation.max_input
        let max_emoji = arguments.interaction.presentation.max_emoji
        
        let emojies = state.string.emojis

        if state.string.length <= limit && emojies.count <= max_emoji {
            arguments.chatInteraction.update({
                $0.withUpdatedEffectiveInputState(state.textInputState())
            })
        } else {
            
            self.textView.set(arguments.interaction.presentation.input)
            if emojies.count > max_emoji {
                showModalText(for: window, text: strings().storyLiveStreamInputEmojiLimitReached)
            } else {
                showModalText(for: window, text: strings().storyLiveStreamInputLimitReached)
            }

            
            self.textView.shake(beep: true)
        }
        
    }
    
    private let container = View()
    
    required init(frame frameRect: NSRect) {
        self.textView = UITextView(frame: NSMakeRect(0, 0, 100, 34), interactions: textInteractions)
        super.init(frame: frameRect)
        self.background = .clear
        addSubview(action)
        addSubview(toggle)
        addSubview(container)
        self.layer?.masksToBounds = false
        
        container.addSubview(textContainer)
        container.addSubview(likeAction)

        container.backgroundColor = darkAppearance.colors.grayBackground.withAlphaComponent(0.8)
        
        textContainer.addSubview(textView)
        
       
        
        self.set(handler: { [weak self] _ in
            if self?.input?.isEditable == true {
                self?.window?.makeFirstResponder(self?.input)
            }
        }, for: .Click)
           
          
        
        container.layer?.cornerRadius = 20

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
        
        toggle.set(image: toggle_image_down, for: .Normal)
        toggle.set(background:  darkAppearance.colors.grayBackground.withAlphaComponent(0.8), for: .Normal)
        toggle.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
        toggle.layer?.cornerRadius = toggle.frame.height / 2
        
        toggle.scaleOnClick = true
        toggle.autohighlight = false
        toggle.set(handler: { [weak self] _ in
            self?.arguments?.toggleMessages(self?.arguments?.interaction.presentation.mediaCall?.messages?.messages.last?.id.id)
        }, for: .Click)
    }
    
    func inputDidUpdateLayout(animated: Bool) {
        let size = NSMakeSize(frame.width, textViewSize(frame.width).0.height)
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
        return nil
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
    
    
    func updateInputContext(with result:ChatPresentationInputQueryResult?, context: InputContextHelper, animated:Bool) {
        
    }
    
    
    deinit {
        rtfAttachmentsDisposable.dispose()
    }
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        
               
        
        var textX: CGFloat = 0
        if !toggle.isHidden {
            textX += 50
        }
        
        let (textSize, textHeight) = textViewSize(size.width)
        
        var textRect = textSize.bounds
        textRect.origin.x = 0
        textRect.origin.y = size.height - textRect.height
        
        
        var containerRect = textRect
        containerRect.origin.x = textX
        
        var offset: CGFloat = 0
        if let sendAsView {
            containerRect.size.width += sendAsView.frame.width
            offset += sendAsView.frame.width
        } else {
            offset = 10
        }
        if !likeAction.isHidden {
            containerRect.size.width += likeAction.frame.width
        }
        
        transition.updateFrame(view: container, frame: containerRect)
        
        transition.updateFrame(view: textContainer, frame: textRect.size.bounds.offsetBy(dx: offset, dy: 0))
        
        transition.updateFrame(view: textView, frame: textRect.size.bounds)
        textView.updateLayout(size: textRect.size, textHeight: textHeight, transition: transition)
        
        transition.updateFrame(view: toggle, frame: NSMakeRect(0, size.height - toggle.frame.height, toggle.frame.width, toggle.frame.height))
        
        if let sendAsView {
            transition.updateFrame(view: sendAsView, frame: NSMakeRect(0, size.height - sendAsView.frame.height, sendAsView.frame.width, sendAsView.frame.height))
        }

        transition.updateFrame(view: likeAction, frame: NSMakeRect(container.frame.width - likeAction.frame.width, size.height - likeAction.frame.height, likeAction.frame.width, likeAction.frame.height))

        
        transition.updateFrame(view: action, frame: NSMakeRect(size.width - action.frame.width, size.height - action.frame.height, action.frame.width, action.frame.height))


    }
    
    override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
}
