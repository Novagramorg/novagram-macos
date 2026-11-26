import Cocoa
import TGUIKit
import TelegramCore
import ColorPalette
import SwiftSignalKit
import Postbox
import TelegramIconsTheme



public final class ChatMediaPresentation : Equatable {
    
    public let isIncoming: Bool
    public let isBubble: Bool
    
    public let activityBackground: NSColor
    public let activityForeground: NSColor
    public let waveformBackground: NSColor
    public let waveformForeground: NSColor
    public let text: NSColor
    public let grayText: NSColor
    public let link: NSColor
    public let presentation: TelegramPresentationTheme
    public init(presentation: TelegramPresentationTheme, isIncoming: Bool, isBubble: Bool, activityBackground: NSColor, activityForeground: NSColor, text: NSColor, grayText: NSColor, link: NSColor, waveformBackground: NSColor, waveformForeground: NSColor) {
        self.presentation = presentation
        self.isIncoming = isIncoming
        self.isBubble = isBubble
        self.activityForeground = activityForeground
        self.activityBackground = activityBackground
        self.text = text
        self.grayText = grayText
        self.link = link
        self.waveformBackground = waveformBackground
        self.waveformForeground = waveformForeground
    }
    
    public var blendingMode: CGBlendMode {
        return !self.isIncoming && self.isBubble ? .clear : .normal
    }
    
    public static func make(for message: Message, account: Account, renderType: ChatItemRenderType, theme: TelegramPresentationTheme) -> ChatMediaPresentation {
        let isIncoming: Bool = message.isIncoming(account, renderType == .bubble)
        
        
        let grayText = theme.chat.grayText(isIncoming, renderType == .bubble)

        return ChatMediaPresentation(presentation: theme, isIncoming: isIncoming,
                                     isBubble: renderType == .bubble,
                                     activityBackground: theme.chat.activityBackground(isIncoming, renderType == .bubble),
                                     activityForeground: theme.chat.activityForeground(isIncoming, renderType == .bubble),
                                     text: theme.chat.textColor(isIncoming, renderType == .bubble),
                                     grayText: grayText,
                                     link: theme.chat.linkColor(isIncoming, renderType == .bubble),
                                     waveformBackground: theme.chat.waveformBackground(isIncoming, renderType == .bubble),
                                     waveformForeground: theme.chat.waveformForeground(isIncoming, renderType == .bubble))
    }
    public static func make(theme: TelegramPresentationTheme) -> ChatMediaPresentation {
        let isIncoming: Bool = false
        
        let grayText = theme.chat.grayText(isIncoming, false)

        return ChatMediaPresentation(presentation: theme, isIncoming: isIncoming,
                                     isBubble: false,
                                     activityBackground: theme.chat.activityBackground(isIncoming, false),
                                     activityForeground: theme.chat.activityForeground(isIncoming, false),
                                     text: theme.chat.textColor(isIncoming, false),
                                     grayText: grayText,
                                     link: theme.chat.linkColor(isIncoming, false),
                                     waveformBackground: theme.chat.waveformBackground(isIncoming, false),
                                     waveformForeground: theme.chat.waveformForeground(isIncoming, false))
    }
    public static var empty: ChatMediaPresentation {
        return .init(presentation: theme, isIncoming: true, isBubble: true, activityBackground: .clear, activityForeground: .clear, text: .clear, grayText: .clear, link: .clear, waveformBackground: .clear, waveformForeground: .clear)
    }
    
    public var fileThumb: CGImage {
        if isBubble {
            return isIncoming ? presentation.icons.chatFileThumbBubble_incoming : presentation.icons.chatFileThumbBubble_outgoing
        } else {
            return presentation.icons.chatFileThumb
        }
    }
    
    
    public var pauseThumb: CGImage {
        if isBubble {
            return isIncoming ? presentation.icons.chatMusicPauseBubble_incoming : presentation.icons.chatMusicPauseBubble_outgoing
        } else {
            return presentation.icons.chatMusicPause
        }
    }
    public var playThumb: CGImage {
        if isBubble {
            return isIncoming ? presentation.icons.chatMusicPlayBubble_incoming : presentation.icons.chatMusicPlayBubble_outgoing
        } else {
            return presentation.icons.chatMusicPlay
        }
    }
    
