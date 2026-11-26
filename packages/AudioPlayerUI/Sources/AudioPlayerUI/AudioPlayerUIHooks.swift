import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramContext
import AudioPlayerCore

public protocol InlineAudioPlayerInstantVideoPIP: ViewController {

}

public struct AudioPlayerUIHooks {
    public let makeInstantVideoPip: (APController) -> InlineAudioPlayerInstantVideoPIP
    public let updateInstantVideoPip: (InlineAudioPlayerInstantVideoPIP?, TableView, APController) -> Void
    public let hideInstantVideoPip: (InlineAudioPlayerInstantVideoPIP?) -> Void
    public let addGlobalAudioToVisible: (TableView, APController) -> Void
    public let gotoMessage: (any AccountContextProtocol, Message) -> Void
    public let showChatPlayerList: (InlineAudioPlayerView, APChatMusicController, any AccountContextProtocol, Message, Window) -> Void
    public let showProfilePlayerList: (InlineAudioPlayerView, APProfileSavedController, any AccountContextProtocol, FileMediaReference, Window) -> Void
    public let endInlinePlayer: ((any AccountContextProtocol)?, Bool) -> Void
    public let getAudioPlayer: (any AccountContextProtocol) -> APController?
    public let focusSearch: (any AccountContextProtocol, String) -> Void

    public init(makeInstantVideoPip: @escaping (APController) -> InlineAudioPlayerInstantVideoPIP,
                updateInstantVideoPip: @escaping (InlineAudioPlayerInstantVideoPIP?, TableView, APController) -> Void,
                hideInstantVideoPip: @escaping (InlineAudioPlayerInstantVideoPIP?) -> Void,
                addGlobalAudioToVisible: @escaping (TableView, APController) -> Void,
                gotoMessage: @escaping (any AccountContextProtocol, Message) -> Void,
                showChatPlayerList: @escaping (InlineAudioPlayerView, APChatMusicController, any AccountContextProtocol, Message, Window) -> Void,
                showProfilePlayerList: @escaping (InlineAudioPlayerView, APProfileSavedController, any AccountContextProtocol, FileMediaReference, Window) -> Void,
                endInlinePlayer: @escaping ((any AccountContextProtocol)?, Bool) -> Void,
                getAudioPlayer: @escaping (any AccountContextProtocol) -> APController?,
                focusSearch: @escaping (any AccountContextProtocol, String) -> Void) {
        self.makeInstantVideoPip = makeInstantVideoPip
        self.updateInstantVideoPip = updateInstantVideoPip
        self.hideInstantVideoPip = hideInstantVideoPip
        self.addGlobalAudioToVisible = addGlobalAudioToVisible
        self.gotoMessage = gotoMessage
        self.showChatPlayerList = showChatPlayerList
        self.showProfilePlayerList = showProfilePlayerList
        self.endInlinePlayer = endInlinePlayer
        self.getAudioPlayer = getAudioPlayer
        self.focusSearch = focusSearch
    }

    private static var _shared: AudioPlayerUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: AudioPlayerUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("AudioPlayerUIHooks.install must be called before the inline audio player is used")
        return .placeholder
    }

    public static func install(_ hooks: AudioPlayerUIHooks) {
        assert(Thread.isMainThread, "AudioPlayerUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = AudioPlayerUIHooks(makeInstantVideoPip: { _ in
        AudioPlayerUIPlaceholderInstantVideoPIP()
    }, updateInstantVideoPip: { _, _, _ in
    }, hideInstantVideoPip: { _ in
    }, addGlobalAudioToVisible: { _, _ in
    }, gotoMessage: { _, _ in
    }, showChatPlayerList: { _, _, _, _, _ in
    }, showProfilePlayerList: { _, _, _, _, _ in
    }, endInlinePlayer: { _, _ in
    }, getAudioPlayer: { _ in
        nil
    }, focusSearch: { _, _ in
    })
}

private final class AudioPlayerUIPlaceholderInstantVideoPIP: ViewController, InlineAudioPlayerInstantVideoPIP {

}
