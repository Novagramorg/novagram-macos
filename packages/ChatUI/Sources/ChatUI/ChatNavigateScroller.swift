import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import TelegramTheme
import Localization


public class ChatNavigationScroller: ImageButton {

    public enum Source {
        case mentions
        case failed
        case reactions
        case pollVotes
        case scroller
        case scrollerUp
        public var image: CGImage {
            switch self {
            case .mentions:
                return theme.icons.chatMention
            case .failed:
                return theme.icons.chat_failed_scroller
            case .reactions:
                return theme.icons.chat_reactions_badge
            case .pollVotes:
                return theme.icons.chat_poll_votes_badge
            case .scroller:
                return theme.icons.chatScrollUp
            case .scrollerUp:
                return theme.icons.chatScrollDown
            }
        }
        public var active: CGImage {
            switch self {
            case .mentions:
                return theme.icons.chatMentionActive
            case .failed:
                return theme.icons.chat_failed_scroller_active
            case .reactions:
                return theme.icons.chat_reactions_badge_active
            case .pollVotes:
                return theme.icons.chat_poll_votes_badge_active
            case .scroller:
                return theme.icons.chatScrollUpActive
            case .scrollerUp:
                return theme.icons.chatScrollDownActive
            }
        }
    }

    private var badge:BadgeNode?
    private var badgeView:View = View()
    private let source: Source
    private var count: Int32 = 0
    public init(_ source: Source) {
        self.source = source
        super.init()
        autohighlight = false
        set(image: source.image, for: .Normal)
        set(image: source.active, for: .Highlight)
        self.setFrameSize(64,64)

        self.layer?.masksToBounds = false
        
        setGlassEffect(size: NSMakeSize(40, 40))
    }

    public func updateCount(_ count: Int32) {
        self.count = count
        if count > 0 {
            badge = BadgeNode(.initialize(string: Int(count).prettyNumber, color: theme.colors.underSelectedColor, font: .bold(.small)), theme.colors.accent)
            badgeView.setFrameSize(badge!.size)
            badge!.view = badgeView
            addSubview(badgeView)
            badgeView.needsDisplay = true
        } else {
            badgeView.removeFromSuperview()
        }
        needsLayout = true
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        set(image: source.image, for: .Normal)
        set(image: source.active, for: .Highlight)
    }

    public override func scrollWheel(with event: NSEvent) {

    }

    public override var accessibilityDefaultLabel: String? {
        switch source {
        case .mentions:
            return strings().voiceOverCommonMentions
        case .failed:
            return strings().voiceOverChatFailed
        case .reactions:
            return strings().voiceOverCommonUnreadReactions
        case .pollVotes:
            return strings().voiceOverChatPollVotes
        case .scroller:
            return strings().voiceOverCommonScrollToBottom
        case .scrollerUp:
            return strings().voiceOverCommonScrollUp
        }
    }

    public override func accessibilityValue() -> Any? {
        guard count > 0 else {
            return nil
        }
        switch source {
        case .scroller:
            return count == 1 ? strings().voiceOverChatUnreadMessagesOne(Int(count)) : strings().voiceOverChatUnreadMessagesOther(Int(count))
        default:
            return Int(count).prettyNumber
        }
    }

    public var hasBadge: Bool {
        return count > 0
    }

    public override func layout() {
        super.layout()
        badgeView.centerX(y:0)
    }


    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }


}


