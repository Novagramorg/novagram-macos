import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramContext
import TelegramUtils
import ChatModeTypes
import AudioPlayerCore

public struct PeerMediaUIHooks {
    public let getAudioPlayer: (any AccountContextProtocol) -> APController?
    public let showQuickLookPreview: (any AccountContextProtocol, TelegramMediaFile, ChatHistoryEntryId, TableView?) -> Void
    public let makeInlineAudioPlayerContextObject: (APController, any AccountContextProtocol, TableView?, TableView?) -> Any
    public let navigateToChat: (NavigationViewController, any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?) -> Void
    public let pushPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId) -> Void
    public let showInlineAudioPlayer: (APController, any AccountContextProtocol, TableView?, TableView?) -> Void

    public init(getAudioPlayer: @escaping (any AccountContextProtocol) -> APController?,
                showQuickLookPreview: @escaping (any AccountContextProtocol, TelegramMediaFile, ChatHistoryEntryId, TableView?) -> Void,
                makeInlineAudioPlayerContextObject: @escaping (APController, any AccountContextProtocol, TableView?, TableView?) -> Any,
                navigateToChat: @escaping (NavigationViewController, any AccountContextProtocol, ChatLocation, ChatFocusTarget?, ChatInitialAction?) -> Void,
                pushPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId) -> Void,
                showInlineAudioPlayer: @escaping (APController, any AccountContextProtocol, TableView?, TableView?) -> Void) {
        self.getAudioPlayer = getAudioPlayer
        self.showQuickLookPreview = showQuickLookPreview
        self.makeInlineAudioPlayerContextObject = makeInlineAudioPlayerContextObject
        self.navigateToChat = navigateToChat
        self.pushPeerInfo = pushPeerInfo
        self.showInlineAudioPlayer = showInlineAudioPlayer
    }

    private static var _shared: PeerMediaUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: PeerMediaUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("PeerMediaUIHooks.install must be called before shared media screens are used")
        return .placeholder
    }

    public static func install(_ hooks: PeerMediaUIHooks) {
        assert(Thread.isMainThread, "PeerMediaUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = PeerMediaUIHooks(getAudioPlayer: { _ in
        nil
    }, showQuickLookPreview: { _, _, _, _ in
    }, makeInlineAudioPlayerContextObject: { controller, _, _, _ in
        controller
    }, navigateToChat: { _, _, _, _, _ in
    }, pushPeerInfo: { _, _, _ in
    }, showInlineAudioPlayer: { _, _, _, _ in
    })
}
