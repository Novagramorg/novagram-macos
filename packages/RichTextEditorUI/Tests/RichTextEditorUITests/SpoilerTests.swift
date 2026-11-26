#if canImport(AppKit)
import AppKit
import XCTest
import RichTextEditorCore
@testable import RichTextEditorUI

@available(macOS 12, *)
final class SpoilerTests: XCTestCase {
    func testForwardAndReadBack() {
        let mapper = AttributedStringMapper()
        var ca = CharacterAttributes(); ca.spoiler = true
        let dict = mapper.attributes(for: ca, style: .body)
        XCTAssertEqual(dict[.rtSpoiler] as? Bool, true)
        XCTAssertTrue(mapper.characterAttributes(from: dict).spoiler)
    }

    func testToggleSpoilerSetsFlagOnSelection() {
        let view = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        view.document = Document(blocks: [.paragraph(ParagraphBlock(id: .generate(), runs: [TextRun(text: "secret")]))])
        view.layoutSubtreeIfNeeded()
        view.makeEditorFirstResponder()
        view.selectAll()
        view.toggleSpoiler()
        guard case let .paragraph(p) = view.document.blocks[0] else { return XCTFail("expected paragraph") }
        XCTAssertTrue(p.runs.allSatisfy { $0.attributes.spoiler })
        XCTAssertFalse(p.runs.isEmpty)
    }

    /// Regression for the spoiler clear-foreground hide being removed BEFORE a storage mutation (not
    /// after): once a run is HIDDEN (its clear-foreground rendering attribute applied), an edit before
    /// the run must not corrupt or drop content. We hide "text" (a sub-range), park the caret outside it
    /// so the hide is actually applied, then insert a character before the run and assert the document
    /// text round-trips intact and the spoiler flag survives.
    ///
    /// Limitation: the precise "no stale clear-foreground attribute lingers" assertion needs a render
    /// pass to observe, which isn't reachable in a unit test; instead we assert model/round-trip
    /// integrity after the edit (no characters lost, run still spoiler), which is what a stale hide
    /// corrupting the storage mutation would break.
    func testHiddenSpoilerSurvivesEditBeforeRunWithoutCorruptingText() {
        let view = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        view.document = Document(blocks: [.paragraph(ParagraphBlock(id: .generate(), runs: [TextRun(text: "secret text")]))])
        view.layoutSubtreeIfNeeded()
        view.makeEditorFirstResponder()
        let canvas = view.canvas

        let start = canvas.firstRenderableGlobal()           // global offset of the paragraph's first char
        let spoilerStart = start + 7                          // "secret " is 7 chars; spoiler covers "text"
        let spoilerEnd = start + 11
        canvas.selectedGlobalRange = (spoilerStart, spoilerEnd)
        view.toggleSpoiler()

        canvas.setCaret(global: start)                        // park outside the run → the hide gets applied
        view.layoutSubtreeIfNeeded()
        canvas.syncSpoilers()

        canvas.commitText("X")                                // edit BEFORE the hidden run

        XCTAssertEqual(canvas.text(inGlobalRange: 0, canvas.documentSizeValue), "Xsecret text",
                       "edit before a hidden spoiler run must not drop/corrupt characters")
        guard case let .paragraph(p) = view.document.blocks[0] else { return XCTFail("expected paragraph") }
        XCTAssertTrue(p.runs.contains { $0.attributes.spoiler && $0.text == "text" },
                      "the spoiler run must round-trip with spoiler == true after the edit")
    }
}
#endif
