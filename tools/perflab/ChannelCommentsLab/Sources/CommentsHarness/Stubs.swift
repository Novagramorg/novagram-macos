import Cocoa
import TGUIKit

public protocol AccountContextProtocol: AnyObject {}

public final class LabContext: AccountContextProtocol {
    public init() {}
}

public final class Message {
    public init() {}
}

public typealias PeerId = Int64

public protocol Peer: AnyObject {
    var id: PeerId { get }
    func isEqual(_ other: Peer) -> Bool
}

public final class LabPeer: Peer {
    public let id: PeerId
    public let color: NSColor
    public init(id: PeerId, color: NSColor) {
        self.id = id
        self.color = color
    }
    public func isEqual(_ other: Peer) -> Bool {
        return other.id == id
    }
}

public struct Avatar: Comparable, Identifiable {
    public static func < (lhs: Avatar, rhs: Avatar) -> Bool {
        return lhs.index < rhs.index
    }

    public var stableId: PeerId {
        return peer.id
    }

    public static func == (lhs: Avatar, rhs: Avatar) -> Bool {
        if lhs.index != rhs.index {
            return false
        }
        if !lhs.peer.isEqual(rhs.peer) {
            return false
        }
        return true
    }

    public let peer: Peer
    public let index: Int
    public init(peer: Peer, index: Int) {
        self.peer = peer
        self.index = index
    }
}

public final class AvatarContentLayer: SimpleLayer {
    public let peerId: PeerId

    public init(context: any AccountContextProtocol, peer: Peer, message: Message?, synchronousLoad: Bool, size: NSSize, inset: CGFloat = 3) {
        self.peerId = peer.id
        super.init()
        self.frame = CGRect(origin: .zero, size: size)
        self.cornerRadius = size.height / 2
        self.backgroundColor = (peer as? LabPeer)?.color.cgColor ?? NSColor.gray.cgColor
    }

    public override init(layer: Any) {
        self.peerId = (layer as? AvatarContentLayer)?.peerId ?? 0
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func updateLayout(size: NSSize, isClipped: Bool, animated: Bool) {
        self.borderWidth = isClipped ? 1 : 0
        self.borderColor = NSColor.white.cgColor
    }
}

public func labImage(width: Int, height: Int, color: NSColor) -> CGImage {
    let scale = 2
    let context = CGContext(data: nil, width: width * scale, height: height * scale, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    context.setFillColor(color.withAlphaComponent(0.5).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: max(1, width / 2), height: max(1, height / 3)))
    return context.makeImage()!
}

public final class LabIcons {
    public var channel_comments_bubble = labImage(width: 18, height: 16, color: .systemRed)
    public var channel_comments_bubble_next = labImage(width: 8, height: 13, color: .systemBlue)
    public var channel_comments_list = labImage(width: 14, height: 12, color: .systemGreen)
    public var channel_comments_overlay = labImage(width: 16, height: 14, color: .systemPurple)
}

public final class LabColors {
    public var accentIconBubble_incoming = NSColor.systemTeal
    public var accentIcon = NSColor.systemBlue
    public var accent = NSColor.systemOrange
}

public struct LabBackgroundMode {
    public var hasWallpaper: Bool
}

public final class LabTheme {
    public var icons = LabIcons()
    public var colors = LabColors()
    public var chat_comments_overlay = labImage(width: 16, height: 14, color: .systemPink)
    public var bubbled = true
    public var backgroundMode = LabBackgroundMode(hasWallpaper: false)
    public var chatServiceItemTextColor = NSColor.white
}

public var theme = LabTheme()

public enum ChatRowItem {
    public static var channelCommentsBubbleHeight: CGFloat {
        return 42
    }
    public static var channelCommentsHeight: CGFloat {
        return 16
    }
}
