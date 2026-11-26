import Cocoa
import TelegramCore

public struct ChatTextCustomEmojiAttribute : Equatable {

    public let fileId: Int64
    public let file: TelegramMediaFile?
    public let emoji: String
    public let color: NSColor?
    public init(fileId: Int64, file: TelegramMediaFile?, emoji: String, color: NSColor? = nil) {
        self.fileId = fileId
        self.emoji = emoji
        self.file = file
        self.color = color
    }
}

public protocol EmbeddedCustomEmojiAttributeValue {
    var customEmojiAttribute: ChatTextCustomEmojiAttribute? { get }
}
