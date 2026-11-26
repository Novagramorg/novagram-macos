#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
@testable import RichTextEditorCore

/// Cut / Copy / Paste inside a code block's LANGUAGE line, and the atom-insert lock-out across BOTH of a
/// code block's regions.
///
/// The language line is a non-primary leaf region, so `slicedBlocks` (which slices every box against its
/// PRIMARY region) contributes nothing for a selection lying wholly inside it — the copy path has to fall
/// back to plain text or ⌘X becomes a silent destructive delete. Each lock-out test is paired with a
/// CONTROL on a body paragraph: without one, an inertness assertion could pass simply because the gesture
/// never took effect.
@available(macOS 12, *)
final class CodeLanguageClipboardTests: XCTestCase {

    /// Mirrors `NSPasteboardAdapter`: writing `string` CLEARS the pasteboard (so a plain-text-only copy
    /// cannot leave a stale rich fragment behind for the next paste to prefer).
    private final class FakePasteboard: TextPasteboard {
        var string: String? { didSet { richFragment = nil } }
        var richFragment: Data?
        var hasStrings: Bool { !(string ?? "").isEmpty }
    }

    private func makeCanvas(_ blocks: [Block]) -> (DocumentCanvasView, FakePasteboard) {
        let c = DocumentCanvasView()
        c.setBlocks(blocks, width: 320)
        let pb = FakePasteboard()
        c.pasteboard = pb
        return (c, pb)
    }

    private func codeCanvas(language: String? = "swift", text: String = "let x = 1")
        -> (DocumentCanvasView, FakePasteboard) {
        makeCanvas([.code(CodeBlock(id: BlockID("c"), language: language, runs: [TextRun(text: text)]))])
    }

    private func code(_ canvas: DocumentCanvasView) -> CodeBlockBox { canvas.boxes[0] as! CodeBlockBox }

    // MARK: - Copy

    func test_copyInsideTheLanguageLinePutsItsTextOnThePasteboard() {
        let (canvas, pb) = codeCanvas()
        let box = code(canvas)
        canvas.selectedGlobalRange = (box.nodeStart + 1, box.nodeStart + 1 + 5)   // the whole "swift"
        canvas.copy(nil)
        XCTAssertEqual(pb.string, "swift", "a language-line copy writes plain text (no Core fragment exists for it)")
    }

    func test_copyOfAPartialLanguageSelectionPutsThatSubstringOnThePasteboard() {
        let (canvas, pb) = codeCanvas()
        let box = code(canvas)
        canvas.selectedGlobalRange = (box.nodeStart + 1 + 1, box.nodeStart + 1 + 3)   // "wi"
        canvas.copy(nil)
        XCTAssertEqual(pb.string, "wi")
    }

    // CONTROL: the primary (code text) region still copies as a rich fragment — the plain-text fallback
    // must not have swallowed the normal path.
    func test_control_copyInsideTheCodeTextStillWritesARichFragment() {
        let (canvas, pb) = codeCanvas()
        let box = code(canvas)
        canvas.selectedGlobalRange = (box.textStart, box.textStart + 3)   // "let"
        canvas.copy(nil)
        XCTAssertEqual(pb.string, "let")
        XCTAssertNotNil(pb.richFragment, "the code text is a primary region, so it still yields a fragment")
    }

    // MARK: - Cut

    func test_cutInsideTheLanguageLineWritesThePasteboardBeforeDeleting() {
        let (canvas, pb) = codeCanvas()
        let box = code(canvas)
        canvas.selectedGlobalRange = (box.nodeStart + 1, box.nodeStart + 1 + 5)
        canvas.cut(nil)
        XCTAssertEqual(pb.string, "swift", "cut must not be a silent destructive delete")
        XCTAssertNil(code(canvas).currentCode().language, "and it still removes the language")
        XCTAssertEqual(code(canvas).currentCode().text, "let x = 1", "the code text is untouched")
    }

    func test_cutOfAPartialLanguageSelectionKeepsTheRemainderAndCarriesTheCutText() {
        let (canvas, pb) = codeCanvas()
        let box = code(canvas)
        canvas.selectedGlobalRange = (box.nodeStart + 1 + 1, box.nodeStart + 1 + 3)   // "wi"
        canvas.cut(nil)
        XCTAssertEqual(pb.string, "wi")
        XCTAssertEqual(code(canvas).currentCode().language, "sft")
    }

