#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasDecorationsTests: XCTestCase {
    private func canvas(_ blocks: [Block], width: CGFloat = 390) -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setBlocks(blocks, width: width)
        v.frame = CGRect(x: 0, y: 0, width: width, height: 600); v.layoutSubtreeIfNeeded()
        return v
    }

    private func quoteBlock(_ id: String, _ texts: [String]) -> Block {
        .blockQuote(BlockQuote(id: BlockID(id), children: texts.enumerated().map { i, t in
            .paragraph(ParagraphBlock(id: BlockID("\(id)-c\(i)"), runs: [TextRun(text: t)]))
        }))
    }

    func test_blockquoteDecoration_barAndFill() {
        let v = canvas([
            .paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Body")])),
            quoteBlock("q", ["Quote"]),
        ])
        let decs = v.blockquoteDecorations()
        XCTAssertEqual(decs.count, 1)                                  // only the quote block
        XCTAssertEqual(decs[0].bar.minX, CanvasMetrics.pageMargin, accuracy: 0.5)   // bar at the text margin (16)
        XCTAssertEqual(decs[0].bar.width, 3, accuracy: 0.5)
        XCTAssertGreaterThan(decs[0].fill.width, decs[0].bar.width)    // fill spans the block
    }

    func test_quoteContainer_oneBackgroundSpanningChildren() {
        let v = canvas([
            quoteBlock("q", ["First line", "Second line"]),
        ])
        let decs = v.blockquoteDecorations()
        XCTAssertEqual(decs.count, 1)                                            // one background for the whole quote
        XCTAssertEqual(decs[0].fill.minY, v.boxes[0].frame.minY, accuracy: 0.5)  // spans the container frame
        XCTAssertEqual(decs[0].fill.maxY, v.boxes[0].frame.maxY, accuracy: 0.5)
        XCTAssertEqual(decs[0].bar.height, decs[0].fill.height, accuracy: 0.5)   // one continuous bar
    }

    func test_separateQuoteContainers_makeSeparateBackgrounds() {
        let v = canvas([
            quoteBlock("q1", ["A"]),
            .paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Body")])),
            quoteBlock("q2", ["B"]),
        ])
        XCTAssertEqual(v.blockquoteDecorations().count, 2)                     // two distinct quotes → two backgrounds
    }

    func test_nestedQuote_getsItsOwnFill() {
        let inner = Block.blockQuote(BlockQuote(id: BlockID("qi"), children: [
            .paragraph(ParagraphBlock(id: BlockID("qic"), runs: [TextRun(text: "inner")])),
        ]))
        let v = canvas([
            .blockQuote(BlockQuote(id: BlockID("qo"), children: [
                .paragraph(ParagraphBlock(id: BlockID("qoc"), runs: [TextRun(text: "outer")])),
                inner,
            ])),
        ])
        XCTAssertEqual(v.blockquoteDecorations().count, 2)                     // outer + nested fills
    }

    func test_imageEmptyCaption_showsAddCaption_andReservesLine() {
        let v = DocumentCanvasView()
        v.setModelBlocks([
            .media(MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 80, height: 50))),
            .core(.paragraph(ParagraphBlock(id: BlockID("b"), style: .body, runs: []))),
        ], width: 390)
        v.frame = CGRect(x: 0, y: 0, width: 390, height: 600); v.layoutSubtreeIfNeeded()
        // The image's empty caption always prompts "Add caption…"; the body paragraph prompts
        // "Type something…" only while the caret is on it.
        XCTAssertEqual(v.placeholderDraws().map(\.text), ["Add caption…"])
        v.setCaret(global: v.boxes[1].textStart)
        XCTAssertEqual(v.placeholderDraws().map(\.text), ["Add caption…", "Type something…"])
        // The empty caption still reserves a line, so the body paragraph sits BELOW the image block (no overlap).
        let img = v.boxes[0], body = v.boxes[1]
        XCTAssertGreaterThanOrEqual(body.frame.minY, img.frame.maxY - 0.5, "body must not overlap the image's caption area")
    }

    func test_placeholders_bodyOnly_whenEmpty() {
        let v = canvas([
            .paragraph(ParagraphBlock(id: BlockID("h"), style: .heading1, runs: [])),
            .paragraph(ParagraphBlock(id: BlockID("b"), style: .body, runs: [])),
        ])
        v.setCaret(global: v.boxes[0].textStart)
        XCTAssertTrue(v.placeholderDraws().isEmpty)                // heading has no placeholder; body isn't the caret's paragraph
        v.setCaret(global: v.boxes[1].textStart)
        XCTAssertEqual(v.placeholderDraws().map(\.text), ["Type something…"])     // only the caret's body shows a placeholder
    }

    func test_placeholders_noneWhenNonEmpty() {
        let v = canvas([.paragraph(ParagraphBlock(id: BlockID("b"), style: .body, runs: [TextRun(text: "Hi")]))])
        XCTAssertTrue(v.placeholderDraws().isEmpty)
    }
}
#endif
