#if canImport(AppKit)
import AppKit
import XCTest
import RichTextEditorCore
@testable import RichTextEditorUI

@available(macOS 12, *)
final class EditorAppearanceTests: XCTestCase {
    func testDefaultMatchesLegacyLiterals() {
        let a = EditorAppearance.default
        XCTAssertEqual(a.caretColor, NSColor.labelColor)
        XCTAssertEqual(a.selectionFocused, NSColor.selectedTextBackgroundColor)
        XCTAssertEqual(a.selectionUnfocused, NSColor.unemphasizedSelectedTextBackgroundColor)
        XCTAssertEqual(a.background, NSColor.textBackgroundColor)
        XCTAssertEqual(a.linkColor, NSColor.linkColor)
        XCTAssertEqual(a.inlineCodeBackground, NSColor.systemGray.withAlphaComponent(0.15))
        XCTAssertEqual(a.spoilerCoverColor, NSColor.secondaryLabelColor)
    }

    func testMapperUsesAppearanceLinkColor() {
        let mapper = AttributedStringMapper(styleSheet: .default, appearance: EditorAppearance(linkColor: .red))
        var ca = CharacterAttributes()
        ca.link = "https://example.com"
        let dict = mapper.attributes(for: ca, style: .body)
        XCTAssertEqual(dict[.foregroundColor] as? NSColor, NSColor.red)
    }
}
#endif
