#if canImport(AppKit)
import AppKit

/// Look Up / Share for the current selection, via the native AppKit APIs. AppKit gives an `NSView` these
/// for free only through `NSTextView`; a custom `NSTextInputClient` view drives them itself:
/// `showDefinition(for:at:)` (the system dictionary panel) and `NSSharingServicePicker`.
@available(macOS 12, *)
extension DocumentCanvasView {
    /// Show the system dictionary panel for the selected term, anchored under the selection start.
    func lookUpSelection() {
        let term = text(inGlobalRange: selFrom, selTo)
        guard !term.isEmpty else { return }
        let rect = caretRect(forGlobal: selFrom)
        showDefinition(for: NSAttributedString(string: term),
                       at: NSPoint(x: rect.minX, y: rect.maxY))
    }

    /// Show the Share sheet for the selected text, anchored at the click point.
    func shareSelection(from event: NSEvent) {
        let term = text(inGlobalRange: selFrom, selTo)
        guard !term.isEmpty else { return }
        let picker = NSSharingServicePicker(items: [term])
        let p = convert(event.locationInWindow, from: nil)
        picker.show(relativeTo: NSRect(origin: p, size: .zero), of: self, preferredEdge: .minY)
    }
}
#endif
