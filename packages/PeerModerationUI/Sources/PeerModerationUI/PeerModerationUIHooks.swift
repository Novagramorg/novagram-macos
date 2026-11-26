import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramContext

public struct PeerModerationUIHooks {
    public let pushPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId) -> Void
    public let makePeerInfoController: (any AccountContextProtocol, Peer) -> ViewController

    public init(pushPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId) -> Void,
                makePeerInfoController: @escaping (any AccountContextProtocol, Peer) -> ViewController) {
        self.pushPeerInfo = pushPeerInfo
        self.makePeerInfoController = makePeerInfoController
    }

    private static var _shared: PeerModerationUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: PeerModerationUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("PeerModerationUIHooks.install must be called before moderation screens are used")
        return .placeholder
    }

    public static func install(_ hooks: PeerModerationUIHooks) {
        assert(Thread.isMainThread, "PeerModerationUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = PeerModerationUIHooks(pushPeerInfo: { _, _, _ in
    }, makePeerInfoController: { _, _ in
        ViewController()
    })
}
