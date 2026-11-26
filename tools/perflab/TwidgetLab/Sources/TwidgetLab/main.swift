import Cocoa
import CryptoKit
import Darwin
import WebKit
import WidgetSandbox
import TwidgetRenderer
import LiteHTML
import WidgetSandboxProtocol

extension LiteHTMLWidgetRenderer: Renderer {
    public func evaluate(_ script: String, completion: @escaping (String?) -> Void) {
        completion(nil)
    }

    public func snapshot(completion: @escaping (NSImage?) -> Void) {
        completion(snapshot())
    }
}

extension LiteHTMLWidgetRenderer: SurfaceHostingRenderer {}
extension LiteHTMLWidgetRenderer: ScheduledRenderer {}

final class RecordingRenderer: Renderer, SurfaceHostingRenderer {
    var surfaceLayer: ((String) -> CALayer?)? {
        get { (inner as? SurfaceHostingRenderer)?.surfaceLayer }
        set { (inner as? SurfaceHostingRenderer)?.surfaceLayer = newValue }
    }
    var surfaceLayout: ((String, CGSize, CGFloat, Bool) -> Void)? {
        get { (inner as? SurfaceHostingRenderer)?.surfaceLayout }
        set { (inner as? SurfaceHostingRenderer)?.surfaceLayout = newValue }
    }
    let inner: Renderer
    let recordsTraffic: Bool
    var log: [String] = []
    private(set) var messageCount = 0
    var onMessage: ((String) -> Void)? {
        didSet {
            inner.onMessage = { [weak self] json in
                self?.messageCount += 1
                if self?.recordsTraffic == true { self?.log.append("< " + json) }
                self?.onMessage?(json)
            }
        }
    }
    var onDiag: ((String, String) -> Void)? {
        didSet { inner.onDiag = onDiag }
    }
    var view: NSView { inner.view }

    init(_ inner: Renderer, recordsTraffic: Bool = false) {
        self.inner = inner
        self.recordsTraffic = recordsTraffic
    }

    func load() { inner.load() }
    func send(_ json: String) {
        messageCount += 1
        if recordsTraffic { log.append("> " + json) }
        inner.send(json)
    }
    var acceptsTypedOps: Bool { inner.acceptsTypedOps }
    func send(ops: [WidgetOp]) {
        messageCount += 1
        if recordsTraffic { log.append("> {\"type\":\"ops\"} typed \(ops.count)") }
        inner.send(ops: ops)
    }
    func setTheme(_ theme: String) { inner.setTheme(theme) }
    func evaluate(_ script: String, completion: @escaping (String?) -> Void) { inner.evaluate(script, completion: completion) }
    func snapshot(completion: @escaping (NSImage?) -> Void) { inner.snapshot(completion: completion) }
    func destroy() { inner.destroy() }
}

final class TimingRenderer: Renderer {
    static var total = 0.0, worst = 0.0, calls = 0, worstWhat = ""
    let inner: Renderer
    var onMessage: ((String) -> Void)? {
        didSet {
            inner.onMessage = { [weak self] json in
                let t0 = CACurrentMediaTime()
                self?.onMessage?(json)
                TimingRenderer.note(t0, "host<" + String(json.prefix(24)))
            }
        }
    }
    var onDiag: ((String, String) -> Void)? { didSet { inner.onDiag = onDiag } }
    var view: NSView { inner.view }
    init(_ inner: Renderer) { self.inner = inner }
    static func note(_ t0: CFTimeInterval, _ what: String) {
        let dt = (CACurrentMediaTime() - t0) * 1000
        total += dt
        calls += 1
        if dt > worst { worst = dt; worstWhat = what }
    }
    func load() { let t0 = CACurrentMediaTime(); inner.load(); Self.note(t0, "load") }
    func send(_ json: String) { let t0 = CACurrentMediaTime(); inner.send(json); Self.note(t0, String(json.prefix(30))) }
    var acceptsTypedOps: Bool { inner.acceptsTypedOps }
    func send(ops: [WidgetOp]) { let t0 = CACurrentMediaTime(); inner.send(ops: ops); Self.note(t0, "ops \(ops.count)") }
    func setTheme(_ theme: String) { inner.setTheme(theme) }
    func evaluate(_ script: String, completion: @escaping (String?) -> Void) { inner.evaluate(script, completion: completion) }
    func destroy() { inner.destroy() }
}

typealias ResponsibleFunction = @convention(c) (pid_t) -> pid_t
let responsibleFor: ResponsibleFunction? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
    return unsafeBitCast(symbol, to: ResponsibleFunction.self)
}()

func cpuSeconds(of pid: pid_t) -> Double {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    guard result == 0 else { return 0 }
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return Double(info.ri_user_time + info.ri_system_time) * Double(timebase.numer) / Double(timebase.denom) / 1e9
}

func webKitProcesses() -> Set<pid_t> {
    var pids = [pid_t](repeating: 0, count: 8192)
    let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    var result: Set<pid_t> = []
    for pid in pids.prefix(Int(max(0, count))) where pid > 0 {
        var path = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0, String(cString: path).contains("com.apple.WebKit.") {
            result.insert(pid)
        }
    }
    return result
}

let preexistingWebKit = webKitProcesses()

var knownHelpers: (() -> Set<pid_t>)?

func webKitHelpers(_ web: WKWebView, _ pool: WKProcessPool) -> Set<pid_t> {
    var result: Set<pid_t> = []
    for (object, key) in [(web as NSObject, "_webProcessIdentifier"), (pool as NSObject, "_gpuProcessIdentifier"), (pool as NSObject, "_networkProcessIdentifier"), (web.configuration.websiteDataStore as NSObject, "_networkProcessIdentifier")] where object.responds(to: Selector(key)) {
        if let value = (object.value(forKey: key) as? NSNumber)?.int32Value, value > 0 {
            result.insert(value)
        }
    }
    return result
}

func helperProcesses() -> [pid_t] {
    let me = getpid()
    if let known = knownHelpers {
        return Array(known())
    }
    let own = webKitProcesses().subtracting(preexistingWebKit)
    guard let responsibleFor = responsibleFor else {
        return Array(own)
    }
    return own.filter { responsibleFor($0) == me }
}

func groupCPU() -> (own: Double, helpers: Double) {
    return (cpuSeconds(of: getpid()), helperProcesses().reduce(0) { $0 + cpuSeconds(of: $1) })
}

func gpuSeconds(of pids: Set<pid_t>) -> Double {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    task.arguments = ["-r", "-d", "1", "-w0", "-c", "AGXDeviceUserClient"]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    var total = 0.0
    for block in text.components(separatedBy: "+-o ") {
        guard let range = block.range(of: "\"IOUserClientCreator\" = \"pid "), let pid = pid_t(block[range.upperBound...].prefix { $0.isNumber }), pids.contains(pid) else {
            continue
        }
        var rest = block[...]
        while let r = rest.range(of: "\"accumulatedGPUTime\"=") {
            rest = rest[r.upperBound...]
            total += Double(rest.prefix { $0.isNumber }) ?? 0
        }
    }
    return total / 1e9
}

func groupGPU() -> (own: Double, helpers: Double, windowServer: Double) {
    let helpers = Set(helperProcesses())
    return (gpuSeconds(of: [getpid()]), gpuSeconds(of: helpers), gpuSeconds(of: [pid_t(windowServerPid) ?? -1]))
}

