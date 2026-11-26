import Foundation
import AppKit
import Postbox
import TelegramCore
import MtProtoKit
import Colors
import Strings

public struct inAppSecureIdRequest {
    public let peerId: PeerId
    public let scope: String
    public let callback: String?
    public let publicKey: String
    public let nonce: Data
    public let isModern: Bool

    public init(peerId: PeerId, scope: String, callback: String?, publicKey: String, nonce: Data, isModern: Bool) {
        self.peerId = peerId
        self.scope = scope
        self.callback = callback
        self.publicKey = publicKey
        self.nonce = nonce
        self.isModern = isModern
    }
}

public enum WallpaperPreview {
    case color(NSColor)
    case slug(String, WallpaperSettings)
    case gradient(Int64?, [NSColor], WallpaperSettings)
}

public enum ParsedInAppLink {
    case external(link:String, Bool)
    case tonsite(link: String)
    case followResolvedName(link: String, username:String, postId:Int32?, forceProfile: Bool, action:ParsedChatLinkAction?)
    case comments(link: String, username:String, threadId: Int32, commentId: Int32?)
    case topic(link: String, username:String, threadId: Int32, commentId: Int32?)
    case inviteBotToGroup(link: String, username:String, action:ParsedChatLinkAction?, rights: String?, isChannel: Bool)
    case botCommand(String)
    case hashtag(String)
    case shareUrl(link: String, String, String?)
    case joinchat(link: String, String)
    case stickerPack(link: String, ParsedStickerPack, peerId:PeerId?)
    case confirmPhone(link: String, phone: String, hash: String)
    case nothing
    case socks(link: String, ProxyServerSettings)
    case requestSecureId(link: String, value: inAppSecureIdRequest)
    case unsupportedScheme(link: String, path: String)
    case applyLocalization(link: String, value: String)
    case wallpaper(link: String, preview: WallpaperPreview)
    case theme(link: String, name: String)
    case tonTransfer(link: String, data: ParsedWalletUrl)
    case sendGrams(link: String, data: ParsedSendGramsLink)
    case settings(link: String, section: InAppSettingsSection)
    case invoice(link: String, slug: String)
    case premiumOffer(link: String, ref: String?)
    case restorePurchase(link: String)
    case urlAuth(link: String)
    case loginCode(link: String, code: String)
    case folder(link: String, slug: String)
    case story(link: String, username: String, storyId: Int32, messageId: MessageId?)
    case boost(link: String, username: String)
    case gift(link: String, slug: String)
    case businessLink(link: String, slug: String)
    case starsTopup(link: String, amount: Int64, purpose: String)
    case multigift(link: String)
    case nft(link: String, slug: String)
    case joinCall(link: String, slug: String)
    case starsInfo(link: String, isTon: Bool)
    case auction(link: String, slug: String)
    case oauth(link: String, token: String)
    case createBot(link: String, managerUsername: String, botUsername: String, title: String?)
    case addStyle(link: String, slug: String)
    case noPaidMessagesToken(link: String, username: String, token: String)
    case contactToken(link: String, token: String, freeToken: String?)
}

public enum ParsedStickerPack: Equatable {
    case stickers(String)
    case emoji(String)
}

public enum ParsedChatLinkAction: Equatable {
    public enum AlbumKind: Equatable {
        case stories
        case gifts
    }

    case start(parameter: String, behavior: ChatInitialActionBehavior)
    case inputText(text: String, behavior: ChatInitialActionBehavior)
    case source(MessageId, Int32?)
    case joinVoiceChat(String?)
    case attachBot(String, String?, [String]?)
    case makeWebview(appname: String, command: String?)
    case album(album: Int32, mode: AlbumKind)
    case openMedia(Int32?)
    case pollOption(Data)
    case direct
}

public struct InAppLinkParsingOptions {
    public var peerId: PeerId?
    public var messageId: MessageId?
    public var urlAuthDomains: [String]
    public var hasContext: Bool
    public var hasOpenInfo: Bool
    public var hasHashtag: Bool
    public var hasCommand: Bool
    public var hasApplyProxy: Bool
    public var confirm: Bool

    public init(peerId: PeerId? = nil, messageId: MessageId? = nil, urlAuthDomains: [String] = [], hasContext: Bool = false, hasOpenInfo: Bool = false, hasHashtag: Bool = false, hasCommand: Bool = false, hasApplyProxy: Bool = false, confirm: Bool = false) {
        self.peerId = peerId
        self.messageId = messageId
        self.urlAuthDomains = urlAuthDomains
        self.hasContext = hasContext
        self.hasOpenInfo = hasOpenInfo
        self.hasHashtag = hasHashtag
        self.hasCommand = hasCommand
        self.hasApplyProxy = hasApplyProxy
        self.confirm = confirm
    }
}
