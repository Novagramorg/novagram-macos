#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// Mouse-driven selection: click-drag across text must create a non-empty selection (so toolbar
/// formatting has something to act on), and bold must then apply to it.
@available(macOS 12, *)
final class CanvasMouseSelectionTests: AppKitTestCase {
    private func makeCanvas() -> (DocumentCanvasView, NSWindow) {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("h"), runs: [TextRun(text: "Hello world")]))], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        let win = hostInWindow(v)
        v.layoutSubtreeIfNeeded()
        return (v, win)
    }

    func test_mouseDrag_createsSelection_andBoldApplies() {
        let (v, win) = makeCanvas()
        let region = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("h")) }!
        let aGlobal = region.globalStart          // before 'H'
        let bGlobal = region.globalStart + 5      // after "Hello"
        func winPt(_ g: Int) -> NSPoint {
            let r = v.caretRect(forGlobal: g)
            return v.convert(NSPoint(x: r.midX, y: r.midY), to: nil)
        }
        func ev(_ t: NSEvent.EventType, _ g: Int, _ cc: Int) -> NSEvent {
            NSEvent.mouseEvent(with: t, location: winPt(g), modifierFlags: [], timestamp: 0,
                windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: cc, pressure: 1)!
        }
        v.mouseDown(with: ev(.leftMouseDown, aGlobal, 1))
        v.mouseDragged(with: ev(.leftMouseDragged, bGlobal, 1))
        v.mouseUp(with: ev(.leftMouseUp, bGlobal, 1))
        XCTAssertNotEqual(v.selFrom, v.selTo, "drag should create a selection; got \(v.selFrom)..\(v.selTo)")
        v.toggleBold()
        let bold = v.currentBlocks().compactMap { b -> String? in
            if case .paragraph(let p) = b, p.id == BlockID("h") {
                return p.runs.filter { $0.attributes.bold }.map(\.text).joined()
            }
            return nil
        }.joined()
        XCTAssertFalse(bold.isEmpty, "bold should apply to the drag-selected text; bold runs=\"\(bold)\"")
    }
}
#endif
