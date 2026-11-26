import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class EmbeddedTextSelectionTests: XCTestCase {
    final class MixedRow: ChatRowView {
        var sources: [ChatTextSelectionSource] = []
        var scenes: [ChatLayerSceneView] = []
        var nativeOnly = false
        override var textSelectionSources: ChatTextSelectionSources { nativeOnly ? .views(selectableTextViews) : .mixed(sources) }
    }

    override func setUp() { TGUIKitTestBootstrap.install() }

    func makeLayout(_ string: String) -> TextViewLayout {
        let text = NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.red])
        let layout = TextViewLayout(text)
        layout.measure(width: 250)
        return layout
    }

    func makeRow(_ index: Int, mask: Int, clipped: Bool = false) throws -> MixedRow {
        let row = MixedRow(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        row.nativeOnly = mask == 0
        row.header = "Author \(index)"
        let scene = ChatLayerSceneView(frame: NSRect(x: 9, y: 2, width: 280, height: 95))
        let group = ChatLayerNode(id: "group")
        group.frame = NSRect(x: 3, y: 2, width: 260, height: 90)
        try scene.root.setChildren([group])
        row.addSubview(scene)
        row.scenes = [scene]
        var nodes: [ChatLayerNode] = []
        for block in 0..<3 {
            let layout = makeLayout(["one 👨‍👩‍👧‍👦 café \(index)", "אבג مرحبا \(index)", "last e\u{301} text \(index)"][block])
            let origin = NSPoint(x: 12, y: 4 + CGFloat(block * 30))
            let height = clipped ? layout.layoutSize.height / 2 : layout.layoutSize.height
            if mask & (1 << block) != 0 {
                let node = ChatLayerTextNode(id: block, selectable: true)
                node.update(layout, frame: NSRect(x: 0, y: CGFloat(block * 30), width: layout.layoutSize.width, height: height))
                nodes.append(node)
                row.sources.append(.layer(node, scene))
            } else {
                let text = TextView()
                text.update(layout)
                if clipped {
                    let parent = View(frame: NSRect(origin: origin, size: NSSize(width: layout.layoutSize.width, height: height)))
                    parent.addSubview(text)
                    row.addSubview(parent)
                } else {
                    text.setFrameOrigin(origin)
                    row.addSubview(text)
                }
                row.selectableTextViews.append(text)
                row.sources.append(.view(text))
            }
        }
        try group.setChildren(nodes)
        scene.selectableTextNodeIds = nodes.map(\.id)
        return row
    }

    func window() -> Window {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    func testEmbeddedLayersMatchNativeRangesAttributesHeadersAndOrdering() throws {
        let window = window()
        defer { window.contentView = nil; window.close() }
        var comparisons = 0
        for clipped in [false, true] {
            for reversedTable in [false, true] {
                let referenceRows = try (0..<3).map { try makeRow($0, mask: 0, clipped: clipped) }
                let reference = ReferenceEmbeddedSelectionLoopHarness(SelectionTable(views: referenceRows, reversed: reversedTable))
                for mask in 0..<8 {
                    let rows = try (0..<3).map { try makeRow($0, mask: (mask + $0) % 8, clipped: clipped) }
                    let current = SelectionLoopHarness(SelectionTable(views: rows, reversed: reversedTable))
                    for start in [NSPoint(x: 0, y: 0), NSPoint(x: 24, y: 10), NSPoint(x: 60, y: 35), NSPoint(x: 110, y: 70)] {
                        for end in [NSPoint(x: 80, y: 75), NSPoint(x: 40, y: 135), NSPoint(x: 150, y: 270), NSPoint(x: 299, y: 299)] {
                            for reversed in [false, true] {
                                reference.select(begin: reversed ? end : start, end: reversed ? start : end, window: window, reversedTable: reversedTable)
                                current.select(begin: reversed ? end : start, end: reversed ? start : end, window: window, reversedTable: reversedTable)
                                XCTAssertTrue(current.selectManager.selectedText.isEqual(to: reference.selectManager.selectedText), "mask=\(mask), clipped=\(clipped), reversedTable=\(reversedTable), reversed=\(reversed), start=\(start), end=\(end): \(current.selectManager.selectedText.string) != \(reference.selectManager.selectedText.string)")
                                for row in 0..<3 {
                                    for block in 0..<3 {
                                        XCTAssertEqual(rows[row].sources[block].textLayout?.selectedRange.range, referenceRows[row].sources[block].textLayout?.selectedRange.range)
                                    }
                                }
                                comparisons += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 1024)
    }

    func testCapturedLoopOmitsTheLayerBodyInsideANormalRow() throws {
        let window = window()
        defer { window.contentView = nil; window.close() }
        let table = SelectionTable(views: try (0..<3).map { try makeRow($0, mask: 2) }, reversed: false)
        let original = ReferenceEmbeddedSelectionLoopHarness(table)
        let current = SelectionLoopHarness(table)
        original.select(begin: .zero, end: NSPoint(x: 299, y: 299), window: window, reversedTable: false)
        let oldText = original.selectManager.selectedText.string
        current.select(begin: .zero, end: NSPoint(x: 299, y: 299), window: window, reversedTable: false)
        XCTAssertFalse(oldText.contains("אבג"))
        XCTAssertTrue(current.selectManager.selectedText.string.contains("אבג"))
        XCTAssertTrue(current.selectManager.selectedText.string.contains("one"))
        XCTAssertTrue(current.selectManager.selectedText.string.contains("last"))
    }

    func testMixedFragmentsSurviveOffscreenRowsAndShrinkWithoutStaleSelection() throws {
        let window = window()
        defer { window.contentView = nil; window.close() }
        for reversedTable in [false, true] {
            let rows = try (0..<3).map { try makeRow($0, mask: 5) }
            let table = SelectionTable(views: rows, reversed: reversedTable)
            let selector = SelectionLoopHarness(table)
            selector.select(begin: .zero, end: NSPoint(x: 299, y: 299), window: window, reversedTable: reversedTable)
            let selected = selector.selectManager.selectedText
            XCTAssertTrue(selected.string.contains("Author 1"))
            table.offscreenRows = [1]
            for _ in 0..<4 {
                selector.select(begin: .zero, end: NSPoint(x: 299, y: 299), window: window, reversedTable: reversedTable)
                XCTAssertTrue(selector.selectManager.selectedText.isEqual(to: selected))
            }
            table.offscreenRows = []
            selector.select(begin: NSPoint(x: 15, y: 5), end: NSPoint(x: 90, y: 12), window: window, reversedTable: reversedTable)
            XCTAssertFalse(selector.selectManager.selectedText.string.contains("Author 1"))
            for source in rows[1].sources {
                XCTAssertFalse(source.textLayout?.selectedRange.hasSelectText ?? true)
            }
            selector.selectManager.removeAll()
            for row in rows {
                for source in row.sources {
                    XCTAssertFalse(source.textLayout?.selectedRange.hasSelectText ?? true)
                }
                XCTAssertTrue(row.selectableTextViews.allSatisfy(\.canBeResponder))
            }
        }
    }

    func testFocusRestoresTheSelectedEmbeddedNodeInsteadOfFirstCaption() throws {
        let window = window()
        defer { window.contentView = nil; window.close() }
        let row = try makeRow(0, mask: 6)
        window.contentView = row
        guard case let .layer(node, scene) = row.sources[2] else { return XCTFail() }
        scene.focus(node)
        XCTAssertTrue(window.makeFirstResponder(scene))
        row.textSelectionSources.restoreFocus(in: window)
        XCTAssertTrue(scene.focusedNode === node)
        XCTAssertTrue(window.firstResponder === scene)
        XCTAssertTrue(row.sources[2].isFirstResponder(in: window))
        XCTAssertFalse(row.sources[1].isFirstResponder(in: window))
        XCTAssertTrue(window.makeFirstResponder(row.selectableTextViews[0]))
        row.textSelectionSources.restoreFocus(in: window)
        XCTAssertTrue(window.firstResponder === row.selectableTextViews[0])
    }

    func testLayerSelectionRejectsRemovedHiddenDisabledAndProtectedText() throws {
        for mode in 0..<5 {
            let row = try makeRow(0, mask: 7)
            guard case let .layer(node, scene) = row.sources[0], let layout = node.textLayout else { return XCTFail() }
            let manager = SelectManager()
            switch mode {
            case 0: try node.parent?.setChildren([])
            case 1: node.isHidden = true
            case 2: node.isEnabled = false
            case 3: layout.mayItems = false
            default: scene.isHidden = true
            }
            XCTAssertNil(row.sources[0].textLayout)
            row.sources[0].select(layout: layout, start: .zero, end: NSPoint(x: 250, y: 100), manager: manager, header: nil, stableId: 0, index: 0)
            XCTAssertTrue(manager.isEmpty)
        }
    }

    func testSelectionCallbackRebindCannotCopyThePreviousMessage() throws {
        let row = try makeRow(0, mask: 7)
        guard case let .layer(node, _) = row.sources[0], let layout = node.textLayout else { return XCTFail() }
        let replacement = makeLayout("new message")
        node.onSelectionChanged = { _ in
            node.onSelectionChanged = nil
            node.update(replacement)
        }
        let manager = SelectManager()
        row.sources[0].select(layout: layout, start: .zero, end: NSPoint(x: 250, y: 100), manager: manager, header: nil, stableId: 0, index: 0)
        XCTAssertTrue(manager.isEmpty)
        XCTAssertTrue(node.textLayout === replacement)
        XCTAssertFalse(replacement.selectedRange.hasSelectText)
    }

    func testSelectionManagerDoesNotRetainTheEmbeddedScene() throws {
        let manager = SelectManager()
        weak var weakScene: ChatLayerSceneView?
        try autoreleasepool {
            let row = try makeRow(0, mask: 7)
            weakScene = row.scenes[0]
            let source = row.sources[0]
            source.select(layout: try XCTUnwrap(source.textLayout), start: .zero, end: NSPoint(x: 250, y: 100), manager: manager, header: nil, stableId: 0, index: 0)
        }
        XCTAssertNil(weakScene)
        XCTAssertTrue(manager.selectedText.string.contains("one"))
        manager.removeAll()
        XCTAssertTrue(manager.isEmpty)
    }
}