    public static var Empty: ChatMediaPresentation {
        return ChatMediaPresentation(presentation: theme, isIncoming: false, isBubble: false, activityBackground: theme.colors.accent, activityForeground: theme.colors.underSelectedColor, text: theme.colors.text, grayText: theme.colors.grayText, link: theme.colors.link, waveformBackground: theme.colors.waveformBackground, waveformForeground: theme.colors.waveformForeground)
    }
    
    public static func ==(lhs: ChatMediaPresentation, rhs: ChatMediaPresentation) -> Bool {
        return lhs === rhs
    }
}

private func generatePollReplyBarIcon(color: NSColor) -> CGImage {
    let size = NSMakeSize(14, 14)
    return generateImage(size, rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        ctx.setFillColor(color.cgColor)
        let barWidth: CGFloat = 2.5
        let spacing: CGFloat = 1.5
        let barHeights: [CGFloat] = [8, 5, 11]
        let totalWidth = barWidth * 3 + spacing * 2
        var x = floorToScreenPixels(System.backingScale, (size.width - totalWidth) / 2)
        let baseY = size.height - 1
        for h in barHeights {
            let rect = NSMakeRect(x, baseY - h, barWidth, h)
            let path = CGMutablePath()
            path.addRoundedRect(in: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2)
            ctx.addPath(path)
            ctx.fillPath()
            x += barWidth + spacing
        }
    })!
}

private func generatePollReplyCheckIcon(backgroundColor: NSColor, checkColor: NSColor, isMultiple: Bool) -> CGImage {
    let size = NSMakeSize(14, 14)
    return generateImage(size, rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        let rect = NSMakeRect(1, 1, size.width - 2, size.height - 2)
        let path = CGMutablePath()
        if isMultiple {
            path.addRoundedRect(in: rect, cornerWidth: 3, cornerHeight: 3)
        } else {
            path.addEllipse(in: rect)
        }
        ctx.addPath(path)
        ctx.setFillColor(backgroundColor.cgColor)
        ctx.fillPath()
        ctx.setStrokeColor(checkColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: NSMakePoint(4.5, 7))
        ctx.addLine(to: NSMakePoint(6.5, 9.5))
        ctx.addLine(to: NSMakePoint(10, 5))
        ctx.strokePath()
    })!
}

private func generatePercentageImage(color: NSColor, value: Int, font: NSFont) -> CGImage {
    return generateImage(CGSize(width: 36.0, height: 16.0), rotatedContext: { size, context in
    
        
        context.clear(CGRect(origin: CGPoint(), size: size))
        
        
        let layout = TextViewLayout(.initialize(string: "\(value)%", color: color, font: font), maximumNumberOfLines: 1, alignment: .right)
        layout.measure(width: size.width)
        if !layout.lines.isEmpty {
            let line = layout.lines[0]
            context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
            let penOffset = CGFloat( CTLineGetPenOffsetForFlush(line.line, layout.penFlush, Double(size.width))) + line.frame.minX
            
            context.setAllowsFontSubpixelPositioning(true)
            context.setShouldSubpixelPositionFonts(true)
            context.setAllowsAntialiasing(true)
            context.setShouldAntialias(true)
            context.setAllowsFontSmoothing(System.backingScale == 1.0)
            context.setShouldSmoothFonts(System.backingScale == 1.0)
            
            context.textPosition = CGPoint(x: penOffset, y: line.frame.minY)

            CTLineDraw(line.line, context)
        }
        
    })!
}


public final class TelegramChatColors {
    

    
    enum PercentageVariant: Int {
        case plain
        case incomingBubbled
        case outgoingBubbled
    }
    
    private let percentageImagesLock = NSLock()
    private var percentageImages: [[CGImage?]] = Array(repeating: Array(repeating: nil, count: 101), count: 3)
    private(set) var generatedPercentageImageCount: Int = 0
    
