import Cocoa
import Postbox
import TelegramCore
import MessageUtils
import TelegramUtils

public struct SearchMessagesResultState : Equatable {
    public static func == (lhs: SearchMessagesResultState, rhs: SearchMessagesResultState) -> Bool {
        if lhs.query != rhs.query {
            return false
        }
        if lhs.messages.count != rhs.messages.count {
            return false
        } else {
            for i in 0 ..< lhs.messages.count {
                if !isEqualMessages(lhs.messages[i], rhs.messages[i]) {
                    return false
                }
            }
        }
        return true
    }

    public let query: String
    public let messages: [Message]
    public init(_ query: String, _ messages: [Message]) {
        self.query = query
        self.messages = messages
    }

    public func containsMessage(_ message: Message) -> Bool {
        return self.messages.contains(where: { $0.id == message.id })
    }
}
