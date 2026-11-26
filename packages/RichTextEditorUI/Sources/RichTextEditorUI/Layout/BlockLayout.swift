#if canImport(AppKit)
import AppKit

/// One paragraph block's TextKit 2 layout context (line layout only). All geometry is returned in
/// the block's own container coordinate space (origin 0,0); the document view offsets it.
@available(macOS 12, *)
final class BlockLayout {
    let contentStorage: NSTextContentStorage
    let layoutManager: NSTextLayoutManager
    let container: NSTextContainer

    init(attributedString: NSAttributedString, width: CGFloat) {
        contentStorage = NSTextContentStorage()
        layoutManager = NSTextLayoutManager()
        container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
        contentStorage.textStorage = NSTextStorage(attributedString: attributedString)
    }

    var attributedString: NSAttributedString {
        get { contentStorage.textStorage ?? NSAttributedString() }
        set { clearSpoilerRendering(); contentStorage.textStorage?.setAttributedString(newValue) }
    }

    // MARK: - Spoiler hide (clear-foreground rendering attribute; never enters the model)

    /// The text ranges currently rendered with a clear foreground (so spoiler glyphs occupy layout but
    /// don't draw). Tracked so they can be removed before the next hide pass.
    private var spoilerTextRanges: [NSTextRange] = []
    /// The local UTF-16 ranges last hidden — the equality key for the LOAD-BEARING no-op guard.
    private var spoilerLocalRanges: [NSRange] = []

    /// Remove the clear-foreground spoiler-hide rendering attributes (while the tracked text ranges are
    /// still valid) and clear tracking. Call BEFORE mutating storage so no stale hide lingers on text.
    private func clearSpoilerRendering() {
        for tr in spoilerTextRanges { layoutManager.removeRenderingAttribute(.foregroundColor, for: tr) }
        spoilerTextRanges = []
        spoilerLocalRanges = []
    }

    /// Hides `ranges` (local UTF-16) by applying a clear-foreground RENDERING attribute (glyphs stop
    /// drawing but still occupy layout; never touches the text storage / model). Returns `true` when the
    /// hidden set changed. The no-op equality guard is LOAD-BEARING: re-applying the same hide must NOT
    /// report a change, or the layout → syncSpoilers → setSpoilerHidden → needsDisplay loop never settles.
    @discardableResult
    func setSpoilerHidden(_ ranges: [NSRange]) -> Bool {
        let effective = ranges.filter { $0.length > 0 }
        if effective == spoilerLocalRanges { return false }
        for prev in spoilerTextRanges { layoutManager.removeRenderingAttribute(.foregroundColor, for: prev) }
        spoilerTextRanges = []
        for r in effective {
            guard let tr = textRange(r.location, r.location + r.length) else { continue }
            layoutManager.addRenderingAttribute(.foregroundColor, value: NSColor.clear, for: tr)
            spoilerTextRanges.append(tr)
        }
        spoilerLocalRanges = effective
        return true
    }

    var length: Int { contentStorage.textStorage?.length ?? 0 }

    func setWidth(_ width: CGFloat) {
        container.size = CGSize(width: width, height: .greatestFiniteMagnitude)
    }

