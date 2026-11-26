#if canImport(AppKit)
import AppKit
import RichTextEditorCore

@available(macOS 12, *)
extension DocumentCanvasView {
    /// Per-block marker strings, computed by Core `ListNumbering` from each box's list membership
    /// (runs are irrelevant to numbering, so we pass lightweight paragraphs). Keyed by `BlockID`.
    func listMarkerLabels() -> [BlockID: String] {
        // Image blocks have no list membership → a nil-list ParagraphBlock, which ListNumbering treats
        // as a non-list paragraph (resets numbering). That is the intended behavior.
        ListNumbering.labels(for: boxes.map { box in
            ParagraphBlock(id: box.id, list: (box as? BlockBox)?.listMembership)
        })
    }

    struct ListMarkerDraw { let label: String; let origin: CGPoint; let font: NSFont; let id: BlockID; let checkboxRect: CGRect?; let checked: Bool }

    /// One draw per list box: its Core-computed marker label, the marker font, and the canvas-coordinate
    /// origin passed to `str.draw(at:)` (the line's top-left). The marker hangs at its level's indent
    /// column, and its baseline is aligned to the paragraph's first text line. Presentation only —
    /// markers are never part of the text storage.
    func listMarkerDraws() -> [ListMarkerDraw] {
        let labels = listMarkerLabels()
        guard !labels.isEmpty else { return [] }
        var draws: [ListMarkerDraw] = []
        for box in boxes {
            guard let p = box as? BlockBox, let membership = p.listMembership, let label = labels[p.id] else { continue }
            let font = mapper.styleSheet.font(for: p.style, attributes: .plain)
            let x = p.textOrigin.x + StyleSheet.listIndentStep * CGFloat(membership.level)
            // Align the marker baseline to the paragraph's first text line: `str.draw(at:)` puts the
            // baseline at origin.y + ascender, so back the origin off by the ascender from the text
            // baseline (which lineHeightMultiple shifts below the natural top).
            let baselineFromTop = p.listMarkerBaselineFromTop(markerFont: font)
            let y = p.textOrigin.y + baselineFromTop - font.ascender
            // For a checklist, draw a `checkboxSize` box (not a glyph) centred on the first line's cap region.
            var checkboxRect: CGRect? = nil
            if membership.marker == .checklist {
                let baseline = p.textOrigin.y + baselineFromTop
                let s = StyleSheet.checkboxSize
                checkboxRect = CGRect(x: x, y: baseline - font.capHeight / 2 - s / 2, width: s, height: s)
            }
            draws.append(ListMarkerDraw(label: label, origin: CGPoint(x: x, y: y), font: font, id: p.id,
                                        checkboxRect: checkboxRect, checked: membership.checked ?? false))
        }
        return draws
    }

    /// Draws each list box's marker in the indentation gutter to the left of its text. Markers are
    /// presentation only and are never part of the text storage. Checklist items draw a custom
    /// checkbox (`StyleSheet.checkboxSize`); bullets/numbers draw their label glyph in the label colour.
    func drawListMarkers(in ctx: CGContext) {
        for d in listMarkerDraws() {
            if let rect = d.checkboxRect {
                drawCheckbox(rect, checked: d.checked, in: ctx)
            } else {
                NSAttributedString(string: d.label,
                    attributes: [.font: d.font, .foregroundColor: NSColor.labelColor]).draw(at: d.origin)
            }
        }
    }

