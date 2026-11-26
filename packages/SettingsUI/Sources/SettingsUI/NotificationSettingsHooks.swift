import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext

public enum NotificationAuthorizationStatus: Int {
    case notDetermined = 0
    case denied = 1
    case authorized = 2
    case provisional = 3
}

public struct NotificationSettingsHooks {
    public let authorizationStatus: (any AccountContextProtocol) -> Signal<NotificationAuthorizationStatus, NoError>

    public init(authorizationStatus: @escaping (any AccountContextProtocol) -> Signal<NotificationAuthorizationStatus, NoError>) {
        self.authorizationStatus = authorizationStatus
    }

    private static var _shared: NotificationSettingsHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: NotificationSettingsHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("NotificationSettingsHooks.install must be called before notification settings screens are used")
        return .placeholder
    }

    public static func install(_ hooks: NotificationSettingsHooks) {
        assert(Thread.isMainThread, "NotificationSettingsHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = NotificationSettingsHooks(
        authorizationStatus: { _ in .single(.authorized) }
    )
}
