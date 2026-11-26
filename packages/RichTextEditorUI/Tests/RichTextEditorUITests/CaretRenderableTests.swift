#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

/// The system tokenizer (Option+Arrow word nav, double-tap select, …) steps the caret via
/// `position(from:offset:)`. These lock the invariant the fix enforces: that primitive — and the
/// document-bound positions — can only ever land on a RENDERABLE caret slot, never a structural token.
@available(macOS 12, *)
final class CaretRenderableTests: XCTestCase {
    /// The renderable-aware caret-stepping primitive (was the `position(from:offset:)` UITextInput
    /// witness): step `|offset|` single renderable-aware moves in the offset's direction.
    private func step(_ v: DocumentCanvasView, from start: Int, offset: Int) -> Int {
        var p = start
        for _ in 0..<abs(offset) { p = offset >= 0 ? v.nextTextPosition(after: p) : v.prevTextPosition(before: p) }
        return p
    }
    private func cell(_ id: String, _ t: String) -> Cell {
        Cell(id: BlockID(id), blocks: [.paragraph(ParagraphBlock(id: BlockID(id + "p"), runs: [TextRun(text: t)]))])
    }
    private func canvas(_ blocks: [CanvasModelBlock]) -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setModelBlocks(blocks, width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 600); v.layoutSubtreeIfNeeded()
        return v
    }

    // INVARIANT: stepping by ANY offset from ANY position can never yield a non-renderable caret.
    func test_positionFromOffset_neverYieldsNonRenderable() {
        let v = canvas([
            .core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Hello")]))),
            .core(.table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
                rows: [Row(id: BlockID("r0"), cells: [cell("c", "Ada"), cell("d", "Lovelace")])]))),
            .core(.paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "End")]))),
        ])
        let size = v.documentSizeValue
        for start in 0...size {
            for delta in [-5, -2, -1, 0, 1, 2, 5, size] {
                let p = step(v, from: v.snapToRenderable(start, forward: delta >= 0), offset: delta)
                XCTAssertTrue(v.isRenderablePosition(p),
                              "position(from: \(start), offset: \(delta)) = \(p) must be renderable")
            }
        }
    }

    // snapToRenderable is the identity on positions that are already renderable (no caret regresses).
    func test_snapToRenderable_identityOnRenderablePositions() {
        let v = canvas([.core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Hello")])))])
        for r in v.allLeafRegions() {
            for off in 0...r.length {
                let p = r.globalStart + off
                XCTAssertEqual(v.snapToRenderable(p, forward: true), p)
                XCTAssertEqual(v.snapToRenderable(p, forward: false), p)
            }
        }
    }

    // The reported bug's core: the document end is a renderable position (the last text slot), NOT the
    // structural close-token slot at documentSize where the caret would be hidden.
    func test_endOfDocument_isLastRenderableTextPosition() {
        let v = canvas([.core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Hello")])))])
        let end = v.lastRenderableGlobal()
        XCTAssertTrue(v.isRenderablePosition(end))
        XCTAssertLessThan(end, v.documentSizeValue, "endOfDocument is not the structural documentSize slot")
        let last = v.allLeafRegions().last!
        XCTAssertEqual(end, last.globalStart + last.length, "endOfDocument is the end of the last text region")
    }

    // Edge: a document ending in a TABLE — the end snaps into the last cell's text end.
    func test_endOfDocument_trailingTable_landsInLastCell() {
        let v = canvas([
            .core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Top")]))),
            .core(.table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)],
                rows: [Row(id: BlockID("r0"), cells: [cell("c", "Ada"), cell("d", "Lovelace")])]))),
        ])
        let end = v.lastRenderableGlobal()
        XCTAssertTrue(v.isRenderablePosition(end))
        let last = v.allLeafRegions().last!
        XCTAssertEqual(end, last.globalStart + last.length)
        XCTAssertEqual(last.ref, .paragraph(BlockID("dp")), "the last renderable region is the last cell")
    }

    // Edge: an empty document (single empty paragraph) — both endpoints resolve to the one position.
    func test_emptyParagraph_endpointsAreRenderable() {
        let v = canvas([.core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [])))])
        let begin = v.firstRenderableGlobal()
        let end = v.lastRenderableGlobal()
        XCTAssertTrue(v.isRenderablePosition(begin))
        XCTAssertTrue(v.isRenderablePosition(end))
        XCTAssertEqual(begin, end, "single empty paragraph has exactly one caret position")
    }

    // Edge: a document ending in an IMAGE — the end snaps to a renderable slot (caption / gap), never a
    // structural token.
    func test_trailingImage_endpointIsRenderable() {
        let v = canvas([
            .core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Top")]))),
            .media(MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 80, height: 50),
                              caption: [TextRun(text: "Capt")])),
        ])
        let end = v.lastRenderableGlobal()
        XCTAssertTrue(v.isRenderablePosition(end))
        XCTAssertLessThan(end, v.documentSizeValue)
    }

    // beginningOfDocument is the first renderable text position, not the leading open-token slot (0).
    func test_beginningOfDocument_isFirstRenderableTextPosition() {
        let v = canvas([.core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Hello")])))])
        let begin = v.firstRenderableGlobal()
        XCTAssertTrue(v.isRenderablePosition(begin))
        XCTAssertEqual(begin, v.allLeafRegions().first!.globalStart, "beginningOfDocument is the first text region start")
    }
}
#endif
