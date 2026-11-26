import Cocoa
import TGUIKit
import GraphCore
import GraphUI

var layerDrawCount = 0

func installDrawCounter() {
    guard let cls = NSClassFromString("NSViewBackingLayer"), let method = class_getInstanceMethod(cls, #selector(CALayer.draw(in:))) else {
        return
    }
    typealias DrawFunction = @convention(c) (AnyObject, Selector, CGContext) -> Void
    let original = unsafeBitCast(method_getImplementation(method), to: DrawFunction.self)
    let block: @convention(block) (AnyObject, CGContext) -> Void = { layer, context in
        layerDrawCount += 1
        original(layer, #selector(CALayer.draw(in:)), context)
    }
    method_setImplementation(method, imp_implementationWithBlock(block))
}

struct SeededRandom {
    var state: UInt64

    mutating func next() -> Double {
        self.state = self.state &* 6364136223846793005 &+ 1442695040888963407
        return Double(self.state >> 11) / Double(UInt64(1) << 53)
    }
}

func makeCollection(kind: String, series: Int, points: Int, seed: UInt64) -> ChartsCollection {
    var random = SeededRandom(state: seed)
    let start = 1_600_000_000_000
    let step = kind == "hourly" ? 3_600_000 : 86_400_000
    var columns: [[Any]] = [["x"] + (0 ..< points).map { start + $0 * step }]
    var types: [String: String] = ["x": "x"]
    var names: [String: String] = [:]
    var colors: [String: String] = [:]
    let palette = ["#3497ED", "#F34C44", "#4BD964", "#FE9500", "#9C27B0", "#00BCD4"]
    for i in 0 ..< series {
        var value = 1000.0 * Double(i + 1)
        var values: [Any] = ["y\(i)"]
        for _ in 0 ..< points {
            value = max(1, value + (random.next() - 0.48) * 120 * Double(i + 1))
            values.append(Int(value))
        }
        columns.append(values)
        switch kind {
        case "bars":
            types["y\(i)"] = "bar"
        case "step", "hourly":
            types["y\(i)"] = "step"
        case "area":
            types["y\(i)"] = "area"
        default:
            types["y\(i)"] = "line"
        }
        names["y\(i)"] = "Series \(i)"
        colors["y\(i)"] = palette[i % palette.count]
    }
    return try! ChartsCollection(from: ["columns": columns, "types": types, "names": names, "colors": colors])
}

func makeController(_ name: String) -> BaseChartController {
    switch name {
    case "lines":
        let controller = GeneralLinesChartController(chartsCollection: makeCollection(kind: "lines", series: 3, points: 365, seed: 1))
        controller.isZoomable = false
        return controller
    case "twoAxis":
        let controller = TwoAxisLinesChartController(chartsCollection: makeCollection(kind: "lines", series: 2, points: 365, seed: 2))
        controller.isZoomable = false
        return controller
    case "stackedBars":
        let controller = StackedBarsChartController(chartsCollection: makeCollection(kind: "bars", series: 4, points: 365, seed: 3))
        controller.isZoomable = false
        return controller
    case "step":
        return StepBarsChartController(chartsCollection: makeCollection(kind: "step", series: 2, points: 365, seed: 4))
    case "area":
        return PercentPieChartController(chartsCollection: makeCollection(kind: "area", series: 4, points: 365, seed: 5), initiallyZoomed: false)
    case "pie":
        return PercentPieChartController(chartsCollection: makeCollection(kind: "area", series: 4, points: 365, seed: 6))
    default:
        fatalError(name)
    }
}

final class ProcessMonitor {
    private let mainThread: thread_act_t = mach_thread_self()

    struct Snapshot {
        let time: Double
        let cpu: Double
        let mainCpu: Double
    }

    func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1048576 : 0
    }

    func snapshot() -> Snapshot {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6 + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(self.mainThread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        var mainCpu = 0.0
        if result == KERN_SUCCESS {
            mainCpu = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1e6 + Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1e6
        }
        return Snapshot(time: CACurrentMediaTime(), cpu: cpu, mainCpu: mainCpu)
    }
}

final class FrameDriver: NSObject {
    private var link: CADisplayLink?
    private var onFrame: ((Double) -> Void)?
    private(set) var frames = 0
    private(set) var hitches = 0
    private(set) var worstGap = 0.0
    private var lastTimestamp = 0.0
    private var frameDuration = 1.0 / 120.0

    func start(view: NSView, onFrame: @escaping (Double) -> Void) {
        self.onFrame = onFrame
        self.frames = 0
        self.hitches = 0
        self.worstGap = 0
        self.lastTimestamp = 0
        let link = view.displayLink(target: self, selector: #selector(self.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        self.link?.invalidate()
        self.link = nil
        self.onFrame = nil
    }

    @objc func tick(_ link: CADisplayLink) {
        let duration = link.targetTimestamp - link.timestamp
        if duration > 0 {
            self.frameDuration = duration
        }
        if self.lastTimestamp > 0 {
            let gap = link.timestamp - self.lastTimestamp
            self.worstGap = max(self.worstGap, gap)
            if gap > self.frameDuration * 1.5 {
                self.hitches += 1
            }
        }
        self.lastTimestamp = link.timestamp
        self.frames += 1
        self.onFrame?(link.targetTimestamp)
    }
}

struct Result {
    let chart: String
    let scenario: String
    let run: Int
    var metrics: [String: Double]
}

final class Lab: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 680, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
    let monitor = ProcessMonitor()
    let driver = FrameDriver()
    var results: [Result] = []
    let label: String
    let charts: [String]
    let scenarios: [String]
    let runs: Int
    let seconds: Double
    var queue: [(String, String, Int)] = []
    var section: ChartStackSection?
    var night: Bool = argument("--night", "0") == "1"
    var controller: BaseChartController?
    #if CHARTLAB_STYLES
    var overviewTiles: [ChartOverviewTileView] = []
    #endif
    var overviewHost: NSView?

    init(label: String, charts: [String], scenarios: [String], runs: Int, seconds: Double) {
        self.label = label
        self.charts = charts
        self.scenarios = scenarios
        self.runs = runs
        self.seconds = seconds
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.window.title = "ChartLab \(self.label)"
        self.window.contentView?.wantsLayer = true
        self.window.backgroundColor = self.night ? NSColor(red: 34/255.0, green: 47/255.0, blue: 63/255.0, alpha: 1.0) : .white
        self.window.appearance = NSAppearance(named: self.night ? .darkAqua : .aqua)
        self.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        for chart in self.charts {
            for run in 0 ..< self.runs {
                for scenario in self.scenarios {
                    self.queue.append((chart, scenario, run))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.next()
        }
    }

    func mount(_ chart: String) -> Double {
        self.section?.removeFromSuperview()
        self.section = nil
        self.controller = nil
        let start = self.monitor.snapshot()
        if chart == "none" {
            self.window.displayIfNeeded()
            CATransaction.flush()
            return 0
        }
        #if CHARTLAB_STYLES
        if chart == "overview" {
            self.mountOverview(generation: 0)
            return 0
        }
        #endif
        let controller = makeController(chart)
        let section = ChartStackSection()
        let height = controller.height(for: 640)
        section.frame = NSRect(x: 20, y: 20, width: 640, height: height)
        self.window.contentView?.addSubview(section)
        section.layout()
        section.setup(controller: controller, title: chart)
        applyStyle(section)
        section.apply(theme: self.night ? .defaultNightTheme : .defaultDayTheme, strings: .defaultStrings, animated: false)
        self.window.contentView?.layoutSubtreeIfNeeded()
        self.window.displayIfNeeded()
        CATransaction.flush()
        if ProcessInfo.processInfo.environment["CHARTLAB_SYNC_DRAW"] == "1" {
            disableAsynchronousDrawing(section.layer)
        }
        if ProcessInfo.processInfo.environment["CHARTLAB_RGBA8"] == "1" {
            forceEightBitContents(section.layer)
        }
        if ProcessInfo.processInfo.environment["CHARTLAB_DUMP_LAYERS"] == "1" {
            dumpLayers(self.window.contentView?.layer, depth: 0)
        }
        let end = self.monitor.snapshot()
        self.section = section
        self.controller = controller
        return (end.mainCpu - start.mainCpu) * 1000
    }

    #if CHARTLAB_STYLES
    func overviewItems(_ generation: Int) -> [ChartOverviewTileView.Content] {
        let text = self.night ? NSColor.white : NSColor(white: 0.08, alpha: 1)
        let gray = self.night ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.5, alpha: 1)
        let green = NSColor(red: 0.2, green: 0.72, blue: 0.35, alpha: 1)
        let red = NSColor(red: 0.9, green: 0.27, blue: 0.24, alpha: 1)
        let sets: [[(String, String, Bool, String)]] = [
            [("12 384", " +184 (1.51%)", true, "Followers"), ("4 512", " -96 (2.08%)", false, "Views Per Post"), ("38.2%", "", true, "Enabled Notifications"), ("1 287", " +42 (3.37%)", true, "Shares Per Post")],
            [("12 431", " +231 (1.89%)", true, "Followers"), ("4 609", " +1 (0.02%)", true, "Views Per Post"), ("38.7%", "", true, "Enabled Notifications"), ("1 279", " -8 (0.62%)", false, "Shares Per Post")],
        ]
        return sets[generation % sets.count].map { value, delta, up, title in
            let trimmed = delta.trimmingCharacters(in: .whitespaces)
            return ChartOverviewTileView.Content(title: title, value: value, detail: trimmed, titleColor: gray, valueColor: text, detailColor: up ? green : red, detailTinted: true)
        }
    }

    func mountOverview(generation: Int) {
        if self.overviewHost == nil {
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 560))
            host.wantsLayer = true
            host.layer?.backgroundColor = (self.night ? NSColor(red: 0.08, green: 0.11, blue: 0.15, alpha: 1) : NSColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)).cgColor
            self.window.contentView?.addSubview(host)
            self.overviewHost = host
            for _ in 0 ..< 4 {
                let tile = ChartOverviewTileView(frame: .zero)
                host.addSubview(tile)
                self.overviewTiles.append(tile)
            }
        }
        let items = self.overviewItems(generation)
        for (index, tile) in self.overviewTiles.enumerated() {
            tile.update(content: items[index], cardColor: self.night ? NSColor(red: 0.13, green: 0.17, blue: 0.22, alpha: 1) : .white, isDark: self.night, animated: generation > 0)
            let height = ChartOverviewTileView.height(for: items[index])
            let width: CGFloat = 306
            tile.frame = NSRect(x: 30 + CGFloat(index % 2) * (width + 8), y: 360 - CGFloat(index / 2) * (height + 8), width: width, height: height)
        }
        self.window.displayIfNeeded()
        CATransaction.flush()
    }

    func captureSequence(_ name: String, delays: [Double], start: @escaping () -> Void) {
        self.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            CATransaction.flush()
            self.capture("\(name)-0")
            start()
            let begin = CACurrentMediaTime()
            func step(_ index: Int) {
                guard index < delays.count else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.next()
                    }
                    return
                }
                let wait = max(0, begin + delays[index] - CACurrentMediaTime())
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                    CATransaction.flush()
                    self.capture("\(name)-\(index + 1)")
                    step(index + 1)
                }
            }
            step(0)
        }
    }

    func overviewReveal() {
        for tile in self.overviewTiles {
            tile.showSkeleton(cardColor: self.night ? NSColor(red: 0.13, green: 0.17, blue: 0.22, alpha: 1) : .white, isDark: self.night)
        }
        self.captureSequence("overview-reveal", delays: [0.04, 0.12, 0.25, 0.7]) {
            self.mountOverview(generation: 1)
        }
    }

    func chartReveal(chart: String) {
        self.section?.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.section?.isHidden = false
            self.captureSequence("\(chart)-reveal", delays: [0.12, 0.3, 0.5, 1.0]) {
                self.section?.playReveal()
            }
        }
    }

    func chartSkeleton() {
        self.section?.isHidden = true
        let skeleton = ChartSkeletonView(frame: NSRect(x: 20, y: 20, width: 640, height: 350))
        self.window.contentView?.addSubview(skeleton)
        let colors = ChartSkeletonView.colors(isDark: self.night)
        skeleton.update(shapes: ChartSkeletonView.chartShapes(size: skeleton.frame.size, seriesCount: 2), baseColor: colors.base, highlightColor: colors.highlight)
        self.captureSequence("skeleton", delays: [0.4, 0.8]) {
        }
    }

    func overviewMorph() {
        self.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.capture("overview-morph-0")
            self.mountOverview(generation: 1)
            let start = CACurrentMediaTime()
            let delays = [0.03, 0.07, 0.13, 0.45]
            func step(_ index: Int) {
                guard index < delays.count else {
                    self.next()
                    return
                }
                let wait = max(0, start + delays[index] - CACurrentMediaTime())
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                    CATransaction.flush()
                    self.capture("overview-morph-\(index + 1)")
                    step(index + 1)
                }
            }
            step(0)
        }
    }
    #endif

    func next() {
        guard !self.queue.isEmpty else {
            self.finish()
            return
        }
        let (chart, scenario, run) = self.queue.removeFirst()
        let openMs = self.mount(chart)
        let footprint = self.monitor.footprintMB()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.run(chart: chart, scenario: scenario, run: run, openMs: openMs, footprint: footprint)
        }
    }

    func tapVisibilityItem(_ index: Int, in view: NSView) {
        var items: [NSView] = []
        func collect(_ view: NSView) {
            if String(describing: type(of: view)) == "ChartVisibilityItemView" {
                items.append(view)
                return
            }
            view.subviews.forEach(collect)
        }
        collect(view)
        guard index < items.count, let button = items[index].subviews.first(where: { $0 is TextButton }) as? TextButton else {
            return
        }
        button.send(event: .Click)
    }

    func snapshot(chart: String) {
        guard let controller = self.controller, let window = self.section?.window else {
            return
        }
        if let index = Int(argument("--uncheck", "-1")), index >= 0, let section = self.section {
            self.tapVisibilityItem(index, in: section)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.chartInteractionDidBegin(point: CGPoint(x: 0.62, y: 0.5))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let directory = ProcessInfo.processInfo.environment["CHARTLAB_SNAPSHOTS"] ?? NSTemporaryDirectory()
            if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
                let url = URL(fileURLWithPath: directory).appendingPathComponent("\(self.label)-\(chart).png")
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            }
            controller.cancelChartInteraction()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.next()
            }
        }
    }
    
    func capture(_ name: String) {
        let window = self.window
        let directory = ProcessInfo.processInfo.environment["CHARTLAB_SNAPSHOTS"] ?? NSTemporaryDirectory()
        if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(self.label)-\(name).png")
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    func morph(chart: String) {
        guard let controller = self.controller, let window = self.section?.window else {
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let from = Double(argument("--morph-from", "0.55")) ?? 0.55
        let to = Double(argument("--morph-to", "0.62")) ?? 0.62
        controller.chartInteractionDidBegin(point: CGPoint(x: from, y: 0.5))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.capture("\(chart)-morph-0")
            controller.chartInteractionDidBegin(point: CGPoint(x: to, y: 0.5))
            let start = CACurrentMediaTime()
            let delays = [0.03, 0.07, 0.13, 0.45]
            func step(_ index: Int) {
                guard index < delays.count else {
                    controller.cancelChartInteraction()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.next()
                    }
                    return
                }
                let wait = max(0, start + delays[index] - CACurrentMediaTime())
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                    CATransaction.flush()
                    self.capture("\(chart)-morph-\(index + 1)")
                    step(index + 1)
                }
            }
            step(0)
        }
    }

    func run(chart: String, scenario: String, run: Int, openMs: Double, footprint: Double) {
        if scenario == "snapshot" {
            self.snapshot(chart: chart)
            return
        }
        #if CHARTLAB_STYLES
        if scenario == "reveal" {
            if chart == "overview" {
                self.overviewReveal()
            } else {
                self.chartReveal(chart: chart)
            }
            return
        }
        if scenario == "skeleton" {
            self.chartSkeleton()
            return
        }
        #endif
        if scenario == "morph" {
            #if CHARTLAB_STYLES
            if chart == "overview" {
                self.overviewMorph()
                return
            }
            #endif
            self.morph(chart: chart)
            return
        }
        if scenario == "blink" || scenario == "redraw" || scenario == "redrawAsync" {
            let square: NSView
            if scenario == "blink" {
                square = NSView(frame: NSRect(x: 40, y: 40, width: 20, height: 20))
                square.wantsLayer = true
            } else {
                let view = RedrawView(frame: NSRect(x: 20, y: 20, width: 640, height: 250))
                view.layer?.drawsAsynchronously = scenario == "redrawAsync"
                square = view
            }
            self.window.contentView?.addSubview(square)
            var frame = 0
            let startTime = CACurrentMediaTime()
            self.driver.start(view: self.window.contentView!) { [weak self] _ in
                guard let self = self else {
                    return
                }
                frame += 1
                if let view = square as? RedrawView {
                    view.phase = frame
                    view.needsDisplay = true
                } else {
                    square.layer?.backgroundColor = (frame % 2 == 0 ? NSColor.red : NSColor.blue).cgColor
                }
                if CACurrentMediaTime() - startTime >= self.seconds {
                    self.driver.stop()
                    square.removeFromSuperview()
                    self.results.append(Result(chart: chart, scenario: scenario, run: run, metrics: ["footprintMB": self.monitor.footprintMB()]))
                    self.next()
                }
            }
            return
        }
        guard let controller = self.controller, let section = self.section else {
            DispatchQueue.main.asyncAfter(deadline: .now() + self.seconds) {
                self.results.append(Result(chart: chart, scenario: scenario, run: run, metrics: ["footprintMB": footprint]))
                self.next()
            }
            return
        }
        let seriesCount = controller.actualChartVisibility.count
        let duration = self.seconds
        var visibility = controller.actualChartVisibility
        var lastToggle = 0.0
        var toggleIndex = 0
        let start = self.monitor.snapshot()
        let startTime = CACurrentMediaTime()
        let startDraws = layerDrawCount
        self.driver.start(view: section) { [weak self] timestamp in
            guard let self = self else {
                return
            }
            let elapsed = CACurrentMediaTime() - startTime
            let phase = CGFloat(elapsed / duration)
            switch scenario {
            case "scrub":
                let wave = 0.5 - 0.5 * cos(Double(phase) * Double.pi * 4)
                let lower = CGFloat(0.1 + 0.5 * wave)
                controller.updateChartRange(lower ... lower + 0.35)
            case "hover":
                let x = 0.5 - 0.5 * cos(Double(phase) * Double.pi * 6)
                controller.chartInteractionDidBegin(point: CGPoint(x: CGFloat(x), y: 0.5))
            case "toggle":
                if seriesCount > 1 && elapsed - lastToggle > 0.45 {
                    lastToggle = elapsed
                    visibility[toggleIndex % seriesCount].toggle()
                    if !visibility.contains(true) {
                        visibility[toggleIndex % seriesCount] = true
                    }
                    toggleIndex += 1
                    controller.updateChartsVisibility(visibility: visibility, animated: true)
                }
            default:
                break
            }
            if elapsed >= duration {
                let end = self.monitor.snapshot()
                let frames = self.driver.frames
                let hitches = self.driver.hitches
                let worstGap = self.driver.worstGap
                self.driver.stop()
                if scenario == "hover" {
                    controller.cancelChartInteraction()
                }
                let wall = end.time - start.time
                self.results.append(Result(chart: chart, scenario: scenario, run: run, metrics: [
                    "cpuCores": (end.cpu - start.cpu) / wall,
                    "mainThreadBusyPercent": (end.mainCpu - start.mainCpu) / wall * 100,
                    "frames": Double(frames),
                    "hitches": Double(hitches),
                    "worstGapMs": worstGap * 1000,
                    "openMs": openMs,
                    "footprintMB": footprint,
                    "drawsPerSecond": Double(layerDrawCount - startDraws) / wall,
                ]))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.next()
                }
            }
        }
    }

    func finish() {
        var lines: [String] = []
        for result in self.results {
            let metrics = result.metrics.keys.sorted().map { "\"\($0)\": \(String(format: "%.4f", result.metrics[$0]!))" }.joined(separator: ", ")
            lines.append("{\"label\": \"\(self.label)\", \"chart\": \"\(result.chart)\", \"scenario\": \"\(result.scenario)\", \"run\": \(result.run), \(metrics)}")
        }
        let output = lines.joined(separator: "\n") + "\n"
        if let path = ProcessInfo.processInfo.environment["CHARTLAB_OUTPUT"] {
            try? output.write(toFile: path, atomically: true, encoding: .utf8)
        }
        print(output, terminator: "")
        NSApp.terminate(nil)
    }
}

