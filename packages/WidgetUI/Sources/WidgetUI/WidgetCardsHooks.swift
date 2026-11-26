import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import ColorPalette
import TelegramContext

public protocol WidgetCardsStickerView: View {
    func updateWidgetCardsSticker(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool)
}

public struct WidgetCardsHooks {
    public let makeStickerView: (NSRect) -> WidgetCardsStickerView
    public let downloadAndApplyCloudTheme: (any AccountContextProtocol, TelegramTheme, ColorPalette?, Bool) -> Signal<Never, Void>
    public let showStickerPackPreview: (any AccountContextProtocol, String, @escaping () -> Void) -> Void
    public let navigateToChat: (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void

    public init(makeStickerView: @escaping (NSRect) -> WidgetCardsStickerView,
                downloadAndApplyCloudTheme: @escaping (any AccountContextProtocol, TelegramTheme, ColorPalette?, Bool) -> Signal<Never, Void>,
                showStickerPackPreview: @escaping (any AccountContextProtocol, String, @escaping () -> Void) -> Void,
                navigateToChat: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void) {
        self.makeStickerView = makeStickerView
        self.downloadAndApplyCloudTheme = downloadAndApplyCloudTheme
        self.showStickerPackPreview = showStickerPackPreview
        self.navigateToChat = navigateToChat
    }

    private static var _shared: WidgetCardsHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: WidgetCardsHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("WidgetCardsHooks.install must be called before widget cards are used")
        return .placeholder
    }

    public static func install(_ hooks: WidgetCardsHooks) {
        assert(Thread.isMainThread, "WidgetCardsHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = WidgetCardsHooks(
        makeStickerView: { frame in WidgetCardsPlaceholderStickerView(frame: frame) },
        downloadAndApplyCloudTheme: { _, _, _, _ in .complete() },
        showStickerPackPreview: { _, _, _ in },
        navigateToChat: { _, _, _ in }
    )
}

public func installWidgetCardsHooks(_ hooks: WidgetCardsHooks) {
    WidgetCardsHooks.install(hooks)
}

final class WidgetCardsPlaceholderStickerView: View, WidgetCardsStickerView {
    func updateWidgetCardsSticker(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool) {

    }
}
