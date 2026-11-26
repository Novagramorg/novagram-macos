import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext

public struct PaymentsHooks {
    public let formatPhoneNumber: (any AccountContextProtocol, String) -> String
    public let meUrlHost: () -> String?

    public init(formatPhoneNumber: @escaping (any AccountContextProtocol, String) -> String,
                meUrlHost: @escaping () -> String?) {
        self.formatPhoneNumber = formatPhoneNumber
        self.meUrlHost = meUrlHost
    }

    private static var value: PaymentsHooks?

    public static var shared: PaymentsHooks {
        guard let value = value else {
            preconditionFailure("PaymentsHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: PaymentsHooks) {
        self.value = hooks
    }
}

public func installPaymentsHooks(_ hooks: PaymentsHooks) {
    PaymentsHooks.install(hooks)
}
