#if canImport(AppKit)
import AppKit
import RichTextEditorCore

@available(macOS 12, *)
extension DocumentCanvasView {
    // MARK: - Per-box collapse toggle (BlockQuoteBox)

    /// Flips the `collapsed` flag on `box` (rebuild the box, relocate the caret, recompute).
    func toggleCollapsed(box: BlockQuoteBox) {
        guard let (parentStack, index) = parentStackAndIndex(of: box),
              case .blockQuote(var bq) = box.currentBlock() else { return }
        let wasCollapsed = bq.collapsed
        bq.collapsed.toggle()
        let oldStart = box.nodeStart, oldSize = box.nodeSize
        let beforeAnchor = anchor, beforeHead = head
        let caretTouched = (beforeHead >= oldStart && beforeHead < oldStart + oldSize)
            || (beforeAnchor >= oldStart && beforeAnchor < oldStart + oldSize)
        editing {
            let newBox = BlockQuoteBox(blockQuote: bq, mapper: mapper, width: effectiveWidth)
            parentStack.boxes.replaceSubrange(index...index, with: [newBox])
            recomputeSpans()
            if caretTouched {
                if wasCollapsed {   // EXPANDING: caret into the first child leaf
                    let caret = newBox.children.boxes.first?.leafRegions().first?.globalStart
                        ?? (newBox.nodeStart + 1)
                    anchor = caret; head = caret
                } else {            // COLLAPSING: relocate the caret AFTER the folded atom into a real text
                    // block — a keystroke on a display-only gap would be swallowed by the preview layout.
                    let afterIndex = index + 1
                    if afterIndex < parentStack.boxes.count, let next = parentStack.boxes[afterIndex] as? BlockBox {
                        anchor = next.textStart; head = next.textStart
                    } else {
                        let trailing = BlockBox(paragraph: ParagraphBlock(id: .generate(), style: .body),
                                                mapper: mapper, width: effectiveWidth)
                        parentStack.boxes.insert(trailing, at: afterIndex)
                        recomputeSpans()
                        anchor = trailing.textStart; head = trailing.textStart
                    }
                }
            } else {                // caret outside — preserve, shifted by the size delta
                let delta = newBox.nodeSize - oldSize
                func remap(_ p: Int) -> Int { p < oldStart ? p : p + delta }
                anchor = remap(beforeAnchor); head = remap(beforeHead)
            }
        }
    }

    /// The owning `BlockStack` + index for `box` — a recursive descent matching by identity (`===`).
    func parentStackAndIndex(of box: CanvasBlock) -> (BlockStack, Int)? {
        func descend(_ stack: BlockStack) -> (BlockStack, Int)? {
            for (i, b) in stack.boxes.enumerated() {
                if b === box { return (stack, i) }
                if let bq = b as? BlockQuoteBox, let found = descend(bq.children) { return found }
                if let t = b as? TableBlockBox {
                    for row in t.cells { for cell in row { if let found = descend(cell) { return found } } }
                }
            }
            return nil
        }
        return descend(root)
    }

    /// Walks the full box tree and returns the first `BlockQuoteBox` whose ACTIVE glyph rect (expanded →
    /// collapse glyph, collapsed → expand glyph) contains `point` (with a small touch inset). Deepest
    /// match wins so a nested quote's glyph beats its ancestor's.
    func firstBlockQuoteGlyphHit(at point: CGPoint) -> BlockQuoteBox? {
        func check(_ bq: BlockQuoteBox) -> BlockQuoteBox? {
            if !bq.collapsed {
                for child in bq.children.boxes {
                    if let found = searchStack(child) { return found }
                }
            }
            let activeRect: CGRect? = bq.collapsed
                ? bq.expandGlyphRect()
                : (bq.isCollapsible ? bq.collapseGlyphRect() : nil)
            if let r = activeRect, r.insetBy(dx: -6, dy: -6).contains(point) { return bq }
            return nil
        }
        func searchStack(_ b: CanvasBlock) -> BlockQuoteBox? {
            if let bq = b as? BlockQuoteBox { return check(bq) }
            if let t = b as? TableBlockBox {
                for row in t.cells { for cell in row { for cellBox in cell.boxes { if let found = searchStack(cellBox) { return found } } } }
            }
            return nil
        }
        for b in boxes {
            if let found = searchStack(b) { return found }
        }
        return nil
    }
}
#endif
