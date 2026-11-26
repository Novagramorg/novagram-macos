import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import LocalAnimations
import ChatModeTypes
import LocationUI
import MapKit
import FoundationUtils
import MessageTextUtils

public enum BusinessChatCategory {
    case existingChats
    case newChats
    case contacts
    case nonContacts
}

public struct BusinessSelectChatsRequest {
    public let categories: [BusinessChatCategory]
    public let categoriesTopSeparator: String
    public let categoriesBottomSeparator: String
    public let selected: Set<PeerId>
    public let contacts: Set<PeerId>
    public let limit: Int
    public let limitReachedText: String
    public let excludePeerIds: Set<PeerId>
    public let callback: ([PeerId]) -> Signal<Never, NoError>

    public init(categories: [BusinessChatCategory],
                categoriesTopSeparator: String,
                categoriesBottomSeparator: String,
                selected: Set<PeerId>,
                contacts: Set<PeerId>,
                limit: Int,
                limitReachedText: String,
                excludePeerIds: Set<PeerId>,
                callback: @escaping ([PeerId]) -> Signal<Never, NoError>) {
        self.categories = categories
        self.categoriesTopSeparator = categoriesTopSeparator
        self.categoriesBottomSeparator = categoriesBottomSeparator
        self.selected = selected
        self.contacts = contacts
        self.limit = limit
        self.limitReachedText = limitReachedText
        self.excludePeerIds = excludePeerIds
        self.callback = callback
    }
}

public protocol BusinessStickerPreviewView: NSView {
    func updateBusinessSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol)
}

public protocol BusinessStickerPicker: AnyObject {
    func showStickerPicker(for control: Control)
}

public struct BusinessHooks {
    public let makeStickerPreviewView: (NSRect) -> BusinessStickerPreviewView
    public let makeStickerPicker: (any AccountContextProtocol, @escaping (TelegramMediaFile) -> Void) -> BusinessStickerPicker
    public let makeStickerHeaderRow: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker, NSAttributedString) -> TableRowItem
    public let openCustomChat: (any AccountContextProtocol, ChatMode, ChatInitialAction?) -> Void
    public let shareLink: (any AccountContextProtocol, String) -> Void
    public let selectChats: (any AccountContextProtocol, BusinessSelectChatsRequest) -> Void

    public init(makeStickerPreviewView: @escaping (NSRect) -> BusinessStickerPreviewView,
                makeStickerPicker: @escaping (any AccountContextProtocol, @escaping (TelegramMediaFile) -> Void) -> BusinessStickerPicker,
                makeStickerHeaderRow: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker, NSAttributedString) -> TableRowItem,
                openCustomChat: @escaping (any AccountContextProtocol, ChatMode, ChatInitialAction?) -> Void,
                shareLink: @escaping (any AccountContextProtocol, String) -> Void,
                selectChats: @escaping (any AccountContextProtocol, BusinessSelectChatsRequest) -> Void) {
        self.makeStickerPreviewView = makeStickerPreviewView
        self.makeStickerPicker = makeStickerPicker
        self.makeStickerHeaderRow = makeStickerHeaderRow
        self.openCustomChat = openCustomChat
        self.shareLink = shareLink
        self.selectChats = selectChats
    }

    private static var value: BusinessHooks?

    public static var shared: BusinessHooks {
        guard let value = value else {
            preconditionFailure("BusinessHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: BusinessHooks) {
        self.value = hooks
    }
}

public func installBusinessHooks(_ hooks: BusinessHooks) {
    BusinessHooks.install(hooks)
}
