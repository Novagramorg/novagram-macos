import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramMediaUtils

public struct CallSettingsHooks {
    public let devicesContext: (any SharedAccountContextProtocol) -> DevicesContext

    public init(devicesContext: @escaping (any SharedAccountContextProtocol) -> DevicesContext) {
        self.devicesContext = devicesContext
    }

    private static var value: CallSettingsHooks?

    public static var shared: CallSettingsHooks {
        guard let value = value else {
            preconditionFailure("CallSettingsHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: CallSettingsHooks) {
        self.value = hooks
    }
}

public func installCallSettingsHooks(_ hooks: CallSettingsHooks) {
    CallSettingsHooks.install(hooks)
}
