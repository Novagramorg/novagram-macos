import Cocoa
import TGUIKit
import TelegramContext
import InputView

public enum PlayPolicy: Equatable { case loop, once }
public final class InlineStickerItem: NSObject {
    public enum Source {
        case attribute(ChatTextCustomEmojiAttribute)
        case avatar(Int)
        case rendered(CGImage)
        case reference(Int)
    }
    public let source: Source
    public let playPolicy: PlayPolicy?
    public init(source: Source, playPolicy: PlayPolicy? = nil) {
        self.source = source
        self.playPolicy = playPolicy
    }
}
public final class InlineStickerItemLayer: SimpleLayer {
    public static var created = 0
    public static var released = 0
    public static var onCreate: ((InlineStickerItemLayer) -> Void)?
    public var playbackAssignments = 0
    public weak var superview: NSView?
    public let textColor: NSColor
    public let color: NSColor?
    public let size: NSSize
    public let source: ChatTextCustomEmojiAttribute
    public let accountId: ObjectIdentifier
    public var isPlayable: Bool? = nil { didSet { playbackAssignments += 1 } }
    public var isVisibleForFetching = false
    public init(account: Account, inlinePacksContext: InlineStickersContext?, emoji: ChatTextCustomEmojiAttribute, size: NSSize, playPolicy: PlayPolicy = .loop, textColor: NSColor) {
        self.textColor = textColor
        self.color = emoji.color
        self.size = size
        self.source = emoji
        self.accountId = ObjectIdentifier(account)
        super.init()
        Self.created += 1
        self.frame = CGRect(origin: .zero, size: size)
        let pixels = 16
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor((emoji.color ?? textColor).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)))
        context.setFillColor(NSColor.yellow.cgColor)
        context.fill(CGRect(x: CGFloat(emoji.file?.revision ?? 2), y: 3, width: 4, height: 5))
        contents = context.makeImage()
        Self.onCreate?(self)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { Self.released += 1 }
}
