import Cocoa
import WidgetSandbox
import TwidgetRenderer
import WidgetSandboxProtocol

var feedTrustOcclusion = false

func feedWindowVisible(_ window: NSWindow) -> Bool {
    return feedTrustOcclusion ? window.occlusionState.contains(.visible) : window.isVisible
}

class FeedFlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class BaselineItem {
    let name: String
    let html: String
    var host: WidgetHost?
    var renderer: LiteHTMLWidgetRenderer?
    var visible = false
    var height: CGFloat = 0
    var hasContent = false
    var observers: [Int: () -> Void] = [:]
    var nextObserver = 0
    static var live = 0
    static var createMs: [Double] = []

    init(name: String, html: String) {
        self.name = name
        self.html = html
    }

    func size(width: CGFloat) -> NSSize {
        return NSSize(width: width, height: max(height, 60))
    }

    func host(width: CGFloat) -> WidgetHost? {
        if let host { return host }
        let t0 = CACurrentMediaTime()
        var made: LiteHTMLWidgetRenderer?
        guard let host = try? WidgetHost(html: html, theme: "light", width: width, options: labOptions(), rendererFactory: { [weak self] _, theme, width in
            let renderer = LiteHTMLWidgetRenderer(theme: theme, width: width)
            made = renderer
            let timed = TimedRenderer(renderer) { self?.visible ?? false }
            timed.name = self?.name ?? ""
            return timed
        }) else { return nil }
        renderer = made
        host.onChange = { [weak self] d in self?.changed(height: d.height, hasContent: d.firstContentMs != nil) }
        self.host = host
        BaselineItem.live += 1
        BaselineItem.createMs.append((CACurrentMediaTime() - t0) * 1000)
        FeedSpikes.createTotal += (CACurrentMediaTime() - t0) * 1000
        return host
    }

    private func changed(height: CGFloat, hasContent: Bool) {
        let changed = height > 0 && abs(height - self.height) > 0.5
        if changed {
            self.height = height
            observers.values.forEach { $0() }
        }
        if hasContent { self.hasContent = true }
    }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        host?.setVisible(visible)
        renderer?.setVisible(visible)
    }
}

final class BaselineBubbleView: NSView {
    private(set) var item: BaselineItem?
    private var observer: Int?
    private let container = FeedFlippedView(frame: .zero)
    private var attached: NSView?
    private var width: CGFloat = 0
    private var lastVisible = false
    private var recheckScheduled = false
    var onContentChanged: ((NSSize) -> Void)?

    override var isFlipped: Bool { true }

    func update(item: BaselineItem, width: CGFloat) {
        if self.item !== item {
            detach()
            self.item = item
            observer = { item.nextObserver += 1; item.observers[item.nextObserver] = { [weak self] in self?.reportSize() }; return item.nextObserver }()
        }
        self.width = width
        attach()
        updateVisibility(force: true)
    }

    private func detach() {
        if let item, let observer { item.observers.removeValue(forKey: observer) }
        observer = nil
        item = nil
        if let attached, attached.superview === self {
            attached.removeFromSuperview()
            container.subviews.forEach { $0.removeFromSuperview() }
        }
        attached = nil
    }

