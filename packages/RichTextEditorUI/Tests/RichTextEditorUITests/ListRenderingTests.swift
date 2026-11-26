#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class ListRenderingTests: XCTestCase {
    private func paragraphStyle(_ block: ParagraphBlock) -> NSParagraphStyle? {
        AttributedStringMapper().attributedString(for: block)
            .attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
    }

    func test_listParagraph_isIndented_plainIsNot() {
        let listed = ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .bullet),
                                    runs: [TextRun(text: "Item")])
        let plain = ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Item")])
        XCTAssertGreaterThan(paragraphStyle(listed)?.firstLineHeadIndent ?? 0, 0)
        XCTAssertEqual(paragraphStyle(plain)?.firstLineHeadIndent ?? -1, 0)
    }

    func test_deeperLevel_indentsMore() {
        let l0 = ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .bullet, level: 0),
                                runs: [TextRun(text: "A")])
        let l1 = ParagraphBlock(id: BlockID("b"), list: ListMembership(marker: .bullet, level: 1),
                                runs: [TextRun(text: "B")])
        XCTAssertGreaterThan(paragraphStyle(l1)?.headIndent ?? 0, paragraphStyle(l0)?.headIndent ?? 0)
    }

    func test_markerToTextSpacing_isHalfTheIndentStep() {
        // The marker hangs at the level's indent; the text starts only half a step past it (the
        // bullet→text gap), not a full step as before.
        let listed = ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .bullet, level: 0),
                                    runs: [TextRun(text: "Item")])
        XCTAssertEqual(paragraphStyle(listed)?.firstLineHeadIndent ?? -1, StyleSheet.listIndentStep / 2, accuracy: 0.5)
        XCTAssertEqual(paragraphStyle(listed)?.headIndent ?? -1, StyleSheet.listIndentStep / 2, accuracy: 0.5)
    }

    func test_perLevelNestingIndent_isUnchanged() {
        // Halving the marker→text gap must NOT change how far each nesting level indents.
        let l0 = ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .bullet, level: 0), runs: [TextRun(text: "A")])
        let l1 = ParagraphBlock(id: BlockID("b"), list: ListMembership(marker: .bullet, level: 1), runs: [TextRun(text: "B")])
        let step = (paragraphStyle(l1)?.headIndent ?? 0) - (paragraphStyle(l0)?.headIndent ?? 0)
        XCTAssertEqual(step, StyleSheet.listIndentStep, accuracy: 0.5)
    }

    func test_orderedList_textInset_is4ptMoreThanBullet() {
        // A number marker is wider than a bullet, so an ordered item's text gets `orderedListTextInset`
        // more inset than a bullet item's. The marker column is unchanged (only the text shifts right).
        let ordered = ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .ordered), runs: [TextRun(text: "x")])
        let bullet  = ParagraphBlock(id: BlockID("b"), list: ListMembership(marker: .bullet),  runs: [TextRun(text: "x")])
        let oi = paragraphStyle(ordered)?.firstLineHeadIndent ?? 0
        let bi = paragraphStyle(bullet)?.firstLineHeadIndent ?? 0
        XCTAssertEqual(StyleSheet.orderedListTextInset, 4, accuracy: 0.001)
        XCTAssertEqual(oi - bi, StyleSheet.orderedListTextInset, accuracy: 0.5)
    }

    func test_orderedList_extraInset_appliesToHeadIndent_andIsFlatAcrossLevels() {
        // The +4 is a flat per-item offset (numbers need room regardless of depth); it must also apply to
        // headIndent (wrapped lines) and must NOT change the per-level nesting step.
        let o1 = ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .ordered, level: 1), runs: [TextRun(text: "x")])
        let b1 = ParagraphBlock(id: BlockID("b"), list: ListMembership(marker: .bullet,  level: 1), runs: [TextRun(text: "x")])
        XCTAssertEqual((paragraphStyle(o1)?.headIndent ?? 0) - (paragraphStyle(b1)?.headIndent ?? 0),
                       StyleSheet.orderedListTextInset, accuracy: 0.5)
    }

    private func canvas(_ blocks: [ParagraphBlock]) -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setParagraphs(blocks, width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 300); v.layoutSubtreeIfNeeded()
        return v
    }

    func test_listMarkerLabels_matchCoreNumbering() {
        let v = canvas([
            ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .ordered), runs: [TextRun(text: "One")]),
            ParagraphBlock(id: BlockID("b"), list: ListMembership(marker: .ordered), runs: [TextRun(text: "Two")]),
            ParagraphBlock(id: BlockID("c"), runs: [TextRun(text: "Plain")]),
            ParagraphBlock(id: BlockID("d"), list: ListMembership(marker: .bullet), runs: [TextRun(text: "Dot")]),
        ])
        let labels = v.listMarkerLabels()
        XCTAssertEqual(labels[BlockID("a")], "1.")
        XCTAssertEqual(labels[BlockID("b")], "2.")
        XCTAssertNil(labels[BlockID("c")])
        XCTAssertEqual(labels[BlockID("d")], "•")
        XCTAssertEqual(labels, ListNumbering.labels(for: v.currentParagraphs()))
    }

    func test_listMarker_baselineAlignsWithTextFirstLine() {
        // The marker is drawn outside the text storage; its baseline must match the paragraph's first
        // text-line baseline (which lineHeightMultiple shifts down from the natural top).
        let v = canvas([ParagraphBlock(id: BlockID("a"), style: .body,
                                       list: ListMembership(marker: .ordered), runs: [TextRun(text: "Item")])])
        let box = v.boxes[0] as! BlockBox
        let draw = v.listMarkerDraws().first { $0.id == box.id }!
        // str.draw(at:) puts the baseline at origin.y + ascender.
        let markerBaseline = draw.origin.y + draw.font.ascender
        let textBaseline = box.textOrigin.y + (box.layout.firstLineBaselineFromTop ?? 0)
        XCTAssertEqual(markerBaseline, textBaseline, accuracy: 0.5)
    }

    func test_listMarker_origin_isBelowTextOrigin_dueToLineHeightMultiple() {
        // Regression guard for the misalignment: body uses lineHeightMultiple 1.10, pushing the first
        // baseline ~2pt below the natural top, so the marker origin must sit below textOrigin.y (the old
        // code drew at textOrigin.y, leaving the number floating above the text line).
        let v = canvas([ParagraphBlock(id: BlockID("a"), style: .body,
                                       list: ListMembership(marker: .ordered), runs: [TextRun(text: "Item")])])
        let box = v.boxes[0] as! BlockBox
        let draw = v.listMarkerDraws().first { $0.id == box.id }!
        XCTAssertGreaterThan(draw.origin.y, box.textOrigin.y)
    }

    func test_listMarkerDraws_oneEntryPerListBox_withLabelAndIndentColumn() {
        let v = canvas([
            ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .ordered), runs: [TextRun(text: "One")]),
            ParagraphBlock(id: BlockID("c"), runs: [TextRun(text: "Plain")]),
            ParagraphBlock(id: BlockID("d"), list: ListMembership(marker: .bullet, level: 1), runs: [TextRun(text: "Dot")]),
        ])
        let draws = v.listMarkerDraws()
        XCTAssertEqual(draws.count, 2)   // the plain block contributes no marker
        let a = draws.first { $0.id == BlockID("a") }!
        XCTAssertEqual(a.label, "1.")
        XCTAssertEqual(a.origin.x, (v.boxes[0] as! BlockBox).textOrigin.x, accuracy: 0.5)   // level 0 → no indent
        let d = draws.first { $0.id == BlockID("d") }!
        XCTAssertEqual(d.label, "◦")
        XCTAssertEqual(d.origin.x, (v.boxes[2] as! BlockBox).textOrigin.x + StyleSheet.listIndentStep, accuracy: 0.5)  // level 1
    }

    func test_setList_appliesBulletToTouchedBlocks() {
        let v = canvas([
            ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Alpha")]),
            ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Beta")]),
        ])
        v.anchor = v.boxes[0].textStart
        v.head = v.boxes[1].textStart + 1
        v.setList(.bullet)
        XCTAssertEqual((v.boxes[0] as! BlockBox).listMembership?.marker, .bullet)
        XCTAssertEqual((v.boxes[1] as! BlockBox).listMembership?.marker, .bullet)
    }

    func test_setListNil_clearsMembership_andUndoRestoresIt() {
        let v = canvas([ParagraphBlock(id: BlockID("a"), list: ListMembership(marker: .bullet),
                                       runs: [TextRun(text: "Item")])])
        let um = UndoManager(); um.groupsByEvent = false
        v.undoManagerOverride = um
        v.anchor = v.boxes[0].textStart + 1; v.head = v.anchor
        um.beginUndoGrouping(); v.setList(nil); um.endUndoGrouping()
        XCTAssertNil((v.boxes[0] as! BlockBox).listMembership)
        um.undo()
        XCTAssertEqual((v.boxes[0] as! BlockBox).listMembership?.marker, .bullet)
    }
}
#endif
