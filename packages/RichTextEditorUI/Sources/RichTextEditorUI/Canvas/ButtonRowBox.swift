#if canImport(AppKit)
import AppKit
import CoreText
import RichTextEditorCore

/// Host seam for the trailing action badge a BLOCK pill draws at its top-right corner (the ↗ on a URL
/// button), so the editor pill matches the sent message. The app assigns the provider once at startup
/// (the `RichTextEditorLocalization` pattern); the returned image is used as an alpha MASK and tinted
/// with the pill's label colour at draw time. nil (the default) draws no badge — the packing's width
/// reserve still applies either way, so labels ellipsise identically.
public enum RichTextEditorButtonBadges {
    public static var provider: ((ButtonRef) -> NSImage?)?
}

/// One `pageBlockButtonRow` in the canvas: a row of pills, packed by `richTextPackButtonRow`.
///
/// **This is the editor's only TEXT-FREE block.** Every other `CanvasBlock` owns at least one editable
/// text region; a button row owns none — a pill's label is button chrome, not document text. So
/// `leafRegions()` is empty and the single-text-region protocol members are degenerate, exactly as
/// `TableBlockBox`/`BlockQuoteBox` supply degenerate values for members that do not apply to them.
///
/// The position model gives the row one atom per pill (the `.mediaBlock` + `.mediaAtom` shape a
/// collapsed block quote already uses), so `nodeSize == max(1, buttons.count) + 2` and the caret can
/// stop on each pill. Unlike iOS — where pills are hosted views so label emoji stay live — this box
/// DRAWS its pills in `draw(in:)` (the macOS canvas is CG-drawn); a custom emoji inside a row-pill
/// label degrades to its reserved blank box (v1).
@available(macOS 12, *)
final class ButtonRowBox {
    let id: BlockID
    let mapper: AttributedStringMapper
    private(set) var buttons: [ButtonRef]
    private(set) var alignment: ButtonRowAlignment

    var frame: CGRect = .zero
    var globalStart: Int = 0

    /// Pill frames in the box's own coordinate space (origin at the row's top-left), model order.
    private(set) var pillFrames: [CGRect] = []
    /// Box-local rect of the trailing "…" menu affordance — EDITOR-ONLY chrome, placed after packing
    /// and deliberately NOT part of `richTextPackButtonRow` (that transcription stays V2-exact; a sent
    /// message has no such control).
    private(set) var menuButtonFrame: CGRect = .zero
    private(set) var attachments: [ButtonTextAttachment] = []
    private var packedHeight: CGFloat = 0.0
    private var layoutWidth: CGFloat = 0.0

    /// A degenerate layout for the protocol's single-text-region members. Nothing reads it, because
    /// `leafRegions()` is empty — same trick as `TableBlockBox`/`BlockQuoteBox`.
    private let emptyLayout = BlockLayout(attributedString: NSAttributedString(string: ""), width: 1)

    /// Side of the trailing "…" control and the gap before it. Chrome, not content — smaller than a pill.
    static let menuButtonSide: CGFloat = 28.0
    static let menuButtonGap: CGFloat = 6.0
    /// Width the row reserves so the "…" always has room.
    static var menuButtonReserve: CGFloat { menuButtonSide + menuButtonGap }

    /// Whether this row shows its "…" menu control. Stamped by the canvas from whether a host wired
    /// the button editor (`buttonEditRequested != nil`), so the modal editor shows it and the inline
    /// chat composer — preservation-only — does not. When hidden the row ALSO stops reserving width
    /// for it, so composer pills match the sent message exactly.
    var showsMenuAffordance: Bool = false {
        didSet {
            if showsMenuAffordance != oldValue { repack(width: layoutWidth) }
        }
    }

    init(row: ButtonRowBlock, mapper: AttributedStringMapper, width: CGFloat) {
        self.id = row.id
        self.mapper = mapper
        self.buttons = row.buttons
        self.alignment = row.alignment
        repack(width: width)
    }

    private func repack(width: CGFloat) {
        layoutWidth = width
        let metrics = RichTextButtonMetrics.default
        // Pills pack into the width MINUS the "…" reserve, so the control always fits on the last
        // line — reserving beats wrapping (the default `justify` stretches pills to fill the width, so
        // an unreserved control never fits and EVERY row would gain a line).
        let packed = richTextPackButtonRow(
            buttons: buttons,
            alignment: alignment,
            availableWidth: max(0.0, width - (showsMenuAffordance ? ButtonRowBox.menuButtonReserve : 0.0)),
            metrics: metrics,
            isRTL: false,
            measure: { [mapper] button, maxWidth, padding in
                mapper.buttonAttachment(button: button, isBlockPill: true, maxWidth: maxWidth,
                                        horizontalPadding: padding)
            }
        )
        attachments = packed.attachments
        pillFrames = packed.frames
        // Floored at one pill row so an EMPTY row stays visible and selectable.
        packedHeight = max(packed.totalHeight, metrics.blockRowHeight)
        layoutMenuButton(availableWidth: max(0.0, width), rowHeight: metrics.blockRowHeight)
    }

