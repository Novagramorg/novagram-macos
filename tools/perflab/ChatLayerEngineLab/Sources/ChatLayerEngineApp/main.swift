import Cocoa
import TGUIKit
import ChatLayerEngine

final class DemoDelegate: NSObject, NSApplicationDelegate {
    var window: Window!
    func applicationDidFinishLaunching(_ notification: Notification) {
        ChatLayerDemo.bootstrap()
        TGUIKitAccessibility.isEnabled = true
        window = Window(contentRect: NSRect(x: 100, y: 100, width: 940, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Chat rows: native views / layer engine"
        let root = View(frame: NSRect(x: 0, y: 0, width: 940, height: 760))
        window.contentView = root
        for candidate in [false, true] {
            let scroll = NSScrollView(frame: NSRect(x: candidate ? 470 : 0, y: 0, width: 470, height: 760))
            scroll.hasVerticalScroller = true
            scroll.autoresizingMask = [.height]
            scroll.documentView = ChatLayerDemo.makeDocument(layerBased: candidate, count: 80) { [weak self] value in
                self?.window.title = "\(candidate ? "Layers" : "Views"): \(value)"
            }
            root.addSubview(scroll)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

_ = NSApplication.shared
NSApp.setActivationPolicy(.regular)
let delegate = DemoDelegate()
NSApp.delegate = delegate
NSApp.run()
