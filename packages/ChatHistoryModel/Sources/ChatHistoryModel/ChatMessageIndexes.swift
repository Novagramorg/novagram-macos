import Cocoa
import Postbox
import TelegramCore
import TGUIKit

public struct QuoteMessageIndex : Hashable {
    public let messageId: MessageId
    public let index: Int
    public init(messageId: MessageId, index: Int) {
        self.messageId = messageId
        self.index = index
    }
}

public struct DetailsMessageIndex : Hashable {
    public let messageId: MessageId
    public let index: Int
    public init(messageId: MessageId, index: Int) {
        self.messageId = messageId
        self.index = index
    }
}

public struct CodeSyntaxThemeKey: Hashable {
    public let dark: Bool
    public let textColor: NSColor
    public let textFont: NSFont
    public let italicFont: NSFont
    public let mediumFont: NSFont
    public init(dark: Bool, textColor: NSColor, textFont: NSFont, italicFont: NSFont, mediumFont: NSFont) {
        self.dark = dark
        self.textColor = textColor
        self.textFont = textFont
        self.italicFont = italicFont
        self.mediumFont = mediumFont
    }
}

public struct CodeSyntaxKey: Hashable {
    public let messageId: MessageId
    public let range: NSRange
    public let language: String
    public let theme: CodeSyntaxThemeKey

    public init(messageId: MessageId, range: NSRange, language: String, theme: CodeSyntaxThemeKey) {
        self.messageId = messageId
        self.range = range
        self.language = language
        self.theme = theme
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(messageId)
        hasher.combine(range)
        hasher.combine(language)
        hasher.combine(theme.textColor.hexString)
    }

    public static func ==(lhs: CodeSyntaxKey, rhs: CodeSyntaxKey) -> Bool {
        if lhs.messageId != rhs.messageId {
            return false
        }
        if lhs.range != rhs.range {
            return false
        }
        if lhs.language != rhs.language {
            return false
        }
        if lhs.theme.textFont != rhs.theme.textFont {
            return false
        }
        if lhs.theme.dark != rhs.theme.dark {
            return false
        }
        if lhs.theme.textColor != rhs.theme.textColor {
            return false
        }
        if lhs.theme.italicFont != rhs.theme.italicFont {
            return false
        }
        if lhs.theme.mediumFont != rhs.theme.mediumFont {
            return false
        }
        return true
    }
}

public struct CodeSyntaxResult : Equatable {
    public let resut: NSAttributedString?

    public init(resut: NSAttributedString?) {
        self.resut = resut
    }

    /// `NSAttributedString` is a class produced once by the syntax loader
    /// and stored in state. The same reference flows through every state
    /// emit until the loader regenerates highlighting for that code block,
    /// so identity (`===`) is a perfect equality signal — and avoids the
    /// expensive value-based `isEqual(_:)` walk over the entire attributed
    /// string (which would touch every glyph + every attribute span).
    /// This `==` is hit per-entry per-diff via the `codeSyntaxData`
    /// dictionary on `MessageEntryAdditionalData`.
    public static func ==(lhs: CodeSyntaxResult, rhs: CodeSyntaxResult) -> Bool {
        return lhs.resut === rhs.resut
    }
}
