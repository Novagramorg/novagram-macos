import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import ObjcUtils
import Postbox
import SwiftSignalKit
import DateUtils
import InAppSettings
import BoostUI
import ChatHistoryModel
import LocalAnimations
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils


public final class ChatGiveawayResultRowItem : ChatRowItem {
    
    public let headerText: TextViewLayout
    public let prizesInfo: TextViewLayout

    public let winnerText: TextViewLayout
    public let badge: BadgeNode
    
    public let media: TelegramMediaGiveawayResults
    
    public private(set) var channels: [GiveawayChannel]
    
    public let givePresentation: WPLayoutPresentation

    
    
    public override init(_ initialSize: NSSize, _ chatInteraction: ChatInteraction, _ context: any AccountContextProtocol, _ object: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        
        let isIncoming: Bool = object.message!.isIncoming(context.account, object.renderType == .bubble)

        
        let givePresentation = WPLayoutPresentation(text: theme.chat.textColor(isIncoming, object.renderType == .bubble), activity: .init(main: theme.chat.activityColor(isIncoming, object.renderType == .bubble)), link: theme.chat.linkColor(isIncoming, object.renderType == .bubble), selectText: theme.chat.selectText(isIncoming, object.renderType == .bubble), ivIcon: theme.chat.instantPageIcon(isIncoming, object.renderType == .bubble, presentation: theme), renderType: object.renderType, pattern: nil)
        self.givePresentation = givePresentation

        
        let media = object.message!.media.first! as! TelegramMediaGiveawayResults
        self.media = media
        
    
        
        let header_attr = NSMutableAttributedString()
        _ = header_attr.append(string: strings().chatGiveawayMessageWinnersSelectedTitleOther(Int(media.winnersCount)), color: givePresentation.text, font: .medium(.text))
        header_attr.detectBoldColorInString(with: .medium(.text))
        self.headerText = .init(header_attr, alignment: .center, alwaysStaticItems: true)
        
        
        let prizes_info = NSMutableAttributedString()
        
        var openReplyMessage:(()->Void)? = nil
        
        let attributed = parseMarkdownIntoAttributedString(strings().chatGiveawayMessageWinnersSelectedTextOther(Int(media.winnersCount)), attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.text), textColor: givePresentation.text), bold: MarkdownAttributeSet(font: .bold(.text), textColor: givePresentation.text), link: MarkdownAttributeSet(font: .normal(.text), textColor: givePresentation.link), linkAttribute: { contents in
            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(contents, { url in
                openReplyMessage?()
            }))
        }))
        
        prizes_info.append(attributed)
        prizes_info.detectBoldColorInString(with: .medium(.text))
        self.prizesInfo = .init(prizes_info, alignment: .center, alwaysStaticItems: true)
        self.prizesInfo.interactions = LinkHooks.shared.globalLinkExecutor()
        
        let winners_attr = NSMutableAttributedString()
        
        let winnerText: String
        switch media.prize {
        case .premium:
            winnerText = strings().chatGiveawayMessageWinnersInfoOther(Int(media.winnersCount))
        case .stars(let amount):
            winnerText = strings().chatGiveawayMessageWinnersInfoStarOther(Int(media.winnersCount), strings().chatGiveawayMessageStarsOther(Int(amount)))
        }
        
        _ = winners_attr.append(string: winnerText, color: givePresentation.text, font: .normal(.text))
        winners_attr.detectBoldColorInString(with: .medium(.text))
        self.winnerText = .init(winners_attr, alignment: .center, alwaysStaticItems: true)
        
        
        var under = theme.colors.underSelectedColor

        let badgeText: String
        let color: NSColor
        switch media.prize {
        case .premium:
            badgeText = "X\(media.winnersCount)"
            color = theme.colors.accent
        case let .stars(amount):
            badgeText = "\(amount)"
            color = NSColor(0xFFAC04)
            under = .white
        }

        badge = .init(.initialize(string: badgeText, color: under, font: .avatar(.small)), color, aroundFill: theme.chat.bubbleBackgroundColor(isIncoming, object.renderType == .bubble), additionSize: NSMakeSize(16, 7))
        
        var channels:[GiveawayChannel] = []
        for peerId in media.winnersPeerIds {
            if let peer = object.message?.peers[peerId] {
                let color = isIncoming || object.renderType == .list ? context.peerNameColors.get(peer.namePeerColor ?? .blue).main : theme.colors.accentIconBubble_outgoing
                channels.append(.init(peer: peer, text: .init(.initialize(string: peer.displayTitle, color: color, font: .medium(.text)), maximumNumberOfLines: 1), rect: .zero))
            }
        }
        self.channels = channels
        super.init(initialSize, chatInteraction, context, object, theme: theme)
        
        openReplyMessage = { [weak self] in
            self?.openReplyMessage()
        }
    }
    public override var isForceRightLine: Bool {
        return true
    }
    
    public var giftAnimation: LocalAnimatedSticker {
        switch media.prize {
        case .premium(let months):
            switch months {
            case 12:
                return LocalAnimatedSticker.premium_gift_12
            case 6:
                return LocalAnimatedSticker.premium_gift_6
            case 3:
                return LocalAnimatedSticker.premium_gift_3
            default:
                return LocalAnimatedSticker.premium_gift_3
            }
        case .stars(let amount):
            if amount <= 1000 {
                return LocalAnimatedSticker.premium_gift_3
            } else if amount < 2500 {
                return LocalAnimatedSticker.premium_gift_6
            } else {
                return LocalAnimatedSticker.premium_gift_12
            }
        }
    }
    
    public override var fixedContentSize: Bool {
        return true
    }
    
    public override func makeContentSize(_ width: CGFloat) -> NSSize {
        
        
        let width = min(width, 300)
        
        headerText.measure(width: width)
        prizesInfo.measure(width: width)

        winnerText.measure(width: width)
        
        let w = max(headerText.layoutSize.width, prizesInfo.layoutSize.width, winnerText.layoutSize.width)

        
        
        var height: CGFloat = 100
        
        height += headerText.layoutSize.height
        height += 5
        
        
        height += prizesInfo.layoutSize.height
        height += 10
                
        //channels
        for channel in channels {
            channel.text.measure(width: w - 46)
        }
        var point: CGPoint = NSMakePoint(0, 0)
        var index = 0
        for (i, channel) in channels.enumerated() {
            if point.x + channel.size.width > w || index == 2, point.x != 0 {
                point.x = 0
                point.y += channel.size.height + 5
                index = 0
            }
            channels[i].rect = CGRect(origin: point, size: channel.size)
            point.x = channel.size.width + 5
            index += 1
        }
        
        var lines: [[GiveawayChannel]] = []
        var current:[GiveawayChannel] = []
        var y: CGFloat = 0
        for channel in channels {
            if y != channel.rect.minY, !current.isEmpty {
                lines.append(current)
                current.removeAll()
            }
            current.append(channel)
            y = channel.rect.minY
        }
        if !current.isEmpty {
            lines.append(current)
        }
        
        var i: Int = 0
        for line in lines {
            let line_w: CGFloat = line.last!.rect.maxX
            let startX = floorToScreenPixels(System.backingScale, (w - line_w) / 2)
            if line.count == 1 {
                channels[i].rect.origin.x = startX
                i += 1
            } else {
                for (j, _) in line.enumerated() {
                    if j == 0 {
                        channels[i].rect.origin.x = startX
                    } else {
                        channels[i].rect.origin.x = channels[i - 1].rect.maxX + 5
                    }
                    i += 1
                }
            }
        }

        if let last = channels.last {
            height += last.rect.maxY + 10
        }
        
        height += winnerText.layoutSize.height
                
        return NSMakeSize(w, height)
    }
    
    public func openChannel(_ peerId: PeerId) {
        chatInteraction.openInfo(peerId, true, nil, nil)
    }
    
    public var channelsSize: NSSize {
        let size: NSSize = .zero
        if let last = channels.last {
            return NSMakeSize(contentSize.width, last.rect.maxY)
        }
        return size
    }
    
    public override func viewClass() -> AnyClass {
        return ChatGiveawayResultRowView.self
    }
}


