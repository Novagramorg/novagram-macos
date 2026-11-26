#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Indent / outdent. A LIST ITEM changes its nesting `ListMembership.level` (GFM-faithful list nesting);
/// a regular paragraph/heading/quote shifts its left (head) indent by `paragraphIndentStep`. Mirrors
/// `setList`: mutate every box the selection touches, restyle, recompute. Works on a collapsed caret (a
/// paragraph-level command). Outdent clamps at level 0 / indent 0 (it does NOT drop the list — that's the
/// list toggle's job); list indent clamps at `maxListLevel`.
@available(macOS 12, *)
extension DocumentCanvasView {
    private var maxListLevel: Int { 8 }
    /// Points a non-list paragraph's left edge moves per indent step.
    private var paragraphIndentStep: Double { 24 }

    func indent() { changeIndent(by: 1) }
    func outdent() { changeIndent(by: -1) }

    private func changeIndent(by delta: Int) {
        guard !boxes.isEmpty else { return }
        // Collect every paragraph the selection touches, RECURSING into block-quote children and table
        // cells — an indent inside a container must act on the nested paragraph, not silently no-op.
        func touched(in stack: BlockStack) -> [BlockBox] {
            var result: [BlockBox] = []
            for box in stack.boxes {
                if let bq = box as? BlockQuoteBox, !bq.collapsed {
                    result += touched(in: bq.children)
                } else if let t = box as? TableBlockBox {
                    for row in t.cells { for cell in row { result += touched(in: cell) } }
                } else if let p = box as? BlockBox {
                    let boxLo = p.textStart, boxHi = p.textStart + p.textLength
                    if selectionTouchesRange(lo: boxLo, hi: boxHi) { result.append(p) }
                }
            }
            return result
        }
        let targets = touched(in: root)
        guard !targets.isEmpty else { return }
        editing {
            for p in targets {
                if let m = p.listMembership {
                    let newLevel = max(0, min(m.level + delta, maxListLevel))
                    p.listMembership = ListMembership(marker: m.marker, level: newLevel)
                } else {
                    var pa = p.paragraphAttributes
                    let newIndent = max(0, pa.headIndent + Double(delta) * paragraphIndentStep)
                    pa.headIndent = newIndent
                    pa.firstLineIndent = newIndent
                    p.paragraphAttributes = pa
                }
                restyle(p)
            }
            recomputeSpans()   // symmetry with setList; a level bump leaves token spans unchanged
        }
    }
}
#endif
