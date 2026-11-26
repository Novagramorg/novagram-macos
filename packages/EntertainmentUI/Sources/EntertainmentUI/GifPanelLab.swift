#if DEBUG
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramMedia
import TelegramMediaUtils
import PerfLab

public enum GifPanelLab {
    private static var session: AnyObject?
    private static var didStart = false

    @discardableResult
    public static func startIfRequested<Context: AccountContextProtocol>(context: Context, outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "gif-panel" else {
            return false
        }
        self.didStart = true
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 4.0), {
            let session = GifPanelLabSession(context: context, configuration: configuration, completion: {
                GifPanelLab.session = nil
                if configuration.quitWhenDone {
                    NSApp.terminate(nil)
                }
            })
            GifPanelLab.session = session
            session.start()
        })
        return true
    }
}

private final class GifPanelLabSession<Context: AccountContextProtocol> {
    private let context: Context
    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private let processMonitor = PerfLabProcessMonitor()
    private var pending: [(scenario: String, run: Int)] = []
    private var window: Window?
    private var controller: GifKeyboardController<Context>?
    private var measurement: PerfLabScrollMeasurement?
    private var wheelSign: Double = -1

    init(context: Context, configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        self.context = context
        self.configuration = configuration
        self.completion = completion
        self.report = PerfLabReport(configuration: configuration)
    }

    func start() {
        SoftwareVideoLayerFrameManager.usesHardwareDecoding = self.configuration.string("-PerfLabGifDecode", "hw") == "hw"
        for scenario in self.configuration.scenarios {
            for run in 0 ..< self.configuration.runs {
                self.pending.append((scenario, run))
            }
        }
        self.next()
    }

    private func next() {
        guard !self.pending.isEmpty else {
            let url = self.report.write()
            NSLog("PerfLab report written to %@", url?.path ?? "nil")
            self.completion()
            return
        }
        let (scenario, run) = self.pending.removeFirst()
        self.runScenario(scenario) { [weak self] metrics, notes in
            guard let self else {
                return
            }
            self.report.add(scenario: scenario, run: run, metrics: metrics, notes: notes)
            self.closePanel()
            Queue.mainQueue().after(1.5, { [weak self] in
                self?.next()
            })
        }
    }

    private var tableView: TableView? {
        return self.controller?.genericView.tableView
    }

    private func openPanel(completion: @escaping () -> Void) {
        let frame = NSMakeRect(200, 200, self.configuration.double("-PerfLabWidth", 360), self.configuration.double("-PerfLabHeight", 520))
        let window = Window(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "GIF Panel Lab"
        window.isReleasedWhenClosed = false
        let controller = GifKeyboardController(self.context)
        controller._frameRect = NSMakeRect(0, 0, frame.width, frame.height)
        controller.loadViewIfNeeded(NSMakeRect(0, 0, frame.width, frame.height))
        controller.view.frame = window.contentView?.bounds ?? frame.size.bounds
        controller.view.autoresizingMask = [.width, .height]
        controller.viewWillAppear(false)
        window.contentView?.addSubview(controller.view)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.viewDidAppear(false)
        self.window = window
        self.controller = controller
        self.waitForContent(deadline: CFAbsoluteTimeGetCurrent() + 30.0, completion: completion)
    }

    private func closePanel() {
        self.measurement = nil
        if let controller = self.controller {
            controller.viewWillDisappear(false)
            controller.view.removeFromSuperview()
            controller.viewDidDisappear(false)
        }
        self.controller = nil
        self.window?.orderOut(nil)
        self.window = nil
    }

    private func waitForContent(deadline: Double, completion: @escaping () -> Void) {
        let height = self.tableView?.documentView?.frame.height ?? 0
        let ready = (self.tableView?.count ?? 0) > 6 && height > self.configuration.double("-PerfLabMinContentHeight", 3000)
        if ready || CFAbsoluteTimeGetCurrent() > deadline {
            Queue.mainQueue().after(self.configuration.double("-PerfLabWarmupSeconds", 6.0), completion)
        } else {
            Queue.mainQueue().after(0.2, { [weak self] in
                self?.waitForContent(deadline: deadline, completion: completion)
            })
        }
    }

    private func scrollToTop() {
        guard let tableView = self.tableView else {
            return
        }
        tableView.clipView.scroll(to: NSPoint(x: 0, y: 0))
        tableView.reflectScrolledClipView(tableView.clipView)
    }

    private func detectWheelSign() {
        guard let tableView = self.tableView else {
            return
        }
        self.scrollToTop()
        let before = tableView.contentView.bounds.minY
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -20, wheel2: 0, wheel3: 0), let nsEvent = NSEvent(cgEvent: event) {
            tableView.scrollWheel(with: nsEvent)
        }
        self.wheelSign = tableView.contentView.bounds.minY > before ? -1 : 1
        self.scrollToTop()
    }

