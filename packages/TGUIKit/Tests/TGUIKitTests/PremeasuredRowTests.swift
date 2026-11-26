import XCTest
import AppKit
@testable import TGUIKit

private final class CountingRowItem: TableRowItem {
    var measured = 0
    private let rowId: AnyHashable
    init(_ initialSize: NSSize, identifier: AnyHashable) {
        self.rowId = identifier
        super.init(initialSize)
    }
    override var stableId: AnyHashable {
        return self.rowId
    }
    override var height: CGFloat {
        return 40
    }
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        self.measured += 1
        return super.makeSize(width, oldWidth: oldWidth)
    }
}

final class PremeasuredRowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testPremeasuredRowsAreNotMeasuredAgainOnInsertAndReplace() {
        let table = TableView(frame: NSMakeRect(0, 0, 300, 400))
        let premeasured = CountingRowItem(table.frame.size, identifier: 1)
        premeasured.premeasuredWidth = 300
        _ = table.insert(item: premeasured, at: 0, redraw: true, animation: .none)
        XCTAssertEqual(premeasured.measured, 0)

        let plain = CountingRowItem(table.frame.size, identifier: 2)
        _ = table.insert(item: plain, at: 1, redraw: true, animation: .none)
        XCTAssertEqual(plain.measured, 1)

        let replacement = CountingRowItem(table.frame.size, identifier: 1)
        replacement.premeasuredWidth = 300
        table.replace(item: replacement, at: 0, animated: false)
        XCTAssertEqual(replacement.measured, 0)

        let otherWidth = CountingRowItem(table.frame.size, identifier: 3)
        otherWidth.premeasuredWidth = 280
        _ = table.insert(item: otherWidth, at: 2, redraw: true, animation: .none)
        XCTAssertEqual(otherWidth.measured, 1)
    }
}

final class TableMergeResultTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testMergeReportsWhetherItAppliedAnything() {
        let table = TableView(frame: NSMakeRect(0, 0, 300, 400))
        let item = TableRowItem(table.frame.size, stableId: AnyHashable(1))
        XCTAssertTrue(table.merge(with: TableUpdateTransition(deleted: [], inserted: [(0, item)], updated: [], state: .none(nil))))
        XCTAssertFalse(table.merge(with: TableUpdateTransition(deleted: [], inserted: [], updated: [], state: .none(nil))))
        XCTAssertTrue(table.merge(with: TableUpdateTransition(deleted: [0], inserted: [], updated: [], state: .none(nil))))
    }
}
