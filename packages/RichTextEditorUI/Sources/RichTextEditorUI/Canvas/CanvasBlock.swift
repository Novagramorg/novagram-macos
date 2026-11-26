#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// A block rendered by `DocumentCanvasView`. Conformers: `BlockBox` (paragraph), `ImageBlockBox`
/// (image + caption), and `TableBlockBox` (a grid of cells). The canvas treats every block uniformly:
/// span math via `nodeStart`/`nodeSize`, and selection/caret/text/draw via `leafRegions()` (each
/// block's editable text regions, recursing into table cells) + `draw(in:imageProvider:)`. The
/// single-text-region members are a convenience for leaf blocks; a table supplies degenerate values.
@available(macOS 12, *)
protocol CanvasBlock: AnyObject {
    var id: BlockID { get }
    /// The mapper this box was built with. Split/merge replacement boxes inherit their source box's
    /// mapper so a container-scoped variant (e.g. a block quote's tight-spacing children) survives edits.
    var mapper: AttributedStringMapper { get }
    /// Token contribution to the position model. Paragraph: `textLength + 2`. Image: `textLength + 5`.
    var nodeSize: Int { get }
    /// Global position of the block's first inner position (before the image atom, for an image).
    /// Assigned by `recomputeSpans`.
    var nodeStart: Int { get set }
    /// The block's single editable text region.
    var textLayout: BlockLayout { get }
    /// Global position where the editable text begins (`== nodeStart` for a paragraph; `nodeStart + 2` for an image).
    var textStart: Int { get }
    /// UTF-16 length of the editable text (`== textLayout.length`).
    var textLength: Int { get }
    /// Model ref for the editable text region.
    var textRef: TextNodeRef { get }
    /// Canvas-coordinate origin of the editable text region.
    var textOrigin: CGPoint { get }
    var frame: CGRect { get set }
    var height: CGFloat { get }
    func setWidth(_ width: CGFloat)
    /// Round-trips this block back to the Core model.
    func currentBlock() -> Block
    /// Round-trips this block to the canvas's internal currency (undo + `setModelBlocks`). Defaults to
    /// `.core(currentBlock())`; `MediaBlockBox` overrides to `.media(...)` so macOS-only media survives.
    func currentModelBlock() -> CanvasModelBlock
    /// Maps a point in canvas coordinates to the closest global position this block can host
    /// (paragraph → a text offset; image → a gap or a caption offset).
    func closestPosition(toCanvasPoint point: CGPoint) -> Int
    /// Editable text regions inside this block, with absolute global ranges + canvas origins.
    /// Valid after layout (frame assigned). Leaf blocks return one; a table flat-maps over its cells.
    func leafRegions() -> [LeafTextRegion]
    /// Draws this block (decoration/grid + text) in canvas coordinates.
    func draw(in ctx: CGContext, imageProvider: (String) -> NSImage?)
}

@available(macOS 12, *)
extension CanvasBlock {
    /// Core blocks (paragraph/image/table) round-trip 1:1 to a shared `Block`.
    func currentModelBlock() -> CanvasModelBlock { .core(currentBlock()) }
}
#endif
