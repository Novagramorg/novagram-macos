import Cocoa
import WidgetSandbox
import TwidgetRenderer
import LiteHTML
import WebKit

private final class WidgetLabScrollDocument: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if NSApp.currentEvent?.type == .scrollWheel {
            return frame.contains(point) ? self : nil
        }
        return super.hitTest(point)
    }
}

func runInteractiveLab() {
    let menu = NSMenu()
    let applicationMenu = NSMenu()
    applicationMenu.addItem(withTitle: "Quit Widget Modal Lab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let applicationItem = NSMenuItem()
    applicationItem.submenu = applicationMenu
    menu.addItem(applicationItem)
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let editItem = NSMenuItem()
    editItem.submenu = editMenu
    menu.addItem(editItem)
    app.mainMenu = menu
    let html = try! String(contentsOfFile: args[2])
    let width = CGFloat(option("--width").flatMap(Double.init) ?? 420)
    let height = CGFloat(option("--height").flatMap(Double.init) ?? 760)
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: height), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = option("--renderer") == "web" ? "Widget Modal Lab — WebKit" : "Widget Modal Lab"
    window.isReleasedWhenClosed = false
    var renderer: LiteHTMLWidgetRenderer?
    let host = try! WidgetHost(html: html, theme: option("--theme") ?? "dark", width: width, options: labOptions(), rendererFactory: { resources, theme, width in
        if option("--renderer") == "web" {
            let made = RendererWebView(rendererBundle: resources.rendererBundle, theme: theme)
            knownHelpers = { [weak view = made.webView] in
                guard let view else { return [] }
                return webKitHelpers(view, view.configuration.processPool)
            }
            return made
        }
        let made = LiteHTMLWidgetRenderer(theme: theme, width: width)
        renderer = made
        return made
    }, executor: args.contains("--background") && option("--renderer") != "web" ? WidgetExecutor(queue: WidgetExecutor.makeQueue("widget.lab")) : WidgetExecutor())
    host.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    host.view.autoresizingMask = [.width, .height]
    let scrollDocument: WidgetLabScrollDocument?
    if args.contains("--scroll-content") {
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        let document = WidgetLabScrollDocument(frame: scroll.bounds)
        document.autoresizingMask = [.width]
        scroll.documentView = document
        document.addSubview(host.view)
        window.contentView?.addSubview(scroll)
        scrollDocument = document
    } else {
        window.contentView?.addSubview(host.view)
        scrollDocument = nil
    }
    host.onChange = { state in
        if let document = scrollDocument, state.height > 0 {
            document.frame.size.height = state.height
            host.view.frame = document.bounds
        }
        if let error = state.lastError { print("ERROR \(error)") }
        if let dead = state.dead { print("STOPPED \(dead)") }
    }
    app.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    var previous = 0
    let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
        guard let renderer else { return }
        let state = host.diagnostics
        let frame = renderer.view.frame
        host.executor.async {
            guard renderer.layoutCount != previous else { return }
            previous = renderer.layoutCount
            print("HOST loaded=\(state.loaded) rendered=\(state.rendered) height=\(state.height) frame=\(frame) logs=\(state.logs.suffix(4))")
            print("MODAL layouts=\(previous) total-ms=\(renderer.layoutMilliseconds) worst-ms=\(renderer.layoutMaxMilliseconds) cache=\(LHDocument.layoutCacheStats()) stages=\(renderer.stageMilliseconds)")
        }
    }
    let deadline = Timer.scheduledTimer(withTimeInterval: option("--seconds").flatMap(Double.init) ?? 1800, repeats: false) { _ in
        app.stop(nil)
    }
    app.run()
    deadline.invalidate()
    timer.invalidate()
    host.destroy()
    window.orderOut(nil)
}