func threadTimes() -> [String: Double] {
    var list: thread_act_array_t?
    var count: mach_msg_type_number_t = 0
    guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return [:] }
    var out: [String: Double] = [:]
    for i in 0..<Int(count) {
        let thread = list[i]
        var info = thread_basic_info()
        var n = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &n) } }
        var name = "other"
        var ident = thread_identifier_info()
        var m = mach_msg_type_number_t(MemoryLayout<thread_identifier_info>.size / MemoryLayout<natural_t>.size)
        if withUnsafeMutablePointer(to: &ident, { $0.withMemoryRebound(to: integer_t.self, capacity: Int(m)) { thread_info(thread, thread_flavor_t(THREAD_IDENTIFIER_INFO), $0, &m) } }) == KERN_SUCCESS {
            var tinfo = proc_threadinfo()
            if proc_pidinfo(getpid(), PROC_PIDTHREADID64INFO, ident.thread_id, &tinfo, Int32(MemoryLayout<proc_threadinfo>.size)) > 0 {
                let raw = withUnsafeBytes(of: tinfo.pth_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                if !raw.isEmpty { name = raw.hasPrefix("widget.validator") ? "widget.validator" : raw }
            }
            if ident.thread_handle != 0, Thread.isMainThread, i == 0 { name = "main" }
        }
        if kr == KERN_SUCCESS {
            out[name, default: 0] += Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1e6 + Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1e6
        }
        mach_port_deallocate(mach_task_self_, thread)
    }
    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: list), vm_size_t(Int(count) * MemoryLayout<thread_t>.size))
    return out
}

func threadDelta(_ a: [String: Double], _ b: [String: Double], frames: Int) -> String {
    let keys = Set(a.keys).union(b.keys)
    return keys.map { ($0, (b[$0] ?? 0) - (a[$0] ?? 0)) }.filter { $0.1 > 0.0005 }.sorted { $0.1 > $1.1 }.map { String(format: "%@ %.3f", $0.0, $0.1 * 1000 / Double(max(1, frames))) }.joined(separator: "  ")
}

func footprintBytes(of pid: pid_t) -> Double {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
    }
    return result == 0 ? Double(info.ri_phys_footprint) : 0
}

func groupFootprint() -> (own: Double, helpers: Double, count: Int) {
    let helpers = helperProcesses()
    return (footprintBytes(of: getpid()), helpers.reduce(0) { $0 + footprintBytes(of: $1) }, helpers.count)
}

let windowServerPid: String = {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", "WindowServer"]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    task.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}()

func windowServerSeconds() -> Double {
    guard !windowServerPid.isEmpty else { return 0 }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/ps")
    task.arguments = ["-o", "time=", "-p", windowServerPid]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    task.waitUntilExit()
    let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var seconds = 0.0
    for part in text.split(separator: ":") {
        seconds = seconds * 60 + (Double(part) ?? 0)
    }
    return seconds
}

func maxHostOptions() -> WidgetHost.Options {
    var options = labOptions()
    let flags = (option("--host-flags") ?? "shared,pools,parallel,async").split(separator: ",")
    options.sharedWebKit = flags.contains("shared")
    options.pools = flags.contains("pools")
    options.parallelBoot = flags.contains("parallel")
    options.asyncValidation = flags.contains("async")
    return options
}

func prewarmMaxHost(width: CGFloat, renderers: Int, engines: Int) {
    RendererWebView.transport = .callAsync
    var environmentReady = renderers == 0
    if renderers > 0 {
        RendererEnvironment.shared.prewarm { environmentReady = true }
    }
    WidgetWarmup.prewarm(renderers: renderers, engines: engines, validators: engines, width: width)
    if renderers == 0 {
        let warm = LiteHTMLWidgetRenderer(theme: "light", width: width)
        warm.onMessage = { _ in }
        warm.load()
        warm.destroy()
    }
    let deadline = Date().addingTimeInterval(30)
    while (!environmentReady || RendererPool.shared.count < renderers || EnginePool.shared.count < engines) && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
}

func disableWebKitOcclusion(_ view: NSView) {
    if let web = view as? WKWebView {
        let selector = Selector(("_setWindowOcclusionDetectionEnabled:"))
        if web.responds(to: selector), let method = class_getInstanceMethod(type(of: web), selector) {
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(method_getImplementation(method), to: Setter.self)(web, selector, false)
        }
    }
    view.subviews.forEach(disableWebKitOcclusion)
}

func megabytes(_ bytes: Double) -> String {
    String(format: "%.1f", bytes / 1048576)
}

func dumpLayers(_ layer: CALayer, _ depth: Int) {
    var line = String(repeating: "  ", count: depth) + "\(type(of: layer)) frame=\(layer.frame) z=\(layer.zPosition) cs=\(layer.contentsScale) opaque=\(layer.isOpaque) hasContents=\(layer.contents != nil) masks=\(layer.masksToBounds) mask=\(layer.mask != nil) filters=\(layer.filters?.count ?? 0) minF=\(layer.minificationFilter.rawValue) magF=\(layer.magnificationFilter.rawValue) aa=\(layer.allowsEdgeAntialiasing) gopac=\(layer.allowsGroupOpacity) raster=\(layer.shouldRasterize) fmt=\(layer.contentsFormat.rawValue) bg=\(layer.backgroundColor != nil) cr=\(layer.cornerRadius) hidden=\(layer.isHidden) op=\(layer.opacity)"
    if let contents = layer.contents {
        let cf = contents as CFTypeRef
        if CFGetTypeID(cf) == CGImage.typeID {
            let image = contents as! CGImage
            line += " img=\(image.width)x\(image.height) bpc=\(image.bitsPerComponent) space=\(image.colorSpace?.name as String? ?? "-")"
        } else {
            line += " contents=\(type(of: contents))"
        }
    }
    print(line)
    for key in layer.animationKeys() ?? [] {
        guard let animation = layer.animation(forKey: key) else { continue }
        var extra = ""
        if #available(macOS 12.0, *) {
            let r = animation.preferredFrameRateRange
            extra = " fps=\(r.minimum)-\(r.maximum)/\(r.preferred ?? -1)"
        }
        if let k = animation as? CAKeyframeAnimation {
            extra += " keyframes=\(k.values?.count ?? 0) calc=\(k.calculationMode.rawValue) path=\(k.keyPath ?? "")"
        } else if let b = animation as? CABasicAnimation {
            extra += " basic path=\(b.keyPath ?? "") timing=\(String(describing: b.timingFunction))"
        } else if let g = animation as? CAAnimationGroup {
            extra += " group=\(g.animations?.count ?? 0) \(g.animations?.map { "\(type(of: $0)):\(($0 as? CAPropertyAnimation)?.keyPath ?? "")" } ?? [])"
        }
        print(String(repeating: "  ", count: depth) + "  ANIM \(key) \(type(of: animation)) dur=\(animation.duration) repeat=\(animation.repeatCount) fill=\(animation.fillMode.rawValue) removed=\(animation.isRemovedOnCompletion)" + extra)
    }
    for sub in layer.sublayers ?? [] {
        dumpLayers(sub, depth + 1)
    }
}

func savePNG(_ image: NSImage, _ path: String) {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
}

