#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
@testable import RichTextEditorCore

/// Editing ACROSS a code block's language line: the language is a second, non-primary leaf region, so a
/// range with only ONE endpoint in it resolves to no `activeStack` and every naive route silently drops the
/// edit (or, for a NESTED block, splices it into the wrong box). These pin the routing that makes such a
/// range behave: `activeStack`'s container pre-guard, the covering-range language clear on BOTH endpoints of
/// a cross-block replace, and the straddling-selection arm in `applySelectionReplace`.
@available(macOS 12, *)
final class CodeLanguageEditingTests: XCTestCase {
    private final class FakePasteboard: TextPasteboard {
        var string: String?
        var richFragment: Data?
        var hasStrings: Bool { !(string ?? "").isEmpty }
    }

    private func makeCanvas(_ blocks: [Block]) -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setBlocks(blocks, width: 400)
        return v
    }

    private func para(_ id: String, _ text: String) -> Block {
        .paragraph(ParagraphBlock(id: BlockID(id), style: .body, runs: [TextRun(text: text)]))
    }

    private func code(_ id: String, language: String?, _ text: String) -> Block {
        .code(CodeBlock(id: BlockID(id), language: language, runs: [TextRun(text: text)]))
    }

    private func codeBox(_ box: any CanvasBlock) -> CodeBlockBox { box as! CodeBlockBox }

    private func paragraphText(_ box: any CanvasBlock) -> String {
        (box as! BlockBox).currentParagraph().runs.map { $0.text }.joined()
    }

    private func pasted(_ v: DocumentCanvasView, _ text: String) {
        let pb = FakePasteboard()
        pb.string = text
        v.pasteboard = pb
        v.pasteFromPasteboard()
    }

    // MARK: - A code block NESTED IN A BLOCK QUOTE

    /// Document: quote[ code(lang) ] followed by a paragraph. `descend` enters the quote by token span and
    /// cannot place a LANGUAGE position (the code box matches by its PRIMARY, i.e. code, region), so the
    /// fallback runs — and `resolveBox` walks TOP-LEVEL boxes only, skipping the quote's degenerate extent
    /// and answering with the FOLLOWING paragraph at local 0. Without the container pre-guard every caller
    /// gets a box + offset in the wrong block.
    func test_nestedCodeBlockLanguage_resolvesToNoActiveStack() {
        let v = makeCanvas([
            .blockQuote(BlockQuote(id: BlockID("q"), children: [code("c", language: "swift", "abc")])),
            para("p", "after"),
        ])
        let quote = v.boxes[0] as! BlockQuoteBox
        let inner = codeBox(quote.children.boxes[0])
        let languageStart = inner.nodeStart + 1
        XCTAssertNil(v.activeStack(at: languageStart))
        XCTAssertNil(v.activeStack(at: languageStart + 3))
        // …and the narrower question still answers, with the QUOTE's child stack — not root.
        XCTAssertTrue(v.owningStack(at: languageStart + 3) === quote.children)
        XCTAssertFalse(v.sameOwningStack(languageStart + 3, v.boxes[1].textStart + 2))
    }

    /// The consequence of the miss: Backspace over a selection running from the quoted code's language line
    /// into the following top-level paragraph deleted from the START of that paragraph (turning "after" into
    /// "ter") and left the language intact. It must route to the region-aware clear instead.
    func test_deleteFromANestedLanguageIntoTheFollowingParagraph_clearsEveryTouchedRegion() {
        let v = makeCanvas([
            .blockQuote(BlockQuote(id: BlockID("q"), children: [code("c", language: "swift", "abc")])),
            para("p", "after"),
        ])
        let quote = v.boxes[0] as! BlockQuoteBox
        let inner = codeBox(quote.children.boxes[0])
        let from = inner.nodeStart + 1 + 3            // mid-"swift"
        let to = v.boxes[1].textStart + 2             // mid-"after"
        v.selectedGlobalRange = (from, to)
        v.performDeleteBackward()
        XCTAssertEqual(inner.currentCode().language, "swi")
        XCTAssertEqual(inner.currentCode().text, "")
        XCTAssertEqual(paragraphText(v.boxes[1]), "ter")
        XCTAssertEqual(v.selFrom, v.selTo)
    }

    /// Same selection, typing: the keystroke must land in the anchor (language) region, not at offset 0 of
    /// the following paragraph.
    func test_typingOverANestedLanguageStraddle_landsInTheLanguage() {
        let v = makeCanvas([
            .blockQuote(BlockQuote(id: BlockID("q"), children: [code("c", language: "swift", "abc")])),
            para("p", "after"),
        ])
        let quote = v.boxes[0] as! BlockQuoteBox
        let inner = codeBox(quote.children.boxes[0])
        v.selectedGlobalRange = (inner.nodeStart + 1 + 3, v.boxes[1].textStart + 2)
        v.commitText("Z")
        XCTAssertEqual(inner.currentCode().language, "swiZ")
        XCTAssertEqual(inner.currentCode().text, "")
        XCTAssertEqual(paragraphText(v.boxes[1]), "ter")
        XCTAssertEqual(v.selFrom, v.selTo)
    }

    // MARK: - Select-All in a MULTI-BLOCK document

    /// Select-All resolves the code block as a selection ENDPOINT (never a dropped middle box), so the
    /// cross-block truncate path runs — which touches only `textLayout`. Without the endpoint clears the
    /// emptied block keeps drawing, and sending, its old language.
    func test_selectAllThenDelete_clearsTheLanguageWhenTheCodeBlockIsTheLastBlock() {
        let v = makeCanvas([para("p", "before"), code("c", language: "swift", "let x = 1")])
        v.selectAllText()
        v.performDeleteBackward()
        XCTAssertNil(codeBox(v.boxes[1]).currentCode().language)
        XCTAssertEqual(codeBox(v.boxes[1]).currentCode().text, "")
    }

    func test_selectAllThenDelete_clearsTheLanguageWhenTheCodeBlockIsTheFirstBlock() {
        let v = makeCanvas([code("c", language: "swift", "let x = 1"), para("p", "after")])
        v.selectAllText()
        v.performDeleteBackward()
        XCTAssertNil(codeBox(v.boxes[0]).currentCode().language)
        XCTAssertEqual(codeBox(v.boxes[0]).currentCode().text, "")
    }

    func test_selectAllThenTyping_clearsTheLanguageToo() {
        let v = makeCanvas([para("p", "before"), code("c", language: "swift", "let x = 1")])
        v.selectAllText()
        v.commitText("Z")
        XCTAssertNil(codeBox(v.boxes[1]).currentCode().language)
        XCTAssertEqual(paragraphText(v.boxes[0]), "Z")
    }

    // MARK: - Straddling selections: language → code (one block)

    func test_deleteAcrossTheLanguageIntoTheCode_clearsBothRegions() {
        let v = makeCanvas([code("c", language: "swift", "abcd")])
        let box = codeBox(v.boxes[0])
        v.selectedGlobalRange = (box.nodeStart + 1 + 2, box.textStart + 2)
        v.performDeleteBackward()
        XCTAssertEqual(box.currentCode().language, "sw")
        XCTAssertEqual(box.currentCode().text, "cd")
        XCTAssertEqual(v.selFrom, v.selTo)
    }

    func test_typingAcrossTheLanguageIntoTheCode_landsInTheLanguage() {
        let v = makeCanvas([code("c", language: "swift", "abcd")])
        let box = codeBox(v.boxes[0])
        v.selectedGlobalRange = (box.nodeStart + 1 + 2, box.textStart + 2)
        v.commitText("Z")
        XCTAssertEqual(box.currentCode().language, "swZ")
        XCTAssertEqual(box.currentCode().text, "cd")
        XCTAssertEqual(v.selFrom, v.selTo)
    }

    func test_pasteAcrossTheLanguageIntoTheCode_landsInTheLanguage() {
        let v = makeCanvas([code("c", language: "swift", "abcd")])
        let box = codeBox(v.boxes[0])
        v.selectedGlobalRange = (box.nodeStart + 1 + 2, box.textStart + 2)
        pasted(v, "P")
        XCTAssertEqual(box.currentCode().language, "swP")
        XCTAssertEqual(box.currentCode().text, "cd")
        XCTAssertEqual(v.selFrom, v.selTo)
    }

    // MARK: - Straddling selections: language → the FOLLOWING block

    func test_deleteFromTheLanguageIntoTheFollowingParagraph_clearsEveryTouchedRegion() {
        let v = makeCanvas([code("c", language: "swift", "abc"), para("p", "after")])
        let box = codeBox(v.boxes[0])
        v.selectedGlobalRange = (box.nodeStart + 1 + 3, v.boxes[1].textStart + 2)
        v.performDeleteBackward()
        XCTAssertEqual(box.currentCode().language, "swi")
        XCTAssertEqual(box.currentCode().text, "")
        XCTAssertEqual(paragraphText(v.boxes[1]), "ter")
        XCTAssertEqual(v.selFrom, v.selTo)
    }

    func test_typingFromTheLanguageIntoTheFollowingParagraph_landsInTheLanguage() {
        let v = makeCanvas([code("c", language: "swift", "abc"), para("p", "after")])
        let box = codeBox(v.boxes[0])
        v.selectedGlobalRange = (box.nodeStart + 1 + 3, v.boxes[1].textStart + 2)
        v.commitText("Z")
        XCTAssertEqual(box.currentCode().language, "swiZ")
        XCTAssertEqual(paragraphText(v.boxes[1]), "ter")
        XCTAssertEqual(v.selFrom, v.selTo)
    }

    func test_pasteFromTheLanguageIntoTheFollowingParagraph_landsInTheLanguage() {
        let v = makeCanvas([code("c", language: "swift", "abc"), para("p", "after")])
        let box = codeBox(v.boxes[0])
        v.selectedGlobalRange = (box.nodeStart + 1 + 3, v.boxes[1].textStart + 2)
        pasted(v, "P")
        XCTAssertEqual(box.currentCode().language, "swiP")
        XCTAssertEqual(paragraphText(v.boxes[1]), "ter")
        XCTAssertEqual(v.selFrom, v.selTo)
    }

    // MARK: - Straddling selections: the PRECEDING block → language

    func test_deleteFromTheParagraphIntoTheLanguage_clearsBothSides() {
        let v = makeCanvas([para("p", "before"), code("c", language: "swift", "let x")])
        let box = codeBox(v.boxes[1])
        v.selectedGlobalRange = (v.boxes[0].textStart + 3, box.nodeStart + 1 + 3)
        v.performDeleteBackward()
        XCTAssertEqual(paragraphText(v.boxes[0]), "bef")
        XCTAssertEqual(box.currentCode().language, "ft")
        XCTAssertEqual(box.currentCode().text, "let x")
        XCTAssertEqual(v.selFrom, v.selTo)
    }

    func test_typingFromTheParagraphIntoTheLanguage_landsInTheParagraph() {
        let v = makeCanvas([para("p", "before"), code("c", language: "swift", "let x")])
        let box = codeBox(v.boxes[1])
        v.selectedGlobalRange = (v.boxes[0].textStart + 3, box.nodeStart + 1 + 3)
        v.commitText("Z")
        XCTAssertEqual(paragraphText(v.boxes[0]), "befZ")
        XCTAssertEqual(box.currentCode().language, "ft")
        XCTAssertEqual(box.currentCode().text, "let x")
        XCTAssertEqual(v.selFrom, v.selTo)
    }

    func test_pasteFromTheParagraphIntoTheLanguage_landsInTheParagraph() {
        let v = makeCanvas([para("p", "before"), code("c", language: "swift", "let x")])
        let box = codeBox(v.boxes[1])
        v.selectedGlobalRange = (v.boxes[0].textStart + 3, box.nodeStart + 1 + 3)
        pasted(v, "P")
        XCTAssertEqual(paragraphText(v.boxes[0]), "befP")
        XCTAssertEqual(box.currentCode().language, "ft")
        XCTAssertEqual(v.selFrom, v.selTo)
    }

    // A `.Pre` language is a SINGLE-LINE string, so replacement text landing in a language anchor is
    // flattened — the same rule the wholly-inside-language typing paths already apply.
    func test_multiLineReplacementLandingInTheLanguage_isFlattened() {
        let v = makeCanvas([code("c", language: "swift", "abcd")])
        let box = codeBox(v.boxes[0])
        let from = box.nodeStart + 1 + 2
        v.replace(globalRange: (from, box.textStart + 2), withText: "x\ny")
        XCTAssertEqual(box.currentCode().language, "swx y")
        XCTAssertFalse(box.currentCode().language?.contains("\n") ?? false)
    }

    // The positive control: the identical drag ending in the CODE text (both endpoints on the top-level
    // engine's radar) must keep using the cross-block engine — the straddle arm must not swallow it.
    func test_paragraphIntoTheCodeText_stillUsesTheCrossBlockEngine() {
        let v = makeCanvas([para("p", "before"), code("c", language: "swift", "let x")])
        let box = codeBox(v.boxes[1])
        v.selectedGlobalRange = (v.boxes[0].textStart + 3, box.textStart + 3)
        v.performDeleteBackward()
        XCTAssertEqual(paragraphText(v.boxes[0]), "bef")
        XCTAssertEqual(box.currentCode().language, "swift")
        XCTAssertEqual(box.currentCode().text, " x")
    }
}
#endif
