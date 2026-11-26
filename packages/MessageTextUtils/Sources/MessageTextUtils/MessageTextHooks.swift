import Foundation
import TelegramContext

public struct MessageTextHooks {
    public let currentContext: () -> (any AccountContextProtocol)?

    public init(currentContext: @escaping () -> (any AccountContextProtocol)?) {
        self.currentContext = currentContext
    }

    public static var shared: MessageTextHooks = MessageTextHooks(currentContext: { return nil })
}

public func installMessageTextHooks(_ hooks: MessageTextHooks) {
    MessageTextHooks.shared = hooks
}