let args = CommandLine.arguments.count == 1 && Bundle.main.url(forResource: "widget", withExtension: "html") != nil
    ? [CommandLine.arguments[0], "interactive", Bundle.main.url(forResource: "widget", withExtension: "html")!.path]
    : CommandLine.arguments
setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IONBF, 0)
for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
    signal(sig) { code in
        let header = "\nLAB CRASH signal \(code)\n"
        header.withCString { _ = write(2, $0, strlen($0)) }
        var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
        let count = backtrace(&frames, Int32(frames.count))
        backtrace_symbols_fd(&frames, count, 2)
        signal(code, SIG_DFL)
        raise(code)
    }
}
if ProcessInfo.processInfo.environment["LAB_EXIT_HOLD"] != nil {
    atexit { sleep(5) }
}
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.finishLaunching()

switch args.count > 1 ? args[1] : "" {
case "interactive":
    runInteractiveLab()
case "capture":
    let file = args[2]
    let out = option("--out") ?? "out"
    let width = CGFloat(Double(option("--width") ?? "400") ?? 400)
    let fixedHeight = option("--height").flatMap(Double.init).map { CGFloat(max(1, $0)) }
    let seconds = Double(option("--seconds") ?? "2") ?? 2
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    let html = try! String(contentsOfFile: file)
    var recorder: RecordingRenderer?
    var lite: LiteHTMLWidgetRenderer?
    let maxHost = option("--host") == "max"
    let footprintStart = groupFootprint()
    if maxHost {
        prewarmMaxHost(width: width, renderers: option("--renderer") == "lite" ? 0 : 1, engines: 1)
    }
    if let wait = option("--pre-wait").flatMap(Double.init) {
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
    }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
    window.alphaValue = args.contains("--visible") ? 1 : 0.02
    if let at = option("--at") {
        let xy = at.split(separator: ",").compactMap { Double($0) }
        if xy.count == 2 { window.setFrameOrigin(NSPoint(x: xy[0], y: xy[1])) }
    }
    window.ignoresMouseEvents = true
    window.level = .floating
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    let footprintBeforeHost = groupFootprint()
    let host = try! WidgetHost(html: html, theme: option("--theme") ?? "light", width: width, options: maxHost ? maxHostOptions() : labOptions(), rendererFactory: maxHost && option("--renderer") != "lite" ? nil : { resources, theme, _ in
        let inner: Renderer
        if option("--renderer") == "lite" {
            let made = LiteHTMLWidgetRenderer(theme: theme, width: width)
            if let dump = option("--dump") {
                var index = 0
                made.onSerialized = { html, reused in
                    index += 1
                    if index <= (Int(option("--dump-limit") ?? "40") ?? 40) {
                        try? html.write(toFile: dump + "/frame\(index)\(reused ? "-reused" : "").html", atomically: true, encoding: .utf8)
                    }
                }
            }
            lite = made
            inner = made
        } else {
            let web = RendererWebView(rendererBundle: resources.rendererBundle, theme: theme)
            knownHelpers = { [weak view = web.webView] in
                guard let view = view else { return [] }
                return webKitHelpers(view, view.configuration.processPool)
            }
            let selector = Selector(("_setWindowOcclusionDetectionEnabled:"))
            if web.webView.responds(to: selector), let method = class_getInstanceMethod(type(of: web.webView), selector) {
                typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
                unsafeBitCast(method_getImplementation(method), to: Setter.self)(web.webView, selector, false)
            }
            inner = web
        }
        let r = RecordingRenderer(inner, recordsTraffic: args.contains("--record-ops") || option("--click") != nil)
        recorder = r
        return r
    })
    host.view.frame = NSRect(x: 0, y: 0, width: width, height: fixedHeight ?? 300)
    if let delay = option("--show-after").flatMap(Double.init) {
        RunLoop.main.run(until: Date().addingTimeInterval(delay))
    }
    disableWebKitOcclusion(host.view)
    window.contentView?.addSubview(host.view)
    let start = Date()
    var cpuStart: (own: Double, helpers: Double)?
    var gpuStart = (own: 0.0, helpers: 0.0, windowServer: 0.0)
    var surfaceStart: [Double] = []
    var cpuStartAt = Date()
    var windowServerStart = 0.0
    var opsStart = 0
    var framesStart = 0
    var threadsStart: [String: Double] = [:]
    var tileStart = WidgetTileStats.snapshot
    var layoutStart = (count: 0, milliseconds: 0.0, pureMilliseconds: 0.0, draws: 0, drawMilliseconds: 0.0)
    let warmup = Double(option("--warmup") ?? "1") ?? 1
    while Date().timeIntervalSince(start) < seconds {
        if cpuStart == nil && Date().timeIntervalSince(start) >= warmup && args.contains("--cpu") {
            gpuStart = groupGPU()
            cpuStart = groupCPU()
            surfaceStart = (host.surfaceStats.map { [Double($0.frames), $0.gpuSeconds, $0.cpuSeconds] }.first ?? [0, 0, 0]) + [host.diagnostics.stats.jsMs, Double(host.diagnostics.stats.tasks)]
            cpuStartAt = Date()
            windowServerStart = windowServerSeconds()
            opsStart = host.diagnostics.stats.ops
            framesStart = host.frameCount
            threadsStart = threadTimes()
            tileStart = WidgetTileStats.snapshot
            if let lite = lite {
                layoutStart = (lite.layoutCount, lite.layoutMilliseconds, lite.stageMilliseconds["layout"] ?? 0, lite.drawCount, lite.drawMilliseconds)
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        host.view.frame.size.height = fixedHeight ?? max(24, host.diagnostics.height)
    }
    if let begin = cpuStart {
        let end = groupCPU()
        let elapsed = Date().timeIntervalSince(cpuStartAt)
        let windowServer = (windowServerSeconds() - windowServerStart) / elapsed * 100
        let frames = host.frameCount - framesStart
        print("threads ms/frame: " + threadDelta(threadsStart, threadTimes(), frames: frames))
        print(String(format: "steady: own %.2f%% helpers %.2f%% total %.2f%% windowserver %.2f%% over %.2fs ops %d fps %.1f cpu/frame %.3f ms", (end.own - begin.own) / elapsed * 100, (end.helpers - begin.helpers) / elapsed * 100, (end.own - begin.own + end.helpers - begin.helpers) / elapsed * 100, windowServer, elapsed, host.diagnostics.stats.ops - opsStart, Double(frames) / elapsed, frames > 0 ? (end.own - begin.own + end.helpers - begin.helpers) * 1000 / Double(frames) : 0))
        print("pool: \(WidgetSurfacePool.shared.status)")
        print(WidgetTileStats.snapshot.delta(since: tileStart, frames: Double(frames)))
        if let lite = lite {
            let count = lite.layoutCount - layoutStart.count
            let draws = lite.drawCount - layoutStart.draws
            print(String(format: "steady-layout: count %d pipeline-total %.3f ms pure-total %.3f ms draws %d draw-total %.3f ms", count, lite.layoutMilliseconds - layoutStart.milliseconds, (lite.stageMilliseconds["layout"] ?? 0) - layoutStart.pureMilliseconds, draws, lite.drawMilliseconds - layoutStart.drawMilliseconds))
            print(lite.canvasReport)
        }
        if ProcessInfo.processInfo.environment["TW_VERIFY_PREPARE"] != nil {
            print("prepare-check: \(LiteHTMLWidgetRenderer.preparedReport)")
        }
        let gpuEnd = groupGPU()
        print(String(format: "gpu: own %.2f%% helpers %.2f%% windowserver %.2f%%", (gpuEnd.own - gpuStart.own) / elapsed * 100, (gpuEnd.helpers - gpuStart.helpers) / elapsed * 100, (gpuEnd.windowServer - gpuStart.windowServer) / elapsed * 100))
        if let surface = host.surfaceStats.first {
            let frames = Double(surface.frames) - surfaceStart[0]
            print(String(format: "surface: %.1f fps, gpu %.3f ms/frame, encode cpu %.3f ms/frame, js %.3f ms/frame, tasks %.1f/frame, draws %d, triangles %d, memory %.1f MB", frames / elapsed, (surface.gpuSeconds - surfaceStart[1]) / max(1, frames) * 1000, (surface.cpuSeconds - surfaceStart[2]) / max(1, frames) * 1000, (host.diagnostics.stats.jsMs - surfaceStart[3]) / max(1, frames), (Double(host.diagnostics.stats.tasks) - surfaceStart[4]) / max(1, frames), surface.draws, surface.triangles, Double(surface.memoryBytes) / 1048576))
        }
    }
    if args.contains("--memory") {
        let end = groupFootprint()
        print("js heap \(megabytes(Double(host.diagnostics.stats.memoryBytes))) MB, 3D \(host.surfaceStats.map { megabytes(Double($0.memoryBytes)) }.joined(separator: ",")) MB")
        print("footprint: start own \(megabytes(footprintStart.own)) helpers \(megabytes(footprintStart.helpers)) | before-host own \(megabytes(footprintBeforeHost.own)) helpers \(megabytes(footprintBeforeHost.helpers)) (\(footprintBeforeHost.count) procs) | end own \(megabytes(end.own)) helpers \(megabytes(end.helpers)) (\(end.count) procs) | delta \(megabytes(end.own + end.helpers - footprintStart.own - footprintStart.helpers))")
    }
    if let hidden = option("--hidden-seconds").flatMap(Double.init), args.contains("--cpu") {
        host.setVisible(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let begin = groupCPU()
        let windowServerBegin = windowServerSeconds()
        let at = Date()
        RunLoop.main.run(until: Date().addingTimeInterval(hidden))
        let end = groupCPU()
        let elapsed = Date().timeIntervalSince(at)
        print(String(format: "hidden: own %.2f%% helpers %.2f%% total %.2f%% windowserver %.2f%% over %.2fs", (end.own - begin.own) / elapsed * 100, (end.helpers - begin.helpers) / elapsed * 100, (end.own - begin.own + end.helpers - begin.helpers) / elapsed * 100, (windowServerSeconds() - windowServerBegin) / elapsed * 100, elapsed))
        host.setVisible(true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }
    if args.contains("--dump-layers"), let root = window.contentView?.layer {
        print("window colorspace=\(window.colorSpace?.localizedName ?? "-") depth=\(window.depthLimit.rawValue)")
        dumpLayers(root, 0)
    }
    if let script = option("--eval") {
        var answered = false
        host.evaluateInRenderer(script) { value in
            print("eval: \(value)")
            answered = true
        }
        while !answered { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }
    let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent + (option("--renderer") == "lite" ? ".lite" : "")
    if args.contains("--screenshot"), let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
        savePNG(NSImage(cgImage: image, size: .zero), "\(out)/\(name).screen.png")
    }
    if args.contains("--debug") {
        print("window visible=\(window.isVisible) occlusion=\(window.occlusionState.rawValue) onScreen=\(window.screen != nil)")
        if let lite = lite {
            print("renderer pressure: escalations=\(lite.escalations) throttledUpdates=\(lite.throttledUpdates) maxPassCPUms=\(lite.passMaxCPUMilliseconds) scriptFrameCost=\(lite.scriptFrameCost) \(lite.tileDebug)")
        }
    }
    if let clicks = option("--click"), let lite = lite {
        var before = false
        lite.snapshot { image in
            if let image = image { savePNG(image, "\(out)/\(name).before.png") }
            before = true
        }
        while !before { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        let logStart = recorder!.log.count
        func click(_ pair: Substring) {
            let xy = pair.split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2 else { return }
            let view = lite.view
            let local = NSPoint(x: xy[0], y: xy[1])
            let inWindow = view.convert(local, to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
            }
        }
        let filmClicks: [Int: Substring] = Dictionary(uniqueKeysWithValues: (option("--film-click") ?? "").split(separator: ";").compactMap { entry in
            let parts = entry.split(separator: "@")
            return parts.count == 2 ? Int(parts[1]).map { ($0, parts[0]) } : nil
        })
        if let pick = option("--menu-pick").flatMap(Int.init) {
            WidgetRendererEnvironment.presentMenu = { items, anchor, _, _, completion in
                print("menu at \(anchor): " + items.enumerated().map { "\($0.offset):\($0.element.kind):\($0.element.title)\($0.element.enabled ? "" : "(off)")\($0.element.selected ? "*" : "")" }.joined(separator: " | "))
                completion(pick)
            }
        }
        for pair in clicks.split(separator: ";") {
            click(pair)
            RunLoop.main.run(until: Date().addingTimeInterval(option("--click-gap").flatMap(Double.init) ?? (option("--film") != nil ? 0.03 : 0.6)))
            host.view.frame.size.height = max(24, host.diagnostics.height)
        }
        if let typed = option("--type") {
            let editor = window.firstResponder as? NSTextView
            print("editor: \(editor.map { String(describing: type(of: $0)) } ?? "none")")
            for character in typed {
                editor?.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
                RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
                savePNG(NSImage(cgImage: image, size: .zero), "\(out)/\(name).typed.screen.png")
            }
        }
        if let film = option("--film").flatMap(Int.init) {
            for index in 0..<film {
                if let pair = filmClicks[index] {
                    click(pair)
                }
                var shot = false
                lite.snapshot { image in
                    if let image = image { savePNG(image, "\(out)/\(name).film\(index).png") }
                    shot = true
                }
                while !shot { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
                if option("--film-dump").flatMap(Int.init) == index, let root = window.contentView?.layer {
                    print("FILM DUMP \(index)")
                    dumpLayers(root, 0)
                }
                if args.contains("--film-screen"), let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
                    savePNG(NSImage(cgImage: image, size: .zero), "\(out)/\(name).film\(index).screen.png")
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            }
        }
        let after = recorder!.log[logStart...]
        let events = after.filter { $0.hasPrefix("< {\"type\":\"event\"") }.count
        let ops = after.filter { $0.hasPrefix("> {\"type\":\"ops\"") }.count
        print("interaction: \(events) events sent, \(ops) op batches back")
    }
    if let dir = option("--layershot"), let lite = lite, let root = lite.view.layer {
        let scale = window.backingScaleFactor
        let size = lite.view.bounds.size
        if let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            ctx.scaleBy(x: scale, y: scale)
            if root.isGeometryFlipped || lite.view.isFlipped {
                ctx.translateBy(x: 0, y: size.height)
                ctx.scaleBy(x: 1, y: -1)
            }
            root.render(in: ctx)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if let image = ctx.makeImage() {
                savePNG(NSImage(cgImage: image, size: size), "\(dir)/\(URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent).lite.png")
            }
        }
    }
    try? (recorder?.log ?? []).joined(separator: "\n").write(toFile: "\(out)/\(name).log", atomically: true, encoding: .utf8)
    var done = false
    host.snapshot { image in
        if let image = image { savePNG(image, "\(out)/\(name).png") }
        done = true
    }
    while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    if let lite = lite {
        print("compositor-rasters: \(LiteHTMLWidgetRenderer.totalPromotions)")
        print("composited now=\(lite.compositedCount) promotions=\(lite.promotionCount) magic=\(lite.magicMoveCount) driven=\(lite.drivenCount) handoff-error=\(String(format: "%.3f px %.4f alpha", lite.handoffWorst.geometry, lite.handoffWorst.alpha)) offsets(ms) median=\(lite.handoffOffsets.sorted().dropFirst(lite.handoffOffsets.count / 2).first.map { String(format: "%.0f", $0 * 1000) } ?? "-") min=\(lite.handoffOffsets.min().map { String(format: "%.0f", $0 * 1000) } ?? "-") max=\(lite.handoffOffsets.max().map { String(format: "%.0f", $0 * 1000) } ?? "-")")
    }
    if let lite = lite, lite.compositeChecks > 0 {
        print(String(format: "compositecheck: %d frames, worst %.3f%% of pixels unmatched within a pixel", lite.compositeChecks, lite.compositeWorst))
    }
    if let lite = lite, lite.patchChecks > 0 {
        print("patchcheck: \(lite.patchChecks) patched documents, \(lite.patchMismatches) differ from a fresh parse, \(lite.styleFastMismatches) style-fast sources differ")
    }
    if let lite = lite, lite.verification.frames > 0 {
        print("verify: \(lite.verification.frames) frames, \(lite.verification.mismatched) differ from a fresh render")
        if ProcessInfo.processInfo.environment["TW_SVGCHECK"] != nil {
            print(lite.svgCheckReport)
        }
        print(lite.shimmerCheckReport)
    }
    if let lite = lite {
        print(String(format: "layouts=%d total=%.1f ms mean=%.3f ms", lite.layoutCount, lite.layoutMilliseconds, lite.layoutMilliseconds / Double(max(1, lite.layoutCount))) + " | " + lite.stageMilliseconds.sorted { $0.key < $1.key }.map { String(format: "%@ %.3f", $0.key, $0.value / Double(max(1, lite.layoutCount))) }.joined(separator: "  ") + String(format: " | draws=%d mean=%.3f ms | max layout %.2f draw %.2f | frames=%d layouts/frame=%.2f ticks=%d layouts/tick=%.2f", lite.drawCount, lite.drawMilliseconds / Double(max(1, lite.drawCount)), lite.layoutMaxMilliseconds, lite.drawMaxMilliseconds, lite.framesPosted, Double(lite.layoutCount) / Double(max(1, lite.framesPosted)), lite.ticks, Double(lite.layoutCount) / Double(max(1, lite.ticks))))
    }
    if args.contains("--logs") {
        for entry in host.diagnostics.logs.suffix(40) {
            print("log \(entry.level): \(entry.text)")
        }
        for (kind, entry) in host.diagnostics.diags.sorted(by: { $0.key < $1.key }) {
            print("diag \(kind): \(entry.details.prefix(3).joined(separator: " | "))")
        }
    }
    let d = host.diagnostics
    print("\(name): height=\(d.height) rendered=\(d.rendered) dead=\(d.dead ?? "-") error=\(d.lastError ?? "-") first=\(d.firstContentMs.map { String(format: "%.1f", $0) } ?? "-") ready=\(d.rendererReadyMs.map { String(format: "%.1f", $0) } ?? "-") loaded=\(d.loadedMs.map { String(format: "%.1f", $0) } ?? "-") renderedAt=\(d.renderedMs.map { String(format: "%.1f", $0) } ?? "-") prewarmed=\(d.prewarmed.isEmpty ? "-" : d.prewarmed) messages=\(recorder?.messageCount ?? -1) recorded=\(recorder?.recordsTraffic ?? false) diags=\(d.diags.map { "\($0.key)=\($0.value.count)" }.joined(separator: ","))")
    if args.contains("--diags") {
        for (k, v) in d.diags.sorted(by: { $0.key < $1.key }) { print("diag \(k) x\(v.count): \(v.details.prefix(5).joined(separator: " | "))") }
    }
    if let path = option("--timeline-out"), let web = recorder?.inner as? RendererWebView, let timeline = WebKitTimeline(web.webView) {
        timeline.capture(seconds: Double(option("--timeline-seconds") ?? "3") ?? 3, path: path)
    }
case "qbc":
    let source = try! String(contentsOfFile: args[2], encoding: .utf8)
    let js = QuickJSContext(memoryLimitBytes: 256 << 20, maxStackBytes: JSThread.jsStackLimit)
    let blob = try! JSThread(name: "qbc").sync { Result { try js.compileBytecode(source, filename: URL(fileURLWithPath: args[2]).lastPathComponent) } }.get()
    try! blob.write(to: URL(fileURLWithPath: args[3]))
    print("qbc: \(blob.count) bytes")
case "bootfloor":
    runBootFloor(args, option: option)
case "opsdump":
    runOpsDump(args, option: option)
case "shimprof":
    runShimProfile(args, option: option)
case "bootbench":
    runBootBench(args, option: option)
case "startup":
    runStartupTrace(args, option: option)
case "shimbench":
    runShimBench(args, option: option)
case "scroll":
    runFeed(args, option: option)
case "crashstress":
    runCrashStress(args, option: option)
case "clickfuzz":
    runClickFuzz(args, option: option)
case "gateattack":
    runGateAttack(args, option: option)
case "resattack":
    runResourceAttack(args, option: option)
case "eventrepro":
    runEventRepro(args, option: option)
case "feed":
    let files = try! String(contentsOfFile: args[2]).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    let count = Int(option("--count") ?? "20") ?? 20
    let width = CGFloat(Double(option("--width") ?? "400") ?? 400)
    let useLite = option("--renderer") == "lite"
    let maxHost = option("--host") == "max"
    let idleSeconds = Double(option("--seconds") ?? "4") ?? 4
    let scrollSeconds = Double(option("--scroll-seconds") ?? "6") ?? 6
    let scrollSpeed = Double(option("--scroll-speed") ?? "1200") ?? 1200
    let viewportHeight: CGFloat = 900
    let gap: CGFloat = 8
    let footprintStart = groupFootprint()
    if maxHost {
        prewarmMaxHost(width: width, renderers: useLite ? 0 : min(4, count), engines: min(4, count))
    }
    let footprintBeforeHosts = groupFootprint()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: viewportHeight), styleMask: [.borderless], backing: .buffered, defer: false)
    window.ignoresMouseEvents = true
    window.level = .floating
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: viewportHeight))
    let document = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: viewportHeight))
    scroll.documentView = document
    scroll.hasVerticalScroller = false
    window.contentView?.addSubview(scroll)
    var hosts: [WidgetHost] = []
    var shownBlank = 0
    var seen = Set<Int>()
    var countEntries = false
    func layout() {
        var y: CGFloat = 0
        for host in hosts {
            let height = max(24, host.diagnostics.height)
            host.view.frame = NSRect(x: 0, y: y, width: width, height: height)
            y += height + gap
        }
        document.frame.size.height = max(viewportHeight, y)
        let visible = scroll.contentView.bounds
        for (index, host) in hosts.enumerated() {
            let on = host.view.frame.intersects(visible)
            host.setVisible(on)
            if on && !seen.contains(index) {
                seen.insert(index)
                if countEntries && host.diagnostics.firstContentMs == nil { shownBlank += 1 }
            }
        }
    }
    let loadStart = Date()
    let loadCPU = groupCPU()
    let loadWindowServer = windowServerSeconds()
    var maxCreateMs = 0.0
    for index in 0..<count {
        let html = try! String(contentsOfFile: files[index % files.count])
        let t0 = CACurrentMediaTime()
        let host = try! WidgetHost(html: html, theme: "light", width: width, options: maxHost ? maxHostOptions() : labOptions(), rendererFactory: useLite ? { _, theme, width in TimingRenderer(LiteHTMLWidgetRenderer(theme: theme, width: width)) } : (maxHost ? nil : { resources, theme, _ in RendererWebView(rendererBundle: resources.rendererBundle, theme: theme) }))
        host.view.frame = NSRect(x: 0, y: 0, width: width, height: 300)
        disableWebKitOcclusion(host.view)
        document.addSubview(host.view)
        maxCreateMs = max(maxCreateMs, (CACurrentMediaTime() - t0) * 1000)
        hosts.append(host)
    }
    layout()
    var firstScreenMs: Double?
    var allMs: Double?
    var loadMaxGap = 0.0
    var last = CACurrentMediaTime()
    while Date().timeIntervalSince(loadStart) < 30 {
        RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 120))
        let now = CACurrentMediaTime()
        loadMaxGap = max(loadMaxGap, now - last)
        last = now
        layout()
        let visible = scroll.contentView.bounds
        if firstScreenMs == nil, hosts.filter({ $0.view.frame.intersects(visible) }).allSatisfy({ $0.diagnostics.firstContentMs != nil }) {
            firstScreenMs = Date().timeIntervalSince(loadStart) * 1000
        }
        if hosts.allSatisfy({ $0.diagnostics.firstContentMs != nil || $0.diagnostics.dead != nil }) {
            allMs = Date().timeIntervalSince(loadStart) * 1000
            break
        }
    }
    let loadEnd = groupCPU()
    let loadElapsed = Date().timeIntervalSince(loadStart)
    let loadWindowServerEnd = windowServerSeconds()
    print(String(format: "feed: %d widgets renderer %@ host %@", count, useLite ? "lite" : "web", maxHost ? "max" : "default"))
    print(String(format: "load main-thread renderer+host work: %.0f ms in %d calls, worst %.1f ms (%@)", TimingRenderer.total, TimingRenderer.calls, TimingRenderer.worst, TimingRenderer.worstWhat))
    print(String(format: "load: first screen %.0f ms, all %.0f ms, worst host init %.1f ms, worst main gap %.0f ms, cpu own %.2f s helpers %.2f s windowserver %.2f s", firstScreenMs ?? -1, allMs ?? -1, maxCreateMs, loadMaxGap * 1000, loadEnd.own - loadCPU.own, loadEnd.helpers - loadCPU.helpers, loadWindowServerEnd - loadWindowServer))
    RunLoop.main.run(until: Date().addingTimeInterval(1))
    let idleBegin = groupCPU()
    let idleWindowServer = windowServerSeconds()
    let idleAt = Date()
    while Date().timeIntervalSince(idleAt) < idleSeconds {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        layout()
    }
    let idleEnd = groupCPU()
    let idleElapsed = Date().timeIntervalSince(idleAt)
    print(String(format: "idle at top: own %.2f%% helpers %.2f%% total %.2f%% windowserver %.2f%% over %.2fs", (idleEnd.own - idleBegin.own) / idleElapsed * 100, (idleEnd.helpers - idleBegin.helpers) / idleElapsed * 100, (idleEnd.own - idleBegin.own + idleEnd.helpers - idleBegin.helpers) / idleElapsed * 100, (windowServerSeconds() - idleWindowServer) / idleElapsed * 100, idleElapsed))
    let entriesBefore = seen.count
    countEntries = true
    let scrollBegin = groupCPU()
    let scrollWindowServer = windowServerSeconds()
    let scrollAt = CACurrentMediaTime()
    var scrollMaxGap = 0.0
    var longFrames = 0
    var frames = 0
    last = CACurrentMediaTime()
    var direction = 1.0
    var offset = 0.0
    while CACurrentMediaTime() - scrollAt < scrollSeconds {
        RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 120))
        let now = CACurrentMediaTime()
        let dt = now - last
        last = now
        frames += 1
        scrollMaxGap = max(scrollMaxGap, dt)
        if dt > 1.0 / 30 { longFrames += 1 }
        let maxOffset = Double(max(0, document.frame.height - viewportHeight))
        offset += direction * scrollSpeed * dt
        if offset >= maxOffset { offset = maxOffset; direction = -1 }
        if offset <= 0 { offset = 0; direction = 1 }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scroll.reflectScrolledClipView(scroll.contentView)
        layout()
    }
    let scrollEnd = groupCPU()
    let scrollElapsed = CACurrentMediaTime() - scrollAt
    print(String(format: "scroll %.0f pt/s: own %.2f%% helpers %.2f%% total %.2f%% windowserver %.2f%% over %.2fs, frames %d, >33ms %d, worst gap %.0f ms, blank on entry %d of %d entered", scrollSpeed, (scrollEnd.own - scrollBegin.own) / scrollElapsed * 100, (scrollEnd.helpers - scrollBegin.helpers) / scrollElapsed * 100, (scrollEnd.own - scrollBegin.own + scrollEnd.helpers - scrollBegin.helpers) / scrollElapsed * 100, (windowServerSeconds() - scrollWindowServer) / scrollElapsed * 100, scrollElapsed, frames, longFrames, scrollMaxGap * 1000, shownBlank, seen.count - entriesBefore))
    let end = groupFootprint()
    print("footprint: start own \(megabytes(footprintStart.own)) helpers \(megabytes(footprintStart.helpers)) | before-hosts own \(megabytes(footprintBeforeHosts.own)) helpers \(megabytes(footprintBeforeHosts.helpers)) | end own \(megabytes(end.own)) helpers \(megabytes(end.helpers)) (\(end.count) procs) | delta \(megabytes(end.own + end.helpers - footprintStart.own - footprintStart.helpers))")
    print("dead: \(hosts.filter { $0.diagnostics.dead != nil }.count), no content: \(hosts.filter { $0.diagnostics.firstContentMs == nil }.count)")
    hosts.forEach { $0.destroy() }
