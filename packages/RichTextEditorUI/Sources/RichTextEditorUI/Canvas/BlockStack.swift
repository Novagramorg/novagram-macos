#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// A vertical run of `CanvasBlock`s — the shared engine for the document body and for each table
/// cell. Owns span math (relative to a `baseOffset`) and vertical layout (relative to an origin).
@available(macOS 12, *)
final class BlockStack {
    var boxes: [CanvasBlock]
    private(set) var baseOffset: Int = 0
    private(set) var contentHeight: CGFloat = 0

    init(boxes: [CanvasBlock] = []) { self.boxes = boxes }

    /// Assigns each box's `nodeStart` (= running tokens + 1, relative to `baseOffset`) and returns
    /// the stack's total token size.
    @discardableResult
    func recompute(baseOffset: Int) -> Int {
        self.baseOffset = baseOffset
        var pos = baseOffset
        for box in boxes {
            box.nodeStart = pos + 1
            pos += box.nodeSize
        }
        return pos - baseOffset
    }

    /// Extra inset a block reserves on the side facing a block that draws its own bounded background or
    /// border — a quote's fill, a code block's fill, a pull quote's pill, or a table's grid — so that
    /// framed block has visible separation from its neighbors. Lives on the neighbor (external to the
    /// framed block), since a framed block fills its own frame; its own inset is internal padding.
    private static let framedNeighborMargin: CGFloat = 8

    /// A block that draws its own bounded fill and is NOT a `BlockBox`, so `facingInset` never runs for
    /// it: a code block, a table, a pull quote, or a block-quote container. Its own top/bottom insets are
    /// INTERNAL padding (fill→text), not external margin — so two of these adjacent would sit flush.
    private static func isFramedAtom(_ box: CanvasBlock) -> Bool {
        box is CodeBlockBox || box is TableBlockBox || box is PullQuoteBox || box is BlockQuoteBox || box is ButtonRowBox
    }

    /// The base inter-block vertical inset (each side; two facing insets make a gap). Defaults to the
    /// document metric; a `BlockQuoteBox`'s child stack sets 0 so the container's own top/bottom padding
    /// is the sole outer padding (an empty one-child quote stays one line tall).
    var verticalInsetBase: CGFloat = BlockBox.defaultVerticalInset

    /// The inset for `box` on the side facing `neighbor` (or the stack edge, when nil). The facing
    /// insets of two adjacent blocks together make their gap: list items stack tight (0); two body
    /// paragraphs sit at half the default; a block facing a framed atom reserves extra margin;
    /// otherwise the default.
    private func facingInset(of box: BlockBox, toward neighbor: CanvasBlock?) -> CGFloat {
        let base = verticalInsetBase
        if let n = neighbor, BlockStack.isFramedAtom(n) { return base + BlockStack.framedNeighborMargin }
        guard let n = neighbor as? BlockBox else { return base }
        if box.listMembership != nil && n.listMembership != nil { return 0 }
        if box.isTextParagraph && n.isTextParagraph { return base / 2 }
        return base
    }

    /// Bare space laid down ABOVE `boxes[i]` that belongs to no box frame: two adjacent framed atoms
    /// both fill their whole frames, so neither's internal padding separates the fills — an external
    /// gap is inserted between them. One expression of the ownership rule, read by BOTH `layout` and
    /// `currentHeight` so measure and commit cannot disagree.
    private func bareGapAbove(_ i: Int) -> CGFloat {
        guard i > 0, BlockStack.isFramedAtom(boxes[i - 1]), BlockStack.isFramedAtom(boxes[i]) else { return 0 }
        // Two adjacent button rows stack tight: the V2 renderer separates them by their own padding
        // only (4+4), not the framed-atom margin — mirrored here so stacked rows read like the message.
        if boxes[i - 1] is ButtonRowBox, boxes[i] is ButtonRowBox { return verticalInsetBase }
        return verticalInsetBase + BlockStack.framedNeighborMargin
    }

    /// The live laid-out extent: box heights PLUS the bare inter-atom gaps `layout` lays down. A sum
    /// of box heights alone under-reports by one gap per framed-atom adjacency, stranding trailing
    /// content outside the host's scroll range.
    var currentHeight: CGFloat {
        var total: CGFloat = 0
        for i in boxes.indices {
            total += bareGapAbove(i)
            total += boxes[i].height
        }
        return total
    }

    /// Lays boxes out top-to-bottom from `origin` at the given content `width`; returns total height.
    @discardableResult
    func layout(origin: CGPoint, width: CGFloat) -> CGFloat {
        var y = origin.y
        for i in boxes.indices {
            let box = boxes[i]
            if let b = box as? BlockBox {
                let prev: CanvasBlock? = i > 0 ? boxes[i - 1] : nil
                let next: CanvasBlock? = i + 1 < boxes.count ? boxes[i + 1] : nil
                b.topInset = facingInset(of: b, toward: prev)
                b.bottomInset = facingInset(of: b, toward: next)
            }
            box.setWidth(width)
            y += bareGapAbove(i)
            box.frame = CGRect(x: origin.x, y: y, width: width, height: box.height)
            y += box.height
        }
        contentHeight = y - origin.y
        return contentHeight
    }

    func leafRegions() -> [LeafTextRegion] { boxes.flatMap { $0.leafRegions() } }
    func draw(in ctx: CGContext, imageProvider: (String) -> NSImage?) { for b in boxes { b.draw(in: ctx, imageProvider: imageProvider) } }

    func closestPosition(toCanvasPoint point: CGPoint) -> Int {
        guard !boxes.isEmpty else { return baseOffset }
        let box = boxes.first(where: { point.y < $0.frame.maxY }) ?? boxes[boxes.count - 1]
        return box.closestPosition(toCanvasPoint: point)
    }
}
#endif
