import Cocoa
import TGUIKit
import TelegramCore
import ColorPalette
import SwiftSignalKit
import Postbox
import TelegramIconsTheme
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils

extension TelegramChatColors {
    public func channelViewsIcon(_ item: ChatRowItem) -> CGImage {
        return item.isStateOverlayLayout ? !item.isInteractiveMedia ? item.presentation.chatChannelViewsOverlayServiceBubble : item.presentation.icons.chatChannelViewsOverlayBubble : item.hasBubble ? item.isIncoming ? item.presentation.icons.chatChannelViewsInBubble_incoming : item.presentation.icons.chatChannelViewsInBubble_outgoing : item.presentation.icons.chatChannelViewsOutBubble
    }
    
    public func paidMessageIcon(_ item: ChatRowItem) -> CGImage {
        return item.isStateOverlayLayout ? !item.isInteractiveMedia ? item.presentation.chatPaidMessageOverlayServiceBubble : item.presentation.icons.chatPaidMessageOverlayBubble : item.hasBubble ? item.isIncoming ? item.presentation.icons.chatPaidMessageInBubble_incoming : item.presentation.icons.chatPaidMessageInBubble_outgoing : item.presentation.icons.chatPaidMessageOutBubble
    }

    public func diceStakeIcon(_ item: ChatRowItem) -> CGImage {
        return item.isStateOverlayLayout ? !item.isInteractiveMedia ? item.presentation.chatDiceStakeOverlayServiceBubble : item.presentation.icons.chatDiceStakeOverlayBubble : item.hasBubble ? item.isIncoming ? item.presentation.icons.chatDiceStakeInBubble_incoming : item.presentation.icons.chatDiceStakeInBubble_outgoing : item.presentation.icons.chatDiceStakeOutBubble
    }

    public func messagePinnedIcon(_ item: ChatRowItem) -> CGImage {
        if item.isStateOverlayLayout {
            if !item.isInteractiveMedia {
                return item.presentation.chat_pinned_message_overlay_service_bubble
            } else {
                return item.presentation.icons.chat_pinned_message_overlay_bubble
            }
        } else {
            return item.hasBubble ? item.isIncoming ? item.presentation.icons.chat_pinned_message_bubble_incoming : item.presentation.icons.chat_pinned_message_bubble_outgoing : item.presentation.icons.chat_pinned_message
        }
    }
    
    public func repliesCountIcon(_ item: ChatRowItem) -> CGImage {
        return item.isStateOverlayLayout ? !item.isInteractiveMedia ? item.presentation.chat_reply_count_overlay_service_bubble : item.presentation.icons.chat_reply_count_overlay : item.hasBubble ? item.isIncoming ? item.presentation.icons.chat_reply_count_bubble_incoming : item.presentation.icons.chat_reply_count_bubble_outgoing : item.presentation.icons.chat_reply_count
    }

    public func stateStateIcon(_ item: ChatRowItem) -> CGImage {
        return item.isFailed ? item.presentation.icons.sentFailed : (item.isStateOverlayLayout ? !item.isInteractiveMedia ? item.presentation.chatReadMarkServiceOverlayBubble1 :  theme.icons.chatReadMarkOverlayBubble1 : item.hasBubble ? item.isIncoming ? item.presentation.icons.chatReadMarkInBubble1_incoming : item.presentation.icons.chatReadMarkInBubble1_outgoing : item.presentation.icons.chatReadMarkOutBubble1)
    }
    public func readStateIcon(_ item: ChatRowItem) -> CGImage {
        return item.isStateOverlayLayout ? !item.isInteractiveMedia ? item.presentation.chatReadMarkServiceOverlayBubble2 : item.presentation.icons.chatReadMarkOverlayBubble2 : item.hasBubble ? item.isIncoming ? item.presentation.icons.chatReadMarkInBubble2_incoming : item.presentation.icons.chatReadMarkInBubble2_outgoing : item.presentation.icons.chatReadMarkOutBubble2
    }
    
    public func quizSolution(_ item: ChatRowItem) -> CGImage {
        return item.hasBubble ? item.isIncoming ? item.presentation.icons.chat_quiz_explanation_bubble_incoming : item.presentation.icons.chat_quiz_explanation_bubble_outgoing : item.presentation.icons.chat_quiz_explanation
    }
    
