import AppKit
import TGUIKit
import TwidgetRenderer
import WidgetSandbox

let padding: CGFloat = 8
let widgetWidth: CGFloat = 300

struct Scenario {
    let name: String
    let html: String
    let offset: CGFloat
    let widget: Int
    var clicks = true
    var inserts = false
}

func page(_ body: String, script: String) -> String {
    return """
    <style>body{margin:0;font-family:-apple-system;font-size:13px} .b{box-sizing:border-box} #target{background:#ff00ff;height:36px} .f{background:#d0e4ff} .g{background:#c8f0c8}</style>
    \(body)
    <script>\(script)</script>
    """
}

let allScenarios: [Scenario] = [
    Scenario(name: "tab at top grows details below", html: page("<div id='target'></div><div class='f' style='height:60px'></div><div id='slot'></div><div class='g' style='height:40px'></div>", script: "document.getElementById('target').addEventListener('click',()=>{const d=document.createElement('div');d.className='f';d.style.height='200px';document.getElementById('slot').appendChild(d)})"), offset: 300, widget: 6),
    Scenario(name: "show more at bottom grows above", html: page("<div class='f' style='height:120px'></div><div id='slot'></div><div id='target'></div>", script: "document.getElementById('target').addEventListener('click',()=>{const d=document.createElement('div');d.className='g';d.style.height='160px';document.getElementById('slot').appendChild(d)})"), offset: 300, widget: 6),
    Scenario(name: "header in lower half opens body below", html: page("<div class='f' style='height:200px'></div><div id='target'></div><div id='slot'></div><div class='g' style='height:20px'></div>", script: "document.getElementById('target').addEventListener('click',()=>{const d=document.createElement('div');d.className='f';d.style.height='160px';document.getElementById('slot').appendChild(d)})"), offset: 300, widget: 6),
    Scenario(name: "collapse above bottom button", html: page("<div id='gone' class='f' style='height:150px'></div><div class='g' style='height:40px'></div><div id='target'></div>", script: "document.getElementById('target').addEventListener('click',()=>{document.getElementById('gone').remove()})"), offset: 300, widget: 6),
    Scenario(name: "collapse details below top tab", html: page("<div id='target'></div><div id='gone' class='f' style='height:200px'></div><div class='g' style='height:40px'></div>", script: "document.getElementById('target').addEventListener('click',()=>{document.getElementById('gone').remove()})"), offset: 300, widget: 6),
    Scenario(name: "css transition grows below tab", html: page("<div id='target'></div><div id='panel' class='f' style='height:40px;transition:height .35s ease'></div><div class='g' style='height:40px'></div>", script: "document.getElementById('target').addEventListener('click',()=>{document.getElementById('panel').style.height='240px'})"), offset: 300, widget: 6),
    Scenario(name: "css transition grows above button", html: page("<div id='panel' class='f' style='height:40px;transition:height .35s ease'></div><div class='g' style='height:40px'></div><div id='target'></div>", script: "document.getElementById('target').addEventListener('click',()=>{document.getElementById('panel').style.height='240px'})"), offset: 300, widget: 6),
    Scenario(name: "huge growth below tab", html: page("<div id='target'></div><div id='slot'></div><div class='g' style='height:40px'></div>", script: "document.getElementById('target').addEventListener('click',()=>{const d=document.createElement('div');d.className='f';d.style.height='700px';document.getElementById('slot').appendChild(d)})"), offset: 300, widget: 6),
    Scenario(name: "middle header inserts above and below", html: page("<div class='f' style='height:80px'></div><div id='above'></div><div id='target'></div><div id='below'></div><div class='g' style='height:80px'></div>", script: "document.getElementById('target').addEventListener('click',()=>{const a=document.createElement('div');a.className='g';a.style.height='60px';document.getElementById('above').appendChild(a);const b=document.createElement('div');b.className='f';b.style.height='140px';document.getElementById('below').appendChild(b)})"), offset: 300, widget: 6),
    Scenario(name: "timer grows widget at chat bottom", html: page("<div class='g' style='height:60px'></div><div id='slot'></div><div id='target'></div>", script: "setTimeout(()=>{const d=document.createElement('div');d.className='f';d.style.height='180px';document.getElementById('slot').appendChild(d)},1900)"), offset: 0, widget: 0, clicks: false),
    Scenario(name: "css transition shrinks above button", html: page("<div id='panel' class='f' style='height:240px;transition:height .35s ease'></div><div class='g' style='height:40px'></div><div id='target'></div>", script: "document.getElementById('target').addEventListener('click',()=>{document.getElementById('panel').style.height='40px'})"), offset: 300, widget: 6),
    Scenario(name: "css transition shrinks below tab", html: page("<div id='target'></div><div id='panel' class='f' style='height:240px;transition:height .35s ease'></div><div class='g' style='height:40px'></div>", script: "document.getElementById('target').addEventListener('click',()=>{document.getElementById('panel').style.height='40px'})"), offset: 300, widget: 6),
    Scenario(name: "message arrives while tab grows", html: page("<div id='target'></div><div id='slot'></div><div class='g' style='height:40px'></div>", script: "document.getElementById('target').addEventListener('click',()=>{const d=document.createElement('div');d.className='f';d.style.height='200px';document.getElementById('slot').appendChild(d)})"), offset: 300, widget: 6, inserts: true),
    Scenario(name: "message arrives while css grows above", html: page("<div id='panel' class='f' style='height:40px;transition:height .35s ease'></div><div class='g' style='height:40px'></div><div id='target'></div>", script: "document.getElementById('target').addEventListener('click',()=>{document.getElementById('panel').style.height='240px'})"), offset: 300, widget: 6, inserts: true),
    Scenario(name: "tab grows at chat bottom", html: page("<div id='target'></div><div id='slot'></div><div class='g' style='height:60px'></div>", script: "document.getElementById('target').addEventListener('click',()=>{const d=document.createElement('div');d.className='f';d.style.height='200px';document.getElementById('slot').appendChild(d)})"), offset: 0, widget: 0),
]