    func percentageImage(_ variant: PercentageVariant, value: Int) -> CGImage {
        let value = max(0, min(100, value))
        percentageImagesLock.lock()
        if let image = percentageImages[variant.rawValue][value] {
            percentageImagesLock.unlock()
            return image
        }
        percentageImagesLock.unlock()
        
        let color: NSColor
        switch variant {
        case .plain:
            color = palette.text
        case .incomingBubbled:
            color = palette.textBubble_incoming
        case .outgoingBubbled:
            color = palette.textBubble_outgoing
        }
        let image = generatePercentageImage(color: color, value: value, font: .bold(12))
        
        percentageImagesLock.lock()
        defer {
            percentageImagesLock.unlock()
        }
        if let existing = percentageImages[variant.rawValue][value] {
            return existing
        }
        percentageImages[variant.rawValue][value] = image
        generatedPercentageImageCount += 1
        return image
    }
    
    private func percentageVariant(_ incoming: Bool, _ bubbled: Bool) -> PercentageVariant {
        return bubbled ? incoming ? .incomingBubbled : .outgoingBubbled : .plain
    }
    
    
    public let palette: ColorPalette
    public init(_ palette: ColorPalette, _ bubbled: Bool) {
        self.palette = palette
    }
    
    private var cacheDict: [String: CGImage] = [:]
    
    public func messageSecretTimer(_ value: String) -> CGImage {
        if let value = cacheDict[value] {
            return value
        } else {
            let node = TextNode.layoutText(.initialize(string: value, color: self.palette.darkGrayText, font: .normal(15)), nil, 1, .end, NSMakeSize(30, 30), nil, false, .left)
            
            let image = generateImage(NSMakeSize(30, 30), rotatedContext: { size, ctx in
                let rect = NSMakeRect(0, 0, size.width, size.height)
                ctx.clear(rect)
                node.1.draw(rect.focus(node.0.size).offsetBy(dx: 0, dy: 1), in: ctx, backingScaleFactor: 1.0, backgroundColor: .clear)
            })!
            cacheDict[value] = image
            
            return image
        }
        
    }
    
    //chatGotoMessageWallpaper / chatShareWallpaper / chatSwipeReplyWallpaper
    
    public func chat_goto_message_bubble(theme: TelegramPresentationTheme) -> CGImage {
        if let value = cacheDict["chat_goto_message_bubble"] {
            return value
        } else {
            let image = TelegramThemeHooks.shared.image(.iconGotoBubbleMessage).precomposed(theme.chatServiceItemTextColor)
            cacheDict["chat_goto_message_bubble"] = image
            return image
        }
    }
    public func chat_share_bubble(theme: TelegramPresentationTheme) -> CGImage {
        if let value = cacheDict["chat_share_bubble"] {
            return value
        } else {
            let image = TelegramThemeHooks.shared.image(.iconChannelShare).precomposed(theme.chatServiceItemTextColor)
            cacheDict["chat_share_bubble"] = image
            return image
        }
    }
    public func chat_reply_swipe_bubble(theme: TelegramPresentationTheme) -> CGImage {
        if let value = cacheDict["chat_reply_swipe_bubble"] {
            return value
        } else {
            let image = TelegramThemeHooks.shared.image(.iconChannelShare).precomposed(theme.chatServiceItemTextColor, flipHorizontal: true)
            cacheDict["chat_reply_swipe_bubble"] = image
            return image
        }
    }
    public func chat_like_message_bubble(theme: TelegramPresentationTheme) -> CGImage {
        if let value = cacheDict["chat_like_message_bubble"] {
            return value
        } else {
            let image = TelegramThemeHooks.shared.image(.iconLikeMessageButton).precomposed(theme.chatServiceItemTextColor)
            cacheDict["chat_like_message_bubble"] = image
            return image
        }
    }
    public func chat_like_message_unlike_bubble(theme: TelegramPresentationTheme) -> CGImage {
        if let value = cacheDict["chat_like_message_unlike_bubble"] {
            return value
        } else {
            let image = TelegramThemeHooks.shared.image(.iconLikeMessageButtonUnlike).precomposed(theme.chatServiceItemTextColor)
            cacheDict["chat_like_message_unlike_bubble"] = image
            return image
        }
    }
    
    private var _chatActionUrl: CGImage?
    public func chatActionUrl(theme: TelegramPresentationTheme) -> CGImage {
        if let chatActionUrl = _chatActionUrl {
            return chatActionUrl
        } else {
            let image = TelegramThemeHooks.shared.image(.iconInlineBotUrl).precomposed(theme.chatServiceItemTextColor)
            _chatActionUrl = image
            return image
        }
    }