    public func instantPageIcon(_ incoming: Bool, _ bubbled: Bool, presentation: TelegramPresentationTheme) -> CGImage {
        return bubbled ? incoming ? presentation.icons.chatInstantViewBubble_incoming : presentation.icons.chatInstantViewBubble_outgoing : presentation.icons.chatInstantView
    }
    
    public func sendingFrameIcon(_ item: ChatRowItem) -> CGImage {
        return item.isStateOverlayLayout ? !item.isInteractiveMedia ? item.presentation.chatSendingOverlayServiceFrame : item.presentation.icons.chatSendingOverlayFrame : item.hasBubble ? item.isIncoming ? item.presentation.icons.chatSendingInFrame_incoming : item.presentation.icons.chatSendingInFrame_outgoing : item.presentation.icons.chatSendingOutFrame
    }
    public func sendingHourIcon(_ item: ChatRowItem) -> CGImage {
        return item.isStateOverlayLayout ? !item.isInteractiveMedia ? item.presentation.chatSendingOverlayServiceHour : item.presentation.icons.chatSendingOverlayHour : item.hasBubble ? item.isIncoming ? item.presentation.icons.chatSendingInHour_incoming : item.presentation.icons.chatSendingInHour_outgoing : item.presentation.icons.chatSendingOutHour
    }
    public func sendingMinIcon(_ item: ChatRowItem) -> CGImage {
        return item.isStateOverlayLayout ? !item.isInteractiveMedia ? item.presentation.chatSendingOverlayServiceMin : item.presentation.icons.chatSendingOverlayMin : item.hasBubble ? item.isIncoming ? item.presentation.icons.chatSendingInMin_incoming : item.presentation.icons.chatSendingInMin_outgoing : item.presentation.icons.chatSendingOutMin
    }
    
    public func chatCallIcon(_ item: ChatCallRowItem) -> CGImage {
        if item.hasBubble {
            return !item.isIncoming ? (item.failed ? item.presentation.icons.chatFailedCallBubble_outgoing : item.presentation.icons.chatCallBubble_outgoing) : (item.failed ? item.presentation.icons.chatFailedCallBubble_incoming : item.presentation.icons.chatCallBubble_outgoing)
        } else {
            return !item.isIncoming ? (item.failed ? item.presentation.icons.chatFailedCall_outgoing : item.presentation.icons.chatCall_outgoing) : (item.failed ? item.presentation.icons.chatFailedCall_incoming : item.presentation.icons.chatCall_outgoing)
        }
    }
    
    public func chatCallFallbackIcon(_ item: ChatCallRowItem) -> CGImage {
        if item.isVideo {
            return item.hasBubble ? item.isIncoming ? item.presentation.icons.chatFallbackVideoCallBubble_incoming : item.presentation.icons.chatFallbackVideoCallBubble_outgoing : item.presentation.icons.chatFallbackVideoCall
        } else {
            return item.hasBubble ? item.isIncoming ? item.presentation.icons.chatFallbackCallBubble_incoming : item.presentation.icons.chatFallbackCallBubble_outgoing : item.presentation.icons.chatFallbackCall
        }
    }
    
    public func peerName(_ index: Int) -> NSColor {
        let array = [theme.colors.groupPeerNameRed,
                     theme.colors.groupPeerNameOrange,
                     theme.colors.groupPeerNameViolet,
                     theme.colors.groupPeerNameGreen,
                     theme.colors.groupPeerNameCyan,
                     theme.colors.groupPeerNameLightBlue,
                     theme.colors.groupPeerNameBlue]
        
        return array[index]
    }
    
    public func replyTitle(_ item: ChatRowItem) -> PeerNameColors.Colors {
        
        var hasSecondary: Bool = false
        var hasTertiary: Bool = false
        
        if let message = item.message, let replyAttr = message.replyAttribute, let replyMessage = message.associatedMessages[replyAttr.messageId], let author = replyMessage.effectiveAuthor {
            let accept = item.isIncoming || item.renderType == .list
            if let nameColor = author.nameColor {
                let color = nameColor.nameColors(item.context)
                if accept {
                    return color
                }
                hasSecondary = color.secondary != nil
                hasTertiary = color.tertiary != nil
            }
        }
        let color = item.hasBubble ? (item.isIncoming ? item.presentation.colors.chatReplyTitleBubble_incoming : item.presentation.colors.chatReplyTitleBubble_outgoing) : item.presentation.colors.chatReplyTitle
        
        let secondary = hasSecondary ? color : nil
        let tertiary = hasTertiary ? color : nil

        return .init(main: color, secondary: secondary, tertiary: tertiary)

    }
    