case "native":
    let file = args[2]
    let out = option("--out") ?? "out"
    let width = CGFloat(Double(option("--width") ?? "400") ?? 400)
    let seconds = Double(option("--seconds") ?? "3.5") ?? 3.5
    let warmup = Double(option("--warmup") ?? "1.5") ?? 1.5
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    let html = try! String(contentsOfFile: file)
    final class NativeProbe: NSObject, WKScriptMessageHandler {
        var firstAt: CFTimeInterval?
        var height: CGFloat = 0
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if firstAt == nil { firstAt = CACurrentMediaTime() }
            if let value = message.body as? NSNumber { height = CGFloat(value.doubleValue) }
        }
    }
    let probe = NativeProbe()
    let pool = WKProcessPool()
    func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.processPool = pool
        config.websiteDataStore = .nonPersistent()
        let controller = WKUserContentController()
        controller.add(probe, name: "probe")
        controller.addUserScript(WKUserScript(source: "(function(){function report(){webkit.messageHandlers.probe.postMessage(Math.ceil(document.documentElement.getBoundingClientRect().height))}function first(){requestAnimationFrame(function(){report();new ResizeObserver(report).observe(document.documentElement)})}if(document.readyState==='loading'){document.addEventListener('DOMContentLoaded',first)}else{first()}})()", injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        if (args.contains("--count-frames") || args.contains("--fps")) {
            controller.addUserScript(WKUserScript(source: "(function(){window.__twFrames=0;function f(){window.__twFrames++;requestAnimationFrame(f)}requestAnimationFrame(f)})()", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.userContentController = controller
        return config
    }
    func disableOcclusion(_ view: WKWebView) {
        let selector = Selector(("_setWindowOcclusionDetectionEnabled:"))
        if view.responds(to: selector), let method = class_getInstanceMethod(type(of: view), selector) {
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(method_getImplementation(method), to: Setter.self)(view, selector, false)
        }
    }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
    window.ignoresMouseEvents = true
    window.level = .floating
    window.orderFrontRegardless()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    let footprintStart = groupFootprint()
    var warm: WKWebView?
    if !args.contains("--cold") {
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 300), configuration: makeConfiguration())
        disableOcclusion(view)
        window.contentView?.addSubview(view)
        view.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
        warm = view
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))
        probe.firstAt = nil
        view.removeFromSuperview()
    }
    let createdAt = CACurrentMediaTime()
    let web = warm ?? WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 300), configuration: makeConfiguration())
    knownHelpers = { webKitHelpers(web, pool) }
    disableOcclusion(web)
    web.setValue(false, forKey: "drawsBackground")
    window.contentView?.addSubview(web)
    web.loadHTMLString(html.lowercased().contains("<!doctype") ? html : "<!doctype html>" + html, baseURL: nil)
    let start = Date()
    var cpuStart: (own: Double, helpers: Double)?
    var gpuStart = (own: 0.0, helpers: 0.0, windowServer: 0.0)
    var cpuStartAt = Date()
    var windowServerStart = 0.0
    func frameCount() -> Double {
        var value = -1.0
        var answered = false
        web.evaluateJavaScript("window.__twFrames || 0") { result, _ in
            value = (result as? NSNumber)?.doubleValue ?? -1
            answered = true
        }
        while !answered { RunLoop.main.run(until: Date().addingTimeInterval(0.002)) }
        return value
    }
    var framesStart = 0.0
    while Date().timeIntervalSince(start) < seconds {
        if cpuStart == nil && Date().timeIntervalSince(start) >= warmup {
            if (args.contains("--count-frames") || args.contains("--fps")) { framesStart = frameCount() }
            gpuStart = groupGPU()
            cpuStart = groupCPU()
            cpuStartAt = Date()
            windowServerStart = windowServerSeconds()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        if probe.height > 0 { web.frame.size.height = min(900, max(24, probe.height)) }
    }
    if let begin = cpuStart {
        let end = groupCPU()
        let elapsed = Date().timeIntervalSince(cpuStartAt)
        let frames = (args.contains("--count-frames") || args.contains("--fps")) ? frameCount() - framesStart : 0
        print(String(format: "steady: own %.2f%% helpers %.2f%% total %.2f%% windowserver %.2f%% over %.2fs ops 0 fps %.1f cpu/frame %.3f ms", (end.own - begin.own) / elapsed * 100, (end.helpers - begin.helpers) / elapsed * 100, (end.own - begin.own + end.helpers - begin.helpers) / elapsed * 100, (windowServerSeconds() - windowServerStart) / elapsed * 100, elapsed, frames / elapsed, frames > 0 ? (end.own - begin.own + end.helpers - begin.helpers) * 1000 / frames : 0))
        let gpuEnd = groupGPU()
        print(String(format: "gpu: own %.2f%% helpers %.2f%% windowserver %.2f%%", (gpuEnd.own - gpuStart.own) / elapsed * 100, (gpuEnd.helpers - gpuStart.helpers) / elapsed * 100, (gpuEnd.windowServer - gpuStart.windowServer) / elapsed * 100))
        if false {
            print(String(format: "frames: %.1f fps", (frameCount() - framesStart) / Date().timeIntervalSince(cpuStartAt)))
        }
    }
    let end = groupFootprint()
    print("footprint: start own \(megabytes(footprintStart.own)) helpers \(megabytes(footprintStart.helpers)) | end own \(megabytes(end.own)) helpers \(megabytes(end.helpers)) (\(end.count) procs) | delta \(megabytes(end.own + end.helpers - footprintStart.own - footprintStart.helpers))")
    var done = false
    web.takeSnapshot(with: nil) { image, _ in
        if let image = image { savePNG(image, "\(out)/\(URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent).native.png") }
        done = true
    }
    while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent + ".native"
    print("\(name): height=\(probe.height) rendered=true dead=- error=- first=\(probe.firstAt.map { String(format: "%.1f", ($0 - createdAt) * 1000) } ?? "-") ")
case "bench":
    let dir = args[2]
    let width = CGFloat(Double(option("--width") ?? "400") ?? 400)
    let rounds = Int(option("--rounds") ?? "20") ?? 20
    let files = try! FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasPrefix("frame") && $0.hasSuffix(".html") }.sorted { Int($0.dropFirst(5).prefix { $0.isNumber })! < Int($1.dropFirst(5).prefix { $0.isNumber })! }
    let frames = files.map { try! String(contentsOfFile: dir + "/" + $0) }
    var changed: [(Int, String)] = []
    for i in 1..<frames.count where frames[i] != frames[i - 1] {
        changed.append((i, files[i]))
    }
    var docMs = [Double](repeating: 0, count: frames.count), layMs = [Double](repeating: 0, count: frames.count), listMs = [Double](repeating: 0, count: frames.count)
    var reused = [Bool](repeating: false, count: frames.count)
    let warm = LHDocument(html: frames[0], css: nil)
    _ = warm.layout(maxWidth: width, preferredWidth: width)
    for round in 0...rounds {
        var doc = LHDocument(html: frames[0], css: nil, previous: nil)
        _ = doc.layout(maxWidth: width, preferredWidth: width)
        _ = doc.displayList(maxWidth: width)
        for i in 1..<frames.count {
            let t0 = CACurrentMediaTime()
            let next = LHDocument(html: frames[i], css: nil, previous: doc)
            let t1 = CACurrentMediaTime()
            _ = next.layout(maxWidth: width, preferredWidth: width)
            let t2 = CACurrentMediaTime()
            _ = next.displayList(maxWidth: width)
            let t3 = CACurrentMediaTime()
            reused[i] = next.reusedPrevious
            doc = next
            let t4 = CACurrentMediaTime()
            if round > 0 {
                let d = (t1 - t0 + t4 - t3) * 1000, l = (t2 - t1) * 1000, s = (t3 - t2) * 1000
                if round == 1 || d + l + s < docMs[i] + layMs[i] + listMs[i] {
                    docMs[i] = d
                    layMs[i] = l
                    listMs[i] = s
                }
            }
        }
    }
    var structural: [Double] = []
    for (i, name) in changed {
        let total = docMs[i] + layMs[i] + listMs[i]
        if args.contains("--all") || total > 0.4 {
            print(String(format: "%@ %@ document %.3f layout %.3f list %.3f total %.3f", name, reused[i] ? "reused" : "fresh ", docMs[i], layMs[i], listMs[i], total))
        }
        if !files[i].contains("reused") || reused[i] { structural.append(total) }
    }
    let totals = changed.map { docMs[$0.0] + layMs[$0.0] + listMs[$0.0] }
    print(String(format: "frames=%d changed=%d reused=%d mean=%.3f max=%.3f", frames.count, changed.count, changed.filter { reused[$0.0] }.count, totals.reduce(0, +) / Double(max(1, totals.count)), totals.max() ?? 0))
