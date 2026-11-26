import Cocoa
import Foundation
import TGUIKit
import TelegramMedia
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import CurrencyFormat
import SceneEffects
import InAppPurchaseManager
import InlineStickers
import ObjcUtils

public final class PremiumBoardingStoryRowItem : GeneralRowItem {
    public let title: TextViewLayout
    public let info: TextViewLayout
    public let itemType: PremiumBoardingExtraFeatureItem
    public let presentation: TelegramPresentationTheme
    public init(_ initialSize: NSSize, type: PremiumBoardingExtraFeatureItem, presentation: TelegramPresentationTheme) {
        self.itemType = type
        self.presentation = presentation
        self.title = .init(.initialize(string: type.title, color: presentation.colors.text, font: .medium(.title)))
        
        
        let info = NSMutableAttributedString()
        _ = info.append(string: type.info, color: presentation.colors.grayText, font: .normal(.text))
        GeneralRowsHooks.shared.detectLinks(info)
        self.info = .init(info)

        super.init(initialSize, stableId: arc4random64())
        _ = makeSize(initialSize.width)
    }
    
    public override var height: CGFloat {
        return title.layoutSize.height + 4 + info.layoutSize.height + 8
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }

    public override var accessibilityValue: String? {
        return info.attributedString.string
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        title.measure(width: width - 100)
        info.measure(width: width - 100)

        return true
    }
    
    public override func viewClass() -> AnyClass {
        return PremiumBoardingStoriesRowView.self
    }
    
}

private final class PremiumBoardingStoriesRowView : TableRowView {
    


    private let titleView = TextView()
    private let infoView = TextView()
    private let imageView = ImageView()
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(infoView)
        addSubview(imageView)
        imageView.isAccessibilityDecorative = true
        titleView.userInteractionEnabled = false
        infoView.userInteractionEnabled = false
        
        titleView.isSelectable = false
        infoView.isSelectable = false
        
    }
    
    public override var backdorColor: NSColor {
        guard let item = item as? PremiumBoardingStoryRowItem else {
            return super.backdorColor
        }
        return item.presentation.colors.background
    }
    
    public override func layout() {
        super.layout()
        imageView.setFrameOrigin(NSMakePoint(20, 0))

        titleView.setFrameOrigin(NSMakePoint(imageView.frame.maxX + 10, 0))
        infoView.setFrameOrigin(NSMakePoint(imageView.frame.maxX + 10, titleView.frame.maxY + 4))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? PremiumBoardingStoryRowItem else {
            return
        }
        titleView.update(item.title)
        infoView.update(item.info)
        
        imageView.image = item.itemType.image
        imageView.sizeToFit()
        
        needsLayout = true

    }
}




public enum PremiumBoardingExtraFeatureItem {
    case priority
    case stealth
    case permanentViews
    case expiratationDuration
    case saveToGallery
    case longerCaption
    case linksAndFormating
    case highQuality
    
    case business_location
    case business_hours
    case business_quick_replies
    case business_greeting_messages
    case business_away_messages
    case business_chatbots
    case business_intro
    case business_links
    
    public static var stories: [PremiumBoardingExtraFeatureItem] {
        return [.priority,
                .stealth,
                .highQuality,
                .permanentViews,
                .expiratationDuration,
                .saveToGallery,
                .longerCaption,
                .linksAndFormating]
    }
    
    public static var business: [PremiumBoardingExtraFeatureItem] {
        return [.business_location,
                .business_hours,
                .business_quick_replies,
                .business_greeting_messages,
                .business_away_messages,
                .business_intro,
                .business_links]
    }
    
    
    
