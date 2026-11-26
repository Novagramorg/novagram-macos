#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class OutgoingSnapshotTests: AppKitTestCase {
    private func editor(_ blocks: [RichTextOutgoingBlock]) -> RichTextEditorView {
        let editor = RichTextEditorView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        _ = hostInWindow(editor)
        editor.setOutgoingBlocks(blocks)
        editor.layoutSubtreeIfNeeded()
        return editor
    }

    func testSelectionAndLayoutKeepSnapshotStableWhileEditsChangeIt() {
        let editor = editor([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "text")]))])
        let snapshot = editor.outgoingBlocks()
        editor.selectedRange = (1, 3)
        editor.layoutSubtreeIfNeeded()
        XCTAssertEqual(editor.outgoingBlocks(), snapshot)
        editor.toggleBold()
        XCTAssertNotEqual(editor.outgoingBlocks(), snapshot)
        let formatted = editor.outgoingBlocks()
        editor.selectedRange = (5, 5)
        editor.insertText("more")
        XCTAssertNotEqual(editor.outgoingBlocks(), formatted)
    }

    func testNestedTableCodeAndQuoteSnapshotsAreStableAcrossReads() {
        let paragraph = ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "text")])
        let table = TableBlock(id: BlockID("table"), columns: [ColumnSpec(width: 100)], rows: [Row(id: BlockID("row"), isHeader: true, cells: [Cell(id: BlockID("cell"), blocks: [.paragraph(paragraph)])])])
        let editor = editor([.table(table), .code(CodeBlock(id: BlockID("code"), language: nil, runs: [TextRun(text: "code")])), .blockQuote(children: [.paragraph(paragraph)], collapsed: false)])
        let snapshot = editor.outgoingBlocks()
        XCTAssertEqual(snapshot.count, 3)
        for _ in 0..<3 { editor.layoutSubtreeIfNeeded(); XCTAssertEqual(editor.outgoingBlocks(), snapshot) }
    }

    func testMediaCaptionSpoilerAndGroupOrderParticipateInEquality() {
        let blocks: [RichTextOutgoingBlock] = [.media(kind: "map", mediaID: "one", caption: [TextRun(text: "caption")], spoiler: false), .mediaGroup(kind: "collage", mediaIDs: ["two", "three"], caption: [], spoilers: [false, true])]
        let editor = editor(blocks)
        let snapshot = editor.outgoingBlocks()
        XCTAssertEqual(editor.outgoingBlocks(), snapshot)
        editor.setOutgoingBlocks(snapshot)
        XCTAssertEqual(editor.outgoingBlocks(), snapshot)
        for replacement in [RichTextOutgoingBlock.media(kind: "map", mediaID: "one", caption: [TextRun(text: "changed")], spoiler: false), .media(kind: "map", mediaID: "one", caption: [TextRun(text: "caption")], spoiler: true)] {
            editor.setOutgoingBlocks([replacement, blocks[1]])
            XCTAssertNotEqual(editor.outgoingBlocks(), snapshot)
        }
        editor.setOutgoingBlocks([blocks[0], .mediaGroup(kind: "collage", mediaIDs: ["three", "two"], caption: [], spoilers: [false, true])])
        XCTAssertNotEqual(editor.outgoingBlocks(), snapshot)
    }
}
#endif
