import Cocoa
import TGUIKit

public final class Account {}
public final class InlineStickersContext {}
public final class Peer {
    public var isFake = false
    public var isScam = false
    public var isPremium = false
    public var isVerified = false
    public var emojiStatus: EmojiStatus?
    public var verificationIconFileId: Int64?
}
public struct EmojiStatus {
    public let fileId: Int64
    public let content: Content
    public enum Content { case plain, starGift(Int, Int, Int, Int, Int, Int32, Int, Int, Int) }
    public init(_ id: Int64, gift: Bool = false) {
        fileId = id
        content = gift ? .starGift(0, 0, 0, 0, 0, 0x123456, 0, 0, 0) : .plain
    }
}
public final class PremiumStatusPeerObservation {
    public private(set) var bindings = 0
    public func update(peer: Peer, account: Account, enabled: Bool, onUpdate: @escaping (Peer) -> Void) { bindings += 1 }
}
public struct MediaId { public let id: Int64 }
public final class TelegramMediaFile {
    public let fileId: MediaId
    public var emojiReference: Int? = nil
    public var paintToText = false
    public init(_ id: Int64) { fileId = MediaId(id: id) }
}
public struct ChatTextCustomEmojiAttribute {
    public let fileId: Int64
    public let file: TelegramMediaFile?
    public let emoji: String
}
public struct LottieColor { public let keyPath: String; public let color: NSColor }
public enum LottiePlayPolicy: Equatable { case loop, playCount(Int) }
public func isDefaultStatusesPackId(_ id: Int?) -> Bool { id == 1 }

public final class InlineStickerItemLayer: SimpleLayer {
    public static var resolvesImmediately = true
    public static var created = 0
    public let account: Account
    public let inlinePacksContext: InlineStickersContext?
    public let policy: LottiePlayPolicy
    public let colors: (TelegramMediaFile?) -> [LottieColor]
    public weak var superview: NSView?
    public let fileId: Int64
    public private(set) var file: TelegramMediaFile? {
        didSet {
            self.didReceiveFileResolutionResult = true
            self.fileDidUpdate?(file)
        }
    }
    private var didReceiveFileResolutionResult = false
    public var hasFileResolutionResult: Bool {
        return didReceiveFileResolutionResult || file != nil
    }
    public var stopped = false
    public var writes = 0
    public var preview: CGImage?
    public var isPlayable: Bool? {
        didSet {
            writes += 1
            if isPlayable == false, let preview { contents = preview }
        }
    }
    public var fileDidUpdate: ((TelegramMediaFile?) -> Void)?
    public init(account: Account, inlinePacksContext: InlineStickersContext?, emoji: ChatTextCustomEmojiAttribute, size: NSSize, playPolicy: LottiePlayPolicy, checkStatus: Bool, getColors: @escaping (TelegramMediaFile?) -> [LottieColor]) {
        InlineStickerItemLayer.created += 1
        self.account = account
        self.inlinePacksContext = inlinePacksContext
        policy = playPolicy
        colors = getColors
        fileId = emoji.fileId
        super.init()
        if InlineStickerItemLayer.resolvesImmediately { self.file = TelegramMediaFile(emoji.fileId) }
        frame = size.bounds
    }
    public func resolve(_ file: TelegramMediaFile?) { self.file = file }
    public required init?(coder: NSCoder) { fatalError() }
}
public final class StarsEffectLayer: SimpleLayer {
    public var writes = 0
    public var isPlaying = true { didSet { writes += 1 } }
    public func update(color: NSColor, size: CGSize) {}
}
private func makeIcon() -> CGImage {
    let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.blue.cgColor)
    context.fillEllipse(in: CGRect(x: 2, y: 2, width: 12, height: 12))
    return context.makeImage()!
}
public struct FixtureIcons {
    private let icon = makeIcon()
    public var verify_dialog_active_left: CGImage { icon }
    public var verifyDialogActive: CGImage { icon }
    public var verify_dialog_left: CGImage { icon }
    public var verifyDialog: CGImage { icon }
    public var scamActive: CGImage { icon }
    public var scam: CGImage { icon }
    public var fakeActive: CGImage { icon }
    public var fake: CGImage { icon }
}
public struct FixtureColors {
    public var accent = NSColor.blue
    public var underSelectedColor = NSColor.white
}
public final class FixtureCache {
    private var images: [Int32: CGImage] = [:]
    public func image(_ key: Int32, _ create: () -> CGImage) -> CGImage {
        if let image = images[key] { return image }
        let image = create()
        images[key] = image
        return image
    }
}
public struct FixtureTheme {
    public let icons = FixtureIcons()
    public var colors = FixtureColors()
    public let resourceCache = FixtureCache()
}
public var theme = FixtureTheme()
public func generatePremium(_ value: Bool, color: NSColor, small: Bool = false) -> CGImage { makeIcon() }
public struct TelegramUtilsHooks {
    public static let shared = TelegramUtilsHooks()
    public enum Lite { case emoji }
    public func isLite(_ mode: Lite) -> Bool { false }
}
