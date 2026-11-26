#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class ColorAndFontTests: XCTestCase {
    func test_rgba_doesNotCrashOnCatalogColor() {
        // .textBackgroundColor is dynamic — getRed without sRGB normalization would throw.
        let rgba = NSColor.textBackgroundColor.rgba
        XCTAssertTrue((0...1).contains(rgba.red) && (0...1).contains(rgba.alpha))
    }
    func test_rgba_roundTripsDeviceColor() {
        let c = RGBAColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1).nsColor
        let back = c.rgba
        XCTAssertEqual(back.red, 0.2, accuracy: 0.01)
        XCTAssertEqual(back.blue, 0.6, accuracy: 0.01)
    }
    func test_fontResolver_appliesBoldItalicTraits() {
        let f = FontResolver.font(family: nil, size: 14, bold: true, italic: true)
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(f.fontDescriptor.symbolicTraits.contains(.italic))
    }
}
#endif
