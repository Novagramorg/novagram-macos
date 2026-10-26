import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramContext

// Novagram ads v2. The ads logic (NovagramAds SDK, our backend) lives in the app target, because the SDK
// binary is linked to the app only. Telegram packages (ChatUI, GalleryUI, ChatListUI) call these closures;
// the app installs them. Defaults keep upstream behaviour: none of our ads, Telegram's ads untouched.
public struct NovagramAdsHooks {
    public typealias ChatAdState = (fixed: Message?, opportunistic: [Message], version: Int)
    public typealias VideoAdState = (interPostInterval: Int32?, messages: [Message], startDelay: Int32?, betweenDelay: Int32?)

    // "Remove all ads" is off by default, so Telegram's sponsored messages load as upstream.
    public var showAds: () -> Bool = { true }

    // Chat (ChatUI)
    public var withInjectedAd: (_ base: Signal<ChatAdState, NoError>, _ context: any AccountContextProtocol, _ peerId: PeerId) -> Signal<ChatAdState, NoError> = { base, _, _ in base }
    public var hideIfOurs: (_ opaqueId: Data) -> Bool = { _ in false }
    public var recordViewIfOurs: (_ opaqueId: Data) -> Bool = { _ in false }
    public var recordClickIfOurs: (_ opaqueId: Data) -> Bool = { _ in false }
    public var recordVideoOpenIfOurs: (_ opaqueId: Data) -> Bool = { _ in false }
    public var reportClickIfOurs: (_ opaqueId: Data, _ context: any AccountContextProtocol) -> Bool = { _, _ in false }
    public var menuItems: (_ opaqueId: Data, _ window: Window) -> [ContextMenuItem]? = { _, _ in nil }
    public var menu: (_ opaqueId: Data, _ window: Window, _ presentation: AppMenu.Presentation) -> ContextMenu? = { _, _, _ in nil }
    // delegate is ChatUI's InteractionContentViewProtocol?, parameters is ChatMediaLayoutParameters?
    public var openMediaIfOurs: (_ message: Message?, _ media: Media?, _ context: (any AccountContextProtocol)?, _ delegate: Any?, _ parameters: Any?) -> Bool = { _, _, _, _, _ in false }

    // Video player (GalleryUI)
    public var videoAdState: (_ context: any AccountContextProtocol, _ message: Message, _ fallback: Signal<VideoAdState, NoError>) -> Signal<VideoAdState, NoError> = { _, _, fallback in fallback }

    // Chat list banner (ChatListUI)
    public var bannerSuggestions: (_ context: any AccountContextProtocol, _ telegram: Signal<[ServerProvidedSuggestion], NoError>) -> Signal<[ServerProvidedSuggestion], NoError> = { _, telegram in telegram }
    public var bannerOpenIfOurs: (_ noticeId: String, _ context: any AccountContextProtocol) -> Bool = { _, _ in false }
    public var bannerDismissIfOurs: (_ noticeId: String, _ context: any AccountContextProtocol) -> Bool = { _, _ in false }
    public var bannerIsOurs: (_ noticeId: String) -> Bool = { _ in false }
    public var bannerCanDismiss: (_ noticeId: String) -> Bool = { _ in true }

    // Global search (ChatListUI)
    public var promotedSearchPeer: (_ context: any AccountContextProtocol, _ query: String) -> Signal<NovagramPromotedSearchPeer?, NoError> = { _, _ in .single(nil) }
    public var searchTelegramFallback: (_ context: any AccountContextProtocol, _ query: String, _ telegram: Signal<[AdPeer], NoError>) -> Signal<[AdPeer], NoError> = { _, _, telegram in telegram }
    public var searchAdLabel: () -> String? = { nil }
    public var searchAdMenu: (_ token: String, _ window: Window) -> ContextMenu? = { _, _ in nil }
    public var searchRecordView: (_ token: String) -> Void = { _ in }
    public var searchRecordClick: (_ token: String) -> Void = { _ in }

    public init() {}

    public static var shared = NovagramAdsHooks()

    public static func install(_ hooks: NovagramAdsHooks) {
        shared = hooks
    }
}

public struct NovagramPromotedSearchPeer: Equatable {
    public let peer: EnginePeer
    public let token: String

    public init(peer: EnginePeer, token: String) {
        self.peer = peer
        self.token = token
    }
}

public extension NovagramAdsHooks {
    static let opaqueIdPrefix = "novagram:"

    static func token(opaqueId: Data) -> String? {
        guard let value = String(data: opaqueId, encoding: .utf8), value.hasPrefix(opaqueIdPrefix) else {
            return nil
        }
        let token = String(value.dropFirst(opaqueIdPrefix.count))
        return token.isEmpty ? nil : token
    }

    static func opaqueId(token: String) -> Data {
        return Data((opaqueIdPrefix + token).utf8)
    }

    static func isOurs(opaqueId: Data) -> Bool {
        return token(opaqueId: opaqueId) != nil
    }

    static func isOurs(message: Message?) -> Bool {
        guard let attribute = message?.attributes.first(where: { $0 is AdMessageAttribute }) as? AdMessageAttribute else {
            return false
        }
        return isOurs(opaqueId: attribute.opaqueId)
    }

    // Our channel ad has no "X": Telegram's "X" opens the Premium "hide ads" path. The "⋯" menu stays.
    static func hideCloseIfOurs(_ message: Message?, close: NSView, separator: NSView) {
        let ours = isOurs(message: message)
        close.isHidden = ours
        if ours {
            separator.isHidden = true
        }
    }
}
