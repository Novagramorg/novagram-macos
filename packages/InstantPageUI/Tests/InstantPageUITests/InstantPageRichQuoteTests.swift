import Cocoa
import XCTest
import TelegramCore
import MessageTextUtils
@testable import InstantPageUI

final class InstantPageRichQuoteTests: XCTestCase {
    override func setUp() {
        super.setUp()
        InstantPageRenderHooks.install(InstantPageRenderHooks(renderMath: { _, _, _, _, _ in
            let size = CGSize(width: 20, height: 16)
            return InstantPageMathRenderResult(image: NSImage(size: size), size: size, width: size.width, ascent: 12, descent: 4)
        }, detectLinks: { _ in }))
    }

    private func select(_ text: RichText, range: NSRange? = nil) -> RichText {
        let rendered = attributedStringForRichText(text, styleStack: InstantPageTextStyleStack())
        let selected = rendered.attributedSubstring(from: range ?? NSRange(location: 0, length: rendered.length))
        return instantPageRichTextForSelection(selected)
    }

    func testPartialSelectionPreservesNestedFormattingAndUTF16Ranges() {
        let text: RichText = .bold(.italic(.plain("A😀 quoted text")))
        XCTAssertEqual(select(text, range: NSRange(location: 4, length: 6)), .bold(.italic(.plain("quoted"))))
    }

    func testSelectionAcrossFormattingRuns() {
        let text: RichText = .concat([.plain("first "), .marked(.superscript(.plain("second")))])
        XCTAssertEqual(select(text, range: NSRange(location: 3, length: 6)), .concat([.plain("st "), .marked(.superscript(.plain("sec")))]))
    }

    func testCustomEmojiPreservesIdentityAndAltText() {
        let text: RichText = .textCustomEmoji(fileId: 12345, alt: "😀")
        XCTAssertEqual(select(text), text)
    }

    func testFormulaPreservesLatex() {
        let text: RichText = .formula(latex: "x^2 + y^2")
        XCTAssertEqual(select(text), text)
    }

    func testLinkAndSpoilerSurvivePartialSelection() {
        let text: RichText = .textSpoiler(text: .url(text: .plain("a secret link"), url: "https://example.com", webpageId: nil))
        XCTAssertEqual(select(text, range: NSRange(location: 2, length: 6)), .textSpoiler(text: .url(text: .plain("secret"), url: "https://example.com", webpageId: nil)))
    }

    func testFormulaFallbackPreservesLatex() {
        InstantPageRenderHooks.install(InstantPageRenderHooks(renderMath: { _, _, _, _, _ in nil }, detectLinks: { _ in }))
        let text: RichText = .formula(latex: "unsupported formula")
        XCTAssertEqual(select(text), text)
    }

    func testRichQuotePreviewUsesUTF16EntityRangesAcrossParts() {
        let quote = EngineMessageReplyQuote(text: "", offset: nil, entities: [], media: nil, richText: [
            .bold(.plain("😀")),
            .concat([.formula(latex: "x^2"), .textCustomEmoji(fileId: 123, alt: "👍")])
        ])
        let preview = messageReplyQuoteText(quote)
        XCTAssertEqual(preview.text, "😀\n𝑓𝑥👍")
        XCTAssertEqual(preview.entities, [
            MessageTextEntity(range: 0 ..< 2, type: .Bold),
            MessageTextEntity(range: 7 ..< 9, type: .CustomEmoji(stickerPack: nil, fileId: 123))
        ])
    }

    func testLegacyQuotePreviewPreservesEntities() {
        let entities = [MessageTextEntity(range: 0 ..< 4, type: .Italic)]
        let quote = EngineMessageReplyQuote(text: "text", offset: 3, entities: entities, media: nil)
        let preview = messageReplyQuoteText(quote)
        XCTAssertEqual(preview.text, quote.text)
        XCTAssertEqual(preview.entities, entities)
    }

    func testQuoteFocusMapsUTF16AcrossFormattingRuns() {
        let rendered = attributedStringForRichText(.concat([.plain("😀 first "), .bold(.plain("quoted")), .italic(.plain(" passage"))]), styleStack: InstantPageTextStyleStack())
        XCTAssertEqual(instantPageQuoteRanges(in: [rendered], text: "quoted pass"), [NSRange(location: 9, length: 11)])
    }

    func testQuoteFocusSpansParagraphsWithoutIncludingSurroundingText() {
        let blocks = [NSAttributedString(string: "before first"), NSAttributedString(string: "second after")]
        XCTAssertEqual(instantPageQuoteRanges(in: blocks, text: "first\nsecond"), [NSRange(location: 7, length: 5), NSRange(location: 0, length: 6)])
    }

    func testQuoteFocusUsesValidOffsetForRepeatedText() {
        let blocks = [NSAttributedString(string: "same same")]
        XCTAssertEqual(instantPageQuoteRanges(in: blocks, text: "same", range: NSRange(location: 5, length: 4)), [NSRange(location: 5, length: 4)])
    }

    func testQuoteFocusFallsBackWhenOffsetIsStaleOrInvalid() {
        let blocks = [NSAttributedString(string: "before quote after")]
        for range in [NSRange(location: 0, length: 5), NSRange(location: NSNotFound, length: 5), NSRange(location: 7, length: Int.max)] {
            XCTAssertEqual(instantPageQuoteRanges(in: blocks, text: "quote", range: range), [NSRange(location: 7, length: 5)])
        }
    }

    func testQuoteFocusMapsFormulaAndEmojiToRenderedAttachments() {
        let formula: RichText = .formula(latex: "x^2 + y^2")
        let emoji: RichText = .textCustomEmoji(fileId: 123, alt: "😀")
        let style = InstantPageTextStyleStack()
        let prefix = attributedStringForRichText(.plain("before "), styleStack: style)
        let selected = attributedStringForRichText(.concat([formula, emoji, .bold(.plain(" target"))]), styleStack: style)
        let rendered = NSMutableAttributedString(attributedString: prefix)
        rendered.append(selected)
        rendered.append(NSAttributedString(string: " after"))
        XCTAssertEqual(instantPageQuoteRanges(in: [rendered], text: formula.plainText + emoji.plainText + " target"), [NSRange(location: prefix.length, length: selected.length)])
        XCTAssertEqual(instantPageQuoteRanges(in: [rendered], text: "target"), [NSRange(location: prefix.length + selected.length - 6, length: 6)])
    }

    func testQuoteFocusDoesNotHighlightMissingOrEmptyQuote() {
        let blocks = [NSAttributedString(string: "content")]
        XCTAssertEqual(instantPageQuoteRanges(in: blocks, text: "absent"), [nil])
        XCTAssertEqual(instantPageQuoteRanges(in: blocks, text: ""), [nil])
    }

}
