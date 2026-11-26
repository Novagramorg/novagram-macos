#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// Checklist list type: a `.checklist` marker with a per-item `checked` state (Core), rendered as a
/// ☐/☑ marker, toggled by tapping the checkbox or `toggleChecklistItem()`.
@available(macOS 12, *)
final class CanvasChecklistTests: AppKitTestCase {
    private func seeded() -> (DocumentCanvasView, NSWindow) {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "task one")]))], width: 400)
        let win = hostInWindow(v); v.layoutSubtreeIfNeeded()
        return (v, win)
    }

    func test_setChecklist_marksItemUnchecked() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + 2)
        v.setList(.checklist)
        let box = v.boxes[0] as? BlockBox
        XCTAssertEqual(box?.listMembership?.marker, .checklist)
        XCTAssertEqual(box?.listMembership?.checked, false, "a new checklist item starts unchecked")
    }

    func test_switchingChecklistToBullet_dropsCheckedState() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + 2)
        v.setList(.checklist)
        v.setList(.bullet)
        let box = v.boxes[0] as? BlockBox
        XCTAssertEqual(box?.listMembership?.marker, .bullet)
        XCTAssertNil(box?.listMembership?.checked, "bullet/ordered carry no checked state")
    }

    func test_listNumbering_checklistGlyphs() {
        let unchecked = ParagraphBlock(id: BlockID("u"), list: ListMembership(marker: .checklist, checked: false))
        let checked = ParagraphBlock(id: BlockID("c"), list: ListMembership(marker: .checklist, checked: true))
        let labels = ListNumbering.labels(for: [unchecked, checked])
        XCTAssertEqual(labels[BlockID("u")], "☐", "unchecked → empty box glyph")
        XCTAssertEqual(labels[BlockID("c")], "☑", "checked → ticked box glyph")
    }

    func test_toggleChecklist_flipsChecked_andIsUndoable() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + 2)
        v.setList(.checklist)
        let um = UndoManager(); um.groupsByEvent = false; v.undoManagerOverride = um
        let box = v.boxes[0] as! BlockBox
        XCTAssertEqual(box.listMembership?.checked, false)

        um.beginUndoGrouping(); v.toggleChecklist(box); um.endUndoGrouping()
        XCTAssertEqual((v.boxes[0] as? BlockBox)?.listMembership?.checked, true, "toggle checks it")

        um.undo()
        XCTAssertEqual((v.boxes[0] as? BlockBox)?.listMembership?.checked, false, "undo restores unchecked")
    }

    func test_checklistDraw_usesEighteenPointBox_notGlyph() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + 2)
        v.setList(.checklist)
        let draw = v.listMarkerDraws().first
        XCTAssertNotNil(draw?.checkboxRect, "a checklist item draws a custom box, not a label glyph")
        XCTAssertEqual(draw?.checkboxRect?.size, NSSize(width: StyleSheet.checkboxSize, height: StyleSheet.checkboxSize))
    }

    func test_bulletDraw_hasNoCheckbox() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + 2)
        v.setList(.bullet)
        XCTAssertNil(v.listMarkerDraws().first?.checkboxRect, "bullets draw a label glyph, not a checkbox")
    }

    func test_tapInsideCheckbox_resolvesChecklistBox() {
        let (v, _) = seeded()
        v.setCaret(global: v.boxes[0].textStart + 2)
        v.setList(.checklist)
        guard let rect = v.listMarkerDraws().first?.checkboxRect else { return XCTFail("no checkbox rect") }
        XCTAssertNotNil(v.checklistBox(atCanvasPoint: CGPoint(x: rect.midX, y: rect.midY)), "tapping the box resolves its item")
        XCTAssertNil(v.checklistBox(atCanvasPoint: CGPoint(x: rect.maxX + 100, y: rect.midY)), "tapping far away resolves nothing")
    }

    func test_checklistMembership_codableRoundTrips() throws {
        let m = ListMembership(marker: .checklist, level: 1, checked: true)
        let back = try JSONDecoder().decode(ListMembership.self, from: try JSONEncoder().encode(m))
        XCTAssertEqual(back, m, "the new checked field round-trips (and is omitted/nil for bullet/ordered)")
    }
}
#endif