    private func attach() {
        guard let item, let host = item.host(width: width) else { return }
        if container.superview !== self { addSubview(container) }
        container.frame = bounds
        if host.view.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            container.addSubview(host.view)
        }
        host.view.frame = container.bounds
        host.view.autoresizingMask = [.width, .height]
        attached = container
        reportSize()
    }

    private func reportSize() {
        guard let item else { return }
        let size = item.size(width: width)
        if size != frame.size { onContentChanged?(size) }
    }

    var isBubbleVisible: Bool {
        guard let window, feedWindowVisible(window) else { return false }
        if let clip = enclosingScrollView?.contentView {
            return bounds.intersects(convert(clip.bounds, from: clip))
        }
        return !visibleRect.isEmpty
    }

    private func updateVisibility(force: Bool) {
        let visible = isBubbleVisible
        if !visible, window != nil, !recheckScheduled {
            recheckScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.recheckScheduled = false
                if self.isBubbleVisible { self.updateVisibility(force: false) }
            }
        }
        if force || visible != lastVisible {
            lastVisible = visible
            item?.setVisible(visible)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(visibilityNotification(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: window)
            if let clip = enclosingScrollView?.contentView {
                NotificationCenter.default.addObserver(self, selector: #selector(visibilityNotification(_:)), name: NSView.boundsDidChangeNotification, object: clip)
                if let document = clip.documentView {
                    NotificationCenter.default.addObserver(self, selector: #selector(visibilityNotification(_:)), name: NSView.frameDidChangeNotification, object: document)
                }
            }
        }
        updateVisibility(force: true)
    }

    @objc private func visibilityNotification(_ notification: Notification) {
        updateVisibility(force: false)
    }

    override func layout() {
        super.layout()
        attached?.frame = bounds
        updateVisibility(force: false)
    }
}

final class TimedRenderer: Renderer, ScheduledRenderer {
    var schedule: (@escaping () -> Void) -> Void {
        get { (inner as? ScheduledRenderer)?.schedule ?? { DispatchQueue.main.async(execute: $0) } }
        set { (inner as? ScheduledRenderer)?.schedule = newValue }
    }
    var scheduleAfter: (TimeInterval, @escaping () -> Void) -> Void {
        get { (inner as? ScheduledRenderer)?.scheduleAfter ?? { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) } }
        set { (inner as? ScheduledRenderer)?.scheduleAfter = newValue }
    }
    var isOnExecutor: () -> Bool {
        get { (inner as? ScheduledRenderer)?.isOnExecutor ?? { Thread.isMainThread } }
        set { (inner as? ScheduledRenderer)?.isOnExecutor = newValue }
    }
    var scheduleUrgent: (@escaping () -> Void) -> Void {
        get { (inner as? ScheduledRenderer)?.scheduleUrgent ?? { DispatchQueue.main.async(execute: $0) } }
        set { (inner as? ScheduledRenderer)?.scheduleUrgent = newValue }
    }
    var executorIsMain: () -> Bool {
        get { (inner as? ScheduledRenderer)?.executorIsMain ?? { true } }
        set { (inner as? ScheduledRenderer)?.executorIsMain = newValue }
    }
    static var sendMs: (visible: Double, hidden: Double, visibleCount: Int, hiddenCount: Int) = (0, 0, 0, 0)
    let inner: Renderer
    let isVisible: () -> Bool
    var name = ""
    var onMessage: ((String) -> Void)? { didSet { inner.onMessage = onMessage } }
    var onDiag: ((String, String) -> Void)? { didSet { inner.onDiag = onDiag } }
    var view: NSView { inner.view }

    init(_ inner: Renderer, isVisible: @escaping () -> Bool) {
        self.inner = inner
        self.isVisible = isVisible
    }

    func load() { inner.load() }
    func send(_ json: String) {
        let t0 = CACurrentMediaTime()
        inner.send(json)
        record((CACurrentMediaTime() - t0) * 1000)
    }
    static var typed = true
    var acceptsTypedOps: Bool { TimedRenderer.typed && inner.acceptsTypedOps }
    func send(ops: [WidgetOp]) {
        let t0 = CACurrentMediaTime()
        inner.send(ops: ops)
        record((CACurrentMediaTime() - t0) * 1000)
    }
    private var sends = 0
    static var firstSendMs = 0.0
    static var laterSendMs = 0.0
    static let bgLock = NSLock()
    static var bgSendMs = 0.0
    private func record(_ ms: Double) {
        guard Thread.isMainThread else {
            TimedRenderer.bgLock.lock()
            TimedRenderer.bgSendMs += ms
            TimedRenderer.bgLock.unlock()
            return
        }
        sends += 1
        if sends <= 2 { TimedRenderer.firstSendMs += ms } else { TimedRenderer.laterSendMs += ms }
        if ms > FeedSpikes.worstSend.ms { FeedSpikes.worstSend = (name, ms) }
        FeedSpikes.sendTotal += ms
        if isVisible() {
            TimedRenderer.sendMs.visible += ms
            TimedRenderer.sendMs.visibleCount += 1
        } else {
            TimedRenderer.sendMs.hidden += ms
            TimedRenderer.sendMs.hiddenCount += 1
        }
    }
    func setTheme(_ theme: String) { inner.setTheme(theme) }
    func evaluate(_ script: String, completion: @escaping (String?) -> Void) { inner.evaluate(script, completion: completion) }
    func snapshot(completion: @escaping (NSImage?) -> Void) { inner.snapshot(completion: completion) }
    func destroy() { inner.destroy() }
}