case "replaycheck":
    let dir = args[2]
    let width = CGFloat(Double(option("--width") ?? "400") ?? 400)
    let fingerprintPath = option("--fingerprints")
    var fingerprints: [[String: Any]] = []
    let files = try! FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasPrefix("frame") && $0.hasSuffix(".html") }.sorted { Int($0.dropFirst(5).prefix { $0.isNumber })! < Int($1.dropFirst(5).prefix { $0.isNumber })! }
    func same(_ a: CGImage?, _ b: CGImage?) -> Bool {
        guard let a = a, let b = b, a.width == b.width, a.height == b.height, let da = a.dataProvider?.data, let db = b.dataProvider?.data, CFDataGetLength(da) == CFDataGetLength(db) else { return a == nil && b == nil }
        let pa = CFDataGetBytePtr(da)!, pb = CFDataGetBytePtr(db)!
        for i in 0..<CFDataGetLength(da) where abs(Int(pa[i]) - Int(pb[i])) > 1 { return false }
        return true
    }
    func recordFingerprint(_ document: LHDocument, name: String) {
        guard fingerprintPath != nil else { return }
        let size = CGSize(width: width, height: max(1, ceil(document.size.height)))
        guard let image = document.copyImage(maxWidth: width, rect: CGRect(origin: .zero, size: size), scale: 2),
              let bytes = image.dataProvider?.data, let pointer = CFDataGetBytePtr(bytes) else {
            fatalError("Unable to render fingerprint for \(name)")
        }
        func digest(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        fingerprints.append([
            "frame": name, "width": image.width, "height": image.height, "bytesPerRow": image.bytesPerRow,
            "pixels": digest(Data(bytes: pointer, count: CFDataGetLength(bytes))),
            "layout": digest(Data(document.layoutSignature.utf8))
        ])
    }
    var doc = LHDocument(html: try! String(contentsOfFile: dir + "/" + files[0]), css: nil, previous: nil)
    _ = doc.layout(maxWidth: width, preferredWidth: width)
    recordFingerprint(doc, name: files[0])
    var patched = 0, differ = 0
    var previousHTML = try! String(contentsOfFile: dir + "/" + files[0])
    for name in files.dropFirst() {
        let html = try! String(contentsOfFile: dir + "/" + name)
        let next = LHDocument(html: html, css: nil, previous: doc)
        _ = next.layout(maxWidth: width, preferredWidth: width)
        if next.reusedPrevious {
            patched += 1
            let fresh = LHDocument(html: html, css: nil)
            _ = fresh.layout(maxWidth: width, preferredWidth: width)
            let size = CGSize(width: width, height: max(1, ceil(max(next.size.height, fresh.size.height))))
            let a = next.copyImage(maxWidth: width, rect: CGRect(origin: .zero, size: size), scale: 2)
            let b = fresh.copyImage(maxWidth: width, rect: CGRect(origin: .zero, size: size), scale: 2)
            if abs(next.size.height - fresh.size.height) > 0.01 || !same(a, b) {
                differ += 1
                print("DIFFER \(name)")
                if let out = option("--out"), differ <= 3 {
                    try? previousHTML.write(toFile: out + "/before\(differ).html", atomically: true, encoding: .utf8)
                    try? html.write(toFile: out + "/after\(differ).html", atomically: true, encoding: .utf8)
                    for (n, image) in [("patched", a), ("fresh", b)] {
                        if let image = image { try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + "/\(n)\(differ).png")) }
                    }
                }
            }
        }
        previousHTML = html
        doc = next
        recordFingerprint(next, name: name)
    }
    if let path = fingerprintPath {
        try! JSONSerialization.data(withJSONObject: fingerprints, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: path))
    }
    print("replaycheck: \(files.count) frames, \(patched) patched, \(differ) differ")
    if differ > 0 { exit(1) }
