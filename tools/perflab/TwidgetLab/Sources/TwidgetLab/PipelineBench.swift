import Foundation
import QuartzCore
import WidgetSandbox
import WidgetSandboxProtocol
import TwidgetRenderer
import Cocoa

func threadCPUms() -> Double {
    var ts = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
    return Double(ts.tv_sec) * 1000 + Double(ts.tv_nsec) / 1e6
}

final class BenchDelegate: SandboxEngineDelegate {
    var batches: [String] = []
    var canvases: [[Int: WidgetCanvasBatch]] = []
    var opBytes = 0
    var frameWanted = false
    var loaded = false
    var died: String?
    var keep = false
    var onOps: ((String) -> Void)?
    var payloads: [(BinaryOpsPayload, [Int: WidgetCanvasBatch])] = []

    func engine(_ engine: SandboxEngine, binaryOps: BinaryOpsPayload, canvas: [Int: WidgetCanvasBatch]) {
        opBytes += binaryOps.words.count * 4 + binaryOps.strings.count + canvas.values.reduce(0) { $0 + $1.words.count * 8 + $1.strings.reduce(0) { $0 + $1.utf8.count } }
        if keep { payloads.append((binaryOps, canvas)) }
    }

    func engine(_ engine: SandboxEngine, ops json: String) {
        self.engine(engine, ops: json, canvas: [:])
    }
    func engine(_ engine: SandboxEngine, ops json: String, canvas: [Int: WidgetCanvasBatch]) {
        opBytes += json.utf8.count + canvas.values.reduce(0) { $0 + $1.words.count * 8 + $1.strings.reduce(0) { $0 + $1.utf8.count } }
        if keep { batches.append(json); canvases.append(canvas) }
        onOps?(json)
    }
    func engine(_ engine: SandboxEngine, query json: String) -> (json: String, binary: Data?) {
        if json.contains("\"viewport\"") { return ("{\"innerWidth\":400,\"innerHeight\":300,\"dpr\":2}", nil) }
        return ("{\"x\":0,\"y\":0,\"width\":0,\"height\":0,\"top\":0,\"left\":0,\"right\":0,\"bottom\":0}", nil)
    }
    func engine(_ engine: SandboxEngine, listen json: String) {}
    func engine(_ engine: SandboxEngine, preventDefault json: String) {}
    func engineRequestsFrame(_ engine: SandboxEngine) { frameWanted = true }
    func engine(_ engine: SandboxEngine, log level: String, text: String) { if level == "error" { print("log \(level): \(text.prefix(300))") } }
    func engine(_ engine: SandboxEngine, diag kind: String, detail: String) {}
    func engine(_ engine: SandboxEngine, bridge method: String, argsJson: String) {}
    func engineLoaded(_ engine: SandboxEngine) { loaded = true }
    func engine(_ engine: SandboxEngine, stats: SandboxStats) {}
    func engine(_ engine: SandboxEngine, died reason: String) { died = reason }
}

func runShimBench(_ args: [String], option: (String) -> String?) {
    let file = args[2]
    let frames = Int(option("--frames") ?? "300") ?? 300
    let html = try! String(contentsOfFile: file)
    let delegate = BenchDelegate()
    var config = SandboxConfig(innerWidth: 400, innerHeight: 300, devicePixelRatio: 2, theme: "light")
    config.cpuLimitMs = 100_000
    config.cpuQuotaMs = 1_000_000
    config.features = LabSandbox.features
    config.policy = .strict
    let resources = option("--bundle").map { SandboxResources(bundle: Bundle(path: $0)!) } ?? .shared
    let engine = SandboxEngine(html: html, config: config, resources: resources)
    delegate.keep = args.contains("--validate")
    engine.delegate = delegate
    engine.start()
    engine.queue.sync {}
    let validator = args.contains("--validate") ? try! TrustedValidator(theme: "light", resources: resources) { _, _ in } : nil
    if let validator { validator.setPolicy(.strict); validator.useNativeModel(engine.runtimeFeatures.contains("binaryOps")) }
    var primed = false
    var time = 16.0
    func step() {
        delegate.frameWanted = false
        engine.frame(time: time)
        time += 16.667
        engine.queue.sync {}
    }
    for _ in 0..<30 { step() }
    if let validator, !primed {
        primed = true
        for (batch, canvas) in zip(delegate.batches, delegate.canvases) { _ = validator.processOpsForRenderer(batch, canvas: canvas, typed: true) }
        for (payload, canvas) in delegate.payloads { _ = validator.processBinary(payload, canvas: canvas, typed: true) }
    }
    delegate.opBytes = 0
    delegate.batches = []
    delegate.canvases = []
    delegate.payloads = []
    let c0 = engine.queue.sync { threadCPUms() }
    let w0 = CACurrentMediaTime()
    for _ in 0..<frames { step() }
    let c1 = engine.queue.sync { threadCPUms() }
    let w1 = CACurrentMediaTime()
    var line = String(format: "shim: %.3f ms cpu/frame (wall %.3f), %d op bytes/frame", (c1 - c0) / Double(frames), (w1 - w0) * 1000 / Double(frames), delegate.opBytes / frames)
    if let validator {
        let batches = delegate.batches
        let v0 = validator.thread.sync { threadCPUms() }
        for (batch, canvas) in zip(batches, delegate.canvases) { _ = validator.processOpsForRenderer(batch, canvas: canvas, typed: true) }
        for (payload, canvas) in delegate.payloads { _ = validator.processBinary(payload, canvas: canvas, typed: true) }
        let v1 = validator.thread.sync { threadCPUms() }
        line += String(format: ", validator %.3f ms cpu/frame over %d batches", (v1 - v0) / Double(frames), batches.count + delegate.payloads.count)
    }
    print(line + (delegate.died.map { " DIED \($0)" } ?? ""))
    engine.terminate()
}

