import XCTest
import AppKit
@testable import TGUIKit

final class AccessibilityTableReproTests: XCTestCase {
    private var window: NSWindow!
    private var table: TableView!

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        window = NSWindow(contentRect: NSMakeRect(0, 0, 320, 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        table = TableView(frame: NSMakeRect(0, 0, 320, 480))
        window.contentView?.addSubview(table)
        for index in 0 ..< 30 {
            _ = table.addItem(item: TableRowItem(NSMakeSize(320, 60), stableId: index))
        }
        table.layoutSubtreeIfNeeded()
    }

    override func tearDown() {
        window.close()
        window = nil
        table = nil
        super.tearDown()
    }

    private func exercise(_ element: NSAccessibilityProtocol, depth: Int = 0) {
        guard depth < 12 else { return }
        _ = element.accessibilityRole()
        _ = element.accessibilityLabel()
        _ = element.accessibilityValue()
        _ = element.accessibilityParent()
        _ = element.accessibilityFrame()
        _ = element.accessibilityIndex()
        _ = element.isAccessibilityElement()
        for child in objcArray(element, "accessibilityChildren") {
            if let child = child as? NSAccessibilityProtocol {
                exercise(child, depth: depth + 1)
            }
        }
    }

    private func exerciseTableProtocol(_ tableView: NSTableView) {
        _ = objcArray(tableView, "accessibilityRows")
        _ = objcArray(tableView, "accessibilityVisibleRows")
        _ = objcArray(tableView, "accessibilitySelectedRows")
        _ = objcArray(tableView, "accessibilityColumns")
        _ = objcArray(tableView, "accessibilityVisibleColumns")
        _ = objcArray(tableView, "accessibilitySelectedColumns")
        _ = tableView.accessibilityHeader()
        _ = tableView.accessibilityRowCount()
        _ = tableView.accessibilityColumnCount()
        _ = objcArray(tableView, "accessibilityVisibleCells")
        _ = objcArray(tableView, "accessibilitySelectedCells")
        for row in 0 ..< 3 {
            _ = tableView.accessibilityCell(forColumn: 0, row: row)
        }
        for row in objcArray(tableView, "accessibilityRows") {
            if let row = row as? NSAccessibilityProtocol {
                exercise(row)
            }
        }
    }

    func testTreeQueriesDoNotRaise() {
        exercise(window.contentView!)
        exercise(table)
        exerciseTableProtocol(table.tableView)
        for index in 0 ..< 10 {
            if let rowView = table.tableView.rowView(atRow: index, makeIfNecessary: false) {
                exercise(rowView)
            }
        }
    }

    func testTreeQueriesWhileRowsAreRemoved() {
        exerciseTableProtocol(table.tableView)
        table.removeAll()
        exerciseTableProtocol(table.tableView)
        for index in 0 ..< 5 {
            _ = table.addItem(item: TableRowItem(NSMakeSize(320, 60), stableId: 100 + index))
        }
        exerciseTableProtocol(table.tableView)
        exercise(window.contentView!)
    }
}

private func objcArray(_ target: Any, _ selectorName: String) -> [Any] {
    let object = target as AnyObject
    let selector = NSSelectorFromString(selectorName)
    guard object.responds(to: selector), let result = object.perform(selector)?.takeUnretainedValue() as? NSArray else {
        return []
    }
    return result.map { $0 }
}