let scenarios: [Scenario] = ProcessInfo.processInfo.environment["LAB_ONLY"].map { only in allScenarios.filter { $0.name.contains(only) } } ?? allScenarios

enum Click {
    static var location: NSPoint = .zero
    static var time: CFTimeInterval = 0
    static let monitor: Any? = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
        location = event.locationInWindow
        time = CACurrentMediaTime()
        return event
    }

    static func point(in view: NSView) -> CGFloat? {
        guard CACurrentMediaTime() - time < 1.5 else {
            return nil
        }
        let point = view.convert(location, from: nil)
        guard view.bounds.contains(point) else {
            return nil
        }
        return view.isFlipped ? point.y : view.bounds.height - point.y
    }
}

final class LabSpace: WidgetFeedSpace {
    let slot: WidgetFeedSlot

    init(_ slot: WidgetFeedSlot) {
        self.slot = slot
        slot.space = self
        slot.locate = { CGRect(x: 0, y: 0, width: widgetWidth, height: 400) }
    }

    var feedViewport: CGRect { CGRect(x: 0, y: 0, width: widgetWidth, height: 800) }
    var feedOnScreen: Bool { true }
    func feedSlots(in rect: CGRect) -> [WidgetFeedSlot] { [slot] }
}

final class Widget {
    let bubble: WidgetBubble
    var renderer: LiteHTMLWidgetRenderer?
    let feed = WidgetFeed()
    var space: LabSpace?
    var lastChange: CFTimeInterval = 0
    var previousChange: CFTimeInterval = 0
    var keepsBottom: Bool?
    var pacing = TableRowResizePacing()

    func attach() {
        let space = LabSpace(bubble.slot)
        self.space = space
        feed.attach(space)
        feed.update()
    }

    init(html: String) {
        var made: ((LiteHTMLWidgetRenderer) -> Void)?
        bubble = WidgetBubble(html: html, theme: "light", width: widgetWidth, feed: feed, rendererFactory: { _, theme, width in
            let renderer = LiteHTMLWidgetRenderer(theme: theme, width: width)
            made?(renderer)
            return renderer
        })
        made = { [weak self] renderer in
            self?.renderer = renderer
        }
    }
}

final class RealItem: TableRowItem {
    let rowHeight: CGFloat
    let widget: Widget?
    let usesAnchor: Bool
    let usesDiff: Bool

    init(id: Int, height: CGFloat, widget: Widget? = nil, usesAnchor: Bool = true, usesDiff: Bool = true) {
        self.rowHeight = height
        self.widget = widget
        self.usesAnchor = usesAnchor
        self.usesDiff = usesDiff
        super.init(.zero, stableId: id)
    }

