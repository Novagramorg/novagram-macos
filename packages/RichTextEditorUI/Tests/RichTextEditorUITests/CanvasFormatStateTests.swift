#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// `currentCharacterFormatState()` drives the toolbar active-state highlight: it reflects pending format
/// at a bare caret and the uniform format of a selection.
@available(macOS 12, *)
final class CanvasFormatStateTests: AppKitTestCase {
    private func canvasWith(_ text: String) -> (DocumentCanvasView, Int) {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: text)]))], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 200); v.layoutSubtreeIfNeeded()
        let r = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("p")) }!
        return (v, r.globalStart)
    }

    func test_state_reflectsPendingBoldAtCaret() {
        let (v, start) = canvasWith("ab")
        v.setCaret(global: start + 2)
        XCTAssertFalse(v.currentCharacterFormatState().bold)
        v.toggleBold()                               // pending bold
        XCTAssertTrue(v.currentCharacterFormatState().bold, "pending bold should read as active")
        v.toggleBold()                               // cancel
        XCTAssertFalse(v.currentCharacterFormatState().bold)
    }

    func test_state_reflectsUniformlyBoldSelection() {
        let (v, start) = canvasWith("Hello")
        v.selectedGlobalRange = (start, start + 5); v.toggleBold()   // bold all
        v.selectedGlobalRange = (start, start + 5)
        XCTAssertTrue(v.currentCharacterFormatState().bold, "fully-bold selection is bold-active")
    }

    func test_state_mixedSelectionNotActive() {
        let (v, start) = canvasWith("Hello")
        v.selectedGlobalRange = (start, start + 2); v.toggleBold()   // bold only "He"
        v.selectedGlobalRange = (start, start + 5)                   // select all "Hello"
        XCTAssertFalse(v.currentCharacterFormatState().bold, "partially-bold selection is not bold-active")
    }
}
#endif