    var boundingHeight: CGFloat {
        var maxY: CGFloat = 0
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            maxY = max(maxY, fragment.layoutFragmentFrame.maxY)
            return true
        }
        return maxY
    }

    /// Y of the first laid-out text line's baseline, relative to the top of the layout (y = 0, i.e. the
    /// block's `textOrigin.y`). `nil` when there is no laid-out line (empty text — TextKit 2 lays out no
    /// fragment). Used to align a list marker (drawn outside the text storage) to the paragraph's first
    /// line, which `lineHeightMultiple` shifts below the natural top.
    var firstLineBaselineFromTop: CGFloat? {
        var result: CGFloat?
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            guard let line = fragment.textLineFragments.first else { return true }
            result = fragment.layoutFragmentFrame.minY + line.glyphOrigin.y
            return false
        }
        return result
    }

    func textRange(_ start: Int, _ end: Int) -> NSTextRange? {
        let docStart = contentStorage.documentRange.location
        guard let s = contentStorage.location(docStart, offsetBy: start),
              let e = contentStorage.location(docStart, offsetBy: end) else { return nil }
        return NSTextRange(location: s, end: e)
    }

    func caretRect(atOffset offset: Int) -> CGRect {
        guard let range = textRange(offset, offset) else { return CGRect(x: 0, y: 0, width: 2, height: 20) }
        var rect = CGRect(x: 0, y: 0, width: 2, height: 20)
        // `.selection` (not `.standard`): for an ALIGNED line (centered pull quote, right-aligned/RTL
        // text) the `.standard` segment reports x in the unaligned left-origin coordinate — the caret
        // draws mid-line while the position is at the end. `.selection` is the glyph-accurate geometry
        // the selection wash uses; for a zero-width range it is the true insertion point, and it is
        // identical to `.standard` for plain left-aligned text.
        layoutManager.enumerateTextSegments(in: range, type: .selection, options: []) { _, frame, _, _ in
            rect = CGRect(x: frame.minX, y: frame.minY, width: 2, height: max(frame.height, 20))
            return false
        }
        return rect
    }

    /// The LOCAL offset of the start (`forward == false`) or end (`forward == true`) of the VISUAL line
    /// (wrapped display line) containing `offset` — drives ⌘←/⌘→. Scans caret rects by their vertical
    /// band, so a wrapped paragraph stops at each display line rather than the whole region (matching a
    /// plain NSTextView). Already at the edge → returns `offset` (a no-op, like NSTextView).
    func visualLineBoundary(atOffset offset: Int, forward: Bool) -> Int {
        let clamped = max(0, min(offset, length))
        let band = caretRect(atOffset: clamped)
        func onSameLine(_ o: Int) -> Bool {
            let r = caretRect(atOffset: o)
            return r.minY < band.maxY - 0.5 && r.maxY > band.minY + 0.5   // overlapping vertical bands
        }
        if forward {
            var end = clamped
            while end < length, onSameLine(end + 1) { end += 1 }
            return end
        }
        var start = clamped
        while start > 0, onSameLine(start - 1) { start -= 1 }
        return start
    }

    func selectionRects(start: Int, end: Int) -> [CGRect] {
        guard start < end, let range = textRange(start, end) else { return [] }
        var rects: [CGRect] = []
        layoutManager.enumerateTextSegments(in: range, type: .selection, options: []) { _, frame, _, _ in
            rects.append(frame)
            return true
        }
        return rects
    }

    func closestOffset(toPoint point: CGPoint) -> Int {
        // Pick by line first, then by x within that line: a tap in a line's vertical band must map to
        // that line even if a longer line above has an end-caret that's horizontally nearer (e.g.
        // tapping the empty space to the right of a short last line). `dy` is the vertical distance to
        // the caret's line band (0 when the tap is inside it); ties on the same line break on `dx`.
        var best = 0
        var bestDy = CGFloat.greatestFiniteMagnitude
        var bestDx = CGFloat.greatestFiniteMagnitude
        for offset in 0...length {
            let caret = caretRect(atOffset: offset)
            let dy = point.y < caret.minY ? caret.minY - point.y
                   : point.y > caret.maxY ? point.y - caret.maxY : 0
            let dx = abs(caret.midX - point.x)
            if dy < bestDy - 0.5 || (dy <= bestDy + 0.5 && dx < bestDx) {
                bestDy = dy; bestDx = dx; best = offset
            }
        }
        return best
    }

    /// Draws the laid-out text fragments into `ctx`, translated to `origin` (canvas coordinates).
    func drawText(in ctx: CGContext, at origin: CGPoint) {
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            fragment.draw(at: fragment.layoutFragmentFrame.origin, in: ctx); return true
        }
        ctx.restoreGState()
    }

    func replace(start: Int, end: Int, with string: NSAttributedString) {
        clearSpoilerRendering()
        contentStorage.textStorage?.replaceCharacters(in: NSRange(location: start, length: end - start),
                                                       with: string)
        // TextKit 2 leaves the layout fragments BELOW the edited paragraph at stale positions after an
        // in-place edit — even `.ensuresLayout` enumeration doesn't move them, so a top line that grows
        // (wraps) draws OVER the lines below (empirically verified on macOS). Invalidating the whole
        // (per-block, small) document range forces consistent fragment positions on the next layout pass.
        layoutManager.invalidateLayout(for: layoutManager.documentRange)
    }
}
#endif
