#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// Phase 0 of the media-attach work: the macOS-only `MediaBlock` / `CanvasModelBlock` model and
/// `MediaBlockBox`. Verifies position accounting (the media block is a single atom token), the
/// public-`[Block]`-drops vs internal-currency-keeps split, and that the undo snapshot/restore
/// round-trip (which now uses `CanvasModelBlock`) preserves a media block.
@available(macOS 12, *)
final class MediaBlockModelTests: XCTestCase {

    private func docWithMedia() -> [CanvasModelBlock] {
        [.core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "ab")]))),
         .media(MediaBlock(id: BlockID("m"), kind: .file, mediaID: "asset-1")),
         .core(.paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "cd")])))]
    }

    func test_mediaBox_basics() {
        let box = MediaBlockBox(media: MediaBlock(id: BlockID("m"), kind: .file, mediaID: "x"), mapper: AttributedStringMapper(), width: 300)
        XCTAssertEqual(box.nodeSize, 5, "empty caption → caption.length(0) + 5 (mirrors ImageBlockBox)")
        XCTAssertEqual(box.textLength, 0)
        XCTAssertEqual(box.textStart, box.nodeStart + 2, "the caption begins after the atom")
        XCTAssertEqual(box.leafRegions().count, 1, "the caption is an editable text region")
        XCTAssertEqual(box.mediaAreaHeight, MediaBlockBox.placeholderHeight, accuracy: 0.5,
                       "the media area uses the placeholder until a host view reports its height")
        XCTAssertGreaterThan(box.height, box.mediaAreaHeight, "the block is taller than the media area (caption space below)")
        guard case .media(let m) = box.currentModelBlock() else { return XCTFail("currentModelBlock should be .media") }
        XCTAssertEqual(m.kind, .file)
        XCTAssertEqual(m.mediaID, "x")
        XCTAssertTrue(m.caption.isEmpty)
    }

    func test_hostHeightOverridesPlaceholder() {
        var block = MediaBlock(id: BlockID("m"), kind: .map, mediaID: "x")
        block.height = 120
        let box = MediaBlockBox(media: block, mapper: AttributedStringMapper(), width: 300)
        XCTAssertEqual(box.mediaAreaHeight, 120, accuracy: 0.5,
                       "a host-reported height replaces the placeholder for the media area")
    }

    func test_positions_accountForMediaAtom() {
        let v = DocumentCanvasView()
        v.setModelBlocks(docWithMedia(), width: 300)
        let boxes = v.boxes
        XCTAssertEqual(boxes.count, 3)
        // paragraph "ab" → nodeSize 4 (len 2 + 2); media (empty caption) → 5; paragraph "cd" → 4.
        XCTAssertEqual(boxes[0].nodeStart, 1)
        XCTAssertEqual(boxes[1].nodeStart, 5, "media starts after the first paragraph's 4 tokens")
        XCTAssertEqual(boxes[2].nodeStart, 10, "third block starts after the media's 5 tokens")
        XCTAssertEqual(v.documentSize, 13)
    }

    func test_publicBlocksDropMedia_internalCurrencyKeepsIt() {
        let v = DocumentCanvasView()
        v.setModelBlocks(docWithMedia(), width: 300)
        XCTAssertEqual(v.currentBlocks().count, 2, "public [Block] excludes the media block")
        XCTAssertEqual(v.currentModelBlocks().count, 3, "internal currency keeps it")
        guard case .media(let m) = v.currentModelBlocks()[1] else { return XCTFail("middle model block should be .media") }
        XCTAssertEqual(m.mediaID, "asset-1")
    }

    func test_undoCurrency_roundTripsMedia() {
        // Mirrors exactly what undo does: snapshot `currentModelBlocks()`, mutate, restore via `setModelBlocks`.
        let v = DocumentCanvasView()
        v.setModelBlocks(docWithMedia(), width: 300)
        let snapshot = v.currentModelBlocks()
        v.setModelBlocks([.core(.paragraph(ParagraphBlock(id: BlockID("z"), runs: [TextRun(text: "x")])))], width: 300)
        XCTAssertEqual(v.boxes.count, 1)
        v.setModelBlocks(snapshot, width: 300)          // == undo restore
        XCTAssertEqual(v.boxes.count, 3)
        XCTAssertTrue(v.boxes[1] is MediaBlockBox, "media block survives the snapshot/restore round-trip")
        XCTAssertEqual(v.documentSize, 13)
    }
}
#endif
