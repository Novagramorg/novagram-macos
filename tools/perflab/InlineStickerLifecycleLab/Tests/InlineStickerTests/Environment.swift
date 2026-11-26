import Cocoa
import TGUIKit

public final class Account {}
public final class InlineStickersContext {}
public final class ChatTextCustomEmojiAttribute {}
public final class TelegramMediaFile {}
public struct LottieColor {}
public enum LottiePlayPolicy { case loop, onceEnd, playCount(Int), framesCount(Int) }

public final class InlineStickerItemLayer: SimpleLayer {
    public struct Shimmer { public init(circle: Bool) {} }
    public weak var superview: NSView?
    public var writes = 0
    public var isPlayable: Bool? { didSet { writes += 1 } }
    public let policy: LottiePlayPolicy
    public let ignorePreview: Bool
    public let synchronyous: Bool
    public let file: TelegramMediaFile?
    public let emoji: ChatTextCustomEmojiAttribute?
    public init(account: Account, inlinePacksContext: InlineStickersContext?, emoji: ChatTextCustomEmojiAttribute, size: NSSize, playPolicy: LottiePlayPolicy, getColors: ((TelegramMediaFile) -> [LottieColor])?, shimmerColor: Shimmer) {
        self.emoji = emoji
        file = nil
        policy = playPolicy
        ignorePreview = false
        synchronyous = false
        super.init()
        frame = size.bounds
    }
    public init(account: Account, file: TelegramMediaFile, size: NSSize, playPolicy: LottiePlayPolicy, getColors: ((TelegramMediaFile) -> [LottieColor])?, shimmerColor: Shimmer, ignorePreview: Bool, synchronyous: Bool) {
        self.file = file
        emoji = nil
        policy = playPolicy
        self.ignorePreview = ignorePreview
        self.synchronyous = synchronyous
        super.init()
        frame = size.bounds
    }
    public required init?(coder: NSCoder) { fatalError() }
}