    private var _chatActionShare: CGImage?
    public func chatActionShare(theme: TelegramPresentationTheme) -> CGImage {
        if let chatActionShare = _chatActionShare {
            return chatActionShare
        } else {
            let image = TelegramThemeHooks.shared.image(.iconInlineBotShare).precomposed(theme.chatServiceItemTextColor)
            _chatActionShare = image
            return image
        }
    }

    private var _chatActionProfile: CGImage?
    public func chatActionProfile(theme: TelegramPresentationTheme) -> CGImage {
        if let chatActionProfile = _chatActionProfile {
            return chatActionProfile
        } else {
            let image = TelegramThemeHooks.shared.image(.iconInlineBotProfile).precomposed(theme.chatServiceItemTextColor)
            _chatActionProfile = image
            return image
        }
    }
    
    private var _chatActionSuggestApprove: CGImage?
    public func chatActionSuggestApprove(theme: TelegramPresentationTheme) -> CGImage {
        if let chatActionSuggestApprove = _chatActionSuggestApprove {
            return chatActionSuggestApprove
        } else {
            let image = TelegramThemeHooks.shared.image(.iconSuggestPostApprove).precomposed(theme.chatServiceItemTextColor)
            _chatActionSuggestApprove = image
            return image
        }
    }
    
    private var _chatActionSuggestDecline: CGImage?
    public func chatActionSuggestDecline(theme: TelegramPresentationTheme) -> CGImage {
        if let chatActionSuggestDecline = _chatActionSuggestDecline {
            return chatActionSuggestDecline
        } else {
            let image = TelegramThemeHooks.shared.image(.iconSuggestPostDecline).precomposed(theme.chatServiceItemTextColor)
            _chatActionSuggestDecline = image
            return image
        }
    }
    
    private var _chatActionSuggestEdit: CGImage?
    public func chatActionSuggestEdit(theme: TelegramPresentationTheme) -> CGImage {
        if let chatActionSuggestEdit = _chatActionSuggestEdit {
            return chatActionSuggestEdit
        } else {
            let image = TelegramThemeHooks.shared.image(.iconSuggestPostEdit).precomposed(theme.chatServiceItemTextColor)
            _chatActionSuggestEdit = image
            return image
        }
    }
    
    private var _chatActionCopy: CGImage?
    public func chatActionCopy(theme: TelegramPresentationTheme) -> CGImage {
        if let chatActionUrl = _chatActionCopy {
            return chatActionUrl
        } else {
            let image = TelegramThemeHooks.shared.image(.iconInlineBotCopy).precomposed(theme.chatServiceItemTextColor)
            _chatActionCopy = image
            return image
        }
    }
    
    private var _chatActionWebUrl: CGImage?
    public func chatActionWebUrl(theme: TelegramPresentationTheme) -> CGImage {
        if let chatActionWebUrl = _chatActionWebUrl {
            return chatActionWebUrl
        } else {
            let image = NSImage.init(named: "Icon_InlineBotWeb")!.precomposed(theme.chatServiceItemTextColor)
            _chatActionWebUrl = image
            return image
        }
    }
    
    private var _chatInvoiceAction: CGImage?
    public func chatInvoiceAction(theme: TelegramPresentationTheme) -> CGImage {
        if let _chatInvoiceAction = _chatInvoiceAction {
            return _chatInvoiceAction
        } else {
            let image = TelegramThemeHooks.shared.image(.iconChatInvoice).precomposed(theme.chatServiceItemTextColor)
            _chatInvoiceAction = image
            return image
        }
    }
    
    public func pollPercentAnimatedIcons(_ incoming: Bool, _ bubbled: Bool, from fromValue: CGFloat, to toValue: CGFloat, duration: Double) -> [CGImage] {
        let minimumFrameDuration = 1.0 / 60
        let numberOfFrames = max(1, Int(duration / minimumFrameDuration))
        var images: [CGImage] = []
        
        let variant = percentageVariant(incoming, bubbled)
        
        for i in 0 ..< numberOfFrames {
            let t = CGFloat(i) / CGFloat(numberOfFrames)
            let value = (1.0 - t) * fromValue + t * toValue
            images.append(percentageImage(variant, value: Int(round(value))))
        }
        return images
    }
    