    public var title: String {
        switch self {
        case .priority:
            return strings().premiumBoardingStoriesPriorityOrderTitle
        case .stealth:
            return strings().premiumBoardingStoriesStealthModeTitle
        case .permanentViews:
            return strings().premiumBoardingStoriesPermanentHistoryViewTitle
        case .expiratationDuration:
            return strings().premiumBoardingStoriesExpirationDurationTitle
        case .saveToGallery:
            return strings().premiumBoardingStoriesSaveToGalleryTitle
        case .longerCaption:
            return strings().premiumBoardingStoriesLongerCaptionTitle
        case .linksAndFormating:
            return strings().premiumBoardingStoriesLinkFormattingTitle
        case .highQuality:
            return strings().premiumBoardingStoriesHighQualityTitle
        case .business_location:
            return strings().premiumBoardingBusinessLocation
        case .business_hours:
            return strings().premiumBoardingBusinessOpeningHours
        case .business_quick_replies:
            return strings().premiumBoardingBusinessQuickReplies
        case .business_greeting_messages:
            return strings().premiumBoardingBusinessGreetingMessages
        case .business_away_messages:
            return strings().premiumBoardingBusinessAwayMessages
        case .business_chatbots:
            return strings().premiumBoardingBusinessChatBots
        case .business_intro:
            return strings().premiumBoardingBusinessIntro
        case .business_links:
            return strings().premiumBoardingBusinessLinks
        }
    }
    public var info: String {
        switch self {
        case .priority:
            return strings().premiumBoardingStoriesPriorityOrderInfo
        case .stealth:
            return strings().premiumBoardingStoriesStealthModeInfo
        case .permanentViews:
            return strings().premiumBoardingStoriesPermanentHistoryViewInfo
        case .expiratationDuration:
            return strings().premiumBoardingStoriesExpirationDurationInfo
        case .saveToGallery:
            return strings().premiumBoardingStoriesSaveToGalleryInfo
        case .longerCaption:
            return strings().premiumBoardingStoriesLongerCaptionInfo
        case .linksAndFormating:
            return strings().premiumBoardingStoriesLinkFormattingInfo
        case .highQuality:
            return strings().premiumBoardingStoriesHighQualityInfo
        case .business_location:
            return strings().premiumBoardingBusinessLocationInfo
        case .business_hours:
            return strings().premiumBoardingBusinessOpeningHoursInfo
        case .business_quick_replies:
            return strings().premiumBoardingBusinessQuickRepliesInfo
        case .business_greeting_messages:
            return strings().premiumBoardingBusinessGreetingMessagesInfo
        case .business_away_messages:
            return strings().premiumBoardingBusinessAwayMessagesInfo
        case .business_chatbots:
            return strings().premiumBoardingBusinessChatBotsInfo
        case .business_intro:
            return strings().premiumBoardingBusinessIntroInfo
        case .business_links:
            return strings().premiumBoardingBusinessLinksInfo
        }
    }
    
    public var color: NSColor {
        return .random
    }
    public var image: CGImage {
        switch self {
        case .priority:
            return TelegramThemeHooks.shared.image(.iconPremiumBoardingPriorityOrder).precomposed()
        case .stealth:
            return TelegramThemeHooks.shared.image(.iconPremiumBoardingStealthMode).precomposed()
        case .permanentViews:
            return TelegramThemeHooks.shared.image(.iconPremiumBoardingPermanentViewsHistory).precomposed()
        case .expiratationDuration:
            return TelegramThemeHooks.shared.image(.iconPremiumBoardingExpirationDurations).precomposed()
        case .saveToGallery:
            return TelegramThemeHooks.shared.image(.iconPremiumBoardingSaveStoriesToGallery).precomposed()
        case .longerCaption:
            return TelegramThemeHooks.shared.image(.iconPremiumBoardingLongerCaptions).precomposed()
        case .linksAndFormating:
            return TelegramThemeHooks.shared.image(.iconPremiumBoardingLinksAndFormatting).precomposed()
        case .highQuality:
            return TelegramThemeHooks.shared.image(.iconPremiumBoardingHighQuality).precomposed(NSColor(0x9A64EE))
        case .business_location:
            return TelegramThemeHooks.shared.image(.iconPremiumBusinessFeatureLocation).precomposed()
        case .business_hours:
            return TelegramThemeHooks.shared.image(.iconPremiumBusinessFeatureHours).precomposed()
        case .business_quick_replies:
            return TelegramThemeHooks.shared.image(.iconPremiumBusinessFeatureReply).precomposed()
        case .business_greeting_messages:
            return TelegramThemeHooks.shared.image(.iconPremiumBusinessFeatureGreeting).precomposed()
        case .business_away_messages:
            return TelegramThemeHooks.shared.image(.iconPremiumBusinessFeatureAway).precomposed()
        case .business_chatbots:
            return TelegramThemeHooks.shared.image(.iconPremiumBusinessFeatureBot).precomposed()
        case .business_intro:
            return TelegramThemeHooks.shared.image(.iconPremiumBusinessFeatureIntro).precomposed(NSColor(red: 0.404, green: 0.42, blue: 1, alpha: 1))
        case .business_links:
            return TelegramThemeHooks.shared.image(.iconPremiumBusinessFeatureLinks).precomposed()
        }
    }
}