    /// Draws a checklist checkbox matching the chat's InstantPage rendering: a rounded square —
    /// link-colour fill plus a white checkmark when checked, a dimmed 1pt outline when not. The canvas
    /// is flipped (y-down), so the chat's checkmark geometry ports over directly.
    private func drawCheckbox(_ rect: CGRect, checked: Bool, in ctx: CGContext) {
        let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
        if checked {
            ctx.setFillColor(editorAppearance.linkColor.cgColor)
            ctx.addPath(path); ctx.fillPath()
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.midY))
            ctx.addLine(to: CGPoint(x: rect.minX + rect.width * 0.43, y: rect.maxY - rect.height * 0.28))
            ctx.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.28))
            ctx.strokePath()
        } else {
            ctx.setStrokeColor(NSColor.secondaryLabelColor.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(1.0)
            ctx.addPath(path); ctx.strokePath()
        }
    }

    /// The checklist box whose checkbox contains `point` (canvas coords), for tap-to-toggle.
    func checklistBox(atCanvasPoint point: CGPoint) -> BlockBox? {
        for d in listMarkerDraws() {
            guard let rect = d.checkboxRect else { continue }
            if rect.insetBy(dx: -4, dy: -4).contains(point),   // generous tap target
               let box = boxes.first(where: { $0.id == d.id }) as? BlockBox { return box }
        }
        return nil
    }

    /// Toggles a checklist item's checked state (undoable). The marker is presentation only, so this
    /// doesn't change token counts — just the membership + a redraw.
    func toggleChecklist(_ box: BlockBox) {
        guard var membership = box.listMembership, membership.marker == .checklist else { return }
        editing {
            membership.checked = !(membership.checked ?? false)
            box.listMembership = membership
        }
        needsDisplay = true
    }

    /// Sets (or clears, with `nil`) list membership on every box the current selection touches,
    /// re-styling each affected box. A touched paragraph carrying interior soft "\n"s is SPLIT into
    /// one list item per line (blank lines dropped), so listing a multi-line paragraph numbers each
    /// line instead of making one tall item. Undoable.
    func setList(_ marker: ListMarker?) {
        guard !boxes.isEmpty else { return }
        editing {
            var newBoxes: [CanvasBlock] = []
            var lastCreated: BlockBox? = nil
            for box in boxes {
                guard let p = box as? BlockBox else { newBoxes.append(box); continue }
                let boxLo = p.textStart, boxHi = p.textStart + p.textLength
                guard selectionTouchesRange(lo: boxLo, hi: boxHi) else { newBoxes.append(box); continue }
                if let marker = marker {
                    // A checklist item starts unchecked; switching to bullet/ordered drops the checked state.
                    // Preserve checked when re-applying .checklist to an already-checked item.
                    let checked: Bool? = marker == .checklist ? (p.listMembership?.checked ?? false) : nil
                    let membership = ListMembership(marker: marker, level: p.listMembership?.level ?? 0, checked: checked)
                    let paragraph = p.currentParagraph()
                    let lines = splitRunsOnNewlines(paragraph.runs).filter { runs in
                        runs.contains(where: { !$0.text.isEmpty })
                    }
                    if lines.count > 1 {
                        for runs in lines {
                            let item = ParagraphBlock(id: BlockID.generate(), style: paragraph.style,
                                                      paragraph: paragraph.paragraph, list: membership, runs: runs)
                            let itemBox = BlockBox(paragraph: item, mapper: p.mapper, width: effectiveWidth)
                            newBoxes.append(itemBox)
                            lastCreated = itemBox
                        }
                        continue
                    }
                    p.listMembership = membership
                } else {
                    p.listMembership = nil
                }
                restyle(p)
                newBoxes.append(p)
            }
            boxes = newBoxes
            recomputeSpans()
            if let last = lastCreated {
                anchor = last.textStart + last.textLength
                head = anchor
            }
        }
    }

    /// Toggles the checked state of the caret's checklist item (no-op if the caret isn't in one).
    func toggleChecklistAtCaret() {
        guard let box = activeListBox(), box.listMembership?.marker == .checklist else { return }
        toggleChecklist(box)
    }

    /// The caret's paragraph when it is a list item (root stack or a cell), else nil. Drives Return
    /// semantics: in a list, Enter adds a new item (and outdents / leaves the list on an empty item)
    /// while Shift+Enter is a soft line break within the item.
    func activeListBox() -> BlockBox? {
        guard let active = activeStack(at: head), let p = active.box as? BlockBox,
              p.listMembership != nil else { return nil }
        return p
    }

    /// Re-applies the paragraph style (reflecting the box's current style + list membership) across
    /// the box's text. No-op for an empty box (typing applies the style via `typingAttributeDict`).
    func restyle(_ box: BlockBox) {
        let ps = box.mapper.styleSheet.paragraphStyle(for: box.style, attributes: box.paragraphAttributes,
                                                      list: box.listMembership)
        let storage = box.layout.attributedString
        guard storage.length > 0 else { return }
        let m = NSMutableAttributedString(attributedString: storage)
        m.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: m.length))
        box.layout.attributedString = m
    }
}
#endif
