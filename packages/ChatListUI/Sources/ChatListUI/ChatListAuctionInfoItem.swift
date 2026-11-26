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
import StarsUI
import InlineStickerLayer

public final class ChatListAuctionInfoItem : GeneralRowItem {
    fileprivate let title: TextViewLayout
    fileprivate let text: TextViewLayout
    fileprivate let info: UIChatListEntry.ChatListAuctionInfo
    fileprivate let context: any AccountContextProtocol
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, info: UIChatListEntry.ChatListAuctionInfo) {
        self.info = info
        self.context = context
        let attr = NSMutableAttributedString()
        
        let title: String
        
        if info.active.count == 1 {
            if let startDate = info.active[0].gift.generic?.auctionStartDate, startDate > context.timestamp {
                title = strings().chatListUpcomingAuction
            } else {
                title = strings().chatListActiveAuctionTitleZeroValueHolder
            }
        } else {
            title = strings().chatListActiveAuctionTitleOther(info.active.count)
        }
        
        
        attr.append(string: TINY_SPACE + title, color: theme.colors.text, font: .medium(.title))
        for active in info.active.reversed().prefix(3) {
            if let file = active.gift.generic?.file {
                attr.insert(.embeddedAnimated(file), at: 0)
            }
        }
        
        self.title = .init(attr)
        
        
        let infoText: String
        let infoColor: NSColor
        if info.active.count == 1 {
            let giftsPerRound = info.active[0].gift.generic?.auctionGiftsPerRound ?? 0

            if let place = info.active[0].place {
                infoText = place <= giftsPerRound
                    ? strings().starAuctionOptionInfoYouAreWinningOther(Int(place))
                    : strings().starAuctionOptionInfoOutbid
                infoColor = place <= giftsPerRound ? theme.colors.grayText : theme.colors.redUI
            } else {
                infoText = strings().starAuctionOptionInfoOutbid
                infoColor = theme.colors.redUI
            }

        } else {
            let allWinning = info.active.filter { value in
                let perRound = value.gift.generic?.auctionGiftsPerRound ?? 0
                let place = value.place ?? .max
                return place <= perRound
            }.count == info.active.count
            
            let outbidCount = info.active.filter { value in
                let perRound = value.gift.generic?.auctionGiftsPerRound ?? 0
                let place = value.place ?? .max
                return place > perRound
            }.count
            
            if allWinning {
                infoText = strings().starAuctionOptionInfoYouAreWinningInAll
                infoColor = theme.colors.grayText
            } else if outbidCount == info.active.count {
                infoText = strings().starAuctionOptionInfoYouHaveBeenOutbidInAll
                infoColor = theme.colors.redUI
            } else {
                infoText = strings().starAuctionOptionInfoOutbidCountableOther(outbidCount)
                infoColor = theme.colors.redUI
            }

        }
        
        self.text = .init(.initialize(string: infoText, color: infoColor, font: .normal(.text)))

        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        title.measure(width: width - 40)
        text.measure(width: width - 40)

        return true
    }
    
    public override var height: CGFloat {
        return 6 + title.layoutSize.height + 2 + text.layoutSize.height + 6
    }
    
    public override func viewClass() -> AnyClass {
        return ChatListAuctionInfoItemView.self
    }
    
    public override var accessibilityLabel: String? {
        return title.attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public override var accessibilityValue: String? {
        return text.attributedString.string
    }
    
    public func invoke() {
        
        let context = self.context
        
        
        if self.info.active.count == 1 {
            
            let value = self.info.active[0]
            let peerId = value.myState.bidPeerId ?? context.peerId
            
            _ = showModalProgress(signal: context.giftAuctionsManager.auctionContext(for: .giftId(value.gift.id)), for: context.window).startStandalone(next: { auctionContext in
                if let auctionContext {
                    showModal(with: Star_AuctionBidController(context: context, peerId: peerId, gift: value.gift.generic!, auctionContext: auctionContext, hideName: true, text: "", entities: []), for: context.window)
                } else {
                    showModalText(for: context.window, text: strings().auctionErrorNotExists)
                }
            })
            
        } else {
            showModal(with: Star_AuctionListController(context: context, activeState: self.info.active), for: context.window)
        }
    }
}

private final class ChatListAuctionInfoItemView : TableRowView {
    private let title = InteractiveTextView()
    private let text = TextView()
    private let control = TextButton()
    private let borderView = View()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(control)
        addSubview(title)
        addSubview(text)
        addSubview(borderView)
        
        title.userInteractionEnabled = false
        title.isEventLess = true
        
        text.isSelectable = false
        text.userInteractionEnabled = false
        text.isEventLess = true
        text.isAccessibilityDecorative = true
        
        control.scaleOnClick = true
        control.autohighlight = false

        control.set(handler: { [weak self] _ in
            guard let item = self?.item as? ChatListAuctionInfoItem else {
                return
            }
            item.invoke()
        }, for: .Click)
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        transition.updateFrame(view: title, frame: CGRect(origin: NSMakePoint(10, 6), size: title.frame.size))
        transition.updateFrame(view: text, frame: CGRect(origin: NSMakePoint(10, title.frame.maxY + 2), size: text.frame.size))
        
        transition.updateFrame(view: control, frame: control.centerFrameY(x: size.width - 10 - control.frame.width))

        transition.updateFrame(view: borderView, frame: NSMakeRect(0, size.height - .borderSize, size.width, .borderSize))
        
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? ChatListAuctionInfoItem else {
            return
        }
        
        borderView.backgroundColor = theme.colors.border
        
        title.set(text: item.title, context: item.context)
        text.update(item.text)
        
        control.set(background: theme.colors.accent, for: .Normal)
        control.set(background: theme.colors.accent.lighter(), for: .Highlight)
        control.set(font: .medium(.text), for: .Normal)
        control.set(color: theme.colors.underSelectedColor, for: .Normal)
        
        control.set(text: "View", for: .Normal)
        control.sizeToFit(NSMakeSize(10, 10))

        control.layer?.cornerRadius = control.frame.height / 2
        
        needsLayout = true
    }
}