    public func pollPercentAnimatedIcon(_ incoming: Bool, _ bubbled: Bool, value: Int) -> CGImage {
        return percentageImage(percentageVariant(incoming, bubbled), value: value)
    }
    
    public func activityBackground(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.fileActivityBackgroundBubble_incoming : palette.fileActivityBackgroundBubble_outgoing : palette.fileActivityBackground
    }
    public func activityForeground(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.fileActivityForegroundBubble_incoming : palette.fileActivityForegroundBubble_outgoing : palette.fileActivityForeground
    }
    public func activityColor(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.webPreviewActivityBubble_incoming : palette.webPreviewActivityBubble_outgoing : palette.webPreviewActivity
    }
    public func webPreviewActivity(_ colors: PeerNameColors, message: Message, account: Account, bubbled: Bool) -> PeerNameColors.Colors {
        let isIncoming = message.isIncoming(account, bubbled)
        
        var hasSecondary: Bool = false
        var hasTertiary: Bool = false

        
        if let author = message.effectiveAuthor {
            if let nameColor = author.namePeerColor {
                let color = colors.get(nameColor)
                if isIncoming {
                    return colors.get(nameColor)
                }
                hasSecondary = color.secondary != nil
                hasTertiary = color.tertiary != nil
            }
        }
        let color = bubbled ? isIncoming ? palette.webPreviewActivityBubble_incoming : palette.webPreviewActivityBubble_outgoing : palette.webPreviewActivity
        
        let secondary = hasSecondary ? color.withAlphaComponent(0.2) : nil
        let tertiary = hasTertiary ? color.withAlphaComponent(0.2) : nil

        return .init(main: color, secondary: secondary, tertiary: tertiary)
    }
    
    public func contactActivity(_ colors: PeerNameColors, contactPeer: Peer?, account: Account, isIncoming: Bool, bubbled: Bool) -> PeerNameColors.Colors {
        
        var hasSecondary: Bool = false
        var hasTertiary: Bool = false

        
        if let author = contactPeer {
            if let nameColor = author.namePeerColor {
                let color = colors.get(nameColor)
                if isIncoming {
                    return colors.get(nameColor)
                }
                hasSecondary = color.secondary != nil
                hasTertiary = color.tertiary != nil
            }
        }
        let color = bubbled ? isIncoming ? palette.webPreviewActivityBubble_incoming : palette.webPreviewActivityBubble_outgoing : palette.webPreviewActivity
        
        let secondary = hasSecondary ? color.withAlphaComponent(0.2) : nil
        let tertiary = hasTertiary ? color.withAlphaComponent(0.2) : nil

        return .init(main: color, secondary: secondary, tertiary: tertiary)
    }
    
    public func pollOptionBorder(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return (bubbled ? incoming ?  grayText(incoming, bubbled) : grayText(incoming, bubbled) : palette.grayText).withAlphaComponent(0.2)
    }
    public func pollOptionUnselectedImage(_ incoming: Bool, _ bubbled: Bool) -> CGImage {
        return bubbled ? incoming ? theme.icons.chatPollVoteUnselectedBubble_incoming :  theme.icons.chatPollVoteUnselectedBubble_outgoing : theme.icons.chatPollVoteUnselected
    }
    public func waveformBackground(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.waveformBackgroundBubble_incoming : palette.waveformBackgroundBubble_outgoing : palette.waveformBackground
    }
    public func waveformForeground(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.waveformForegroundBubble_incoming : palette.waveformForegroundBubble_outgoing : palette.waveformForeground
    }
    
    
    
    public func backgroundColor(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? System.supportsTransparentFontDrawing ? .clear : palette.bubbleBackground_incoming : System.supportsTransparentFontDrawing ?  .clear : palette.blendedOutgoingColors : palette.chatBackground
    }
    
    public func bubbleBackgroundColor(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.bubbleBackground_incoming : palette.blendedOutgoingColors : .clear//.clear//palette.bubbleBorder_outgoing
    }
    
    public func textColor(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.textBubble_incoming : palette.textBubble_outgoing : palette.text
    }
    
    public func monospacedPreColor(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.textBubble_incoming : palette.textBubble_outgoing : palette.monospacedPre
    }
    public func monospacedCodeColor(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.textBubble_incoming : palette.textBubble_outgoing : palette.monospacedCode
    }
    
