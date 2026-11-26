import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext

public struct ProxyHooks {
    public let currentContext: () -> (any AccountContextProtocol)?

    public init(currentContext: @escaping () -> (any AccountContextProtocol)?) {
        self.currentContext = currentContext
    }

    private static var value: ProxyHooks?

    public static var shared: ProxyHooks {
        guard let value = value else {
            preconditionFailure("ProxyHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: ProxyHooks) {
        self.value = hooks
    }
}

public func installProxyHooks(_ hooks: ProxyHooks) {
    ProxyHooks.install(hooks)
}