    override var height: CGFloat {
        return rowHeight
    }

    var contentHeight: CGFloat {
        return rowHeight - padding * 2
    }

    override func viewClass() -> AnyClass {
        return RealRowView.self
    }

    override func resizeAnchor(previous: TableRowItem) -> TableRowResizeAnchor? {
        guard usesAnchor, let previous = previous as? RealItem, let view = previous.view as? RealRowView, let table = previous.table, let widget = widget else {
            return nil
        }
        let oldHeight = previous.contentHeight
        let newHeight = contentHeight
        let sticksToBottom = table.documentOffset.y <= 0.5
        let click = Click.point(in: view.clip)
        var diff = usesDiff ? widget.renderer?.lastResizeDiff : nil
        if let current = diff, abs(current.oldHeight - oldHeight) > 1 || abs(current.newHeight - newHeight) > 1 {
            diff = nil
        }
        widget.renderer?.prefersBottomResize = sticksToBottom
        let anchor: TableRowResizeAnchor
        let continuous = widget.lastChange - widget.previousChange < 0.1
        if click == nil, sticksToBottom {
            anchor = .bottom(oldHeight: oldHeight, newHeight: newHeight)
        } else if click != nil, let from = diff?.pointerFrom, let to = diff?.pointerTo {
            anchor = .pointer(from: from, to: to, oldHeight: oldHeight, newHeight: newHeight)
        } else if let diff = diff {
            let point = click ?? (diff.keepsBottom ? oldHeight : 0)
            anchor = diff.keepsBottom ? TableRowResizeAnchor(from: point, to: point + newHeight - oldHeight) : TableRowResizeAnchor(from: point, to: point)
        } else if continuous, let keepsBottom = widget.keepsBottom {
            let point = click ?? (keepsBottom ? oldHeight : 0)
            anchor = keepsBottom ? TableRowResizeAnchor(from: point, to: point + newHeight - oldHeight) : TableRowResizeAnchor(from: point, to: point)
        } else {
            anchor = TableRowResizeAnchor.resolve(oldHeight: oldHeight, newHeight: newHeight, click: click, sticksToBottom: sticksToBottom)
        }
        widget.keepsBottom = abs((anchor.to - anchor.from) - (newHeight - oldHeight)) < abs(anchor.to - anchor.from)
        if ProcessInfo.processInfo.environment["LAB_ANCHOR"] != nil {
            print(String(format: "anchor %.0f->%.0f h %.0f->%.0f diff %@ click %@ offset %.1f t %.3f", anchor.from, anchor.to, oldHeight, newHeight, diff.map { "\($0.oldHeight)->\($0.newHeight) p \(String(describing: $0.pointerFrom))->\(String(describing: $0.pointerTo))" } ?? "nil", click.map { String(format: "%.0f", $0) } ?? "nil", table.documentOffset.y, CACurrentMediaTime().truncatingRemainder(dividingBy: 100)))
        }
        return TableRowResizeAnchor(from: anchor.from + padding, to: anchor.to + padding)
    }
}

final class RealRowView: TableRowView {
    let clip = View()
    let container = NSView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clip.layer?.masksToBounds = true
        clip.backgroundColor = NSColor(white: 0.85, alpha: 1)
        addSubview(clip)
        container.wantsLayer = true
        clip.addSubview(container)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? RealItem else {
            return
        }
        if item.widget == nil, let id = item.stableId.base as? Int {
            clip.backgroundColor = NSColor(srgbRed: 0, green: CGFloat(id * 10) / 255, blue: 1, alpha: 1)
        }
        if let host = item.widget?.bubble.ensureHost(), host.view.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            container.addSubview(host.view)
        }
        if !animated {
            layoutClip(item, transition: .immediate)
        }
    }

    private func layoutClip(_ item: RealItem, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: clip, frame: NSMakeRect(10, padding, widgetWidth, item.contentHeight))
        container.frame = NSMakeRect(0, 0, widgetWidth, item.contentHeight)
        container.subviews.first?.frame = container.bounds
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        if let item = item as? RealItem {
            layoutClip(item, transition: transition)
        }
    }

    override func applyResizeAnchor(_ anchor: TableRowResizeAnchor, transition: ContainedViewLayoutTransition) {
        anchor.pin(container, transition: transition)
    }
}

