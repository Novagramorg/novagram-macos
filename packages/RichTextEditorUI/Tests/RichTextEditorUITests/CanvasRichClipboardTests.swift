#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// Rich (attribute-preserving) copy/paste within the editor: selection→fragment extraction, multi-block
/// fragment insertion, the full copy→paste round-trip via a fake pasteboard, and multi-line plain paste.
@available(macOS 12, *)
final class CanvasRichClipboardTests: AppKitTestCase {
    private final class FakePasteboard: TextPasteboard {
        var string: String?
        var richFragment: Data?
        var hasStrings: Bool { !(string ?? "").isEmpty }
    }
    private func canvas(_ blocks: [Block]) -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setBlocks(blocks, width: 400)
        _ = hostInWindow(v); v.frame = CGRect(x: 0, y: 0, width: 400, height: 400); v.layoutSubtreeIfNeeded()
        return v
    }
    private func bold(_ t: String) -> TextRun { TextRun(text: t, attributes: CharacterAttributes(bold: true)) }
    private func paras(_ v: DocumentCanvasView) -> [ParagraphBlock] {
        v.currentBlocks().compactMap { if case .paragraph(let p) = $0 { return p } else { return nil } }
    }

    func test_selectedFragment_slicesRunsWithAttributes() {
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "ab"), bold("CD")]))])
        v.selectedGlobalRange = (v.boxes[0].textStart + 1, v.boxes[0].textStart + 3)   // "bC"
        guard case .paragraph(let p) = v.selectedFragment().first else { return XCTFail() }
        XCTAssertEqual(p.runs.map(\.text).joined(), "bC")
        XCTAssertEqual(p.runs.first(where: { $0.attributes.bold })?.text, "C", "only the 'C' half keeps bold")
        XCTAssertEqual(p.runs.first(where: { !$0.attributes.bold })?.text, "b")
    }

    func test_copyPaste_preservesBoldWithinEditor() {
        let pb = FakePasteboard()
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "x"), bold("BOLD"), TextRun(text: "y")]))])
        v.pasteboard = pb
        v.selectedGlobalRange = (v.boxes[0].textStart + 1, v.boxes[0].textStart + 5)   // "BOLD"
        v.copySelectionToPasteboard()
        XCTAssertEqual(pb.string, "BOLD", "plain text is on the pasteboard too")
        XCTAssertNotNil(pb.richFragment, "the rich fragment is written")

        v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)   // caret at the end
        v.pasteFromPasteboard()
        let runs = paras(v).first!.runs
        XCTAssertEqual(runs.map(\.text).joined(), "xBOLDyBOLD")
        XCTAssertEqual(runs.filter { $0.attributes.bold }.map(\.text).joined(), "BOLDBOLD", "pasted run keeps bold")
    }

    func test_paste_multiParagraphFragment_splitsAndMergesBoundaries() {
        let pb = FakePasteboard()
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "HelloWorld")]))])
        v.pasteboard = pb
        let fragment = [Block.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "A")])),
                        Block.paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "B")]))]
        pb.richFragment = try! DocumentCodec.encode(Document(blocks: fragment))
        v.setCaret(global: v.boxes[0].textStart + 5)   // Hello|World
        v.pasteFromPasteboard()
        XCTAssertEqual(paras(v).map { $0.runs.map(\.text).joined() }, ["HelloA", "BWorld"])
    }

    func test_paste_plainMultiLine_createsParagraphs() {
        let pb = FakePasteboard(); pb.string = "one\ntwo\nthree"
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("p"), runs: []))])
        v.pasteboard = pb
        v.setCaret(global: v.boxes[0].textStart)
        v.pasteFromPasteboard()
        XCTAssertEqual(paras(v).map { $0.runs.map(\.text).joined() }, ["one", "two", "three"])
    }

    func test_copyWholeDocument_extractsBlocksWithStyles() {
        let v = canvas([
            .paragraph(ParagraphBlock(id: BlockID("p1"), style: .heading1, runs: [TextRun(text: "Title")])),
            .paragraph(ParagraphBlock(id: BlockID("p2"), runs: [TextRun(text: "body")])),
        ])
        v.selectedGlobalRange = (v.boxes[0].textStart, v.boxes[1].textStart + v.boxes[1].textLength)
        let frag = v.selectedFragment().compactMap { if case .paragraph(let p) = $0 { return p } else { return nil } }
        XCTAssertEqual(frag.map { $0.runs.map(\.text).joined() }, ["Title", "body"])
        XCTAssertEqual(frag.first?.style, .heading1, "the extracted fragment keeps each block's style")
    }

    func test_paste_intoEmptyParagraph_preservesBlockStyles() {
        let pb = FakePasteboard()
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("p"), runs: []))])   // an empty paragraph
        v.pasteboard = pb
        let fragment = [Block.paragraph(ParagraphBlock(id: BlockID("h"), style: .heading1, runs: [TextRun(text: "Title")])),
                        Block.paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "body")]))]
        pb.richFragment = try! DocumentCodec.encode(Document(blocks: fragment))
        v.setCaret(global: v.boxes[0].textStart)
        v.pasteFromPasteboard()
        let ps = paras(v)
        XCTAssertEqual(ps.map { $0.runs.map(\.text).joined() }, ["Title", "body"])
        XCTAssertEqual(ps.first?.style, .heading1, "a heading pasted into an empty paragraph keeps its style")
    }

    func testPasteContextEnclosesNativeHostAndPlainImports() throws {
        for route in 0..<5 {
            let pb = FakePasteboard()
            let v = canvas([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "x")]))])
            v.pasteboard = pb
            v.setCaret(global: v.boxes[0].textStart + v.boxes[0].textLength)
            let fragment = [Block.paragraph(ParagraphBlock(id: BlockID("pasted"), runs: [bold("hello")]))]
            pb.string = route == 3 ? "hello\r\nworld" : "hello"
            if route == 0 { pb.richFragment = try DocumentCodec.encode(Document(blocks: fragment)) }
            if route == 4 { pb.richFragment = Data("invalid".utf8) }
            var active = false, contexts = 0, mutations = 0, hostCalls = 0
            v.withPasteContext = { paste in
                contexts += 1
                active = true
                defer { active = false }
                paste()
            }
            v.hostPasteFragmentProvider = {
                XCTAssertTrue(active)
                hostCalls += 1
                return route == 1 ? fragment : nil
            }
            v.onSelectionOrFormatChange = {
                XCTAssertTrue(active)
                mutations += 1
            }
            v.pasteFromPasteboard()
            XCTAssertFalse(active)
            XCTAssertEqual(contexts, 1)
            XCTAssertEqual(hostCalls, route == 0 ? 0 : 1)
            XCTAssertGreaterThan(mutations, 0)
            XCTAssertEqual(paras(v).map { $0.runs.map(\.text).joined() }, route == 3 ? ["xhello", "world"] : ["xhello"])
            if route < 2 {
                XCTAssertEqual(paras(v).flatMap(\.runs).filter { $0.attributes.bold }.map(\.text).joined(), "hello")
            }
        }
    }

    func testEmptyPasteRunsContextWithoutChangingContent() {
        let pb = FakePasteboard()
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "keep")]))])
        v.pasteboard = pb
        var contexts = 0
        v.withPasteContext = { paste in contexts += 1; paste() }
        v.pasteFromPasteboard()
        XCTAssertEqual(contexts, 1)
        XCTAssertEqual(paras(v).flatMap(\.runs).map(\.text).joined(), "keep")
    }

    func testEditorFacadeForwardsPasteContextAndCanClearIt() {
        let editor = RichTextEditorView(frame: .zero)
        let pb = FakePasteboard()
        editor.canvas.pasteboard = pb
        var contexts = 0
        editor.withPasteContext = { paste in contexts += 1; paste() }
        XCTAssertNotNil(editor.withPasteContext)
        editor.paste()
        XCTAssertEqual(contexts, 1)
        editor.withPasteContext = nil
        XCTAssertNil(editor.canvas.withPasteContext)
        editor.paste()
        XCTAssertEqual(contexts, 1)
    }
}
#endif