func runStartupTrace(_ args: [String], option: (String) -> String?) {
    let html = try! String(contentsOfFile: args[2])
    let rounds = Int(option("--rounds") ?? "5") ?? 5
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
    window.orderFrontRegardless()
    var options = labOptions()
    options.pools = args.contains("--pools")
    if options.pools {
        WidgetWarmup.prewarm(renderers: 0, engines: 2, validators: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
    }
    let t = CACurrentMediaTime()
    _ = SandboxResources.shared
    print(String(format: "resources %.2f ms", (CACurrentMediaTime() - t) * 1000))
    for round in 0..<rounds {
        if let wait = option("--idle").flatMap(Double.init) { RunLoop.main.run(until: Date().addingTimeInterval(wait)) }
        let t0 = CACurrentMediaTime()
        var tr = 0.0
        let host = try! WidgetHost(html: html, theme: "light", width: 400, options: options, rendererFactory: { _, theme, width in
            let a = CACurrentMediaTime()
            let r = LiteHTMLWidgetRenderer(theme: theme, width: width)
            tr = (CACurrentMediaTime() - a) * 1000
            return r
        })
        let t1 = CACurrentMediaTime()
        window.contentView?.addSubview(host.view)
        let deadline = Date().addingTimeInterval(2)
        while host.diagnostics.firstContentMs == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.0005)) }
        let d = host.diagnostics
        print(String(format: "round %d: init %.2f ms (renderer %.2f) ready %.1f loaded %.1f first %.1f [%@] %@", round, (t1 - t0) * 1000, tr, d.rendererReadyMs ?? -1, d.loadedMs ?? -1, d.firstContentMs ?? -1, d.prewarmed, d.diags["boot"]?.details.first ?? ""))
        host.destroy()
        host.view.removeFromSuperview()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }
}

func runBootBench(_ args: [String], option: (String) -> String?) {
    let html = try! String(contentsOfFile: args[2])
    var config = SandboxConfig(innerWidth: 400, innerHeight: 300, devicePixelRatio: 2, theme: "light")
    config.cpuLimitMs = 100_000
    config.features = LabSandbox.features
    config.policy = .strict
    let validators = (0..<6).map { _ -> TrustedValidator in
        let v = try! TrustedValidator(theme: "light") { _, _ in }
        v.setPolicy(.strict)
        return v
    }
    for round in 0..<5 {
        let engine = SandboxEngine(resources: .shared, features: LabSandbox.features)
        engine.prewarm()
        _ = engine.isPrewarmed
        let delegate = BenchDelegate()
        delegate.keep = true
        engine.delegate = delegate
        let t0 = CACurrentMediaTime()
        engine.start(html: html, config: config)
        engine.queue.sync {}
        let t1 = CACurrentMediaTime()
        let v = validators[round]
        let first = delegate.batches.first ?? "[]"
        let v0 = CACurrentMediaTime()
        let out = v.processOpsForRenderer(first, typed: true)
        let v1 = CACurrentMediaTime()
        let r = LiteHTMLWidgetRenderer(theme: "light", width: 400)
        r.onMessage = { _ in }
        r.load()
        let r0 = CACurrentMediaTime()
        if case .ops(let ops) = out { r.send(ops: ops) } else if case .json(let j) = out { r.send("{\"type\":\"ops\",\"ops\":\(j)}") }
        let r1 = CACurrentMediaTime()
        print(String(format: "boot %.2f ms (%d batches, first %d bytes), validate first %.2f ms, renderer apply %.2f ms", (t1 - t0) * 1000, delegate.batches.count, first.utf8.count, (v1 - v0) * 1000, (r1 - r0) * 1000))
        r.destroy()
        engine.terminate()
    }
}
