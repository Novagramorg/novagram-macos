#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Identifies a hidden spoiler run by its region's STABLE block identity + its index among that
/// region's spoiler runs, so a dust view survives a re-scan even when an earlier edit shifts the
/// region's absolute position (keying on the region's `globalStart` re-keyed on every such shift,
/// dissolving+recreating a persisting run's dust — a flicker).
@available(macOS 12, *)
struct SpoilerKey: Hashable { let blockID: BlockID; let runIndex: Int }

@available(macOS 12, *)
extension LeafTextRegion {
    /// The owning block's stable identity (unique per paragraph / caption / table cell), used as the
    /// position-independent dust key. `TextNodeRef` is `Equatable` but not `Hashable`, so we unwrap the
    /// `BlockID` it carries (which is `Hashable`).
    var stableBlockID: BlockID {
        switch ref {
        case let .paragraph(id): return id
        case let .caption(id): return id
        case let .code(id): return id
        case let .codeLanguage(id): return id
        case let .pullQuote(id): return id
        case let .quoteAuthor(id): return id
        case let .detailsTitle(id): return id
        }
    }
}

/// One scanned spoiler run: its global range, the per-line canvas rects it covers, and whether it is
/// currently HIDDEN (the selection/caret is not inside it).
@available(macOS 12, *)
struct SpoilerRun {
    let key: SpoilerKey
    let regionStart: Int
    let globalRange: Range<Int>
    let canvasLineRects: [CGRect]
    var hidden: Bool
}

/// A live dust view hosted over a hidden run, plus the canvas frame it was last positioned/sized at
/// (so we only re-feed geometry to the effect when it actually moves).
@available(macOS 12, *)
final class HostedSpoilerDust {
    let effect: SpoilerEffect
    var canvasFrame: CGRect
    var lastUpdatedFrame: CGRect = .null
    init(effect: SpoilerEffect, canvasFrame: CGRect) { self.effect = effect; self.canvasFrame = canvasFrame }
}

@available(macOS 12, *)
extension DocumentCanvasView {
    /// Tightens the dust cover slightly inside each glyph line rect so the cover hugs the text.
    private static let spoilerRectInset: CGFloat = 1

    /// Fast-path gate: scans every leaf region once for any `.rtSpoiler` run. Recomputed ONLY on
    /// model-mutating paths (setBlocks / end of `editing { }`), never per caret-move — `syncSpoilers`
    /// reads this flag to skip all work in spoiler-free documents (which keeps the existing suite
    /// completely unaffected).
    func recomputeDocumentHasSpoilers() {
        documentHasSpoilers = allLeafRegions().contains { region in
            let attr = region.layout.attributedString
            var found = false
            attr.enumerateAttribute(.rtSpoiler, in: NSRange(location: 0, length: attr.length), options: []) { v, _, stop in
                if (v as? Bool) == true { found = true; stop.pointee = true }
            }
            return found
        }
    }

    /// A run is revealed when the caret/selection lands in it: a collapsed caret anywhere inside
    /// `[gStart, gEnd]`, or a non-empty selection that overlaps the run.
    private func isSpoilerRevealed(gStart: Int, gEnd: Int) -> Bool {
        // Only a collapsed caret INSIDE the spoiler reveals it (to edit the hidden text). A RANGE selection
        // covering it does NOT reveal — so applying spoiler to a selection shows the dust immediately, and
        // selecting spoilered text keeps it hidden (matching the sent message / legacy composer).
        guard selFrom == selTo else { return false }
        return selFrom >= gStart && selFrom <= gEnd
    }

    /// Scans every leaf region for `.rtSpoiler` runs, computing each run's global range, its per-line
    /// canvas rects, and whether it is hidden given the current selection.
    func computeSpoilerRuns() -> [SpoilerRun] {
        var result: [SpoilerRun] = []
        for region in allLeafRegions() {
            let attr = region.layout.attributedString
            var idx = 0
            attr.enumerateAttribute(.rtSpoiler, in: NSRange(location: 0, length: attr.length), options: []) { v, range, _ in
                guard (v as? Bool) == true else { return }
                let gStart = region.globalStart + range.location, gEnd = gStart + range.length
                let lineRects = region.layout.selectionRects(start: range.location, end: range.location + range.length)
                    .map { $0.offsetBy(dx: region.canvasOrigin.x, dy: region.canvasOrigin.y)
                        .insetBy(dx: Self.spoilerRectInset, dy: Self.spoilerRectInset) }
                result.append(SpoilerRun(key: SpoilerKey(blockID: region.stableBlockID, runIndex: idx),
                                         regionStart: region.globalStart, globalRange: gStart..<gEnd,
                                         canvasLineRects: lineRects, hidden: !isSpoilerRevealed(gStart: gStart, gEnd: gEnd)))
                idx += 1
            }
        }
        return result
    }

    /// Reconciles the clear-foreground hide (per region) AND the dust overlay views against the current
    /// spoiler runs. Cheap no-op when the document has no spoilers and none are tracked — the
    /// `documentHasSpoilers` gate is what keeps spoiler-free documents untouched.
    func syncSpoilers() {
        guard documentHasSpoilers || !spoilerRuns.isEmpty || !spoilerDustViews.isEmpty else { return }
        let runs = computeSpoilerRuns(); spoilerRuns = runs
        var hideChanged = false
        for region in allLeafRegions() {
            let local = runs.filter { $0.hidden && $0.regionStart == region.globalStart }
                .map { NSRange(location: $0.globalRange.lowerBound - region.globalStart, length: $0.globalRange.count) }
            if region.layout.setSpoilerHidden(local) { hideChanged = true }
        }
        reconcileSpoilerDust(runs)
        if hideChanged { needsDisplay = true }
    }

    private func reconcileSpoilerDust(_ runs: [SpoilerRun]) {
        var present = Set<SpoilerKey>()
        for run in runs where run.hidden {
            guard let first = run.canvasLineRects.first else { continue }
            let bounding = run.canvasLineRects.dropFirst().reduce(first) { $0.union($1) }
            present.insert(run.key)
            let hosted: HostedSpoilerDust
            if let h = spoilerDustViews[run.key] { hosted = h }
            else {
                let effect = (spoilerEffectProvider?(bounding.size)) ?? DefaultSpoilerEffectView(frame: CGRect(origin: .zero, size: bounding.size))
                let h = HostedSpoilerDust(effect: effect, canvasFrame: bounding)
                spoilerDustViews[run.key] = h; spoilerOverlay.addSubview(effect.nsView); hosted = h
            }
            hosted.canvasFrame = bounding
            if bounding != hosted.lastUpdatedFrame {
                let localLine = run.canvasLineRects.map { $0.offsetBy(dx: -bounding.minX, dy: -bounding.minY) }
                hosted.effect.update(size: bounding.size, color: editorAppearance.spoilerCoverColor, lineRects: localLine, wordRects: localLine)
                hosted.lastUpdatedFrame = bounding
            }
            hosted.effect.nsView.frame = bounding
        }
        for (key, hosted) in spoilerDustViews where !present.contains(key) {
            hosted.effect.dissolve(explodingAt: nil) {}; spoilerDustViews[key] = nil
        }
    }
}
#endif
