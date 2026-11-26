import Foundation
import QuartzCore
import WidgetSandbox

func runShimProfile(_ args: [String], option: (String) -> String?) {
    let source = try! String(contentsOfFile: args[2], encoding: .utf8)
    let labels = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2] + ".labels.json")))) as? [String] ?? []
    let rounds = Int(option("--rounds") ?? "8") ?? 8
    var totals = [Double](repeating: 0, count: labels.count)
    var whole: [Double] = []
    let thread = JSThread(name: "shimprof")
    for _ in 0..<rounds {
        thread.sync {
            let js = QuickJSContext(memoryLimitBytes: 256 << 20, maxStackBytes: JSThread.jsStackLimit)
            var last = CACurrentMediaTime()
            var times = [Double](repeating: 0, count: labels.count)
            js.registerFunction("__host") { _ in .undefined }
            js.registerFunction("__hostBinary") { _ in .undefined }
            js.registerFunction("__twMark") { args in
                let now = CACurrentMediaTime()
                if let index = args.first.flatMap({ Int($0) }), index < times.count {
                    times[index] += (now - last) * 1000
                }
                last = CACurrentMediaTime()
                return .undefined
            }
            let start = CACurrentMediaTime()
            last = start
            do {
                _ = try js.evaluate(source, filename: "sandbox-bundle.js")
            } catch {
                print("eval error: \(error)")
            }
            whole.append((CACurrentMediaTime() - start) * 1000)
            for index in times.indices { totals[index] += times[index] }
        }
    }
    let sorted = whole.sorted()
    print(String(format: "bundle eval ms: median %.2f min %.2f (rounds %d)", sorted[sorted.count / 2], sorted.first ?? 0, rounds))
    let ranked = totals.enumerated().sorted { $0.element > $1.element }
    for (index, total) in ranked.prefix(Int(option("--top") ?? "30") ?? 30) {
        print(String(format: "%7.3f ms  #%d %@", total / Double(rounds), index, labels[index]))
    }
}

func runOpsDump(_ args: [String], option: (String) -> String?) {
    let out = args[2]
    let corpus = loadFeedCorpus(limit: Int.max).filter { option("--only").map($0.0.contains) ?? true }
    var lines: [String] = []
    var config = SandboxConfig(innerWidth: 400, innerHeight: 300, devicePixelRatio: 2, theme: "light")
    config.cpuLimitMs = 100_000
    config.features = LabSandbox.features
    config.policy = .strict
    for (name, html) in corpus {
        let engine = SandboxEngine(resources: .shared, features: LabSandbox.features)
        let delegate = BenchDelegate()
        delegate.keep = true
        engine.delegate = delegate
        engine.start(html: html, config: config)
        engine.queue.sync {}
        RunLoop.main.run(until: Date().addingTimeInterval(Double(option("--wait") ?? "0.15") ?? 0.15))
        engine.queue.sync {}
        var hasher = [UInt8]()
        for json in delegate.batches { hasher += Array(json.utf8); hasher.append(10) }
        for (payload, _) in delegate.payloads {
            for word in payload.words { withUnsafeBytes(of: word) { hasher += $0 } }
            hasher += payload.strings
            hasher.append(10)
        }
        var h: UInt64 = 1469598103934665603
        for b in hasher { h = (h ^ UInt64(b)) &* 1099511628211 }
        if let raw = option("--raw") {
            var text = delegate.batches.joined(separator: "\n")
            for (payload, _) in delegate.payloads {
                text += "\nWORDS " + payload.words.map { String($0) }.joined(separator: ",")
                text += "\nSTRINGS " + String(decoding: payload.strings, as: UTF8.self)
            }
            try? text.write(toFile: raw, atomically: true, encoding: .utf8)
        }
        lines.append("\(name)\t\(delegate.batches.count)+\(delegate.payloads.count)\t\(String(h, radix: 16))")
        engine.terminate()
    }
    try! lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
    print("opsdump: \(lines.count) widgets -> \(out)")
}

func runBootFloor(_ args: [String], option: (String) -> String?) {
    let html = args.count > 2 && !args[2].hasPrefix("--") ? try! String(contentsOfFile: args[2]) : "<div>Hello</div>"
    let rounds = Int(option("--rounds") ?? "20") ?? 20
    var config = SandboxConfig(innerWidth: 400, innerHeight: 300, devicePixelRatio: 2, theme: "light")
    config.cpuLimitMs = 100_000
    config.features = LabSandbox.features
    config.policy = .strict
    var prewarm: [Double] = [], first: [Double] = [], total: [Double] = []
    for _ in 0..<rounds {
        let delegate = BenchDelegate()
        delegate.keep = true
        let t0 = CACurrentMediaTime()
        let engine = SandboxEngine(resources: .shared, features: LabSandbox.features)
        engine.delegate = delegate
        engine.prewarm()
        _ = engine.isPrewarmed
        let t1 = CACurrentMediaTime()
        engine.start(html: html, config: config)
        engine.queue.sync {}
        let deadline = Date().addingTimeInterval(2)
        while delegate.batches.isEmpty && delegate.payloads.isEmpty && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.0005))
        }
        let t2 = CACurrentMediaTime()
        prewarm.append((t1 - t0) * 1000)
        first.append((t2 - t1) * 1000)
        total.append((t2 - t0) * 1000)
        engine.terminate()
    }
    func median(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
    print(String(format: "boot floor (median of %d): runtime+bundle %.2f ms, start to first ops %.2f ms, total %.2f ms", rounds, median(prewarm), median(first), median(total)))
}
