import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import Localization

public struct LogoutHooks {
    public let makeStorageUsageController: (any AccountContextProtocol) -> ViewController
    public let makeChatController: (any AccountContextProtocol, PeerId) -> ViewController
    public let openFaq: (any AccountContextProtocol) -> Void
    public let logoutConfirmationText: (any AccountContextProtocol) -> Signal<String, NoError>

    public init(makeStorageUsageController: @escaping (any AccountContextProtocol) -> ViewController,
                makeChatController: @escaping (any AccountContextProtocol, PeerId) -> ViewController,
                openFaq: @escaping (any AccountContextProtocol) -> Void,
                logoutConfirmationText: @escaping (any AccountContextProtocol) -> Signal<String, NoError>) {
        self.makeStorageUsageController = makeStorageUsageController
        self.makeChatController = makeChatController
        self.openFaq = openFaq
        self.logoutConfirmationText = logoutConfirmationText
    }

    private static var _shared: LogoutHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: LogoutHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("LogoutHooks.install must be called before the logout screen is used")
        return .placeholder
    }

    public static func install(_ hooks: LogoutHooks) {
        assert(Thread.isMainThread, "LogoutHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = LogoutHooks(
        makeStorageUsageController: { _ in ViewController() },
        makeChatController: { _, _ in ViewController() },
        openFaq: { _ in },
        logoutConfirmationText: { _ in .single(strings().accountConfirmLogoutText) }
    )
}
