import Cocoa
import TGUIKit
import ColorPalette
import ThemeSettings
import DiceCache
import TelegramContext

public struct MediaRenderHooks {
    public let themePreview: (ColorPalette, Wallpaper, TableBackgroundMode) -> CGImage
    public let drawBackground: (TableBackgroundMode, ColorPalette, Bool, NSRect, CGContext) -> Void
    public let topicIcon: (NSSize, [NSColor], [NSColor], String) -> DrawingContext
    public let diceCache: () -> DiceCache?
    public let startModalPreview: (TableView, Window, any AccountContextProtocol) -> Void

    public init(themePreview: @escaping (ColorPalette, Wallpaper, TableBackgroundMode) -> CGImage,
                drawBackground: @escaping (TableBackgroundMode, ColorPalette, Bool, NSRect, CGContext) -> Void,
                topicIcon: @escaping (NSSize, [NSColor], [NSColor], String) -> DrawingContext,
                diceCache: @escaping () -> DiceCache?,
                startModalPreview: @escaping (TableView, Window, any AccountContextProtocol) -> Void) {
        self.themePreview = themePreview
        self.drawBackground = drawBackground
        self.topicIcon = topicIcon
        self.diceCache = diceCache
        self.startModalPreview = startModalPreview
    }

    private static var installed: MediaRenderHooks?

    public static var shared: MediaRenderHooks {
        guard let hooks = installed else {
            fatalError("MediaRenderHooks.install must be called before the media pipeline is used")
        }
        return hooks
    }

    public static func install(_ hooks: MediaRenderHooks) {
        installed = hooks
    }
}
