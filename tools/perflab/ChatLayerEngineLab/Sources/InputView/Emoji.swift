import Cocoa

public struct EmojiFile: Equatable {
    public let revision: Int
    public init(revision: Int) { self.revision = revision }
}
public struct ChatTextCustomEmojiAttribute: Equatable {
    public let fileId: Int64
    public let file: EmojiFile?
    public let emoji: String
    public let color: NSColor?
    public init(fileId: Int64, file: EmojiFile? = nil, emoji: String = "🦆", color: NSColor? = nil) {
        self.fileId = fileId
        self.file = file
        self.emoji = emoji
        self.color = color
    }
}

public final class TextInputTextCustomEmojiAttribute: NSObject {
    public let fileId: Int64
    public init(fileId: Int64) { self.fileId = fileId }
}
