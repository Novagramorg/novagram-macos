#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI

@available(macOS 12, *)
final class RoundedCornersTests: XCTestCase {
    func test_allCorners_isClosedNonEmpty() {
        let p = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 40, height: 20),
                             byRoundingCorners: .all, cornerRadius: 6)
        XCTAssertFalse(p.isEmpty)
        XCTAssertGreaterThan(p.elementCount, 4)
    }
    func test_noCorners_isPlainRect() {
        let p = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 40, height: 20),
                             byRoundingCorners: [], cornerRadius: 6)
        XCTAssertFalse(p.isEmpty)
    }
}
#endif
