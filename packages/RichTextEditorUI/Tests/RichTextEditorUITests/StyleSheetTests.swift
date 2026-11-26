#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class StyleSheetTests: XCTestCase {
    func test_color_roundTrips() {
        let c = RGBAColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let back = c.nsColor.rgba
        XCTAssertEqual(back.red, 0.2, accuracy: 0.01)
        XCTAssertEqual(back.alpha, 0.8, accuracy: 0.01)
    }

    func test_font_appliesBoldItalicAndSize() {
        let f = FontResolver.font(family: nil, size: 20, bold: true, italic: true)
        XCTAssertEqual(f.pointSize, 20, accuracy: 0.5)
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.italic))
    }

    func test_styleSheet_headingIsLargerThanBody() {
        let sheet = StyleSheet.default
        let h1 = sheet.font(for: .heading1, attributes: .plain)
        let body = sheet.font(for: .body, attributes: .plain)
        XCTAssertGreaterThan(h1.pointSize, body.pointSize)
    }

    func test_headings_areSerifMediumWeight_bodyStaysSans() {
        // WYSIWYG with the chat: headings render in the system serif (New York) at medium weight, body
        // text stays sans — matching ChatRichTextRowItem's header/subheader categories.
        let sheet = StyleSheet.default
        let h1 = sheet.font(for: .heading1, attributes: .plain)
        let body = sheet.font(for: .body, attributes: .plain)
        XCTAssertTrue(h1.fontName.contains("NewYork"), "headings are the system serif, got \(h1.fontName)")
        XCTAssertNotEqual(h1.familyName, NSFont.systemFont(ofSize: h1.pointSize).familyName, "headings are serif, not sans")
        XCTAssertEqual(body.familyName, NSFont.systemFont(ofSize: body.pointSize).familyName, "body stays sans")
        XCTAssertFalse(h1.fontDescriptor.symbolicTraits.contains(.bold), "headings are medium, not bold")
        XCTAssertGreaterThan(headingWeight(h1), NSFont.Weight.regular.rawValue, "headings are heavier than regular")
        XCTAssertGreaterThan(h1.pointSize, body.pointSize)
    }

    func test_boldHeading_staysInTheSerifFamily() {
        // A bold run INSIDE a heading must not jump family mid-line (the renderer resolves it as
        // serif at .bold weight rather than falling through to Georgia).
        let sheet = StyleSheet.default
        let h1 = sheet.font(for: .heading1, attributes: CharacterAttributes(bold: true))
        XCTAssertTrue(h1.fontName.contains("NewYork"), "bold heading stays in the system serif, got \(h1.fontName)")
        XCTAssertTrue(h1.fontDescriptor.symbolicTraits.contains(.bold), "user bold still round-trips as a bold trait")
    }

    private func headingWeight(_ font: NSFont) -> CGFloat {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        return traits?[.weight] as? CGFloat ?? 0
    }

    func test_chatMatchingSizes() {
        let sheet = StyleSheet.default
        XCTAssertEqual(sheet.font(for: .body, attributes: .plain).pointSize, 14, accuracy: 0.5)      // paragraph
        XCTAssertEqual(sheet.font(for: .heading1, attributes: .plain).pointSize, 24, accuracy: 0.5)
        XCTAssertEqual(sheet.font(for: .heading2, attributes: .plain).pointSize, 22, accuracy: 0.5)
        XCTAssertEqual(sheet.font(for: .heading3, attributes: .plain).pointSize, 20, accuracy: 0.5)
        XCTAssertEqual(sheet.font(for: .heading4, attributes: .plain).pointSize, 19, accuracy: 0.5)
        XCTAssertEqual(sheet.font(for: .heading5, attributes: .plain).pointSize, 18, accuracy: 0.5)
        XCTAssertEqual(sheet.font(for: .heading6, attributes: .plain).pointSize, 17, accuracy: 0.5)
        XCTAssertEqual(sheet.font(for: .caption, attributes: .plain).pointSize, 12, accuracy: 0.5)   // caption
    }

    func test_perStyleLineHeightAndCompactHeadingSpacing() {
        let sheet = StyleSheet.default
        let body = sheet.paragraphStyle(for: .body, attributes: .default)
        XCTAssertGreaterThan(body.lineHeightMultiple, 1.0)                 // body gets a line-height bump
        let h1 = sheet.paragraphStyle(for: .heading1, attributes: .default)
        XCTAssertEqual(h1.paragraphSpacingBefore, 0, accuracy: 0.001)       // BlockStack owns heading gaps
        XCTAssertEqual(h1.paragraphSpacing, 0, accuracy: 0.001)
        let caption = sheet.paragraphStyle(for: .caption, attributes: .default)
        XCTAssertGreaterThan(caption.lineHeightMultiple, 1.0)
    }
}
#endif
