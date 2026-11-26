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

public enum PremiumBoardingDoubleItem {
    case channels
    case pinnedChats
    case publicLinks
    case savedGifs
    case favoriteStickers
    case bio
    case captions
    case folders
    case chatsInFolder
    case accounts
    
    public static var all: [PremiumBoardingDoubleItem] {
        return [.channels,
                .pinnedChats,
                .publicLinks,
                .savedGifs,
                .favoriteStickers,
                .bio,
                .captions,
                .folders,
                .chatsInFolder,
                .accounts]
    }
    
    public func title(_ limits: PremiumLimitConfig) -> String {
        switch self {
        case .channels:
            return strings().premiumBoardingDoubleGroupsAndChannels
        case .pinnedChats:
            return strings().premiumBoardingDoublePinnedChats
        case .publicLinks:
            return strings().premiumBoardingDoublePublicLinks
        case .savedGifs:
            return strings().premiumBoardingDoubleSavedGifs
        case .favoriteStickers:
            return strings().premiumBoardingDoubleFavedStickers
        case .bio:
            return strings().premiumBoardingDoubleBio
        case .captions:
            return strings().premiumBoardingDoubleCaptions
        case .folders:
            return strings().premiumBoardingDoubleFolders
        case .chatsInFolder:
            return strings().premiumBoardingDoubleChatsPerFolder
        case .accounts:
            return strings().premiumBoardingDoubleAccounts
        }
    }
    public func info(_ limits: PremiumLimitConfig) -> String {
        switch self {
        case .channels:
            return strings().premiumBoardingDoubleGroupsAndChannelsInfo("\(limits.channels_limit_premium)")
        case .pinnedChats:
            return strings().premiumBoardingDoublePinnedChatsInfo("\(limits.dialog_pinned_limit_premium)")
        case .publicLinks:
            return strings().premiumBoardingDoublePublicLinksInfo("\(limits.channels_public_limit_premium)")
        case .savedGifs:
            return strings().premiumBoardingDoubleSavedGifsInfo("\(limits.saved_gifs_limit_premium)")
        case .favoriteStickers:
            return strings().premiumBoardingDoubleFavedStickersInfo("\(limits.stickers_faved_limit_premium)")
        case .bio:
            return strings().premiumBoardingDoubleBioInfo
        case .captions:
            return strings().premiumBoardingDoubleCaptionsInfo
        case .folders:
            return strings().premiumBoardingDoubleFoldersInfo("\(limits.dialog_filters_limit_premium)")
        case .chatsInFolder:
            return strings().premiumBoardingDoubleChatsPerFolderInfo("\(limits.dialog_filters_chats_limit_premium)")
        case .accounts:
            return strings().premiumBoardingDoubleAccountsInfo("\(4)")
        }
    }
    
    public var color: NSColor {
        switch self {
        case .channels:
            return NSColor(rgb: 0x5ba0ff)
        case .pinnedChats:
            return NSColor(rgb: 0x798aff)
        case .publicLinks:
            return NSColor(rgb: 0x9377ff)
        case .savedGifs:
            return NSColor(rgb: 0xac64f3)
        case .favoriteStickers:
            return NSColor(rgb: 0xc456ae)
        case .bio:
            return NSColor(rgb: 0xcf579a)
        case .captions:
            return NSColor(rgb: 0xdb5887)
        case .folders:
            return NSColor(rgb: 0xdb496f)
        case .chatsInFolder:
            return NSColor(rgb: 0xe95d44)
        case .accounts:
            return NSColor(rgb: 0xf2822a)
        }
    }
    public func defaultLimit(_ limits: PremiumLimitConfig) -> String {
        switch self {
        case .channels:
            return "\(limits.channels_limit_default)"
        case .pinnedChats:
            return "\(limits.dialog_pinned_limit_default)"
        case .publicLinks:
            return "\(limits.channels_public_limit_default)"
        case .savedGifs:
            return "\(limits.saved_gifs_limit_default)"
        case .favoriteStickers:
            return "\(limits.stickers_faved_limit_default)"
        case .bio:
            return "\(limits.about_length_limit_default)"
        case .captions:
            return "\(limits.caption_length_limit_default)"
        case .folders:
            return "\(limits.dialog_filters_limit_default)"
        case .chatsInFolder:
            return "\(limits.dialog_filters_chats_limit_default)"
        case .accounts:
            return "\(normalAccountsLimit)"
        }
    }
    public func premiumLimit(_ limits: PremiumLimitConfig) -> String {
        switch self {
        case .channels:
            return "\(limits.channels_limit_premium)"
        case .pinnedChats:
            return "\(limits.dialog_pinned_limit_premium)"
        case .publicLinks:
            return "\(limits.channels_public_limit_premium)"
        case .savedGifs:
            return "\(limits.saved_gifs_limit_premium)"
        case .favoriteStickers:
            return "\(limits.stickers_faved_limit_premium)"
        case .bio:
            return "\(limits.about_length_limit_premium)"
        case .captions:
            return "\(limits.caption_length_limit_premium)"
        case .folders:
            return "\(limits.dialog_filters_limit_premium)"
        case .chatsInFolder:
            return "\(limits.dialog_filters_chats_limit_premium)"
        case .accounts:
            return "\(normalAccountsLimit + 1)"
        }
    }
}

public final class PremiumBoardingDoubleView: View, PremiumSlideView {
    
    public final class HeaderView: View {
        private let container = View()
        private let titleView = TextView()
        private let presentation: TelegramPresentationTheme
        public required init(frame frameRect: NSRect, presentation: TelegramPresentationTheme) {
            self.presentation = presentation
            super.init(frame: frameRect)            
            
            titleView.userInteractionEnabled = false
            titleView.isSelectable = false
            titleView.isEventLess = true
            
            container.backgroundColor = presentation.colors.background
            container.borderColor = presentation.colors.border
            container.border = [.Bottom]
            container.isEventLess = true

            let layout = TextViewLayout(.initialize(string: strings().premiumBoardingDoubleTitle, color: presentation.colors.text, font: .medium(.header)))
            layout.measure(width: 300)
            
            titleView.update(layout)
            container.addSubview(titleView)
            
            addSubview(container)

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
    public let presentation: TelegramPresentationTheme
    public let tableView: TableView = TableView()
    public required init(frame frameRect: NSRect, presentation: TelegramPresentationTheme) {
        self.presentation = presentation
        self.headerView = HeaderView(frame: .zero, presentation: presentation)
        super.init(frame: frameRect)
        addSubview(tableView)
        addSubview(headerView)
        
        addSubview(bottomBorder)
        bottomBorder.backgroundColor = presentation.colors.border
        tableView.getBackgroundColor = {
            presentation.colors.background
        }
        
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
    
    
    public func initialize(context: (any AccountContextProtocol), initialSize: NSSize) {
        _ = self.tableView.addItem(item: GeneralRowItem(initialSize, height: 15, backgroundColor: presentation.colors.background))
        
        for type in PremiumBoardingDoubleItem.all {
            let item = PremiumBoardingDoubleRowItem(initialSize, presentation: presentation, limits: context.premiumLimits, type: type)
            _ = self.tableView.addItem(item: item)
            _ = self.tableView.addItem(item: GeneralRowItem(initialSize, height: 15, backgroundColor: presentation.colors.background))
        }
        
    }
    
    public func willAppear() {
        
    }
    public func willDisappear() {
        
    }
}
//
