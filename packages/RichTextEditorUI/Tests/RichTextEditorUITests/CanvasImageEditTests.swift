#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasImageEditTests: AppKitTestCase {
    private func canvas(_ texts: [String]) -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.imageProvider = { [self] _ in image(of: CGSize(width: 60, height: 40), fill: .systemPink) }
        v.setBlocks(texts.enumerated().map { .paragraph(ParagraphBlock(id: BlockID("p\($0.offset)"), runs: [TextRun(text: $0.element)])) },
                    width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 400); v.layoutSubtreeIfNeeded()
        return v
    }
    private func caret(_ v: DocumentCanvasView, _ pos: Int) {
        v.selectedGlobalRange = (pos, pos)
    }
    private func img() -> (NSImage, CGSize) {
        let s = CGSize(width: 60, height: 40)
        return (image(of: s, fill: .systemPink), s)
    }

    func test_insertImage_atEndOfParagraph_addsImageBlockAfter() {
        let v = canvas(["Alpha"])
        caret(v, v.boxes[0].textStart + 5)               // end of "Alpha"
        let (image, size) = img()
        v.insertImage(image, naturalSize: size, assetID: "k1")
        XCTAssertEqual(v.boxes.count, 2)
        XCTAssertTrue(v.boxes[1] is MediaBlockBox)
        XCTAssertEqual(v.head, v.boxes[1].textStart)     // caret in the caption
    }

    func test_insertImage_midParagraph_splitsAroundImage() {
        let v = canvas(["Alpha"])
        caret(v, v.boxes[0].textStart + 2)               // after "Al"
        let (image, size) = img()
        v.insertImage(image, naturalSize: size, assetID: "k2")
        XCTAssertEqual(v.boxes.count, 3)
        XCTAssertEqual((v.boxes[0] as! BlockBox).currentParagraph().text, "Al")
        XCTAssertTrue(v.boxes[1] is MediaBlockBox)
        XCTAssertEqual((v.boxes[2] as! BlockBox).currentParagraph().text, "pha")
    }

    func test_insertImage_isUndoable() {
        let v = canvas(["Alpha"])
        let um = UndoManager(); um.groupsByEvent = false
        v.undoManagerOverride = um
        caret(v, v.boxes[0].textStart + 5)
        let (image, size) = img()
        um.beginUndoGrouping(); v.insertImage(image, naturalSize: size, assetID: "k3"); um.endUndoGrouping()
        XCTAssertEqual(v.boxes.count, 2)
        um.undo()
        XCTAssertEqual(v.boxes.count, 1)
        XCTAssertFalse(v.boxes.contains { $0 is MediaBlockBox })
    }

    private func docWithImage() -> DocumentCanvasView {
        let v = canvas(["Above", "Below"])
        caret(v, v.boxes[0].textStart + 5)
        let (image, size) = img()
        v.insertImage(image, naturalSize: size, assetID: "k")   // → ["Above", image, "Below"]
        return v
    }

    func test_backspaceAtGapBeforeImage_deletesImage() {
        let v = docWithImage()
        caret(v, v.boxes[1].nodeStart)                  // gap before the image
        v.performDeleteBackward()
        XCTAssertEqual(v.boxes.count, 2)
        XCTAssertFalse(v.boxes.contains { $0 is MediaBlockBox })
    }

    func test_backspaceAtCaptionStart_deletesImage() {
        let v = docWithImage()
        caret(v, v.boxes[1].textStart)                  // start of the caption
        v.performDeleteBackward()
        XCTAssertFalse(v.boxes.contains { $0 is MediaBlockBox })
    }

    func test_backspaceAtStartOfNonEmptyParagraphAfterImage_movesToCaption_doesNotDelete() {
        let v = docWithImage()                          // ["Above", image, "Below"]
        caret(v, v.boxes[2].textStart)                  // start of "Below" (box after the image)
        v.performDeleteBackward()
        XCTAssertTrue(v.boxes.contains { $0 is MediaBlockBox }, "the image is NOT deleted")
        XCTAssertEqual((v.boxes.last as! BlockBox).currentParagraph().text, "Below", "the paragraph is untouched")
        let image = v.boxes[1]
        XCTAssertEqual(v.head, image.textStart + image.textLength, "caret moved to the image's caption end")
    }

    func test_backspaceInEmptyParagraphAfterImage_removesParagraph_landsInCaption() {
        let v = canvas(["Above", ""])
        caret(v, v.boxes[0].textStart + 5)
        let (image, size) = img()
        v.insertImage(image, naturalSize: size, assetID: "k")   // → ["Above", image, ""]
        XCTAssertEqual(v.boxes.count, 3)
        caret(v, v.boxes[2].textStart)                  // start of the trailing EMPTY paragraph
        v.performDeleteBackward()
        XCTAssertEqual(v.boxes.count, 2, "the empty trailing paragraph is removed")
        XCTAssertTrue(v.boxes[1] is MediaBlockBox, "the image survives as the last block")
        XCTAssertEqual(v.head, v.boxes[1].textStart + v.boxes[1].textLength, "caret lands in the image caption")
    }

    func test_backspaceInEmptyFirstParagraph_removesIt() {
        let v = canvas(["", "Below"])
        caret(v, v.boxes[0].textStart)                  // start of the empty first paragraph
        v.performDeleteBackward()
        XCTAssertEqual(v.boxes.count, 1, "the empty first paragraph is removed")
        XCTAssertEqual((v.boxes[0] as! BlockBox).currentParagraph().text, "Below", "the next block becomes first")
        XCTAssertEqual(v.head, v.boxes[0].textStart, "caret lands at the start of the now-first block")
    }

    func test_backspaceInEmptyFirstParagraphAboveImage_removesIt_landsInImage() {
        let v = canvas(["", "tail"])
        caret(v, v.boxes[1].textStart)                  // start of "tail" (local 0)
        let (image, size) = img()
        v.insertImage(image, naturalSize: size, assetID: "k")   // pos.local 0 → image BEFORE → ["", image, "tail"]
        XCTAssertEqual(v.boxes.count, 3)
        XCTAssertTrue(v.boxes[1] is MediaBlockBox)
        caret(v, v.boxes[0].textStart)                  // empty FIRST paragraph, above the image
        v.performDeleteBackward()
        XCTAssertEqual(v.boxes.count, 2, "the empty first paragraph is removed")
        XCTAssertTrue(v.boxes[0] is MediaBlockBox, "the image becomes the first block")
        XCTAssertEqual(v.head, v.boxes[0].nodeStart, "caret lands at the gap before the now-first image")
    }

    func test_upFromImageCaption_withBlockAbove_movesToThatBlockEnd() {
        let v = docWithImage()                          // ["Above", image, "Below"]
        caret(v, v.boxes[1].textStart)                  // image caption start
        v.moveUp(nil)
        XCTAssertEqual(v.boxes.count, 3, "nothing inserted — there's a block above to move to")
        XCTAssertEqual(v.head, v.boxes[0].textStart + v.boxes[0].textLength, "caret moved to the end of 'Above'")
    }

    func test_downFromParagraphAboveImage_landsInCaption_notGap() {
        let v = docWithImage()                          // ["Above", image, "Below"]
        caret(v, v.boxes[0].textStart)                  // in "Above"
        v.moveDown(nil)
        XCTAssertEqual(v.head, v.boxes[1].textStart, "Down lands in the image caption, not the gap before the image")
    }

    func test_upFromLeadingImageCaption_insertsBodyParagraphAbove() {
        let v = canvas(["Below"])
        caret(v, v.boxes[0].textStart)                  // start of "Below"
        let (image, size) = img()
        v.insertImage(image, naturalSize: size, assetID: "k")   // pos.local 0 → image BEFORE → [image, "Below"], caret in caption
        XCTAssertTrue(v.boxes[0] is MediaBlockBox)
        let before = v.boxes.count
        v.moveUp(nil)
        XCTAssertEqual(v.boxes.count, before + 1, "a body paragraph is inserted above the leading image")
        XCTAssertEqual((v.boxes[0] as? BlockBox)?.style, .body)
        XCTAssertEqual((v.boxes[0] as? BlockBox)?.textLength, 0)
        XCTAssertEqual(v.head, v.boxes[0].textStart, "caret lands in the new top paragraph")
    }

    func test_deleteImage_isUndoable() {
        let v = docWithImage()
        let um = UndoManager(); um.groupsByEvent = false
        v.undoManagerOverride = um
        caret(v, v.boxes[1].nodeStart)
        um.beginUndoGrouping(); v.performDeleteBackward(); um.endUndoGrouping()
        XCTAssertFalse(v.boxes.contains { $0 is MediaBlockBox })
        um.undo()
        XCTAssertTrue(v.boxes.contains { $0 is MediaBlockBox })
    }

    func test_typingAtGapBeforeImage_insertsParagraphBeforeImage() {
        let v = docWithImage()                          // ["Above", image, "Below"]
        caret(v, v.boxes[1].nodeStart)                  // gap before the image
        v.commitText("Hi")
        XCTAssertEqual(v.boxes.count, 4)
        XCTAssertEqual((v.boxes[1] as! BlockBox).currentParagraph().text, "Hi")  // new paragraph before image
        XCTAssertTrue(v.boxes[2] is MediaBlockBox)
        XCTAssertEqual(v.head, v.boxes[1].textStart + 2)                         // caret at end of "Hi"
        guard case .media(let out) = v.boxes[2].currentModelBlock() else { return XCTFail() }
        XCTAssertEqual(out.caption.map(\.text).joined(), "")                     // caption untouched
    }

    func test_enterAtGapBeforeImage_insertsEmptyParagraphBeforeImage() {
        let v = docWithImage()
        caret(v, v.boxes[1].nodeStart)
        v.insertNewline(nil)
        XCTAssertEqual(v.boxes.count, 4)
        XCTAssertEqual((v.boxes[1] as! BlockBox).currentParagraph().text, "")    // empty paragraph before image
        XCTAssertTrue(v.boxes[2] is MediaBlockBox)
        XCTAssertEqual(v.head, v.boxes[1].textStart)                            // caret in the empty paragraph
    }

    func test_typingAtGapBeforeImage_isUndoable() {
        let v = docWithImage()
        let um = UndoManager(); um.groupsByEvent = false
        v.undoManagerOverride = um
        caret(v, v.boxes[1].nodeStart)
        um.beginUndoGrouping(); v.commitText("Hi"); um.endUndoGrouping()
        XCTAssertEqual(v.boxes.count, 4)
        um.undo()
        XCTAssertEqual(v.boxes.count, 3)
        XCTAssertFalse(v.boxes.contains { ($0 as? BlockBox)?.currentParagraph().text == "Hi" })
    }

    func test_typingAtGapBeforeLeadingImage_insertsParagraphAtDocumentStart() {
        let v = canvas(["Below"])
        caret(v, v.boxes[0].textStart)                  // start of "Below"
        let (image, size) = img()
        v.insertImage(image, naturalSize: size, assetID: "k0")  // → [image, "Below"]
        caret(v, v.boxes[0].nodeStart)                  // gap before the leading image
        v.commitText("Top")
        XCTAssertEqual(v.boxes.count, 3)
        XCTAssertEqual((v.boxes[0] as! BlockBox).currentParagraph().text, "Top")  // new first block
        XCTAssertTrue(v.boxes[1] is MediaBlockBox)
        XCTAssertEqual(v.head, v.boxes[0].textStart + 3)
    }
}
#endif
