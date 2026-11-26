#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// Math formulas are created ONLY through the host's LaTeX modal (`insertFormula` / `currentFormula`) —
/// there is no longer any inline `$…$` / `\(…\)` auto-parsing while typing or pasting. A formula is a
/// single `U+FFFC` atom carrying `CharacterAttributes.formula`, rendered via SwiftMath like the chat (IV2).
@available(macOS 12, *)
final class CanvasFormulaTests: AppKitTestCase {
    private final class FakePasteboard: TextPasteboard {
        var string: String?
        var hasStrings: Bool { !(string ?? "").isEmpty }
    }
    private func paste(_ s: String, into v: DocumentCanvasView) {
        let pb = FakePasteboard(); pb.string = s; v.pasteboard = pb
        v.setCaret(global: v.boxes[0].textStart)
        v.pasteFromPasteboard()
    }
    private func paragraphCanvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("p"), runs: []))], width: 400)
        _ = hostInWindow(v); v.frame = CGRect(x: 0, y: 0, width: 400, height: 200); v.layoutSubtreeIfNeeded()
        v.setCaret(global: v.boxes[0].textStart)
        return v
    }
    private func type(_ s: String, into v: DocumentCanvasView) { for ch in s { v.commitText(String(ch)) } }
    private func formulaRuns(_ v: DocumentCanvasView) -> [TextRun] {
        guard case .paragraph(let p) = v.currentBlocks()[0] else { return [] }
        return p.runs.filter { $0.attributes.formula != nil }
    }

    // MARK: No more inline auto-parsing

    func test_typingDelimitedText_doesNotAutoConvert() {
        let v = paragraphCanvas()
        type("$x^2$", into: v)
        XCTAssertTrue(formulaRuns(v).isEmpty, "typing $…$ no longer converts — it stays plain text")
        guard case .paragraph(let p) = v.currentBlocks()[0] else { return XCTFail() }
        XCTAssertEqual(p.runs.map(\.text).joined(), "$x^2$", "the literal text is preserved verbatim")
    }

    func test_typingParenDelimitedText_doesNotAutoConvert() {
        let v = paragraphCanvas()
        type("\\(a+b\\)", into: v)
        XCTAssertTrue(formulaRuns(v).isEmpty, "typing \\(…\\) no longer converts")
    }

    func test_pasteDelimitedText_doesNotAutoConvert() {
        let v = paragraphCanvas()
        paste("see $E=mc^2$ now", into: v)
        XCTAssertTrue(formulaRuns(v).isEmpty, "pasting math delimiters no longer converts")
    }

    // MARK: Modal insert / edit

    func test_insertFormula_insertsOneAtom() {
        let v = paragraphCanvas()
        v.insertFormula(latex: "x^2")
        let runs = formulaRuns(v)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.attributes.formula, "x^2")
        XCTAssertEqual(runs.first?.text, "\u{FFFC}", "a formula occupies exactly one U+FFFC position")
    }

    func test_insertFormula_trimsWhitespace_blankIsNoOp() {
        let v = paragraphCanvas()
        v.insertFormula(latex: "  a+b  ")
        XCTAssertEqual(formulaRuns(v).first?.attributes.formula, "a+b", "surrounding whitespace is trimmed")
        let v2 = paragraphCanvas()
        v2.insertFormula(latex: "   ")
        XCTAssertTrue(formulaRuns(v2).isEmpty, "a blank latex inserts nothing")
    }

    func test_insertFormula_replacesTextSelection() {
        let v = paragraphCanvas()
        type("ab", into: v)
        v.selectedGlobalRange = (v.boxes[0].textStart, v.boxes[0].textStart + 2)  // select "ab"
        v.insertFormula(latex: "z")
        XCTAssertEqual(formulaRuns(v).count, 1)
        guard case .paragraph(let p) = v.currentBlocks()[0] else { return XCTFail() }
        XCTAssertEqual(p.runs.filter { $0.attributes.formula == nil }.map(\.text).joined(), "", "the selected text is replaced by the formula")
    }

    func test_currentFormula_afterInsert_caretRestsAfterAtom() {
        let v = paragraphCanvas()
        v.insertFormula(latex: "x^2")
        XCTAssertEqual(v.currentFormula(), "x^2", "caret just after the atom reads its latex (for editing)")
    }

    func test_currentFormula_nilWhenNotOnFormula() {
        let v = paragraphCanvas()
        type("hello", into: v)
        XCTAssertNil(v.currentFormula(), "plain text → no formula")
    }

    func test_currentFormula_selectedAtom_returnsLatex() {
        let v = paragraphCanvas()
        v.insertFormula(latex: "a_b")
        v.selectedGlobalRange = (v.head - 1, v.head)   // select the atom itself
        XCTAssertEqual(v.currentFormula(), "a_b")
    }

    func test_insertFormula_editsExistingFormula_replacesInPlace() {
        let v = paragraphCanvas()
        v.insertFormula(latex: "x^2")          // caret rests after it
        v.insertFormula(latex: "y^3")          // editing it (caret adjacent) → replace, not add
        let runs = formulaRuns(v)
        XCTAssertEqual(runs.count, 1, "editing replaces the atom, doesn't add a second")
        XCTAssertEqual(runs.first?.attributes.formula, "y^3")
    }

    func test_insertFormula_blankOnExistingFormula_removesIt() {
        let v = paragraphCanvas()
        v.insertFormula(latex: "x^2")
        v.insertFormula(latex: "")             // clearing the field removes the formula
        XCTAssertTrue(formulaRuns(v).isEmpty, "a blank latex on an existing formula deletes it")
    }

    func test_clickOnFormula_selectsTheAtom() {
        let v = paragraphCanvas()
        v.insertFormula(latex: "x^2")
        v.commitText("ab")
        v.setCaret(global: v.boxes[0].textStart + 3)     // caret off the formula (collapsed)
        let a = v.caretRect(forGlobal: v.boxes[0].textStart)
        let b = v.caretRect(forGlobal: v.boxes[0].textStart + 1)
        let p = CGPoint(x: (a.midX + b.midX) / 2, y: a.midY)
        XCTAssertTrue(v.selectFormula(atCanvasPoint: p), "a click on the formula glyph selects it")
        XCTAssertEqual(v.selFrom, v.boxes[0].textStart)
        XCTAssertEqual(v.selTo, v.boxes[0].textStart + 1, "the selection covers exactly the one-char atom")
        XCTAssertEqual(v.currentFormula(), "x^2", "the selected atom is the formula")
    }

    func test_clickOffFormula_doesNotSelect() {
        let v = paragraphCanvas()
        v.insertFormula(latex: "x^2")
        v.commitText("ab")
        let endRect = v.caretRect(forGlobal: v.boxes[0].textStart + 3)   // after "ab", away from the atom
        let p = CGPoint(x: endRect.midX + 1, y: endRect.midY)
        XCTAssertFalse(v.selectFormula(atCanvasPoint: p), "a click away from the formula is not a formula selection")
    }

    func test_rightClickOnFormula_retargetsCaretForEditing() {
        let v = paragraphCanvas()
        v.insertFormula(latex: "x^2")
        v.commitText("abc")                              // text after the atom so the caret can move away
        v.setCaret(global: v.boxes[0].textStart + 4)     // end of "⌀abc", off the formula
        XCTAssertNil(v.currentFormula(), "precondition: caret no longer on the formula")
        // A right-click landing on the formula glyph (the first position).
        let startRect = v.caretRect(forGlobal: v.boxes[0].textStart)
        let endRect = v.caretRect(forGlobal: v.boxes[0].textStart + 1)
        let p = CGPoint(x: (startRect.midX + endRect.midX) / 2, y: startRect.midY)
        v.placeCaretForContextClick(at: p)
        XCTAssertEqual(v.currentFormula(), "x^2", "right-click on a formula re-targets the caret so the menu can edit it")
    }

    func test_backspace_deletesFormulaAtom() {
        let v = paragraphCanvas()
        v.insertFormula(latex: "x^2")
        XCTAssertEqual(formulaRuns(v).count, 1)
        v.performDeleteBackward()              // caret rests after the atom
        XCTAssertTrue(formulaRuns(v).isEmpty, "Backspace removes the whole formula atom as one unit")
    }

    // MARK: Rendering / round-trip (mapper behavior, unchanged)

    func test_formulaRun_rendersAttachment() {
        let para = ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "\u{FFFC}", attributes: CharacterAttributes(formula: "x^2"))])
        let attr = AttributedStringMapper().attributedString(for: para)
        XCTAssertTrue(attr.attribute(.attachment, at: 0, effectiveRange: nil) is FormulaTextAttachment)
    }

    func test_formulaRun_roundTripsThroughMapper() {
        let para = ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "\u{FFFC}", attributes: CharacterAttributes(formula: "a_b"))])
        let mapper = AttributedStringMapper()
        let back = mapper.runs(from: mapper.attributedString(for: para))
        XCTAssertEqual(back.first?.attributes.formula, "a_b")
    }
}
#endif
