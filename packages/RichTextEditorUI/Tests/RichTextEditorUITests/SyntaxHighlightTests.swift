#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
@testable import RichTextEditorCore

/// The editor-owned syntax-highlight machinery: detection, debounce, cache, apply — against a stub
/// provider (the package cannot see the app's `CodeSyntax`/libprisma wrapper). Port of the UIKit
/// editor's `SyntaxHighlightTests`, adapted to the AppKit canvas (which draws code blocks directly,
/// so "repaint the block view" becomes a canvas `needsDisplay` counted by the same test seam).
@available(macOS 12, *)
final class SyntaxHighlightTests: XCTestCase {
    /// Records every request the canvas makes and lets a test answer them on demand.
    final class StubHighlighter {
        private(set) var requests: [(language: String, text: String)] = []
        private var pending: [([RichTextSyntaxToken]) -> Void] = []

        func provider(_ language: String, _ text: String, _ completion: @escaping ([RichTextSyntaxToken]) -> Void) {
            self.requests.append((language, text))
            self.pending.append(completion)
        }

        func answerAll(with tokens: [RichTextSyntaxToken]) {
            let pending = self.pending
            self.pending = []
            for completion in pending { completion(tokens) }
        }
    }

    private func makeCanvas(_ blocks: [Block], stub: StubHighlighter) -> DocumentCanvasView {
        let canvas = DocumentCanvasView()
        canvas.syntaxHighlightDebounceInterval = 0   // fire on the next runloop turn, not after 300ms
        canvas.syntaxHighlighter = { language, text, completion in stub.provider(language, text, completion) }
        canvas.setBlocks(blocks, width: 320)
        return canvas
    }

    /// Spins the main runloop so the debounced pass — and any answer delivered from it — actually runs.
    /// NOT `DispatchQueue.main.async { fulfill }`: `asyncAfter` is timer-backed, so a plain async block
    /// enqueued afterwards can run FIRST and the wait returns before the pass has fired.
    private func settle(_ interval: TimeInterval = 0.1) {
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    }

