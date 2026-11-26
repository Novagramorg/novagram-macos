#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
@testable import RichTextEditorCore

/// Box-level facts about `CodeBlockBox` under the container position model (the language line as a
/// second, always-present leaf region). Port of the UIKit editor's `CodeBlockBoxTests` deltas.
@available(macOS 12, *)
final class CodeBlockBoxTests: XCTestCase {
    private func makeBox(_ text: String, language: String? = "swift") -> CodeBlockBox {
        CodeBlockBox(code: CodeBlock(id: BlockID("c1"), language: language, runs: [TextRun(text: text)]),
                     mapper: AttributedStringMapper(), width: 300)
    }

    /// A code block is a CONTAINER of [languagePara, codePara]: container(2) + (lang + 2) + (code + 2).
    func test_codeBox_nodeSizeCountsBothChildren() {
        let box = makeBox("a\nbb")                 // 4 UTF-16 units of code, "swift" = 5 of language
        XCTAssertEqual(box.nodeSize, 4 + 5 + 6)
        XCTAssertEqual(box.textLength, 4)
        XCTAssertEqual(box.languageLength, 5)
    }

    func test_codeBox_textRefIsCode() {
        XCTAssertEqual(makeBox("x").textRef, .code(BlockID("c1")))
    }

    /// TWO regions, in DOCUMENT order: the language line above, then the code text.
    func test_codeBox_leafRegionsAreLanguageThenText() {
        let box = makeBox("a\nb"); box.globalStart = 5
        let regions = box.leafRegions()
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].globalStart, 6)          // nodeStart + 1
        XCTAssertEqual(regions[0].length, 5)               // "swift"
        XCTAssertEqual(regions[0].ref, .codeLanguage(BlockID("c1")))
        XCTAssertEqual(regions[1].globalStart, box.textStart)
        XCTAssertEqual(regions[1].length, 3)
        XCTAssertEqual(regions[1].ref, .code(BlockID("c1")))
    }

    /// The language line is bold and shown AS TYPED: the line became an editable field, so lowercasing it
    /// here would fight the author's own keystrokes. The renderer still lowercases at display, which is
    /// where casing is a display concern.
    func test_codeBox_languageLineIsBoldAndAsTyped() {
        let box = makeBox("x", language: "Swift")
        let line = box.languageLayout.attributedString
        XCTAssertEqual(line.string, "Swift")
        let font = line.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
    }

    /// No language, and an empty language, are the same state — an EMPTY but present region. The field is
    /// always visible (that is where the "Language" placeholder draws), so unlike the old display-only
    /// header band it is never absent and always reserves its line.
    func test_codeBox_languageLineIsPresentButEmptyWhenAbsent() {
        for box in [makeBox("x", language: nil), makeBox("x", language: "")] {
            XCTAssertEqual(box.languageLength, 0)
            XCTAssertEqual(box.languageLayout.attributedString.string, "")
            XCTAssertGreaterThan(box.languageLineExtent, CodeBlockBox.languageSpacing)
            XCTAssertNil(box.currentCode().language)
        }
    }

    /// A labelled and an unlabelled block are the SAME height: both reserve the always-visible language
    /// line. (Before the field was editable, the header band appeared only when a language was set and
    /// added its height.)
    func test_codeBox_languageLineIsReservedWhetherOrNotItIsSet() {
        let plain = makeBox("x", language: nil)
        let labelled = makeBox("x", language: "swift")
        XCTAssertEqual(labelled.height, plain.height, accuracy: 0.5)
        XCTAssertGreaterThan(plain.height, plain.topInset + plain.bottomInset)
    }

    func test_codeBox_factoryProducesCodeBlockBox() {
        let box = makeBox("x")
        guard case let .code(cb) = box.currentBlock() else { return XCTFail("expected .code") }
        XCTAssertEqual(cb.text, "x")
        XCTAssertEqual(cb.language, "swift")
    }
}
#endif
