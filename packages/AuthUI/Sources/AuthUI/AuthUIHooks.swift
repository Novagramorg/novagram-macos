import Cocoa
import TGUIKit
import TelegramCore
import TelegramContext

public enum AuthInAppLink {
    case external(link: String, Bool)
}

public protocol AuthUpdateTabController: ViewController {

}

public struct AuthUIHooks {
    public let makeChatController: (any AccountContextProtocol, ChatLocation) -> ViewController
    public let makeAccountMenuItem: (AccountWithInfo, any AccountContextProtocol, Bool, (() -> Void)?) -> ContextMenuItem
    public let executeInApp: (AuthInAppLink) -> Void
    public let makeUpdateTabController: (any SharedAccountContextProtocol) -> AuthUpdateTabController

    public init(makeChatController: @escaping (any AccountContextProtocol, ChatLocation) -> ViewController,
                makeAccountMenuItem: @escaping (AccountWithInfo, any AccountContextProtocol, Bool, (() -> Void)?) -> ContextMenuItem,
                executeInApp: @escaping (AuthInAppLink) -> Void,
                makeUpdateTabController: @escaping (any SharedAccountContextProtocol) -> AuthUpdateTabController) {
        self.makeChatController = makeChatController
        self.makeAccountMenuItem = makeAccountMenuItem
        self.executeInApp = executeInApp
        self.makeUpdateTabController = makeUpdateTabController
    }

    private static var _shared: AuthUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: AuthUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("AuthUIHooks.install must be called before auth screens are used")
        return .placeholder
    }

    public static func install(_ hooks: AuthUIHooks) {
        assert(Thread.isMainThread, "AuthUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = AuthUIHooks(makeChatController: { _, _ in
        ViewController()
    }, makeAccountMenuItem: { _, _, _, handler in
        ContextMenuItem("", handler: handler)
    }, executeInApp: { _ in
    }, makeUpdateTabController: { _ in
        AuthPlaceholderUpdateTabController()
    })
}

private final class AuthPlaceholderUpdateTabController: ViewController, AuthUpdateTabController {

}
