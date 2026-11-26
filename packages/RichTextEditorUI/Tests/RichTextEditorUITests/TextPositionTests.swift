#if canImport(AppKit)
import XCTest
@testable import RichTextEditorUI

@available(macOS 12, *)
final class TextPositionTests: XCTestCase {

    // MARK: - DocumentTextPosition

    func test_position_storesOffset() {
        let p = DocumentTextPosition(7)
        XCTAssertEqual(p.offset, 7)
    }

    // MARK: - DocumentTextRange

    func test_range_startEndOrdering_fromLessThanTo() {
        let r = DocumentTextRange(DocumentTextPosition(2), DocumentTextPosition(5))
        XCTAssertEqual(r.start.offset, 2)
        XCTAssertEqual(r.end.offset, 5)
    }

    func test_range_startEndOrdering_fromGreaterThanTo() {
        // start/end always returns the lower/higher offset regardless of construction order.
        let r = DocumentTextRange(DocumentTextPosition(9), DocumentTextPosition(3))
        XCTAssertEqual(r.start.offset, 3)
        XCTAssertEqual(r.end.offset, 9)
    }

    func test_range_isEmpty_whenEqual() {
        XCTAssertTrue(DocumentTextRange(DocumentTextPosition(4), DocumentTextPosition(4)).isEmpty)
    }

    func test_range_isEmpty_whenNotEqual() {
        XCTAssertFalse(DocumentTextRange(DocumentTextPosition(2), DocumentTextPosition(5)).isEmpty)
    }
}
#endif
