import Foundation
import Postbox
import TelegramCore

public struct ChatFocusTarget {
    public var messageId: MessageId
    public var string: String?
    public var range: NSRange?
    public var pollOptionId: Data?
    public var cachedAnchor: Bool = false

     public init?(messageId: MessageId?) {
        if let messageId = messageId {
            self.messageId = messageId
        } else {
            return nil
        }
    }
    public init(messageId: MessageId, string: String?, range: NSRange? = nil, pollOptionId: Data? = nil) {
        self.messageId = messageId
        self.string = string
        self.range = range
        self.pollOptionId = pollOptionId
    }

    public init(messageId: MessageId, quote: EngineMessageReplyQuote?) {
        self.messageId = messageId
        self.string = quote?.text
        if let quote, let offset = quote.offset, offset >= 0, !quote.text.isEmpty {
            self.range = NSRange(location: offset, length: (quote.text as NSString).length)
        } else {
            self.range = nil
        }
    }
}