func applyStyle(_ section: ChartStackSection) {
    #if CHARTLAB_STYLES
    switch argument("--style", "classic") {
    case "glass":
        section.chartStyle = .glass
    case "glassFill":
        section.chartStyle = .glassFill
    default:
        section.chartStyle = .classic
    }
    #endif
}

final class RedrawView: View {
    var phase = 0

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        ctx.setStrokeColor(NSColor.systemBlue.cgColor)
        ctx.setLineWidth(2)
        ctx.beginPath()
        for i in 0 ..< 200 {
            let x = CGFloat(i) * self.bounds.width / 200
            let y = self.bounds.midY + sin(CGFloat(i + self.phase) / 10) * 80
            if i == 0 {
                ctx.move(to: CGPoint(x: x, y: y))
            } else {
                ctx.addLine(to: CGPoint(x: x, y: y))
            }
        }
        ctx.strokePath()
    }
}

func dumpLayers(_ layer: CALayer?, depth: Int) {
    guard let layer = layer else {
        return
    }
    let delegate = layer.delegate.map { String(describing: type(of: $0)) } ?? "-"
    FileHandle.standardError.write("\(String(repeating: "  ", count: depth))\(type(of: layer)) \(delegate) \(Int(layer.bounds.width))x\(Int(layer.bounds.height)) async=\(layer.drawsAsynchronously) fmt=\(layer.contentsFormat.rawValue) contents=\(layer.contents != nil)\n".data(using: .utf8)!)
    for sublayer in layer.sublayers ?? [] {
        dumpLayers(sublayer, depth: depth + 1)
    }
}