typealias WindowListCreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

final class Lab {
    let window: NSWindow
    var table: TableView!
    var index = 0
    var failures = 0
    let mode: String
    let capture: WindowListCreateImage?

    init(mode: String) {
        self.mode = mode
        window = NSWindow(contentRect: NSMakeRect(200, 200, 360, 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.wantsLayer = true
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            capture = unsafeBitCast(symbol, to: WindowListCreateImage.self)
        } else {
            capture = nil
        }
    }

    func rowTop(_ id: Int) -> CGFloat? {
        guard let capture = capture, let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue(), let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        let scale = CGFloat(image.width) / window.frame.width
        let x = Int(150 * scale)
        let titlebar = window.frame.height - window.contentLayoutRect.height
        for row in 0 ..< image.height {
            let pixel = bytes + row * image.bytesPerRow + x * 4
            let b = Int(pixel[0]), g = Int(pixel[1]), r = Int(pixel[2])
            if r < 40, b > 200, abs(g - id * 10) <= 3 {
                return CGFloat(row) / scale - titlebar
            }
        }
        return nil
    }

    func targetY() -> CGFloat? {
        guard let capture = capture, let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() else {
            return nil
        }
        if let path = ProcessInfo.processInfo.environment["LAB_SHOT"], !FileManager.default.fileExists(atPath: path), let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
            print("shot \(image.width)x\(image.height) bpr \(image.bytesPerRow) bpp \(image.bitsPerPixel) info \(image.bitmapInfo.rawValue)")
        }
        if let dir = ProcessInfo.processInfo.environment["LAB_FRAMES"], clickStart > 0, CACurrentMediaTime() - clickStart < 0.12, let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir + String(format: "/f%03d.png", Int((CACurrentMediaTime() - clickStart) * 1000))) as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return nil
        }
        let scale = CGFloat(image.width) / window.frame.width
        let x = Int(150 * scale)
        let titlebar = window.frame.height - window.contentLayoutRect.height
        for row in 0 ..< image.height {
            let pixel = bytes + row * image.bytesPerRow + x * 4
            let b = Int(pixel[0]), g = Int(pixel[1]), r = Int(pixel[2])
            if r > 200, g < 100, b > 200 {
                return CGFloat(row) / scale - titlebar
            }
        }
        if let path = ProcessInfo.processInfo.environment["LAB_MISS"], !FileManager.default.fileExists(atPath: path), let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
        return nil
    }

    func run() {
        guard index < scenarios.count else {
            print("\(mode) failures: \(failures)")
            NSApp.terminate(nil)
            return
        }
        let scenario = scenarios[index]
        index += 1
        table?.removeFromSuperview()
        let table = TableView(frame: window.contentView!.bounds, isFlipped: false)
        window.contentView!.addSubview(table)
        self.table = table
        let widget = Widget(html: scenario.html)
        let usesAnchor = mode != "baseline"
        let usesDiff = mode == "diff"
        let early = mode == "diff" && ProcessInfo.processInfo.environment["LAB_LATE"] == nil
        widget.bubble.configure = { [weak self, weak widget] host in
            guard early else {
                return
            }
            if ProcessInfo.processInfo.environment["LAB_MERGE"] != nil { print("configured host main \(host.executor.isMain)") }
            host.onChangeOnExecutor = { [weak self, weak widget, weak host] diagnostics in
                if ProcessInfo.processInfo.environment["LAB_MERGE"] != nil { print("executor change h \(diagnostics.height) main \(host?.executor.isMain == true) thread \(Thread.isMainThread)") }
                guard host?.executor.isMain == true, diagnostics.height > 0 else {
                    return
                }
                let height = diagnostics.height
                CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                    guard let self = self, let widget = widget else {
                        return
                    }
                    self.resize(scenario, widget, to: height + padding * 2, usesAnchor: usesAnchor, usesDiff: usesDiff, sync: true)
                }
                CFRunLoopWakeUp(CFRunLoopGetMain())
            }
        }
        widget.bubble.onHeightChange = { [weak self, weak widget] in
            guard let self = self, let widget = widget else {
                return
            }
            let height = widget.bubble.height + padding * 2
            if early {
                self.resize(scenario, widget, to: height, usesAnchor: usesAnchor, usesDiff: usesDiff, sync: false)
                return
            }
            let now = CACurrentMediaTime()
            let continuous = now - widget.lastChange < 0.1
            if ProcessInfo.processInfo.environment["LAB_LOG"].map({ scenario.name.contains($0) }) == true {
                print(String(format: "height %.0f at %.3f continuous %@", widget.bubble.height, now.truncatingRemainder(dividingBy: 100), continuous ? "yes" : "no"))
            }
            widget.lastChange = now
            DispatchQueue.main.async {
                guard let current = self.table.item(stableId: AnyHashable(scenario.widget)) as? RealItem, abs(current.rowHeight - height) > 0.5 else {
                    return
                }
                let item = RealItem(id: scenario.widget, height: height, widget: widget, usesAnchor: usesAnchor, usesDiff: usesDiff)
                self.table.merge(with: TableUpdateTransition(deleted: [], inserted: [], updated: [(current.index, item)], animated: self.mode == "baseline" || (!continuous && abs(current.rowHeight - height) > 16)))
            }
        }
        for id in 0 ..< 24 {
            if id == scenario.widget {
                _ = table.addItem(item: RealItem(id: id, height: 100, widget: widget, usesAnchor: usesAnchor, usesDiff: usesDiff))
            } else {
                _ = table.addItem(item: RealItem(id: id, height: CGFloat(44 + (id * 13) % 40)))
            }
        }
        widget.attach()
        table.layoutSubtreeIfNeeded()
        table.clipView.updateBounds(to: NSMakePoint(0, scenario.offset))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.table.clipView.updateBounds(to: NSMakePoint(0, scenario.offset))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.click(scenario, widget)
            }
        }
    }

    var attempts = 0
    var clickStart: CFTimeInterval = 0

    func resize(_ scenario: Scenario, _ widget: Widget, to height: CGFloat, usesAnchor: Bool, usesDiff: Bool, sync: Bool) {
        let apply = {
            guard let current = self.table.item(stableId: AnyHashable(scenario.widget)) as? RealItem, abs(current.rowHeight - height) > 0.5 else {
                return
            }
            let now = CACurrentMediaTime()
            let continuous = now - widget.lastChange < 0.1
            widget.previousChange = widget.lastChange
            widget.lastChange = now
            let item = RealItem(id: scenario.widget, height: height, widget: widget, usesAnchor: usesAnchor, usesDiff: usesDiff)
            _ = continuous
            let animated = widget.pacing.animates(delta: height - current.rowHeight, allowed: ProcessInfo.processInfo.environment["LAB_IMMEDIATE"] == nil, now: now)
            if ProcessInfo.processInfo.environment["TW_TILE_LOG"] != nil {
                print(String(format: "MERGE %.4f h %.1f", CACurrentMediaTime(), height - padding * 2))
            }
            if ProcessInfo.processInfo.environment["LAB_MERGE"] != nil {
                print(String(format: "merge at %.3f animated %@ sync %@ h %.0f", now - self.clickStart, animated ? "yes" : "no", sync ? "yes" : "no", height))
            }
            self.table.merge(with: TableUpdateTransition(deleted: [], inserted: [], updated: [(current.index, item)], animated: animated))
        }
        if sync {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    func click(_ scenario: Scenario, _ widget: Widget) {
        let initialHeight = widget.bubble.height
        guard let view = table.viewNecessary(at: scenario.widget) as? RealRowView, let before = targetY() else {
            print("SKIP \(scenario.name): target not visible")
            failures += 1
            run()
            return
        }
        let flippedTop = window.contentView!.bounds.height - before
        let inClip = view.clip.convert(NSMakePoint(150, 0), from: nil)
        _ = inClip
        let point = NSMakePoint(150 + 10, flippedTop - 10)
        let location = window.contentView!.convert(point, to: nil)
        if !window.isKeyWindow || ProcessInfo.processInfo.environment["LAB_ACTIVATE"] != nil {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        if ProcessInfo.processInfo.environment["LAB_DEBUG"] != nil {
            let hit = window.contentView!.hitTest(point)
            print("hit \(String(describing: hit.map { type(of: $0) })) live \(widget.bubble.slot.isLive) visible \(widget.bubble.slot.isVisible) host \(widget.bubble.host != nil) key \(window.isKeyWindow)")
        }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] where scenario.clicks {
            if let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                NSApp.sendEvent(event)
            }
        }
        if scenario.inserts, scenario.clicks {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(ProcessInfo.processInfo.environment["LAB_INSERT_DELAY"] ?? "") ?? 0.12)) {
                let id = 100 + self.attempts
                guard self.table.item(stableId: AnyHashable(id)) == nil else {
                    return
                }
                self.table.merge(with: TableUpdateTransition(deleted: [], inserted: [(0, RealItem(id: id, height: 64))], updated: [], animated: false, state: .none(nil)))
            }
        }
        var samples: [(Double, CGFloat?)] = []
        let start = CACurrentMediaTime()
        clickStart = start
        let interval = Double(ProcessInfo.processInfo.environment["LAB_INTERVAL"] ?? "") ?? (1.0 / 120.0)
        let background = ProcessInfo.processInfo.environment["LAB_MAIN_CAPTURE"] == nil
        let lock = NSLock()
        var backgroundSamples: [(Double, CGFloat?)] = []
        var sampling = true
        if background, let capture = capture {
            let windowNumber = UInt32(window.windowNumber)
            let width = window.frame.width
            let titlebar = window.frame.height - window.contentLayoutRect.height
            Thread.detachNewThread {
                while true {
                    lock.lock()
                    let running = sampling
                    lock.unlock()
                    if !running {
                        break
                    }
                    let t = CACurrentMediaTime() - start
                    var found: CGFloat?
                    if let image = capture(.null, 8, windowNumber, 1 | 8)?.takeRetainedValue(), let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) {
                        if let dir = ProcessInfo.processInfo.environment["LAB_BGFRAMES"], t < (Double(ProcessInfo.processInfo.environment["LAB_BGFRAMES_UNTIL"] ?? "") ?? 0.03), let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir + String(format: "/b%03d.png", Int(t * 1000))) as CFURL, "public.png" as CFString, 1, nil) {
                            CGImageDestinationAddImage(dest, image, nil)
                            CGImageDestinationFinalize(dest)
                        }
                        let scale = CGFloat(image.width) / width
                        let x = Int(150 * scale)
                        var below: CGFloat = -1
                        var greenTop: CGFloat = -1
                        let belowId = scenario.widget - 1
                        for row in 0 ..< image.height {
                            let pixel = bytes + row * image.bytesPerRow + x * 4
                            if found == nil, Int(pixel[2]) > 200, Int(pixel[1]) < 100, Int(pixel[0]) > 200 {
                                found = CGFloat(row) / scale - titlebar
                            }
                            if greenTop < 0, Int(pixel[2]) > 190, Int(pixel[2]) < 220, Int(pixel[1]) > 230, Int(pixel[0]) > 190, Int(pixel[0]) < 215 {
                                greenTop = CGFloat(row) / scale - titlebar
                            }
                            if below < 0, belowId >= 0, Int(pixel[2]) < 40, Int(pixel[0]) > 200, abs(Int(pixel[1]) - belowId * 10) <= 3, found != nil {
                                below = CGFloat(row) / scale - titlebar
                            }
                        }
                        if ProcessInfo.processInfo.environment["LAB_PARTS"] != nil {
                            print(String(format: "PART %.4f t %.3f button %.1f below %.1f %@", start + t, t, found ?? -1, below, widget.renderer?.alignmentDebug ?? "-"))
                        }
                    }
                    lock.lock()
                    backgroundSamples.append((t, found))
                    lock.unlock()
                    Thread.sleep(forTimeInterval: interval)
                }
            }
        }
        if ProcessInfo.processInfo.environment["LAB_TILES"] != nil {
            var ticks = 0
            let debug = Timer(timeInterval: 0.01, repeats: true) { debug in
                ticks += 1
                if let view = self.table.viewNecessary(at: scenario.widget) as? RealRowView {
                    let host = view.container.subviews.first
                    _ = host
                    if let layer = view.clip.layer, let anim = layer.animation(forKey: "bounds") as? CABasicAnimation {
                        print("    pres \(NSStringFromRect(layer.presentation()?.bounds ?? .zero)) pos \(layer.presentation()?.position ?? .zero) anchor \(layer.anchorPoint) from \(String(describing: anim.fromValue)) to \(String(describing: anim.toValue)) begin \(anim.beginTime - CACurrentMediaTime()) dur \(anim.duration) speed \(anim.speed) rowPres \(view.layer?.presentation()?.frame ?? .zero) row \(view.frame)")
                    }
                    print(String(format: "  t %.3f clip %@ clipAnims [%@] containerAnims [%@] rowAnims [%@]", CACurrentMediaTime() - start, NSStringFromRect(view.clip.frame), (view.clip.layer?.animationKeys() ?? []).joined(separator: ","), (view.container.layer?.animationKeys() ?? []).joined(separator: ","), (view.layer?.animationKeys() ?? []).joined(separator: ",")))
                }
                if ticks > 14 { debug.invalidate() }
            }
            RunLoop.main.add(debug, forMode: .common)
        }
        let timer = Timer(timeInterval: background ? 0.05 : interval, repeats: true) { timer in
            let t = CACurrentMediaTime() - start
            if background {
                lock.lock()
                samples = backgroundSamples
                lock.unlock()
            } else {
                samples.append((t, self.targetY()))
            }
            if ProcessInfo.processInfo.environment["LAB_ROWS"] != nil, t < 0.25 {
                print(String(format: "  t %.3f target %.1f above %.1f below %.1f layouts %d draws %d", t, self.targetY() ?? -1, self.rowTop(scenario.widget + 1) ?? -1, self.rowTop(scenario.widget - 1) ?? -1, widget.renderer?.layoutCount ?? -1, widget.renderer?.drawCount ?? -1))
            }
            if t > 0.35, abs(widget.bubble.height - initialHeight) < 0.5, self.attempts < 4 {
                timer.invalidate()
                lock.lock()
                sampling = false
                lock.unlock()
                self.attempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.click(scenario, widget)
                }
                return
            }
            if t > 1.3 {
                timer.invalidate()
                lock.lock()
                sampling = false
                lock.unlock()
                self.attempts = 0
                if abs(widget.bubble.height - initialHeight) < 0.5 {
                    print("NOCLICK \(scenario.name)")
                    self.failures += 1
                } else {
                    self.report(scenario, before: before, samples: samples, widget: widget)
                }
                self.run()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func report(_ scenario: Scenario, before: CGFloat, samples: [(Double, CGFloat?)], widget: Widget) {
        let values = samples.compactMap { $0.1 }
        let drift = values.map { scenario.inserts ? min(abs($0 - before), abs($0 - before + 64)) : abs($0 - before) }.max() ?? .infinity
        let final = values.last.map { scenario.inserts ? $0 - before + 64 : $0 - before } ?? .infinity
        var flash: CGFloat = 0
        for (a, b) in zip(values, values.dropFirst()) {
            flash = max(flash, abs(b - a))
        }
        let resized = widget.bubble.height
        let ok = drift <= 1.5 && values.count > 10
        if !ok {
            failures += 1
        }
        let trace = ProcessInfo.processInfo.environment["LAB_TRACE"].map { scenario.name.contains($0) } == true ? " trace " + samples.prefix(90).map { String(format: "%.0f@%.3f", ($0.1 ?? -999) - before, $0.0) }.joined(separator: " ") : ""
        print(String(format: "%@ %@ drift %.1f final %.1f maxStep %.1f height %.0f frames %d%@", ok ? "OK  " : "FAIL", scenario.name.padding(toLength: 40, withPad: " ", startingAt: 0), drift, final, flash, resized, values.count, trace))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
System.updateScaleFactor(2)
var retainedImages: [NSImage] = []
for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.black.setFill()
        rect.insetBy(dx: 4, dy: 4).fill()
        return true
    }
    _ = image.setName(name)
    retainedImages.append(image)
}
_ = Click.monitor
let mode = CommandLine.arguments.dropFirst().first ?? "diff"
let lab = Lab(mode: mode)
DispatchQueue.main.async {
    app.activate(ignoringOtherApps: true)
    lab.run()
}
app.run()

extension LiteHTMLWidgetRenderer: ScheduledRenderer {}

extension LiteHTMLWidgetRenderer: Renderer {
    public func evaluate(_ script: String, completion: @escaping (String?) -> Void) {
        completion(nil)
    }

    public func snapshot(completion: @escaping (NSImage?) -> Void) {
        completion(snapshot())
    }
}
