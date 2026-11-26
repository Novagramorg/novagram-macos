#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Button-row atom helpers + Backspace handling.
///
/// A row is TEXT-FREE, and that is the whole problem this file exists to solve: `prevTextPosition`
/// walks back to the nearest position that carries text, so the generic delete machinery would skip
/// over (or wipe) whole rows. The bespoke pill handler runs first: a caret on a pill atom deletes
/// that one pill, and removing the last pill removes the row.
@available(macOS 12, *)
extension DocumentCanvasView {
    /// The row whose INTERIOR atom span (`nodeStart + 1 ... nodeStart + max(1, count)`) contains `pos`.
    func buttonRowBox(atAtom pos: Int) -> ButtonRowBox? {
        buttonRowPill(at: pos)?.box
    }

    /// The row and pill index addressed by `pos`, if it lands on a pill atom. One atom per pill
    /// (minimum one, so an empty row is still addressable).
    func buttonRowPill(at pos: Int) -> (box: ButtonRowBox, index: Int)? {
        for box in allBoxesForButtons() {
            guard let row = box as? ButtonRowBox else { continue }
            let first = row.nodeStart + 1
            let count = max(1, row.buttons.count)
            if pos >= first, pos < first + count {
                return (row, pos - first)
            }
        }
        return nil
    }

    /// The LAST pill whose atom lies within `[lo, hi]` — the one nearest the caret, so a Backspace that
    /// spans several rows removes the closest pill and leaves the rest for subsequent presses.
    func lastButtonPill(in lo: Int, _ hi: Int) -> (box: ButtonRowBox, index: Int)? {
        var result: (box: ButtonRowBox, index: Int)?
        for box in allBoxesForButtons() {
            guard let row = box as? ButtonRowBox else { continue }
            let first = row.nodeStart + 1
            let count = max(1, row.buttons.count)
            for index in 0 ..< count where (first + index) >= lo && (first + index) <= hi {
                result = (row, index)
            }
        }
        return result
    }

    /// The row whose STRUCTURAL boundary slot (`nodeStart` or the close-token slot) is `pos`. Neither
    /// slot is renderable or matched by `buttonRowPill`; a caret can still land there (stale parking,
    /// tokenizer stepping), and acting on it via the generic delete would wipe the whole row.
    func buttonRowBox(atBoundary pos: Int) -> ButtonRowBox? {
        for box in allBoxesForButtons() {
            guard let row = box as? ButtonRowBox else { continue }
            if pos == row.nodeStart || pos == row.nodeStart + row.nodeSize - 1 { return row }
        }
        return nil
    }

    /// Every box that can host a row, flattened. Rows are top-level for authoring, but one can arrive
    /// inside a block quote via the edit round-trip and must still resolve.
    func allBoxesForButtons() -> [CanvasBlock] {
        var out: [CanvasBlock] = []
        func walk(_ stack: BlockStack) {
            for box in stack.boxes {
                out.append(box)
                if let bq = box as? BlockQuoteBox, !bq.collapsed { walk(bq.children) }
            }
        }
        walk(root)
        return out
    }

    /// The stack owning `row` and its index there (root, or a block-quote child stack).
    private func owningStack(ofButtonRow row: ButtonRowBox) -> (stack: BlockStack, index: Int)? {
        func find(_ stack: BlockStack) -> (stack: BlockStack, index: Int)? {
            for (i, box) in stack.boxes.enumerated() {
                if box === row { return (stack, i) }
                if let bq = box as? BlockQuoteBox, !bq.collapsed, let hit = find(bq.children) { return hit }
            }
            return nil
        }
        return find(root)
    }

