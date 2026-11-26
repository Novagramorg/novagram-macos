import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import TelegramTheme
import TelegramContext
import TelegramMediaUtils
import ChatUI

public struct PreviewSenderEmojiSelectedItem : Equatable {
    public enum Selection : Equatable {
        case normal
        case transparent
    }
    public enum Source : Equatable {
        case builtin(String)
        case custom(Int64)
    }
    public let source : Source
    public let type: Selection
    public init(source: Source, type: Selection) {
        self.source = source
        self.type = type
    }
}

public protocol PreviewSenderEmojiesController: ViewController {

}

public struct PreviewSenderUIHooks {
    public let makeEmojies: (any AccountContextProtocol, TelegramPresentationTheme) -> PreviewSenderEmojiesController
    public let updateEmojies: (PreviewSenderEmojiesController, PeerId, @escaping (String, CGRect?) -> Void, @escaping (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void, ChatInteraction) -> Void
    public let showMessageEffectsWindow: (any AccountContextProtocol, PeerId, [PreviewSenderEmojiSelectedItem], @escaping (StickerPackItem, NSRect?) -> Void, NSView & StickerFramesCollector) -> Void

    public init(makeEmojies: @escaping (any AccountContextProtocol, TelegramPresentationTheme) -> PreviewSenderEmojiesController,
                updateEmojies: @escaping (PreviewSenderEmojiesController, PeerId, @escaping (String, CGRect?) -> Void, @escaping (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void, ChatInteraction) -> Void,
                showMessageEffectsWindow: @escaping (any AccountContextProtocol, PeerId, [PreviewSenderEmojiSelectedItem], @escaping (StickerPackItem, NSRect?) -> Void, NSView & StickerFramesCollector) -> Void) {
        self.makeEmojies = makeEmojies
        self.updateEmojies = updateEmojies
        self.showMessageEffectsWindow = showMessageEffectsWindow
    }

    private static var _shared: PreviewSenderUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: PreviewSenderUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("PreviewSenderUIHooks.install must be called before the preview sender is used")
        return .placeholder
    }

    public static func install(_ hooks: PreviewSenderUIHooks) {
        assert(Thread.isMainThread, "PreviewSenderUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = PreviewSenderUIHooks(makeEmojies: { _, _ in
        PreviewSenderPlaceholderEmojiesController()
    }, updateEmojies: { _, _, _, _, _ in
    }, showMessageEffectsWindow: { _, _, _, _, _ in
    })
}

private final class PreviewSenderPlaceholderEmojiesController: ViewController, PreviewSenderEmojiesController {

}