func feedTileLayers(_ layer: CALayer) -> [CALayer] {
    CATransaction.lock()
    defer { CATransaction.unlock() }
    return (layer.sublayers ?? []).flatMap { $0.delegate == nil ? ($0.sublayers ?? []) : [$0] }
}

func feedTileBytes(_ view: NSView) -> Int {
    let scale = view.window?.backingScaleFactor ?? 2
    return view.layer.map(feedTileLayers)?.filter { $0.delegate != nil && !($0.delegate is NSView) && $0.contents != nil }.reduce(0) { $0 + Int($1.bounds.width * scale) * Int($1.bounds.height * scale) * 4 } ?? 0
}

func feedTopRenderers(_ list: [(String, LiteHTMLWidgetRenderer)]) -> String {
    let layout = list.sorted { $0.1.layoutMaxMilliseconds > $1.1.layoutMaxMilliseconds }.prefix(5).map { String(format: "%@ %.1f", $0.0, $0.1.layoutMaxMilliseconds) }
    let draw = list.sorted { $0.1.drawMaxMilliseconds > $1.1.drawMaxMilliseconds }.prefix(5).map { String(format: "%@ %.1f", $0.0, $0.1.drawMaxMilliseconds) }
    TimedRenderer.bgLock.lock()
    let bgSendMs = TimedRenderer.bgSendMs
    TimedRenderer.bgLock.unlock()
    return "top layout max: " + layout.joined(separator: ", ") + "\ntop draw max: " + draw.joined(separator: ", ") + String(format: "\nrenderer send ms: visible %.0f (%d) hidden %.0f (%d) first-two %.0f later %.0f off-main %.0f", TimedRenderer.sendMs.visible, TimedRenderer.sendMs.visibleCount, TimedRenderer.sendMs.hidden, TimedRenderer.sendMs.hiddenCount, TimedRenderer.firstSendMs, TimedRenderer.laterSendMs, bgSendMs)
}

enum FeedSpikes {
    static var worstSend: (name: String, ms: Double) = ("", 0)
    static var sendTotal = 0.0
    static var createTotal = 0.0
    static var log: [String] = []

    static var threshold = 25.0
    static var commitMs = 0.0
    static var tickMs = 0.0
    static var buckets: [String: (count: Int, ms: Double)] = [:]

    static var attaches = 0
    static var attachedLayers = 0
    static var attachedAnimations = 0
    static var attachedKeyframes = 0
    static var attachedSurfaces = 0
    static var imageLog: [String] = []
    static var attachFrames = 0
    static var previousAttached = false
    static var slowAttachFrames = 0
    static var slowFrames = 0
    static var slowCommitAttachMs: [Double] = []
    static var slowCommitNoAttachMs: [Double] = []

    static func noteAttach(_ view: NSView) {
        attaches += 1
        CATransaction.lock()
        var count = 0
        var stack = view.layer.map { [$0] } ?? []
        while let layer = stack.popLast() {
            count += 1
            for key in layer.animationKeys() ?? [] {
                attachedAnimations += 1
                if let k = layer.animation(forKey: key) as? CAKeyframeAnimation { attachedKeyframes += k.values?.count ?? 0 }
                if let g = layer.animation(forKey: key) as? CAAnimationGroup { attachedKeyframes += (g.animations ?? []).reduce(0) { $0 + (($1 as? CAKeyframeAnimation)?.values?.count ?? 0) } }
            }
            if let contents = layer.contents, CFGetTypeID(contents as CFTypeRef) == IOSurfaceGetTypeID() { attachedSurfaces += 1 }
            if let contents = layer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID, imageLog.count < 4000 {
                let image = contents as! CGImage
                var chain: [String] = []
                var up: CALayer? = layer.superlayer
                while let l = up, chain.count < 6 {
                    chain.append((l.delegate.map { String(describing: type(of: $0)) }) ?? (l.name ?? String(describing: type(of: l))))
                    up = l.superlayer
                }
                let windowSpace = view.window?.colorSpace?.cgColorSpace
                let same = windowSpace.map { image.colorSpace == $0 } ?? false
                imageLog.append("\(image.width)x\(image.height) space=\(image.colorSpace?.name.map { $0 as String } ?? (image.colorSpace.map { "\($0.model.rawValue)-unnamed" } ?? "nil")) matchesWindow=\(same) fmt=\(layer.contentsFormat.rawValue) cls=\(type(of: layer)) delegate=\(layer.delegate.map { String(describing: type(of: $0)) } ?? "-") name=\(layer.name ?? "-") chain=\(chain.joined(separator: "<")) site=\(ContentsTrace.site(layer))")
            }
            stack.append(contentsOf: layer.sublayers ?? [])
        }
        CATransaction.unlock()
        attachedLayers += count
    }