    private func playingGifs() -> [String: Double] {
        guard let tableView = self.tableView else {
            return [:]
        }
        var views: [GifPlayerBufferView] = []
        var stack: [NSView] = [tableView]
        while let current = stack.popLast() {
            if let player = current as? GifPlayerBufferView {
                views.append(player)
            } else {
                stack.append(contentsOf: current.subviews)
            }
        }
        return [
            "gifViews": Double(views.count),
            "gifsTicking": Double(views.filter { $0.ticking }.count),
            "gifsRendering": Double(views.filter { $0.isRendering }.count)
        ]
    }

    private func idle(seconds: Double, completion: @escaping ([String: Double]) -> Void) {
        guard let contentView = self.window?.contentView else {
            completion([:])
            return
        }
        let clock = PerfLabFrameClock(view: contentView)
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        clock.start()
        Queue.mainQueue().after(seconds, { [weak self] in
            clock.stop()
            guard let self else {
                return
            }
            let end = self.processMonitor.snapshot()
            let duration = end.time - start.time
            completion([
                "duration": duration,
                "frames": Double(clock.stats.frames),
                "hitches": Double(clock.stats.hitches),
                "worstGapMs": clock.stats.worstGap * 1000,
                "cpuCores": duration > 0 ? (end.cpuTime - start.cpuTime) / duration : 0,
                "mainThreadBusyPercent": duration > 0 ? (end.mainThreadCpuTime - start.mainThreadCpuTime) / duration * 100 : 0,
                "footprintMB": Double(end.footprint) / 1048576.0,
                "startUnixTime": startUnixTime,
                "endUnixTime": Date().timeIntervalSince1970
            ].merging(self.playingGifs(), uniquingKeysWith: { $1 }))
        })
    }

    private func segments() -> [PerfLabScrollSegment] {
        let speed = self.configuration.double("-PerfLabSpeed", 1.0)
        return [
            PerfLabScrollSegment(duration: 0.3, velocity: 0),
            PerfLabScrollSegment(duration: 3.0, velocity: 900 * speed),
            PerfLabScrollSegment(duration: 3.0, velocity: -900 * speed),
            PerfLabScrollSegment(duration: 3.0, velocity: 1600 * speed),
            PerfLabScrollSegment(duration: 0.3, velocity: 0)
        ]
    }

    private func measuredScroll(completion: @escaping ([String: Double]) -> Void) {
        guard let tableView = self.tableView, let contentView = self.window?.contentView else {
            completion([:])
            return
        }
        self.scrollToTop()
        let measurement = PerfLabScrollMeasurement(view: contentView, scrollView: tableView, segments: self.segments(), wheelSign: self.wheelSign, processMonitor: self.processMonitor, sampler: { [weak self] in
            return self?.playingGifs() ?? [:]
        })
        self.measurement = measurement
        measurement.run(completion: { [weak self] metrics in
            self?.measurement = nil
            completion(metrics)
        })
    }

    private func runScenario(_ scenario: String, completion: @escaping ([String: Double], [String: String]) -> Void) {
        let notes = ["decode": SoftwareVideoLayerFrameManager.usesHardwareDecoding ? "hw" : "sw"]
        self.openPanel { [weak self] in
            guard let self else {
                return
            }
            switch scenario {
            case "idle":
                self.idle(seconds: self.configuration.double("-PerfLabIdleSeconds", 10), completion: { metrics in
                    completion(metrics, notes)
                })
            case "scroll":
                self.detectWheelSign()
                self.measuredScroll(completion: { metrics in
                    completion(metrics, notes)
                })
            default:
                completion([:], ["error": "unknown scenario \(scenario)"])
            }
        }
    }
}
#endif