private final class ChatGiveawayResultRowView: ChatRowView {
    
    private let mediaView = MediaAnimatedStickerView(frame: NSMakeRect(0, 0, 90, 90))
    private let headerTextView = TextView()
    private let prizezTextView = TextView()

    private let winnerTextView = TextView()
    
    private let badgeView = View()
    
    private let channels = View()
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(mediaView)
        addSubview(headerTextView)
        addSubview(prizezTextView)
        addSubview(winnerTextView)
        addSubview(channels)
        
        
        addSubview(badgeView)
        
//        headerTextView.userInteractionEnabled = false
        headerTextView.isSelectable = false
        
//        prizezTextView.userInteractionEnabled = false
        prizezTextView.isSelectable = false
        
        winnerTextView.userInteractionEnabled = false
        winnerTextView.isSelectable = false

        
    }
    

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? ChatGiveawayResultRowItem else {
            return
        }
        
        
        mediaView.update(with: item.giftAnimation.file, size: mediaView.frame.size, context: item.context, table: item.table, parameters: item.giftAnimation.parameters, animated: animated)
        
        headerTextView.update(item.headerText)
        prizezTextView.update(item.prizesInfo)
        winnerTextView.update(item.winnerText)
        
        item.badge.view = badgeView
        badgeView.setFrameSize(item.badge.size)
        
        channels.setFrameSize(item.channelsSize)
        
        while channels.subviews.count > item.channels.count {
            channels.subviews.last?.removeFromSuperview()
        }
        while channels.subviews.count < item.channels.count {
            channels.addSubview(GiveawayChannelView(frame: .zero))
        }
        
        for (i, channel) in item.channels.enumerated() {
            let view = channels.subviews[i] as! GiveawayChannelView
            view.update(channel, context: item.context, open: { [weak item] peerId in
                item?.openChannel(peerId)
            })
            view.frame = channel.rect
        }
        
        item.badge.view?.needsDisplay = true
        
    }
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        mediaView.centerX(y: 0)
        badgeView.centerX(y: mediaView.frame.maxY - badgeView.frame.height + 5)
        
        var currentY: CGFloat = mediaView.frame.maxY + 10

        headerTextView.centerX(y: currentY)
        currentY = headerTextView.frame.maxY + 5
        
        self.prizezTextView.centerX(y: currentY)
        currentY = self.prizezTextView.frame.maxY + 10
        
        channels.centerX(y: currentY)
        
        let y: CGFloat = channels.frame.maxY + 10
        winnerTextView.centerX(y: y)
    }
    
    override func contentFrameModifier(_ item: ChatRowItem) -> NSRect {
        return bubbleCenteredContentFrame(item, base: super.contentFrameModifier(item))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