    static var attachSummary: String {
        func stats(_ v: [Double]) -> String { v.isEmpty ? "-" : String(format: "n=%d avg=%.1f max=%.1f", v.count, v.reduce(0, +) / Double(v.count), v.max()!) }
        return "attach frames=\(attachFrames) slow=\(slowFrames) slow-with-attach=\(slowAttachFrames) commit>8.3 with attach: \(stats(slowCommitAttachMs)) without: \(stats(slowCommitNoAttachMs))"
    }

    static func frame(busyMs: Double, phase: String) {
        let attached = attaches > 0 || previousAttached
        previousAttached = attaches > 0
        if attached { attachFrames += 1 }
        if busyMs > 8.3 {
            slowFrames += 1
            if attached { slowAttachFrames += 1 }
            if commitMs > 8.3 { if attached { slowCommitAttachMs.append(commitMs) } else { slowCommitNoAttachMs.append(commitMs) } }
        }
        if busyMs > 8.3 {
            let parts = [("commit", commitMs), ("sends", sendTotal), ("creates", createTotal), ("feed", tickMs)]
            let top = parts.max { $0.1 < $1.1 }!
            let key = busyMs - parts.reduce(0) { $0 + $1.1 } > top.1 ? "other" : top.0
            var b = buckets[key] ?? (0, 0)
            b.count += 1
            b.ms += busyMs
            buckets[key] = b
        }
        if busyMs > threshold, log.count < 40 {
            log.append(String(format: "%@ busy=%.1f commit=%.1f sends=%.1f worst=%@ %.1f creates=%.1f feed=%.1f attaches=%d layers=%d anims=%d keyframes=%d surfaces=%d", phase, busyMs, commitMs, sendTotal, worstSend.name, worstSend.ms, createTotal, tickMs, attaches, attachedLayers, attachedAnimations, attachedKeyframes, attachedSurfaces))
        }
        attaches = 0
        attachedLayers = 0
        attachedAnimations = 0
        attachedKeyframes = 0
        attachedSurfaces = 0
        commitMs = 0
        tickMs = 0
        worstSend = ("", 0)
        sendTotal = 0
        createTotal = 0
    }
}


enum ContentsTrace {
    static let lock = NSLock()
    static var sites: [ObjectIdentifier: String] = [:]

    static func site(_ layer: CALayer) -> String {
        lock.lock()
        defer { lock.unlock() }
        return sites[ObjectIdentifier(layer)] ?? "?"
    }

    static func install() {
        let cls: AnyClass = CALayer.self
        let selector = #selector(setter: CALayer.contents)
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Setter.self)
        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { this, value in
            if let value = value, CFGetTypeID(value as CFTypeRef) == CGImage.typeID, let layer = this as? CALayer {
                let frames = Thread.callStackSymbols.dropFirst(1).filter { $0.contains("TwidgetLab") && !$0.contains("ContentsTrace") }.prefix(3).map { line -> String in
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    return parts.count > 3 ? String(parts[3]) : line
                }
                let demangled = frames.map { name -> String in
                    if let d = swiftDemangle(name) { return String(d.prefix(110)) }
                    return name
                }
                lock.lock()
                sites[ObjectIdentifier(layer)] = demangled.joined(separator: " <- ")
                lock.unlock()
            }
            original(this, selector, value)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private static func swiftDemangle(_ name: String) -> String? {
        typealias Fn = @convention(c) (UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UInt32) -> UnsafeMutablePointer<CChar>?
        guard let handle = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_demangle") else { return nil }
        let fn = unsafeBitCast(handle, to: Fn.self)
        guard let out = name.withCString({ fn($0, strlen($0), nil, nil, 0) }) else { return nil }
        defer { free(out) }
        return String(cString: out)
    }
}
