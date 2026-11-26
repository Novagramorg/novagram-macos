import AppKit
import QuartzCore

func cpuSeconds(_ pid: Int32) -> Double {
    let p = Process(); p.launchPath = "/bin/ps"; p.arguments = ["-o", "time=", "-p", "\(pid)"]
    let pipe = Pipe(); p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
    let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
    return s.split(separator: ":").reduce(0.0) { $0 * 60 + (Double($1) ?? 0) }
}
func gpu() -> Int {
    let p = Process(); p.launchPath = "/usr/sbin/ioreg"; p.arguments = ["-r", "-d", "1", "-w", "0", "-c", "IOAccelerator"]
    let pipe = Pipe(); p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
    let s = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
    if let r = s.range(of: #""Device Utilization %"=(\d+)"#, options: .regularExpression) {
        return Int(s[r].split(separator: "=").last!) ?? -1
    }
    return -1
}
let wsPid: Int32 = {
    let p = Process(); p.launchPath = "/usr/bin/pgrep"; p.arguments = ["-x", "WindowServer"]
    let pipe = Pipe(); p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
    return Int32(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.split(separator: "\n").first!)!
}()

let particle: CGImage = {
    let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(NSColor.white.cgColor); ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 16, height: 16))
    return ctx.makeImage()!
}()

func makeEmitter(size: CGSize, birthRate: Float, velocity: CGFloat, scale: CGFloat) -> CAEmitterLayer {
    let layer = CAEmitterLayer()
    let cell = CAEmitterCell()
    cell.contents = particle
    cell.birthRate = birthRate
    cell.lifetime = 1.5
    cell.velocity = velocity
    cell.scale = scale
    cell.scaleRange = 0.02
    cell.alphaRange = 0.1
    cell.emissionRange = .pi * 2
    cell.color = NSColor.systemYellow.cgColor
    layer.emitterCells = [cell]
    layer.emitterShape = .circle
    layer.emitterMode = .surface
    layer.emitterSize = size
    layer.frame = CGRect(origin: .zero, size: size)
    layer.emitterPosition = CGPoint(x: size.width / 2, y: size.height / 2)
    return layer
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 560, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
window.title = "EmitterLab"
let content = NSView(frame: window.contentLayoutRect)
content.wantsLayer = true
content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
window.contentView = content
var emitters: [CAEmitterLayer] = []
func build() {
    for i in 0 ..< 12 {
        let a = makeEmitter(size: CGSize(width: 25, height: 25), birthRate: 6, velocity: 0.1, scale: 0.09)
        a.frame.origin = CGPoint(x: 10 + CGFloat(i) * 45, y: 100)
        let b = makeEmitter(size: CGSize(width: 40, height: 30), birthRate: 20, velocity: 10, scale: 0.1)
        b.frame.origin = CGPoint(x: 10 + CGFloat(i) * 45, y: 30)
        content.layer?.addSublayer(a); content.layer?.addSublayer(b)
        emitters += [a, b]
    }
}
build()
window.orderFrontRegardless()

let phases: [String] = ["playing", "paused", "removed", "playing", "paused", "removed", "playing", "paused", "removed"]
let phaseSeconds = 10.0
var results: [String: [(Double, Double, Double)]] = [:]

DispatchQueue.global().async {
    Thread.sleep(forTimeInterval: 3)
    for phase in phases {
        DispatchQueue.main.sync {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            switch phase {
            case "playing":
                if emitters.isEmpty { build() }
                emitters.forEach { $0.birthRate = 1 }
            case "paused":
                emitters.forEach { $0.birthRate = 0 }
            default:
                emitters.forEach { $0.removeFromSuperlayer() }; emitters = []
            }
            CATransaction.commit()
        }
        Thread.sleep(forTimeInterval: 2)
        let ws0 = cpuSeconds(wsPid), me0 = cpuSeconds(getpid()), t0 = Date()
        var g: [Int] = []
        while Date().timeIntervalSince(t0) < phaseSeconds { g.append(gpu()); Thread.sleep(forTimeInterval: 0.5) }
        let dt = Date().timeIntervalSince(t0)
        let ws = (cpuSeconds(wsPid) - ws0) / dt * 100, me = (cpuSeconds(getpid()) - me0) / dt * 100
        let gp = Double(g.reduce(0, +)) / Double(g.count)
        results[phase, default: []].append((ws, me, gp))
        print(String(format: "%@ windowServer=%.1f%% app=%.1f%% gpu=%.1f%%", phase, ws, me, gp)); fflush(stdout)
    }
    for k in ["playing", "paused", "removed"] {
        let r = results[k]!
        print(String(format: "MEAN %@ windowServer=%.1f%% app=%.1f%% gpu=%.1f%%", k, r.map { $0.0 }.reduce(0, +) / Double(r.count), r.map { $0.1 }.reduce(0, +) / Double(r.count), r.map { $0.2 }.reduce(0, +) / Double(r.count)))
    }
    exit(0)
}
app.run()
