import XCTest
import AppKit
@testable import TGUIKit

final class AccessibilityRowParentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testViewInsideRowOfColumnlessTableReportsTheRow() {
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertTrue(table.tableColumns.isEmpty)
        let row = TableRowView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        table.addSubview(row)
        let view = View(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        row.addSubview(view)
        let parent = view.accessibilityParent() as AnyObject?
        XCTAssertTrue(parent === row)
    }

    func testParentIsNilWhenAccessibilityIsOff() {
        let row = TableRowView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let view = View(frame: .zero)
        row.addSubview(view)
        TGUIKitAccessibility.isEnabled = false
        defer { TGUIKitAccessibility.isEnabled = true }
        XCTAssertNil(view.accessibilityParent())
    }
}
