#if DEBUG
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InlineStickerLayer
import PerfLab

public enum EmojiPanelLab {
    public static var fetchMode: InlineStickerItemLayer.FetchMode = .whileVisible
    private static var session: AnyObject?
    private static var didStart = false

    @discardableResult
    public static func startIfRequested<Context: AccountContextProtocol>(context: Context, outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "emoji-panel" else {
            return false
        }
        self.didStart = true
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 4.0), {
            self.start(context: context, configuration: configuration, completion: {
                if configuration.quitWhenDone {
                    NSApp.terminate(nil)
                }
            })
        })
        return true
    }

    public static func start<Context: AccountContextProtocol>(context: Context, configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        let session = EmojiPanelLabSession(context: context, configuration: configuration, completion: {
            EmojiPanelLab.session = nil
            completion()
        })
        self.session = session
        session.start()
    }
}

private final class EmojiPanelLabSession<Context: AccountContextProtocol> {
    private let context: Context
    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private let processMonitor = PerfLabProcessMonitor()
    private var pending: [(scenario: String, run: Int)] = []
    private var window: Window?
    private var controller: ViewController?
    private var tableViewGetter: (() -> TableView?)?
    private var measurement: PerfLabScrollMeasurement?
    private var wheelSign: Double = -1
    private var timer: SwiftSignalKit.Timer?
    private let disposable = MetaDisposable()

    init(context: Context, configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        self.context = context
        self.configuration = configuration
        self.completion = completion
        self.report = PerfLabReport(configuration: configuration)
    }