    // MARK: - Round trip

    func test_cutThenPasteRestoresTheLanguage() {
        let (canvas, _) = codeCanvas()
        let box = code(canvas)
        canvas.selectedGlobalRange = (box.nodeStart + 1, box.nodeStart + 1 + 5)
        canvas.cut(nil)
        XCTAssertNil(code(canvas).currentCode().language)

        canvas.setCaret(global: code(canvas).nodeStart + 1)
        canvas.paste(nil)
        XCTAssertEqual(code(canvas).currentCode().language, "swift", "the cut text pastes back into the language line")
        XCTAssertEqual(code(canvas).currentCode().text, "let x = 1")
    }

    func test_copyFromTheLanguageLinePastesIntoABodyParagraph() {
        let (canvas, _) = makeCanvas([
            .code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "x")])),
            .paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "ab")])),
        ])
        let box = code(canvas)
        canvas.selectedGlobalRange = (box.nodeStart + 1, box.nodeStart + 1 + 5)
        canvas.copy(nil)

        let para = canvas.boxes[1]
        canvas.setCaret(global: para.textStart + 1)
        canvas.paste(nil)
        XCTAssertEqual(canvas.boxes[1].textLayout.attributedString.string, "aswiftb")
    }

    // MARK: - Atom inserts are inert in BOTH code regions

    func test_emojiInsertionIsInertInTheCodeText() {
        let (canvas, _) = codeCanvas(text: "let x")
        let box = code(canvas)
        canvas.setCaret(global: box.textStart + 2)
        canvas.insertEmoji(id: "1", altText: "🙂")
        XCTAssertEqual(code(canvas).currentCode().text, "let x", "no U+FFFC may reach the code string")
    }

    func test_emojiInsertionIsInertInTheLanguageLine() {
        let (canvas, _) = codeCanvas(text: "let x")
        let box = code(canvas)
        canvas.setCaret(global: box.nodeStart + 1 + 2)
        canvas.insertEmoji(id: "1", altText: "🙂")
        XCTAssertEqual(code(canvas).currentCode().language, "swift")
    }

    func test_formulaInsertionIsInertInTheCodeText() {
        let (canvas, _) = codeCanvas(text: "let x")
        let box = code(canvas)
        canvas.setCaret(global: box.textStart + 2)
        canvas.insertFormula(latex: "x^2")
        XCTAssertEqual(code(canvas).currentCode().text, "let x", "no U+FFFC may reach the code string")
    }

    func test_formulaInsertionIsInertInTheLanguageLine() {
        let (canvas, _) = codeCanvas(text: "let x")
        let box = code(canvas)
        canvas.setCaret(global: box.nodeStart + 1 + 2)
        canvas.insertFormula(latex: "x^2")
        XCTAssertEqual(code(canvas).currentCode().language, "swift")
    }

    // A refused insert must not eat a live selection either — the gate runs BEFORE `editing { }`, which
    // is where the selection would otherwise be cleared.
    func test_aRefusedAtomInsertLeavesTheCodeSelectionIntact() {
        let (canvas, _) = codeCanvas(text: "let x")
        let box = code(canvas)
        canvas.selectedGlobalRange = (box.textStart + 1, box.textStart + 3)
        canvas.insertFormula(latex: "x^2")
        XCTAssertEqual(code(canvas).currentCode().text, "let x", "the selected code text is not deleted")
    }

    // CONTROLS: the same gestures on a body paragraph DO insert an atom, so the inertness tests above
    // are measuring the gate and not a dead call.
    func test_control_emojiAndFormulaInsertIntoABodyParagraph() {
        let (canvas, _) = makeCanvas([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "ab")]))])
        canvas.setCaret(global: canvas.boxes[0].textStart + 1)
        canvas.insertEmoji(id: "1", altText: "🙂")
        XCTAssertEqual(canvas.boxes[0].textLayout.attributedString.string, "a\u{FFFC}b")

        canvas.setCaret(global: canvas.boxes[0].textStart + 1)
        canvas.insertFormula(latex: "x^2")
        XCTAssertEqual(canvas.boxes[0].textLayout.attributedString.string, "a\u{FFFC}\u{FFFC}b")
    }
}
#endif
