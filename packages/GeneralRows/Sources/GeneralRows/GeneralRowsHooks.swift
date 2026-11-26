import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import TelegramMedia
import LocalAnimations
#if SHARE
import TelegramContextShare
#else
import TelegramContext
#endif

public protocol InlineTextRenderer: AnyObject {
    func update(textView: TextView, layout: TextViewLayout, context: any AccountContextProtocol, insetEmoji: CGFloat, emojiOffset: NSPoint, decreaseAvatar: CGFloat)
    func clear()
    func updateAnimatableContent(window: NSWindow?, isLite: Bool)
}

public protocol GeneralRowsAnimatedItemView: NSView {
    func updateAnimatedItem(context: any AccountContextProtocol, file: TelegramMediaFile, size: NSSize, animated: Bool)
    func updateStickerHeader(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, parameters: GeneralRowsStickerParameters?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool)
}

public protocol GeneralRowsStickerParameters: AnyObject {
    var colors: [LottieColor] { get set }
}

public struct GeneralRowsHooks {
    public let linkExecutor: () -> TextViewInteractions
    public let linkAttribute: (String, @escaping (String) -> Void) -> (String, Any)
    public let detectLinks: (NSMutableAttributedString) -> Void
    public let checkSelectedImage: (NSColor, NSColor) -> CGImage?
    public let makeInlineTextRenderer: () -> InlineTextRenderer
    public let makeAnimatedItemView: () -> GeneralRowsAnimatedItemView
    public let makeStickerHeaderView: (NSRect) -> GeneralRowsAnimatedItemView
    public let localStickerParameters: (LocalAnimatedSticker) -> GeneralRowsStickerParameters

    public init(linkExecutor: @escaping () -> TextViewInteractions,
                linkAttribute: @escaping (String, @escaping (String) -> Void) -> (String, Any),
                detectLinks: @escaping (NSMutableAttributedString) -> Void,
                checkSelectedImage: @escaping (NSColor, NSColor) -> CGImage?,
                makeInlineTextRenderer: @escaping () -> InlineTextRenderer,
                makeAnimatedItemView: @escaping () -> GeneralRowsAnimatedItemView,
                makeStickerHeaderView: @escaping (NSRect) -> GeneralRowsAnimatedItemView,
                localStickerParameters: @escaping (LocalAnimatedSticker) -> GeneralRowsStickerParameters) {
        self.linkExecutor = linkExecutor
        self.linkAttribute = linkAttribute
        self.detectLinks = detectLinks
        self.checkSelectedImage = checkSelectedImage
        self.makeInlineTextRenderer = makeInlineTextRenderer
        self.makeAnimatedItemView = makeAnimatedItemView
        self.makeStickerHeaderView = makeStickerHeaderView
        self.localStickerParameters = localStickerParameters
    }

    private static var _shared: GeneralRowsHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: GeneralRowsHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("GeneralRowsHooks.install must be called before general rows are used")
        return .placeholder
    }

    public static func install(_ hooks: GeneralRowsHooks) {
        assert(Thread.isMainThread, "GeneralRowsHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = GeneralRowsHooks(
        linkExecutor: { TextViewInteractions() },
        linkAttribute: { contents, _ in (NSAttributedString.Key.link.rawValue, contents) },
        detectLinks: { _ in },
        checkSelectedImage: { _, backgroundColor in
            generateImage(NSMakeSize(20, 20), contextGenerator: { size, ctx in
                ctx.clear(NSMakeRect(0, 0, size.width, size.height))
                ctx.setFillColor(backgroundColor.cgColor)
                ctx.fillEllipse(in: NSMakeRect(2, 2, size.width - 4, size.height - 4))
            })
        },
        makeInlineTextRenderer: { PlaceholderInlineTextRenderer() },
        makeAnimatedItemView: { PlaceholderAnimatedItemView(frame: .zero) },
        makeStickerHeaderView: { frame in PlaceholderAnimatedItemView(frame: frame) },
        localStickerParameters: { _ in PlaceholderStickerParameters() }
    )
}

private final class PlaceholderInlineTextRenderer: InlineTextRenderer {
    func update(textView: TextView, layout: TextViewLayout, context: any AccountContextProtocol, insetEmoji: CGFloat, emojiOffset: NSPoint, decreaseAvatar: CGFloat) {
    }
    func clear() {
    }
    func updateAnimatableContent(window: NSWindow?, isLite: Bool) {
    }
}

private final class PlaceholderAnimatedItemView: NSView, GeneralRowsAnimatedItemView {
    func updateAnimatedItem(context: any AccountContextProtocol, file: TelegramMediaFile, size: NSSize, animated: Bool) {
    }
    func updateStickerHeader(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, parameters: GeneralRowsStickerParameters?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool) {
    }
}

private final class PlaceholderStickerParameters: GeneralRowsStickerParameters {
    var colors: [LottieColor] = []
}
