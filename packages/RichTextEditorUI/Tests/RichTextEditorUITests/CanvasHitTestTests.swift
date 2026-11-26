#if canImport(UIKit)
import XCTest
import UIKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasHitTestTests: XCTestCase {
    private func canvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setParagraphs([
            ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Alpha")]),
            ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Beta")]),
        ], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 200); v.layoutIfNeeded()
        return v
    }

    func test_pointSelectionAcrossBlocks() {
        let v = canvas()
        // Point hit-test → cross-block selection (the primitives behind handle-drag / programmatic selection;
        // a one-finger drag no longer selects — it scrolls). Caret in Alpha, head far into Beta.
        v.setCaret(global: v.closestGlobalPosition(to: CGPoint(x: 0, y: v.boxes[0].frame.midY)))        // in Alpha
        v.setSelectionHead(global: v.closestGlobalPosition(to: CGPoint(x: 9999, y: v.boxes[1].frame.midY)))  // far into Beta
        XCTAssertNotEqual(v.selFrom, v.selTo)
        XCTAssertEqual(v.box(containingGlobal: v.selFrom)!.box.id, BlockID("a"))
        XCTAssertEqual(v.box(containingGlobal: v.selTo)!.box.id, BlockID("b"))
    }

    func test_selectionInteractionAttaches() {
        let v = canvas()
        v.installSelectionInteractions()
        XCTAssertTrue(v.interactions.contains { $0 is UITextSelectionDisplayInteraction })
    }
}
#endif
