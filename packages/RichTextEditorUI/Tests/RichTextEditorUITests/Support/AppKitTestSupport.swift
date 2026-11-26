#if canImport(AppKit)
import AppKit
import XCTest

/// Base class for AppKit view-layer tests. Boots a headless NSApplication once per process.
@available(macOS 12, *)
class AppKitTestCase: XCTestCase {
    private static let boot: Void = {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)   // do NOT call NSApp.run()
    }()
    override func setUp() { super.setUp(); _ = AppKitTestCase.boot }

    /// Renders a view offscreen and returns its bitmap (replaces UIGraphicsImageRenderer{drawHierarchy}).
    func snapshot(_ view: NSView) -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// A solid-color NSImage of a given size (replaces UIGraphicsImageRenderer content factories).
    func image(of size: CGSize, fill: NSColor = .systemTeal) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        fill.setFill()
        NSRect(origin: .zero, size: size).fill()
        img.unlockFocus()
        return img
    }

    /// Hosts a view in a borderless offscreen window and makes it first responder.
    /// Use ONLY for responder-routing / edit-menu tests; keep pure draw/geometry tests windowless.
    @discardableResult
    func hostInWindow(_ view: NSView) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 800),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView?.addSubview(view)
        view.frame = w.contentView!.bounds
        w.makeFirstResponder(view)
        return w
    }
}
#endif
