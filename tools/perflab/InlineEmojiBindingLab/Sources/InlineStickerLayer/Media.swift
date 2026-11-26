import Cocoa
import TGUIKit
import TelegramContext
import InputView

public enum PlayPolicy: Equatable { case loop, once, framesCount(Int) }
public struct PeerId {
    public let value: Int64
    public func toInt64() -> Int64 { value }
}
public struct Peer { public let id: PeerId }

public final class InlineStickerItem: NSObject {
    public enum Source {
        case attribute(ChatTextCustomEmojiAttribute)
        case avatar(Peer)
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
    public struct Key: Hashable {
        public let id: Int64
        public let index: Int
        public var color: NSColor?
        public init(id: Int64, index: Int, color: NSColor? = nil) {
            self.id = id
            self.index = index
            self.color = color
        }
    }
    public weak var superview: NSView?
    public let textColor: NSColor
    public let color: NSColor?
    public let size: NSSize
    public let source: ChatTextCustomEmojiAttribute
    public let accountId: ObjectIdentifier
    public var isPlayable: Bool? = nil
    public var isVisibleForFetching = false
    public init(account: Account, inlinePacksContext: InlineStickersContext?, emoji: ChatTextCustomEmojiAttribute, size: NSSize, playPolicy: PlayPolicy = .loop, textColor: NSColor) {
        self.textColor = textColor
        self.color = emoji.color
        self.size = size
        self.source = emoji
        self.accountId = ObjectIdentifier(account)
        super.init()
        self.frame = CGRect(origin: .zero, size: size)
        let pixels = 16
        let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor((emoji.color ?? textColor).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)))
        context.setFillColor(NSColor.yellow.cgColor)
        context.fill(CGRect(x: CGFloat(emoji.file?.revision ?? 2), y: 3, width: 4, height: 5))
        contents = context.makeImage()
    }
    required init?(coder: NSCoder) { fatalError() }
}
