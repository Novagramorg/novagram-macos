import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class CrossRowSelectionTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install(); System.updateScaleFactor(2) }

    func makeScene(_ string: String, origin: NSPoint = NSPoint(x: 20, y: 30)) throws -> (ChatLayerSceneView, ChatLayerTextNode) {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        scene.layout()
        let node = ChatLayerTextNode(id: "body", selectable: true)
        let layout = TextViewLayout(NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14)]))
        layout.measure(width: 240)
        node.update(layout)
        node.frame.origin = origin
        try scene.root.setChildren([node])
        scene.selectableTextNodeIds = ["body"]
        return (scene, node)
    }

    func selectedString(_ fragments: [ChatBubbleSelectionFragment]) -> String {
        fragments.map { $0.attributedString.attributedSubstring(from: $0.range).string }.joined(separator: "\n")
    }

    func testThreeRowsMatchLegacyBoundaryRangesInBothTableOrdersAndDragDirections() throws {
        var comparisons = 0
        for string in ["First line with words\nSecond line\nLast line", "中文 日本語 한글\n👩🏽‍💻 café 🦆"] {
            for reversed in [false, true] {
                for reversedTable in [false, true] {
                    for startX in [CGFloat(2), 45, 100] {
                        let rows = try (0..<3).map { _ in try makeScene(string) }
                        let start = NSPoint(x: 20 + startX, y: 36)
                        let end = NSPoint(x: 120, y: 356)
                        for (index, pair) in rows.enumerated() {
                            let (scene, node) = pair
                            let a = start.offsetBy(dx: 0, dy: -CGFloat(index) * 160)
                            let b = end.offsetBy(dx: 0, dy: -CGFloat(index) * 160)
                            let fragments = scene.applyBubbleSelection(begin: reversed ? b : a, end: reversed ? a : b, isStartRow: index == (reversedTable ? 2 : 0), isEndRow: index == (reversedTable ? 0 : 2), reversed: reversed != reversedTable)
                            let layout = node.textLayout!
                            let expected: NSRange
                            if index == 0 {
                                expected = layout.selectedRange(startPoint: NSPoint(x: startX, y: 6), currentPoint: NSPoint(x: layout.layoutSize.width, y: .greatestFiniteMagnitude))
                            } else if index == 2 {
                                expected = layout.selectedRange(startPoint: .zero, currentPoint: NSPoint(x: 100, y: 6))
                            } else {
                                expected = NSRange(location: 0, length: layout.attributedString.length)
                            }
                            XCTAssertEqual(fragments.first?.range, expected, "\(string) row \(index), reverse \(reversed), table \(reversedTable)")
                            XCTAssertEqual(selectedString(fragments), layout.attributedString.attributedSubstring(from: expected).string)
                            comparisons += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 72)
    }

    func testRTLRowBoundaryUsesLogicalTextEndRatherThanRightEdgeOfLastLine() throws {
        let (scene, node) = try makeScene("مرحبا English שלום\nمرحبا بالعالم")
        let layout = node.textLayout!
        let point = NSPoint(x: 22, y: 36)
        let lastLine = layout.lines.last!
        for reverse in [false, true] {
            let end = NSPoint(x: 200, y: 150)
            let fragments = scene.applyBubbleSelection(begin: reverse ? end : point, end: reverse ? point : end, isStartRow: true, isEndRow: false, reversed: reverse)
            let range = try XCTUnwrap(fragments.first?.range)
            XCTAssertEqual(NSMaxRange(range), layout.attributedString.length)
            XCTAssertLessThanOrEqual(range.location, lastLine.range.location)
            XCTAssertTrue(selectedString(fragments).hasSuffix("مرحبا بالعالم"))
        }
    }

    func testMultipleParagraphsPreserveOrderAttributesAndPartialOffsetsInOneFragment() throws {
        let (scene, first) = try makeScene("First paragraph")
        let secondPair = try makeScene("Second paragraph")
        let second = secondPair.1
        try secondPair.0.root.setChildren([])
        second.frame.origin.y = 80
        let last = ChatLayerTextNode(id: "last", selectable: true)
        last.update(second.textLayout)
        last.frame.origin = NSPoint(x: 20, y: 80)
        try scene.root.setChildren([first, last])
        scene.selectableTextNodeIds = ["body", "last", "body"]
        let fragments = scene.applyBubbleSelection(begin: NSPoint(x: 50, y: 36), end: NSPoint(x: 80, y: 86), isStartRow: true, isEndRow: true, reversed: false)
        XCTAssertEqual(fragments.count, 1)
        let fragment = try XCTUnwrap(fragments.first)
        XCTAssertEqual(fragment.attributedString.string, "First paragraph\nSecond paragraph")
        XCTAssertNotNil(fragment.attributedString.attribute(.font, at: 0, effectiveRange: nil))
        let expected = first.textLayout!.selectedString.string + "\n" + last.textLayout!.selectedString.string
        XCTAssertEqual(selectedString(fragments), expected)
        XCTAssertGreaterThan(fragment.range.location, 0)
        XCTAssertLessThan(NSMaxRange(fragment.range), fragment.attributedString.length)
    }

    func testSelectionSurvivesFocusTransferAndClearsOnRebindRemovalAndRegistrationChange() throws {
        let (scene, node) = try makeScene("Selected message")
        scene.focus(node)
        func select() {
            _ = scene.applyBubbleSelection(begin: NSPoint(x: 0, y: 0), end: NSPoint(x: 200, y: 150), isStartRow: true, isEndRow: true, reversed: false)
        }
        select()
        scene.focus(nil)
        XCTAssertEqual(node.textLayout!.selectedString.string, "Selected message")
        scene.selectableTextNodeIds = []
        XCTAssertEqual(node.textLayout!.selectedRange.range.location, NSNotFound)
        scene.selectableTextNodeIds = ["body"]
        select()
        let old = node.textLayout!
        node.update(TextViewLayout(NSAttributedString(string: "New message")))
        XCTAssertEqual(old.selectedRange.range.location, NSNotFound)
        node.update(old)
        select()
        try scene.root.setChildren([])
        XCTAssertEqual(old.selectedRange.range.location, NSNotFound)
    }

    func testHiddenDisabledProtectedAndOutsideRowsDoNotProduceCopyFragments() throws {
        let (scene, node) = try makeScene("Protected message")
        func select() -> [ChatBubbleSelectionFragment] {
            scene.applyBubbleSelection(begin: NSPoint(x: 0, y: 0), end: NSPoint(x: 200, y: 150), isStartRow: false, isEndRow: false, reversed: false)
        }
        XCTAssertEqual(selectedString(select()), "Protected message")
        node.textLayout!.mayItems = false
        XCTAssertTrue(select().isEmpty)
        XCTAssertEqual(node.textLayout!.selectedRange.range.location, NSNotFound)
        node.textLayout!.mayItems = true
        node.isHidden = true
        XCTAssertTrue(select().isEmpty)
        node.isHidden = false
        node.isEnabled = false
        XCTAssertTrue(select().isEmpty)
        node.isEnabled = true
        XCTAssertTrue(scene.applyBubbleSelection(begin: NSPoint(x: 0, y: 100), end: NSPoint(x: 200, y: 150), isStartRow: true, isEndRow: true, reversed: false).isEmpty)
        XCTAssertTrue(scene.applyBubbleSelection(begin: NSPoint(x: CGFloat.nan, y: 0), end: NSPoint(x: 200, y: 150), isStartRow: true, isEndRow: true, reversed: false).isEmpty)
        XCTAssertFalse(scene.applyBubbleSelection(begin: NSPoint(x: 19, y: 36), end: NSPoint(x: 200, y: 36), isStartRow: true, isEndRow: true, reversed: false).isEmpty)
    }

    func testUnchangedExternalSelectionDoesNotInvalidateDrawingAgain() throws {
        let (scene, node) = try makeScene("A stable selection")
        func select() {
            _ = scene.applyBubbleSelection(begin: .zero, end: NSPoint(x: 300, y: 150), isStartRow: false, isEndRow: false, reversed: false)
        }
        select()
        node.drawingLayer.display()
        XCTAssertFalse(node.drawingLayer.needsDisplay())
        select()
        XCTAssertFalse(node.drawingLayer.needsDisplay())
        scene.clearBubbleSelection()
        XCTAssertTrue(node.drawingLayer.needsDisplay())
    }

    func testSelectionCallbackRemovingNodeDoesNotReturnAnInvalidCopyRange() throws {
        let (scene, node) = try makeScene("Removed during selection")
        node.onSelectionChanged = { [weak scene] range in
            if range.location != NSNotFound { try! scene?.root.setChildren([]) }
        }
        let fragments = scene.applyBubbleSelection(begin: .zero, end: NSPoint(x: 300, y: 150), isStartRow: false, isEndRow: false, reversed: false)
        XCTAssertTrue(fragments.isEmpty)
        XCTAssertEqual(node.textLayout!.selectedRange.range.location, NSNotFound)
        XCTAssertNil(scene.node(id: "body"))
    }

    func testDocumentDragCopyFocusAndShrinkingSelectionAcrossThreeRows() throws {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 480), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let document = View(frame: NSRect(x: 0, y: 0, width: 300, height: 480))
        window.contentView = document
        let rows = try ["First", "Second", "Third"].map { try makeScene($0) }
        for (index, row) in rows.enumerated() {
            row.0.frame.origin.y = CGFloat(index) * 160
            document.addSubview(row.0)
        }
        let selection = LayerDocumentSelection(document: document, scenes: rows.map { $0.0 })
        selection.bind(to: window)
        var copied = ""
        selection.onCopy = { copied = $0.string }
        XCTAssertTrue(selection.begin(at: NSPoint(x: 20, y: 36)))
        _ = rows[0].0.handlePointer(.down, at: NSPoint(x: 20, y: 36))
        XCTAssertFalse(selection.extend(to: NSPoint(x: 22, y: 37)))
        XCTAssertTrue(selection.extend(to: NSPoint(x: 250, y: 356)))
        XCTAssertTrue(window.firstResponder === selection)
        XCTAssertEqual(selection.selectedText.string, "First\n\nSecond\n\nThird")
        XCTAssertEqual(rows[0].1.textLayout!.selectedString.string, "First")
        selection.copy(nil)
        XCTAssertEqual(copied, "First\n\nSecond\n\nThird")
        XCTAssertTrue(selection.extend(to: NSPoint(x: 250, y: 36)))
        XCTAssertEqual(selection.selectedText.string, "First")
        XCTAssertEqual(rows[1].1.textLayout!.selectedRange.range.location, NSNotFound)
        XCTAssertEqual(rows[2].1.textLayout!.selectedRange.range.location, NSNotFound)
        XCTAssertTrue(selection.finish())
        XCTAssertFalse(selection.extend(to: NSPoint(x: 250, y: 356)))
        XCTAssertFalse(selection.begin(at: NSPoint(x: 290, y: 10)))
        XCTAssertEqual(selection.selectedText.length, 0)
        XCTAssertEqual(rows[0].1.textLayout!.selectedRange.range.location, NSNotFound)
    }
}