    public func selectText(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.selectTextBubble_incoming : palette.selectTextBubble_outgoing : palette.selectText
    }
    
    public func grayText(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.grayTextBubble_incoming : palette.grayTextBubble_outgoing : palette.grayText
    }
    public func redUI(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.redBubble_incoming : palette.redBubble_outgoing : palette.redUI
    }
    public func greenUI(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.greenBubble_incoming : palette.greenBubble_outgoing : palette.greenUI
    }
    public func linkColor(_ incoming: Bool, _ bubbled: Bool) -> NSColor {
        return bubbled ? incoming ? palette.linkBubble_incoming : palette.linkBubble_outgoing : palette.accent
    }
    
    public func pollSelected(_ incoming: Bool, _ bubbled: Bool, icons: TelegramIconsTheme) -> CGImage {
        return bubbled ? incoming ? icons.poll_selected_incoming : icons.poll_selected_outgoing : icons.poll_selected
    }
    public func pollSelection(_ incoming: Bool, _ bubbled: Bool, icons: TelegramIconsTheme) -> CGImage {
        return bubbled ? incoming ? icons.poll_selection_incoming : icons.poll_selection_outgoing : icons.poll_selection
    }
    
    public func todoSelected(_ incoming: Bool, _ bubbled: Bool, icons: TelegramIconsTheme) -> CGImage {
        return bubbled ? incoming ? icons.todo_selected_other_incoming : icons.todo_selected_other_outgoing : icons.todo_selection
    }
    public func todoSelection(_ incoming: Bool, _ bubbled: Bool, icons: TelegramIconsTheme) -> CGImage {
        return bubbled ? incoming ? icons.todo_selection_other_incoming : icons.todo_selection_other_outgoing : icons.todo_selected
    }
    
    public func pollSquareUnselected(_ incoming: Bool, _ bubbled: Bool) -> CGImage {
        return bubbled ? incoming ? theme.icons.poll_square_unselected_incoming : theme.icons.poll_square_unselected_outgoing : theme.icons.poll_square_unselected
    }
    public func pollSquareSelected(_ incoming: Bool, _ bubbled: Bool, icons: TelegramIconsTheme) -> CGImage {
        return bubbled ? incoming ? icons.poll_square_selected_incoming : icons.poll_square_selected_outgoing : icons.poll_square_selected
    }
    public func pollSquareSelection(_ incoming: Bool, _ bubbled: Bool, icons: TelegramIconsTheme) -> CGImage {
        return bubbled ? incoming ? icons.poll_square_selection_incoming : icons.poll_square_selection_outgoing : icons.poll_square_selection
    }

    public func pollSelectedCorrect(_ incoming: Bool, _ bubbled: Bool, icons: TelegramIconsTheme) -> CGImage {
        return bubbled ? incoming ? icons.poll_selected_correct_incoming : icons.poll_selected_correct_outgoing : icons.poll_selected_correct
    }
    public func pollSelectedIncorrect(_ incoming: Bool, _ bubbled: Bool, icons: TelegramIconsTheme) -> CGImage {
        return bubbled ? incoming ? icons.poll_selected_incorrect_incoming : icons.poll_selected_incorrect_outgoing : icons.poll_selected_incorrect
    }
    
    public func pollReplyIcon(_ incoming: Bool, _ bubbled: Bool) -> CGImage {
        let color = bubbled ? incoming ? palette.textBubble_incoming : palette.textBubble_outgoing : palette.text
        return generatePollReplyBarIcon(color: color)
    }
    public func pollReplyOptionIcon(_ incoming: Bool, _ bubbled: Bool, isMultiple: Bool = false) -> CGImage {
        let bgColor = bubbled ? incoming ? palette.textBubble_incoming : palette.textBubble_outgoing : palette.text
        let checkColor = bubbled ? incoming ? palette.bubbleBackground_incoming : palette.blendedOutgoingColors : palette.background
        return generatePollReplyCheckIcon(backgroundColor: bgColor, checkColor: checkColor, isMultiple: isMultiple)
    }

    public func channelInfoPromo(_ incoming: Bool, _ bubbled: Bool, icons: TelegramIconsTheme) -> CGImage {
        return bubbled ? incoming ? icons.channel_info_promo_bubble_incoming : icons.channel_info_promo_bubble_outgoing : icons.channel_info_promo
    }
}
