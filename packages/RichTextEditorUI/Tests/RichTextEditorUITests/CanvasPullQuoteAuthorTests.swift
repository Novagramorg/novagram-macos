#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// A pull quote's attribution ("author") line: a second editable region rendered as a centered
/// bold+italic caption below the quote text. Present only when the quote has content; edited via the
/// region-aware engine (its own layout, distinct from the quote text). Mirrors the UIKit editor.
@available(macOS 12, *)
final class CanvasPullQuoteAuthorTests: AppKitTestCase {
    private func host(_ pq: PullQuote, width: CGFloat = 400) -> (DocumentCanvasView, PullQuoteBox) {
        let v = DocumentCanvasView()
        v.setBlocks([.pullQuote(pq)], width: width)
        _ = hostInWindow(v)
        v.layoutSubtreeIfNeeded()
        guard let box = v.boxes.first as? PullQuoteBox else { XCTFail("expected a pull quote"); fatalError() }
        return (v, box)
    }

    // MARK: model round-trip

    func test_pullQuoteWithAuthor_roundTripsAuthorText() {
        let (_, pq) = host(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Few understood")],
                                     author: [TextRun(text: "Ada")]))
        guard case let .pullQuote(model) = pq.currentBlock() else { return XCTFail("not a pull quote") }
        XCTAssertEqual(model.author.map(\.text).joined(), "Ada")
    }

    func test_pullQuoteAuthor_stripsAmbientBoldItalicColorOnReadBack() {
        // The author is rendered forced bold+italic in the ambient author color; none of that must persist.
        let (_, pq) = host(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Q")], author: [TextRun(text: "Ada")]))
        guard case let .pullQuote(model) = pq.currentBlock(), let a = model.author.first else { return XCTFail() }
        XCTAssertFalse(a.attributes.bold, "ambient bold is stripped")
        XCTAssertFalse(a.attributes.italic, "ambient italic is stripped")
        XCTAssertNil(a.attributes.foreground, "ambient author color is stripped")
    }

    func test_pullQuoteAuthor_isRenderedBoldItalicCentered() {
        let (_, pq) = host(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Q")], author: [TextRun(text: "Ada")]))
        let attrs = pq.authorLayout.attributedString.attributes(at: 0, effectiveRange: nil)
        let font = attrs[.font] as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true, "author renders bold")
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.italic) == true, "author renders italic")
        XCTAssertEqual((attrs[.paragraphStyle] as? NSParagraphStyle)?.alignment, .center, "author is centered")
    }

    // MARK: position model

    func test_authorLeafRegion_presentWhenShown_withCorrectPositions() {
        let (v, pq) = host(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Few")], author: [TextRun(text: "Ada")]))
        let authorRegions = v.allLeafRegions().filter { if case .quoteAuthor = $0.ref { return true }; return false }
        XCTAssertEqual(authorRegions.count, 1, "the shown author is one leaf region")
        XCTAssertEqual(authorRegions.first?.globalStart, pq.authorRegionStart)
        XCTAssertEqual(authorRegions.first?.length, ("Ada" as NSString).length)
        // nodeSize accounts for the quote text (+2 base) plus the author region (+authorLength+2).
        XCTAssertEqual(pq.nodeSize, pq.length + pq.authorLength + 4)
    }

    func test_emptyPullQuote_hidesAuthorRegion() {
        let (v, pq) = host(PullQuote(id: BlockID("q"), runs: [], author: []))
        XCTAssertFalse(pq.shouldShowAuthor)
        XCTAssertEqual(v.allLeafRegions().filter { if case .quoteAuthor = $0.ref { return true }; return false }.count, 0)
        XCTAssertEqual(pq.nodeSize, pq.length + 2, "no author tokens when hidden")
    }

    func test_nonEmptyQuote_emptyAuthor_stillShowsAuthorRegion() {
        // A quote with text but no author still exposes an (empty) author region so it's discoverable.
        let (v, pq) = host(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Q")], author: []))
        XCTAssertTrue(pq.shouldShowAuthor)
        XCTAssertEqual(v.allLeafRegions().filter { if case .quoteAuthor = $0.ref { return true }; return false }.count, 1)
    }

    // MARK: caret / tap routing

    func test_tapBelowQuoteText_landsInAuthorRegion() {
        let (v, pq) = host(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Few understood")], author: [TextRun(text: "Ada")]))
        let p = CGPoint(x: pq.authorOrigin.x + 2, y: pq.authorOrigin.y + 2)
        let pos = pq.closestPosition(toCanvasPoint: p)
        XCTAssertGreaterThanOrEqual(pos, pq.authorRegionStart, "a tap on the author line resolves into the author region")
        XCTAssertTrue(v.isAuthorPosition(pos))
    }

    // MARK: editing

    func test_typingIntoEmptyAuthor_writesAuthor_leavesQuoteTextUntouched() {
        let (v, pq) = host(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Quote")], author: []))
        v.setCaret(global: pq.authorRegionStart)
        v.insertText("Ada", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(pq.authorLayout.attributedString.string, "Ada")
        XCTAssertEqual(pq.layout.attributedString.string, "Quote", "the quote text is untouched")
        // The first author character took the author style (bold+italic caption).
        let font = pq.authorLayout.attributedString.attributes(at: 0, effectiveRange: nil)[.font] as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    func test_backspaceInAuthor_deletesAuthorChar_notQuoteText() {
        let (v, pq) = host(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Quote")], author: [TextRun(text: "Ada")]))
        v.setCaret(global: pq.authorRegionStart + ("Ada" as NSString).length)   // caret at end of author
        v.performDeleteBackward()
        XCTAssertEqual(pq.authorLayout.attributedString.string, "Ad")
        XCTAssertEqual(pq.layout.attributedString.string, "Quote", "the quote text is untouched")
    }

    func test_backspaceAtAuthorStart_isNoOp() {
        let (v, pq) = host(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Quote")], author: [TextRun(text: "Ada")]))
        v.setCaret(global: pq.authorRegionStart)
        v.performDeleteBackward()
        XCTAssertEqual(pq.authorLayout.attributedString.string, "Ada", "author unchanged")
        XCTAssertEqual(pq.layout.attributedString.string, "Quote", "quote text unchanged")
    }
}
#endif