func forceEightBitContents(_ layer: CALayer?) {
    guard let layer = layer else {
        return
    }
    layer.contentsFormat = .RGBA8Uint
    for sublayer in layer.sublayers ?? [] {
        forceEightBitContents(sublayer)
    }
}

func disableAsynchronousDrawing(_ layer: CALayer?) {
    guard let layer = layer else {
        return
    }
    layer.drawsAsynchronously = false
    for sublayer in layer.sublayers ?? [] {
        disableAsynchronousDrawing(sublayer)
    }
}

func argument(_ name: String, _ fallback: String) -> String {
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: name), index + 1 < arguments.count {
        return arguments[index + 1]
    }
    return fallback
}

func registerPlaceholderImages() {
    for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "arrow_right"] {
        if NSImage(named: name) == nil {
            let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
                NSColor.gray.setFill()
                rect.fill()
                return true
            }
            image.setName(name)
        }
    }
}

registerPlaceholderImages()
installDrawCounter()
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let lab = Lab(
    label: argument("--label", "run"),
    charts: argument("--charts", "lines,twoAxis,stackedBars,step,area,pie").split(separator: ",").map(String.init),
    scenarios: argument("--scenarios", "idle,scrub,hover,toggle").split(separator: ",").map(String.init),
    runs: Int(argument("--runs", "2")) ?? 2,
    seconds: Double(argument("--seconds", "3")) ?? 3
)
app.delegate = lab
app.run()
