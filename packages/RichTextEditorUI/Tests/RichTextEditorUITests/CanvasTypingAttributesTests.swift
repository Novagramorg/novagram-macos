#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// "Pending" typing attributes: toggling a character format on a BARE caret (no selection) makes the
/// next typed text carry that format, and a caret move clears the pending state. (Word-processor
/// behavior: click B, type, it's bold.)
@available(macOS 12, *)
final class CanvasTypingAttributesTests: AppKitTestCase {
    private func canvasWith(_ text: String) -> (DocumentCanvasView, Int) {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: text)]))], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 200); v.layoutSubtreeIfNeeded()
        let r = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("p")) }!
        return (v, r.globalStart)
    }
    private func boldText(_ v: DocumentCanvasView) -> String {
        v.currentBlocks().compactMap { b -> String? in
            if case .paragraph(let p) = b, p.id == BlockID("p") {
                return p.runs.filter { $0.attributes.bold }.map(\.text).joined()
            }
            return nil
        }.joined()
    }

    func test_toggleBold_onCollapsedCaret_makesTypedTextBold() {
        let (v, start) = canvasWith("ab")
        v.setCaret(global: start + 2)            // caret after "ab"
        v.toggleBold()                            // pending bold (no selection)
        v.commitText("X")                         // type → should be bold
        XCTAssertEqual(boldText(v), "X", "typed text after toggleBold should be bold")
    }

    func test_pendingBold_persistsAcrossMultipleTypedChars() {
        let (v, start) = canvasWith("ab")
        v.setCaret(global: start + 2)
        v.toggleBold()
        v.commitText("X"); v.commitText("Y")
        XCTAssertEqual(boldText(v), "XY", "pending bold should keep applying while typing")
    }

    func test_pendingBold_clearedOnCaretMove() {
        let (v, start) = canvasWith("ab")
        v.setCaret(global: start + 2)
        v.toggleBold()
        v.setCaret(global: start)                 // move caret → pending cleared
        v.commitText("Z")
        XCTAssertEqual(boldText(v), "", "moving the caret should clear pending bold")
    }

    func test_toggleBoldTwice_onCollapsedCaret_cancels() {
        let (v, start) = canvasWith("ab")
        v.setCaret(global: start + 2)
        v.toggleBold(); v.toggleBold()            // on then off
        v.commitText("Q")
        XCTAssertEqual(boldText(v), "", "toggling bold twice should leave typing un-bold")
    }
}
#endif
