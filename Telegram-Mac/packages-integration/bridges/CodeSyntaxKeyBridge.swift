import Cocoa
import Postbox
import CodeSyntax

extension CodeSyntaxThemeKey {
    init(_ theme: SyntaxterTheme) {
        self.init(dark: theme.dark, textColor: theme.textColor, textFont: theme.textFont, italicFont: theme.italicFont, mediumFont: theme.mediumFont)
    }
}

extension CodeSyntaxKey {
    init(messageId: MessageId, range: NSRange, language: String, theme: SyntaxterTheme) {
        self.init(messageId: messageId, range: range, language: language, theme: CodeSyntaxThemeKey(theme))
    }
}
