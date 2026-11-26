#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// A macOS-only media GROUP block — a collage of ≤10 photos/videos (a slider later) WITH one editable
/// caption. Structurally like `MediaBlockBox`, but the media area hosts N tile views laid out by a
/// host-provided mosaic closure (the chat's `GroupedLayout`) instead of a single view, and it bleeds
/// full-width to the canvas edge like a photo/video. Token model mirrors the others: `caption.length + 5`,
/// caption text begins at `nodeStart + 2`, and `nodeStart` (before the atom) is a gap.
@available(macOS 12, *)
final class MediaGroupBlockBox: CanvasBlock {
    let id: BlockID
    var kind: MediaGroupKind
    var mediaIDs: [String]
    /// Per-tile Telegram-style spoiler flags, parallel to `mediaIDs`.
    var spoilers: [Bool]
    let caption: BlockLayout
    let mapper: AttributedStringMapper

    var frame: CGRect = .zero
    var nodeStart: Int = 0
    private(set) var layoutWidth: CGFloat

    /// Host mosaic: maps the group's `mediaIDs` + the full-bleed width to per-tile frames (each frame's
    /// origin is relative to the media area's top-left). Set by the canvas. nil → a placeholder height.
    var mosaicProvider: (([String], CGFloat) -> [CGRect])?
    /// Last height a hosted SLIDER view reported (slideshow kind only); collage height comes from the mosaic.
    var hostHeight: CGFloat?

    static let verticalInset: CGFloat = 8
    static let captionGap: CGFloat = 4
    static let placeholderHeight: CGFloat = 200

    /// The canvas's horizontal content margin (set by the canvas); the group bleeds across both margins.
    var contentMargin: CGFloat = CanvasMetrics.pageMargin

    init(group block: MediaGroupBlock, mapper: AttributedStringMapper, width: CGFloat) {
        id = block.id
        kind = block.kind
        mediaIDs = block.mediaIDs
        spoilers = block.spoilers
        self.mapper = mapper
        layoutWidth = max(width, 1)
        let captionPara = ParagraphBlock(id: block.id, style: .caption,
                                         paragraph: ParagraphAttributes(alignment: .left), runs: block.caption)
        caption = BlockLayout(attributedString: mapper.attributedString(for: captionPara), width: max(width, 1))
    }

    /// Full-bleed width (past both page margins), like a photo/video.
    var canvasWidth: CGFloat { layoutWidth + contentMargin * 2 }

    /// Per-tile frames within the media area (mosaic origin = media-area top-left). Empty without a provider.
    func tileFrames() -> [CGRect] {
        guard let mosaic = mosaicProvider, !mediaIDs.isEmpty else { return [] }
        return mosaic(mediaIDs, max(canvasWidth, 1))
    }

    /// Collage: the mosaic's tallest tile bottom. Slider: the height the hosted slider reported. Either
    /// falls back to a placeholder until known.
    var mediaAreaHeight: CGFloat {
        switch kind {
        case .collage:
            let frames = tileFrames()
            guard !frames.isEmpty else { return MediaGroupBlockBox.placeholderHeight }
            return min(frames.map { $0.maxY }.max() ?? MediaGroupBlockBox.placeholderHeight, CanvasMetrics.maxMediaHeight)
        case .slideshow:
            return min(hostHeight ?? MediaGroupBlockBox.placeholderHeight, CanvasMetrics.maxMediaHeight)
        }
    }

    private static var measuredCaptionLineHeight: CGFloat?
    private func captionLineHeight() -> CGFloat {
        if let h = MediaGroupBlockBox.measuredCaptionLineHeight { return h }
        let probe = ParagraphBlock(id: BlockID.generate(), style: .caption, runs: [TextRun(text: "x")])
        let h = BlockLayout(attributedString: mapper.attributedString(for: probe), width: 100_000).boundingHeight
        MediaGroupBlockBox.measuredCaptionLineHeight = h
        return h
    }
    private var captionAreaHeight: CGFloat { max(caption.boundingHeight, captionLineHeight()) }

    // CanvasBlock — the editable text region is the caption (mirrors MediaBlockBox).
    var textLayout: BlockLayout { caption }
    var textLength: Int { caption.length }
    var nodeSize: Int { caption.length + 5 }
    var textStart: Int { nodeStart + 2 }
    var textRef: TextNodeRef { .caption(id) }

    var height: CGFloat {
        MediaGroupBlockBox.verticalInset + mediaAreaHeight + MediaGroupBlockBox.captionGap
            + captionAreaHeight + MediaGroupBlockBox.verticalInset
    }

    var textOrigin: CGPoint {
        CGPoint(x: frame.minX,
                y: frame.minY + MediaGroupBlockBox.verticalInset + mediaAreaHeight + MediaGroupBlockBox.captionGap)
    }

    /// Top-left of the media area (full-bleed: past the left content margin), where tiles are positioned.
    var mediaOrigin: CGPoint {
        CGPoint(x: frame.minX - contentMargin, y: frame.minY + MediaGroupBlockBox.verticalInset)
    }

    func setWidth(_ width: CGFloat) {
        layoutWidth = max(width, 1)
        caption.setWidth(max(width, 1))
    }

    func closestPosition(toCanvasPoint point: CGPoint) -> Int {
        if point.y < textOrigin.y { return nodeStart }   // media area → gap before the atom
        let local = CGPoint(x: point.x - textOrigin.x, y: point.y - textOrigin.y)
        return textStart + caption.closestOffset(toPoint: local)
    }

    /// Placeholder — NEVER used for the public document (group blocks are dropped, like media).
    func currentBlock() -> Block { .paragraph(ParagraphBlock(id: id, runs: [])) }

    func currentModelBlock() -> CanvasModelBlock {
        .mediaGroup(MediaGroupBlock(id: id, kind: kind, mediaIDs: mediaIDs,
                                    caption: mapper.runs(from: caption.attributedString), spoilers: spoilers))
    }

    func leafRegions() -> [LeafTextRegion] {
        [LeafTextRegion(layout: caption, globalStart: textStart, length: caption.length,
                        ref: .caption(id), canvasOrigin: textOrigin)]
    }

    func draw(in ctx: CGContext, imageProvider: (String) -> NSImage?) {
        // The tiles are hosted views (positioned by syncMediaGroupViews); the box draws only the caption.
        caption.drawText(in: ctx, at: textOrigin)
    }
}
#endif
