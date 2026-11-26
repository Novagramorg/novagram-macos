#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class BlockBoxTests: XCTestCase {
    func test_emptyParagraphHeight_matchesOneTypedLine() {
        let mapper = AttributedStringMapper()
        let empty = BlockBox(paragraph: ParagraphBlock(id: BlockID("e"), runs: []), mapper: mapper, width: 300)
        let typed = BlockBox(paragraph: ParagraphBlock(id: BlockID("t"), runs: [TextRun(text: "x")]), mapper: mapper, width: 300)
        XCTAssertEqual(empty.height, typed.height, accuracy: 0.5, "an empty paragraph reserves exactly one typed line's height")
    }

    func test_emptyBulletHeight_matchesOneTypedLine() {
        let mapper = AttributedStringMapper()
        let empty = BlockBox(paragraph: ParagraphBlock(id: BlockID("e"), list: ListMembership(marker: .bullet), runs: []), mapper: mapper, width: 300)
        let typed = BlockBox(paragraph: ParagraphBlock(id: BlockID("t"), list: ListMembership(marker: .bullet), runs: [TextRun(text: "x")]), mapper: mapper, width: 300)
        XCTAssertEqual(empty.height, typed.height, accuracy: 0.5, "an empty bullet reserves exactly one typed line's height")
    }

    func test_buildsAndRoundTripsParagraph() {
        let p = ParagraphBlock(id: BlockID("p1"), style: .heading2, runs: [
            TextRun(text: "Hi "),
            TextRun(text: "bold", attributes: CharacterAttributes(bold: true)),
        ])
        let box = BlockBox(paragraph: p, mapper: AttributedStringMapper(), width: 300)
        XCTAssertEqual(box.length, 7)
        XCTAssertGreaterThan(box.height, 0)
        let out = box.currentParagraph()
        XCTAssertEqual(out.style, .heading2)
        XCTAssertEqual(out.runs.map(\.text).joined(), "Hi bold")
        XCTAssertTrue(out.runs.last?.attributes.bold ?? false)
    }
}

@available(macOS 12, *)
extension BlockBoxTests {
    private func boldBox(text: String) -> BlockBox {
        let mapper = AttributedStringMapper()
        let p = ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: text)])
        return BlockBox(paragraph: p, mapper: mapper, width: 200)
    }

    func test_applyDisplayOverride_setsParagraphAlignmentOnDisplayOnly() {
        let box = boldBox(text: "Hi")
        box.applyDisplayOverride(alignment: .center, forceBold: false, mapper: AttributedStringMapper())
        // Display layout reflects center alignment...
        let ps = box.layout.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(ps?.alignment, .center)
        // ...but the model's own paragraph alignment is unchanged (round-trip clean).
        XCTAssertEqual(box.currentParagraph().paragraph.alignment, .natural)
    }

    func test_applyDisplayOverride_forceBoldAddsBoldTraitOnDisplay() {
        let box = boldBox(text: "Hi")
        box.applyDisplayOverride(alignment: .left, forceBold: true, mapper: AttributedStringMapper())
        let font = box.layout.attributedString.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func test_applyDisplayOverride_nonBoldLeavesFontUntouched() {
        let box = boldBox(text: "Hi")
        let before = box.layout.attributedString.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        box.applyDisplayOverride(alignment: .left, forceBold: false, mapper: AttributedStringMapper())
        let after = box.layout.attributedString.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        XCTAssertFalse(after.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(before.pointSize, after.pointSize)
    }
}
#endif