case "compare":
    let root = args[2]
    let sideBySide = option("--pairs")
    if let dir = sideBySide { try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }
    var rows: [(String, Double, Double, Int, Int)] = []
    let walker = FileManager.default.enumerator(atPath: root)!
    for case let path as String in walker where path.hasSuffix(".png") && !path.hasSuffix(".lite.png") {
        let litePath = root + "/" + path.replacingOccurrences(of: ".png", with: ".lite.png")
        guard let a = NSImage(contentsOfFile: root + "/" + path)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let b = NSImage(contentsOfFile: litePath)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
        let w = min(a.width, b.width), h = min(a.height, b.height)
        func pixels(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: h - image.height, width: image.width, height: image.height))
            return data
        }
        let pa = pixels(a), pb = pixels(b)
        var off = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            if abs(Int(pa[i]) - Int(pb[i])) > 40 || abs(Int(pa[i + 1]) - Int(pb[i + 1])) > 40 || abs(Int(pa[i + 2]) - Int(pb[i + 2])) > 40 || abs(Int(pa[i + 3]) - Int(pb[i + 3])) > 40 { off += 1 }
        }
        let fraction = Double(off) / Double(max(1, w * h)) * 100
        rows.append((path, fraction, Double(b.height - a.height) / 2, a.height / 2, b.height / 2))
        if let dir = sideBySide {
            let W = a.width + b.width + 20, H = max(a.height, b.height)
            let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.6, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            ctx.draw(a, in: CGRect(x: 0, y: H - a.height, width: a.width, height: a.height))
            ctx.draw(b, in: CGRect(x: a.width + 20, y: H - b.height, width: b.width, height: b.height))
            let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + path.replacingOccurrences(of: "/", with: "_")))
        }
    }
    rows.sort { $0.1 > $1.1 }
    for row in rows {
        print(String(format: "%6.2f%% off  height %+5.0f (webkit %4d lite %4d)  %@", row.1, row.2, row.3, row.4, row.0))
    }
    let avg = rows.map { $0.1 }.reduce(0, +) / Double(max(1, rows.count))
    print(String(format: "%d widgets, mean %.2f%% pixels off, %d within 1%%, %d with height within 4 pt", rows.count, avg, rows.filter { $0.1 < 1 }.count, rows.filter { abs($0.2) <= 4 }.count))
default:
    print("usage: TwidgetLab capture <widget.html> [--out dir] [--width 400] [--height points] [--theme light] [--seconds 2]")
}
