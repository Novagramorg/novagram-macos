import Cocoa
import TGUIKit

public final class InlineStickerItemLayer: SimpleLayer {
    public weak var superview: NSView?
    var changes: [Bool?] = []
    public var isPlayable: Bool? {
        didSet {
            if oldValue != isPlayable { changes.append(isPlayable) }
        }
    }
}

final class KeyWindow: NSWindow {
    var key = true
    var reads = 0
    override var isKeyWindow: Bool {
        reads += 1
        return key
    }
}

final class TextHost: NSView {
    var reads = 0
    override var visibleRect: NSRect {
        reads += 1
        return super.visibleRect
    }
}

final class Fixture {
    let window: KeyWindow
    let scroll: NSScrollView
    let document: NSView
    let text = TextHost(frame: NSRect(x: 0, y: 0, width: 300, height: 2000))
    var layers: [Int: SimpleLayer] = [:]
    let reference = ReferenceRenderer()

    init(count: Int, depth: Int = 8) {
        _ = NSApplication.shared
        window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        document = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 2000))
        scroll.documentView = document
        window.contentView = scroll
        var parent = document
        for _ in 0..<depth {
            let view = NSView(frame: document.bounds)
            parent.addSubview(view)
            parent = view
        }
        parent.addSubview(text)
        for index in 0..<count {
            let layer = InlineStickerItemLayer()
            layer.frame = NSRect(x: (index % 10) * 25, y: (index / 10) * 25, width: 20, height: 20)
            layer.superview = text
            layers[index] = layer
        }
        reference.inlineStickerItemViews = layers
    }
    func update(_ baseline: Bool, lite: Bool = false, detached: Bool = false) {
        if baseline { reference.update(window: detached ? nil : window, isLite: lite) }
        else { updateInlineStickerPlayback(layers.values, window: detached ? nil : window, isLite: lite) }
    }
    var states: [Int: Bool] {
        layers.compactMapValues { ($0 as? InlineStickerItemLayer)?.isPlayable }
    }
    deinit {
        window.contentView = nil
        window.close()
    }
}
