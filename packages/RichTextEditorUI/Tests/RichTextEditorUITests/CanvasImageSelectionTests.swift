#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasImageSelectionTests: AppKitTestCase {
    private func canvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.imageProvider = { [self] _ in image(of: CGSize(width: 80, height: 50), fill: .systemTeal) }
        v.setModelBlocks([
            .core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Above")]))),
            .media(MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 80, height: 50),
                              caption: [TextRun(text: "Caption")])),
            .core(.paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Below")]))),
        ], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 400); v.layoutSubtreeIfNeeded()
        return v
    }

    func test_selectionFlowsThroughCaption() {
        let v = canvas()
        let imgBox = v.boxes[1]
        // From inside "Above" through the caption into "Below" → rects in all three blocks.
        let rects = v.selectionRects(globalFrom: v.boxes[0].textStart + 2,
                                     globalTo: v.boxes[2].textStart + 2)
        func count(in box: CanvasBlock) -> Int { rects.filter { box.frame.intersects($0) }.count }
        XCTAssertGreaterThan(count(in: v.boxes[0]), 0)
        XCTAssertGreaterThan(count(in: imgBox), 0)        // caption rects
        XCTAssertGreaterThan(count(in: v.boxes[2]), 0)
    }

    func test_shiftEnterInImageCaption_exitsIntoNewParagraph() {
        let v = canvas()
        let img = v.boxes[1] as! ImageBlockBox
        v.setCaret(global: img.textStart + 2)   // inside the caption
        let before = v.boxes.count
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0,
                                 windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                 isARepeat: false, keyCode: 36)!
        v.keyDown(with: e)
        XCTAssertEqual(v.boxes.count, before + 1, "Shift+Enter adds a paragraph after the image")
        XCTAssertTrue(v.boxes[2] is BlockBox, "the new block after the image is a paragraph")
        XCTAssertEqual(v.head, v.boxes[2].textStart, "caret lands in the new paragraph")
    }

    func test_clickImageBitmap_resolvesImageBox() {
        let v = canvas()
        let img = v.boxes[1] as! ImageBlockBox
        let mid = CGPoint(x: img.imageRect().midX, y: img.imageRect().midY)
        XCTAssertEqual(v.imageBoxAtCanvasPoint(mid)?.id, img.id, "a click on the bitmap resolves the image box")
        XCTAssertNil(v.imageBoxAtCanvasPoint(CGPoint(x: img.imageRect().midX, y: img.textOrigin.y + 1)), "the caption area is not the bitmap")
    }

    func test_clickImage_selectsWithAccent_togglesOff_andDeletes() {
        let v = canvas()
        let img = v.boxes[1] as! ImageBlockBox
        v.selectImageBlock(img)
        XCTAssertEqual(v.soleSelectedImageBlock()?.id, img.id, "first click selects the image")
        XCTAssertEqual(v.imageBoxesInSelection().count, 1, "the image atom is in the selection (drives the accent wash)")
        v.selectImageBlock(img)
        XCTAssertNil(v.soleSelectedImageBlock(), "second click deselects (toggle)")
        v.selectImageBlock(img)
        v.performDeleteBackward()
        XCTAssertFalse(v.boxes.contains { $0 is ImageBlockBox }, "Backspace removes the click-selected image")
    }

    func test_caretInCaption_isBelowImage() {
        let v = canvas()
        let imgBox = v.boxes[1] as! ImageBlockBox
        let caret = v.caretRect(forGlobal: imgBox.textStart)
        XCTAssertGreaterThan(caret.minY, imgBox.imageRect().minY)   // caption caret sits below the image
    }

    func test_caretAtImageGap_isVerticalBarAtImageLeadingEdge() {
        let v = canvas()
        let imgBox = v.boxes[1] as! ImageBlockBox
        // The gap before the image atom is a real caret position; we must report a drawable rect so
        // UITextSelectionDisplayInteraction renders the native caret there (not .zero, which is invisible).
        let caret = v.caretRect(forGlobal: imgBox.nodeStart)
        let img = imgBox.imageRect()
        XCTAssertFalse(caret.isEmpty, "gap caret must be a drawable rect, not .zero")
        XCTAssertEqual(caret.minX, img.minX, accuracy: 0.5, "vertical caret sits at the image's leading edge")
        XCTAssertEqual(caret.height, img.height, accuracy: 0.5, "caret spans the image height")
    }

    func test_typingInCaption_editsCaptionText() {
        let v = canvas()
        let imgBox = v.boxes[1] as! ImageBlockBox
        v.selectedGlobalRange = (imgBox.textStart + 7, imgBox.textStart + 7) // end of "Caption"
        v.commitText("!")
        guard case .media(let out) = v.boxes[1].currentModelBlock() else { return XCTFail() }
        XCTAssertEqual(out.caption.map(\.text).joined(), "Caption!")
    }
}
#endif