    func test_requestsAHighlightForACodeBlockWithALanguage() {
        let stub = StubHighlighter()
        // Hold the canvas: the debounced pass captures `self` weakly, so a canvas nobody retains is
        // deallocated before the pass fires and the test measures nothing.
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "Swift", runs: [TextRun(text: "let x = 1")]))], stub: stub)
        settle()
        XCTAssertEqual(canvas.boxes.count, 1)
        XCTAssertEqual(stub.requests.count, 1)
        guard stub.requests.count == 1 else { return }
        XCTAssertEqual(stub.requests[0].language, "swift")   // normalized before it leaves the editor
        XCTAssertEqual(stub.requests[0].text, "let x = 1")
    }

    func test_doesNotRequestWithoutALanguageOrWithoutCode() {
        let stub = StubHighlighter()
        // A fourth, VALID block is the control: without it this test passes just as happily against a
        // canvas that requests nothing at all (which is exactly what a deallocated one does).
        let canvas = makeCanvas([
            .code(CodeBlock(id: BlockID("a"), language: nil, runs: [TextRun(text: "let x = 1")])),
            .code(CodeBlock(id: BlockID("b"), language: "  ", runs: [TextRun(text: "let x = 1")])),
            .code(CodeBlock(id: BlockID("c"), language: "swift", runs: [])),
            .code(CodeBlock(id: BlockID("d"), language: "swift", runs: [TextRun(text: "valid")])),
        ], stub: stub)
        settle()
        XCTAssertEqual(canvas.boxes.count, 4)
        XCTAssertEqual(stub.requests.count, 1, "only the fourth block is eligible")
        XCTAssertEqual(stub.requests.first?.text, "valid")
    }

    func test_burstOfEditsCoalescesIntoOneRequestCarryingTheFinalText() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: []))], stub: stub)
        settle()
        stub.answerAll(with: [])
        let codeStart = canvas.boxes[0].textStart
        canvas.setCaret(global: codeStart)
        canvas.commitText("a")
        canvas.commitText("b")
        canvas.commitText("c")
        settle()
        XCTAssertEqual(stub.requests.count, 1, "three keystrokes must debounce into one pass")
        XCTAssertEqual(stub.requests[0].text, "abc")
    }

    func test_anAnsweredSpecIsNotRequestedAgain() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "ab")]))], stub: stub)
        settle()
        stub.answerAll(with: [])
        XCTAssertEqual(stub.requests.count, 1)
        canvas.scheduleSyntaxHighlightPass()
        settle()
        XCTAssertEqual(stub.requests.count, 1, "the same (language, text) must be served from the cache")
    }

    // An unknown language answers with an empty token list, which is cached like any other answer — so it
    // is attempted once, not on every pass.
    func test_anEmptyAnswerIsCachedLikeAnyOther() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "brainfuck", runs: [TextRun(text: "+++")]))], stub: stub)
        settle()
        stub.answerAll(with: [])
        XCTAssertFalse(canvas.syntaxHighlightCacheIsEmptyForTesting, "the empty answer must be STORED, not discarded")
        canvas.scheduleSyntaxHighlightPass()
        settle()
        XCTAssertEqual(stub.requests.count, 1)
    }

    func test_evictsAnAnswerWhoseCodeBlockIsGone() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "ab")]))], stub: stub)
        settle()
        stub.answerAll(with: [])
        canvas.setBlocks([.paragraph(ParagraphBlock(id: BlockID("p"), style: .body, runs: [TextRun(text: "x")]))], width: 320)
        settle()
        XCTAssertTrue(canvas.syntaxHighlightCacheIsEmptyForTesting)
    }

    func test_tokensColourTheirRangesInTheCodeLayout() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "let x = 1")]))], stub: stub)
        settle()
        stub.answerAll(with: [RichTextSyntaxToken(range: NSRange(location: 0, length: 3), color: .red)])
        let box = canvas.boxes[0] as! CodeBlockBox
        XCTAssertEqual(box.layout.attributedString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.red)
        XCTAssertNotEqual(box.layout.attributedString.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor, NSColor.red)
    }

    // The editor's documented idempotence rule: an unconditional re-assign of a layout's string resets the
    // spoiler-hide ranges and re-invalidates the layout.
    func test_anIdenticalAnswerDoesNotReassignTheLayoutString() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "let x = 1")]))], stub: stub)
        settle()
        let tokens = [RichTextSyntaxToken(range: NSRange(location: 0, length: 3), color: .red)]
        stub.answerAll(with: tokens)
        let box = canvas.boxes[0] as! CodeBlockBox
        XCTAssertFalse(box.applySyntaxHighlight(tokens), "re-applying the same tokens must be a no-op")
    }

    func test_anEmptyAnswerLeavesTheBlockPlain() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "let x = 1")]))], stub: stub)
        settle()
        stub.answerAll(with: [])
        let box = canvas.boxes[0] as! CodeBlockBox
        let colour = box.layout.attributedString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(colour, box.mapper.appearance.defaultForeground)
    }

    // Colours are display-only: they must never round-trip into the model.
    func test_highlightNeverReachesTheModel() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "Swift", runs: [TextRun(text: "let x = 1")]))], stub: stub)
        settle()
        stub.answerAll(with: [RichTextSyntaxToken(range: NSRange(location: 0, length: 3), color: .red)])
        guard case let .code(code) = canvas.boxes[0].currentBlock() else { return XCTFail("expected a code block") }
        XCTAssertEqual(code.text, "let x = 1")
        XCTAssertEqual(code.language, "Swift")   // as typed; the request normalized a COPY, not the model
    }

    // A token range that no longer fits the text (an answer arriving after an edit) is dropped WHOLE.
    func test_staleTokensAreRejectedWholesale() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "abc")]))], stub: stub)
        settle()
        let box = canvas.boxes[0] as! CodeBlockBox
        XCTAssertFalse(box.applySyntaxHighlight([
            RichTextSyntaxToken(range: NSRange(location: 0, length: 1), color: .red),
            RichTextSyntaxToken(range: NSRange(location: 2, length: 99), color: .red),
        ]))
        XCTAssertNotEqual(box.layout.attributedString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, NSColor.red)
    }

    func test_applyingTokensRepaints() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "let x = 1")]))], stub: stub)
        settle()
        let before = canvas.codeHighlightRepaintCountForTesting
        stub.answerAll(with: [RichTextSyntaxToken(range: NSRange(location: 0, length: 3), color: .red)])
        XCTAssertGreaterThan(canvas.codeHighlightRepaintCountForTesting, before,
                             "a colour change must repaint the canvas")
    }

    func test_anIdenticalAnswerDoesNotRepaint() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "let x = 1")]))], stub: stub)
        settle()
        let tokens = [RichTextSyntaxToken(range: NSRange(location: 0, length: 3), color: .red)]
        stub.answerAll(with: tokens)
        let after = canvas.codeHighlightRepaintCountForTesting
        canvas.applySyntaxHighlightsToBoxes()
        XCTAssertEqual(canvas.codeHighlightRepaintCountForTesting, after, "no change, no repaint")
    }

    // A theme change rebuilds every box FROM THE MODEL, which carries no colours. Waiting for the
    // debounced pass to repaint them shows a plain frame first — the "text loses highlight on a
    // dark/light switch" report from the UIKit editor. The cache already holds the answer, so a rebuild
    // must apply it synchronously.
    func test_aRebuildKeepsTheHighlightWithoutWaitingForAPass() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "let x = 1")]))], stub: stub)
        settle()
        stub.answerAll(with: [RichTextSyntaxToken(range: NSRange(location: 0, length: 3), color: .red)])

        // What `RichTextEditorView.editorAppearance`'s setter does: re-theme the mapper, then reload
        // every box from the current model.
        var dark = EditorAppearance.default
        dark.defaultForeground = .white
        canvas.editorAppearance = dark

        // NO settle: the colours must be there in the very first frame after the rebuild.
        let box = canvas.boxes[0] as! CodeBlockBox
        XCTAssertEqual(box.layout.attributedString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       NSColor.red, "a rebuild must re-apply the cached highlight synchronously")
        XCTAssertEqual(stub.requests.count, 1, "and must not re-request synchronously — the pass is debounced")
    }

    // Unlike the UIKit hosts (which bake a FIXED light palette, making (language, text) a complete cache
    // identity), the macOS host builds its `SyntaxterTheme` from the LIVE app theme at request time — so
    // the same code answers different colours per theme. A light/dark switch must therefore re-ask, or the
    // block keeps the previous palette forever: dark-theme colours drawn on a light code band.
    func test_anAppearanceChangeReHighlightsWithTheNewPalette() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "let x = 1")]))], stub: stub)
        settle()
        stub.answerAll(with: [RichTextSyntaxToken(range: NSRange(location: 0, length: 3), color: .red)])
        XCTAssertEqual(stub.requests.count, 1)

        var dark = EditorAppearance.default
        dark.isDark = true
        dark.defaultForeground = .white
        canvas.editorAppearance = dark

        // The stale answer still paints the rebuild frame — the palette changed, not the geometry, so
        // there must be no plain flash while the fresh answer is on its way.
        let rebuilt = canvas.boxes[0] as! CodeBlockBox
        XCTAssertEqual(rebuilt.layout.attributedString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       NSColor.red, "the rebuild frame keeps the old colours as a placeholder")

        settle()
        XCTAssertEqual(stub.requests.count, 2, "a new palette makes the cached answer stale — it must be re-asked")
        guard stub.requests.count == 2 else { return }
        XCTAssertEqual(stub.requests[1].language, "swift")
        XCTAssertEqual(stub.requests[1].text, "let x = 1")

        stub.answerAll(with: [RichTextSyntaxToken(range: NSRange(location: 0, length: 3), color: .green)])
        let box = canvas.boxes[0] as! CodeBlockBox
        XCTAssertEqual(box.layout.attributedString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       NSColor.green, "the new palette's colours must land")
    }

    // The other half of the same rule: the palette identity is a VALUE, so re-assigning a colour-identical
    // appearance asks for nothing. The inline chat composer builds a fresh `EditorAppearance` on every
    // update pass, so a generation counter bumped per assignment — or a cache cleared per rebuild — would
    // re-request every spec on every layout.
    func test_aColourIdenticalAppearanceReassignDoesNotReRequest() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "let x = 1")]))], stub: stub)
        settle()
        stub.answerAll(with: [RichTextSyntaxToken(range: NSRange(location: 0, length: 3), color: .red)])
        XCTAssertEqual(stub.requests.count, 1)

        for _ in 0 ..< 3 {
            canvas.editorAppearance = EditorAppearance()   // freshly built, same colours as `.default`
            settle()
        }
        XCTAssertEqual(stub.requests.count, 1, "an unchanged palette must keep being served from the cache")
        let box = canvas.boxes[0] as! CodeBlockBox
        XCTAssertEqual(box.layout.attributedString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
                       NSColor.red)
    }

    // An unknown language's empty answer is cached per palette too: re-asked once when the palette changes,
    // never again while it stays put.
    func test_anEmptyAnswerIsReRequestedOncePerPalette() {
        let stub = StubHighlighter()
        let canvas = makeCanvas([.code(CodeBlock(id: BlockID("c"), language: "brainfuck", runs: [TextRun(text: "+++")]))], stub: stub)
        settle()
        stub.answerAll(with: [])

        var dark = EditorAppearance.default
        dark.isDark = true
        dark.defaultForeground = .white
        canvas.editorAppearance = dark
        settle()
        XCTAssertEqual(stub.requests.count, 2)
        stub.answerAll(with: [])

        canvas.scheduleSyntaxHighlightPass()
        settle()
        XCTAssertEqual(stub.requests.count, 2, "the empty answer is cached under the new palette like any other")
    }
}
#endif