    /// Places the trailing "…" centred on the last visual pill row, at the row's trailing edge. An
    /// EMPTY row shows it against the origin band.
    private func layoutMenuButton(availableWidth: CGFloat, rowHeight: CGFloat) {
        guard showsMenuAffordance else {
            menuButtonFrame = .zero   // `.zero.contains` is false, so hit-testing declines it too
            return
        }
        let side = ButtonRowBox.menuButtonSide
        let lastLineY = pillFrames.last?.minY ?? 0.0
        menuButtonFrame = CGRect(
            x: max(0.0, availableWidth - side),
            y: lastLineY + (rowHeight - side) / 2.0,
            width: side, height: side
        )
    }

    /// True when `point` (canvas space) lands on the "…".
    func hitsMenuButton(atCanvasPoint point: CGPoint) -> Bool {
        guard menuButtonFrame != .zero else { return false }
        return menuButtonFrame.offsetBy(dx: frame.minX, dy: frame.minY).contains(point)
    }

    /// The "…" rect in canvas space, for menu anchoring.
    func menuButtonCanvasRect() -> CGRect {
        menuButtonFrame.offsetBy(dx: frame.minX, dy: frame.minY)
    }

    /// Appends a pill and returns its index.
    @discardableResult
    func appendButton(_ button: ButtonRef) -> Int {
        buttons.append(button)
        repack(width: layoutWidth)
        return buttons.count - 1
    }

    /// The pill index at a canvas point, or nil.
    func pillIndex(atCanvasPoint point: CGPoint) -> Int? {
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        return pillFrames.firstIndex { $0.contains(local) }
    }

    /// The pill index nearest a canvas point — never nil for a non-empty row, so a click anywhere in
    /// the row's band lands on a pill rather than falling through to a neighbouring block.
    func nearestPillIndex(toCanvasPoint point: CGPoint) -> Int? {
        guard !pillFrames.isEmpty else {
            return nil
        }
        if let hit = pillIndex(atCanvasPoint: point) {
            return hit
        }
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, rect) in pillFrames.enumerated() {
            let dx = max(rect.minX - local.x, 0.0, local.x - rect.maxX)
            let dy = max(rect.minY - local.y, 0.0, local.y - rect.maxY)
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    /// The canvas-space rect of a pill, for caret placement and menu anchoring.
    func pillCanvasRect(_ index: Int) -> CGRect? {
        guard pillFrames.indices.contains(index) else {
            return nil
        }
        return pillFrames[index].offsetBy(dx: frame.minX, dy: frame.minY)
    }

    func currentRow() -> ButtonRowBlock {
        ButtonRowBlock(id: id, buttons: buttons, alignment: alignment)
    }

    /// Replaces one pill (nil removes it). Returns false when the index is out of range.
    @discardableResult
    func replaceButton(at index: Int, with button: ButtonRef?) -> Bool {
        guard buttons.indices.contains(index) else {
            return false
        }
        if let button {
            buttons[index] = button
        } else {
            buttons.remove(at: index)
        }
        repack(width: layoutWidth)
        return true
    }

    func setAlignment(_ alignment: ButtonRowAlignment) {
        self.alignment = alignment
        repack(width: layoutWidth)
    }
}

@available(macOS 12, *)
extension ButtonRowBox: CanvasBlock {
    var nodeStart: Int { get { globalStart } set { globalStart = newValue } }

    /// One atom per pill plus the two container tokens. MUST equal what Core `DocumentTree` produces
    /// for the same row, including the `max(1, …)` floor that keeps an EMPTY row selectable.
    var nodeSize: Int { max(1, buttons.count) + 2 }

    // The single-text-region members are degenerate: this block owns no editable text.
    var textLayout: BlockLayout { emptyLayout }
    var textStart: Int { globalStart }
    var textLength: Int { 0 }
    var textRef: TextNodeRef { .paragraph(id) }
    var textOrigin: CGPoint { frame.origin }

    var height: CGFloat { packedHeight }

    func setWidth(_ width: CGFloat) { repack(width: width) }

    func currentBlock() -> Block { .buttonRow(currentRow()) }

    /// Snaps to the atom position of the nearest pill. An empty row has one atom and no pill, so it
    /// resolves to that single interior slot.
    func closestPosition(toCanvasPoint point: CGPoint) -> Int {
        guard let index = nearestPillIndex(toCanvasPoint: point) else {
            return globalStart + 1
        }
        return globalStart + 1 + index
    }