    public func blockColor(_ colors: PeerNameColors, message: Message, isIncoming: Bool, bubbled: Bool) -> PeerNameColors.Colors {
        var hasSecondary: Bool = false
        var hasTertiary: Bool = false
        var author: Peer?
        if let forwardInfo = message.forwardInfo {
            author = forwardInfo.author
        } else {
            author = message.effectiveAuthor
        }
        if let author = author {
            if let nameColor = author.nameColor {
                let color =  nameColor.nameColors(colors)
                if isIncoming || !bubbled {
                    return color
                }
                hasSecondary = color.secondary != nil
                hasTertiary = color.tertiary != nil
            }
        }
        let color = bubbled ? (isIncoming ? self.palette.chatReplyTitleBubble_incoming : self.palette.chatReplyTitleBubble_outgoing) : self.palette.chatReplyTitle
        
        let secondary = hasSecondary ? color.withAlphaComponent(0.2) : nil
        let tertiary = hasTertiary ? color.withAlphaComponent(0.2) : nil

        return .init(main: color, secondary: secondary, tertiary: tertiary)
    }
    
    
    public func replyPattern(_ item: ChatRowItem) -> Int64? {
        return replyPattern(item.message)
    }
    
    public func replyPattern(_ message: Message?) -> Int64? {
        if let message = message, let replyAttr = message.replyAttribute, let replyMessage = message.associatedMessages[replyAttr.messageId], let author = replyMessage.effectiveAuthor {
            if let name = author.nameColor {
                switch name {
                case let .collectible(value):
                    return value.backgroundEmojiId
                default:
                    return author.backgroundEmojiId
                }
            }
            return author.backgroundEmojiId
        }
        return nil
    }
    
    public func replyGiftEmojiId(_ item: ChatRowItem) -> Int64? {
        return replyGiftEmojiId(item.message)
    }
    
    public func replyGiftEmojiId(_ message: Message?) -> Int64? {
        if let message = message, let replyAttr = message.replyAttribute, let replyMessage = message.associatedMessages[replyAttr.messageId], let author = replyMessage.effectiveAuthor {
            if let name = author.nameColor {
                switch name {
                case let .collectible(value):
                    return value.giftEmojiFileId
                default:
                    break
                }
            }
        }
        return nil
    }
    
    public func webPreviewPattern(_ message: Message?) -> Int64? {
        if let message = message, let author = message.author {
            if let name = author.nameColor {
                switch name {
                case let .collectible(value):
                    return value.backgroundEmojiId
                default:
                    return author.backgroundEmojiId
                }
            }
        }
        return nil
    }
    
    private static let quoteBaseImage: NSImage = TelegramThemeHooks.shared.image(.iconQuote)

    public func replyQuote(_ item: ChatRowItem) -> CGImage {
        if let message = item.message, let replyAttr = message.replyAttribute, let replyMessage = message.associatedMessages[replyAttr.messageId], let author = replyMessage.effectiveAuthor {
            if item.isIncoming || item.renderType == .list {
                if let nameColor = author.namePeerColor {
                    let color = item.context.peerNameColors.get(nameColor).main
                    return item.presentation.resourceCache.image(Int32(bitPattern: color.rgb), {
                        Self.quoteBaseImage.precomposed(color)
                    })
                }
            }
        }
        return item.hasBubble ? (item.isIncoming ? item.presentation.icons.message_quote_bubble_incoming : item.presentation.icons.message_quote_bubble_outgoing) : item.presentation.icons.message_quote_accent
    }
    
    public func replyText(_ item: ChatRowItem) -> NSColor {
        return item.hasBubble ? (item.isIncoming ? item.presentation.colors.chatReplyTextEnabledBubble_incoming : item.presentation.colors.chatReplyTextEnabledBubble_outgoing) : item.presentation.colors.chatReplyTextEnabled
    }
    public func replyDisabledText(_ item: ChatRowItem) -> NSColor {
        return replyTitle(item).main
    }
}
