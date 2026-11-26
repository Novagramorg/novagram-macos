#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// An image-with-caption block: a rendered image (resolved from `assetID` via the canvas's image
/// provider) above an editable caption. Backed by a `MediaBlock` of kind `.image` — the same local
/// model the file/audio/map blocks use — but rendered as a drawn full-bleed bitmap rather than a hosted
/// view. Contributes `captionLength + 5` tokens; the caption text begins at `nodeStart + 2` (after the
/// image atom and the caption paragraph's open token). The position `nodeStart` (before the atom) is a gap.
@available(macOS 12, *)
final class ImageBlockBox: CanvasBlock {
    let id: BlockID
    var assetID: String
    var naturalSize: Size2D
    var displayWidth: CGFloat?
    var alignment: ImageAlignment
    /// Telegram-style spoiler: the image renders behind the animated dust overlay until revealed.
    var spoiler: Bool
    let caption: BlockLayout
    let mapper: AttributedStringMapper

    var frame: CGRect = .zero
    var nodeStart: Int = 0
    let verticalInset: CGFloat = 8
    let captionGap: CGFloat = 4
    /// The most-recently-set layout width (from `setWidth` or `init`). Used by `height`,
    /// `imageAreaHeight`, and `imageRect` so they are correct before `frame` is assigned by
    /// `layoutSubviews`.
    private(set) var layoutWidth: CGFloat

    /// The canvas's horizontal content margin (set by the canvas). The image bleeds across both margins to
    /// the canvas edge; defaults to the standard page margin.
    var contentMargin: CGFloat = CanvasMetrics.pageMargin

    /// The full canvas width this image bleeds across: its content-strip frame width plus both content
    /// margins (the inverse of the inset top-level frame). The image draws edge-to-edge over this.
    private var canvasWidth: CGFloat { layoutWidth + contentMargin * 2 }

    init(media block: MediaBlock, mapper: AttributedStringMapper, width: CGFloat) {
        id = block.id
        assetID = block.mediaID
        naturalSize = block.naturalSize
        displayWidth = block.displayWidth
        alignment = block.alignment
        spoiler = block.spoiler
        self.mapper = mapper
        layoutWidth = max(width, 1)
        // The caption's paragraph id matches the media block's id — it only keys the paragraph style
        // here; `currentModelBlock()` extracts the caption runs, not this temporary paragraph's id.
        let captionPara = ParagraphBlock(id: block.id, style: .caption,
                                         paragraph: ParagraphAttributes(alignment: .left),
                                         runs: block.caption)
        caption = BlockLayout(attributedString: mapper.attributedString(for: captionPara),
                              width: max(width, 1))
    }

    // CanvasBlock — text region is the caption.
    var textLayout: BlockLayout { caption }
    var textLength: Int { caption.length }
    var nodeSize: Int { caption.length + 5 }
    var textStart: Int { nodeStart + 2 }
    var textRef: TextNodeRef { .caption(id) }

    func setWidth(_ width: CGFloat) {
        layoutWidth = max(width, 1)
        caption.setWidth(max(width, 1))
    }

    /// Displayed image size: `displayWidth` clamped to `maxWidth` (or fills `maxWidth` when no
    /// explicit `displayWidth`), aspect preserved from `naturalSize`.
    func imageDisplaySize(maxWidth: CGFloat) -> CGSize {
        let naturalW = CGFloat(naturalSize.width), naturalH = CGFloat(naturalSize.height)
        let targetW = displayWidth.map { min($0, maxWidth) } ?? maxWidth
        guard naturalW > 0, naturalH > 0 else { return CGSize(width: targetW, height: targetW * 0.5625) }
        return CGSize(width: targetW, height: naturalH * (targetW / naturalW))
    }

    var imageAreaHeight: CGFloat {
        min(imageDisplaySize(maxWidth: max(canvasWidth, 1)).height, CanvasMetrics.maxMediaHeight)
    }

    /// An empty caption still reserves one line so the "Add caption…" placeholder doesn't overflow into
    /// the next block (TextKit 2 lays out no fragment for empty text, so `boundingHeight` is ~0). Mirrors
    /// `MediaBlockBox.captionAreaHeight`.
    private static var measuredCaptionLineHeight: CGFloat?
    private func captionLineHeight() -> CGFloat {
        if let h = ImageBlockBox.measuredCaptionLineHeight { return h }
        let probe = ParagraphBlock(id: BlockID.generate(), style: .caption, runs: [TextRun(text: "x")])
        let h = BlockLayout(attributedString: mapper.attributedString(for: probe), width: 100_000).boundingHeight
        ImageBlockBox.measuredCaptionLineHeight = h
        return h
    }
    private var captionAreaHeight: CGFloat { max(caption.boundingHeight, captionLineHeight()) }

    var height: CGFloat { verticalInset + imageAreaHeight + captionGap + captionAreaHeight + verticalInset }

    var textOrigin: CGPoint {
        CGPoint(x: frame.minX,
                y: frame.minY + verticalInset + imageAreaHeight + captionGap)
    }

    // NOTE: assumes a top-level image (bleeds past the page margin to the canvas edge). No command inserts an image into a table cell today; if that becomes possible, a nested image must skip the bleed.
    func imageRect() -> CGRect {
        let avail = max(canvasWidth, 1)
        let size = imageDisplaySize(maxWidth: avail)
        let bleedX = frame.minX - contentMargin
        let x: CGFloat
        switch alignment {
        case .left: x = bleedX
        case .center: x = bleedX + (avail - size.width) / 2
        case .right: x = bleedX + (avail - size.width)
        }
        return CGRect(x: x, y: frame.minY + verticalInset, width: size.width, height: size.height)
    }

    func closestPosition(toCanvasPoint point: CGPoint) -> Int {
        if point.y < textOrigin.y { return nodeStart }   // image area → gap before the atom
        let local = CGPoint(x: point.x - textOrigin.x, y: point.y - textOrigin.y)
        return textStart + caption.closestOffset(toPoint: local)
    }

    /// Placeholder — NEVER used for the public document: `[Block]` drops media blocks (image included),
    /// and undo round-trips through `currentModelBlock()`.
    func currentBlock() -> Block { .paragraph(ParagraphBlock(id: id, runs: [])) }

    func currentModelBlock() -> CanvasModelBlock {
        .media(MediaBlock(id: id, kind: .image, mediaID: assetID, displayWidth: displayWidth,
                          naturalSize: naturalSize, alignment: alignment,
                          caption: mapper.runs(from: caption.attributedString), spoiler: spoiler))
    }

    func leafRegions() -> [LeafTextRegion] {
        [LeafTextRegion(layout: caption, globalStart: textStart, length: caption.length,
                        ref: .caption(id), canvasOrigin: textOrigin)]
    }

    func draw(in ctx: CGContext, imageProvider: (String) -> NSImage?) {
        let rect = imageRect()
        if let image = imageProvider(assetID) {
            // Use respectFlipped:true so NSImage renders right-side-up in a flipped (y-down) view.
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        } else {
            NSColor.controlColor.setFill(); ctx.fill(rect)
        }
        caption.drawText(in: ctx, at: textOrigin)
    }
}
#endif