public final class PremiumBoardingExtraFeaturesView: View, PremiumSlideView {
    
    public final class HeaderView: View {
        private let container = View()
        private let titleView = TextView()
        private let presentation: TelegramPresentationTheme
        public init(frame frameRect: NSRect, presentation: TelegramPresentationTheme) {
            self.presentation = presentation
            super.init(frame: frameRect)
            
            titleView.userInteractionEnabled = false
            titleView.isSelectable = false
            titleView.isEventLess = true
            
            container.backgroundColor = presentation.colors.background
            container.border = [.Bottom]
            container.borderColor = presentation.colors.border
            container.isEventLess = true

            let layout = TextViewLayout(.initialize(string: strings().premiumBoardingStoriesTitle, color: presentation.colors.text, font: .medium(.header)))
            layout.measure(width: 300)
            
            titleView.update(layout)
            container.addSubview(titleView)
            
            addSubview(container)

        }
        
        public func set(string: String) {
            let layout = TextViewLayout(.initialize(string: string, color: presentation.colors.text, font: .medium(.header)))
            layout.measure(width: 300)
            
            titleView.update(layout)
        }
        
        
        public override func layout() {
            super.layout()
            container.frame = bounds
            titleView.center()
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public required init(frame frameRect: NSRect) {
            fatalError("init(frame:) has not been implemented")
        }
    }
    


    public let headerView: HeaderView
    public let bottomBorder = View(frame: .zero)
    
    public let tableView: TableView = TableView()
    public let presentation: TelegramPresentationTheme
    public required init(frame frameRect: NSRect, presentation: TelegramPresentationTheme) {
        self.presentation = presentation
        self.headerView = HeaderView(frame: .zero, presentation: presentation)
        super.init(frame: frameRect)
        addSubview(tableView)
        addSubview(headerView)
        
        tableView.getBackgroundColor = {
            presentation.colors.background
        }
        
        addSubview(bottomBorder)
        bottomBorder.backgroundColor = presentation.colors.border
        
    }
    
    public override func layout() {
        super.layout()
        headerView.frame = NSMakeRect(0, 0, frame.width, 50)
                
        tableView.frame = NSMakeRect(0, headerView.frame.height, frame.width, frame.height - headerView.frame.height)
        self.bottomBorder.frame = NSMakeRect(0, frame.height - .borderSize, frame.width, .borderSize)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    
    public func initialize(context: (any AccountContextProtocol), initialSize: NSSize, list: [PremiumBoardingExtraFeatureItem], title: String) {
        
        self.headerView.set(string: title)
        
        _ = self.tableView.addItem(item: GeneralRowItem(initialSize, height: 15, backgroundColor: presentation.colors.background))
        
        for type in list {
            let item = PremiumBoardingStoryRowItem(initialSize, type: type, presentation: presentation)
            _ = self.tableView.addItem(item: item)
            _ = self.tableView.addItem(item: GeneralRowItem(initialSize, height: 15, backgroundColor: presentation.colors.background))
        }
        
    }
    
    public func willAppear() {
        
    }
    public func willDisappear() {
        
    }
}