    /// EMPTY by design — the row owns no editable text. This is what keeps the caret off a pill's
    /// label and routes every interaction through the atom positions instead.
    func leafRegions() -> [LeafTextRegion] { [] }

    /// Draws every pill directly: capsule fill, then the label recolored to the pill's label color and
    /// clipped to the capsule (the clip is what keeps an overflowing label inside the pill shape).
    func draw(in ctx: CGContext, imageProvider: (String) -> NSImage?) {
        for (index, attachment) in attachments.enumerated() {
            guard pillFrames.indices.contains(index) else { continue }
            let pill = pillFrames[index].offsetBy(dx: frame.minX, dy: frame.minY)
            guard pill.width > 0, pill.height > 0 else { continue }
            let radius = pill.height / 2.0
            let capsule = CGPath(roundedRect: pill, cornerWidth: radius, cornerHeight: radius, transform: nil)
            ctx.saveGState()
            ctx.addPath(capsule)
            ctx.setFillColor(attachment.colors.fill.cgColor)
            ctx.fillPath()
            if attachment.labelString.length != 0 {
                ctx.addPath(capsule)
                ctx.clip()
                let display = NSMutableAttributedString(attributedString: attachment.labelString)
                display.addAttribute(.foregroundColor, value: attachment.colors.label,
                                     range: NSRange(location: 0, length: display.length))
                let inkWidth = attachment.size.width - attachment.horizontalPadding * 2.0
                let x = pill.minX + max(attachment.horizontalPadding, (pill.width - inkWidth) / 2.0)
                let y = pill.minY + max(0, (pill.height - display.size().height) / 2.0)
                display.draw(at: CGPoint(x: x, y: y))
            }
            ctx.restoreGState()
            if let badge = RichTextEditorButtonBadges.provider?(buttons[index]) {
                drawBadge(badge, forPill: pill, labelColor: attachment.colors.label, in: ctx)
            }
        }
        drawMenuAffordance(in: ctx)
    }

    /// The corner action badge (the sent message's ↗ on a URL pill), at the renderer's exact insets
    /// (`max(5, h·0.3)` / `max(4, h·0.2)` — the same formula the packing's width reserve uses). Block
    /// pills only, like the renderer: an inline pill hugs its label and has no room for corner chrome.
    private func drawBadge(_ image: NSImage, forPill pill: CGRect, labelColor: NSColor, in ctx: CGContext) {
        guard let mask = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let iconSize = image.size
        guard iconSize.width > 0, iconSize.height > 0 else { return }
        let hInset = max(5.0, (pill.height * 0.3).rounded())
        let vInset = max(4.0, (pill.height * 0.2).rounded())
        let rect = CGRect(x: pill.maxX - iconSize.width - hInset, y: pill.minY + vInset,
                          width: iconSize.width, height: iconSize.height)
        ctx.saveGState()
        // Tint: clip to the icon's alpha and fill with the label colour — the provider's image carries
        // a baked colour that belongs to a different background.
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1.0, y: -1.0)
        ctx.clip(to: CGRect(origin: .zero, size: iconSize), mask: mask)
        ctx.setFillColor(labelColor.cgColor)
        ctx.fill(CGRect(origin: .zero, size: iconSize))
        ctx.restoreGState()
    }

    /// The trailing "…" — a dashed circle with three dots (the iOS `ButtonRowMenuPillView` visual),
    /// drawn in the accent so it reads as a control rather than a labelled pill.
    private func drawMenuAffordance(in ctx: CGContext) {
        guard showsMenuAffordance, menuButtonFrame != .zero else { return }
        let rect = menuButtonFrame.offsetBy(dx: frame.minX, dy: frame.minY)
        guard rect.width > 2, rect.height > 2 else { return }
        let tint = mapper.appearance.linkColor
        let circle = rect.insetBy(dx: 1.0, dy: 1.0)
        ctx.saveGState()
        ctx.setStrokeColor(tint.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineDash(phase: 0.0, lengths: [4.0, 3.0])
        ctx.strokeEllipse(in: circle)
        ctx.setLineDash(phase: 0.0, lengths: [])
        let dotRadius: CGFloat = 1.75
        let gap: CGFloat = 5.0
        let centre = CGPoint(x: circle.midX, y: circle.midY)
        ctx.setFillColor(tint.cgColor)
        for offset in [-gap, 0.0, gap] {
            ctx.fillEllipse(in: CGRect(x: centre.x + offset - dotRadius, y: centre.y - dotRadius,
                                       width: dotRadius * 2.0, height: dotRadius * 2.0))
        }
        ctx.restoreGState()
    }
}
#endif