    /// Deletes ONE pill. When it was the row's last, the row itself goes. Called inside `editing { }`
    /// by the caller, so it registers as one undo step.
    @discardableResult
    func deleteButtonPill(row: ButtonRowBox, index: Int) -> Bool {
        guard let (stack, boxIndex) = owningStack(ofButtonRow: row) else { return false }

        if row.buttons.count <= 1 {
            // The last pill (or an already-empty row): remove the whole block. When the stack empties
            // (a buttons-only document), an empty paragraph takes the row's place — mirroring
            // `deleteTableBlock` — or the canvas would have ZERO blocks and every `!boxes.isEmpty`
            // guard would leave it inert. The caret parks on the nearest renderable slot BEFORE the
            // removed row (previous region end, or an adjacent row's last pill), never the raw
            // `nodeStart` — that slot is structural, and with an adjacent row following it would let
            // the next Backspace fall through to the generic replace and wipe that row whole.
            let rowStart = row.nodeStart
            var newBoxes = stack.boxes
            newBoxes.remove(at: boxIndex)
            if newBoxes.isEmpty {
                newBoxes = [BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), runs: []),
                                     mapper: mapper, width: effectiveWidth)]
            }
            stack.boxes = newBoxes
            recomputeSpans()
            let caret = snapToRenderable(max(0, rowStart), forward: false)
            anchor = caret; head = caret
            return true
        }

        row.replaceButton(at: index, with: nil)
        recomputeSpans()
        // Land on the pill that took its place, or the new last pill when the tail was removed, so
        // repeated Backspaces walk leftwards through the row.
        let remaining = max(1, row.buttons.count)
        let landing = row.nodeStart + 1 + min(index, remaining - 1)
        anchor = landing; head = landing
        return true
    }

    /// The Backspace entry point, hooked near the top of `performDeleteBackward` — before the generic
    /// selection-replace. Handles a COLLAPSED caret sitting on a pill atom, and a structural range
    /// reaching back over one or more rows; the `selFrom >= prevTextPosition(before: selTo)` guard
    /// admits such a range while excluding a genuine text selection that merely ends after a row.
    func deleteButtonPillIfNeeded() -> Bool {
        if selFrom == selTo {
            if let (row, index) = buttonRowPill(at: selTo) {
                editing { deleteButtonPill(row: row, index: index) }
                return true
            }
            // A caret stranded on a row's structural boundary slot: snap it back to the nearest
            // renderable slot (previous region end / neighbouring pill) WITHOUT deleting, so the next
            // Backspace resolves pill-by-pill instead of falling through to the generic replace.
            if buttonRowBox(atBoundary: selTo) != nil {
                let caret = snapToRenderable(selTo, forward: false)
                if caret != selTo { setCaret(global: caret) }
                return true
            }
            return false
        }
        guard selFrom >= prevTextPosition(before: selTo),
              let (row, index) = lastButtonPill(in: selFrom, selTo)
        else { return false }
        editing { deleteButtonPill(row: row, index: index) }
        return true
    }

    // MARK: - Authoring

    /// The row box with `id`, wherever it sits (root or a block-quote child stack).
    func buttonRowBox(withID id: BlockID) -> ButtonRowBox? {
        for case let row as ButtonRowBox in allBoxesForButtons() where row.id == id { return row }
        return nil
    }

    /// Inserts a button row at the caret, carrying `button` as its one pill (a blank default when the
    /// host inserts first and configures later). Mirrors the iOS command: an EMPTY caret paragraph is
    /// REPLACED (checked FIRST — an empty paragraph satisfies both `local == 0` and
    /// `local == textLength`), a caret interior to a paragraph splits it, and a caret at the start/end
    /// inserts before/after. Rows are TOP-LEVEL for authoring; one arriving inside a container via the
    /// edit round-trip still renders and round-trips, it just cannot be created there.
    func insertButtonRow(with button: ButtonRef = ButtonRef(label: [], action: .url(""))) {
        guard !boxes.isEmpty, !isInsideTable(head), !isInsideBlockQuote(head),
              let a = activeStack(at: head), a.box is BlockBox else { return }
        editing {
            if selFrom != selTo { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "") }
            guard let active = activeStack(at: head), let p = active.box as? BlockBox else { return }
            let model = ButtonRowBlock(id: BlockID.generate(),
                                       buttons: [button],
                                       alignment: .justify)
            let rowBox = ButtonRowBox(row: model, mapper: mapper, width: effectiveWidth)
            var newBoxes = active.stack.boxes
            let idx = active.index
            if p.textLength == 0 {
                newBoxes.replaceSubrange(idx...idx, with: [rowBox] as [any CanvasBlock])
            } else if active.local > 0, active.local < p.textLength {
                let (upper, lower) = p.currentParagraph().split(at: active.local, newID: BlockID.generate())
                let replacement: [any CanvasBlock] = [
                    BlockBox(paragraph: upper, mapper: mapper, width: effectiveWidth),
                    rowBox,
                    BlockBox(paragraph: lower, mapper: mapper, width: effectiveWidth),
                ]
                newBoxes.replaceSubrange(idx...idx, with: replacement)
            } else if active.local == 0 {
                newBoxes.insert(rowBox, at: idx)
            } else {
                newBoxes.insert(rowBox, at: idx + 1)
            }
            active.stack.boxes = newBoxes
            recomputeSpans()
            let caret = rowBox.nodeStart + 1
            anchor = caret; head = caret
        }
    }

    /// True when the caret's context admits `insertButtonRow` — the EXACT command guard, exposed so a
    /// host menu item's enablement cannot drift from it (an enabled-yet-inert item otherwise appears in
    /// code blocks, pull quotes, media captions, or with the caret parked on a pill atom).
    var canInsertButtonRow: Bool {
        guard !boxes.isEmpty, !isInsideTable(head), !isInsideBlockQuote(head),
              let a = activeStack(at: head) else { return false }
        return a.box is BlockBox
    }

    /// True when the current selection admits `makeSelectionInlineButton` — the EXACT command guard
    /// (one leaf region, not a code block, non-empty text), for host menu enablement.
    var canMakeSelectionInlineButton: Bool {
        guard selFrom != selTo else { return false }
        let lo = min(selFrom, selTo), hi = max(selFrom, selTo)
        guard let region = leafRegion(containingGlobal: lo)?.region else { return false }
        if case .code = region.ref { return false }
        guard hi - region.globalStart <= region.layout.attributedString.length else { return false }
        return !selectedText().isEmpty
    }

    /// True when `insertInlineButton(with:)` would act — a selection convertible to a pill, or a
    /// collapsed caret in a text run (not a code block).
    var canInsertInlineButton: Bool {
        if selFrom != selTo { return canMakeSelectionInlineButton }
        guard let region = leafRegion(containingGlobal: head)?.region else { return false }
        if case .code = region.ref { return false }
        return true
    }

    /// Inserts ONE inline pill carrying `button` at the caret — the no-selection authoring path: the
    /// pill lands at the caret like an emoji atom. With a selection it converts the selection instead
    /// (`makeSelectionInlineButton(with:)`). A code region refuses: the code block serializes its
    /// layout string verbatim, so the atom would be destroyed on the first round-trip.
    func insertInlineButton(with button: ButtonRef) {
        guard !boxes.isEmpty else { return }
        if selFrom != selTo {
            makeSelectionInlineButton(with: button)
            return
        }
        guard let (region, local) = leafRegion(containingGlobal: head) else { return }
        if case .code = region.ref { return }
        editing {
            var ca = CharacterAttributes()
            ca.button = button
            let fragment = NSAttributedString(string: "\u{FFFC}",
                                              attributes: mapper.attributes(for: ca, style: .body))
            region.layout.replace(start: local, end: local, with: fragment)
            recomputeSpans()
            let caret = region.globalStart + local + 1
            anchor = caret; head = caret
        }
    }

    /// Converts the current selection into ONE inline pill whose label is the selected text — the Link
    /// flow's analogue. The run collapses to a single `U+FFFC`, so the pill is an atom like an emoji.
    /// Requires the selection to sit inside one leaf region. A CODE region is refused: the code block
    /// serializes its layout string verbatim (`currentCode()`), so a button atom there would silently
    /// drop the attribute AND the selected text on the first model round-trip.
    func makeSelectionInlineButton() {
        guard selFrom != selTo else { return }
        let label = selectedText()
        guard !label.isEmpty else { return }
        makeSelectionInlineButton(with: ButtonRef(label: [TextRun(text: label)], action: .url("")))
    }

    /// Replaces the current selection with ONE inline pill carrying `button` — the sheet-first flow:
    /// the host collects the button's properties in its editor, then commits the configured pill here
    /// (a cancelled sheet commits nothing, so no placeholder ever enters the document).
    func makeSelectionInlineButton(with button: ButtonRef) {
        guard selFrom != selTo else { return }
        let lo = min(selFrom, selTo), hi = max(selFrom, selTo)
        guard let region = leafRegion(containingGlobal: lo)?.region else { return }
        if case .code = region.ref { return }
        let localLo = lo - region.globalStart
        let localHi = hi - region.globalStart
        guard localLo >= 0, localHi <= region.layout.attributedString.length else { return }
        editing {
            var ca = CharacterAttributes()
            ca.button = button
            let fragment = NSAttributedString(string: "\u{FFFC}",
                                              attributes: mapper.attributes(for: ca, style: .body))
            region.layout.replace(start: localLo, end: localHi, with: fragment)
            recomputeSpans()
            let caret = region.globalStart + localLo + fragment.length
            anchor = caret; head = caret
        }
    }

    /// Replaces (or, with `nil`, removes) the inline pill whose atom sits at `pos`.
    func replaceInlineButton(at pos: Int, with button: ButtonRef?) {
        guard let (region, _) = leafRegion(containingGlobal: pos) else { return }
        let local = pos - region.globalStart
        guard local >= 0, local < region.layout.attributedString.length,
              region.layout.attributedString.attribute(.attachment, at: local, effectiveRange: nil) is ButtonTextAttachment
        else { return }
        editing {
            if let button {
                var ca = CharacterAttributes()
                ca.button = button
                let fragment = NSAttributedString(string: "\u{FFFC}",
                                                  attributes: mapper.attributes(for: ca, style: .body))
                region.layout.replace(start: local, end: local + 1, with: fragment)
            } else {
                region.layout.replace(start: local, end: local + 1, with: NSAttributedString(string: ""))
            }
            recomputeSpans()
            let caret = region.globalStart + local + (button == nil ? 0 : 1)
            anchor = caret; head = caret
        }
    }

    /// The row menu's "Add Button": SHEET-FIRST — asks the host to configure a new button, and appends
    /// it only when the sheet commits. A cancelled sheet appends nothing, so a blank placeholder never
    /// enters the row. The append is one undo step.
    func requestNewButton(forRow rowID: BlockID) {
        guard let buttonEditRequested else { return }
        buttonEditRequested(ButtonRef(label: [], action: .url("")), true) { [weak self] updated in
            guard let self, let updated, let row = self.buttonRowBox(withID: rowID) else { return }
            self.editing {
                row.appendButton(updated)
                self.recomputeSpans()
                let caret = row.nodeStart + row.buttons.count
                self.anchor = caret; self.head = caret
            }
        }
    }

    /// Re-resolves the pill a pending editor sheet should act on. The click-time index can go STALE
    /// while the sheet is open (the window-level ⌘Z shortcut still reaches the canvas, and an undo can
    /// re-insert earlier pills, shifting indices) — so the completion trusts the index only when the
    /// pill there still EQUALS the clicked one, falls back to the pill's current position, and aborts
    /// when it no longer exists at all.
    private func liveIndex(of clicked: ButtonRef, clickedAt index: Int, in row: ButtonRowBox) -> Int? {
        if row.buttons.indices.contains(index), row.buttons[index] == clicked { return index }
        return row.buttons.firstIndex(of: clicked)
    }

    /// Sets a row's alignment as one undo step.
    func setButtonRowAlignment(rowID: BlockID, _ alignment: ButtonRowAlignment) {
        guard let row = buttonRowBox(withID: rowID) else { return }
        editing {
            row.setAlignment(alignment)
            recomputeSpans()
        }
    }

    /// Removes a whole row. The caret parks on the nearest renderable slot before where the row began
    /// (same snapping as `deleteButtonPill` — the raw `nodeStart` is a structural slot).
    func deleteButtonRow(rowID: BlockID) {
        guard let row = buttonRowBox(withID: rowID),
              let (stack, index) = owningStack(ofButtonRow: row) else { return }
        editing {
            let rowStart = row.nodeStart
            var newBoxes = stack.boxes
            newBoxes.remove(at: index)
            if newBoxes.isEmpty {
                newBoxes = [BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), runs: []),
                                     mapper: mapper, width: effectiveWidth)]
            }
            stack.boxes = newBoxes
            recomputeSpans()
            let caret = snapToRenderable(max(0, rowStart), forward: false)
            anchor = caret; head = caret
        }
    }

    // MARK: - Click routing

    /// Click routing, called from `mouseDown` before the caret-placement fallthrough. Returns false
    /// (letting the click place a caret normally) when the point is not on button chrome or no host
    /// wired the button editor — so the preservation-only composer keeps plain caret behavior.
    func handleButtonClickIfNeeded(at point: CGPoint) -> Bool {
        // The row's "…" menu affordance, checked FIRST: it sits beside the pills with its own rect
        // (only present when a host wired the editor — `stampButtonRowAffordances`).
        for case let row as ButtonRowBox in allBoxesForButtons() where row.hitsMenuButton(atCanvasPoint: point) {
            presentButtonRowMenu(for: row)
            return true
        }

        guard let buttonEditRequested else { return false }

        // A block-row pill: park the caret on its atom, then open the property editor.
        for case let row as ButtonRowBox in allBoxesForButtons() {
            guard let index = row.pillIndex(atCanvasPoint: point), row.buttons.indices.contains(index) else { continue }
            setCaret(global: row.nodeStart + 1 + index)
            let rowID = row.id
            let clicked = row.buttons[index]
            buttonEditRequested(clicked, true) { [weak self] updated in
                guard let self, let liveRow = self.buttonRowBox(withID: rowID),
                      let live = self.liveIndex(of: clicked, clickedAt: index, in: liveRow) else { return }
                self.editing {
                    if updated == nil {
                        self.deleteButtonPill(row: liveRow, index: live)
                    } else {
                        liveRow.replaceButton(at: live, with: updated)
                        self.recomputeSpans()
                    }
                }
            }
            return true
        }

        // An inline pill.
        guard let (attachment, position) = inlineButton(atCanvasPoint: point) else { return false }
        setCaret(global: position + 1)
        let clicked = attachment.button
        buttonEditRequested(clicked, false) { [weak self] updated in
            // The click-time position can go stale while the sheet is open (a window-level ⌘Z still
            // reaches the canvas) — only act when the atom there still carries the clicked button.
            guard let self, self.inlineButtonRef(at: position) == clicked else { return }
            self.replaceInlineButton(at: position, with: updated)
        }
        return true
    }

    /// The `ButtonRef` of the inline pill whose atom sits at `pos`, or nil.
    func inlineButtonRef(at pos: Int) -> ButtonRef? {
        guard let (region, _) = leafRegion(containingGlobal: pos) else { return nil }
        let local = pos - region.globalStart
        guard local >= 0, local < region.layout.attributedString.length,
              let attachment = region.layout.attributedString.attribute(.attachment, at: local, effectiveRange: nil) as? ButtonTextAttachment
        else { return nil }
        return attachment.button
    }

    /// The inline pill under a canvas point, with the global position of its atom.
    func inlineButton(atCanvasPoint point: CGPoint) -> (attachment: ButtonTextAttachment, position: Int)? {
        for region in allLeafRegions() {
            let attr = region.layout.attributedString
            var found: (ButtonTextAttachment, Int)?
            attr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attr.length), options: []) { value, range, stop in
                guard let attachment = value as? ButtonTextAttachment,
                      let box = region.layout.selectionRects(start: range.location, end: range.location + 1).first
                else { return }
                let canvasRect = box.offsetBy(dx: region.canvasOrigin.x, dy: region.canvasOrigin.y)
                if canvasRect.contains(point) {
                    found = (attachment, region.globalStart + range.location)
                    stop.pointee = true
                }
            }
            if let found { return found }
        }
        return nil
    }

    /// The row's "…" menu: Add Button / Alignment (submenu, current one checked) / Delete Row. Built
    /// in-package like the table structural menu, so the two authoring menus share one idiom.
    func presentButtonRowMenu(for row: ButtonRowBox) {
        let rowID = row.id
        let menu = NSMenu()
        menu.addItem(menuItem(title: editorLocalized("RichTextEditor.ButtonRow.Add", "Add Button"),
                              symbolName: "plus.circle",
                              handler: { [weak self] in self?.requestNewButton(forRow: rowID) }))
        let alignmentItem = NSMenuItem(title: editorLocalized("RichTextEditor.ButtonRow.Alignment", "Alignment"),
                                       action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let alignments: [(ButtonRowAlignment, String, String)] = [
            (.justify, "RichTextEditor.ButtonRow.AlignJustify", "Justify"),
            (.left, "RichTextEditor.ButtonRow.AlignLeft", "Left"),
            (.center, "RichTextEditor.ButtonRow.AlignCenter", "Center"),
            (.right, "RichTextEditor.ButtonRow.AlignRight", "Right"),
        ]
        for (alignment, key, fallback) in alignments {
            let item = menuItem(title: editorLocalized(key, fallback), symbolName: nil,
                                handler: { [weak self] in self?.setButtonRowAlignment(rowID: rowID, alignment) })
            item.state = row.alignment == alignment ? .on : .off
            sub.addItem(item)
        }
        alignmentItem.submenu = sub
        menu.addItem(alignmentItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(title: editorLocalized("RichTextEditor.ButtonRow.Delete", "Delete Row"),
                              symbolName: "trash",
                              handler: { [weak self] in self?.deleteButtonRow(rowID: rowID) }))
        let anchorRect = row.menuButtonCanvasRect()
        menu.popUp(positioning: nil, at: NSPoint(x: anchorRect.minX, y: anchorRect.maxY + 4), in: self)
    }
}
#endif
