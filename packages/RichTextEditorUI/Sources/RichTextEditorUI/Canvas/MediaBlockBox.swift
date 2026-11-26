#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// A macOS-only embedded-media block (file / audio / map) WITH an editable caption — structurally a clone
/// of `ImageBlockBox`, except the "media area" is an app-injected interactive `NSView` (resolved from
/// `mediaID` via the host's media-block view provider) rather than a drawn image. Layout: vertical inset,
/// the media area (the hosted view, height = `hostHeight`), a caption gap, the editable caption text, a
/// vertical inset. Token model mirrors the image: `caption.length + 5`, caption text begins at
/// `nodeStart + 2`; `nodeStart` (before the atom) is a gap.
@available(macOS 12, *)
final class MediaBlockBox: CanvasBlock {
    let id: BlockID
    var kind: MediaKind
    var mediaID: String
    /// Telegram-style spoiler: the medium renders behind the animated dust overlay until revealed.
    var spoiler: Bool
    var displayWidth: CGFloat?
    /// Last height the host's media view reported (set by the canvas's media-view sync). The media area
    /// reserves this; until the host view exists it falls back to a placeholder.
    var hostHeight: CGFloat?
    let caption: BlockLayout
    let mapper: AttributedStringMapper

    var frame: CGRect = .zero
    var nodeStart: Int = 0
    private(set) var layoutWidth: CGFloat

    /// The canvas's horizontal content margin (set by the canvas); a bleeding media block uses it to reach
    /// the canvas edge.
    var contentMargin: CGFloat = CanvasMetrics.pageMargin

    static let verticalInset: CGFloat = 8
    static let captionGap: CGFloat = 4
    static let placeholderHeight: CGFloat = 60

    init(media block: MediaBlock, mapper: AttributedStringMapper, width: CGFloat) {
        id = block.id
        kind = block.kind
        mediaID = block.mediaID
        spoiler = block.spoiler
        displayWidth = block.displayWidth
        hostHeight = block.height
        self.mapper = mapper
        layoutWidth = max(width, 1)
        // The caption's paragraph id matches the block id — it only keys the paragraph style here;
        // `currentModelBlock()` extracts the caption runs, not this temporary paragraph's id.
        let captionPara = ParagraphBlock(id: block.id, style: .caption,
                                         paragraph: ParagraphAttributes(alignment: .left),
                                         runs: block.caption)
        caption = BlockLayout(attributedString: mapper.attributedString(for: captionPara),
                              width: max(width, 1))
    }

    /// Height reserved for the media area (the hosted view), before its real size is known. Capped at
    /// `CanvasMetrics.maxMediaHeight` so a tall video/file never dominates the document.
    var mediaAreaHeight: CGFloat { min(hostHeight ?? MediaBlockBox.placeholderHeight, CanvasMetrics.maxMediaHeight) }

    /// An empty caption still reserves one line so the "Add caption…" placeholder doesn't overflow into
    /// the next block (TextKit 2 lays out no fragment for empty text, so `boundingHeight` is ~0). Measured
    /// once through the same pipeline a typed body line uses (matches `BlockBox.emptyLineHeight`).
    private static var measuredCaptionLineHeight: CGFloat?
    private func captionLineHeight() -> CGFloat {
        if let h = MediaBlockBox.measuredCaptionLineHeight { return h }
        let probe = ParagraphBlock(id: BlockID.generate(), style: .caption, runs: [TextRun(text: "x")])
        let h = BlockLayout(attributedString: mapper.attributedString(for: probe), width: 100_000).boundingHeight
        MediaBlockBox.measuredCaptionLineHeight = h
        return h
    }
    private var captionAreaHeight: CGFloat { max(caption.boundingHeight, captionLineHeight()) }

    // CanvasBlock — the editable text region is the caption (mirrors ImageBlockBox).
    var textLayout: BlockLayout { caption }
    var textLength: Int { caption.length }
    var nodeSize: Int { caption.length + 5 }
    var textStart: Int { nodeStart + 2 }
    var textRef: TextNodeRef { .caption(id) }

    var height: CGFloat {
        MediaBlockBox.verticalInset + mediaAreaHeight + MediaBlockBox.captionGap
            + captionAreaHeight + MediaBlockBox.verticalInset
    }

    var textOrigin: CGPoint {
        CGPoint(x: frame.minX,
                y: frame.minY + MediaBlockBox.verticalInset + mediaAreaHeight + MediaBlockBox.captionGap)
    }

    /// Top-left of the media area (where the hosted view is placed by `syncMediaBlockViews`).
    var mediaOrigin: CGPoint { CGPoint(x: frame.minX, y: frame.minY + MediaBlockBox.verticalInset) }

    /// Image and video bleed past the page margins to the canvas edge (full-bleed); file / audio / map stay
    /// within the content strip.
    var mediaBleeds: Bool { kind == .video || kind == .image }

    func setWidth(_ width: CGFloat) {
        layoutWidth = max(width, 1)
        caption.setWidth(max(width, 1))
    }

    func closestPosition(toCanvasPoint point: CGPoint) -> Int {
        if point.y < textOrigin.y { return nodeStart }   // media area → gap before the atom
        let local = CGPoint(x: point.x - textOrigin.x, y: point.y - textOrigin.y)
        return textStart + caption.closestOffset(toPoint: local)
    }

    /// Placeholder — NEVER used for media: the public `[Block]` document drops media blocks, and undo
    /// round-trips through `currentModelBlock()`.
    func currentBlock() -> Block { .paragraph(ParagraphBlock(id: id, runs: [])) }

    func currentModelBlock() -> CanvasModelBlock {
        .media(MediaBlock(id: id, kind: kind, mediaID: mediaID, displayWidth: displayWidth,
                          height: hostHeight, caption: mapper.runs(from: caption.attributedString), spoiler: spoiler))
    }

    func leafRegions() -> [LeafTextRegion] {
        [LeafTextRegion(layout: caption, globalStart: textStart, length: caption.length,
                        ref: .caption(id), canvasOrigin: textOrigin)]
    }

    func draw(in ctx: CGContext, imageProvider: (String) -> NSImage?) {
        // The media area is the hosted view (drawn by AppKit); the box draws only the caption text.
        caption.drawText(in: ctx, at: textOrigin)
    }
}
#endif
