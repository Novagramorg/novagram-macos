import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class SelectionLoopTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func row(_ string: String, layered: Bool) throws -> NSView {
        let layout = TextViewLayout(NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14)]))
        layout.measure(width: 260)
        if layered {
            let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
            let text = ChatLayerTextNode(id: "text", selectable: true)
            text.update(layout)
            try scene.root.setChildren([text])
            scene.selectableTextNodeIds = ["text"]
            return scene
        } else {
            let row = ChatRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
            let text = TextView()
            text.update(layout)
            row.addSubview(text)
            row.selectableTextViews = [text]
            return row
        }
    }

    func testRealSelectionLoopKeepsMixedRowsInOrderInBothDragDirections() throws {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        for mask in 0..<16 {
            for reversed in [false, true] {
                for reversedTable in [false, true] {
                    let referenceTable = SelectionTable(views: try (0..<4).map { try row("row \($0)", layered: false) }, reversed: reversedTable)
                    let table = SelectionTable(views: try (0..<4).map { try row("row \($0)", layered: mask & (1 << $0) != 0) }, reversed: reversedTable)
                    let reference = LegacySelectionLoopHarness(referenceTable)
                    let current = SelectionLoopHarness(table)
                    for (start, end) in [(NSPoint(x: 0, y: 0), NSPoint(x: 300, y: 399)), (NSPoint(x: 10, y: 6), NSPoint(x: 23, y: 306))] {
                        reference.select(begin: reversed ? end : start, end: reversed ? start : end, window: window, reversedTable: reversedTable)
                        current.select(begin: reversed ? end : start, end: reversed ? start : end, window: window, reversedTable: reversedTable)
                        XCTAssertTrue(current.selectManager.selectedText.isEqual(to: reference.selectManager.selectedText), "mask=\(mask), reversed=\(reversed), reversedTable=\(reversedTable): \(current.selectManager.selectedText.string) != \(reference.selectManager.selectedText.string)")
                    }
                }
            }
        }
    }

    func testRealLoopPreservesCustomOffscreenRowsAcrossRepeatedUpdatesAndShrinking() throws {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        for reversed in [false, true] {
            let table = SelectionTable(views: try (0..<4).map { try row("row \($0)", layered: $0 == 1 || $0 == 2) })
            let current = SelectionLoopHarness(table)
            let start = NSPoint(x: 0, y: 0), end = NSPoint(x: 300, y: 399)
            current.select(begin: reversed ? end : start, end: reversed ? start : end, window: window)
            let original = current.selectManager.selectedText
            XCTAssertTrue(original.string.contains("row 1"))
            XCTAssertTrue(original.string.contains("row 2"))
            table.offscreenRows = [1, 2]
            for _ in 0..<5 {
                current.select(begin: reversed ? end : start, end: reversed ? start : end, window: window)
                XCTAssertTrue(current.selectManager.selectedText.isEqual(to: original))
            }
            table.offscreenRows = []
            current.select(begin: reversed ? end : start, end: reversed ? start : end, window: window)
            XCTAssertTrue(current.selectManager.selectedText.isEqual(to: original))
            current.select(begin: NSPoint(x: 0, y: 300), end: end, window: window)
            XCTAssertEqual(current.selectManager.selectedText.string, "row 0")
        }
    }

    func testCapturedLoopLosesOffscreenCustomSelection() throws {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let table = SelectionTable(views: try (0..<3).map { try row("row \($0)", layered: $0 == 1) })
        let original = LegacySelectionLoopHarness(table)
        original.select(begin: .zero, end: NSPoint(x: 300, y: 299), window: window)
        XCTAssertTrue(original.selectManager.selectedText.string.contains("row 1"))
        table.offscreenRows = [1]
        original.select(begin: .zero, end: NSPoint(x: 300, y: 299), window: window)
        XCTAssertFalse(original.selectManager.selectedText.string.contains("row 1"))
    }
}
