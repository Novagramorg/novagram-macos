import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext

public struct BlockedPeersHooks {
    public let openPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId) -> Void

    public init(openPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId) -> Void) {
        self.openPeerInfo = openPeerInfo
    }

    private static var _shared: BlockedPeersHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: BlockedPeersHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("BlockedPeersHooks.install must be called before the blocked peers screen is used")
        return .placeholder
    }

    public static func install(_ hooks: BlockedPeersHooks) {
        assert(Thread.isMainThread, "BlockedPeersHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = BlockedPeersHooks(
        openPeerInfo: { _, _, _ in }
    )
}
