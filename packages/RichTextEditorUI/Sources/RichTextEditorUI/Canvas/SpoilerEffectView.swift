#if canImport(AppKit)
import AppKit

/// Pluggable spoiler "dust" overlay. The package ships a private-API-free default; a host may inject a
/// richer effect via RichTextEditorView.spoilerEffectProvider.
@available(macOS 12, *)
public protocol SpoilerEffect: AnyObject {
    var nsView: NSView { get }
    var isRevealed: Bool { get }
    func update(size: CGSize, color: NSColor, lineRects: [CGRect], wordRects: [CGRect])
    func dissolve(explodingAt point: CGPoint?, completion: @escaping () -> Void)
}

/// Minimal fallback: translucent fill over the hidden rects that cross-fades out on reveal. No private API.
@available(macOS 12, *)
final class DefaultSpoilerEffectView: NSView, SpoilerEffect {
    private(set) var isRevealed = false
    private var fillColor: NSColor = .secondaryLabelColor
    private var rects: [CGRect] = []
    var nsView: NSView { self }
    override init(frame frameRect: NSRect) { super.init(frame: frameRect); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func update(size: CGSize, color: NSColor, lineRects: [CGRect], wordRects: [CGRect]) {
        fillColor = color; rects = wordRects.isEmpty ? lineRects : wordRects
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard !isRevealed else { return }
        fillColor.withAlphaComponent(0.9).setFill()
        for r in rects { NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill() }
    }
    func dissolve(explodingAt point: CGPoint?, completion: @escaping () -> Void) {
        guard !isRevealed else { completion(); return }
        isRevealed = true
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.3; animator().alphaValue = 0 },
                                             completionHandler: { [weak self] in self?.removeFromSuperview(); completion() })
    }
}
#endif
