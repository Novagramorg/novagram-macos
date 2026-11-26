import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext

public protocol ComposeChannelVisibilityController: ViewController {
    var onComplete: Promise<PeerId?> { get }
}

public struct ComposeUIHooks {
    public let navigateToChat: (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void
    public let makeChannelVisibilityController: (any AccountContextProtocol, PeerId, Bool, Bool) -> ComposeChannelVisibilityController
    public let openInAppLink: (String) -> Void
    public let makeChatController: (any AccountContextProtocol, PeerId) -> ViewController

    public init(navigateToChat: @escaping (NavigationViewController?, any AccountContextProtocol, ChatLocation) -> Void,
                makeChannelVisibilityController: @escaping (any AccountContextProtocol, PeerId, Bool, Bool) -> ComposeChannelVisibilityController,
                openInAppLink: @escaping (String) -> Void,
                makeChatController: @escaping (any AccountContextProtocol, PeerId) -> ViewController) {
        self.navigateToChat = navigateToChat
        self.makeChannelVisibilityController = makeChannelVisibilityController
        self.openInAppLink = openInAppLink
        self.makeChatController = makeChatController
    }

    private static var _shared: ComposeUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ComposeUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ComposeUIHooks.install must be called before compose screens are used")
        return .placeholder
    }

    public static func install(_ hooks: ComposeUIHooks) {
        assert(Thread.isMainThread, "ComposeUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ComposeUIHooks(navigateToChat: { _, _, _ in
    }, makeChannelVisibilityController: { _, _, _, _ in
        ComposePlaceholderChannelVisibilityController()
    }, openInAppLink: { _ in
    }, makeChatController: { _, _ in
        ViewController()
    })
}

private final class ComposePlaceholderChannelVisibilityController: ViewController, ComposeChannelVisibilityController {
    let onComplete: Promise<PeerId?> = Promise()
}
