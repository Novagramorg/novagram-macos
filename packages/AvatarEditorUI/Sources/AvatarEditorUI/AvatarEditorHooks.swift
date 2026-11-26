import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext

public protocol AvatarStickerPreviewView: NSView {
    func updateSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol)
}

public struct AvatarEditorHooks {
    public let makeStickerPreviewView: (NSRect) -> AvatarStickerPreviewView
    public let makeStickerPicker: (any AccountContextProtocol, @escaping (TelegramMediaFile) -> Void, @escaping (TelegramMediaFile, NSView) -> Void) -> ViewController
    public let makeEmojiPicker: (any AccountContextProtocol, @escaping (TelegramMediaFile) -> Void, @escaping (TelegramMediaFile, NSView) -> Void) -> ViewController
    public let pasteboardUrls: (NSPasteboard, any AccountContextProtocol) -> Signal<[URL], NoError>

    public init(makeStickerPreviewView: @escaping (NSRect) -> AvatarStickerPreviewView,
                makeStickerPicker: @escaping (any AccountContextProtocol, @escaping (TelegramMediaFile) -> Void, @escaping (TelegramMediaFile, NSView) -> Void) -> ViewController,
                makeEmojiPicker: @escaping (any AccountContextProtocol, @escaping (TelegramMediaFile) -> Void, @escaping (TelegramMediaFile, NSView) -> Void) -> ViewController,
                pasteboardUrls: @escaping (NSPasteboard, any AccountContextProtocol) -> Signal<[URL], NoError>) {
        self.makeStickerPreviewView = makeStickerPreviewView
        self.makeStickerPicker = makeStickerPicker
        self.makeEmojiPicker = makeEmojiPicker
        self.pasteboardUrls = pasteboardUrls
    }

    private static var _shared: AvatarEditorHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: AvatarEditorHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("AvatarEditorHooks.install must be called before avatar editor screens are used")
        return .placeholder
    }

    public static func install(_ hooks: AvatarEditorHooks) {
        assert(Thread.isMainThread, "AvatarEditorHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = AvatarEditorHooks(makeStickerPreviewView: { frame in
        AvatarPlaceholderStickerPreviewView(frame: frame)
    }, makeStickerPicker: { _, _, _ in
        ViewController()
    }, makeEmojiPicker: { _, _, _ in
        ViewController()
    }, pasteboardUrls: { _, _ in
        .single([])
    })
}

private final class AvatarPlaceholderStickerPreviewView: View, AvatarStickerPreviewView {
    func updateSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol) {

    }
}
