#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// End-to-end keyboard input: a keyDown event must reach the NSTextInputClient and insert text.
/// Guards the `keyDown(_:) -> inputContext.handleEvent` bridge (without it, typing is dead).
@available(macOS 12, *)
final class CanvasKeyInputTests: AppKitTestCase {
    private func makeHostedCanvas() -> (DocumentCanvasView, NSWindow) {
        let canvas = DocumentCanvasView()
        canvas.setBlocks([.paragraph(ParagraphBlock(id: BlockID.generate()))], width: 400)
        canvas.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        let win = hostInWindow(canvas)
        return (canvas, win)
    }

    func test_keyDown_insertsTypedCharacter() {
        let (canvas, win) = makeHostedCanvas()
        canvas.setCaret(global: canvas.firstRenderableGlobal())
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: win.windowNumber, context: nil,
            characters: "A", charactersIgnoringModifiers: "A", isARepeat: false, keyCode: 0)!
        canvas.keyDown(with: event)
        let text = canvas.text(inGlobalRange: 0, canvas.documentSizeValue)
        XCTAssertTrue(text.contains("A"), "typed 'A' should be inserted via keyDown; got \"\(text)\"")
    }
}
#endif
