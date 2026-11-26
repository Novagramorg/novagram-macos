#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// Content-height reporting to the host. The height summed for the host depends on each box's facing
/// insets, which are only set during `layout()`. A freshly-created box (e.g. an empty trailing bullet from
/// Enter) is summed with stale default insets when `invalidateIntrinsicContentSize` fires its report BEFORE
/// `layout()`; the canvas must re-report once layout has corrected the insets, otherwise the host stays
/// inflated until the next edit. (User-reported: an empty trailing bullet reserved more space than a typed
/// one, and typing a character "fixed" it.)
@available(macOS 12, *)
final class CanvasContentHeightTests: AppKitTestCase {
    private func host(_ blocks: [ParagraphBlock], width: CGFloat = 400) -> (DocumentCanvasView, NSWindow) {
        let v = DocumentCanvasView()
        v.setBlocks(blocks.map { .paragraph($0) }, width: width)
        let win = hostInWindow(v)
        v.layoutSubtreeIfNeeded()
        return (v, win)
    }
    private func pressReturn(_ v: DocumentCanvasView, in win: NSWindow) {
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: win.windowNumber, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        v.keyDown(with: e)
    }

    func test_reportedHeightMatchesPostLayout_afterCreatingEmptyTrailingBullet() {
        let (v, win) = host([
            ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .bullet, level: 0), runs: [TextRun(text: "First")]),
        ])
        var reported: CGFloat = -1
        v.onContentSizeChange = { reported = v.intrinsicContentSize.height }

        v.setCaret(global: v.boxes[0].textStart + 5)        // end of "First"
        pressReturn(v, in: win)                             // splits off a new empty bullet
        v.layoutSubtreeIfNeeded()                           // corrects the new box's facing insets

        XCTAssertGreaterThan(reported, 0, "the host was notified of the new content height")
        XCTAssertEqual(reported, v.intrinsicContentSize.height, accuracy: 0.5,
                       "the height reported to the host equals the height the canvas actually lays out at")
    }

    func test_intrinsicHeight_includesBareGapBetweenAdjacentFramedAtoms() {
        // Two adjacent framed atoms (table + code) get a BARE external gap belonging to no box frame;
        // a sum of box heights misses it, so the intrinsic height must come from the layout root.
        let table = TableBlock(id: BlockID.generate(), columns: [ColumnSpec(width: 100)],
                               rows: [Row(id: BlockID.generate(), isHeader: true,
                                          cells: [Cell(id: BlockID.generate(),
                                                       blocks: [.paragraph(ParagraphBlock(id: BlockID.generate(),
                                                                                          runs: [TextRun(text: "Cell")]))])])])
        let code = CodeBlock(id: BlockID.generate(), language: nil, runs: [TextRun(text: "let x = 1")])
        let v = DocumentCanvasView()
        v.setBlocks([.table(table), .code(code)], width: 400)
        let laidOut = v.root.layout(origin: .zero, width: 400)
        let summed = v.boxes.reduce(0) { $0 + $1.height }
        XCTAssertGreaterThan(laidOut, summed, "the framed-atom adjacency lays down bare space no box owns")
        XCTAssertEqual(v.intrinsicContentSize.height, laidOut, accuracy: 0.5,
                       "the reported height covers the laid-out extent, bare gap included")
    }

    func test_emptyTrailingBullet_contentHeightMatchesTypedTrailingBullet() {
        let (empty, _) = host([
            ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .bullet, level: 0), runs: [TextRun(text: "First")]),
            ParagraphBlock(id: BlockID("b"), list: ListMembership(marker: .bullet, level: 0), runs: []),
        ])
        let (typed, _) = host([
            ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .bullet, level: 0), runs: [TextRun(text: "First")]),
            ParagraphBlock(id: BlockID("b"), list: ListMembership(marker: .bullet, level: 0), runs: [TextRun(text: "x")]),
        ])
        XCTAssertEqual(empty.intrinsicContentSize.height, typed.intrinsicContentSize.height, accuracy: 0.5,
                       "an empty trailing bullet reserves no more height than a typed one")
    }
}
#endif