    func start() {
        InlineStickerItemLayer.usesSilhouetteShimmer = self.configuration.string("-PerfLabPlaceholder", "silhouette") == "silhouette"
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
            EmojiPanelLab.fetchMode = .whileVisible
            Queue.mainQueue().after(1.5, { [weak self] in
                self?.next()
            })
        }
    }

    private var tableView: TableView? {
        return self.tableViewGetter?()
    }

    private func openPanel(completion: @escaping () -> Void) {
        let frame = NSMakeRect(200, 200, self.configuration.double("-PerfLabWidth", 360), self.configuration.double("-PerfLabHeight", 520))
        let window = Window(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Emoji Panel Lab"
        window.isReleasedWhenClosed = false
        let controller: ViewController
        if self.configuration.string("-PerfLabPanel", "emoji") == "stickers" {
            let stickers = NStickersViewController(self.context)
            self.tableViewGetter = { [weak stickers] in stickers?.genericView.tableView }
            controller = stickers
        } else {
            let emoji = EmojiesController(self.context, mode: .emoji)
            self.tableViewGetter = { [weak emoji] in emoji?.genericView.tableView }
            controller = emoji
        }
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
        self.timer?.invalidate()
        self.timer = nil
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

    private func documentHeight() -> CGFloat {
        return self.tableView?.documentView?.frame.height ?? 0
    }

    private func waitForContent(deadline: Double, completion: @escaping () -> Void) {
        let ready = (self.tableView?.count ?? 0) > 10 && self.documentHeight() > self.configuration.double("-PerfLabMinContentHeight", 20000)
        if ready || CFAbsoluteTimeGetCurrent() > deadline {
            Queue.mainQueue().after(1.0, completion)
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
        let after = tableView.contentView.bounds.minY
        self.wheelSign = after > before ? -1 : 1
        self.scrollToTop()
    }

    private func visibleEmojiLayers() -> [InlineStickerItemLayer] {
        guard let tableView = self.tableView else {
            return []
        }
        var result: [InlineStickerItemLayer] = []
        let range = tableView.visibleRows()
        guard range.location != NSNotFound else {
            return []
        }
        for row in range.location ..< range.location + range.length {
            guard let view = tableView.viewNecessary(at: row), let layer = view.layer else {
                continue
            }
            var stack: [CALayer] = [layer]
            while let current = stack.popLast() {
                if let emoji = current as? InlineStickerItemLayer {
                    result.append(emoji)
                } else {
                    stack.append(contentsOf: current.sublayers ?? [])
                }
            }
        }
        return result
    }

    private func loadSample() -> [String: Double] {
        let all = self.visibleEmojiLayers()
        let layers = all.filter { $0.isVisibleForFetching }
        let placeholders = layers.filter { !$0.isContentLoaded }.count
        return [
            "visibleLayers": Double(all.count),
            "playingLayers": Double(all.filter { $0.isPlayable == true }.count),
            "visibleEmoji": Double(layers.count),
            "visiblePlaceholders": Double(placeholders),
            "visibleLoadedPercent": layers.isEmpty ? 100 : Double(layers.count - placeholders) / Double(layers.count) * 100
        ]
    }

    private func panelFiles() -> [TelegramMediaFile] {
        guard let tableView = self.tableView else {
            return []
        }
        var files: [TelegramMediaFile] = []
        for index in 0 ..< tableView.count {
            if let item = tableView.item(at: index) as? EmojiesSectionRowItem {
                for entry in item.items {
                    if let packItem = entry.item {
                        files.append(packItem.file._parse())
                    }
                }
            }
        }
        return files
    }

    private func dropEmojiCaches(files: [TelegramMediaFile], completion: @escaping (Int) -> Void) {
        let mediaBox = self.context.account.postbox.mediaBox
        var ids: [MediaResourceId] = []
        for file in files {
            ids.append(file.resource.id)
            for representation in file.previewRepresentations {
                ids.append(representation.resource.id)
            }
        }
        let prefixes = Set(ids.map { $0.stringRepresentation + ":" })
        self.disposable.set((mediaBox.removeCachedResources(ids) |> deliverOnMainQueue).start(completed: {
            let cacheDirectory = mediaBox.basePath + "/cache"
            var removed = 0
            for name in (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory)) ?? [] {
                if let separator = name.firstIndex(of: ":"), prefixes.contains(String(name[...separator])) {
                    try? FileManager.default.removeItem(atPath: cacheDirectory + "/" + name)
                    removed += 1
                }
            }
            purgeImageCachesForMemoryPressure()
            completion(removed)
        }))
    }

    private func segments() -> [PerfLabScrollSegment] {
        let speed = self.configuration.double("-PerfLabSpeed", 1.0)
        return [
            PerfLabScrollSegment(duration: 0.3, velocity: 0),
            PerfLabScrollSegment(duration: 4.0, velocity: 1200 * speed),
            PerfLabScrollSegment(duration: 3.0, velocity: 2800 * speed),
            PerfLabScrollSegment(duration: 3.0, velocity: -2000 * speed),
            PerfLabScrollSegment(duration: 3.0, velocity: 900 * speed),
            PerfLabScrollSegment(duration: 0.3, velocity: 0)
        ]
    }

    private func measuredScroll(completion: @escaping ([String: Double]) -> Void) {
        guard let tableView = self.tableView, let window = self.window, let contentView = window.contentView else {
            completion([:])
            return
        }
        self.scrollToTop()
        let measurement = PerfLabScrollMeasurement(view: contentView, scrollView: tableView, segments: self.segments(), wheelSign: self.wheelSign, processMonitor: self.processMonitor, sampler: { [weak self] in
            return self?.loadSample() ?? [:]
        })
        self.measurement = measurement
        measurement.run(completion: { [weak self] metrics in
            self?.measurement = nil
            completion(metrics)
        })
    }

    private func preload(offset: CGFloat, until maxOffset: CGFloat, completion: @escaping () -> Void) {
        guard let tableView = self.tableView else {
            completion()
            return
        }
        tableView.clipView.scroll(to: NSPoint(x: 0, y: offset))
        tableView.reflectScrolledClipView(tableView.clipView)
        let deadline = CFAbsoluteTimeGetCurrent() + 4.0
        func check() {
            let sample = self.loadSample()
            if (sample["visiblePlaceholders"] ?? 0) == 0 || CFAbsoluteTimeGetCurrent() > deadline {
                let nextOffset = offset + tableView.frame.height * 0.9
                if nextOffset > maxOffset {
                    self.scrollToTop()
                    Queue.mainQueue().after(1.0, completion)
                } else {
                    self.preload(offset: nextOffset, until: maxOffset, completion: completion)
                }
            } else {
                Queue.mainQueue().after(0.1, check)
            }
        }
        Queue.mainQueue().after(0.15, check)
    }

    private func settle(start: Double, completion: @escaping ([String: Double]) -> Void) {
        let sample = self.loadSample()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        if (sample["visiblePlaceholders"] ?? 0) == 0 || elapsed > 20.0 {
            completion(["settleSeconds": elapsed, "placeholdersAfterSettle": sample["visiblePlaceholders"] ?? 0])
        } else {
            Queue.mainQueue().after(0.1, { [weak self] in
                self?.settle(start: start, completion: completion)
            })
        }
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
            ].merging(self.loadSample(), uniquingKeysWith: { $1 }))
        })
    }

    private func panelViewCount() -> Int {
        func count(_ view: NSView) -> Int {
            return view.subviews.reduce(1) { $0 + count($1) }
        }
        return self.tableView.map(count) ?? 0
    }

    private func maxScrollOffset() -> CGFloat {
        var offset: Double = 0
        var maxOffset: Double = 0
        for segment in self.segments() {
            offset += segment.duration * segment.velocity
            maxOffset = max(maxOffset, offset)
        }
        return CGFloat(maxOffset) + (self.tableView?.frame.height ?? 0)
    }

    private func runScenario(_ scenario: String, completion: @escaping ([String: Double], [String: String]) -> Void) {
        switch scenario {
        case "warm", "idle":
            EmojiPanelLab.fetchMode = .whileVisible
            self.openPanel { [weak self] in
                guard let self else {
                    return
                }
                self.detectWheelSign()
                self.preload(offset: 0, until: self.maxScrollOffset(), completion: { [weak self] in
                    guard let self else {
                        return
                    }
                    let views = ["panelViews": Double(self.panelViewCount())]
                    if scenario == "idle" {
                        self.idle(seconds: self.configuration.double("-PerfLabIdleSeconds", 8), completion: { metrics in
                            completion(metrics.merging(views, uniquingKeysWith: { $1 }), [:])
                        })
                    } else {
                        self.measuredScroll(completion: { metrics in
                            completion(metrics.merging(views, uniquingKeysWith: { $1 }), ["wheelSign": "\(self.wheelSign)"])
                        })
                    }
                })
            }
        case "shimmer", "cold", "shimmeridle":
            EmojiPanelLab.fetchMode = .whileVisible
            self.openPanel { [weak self] in
                guard let self else {
                    return
                }
                let files = self.panelFiles()
                self.closePanel()
                self.dropEmojiCaches(files: files, completion: { [weak self] removedRepresentations in
                    guard let self else {
                        return
                    }
                    EmojiPanelLab.fetchMode = scenario == "cold" ? .whileVisible : .never
                    self.openPanel { [weak self] in
                        guard let self else {
                            return
                        }
                        if scenario == "shimmeridle" {
                            self.idle(seconds: self.configuration.double("-PerfLabIdleSeconds", 8), completion: { metrics in
                                completion(metrics, ["files": "\(files.count)"])
                            })
                            return
                        }
                        self.detectWheelSign()
                        self.measuredScroll(completion: { [weak self] metrics in
                            guard let self else {
                                return
                            }
                            let notes = ["files": "\(files.count)", "removedRepresentations": "\(removedRepresentations)", "wheelSign": "\(self.wheelSign)"]
                            if scenario == "cold" {
                                self.settle(start: CFAbsoluteTimeGetCurrent(), completion: { settleMetrics in
                                    completion(metrics.merging(settleMetrics, uniquingKeysWith: { $1 }), notes)
                                })
                            } else {
                                completion(metrics, notes)
                            }
                        })
                    }
                })
            }
        default:
            completion([:], ["error": "unknown scenario \(scenario)"])
        }
    }
}
#endif
