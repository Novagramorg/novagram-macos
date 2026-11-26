#if DEBUG
import Cocoa
import ImageIO
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import PerfLab
import PeerMediaUI
import InlineMediaGrid
import ChatHistoryModel
import GeneralRows

public enum PeerMediaLab {
    private static var session: AnyObject?
    private static var didStart = false

    @discardableResult
    public static func startIfRequested(context: any AccountContextProtocol, outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "peer-media" else {
            return false
        }
        self.didStart = true
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 4.0), {
            let session = PeerMediaLabSession(context: context, configuration: configuration, completion: {
                PeerMediaLab.session = nil
                if configuration.quitWhenDone {
                    NSApp.terminate(nil)
                }
            })
            PeerMediaLab.session = session
            session.start()
        })
        return true
    }
}

private struct PeerMediaLabCell {
    let id: MessageId
    let modelRect: CGRect
    let windowRect: CGRect
    let isGif: Bool
    let hasImage: Bool
}

private final class PeerMediaLabSession {
    private let context: any AccountContextProtocol
    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private let processMonitor = PerfLabProcessMonitor()
    private var controller: ViewController?
    private weak var mediaTable: TableView?
    private weak var outerTable: TableView?
    private var loadDisposable: Disposable?
    private var wheelSign: Double = -1
    private var notes: [String: String] = [:]
    private var measurement: PerfLabScrollMeasurement?
    private var beforeMerge: [MessageId: CGPoint]?
    private var jumpMerges = 0
    private var jumpCells = 0
    private var maxBlank = 0
    private var maxMissingRows = 0
    private var seenMessages = Set<MessageId>()
    private var jumpLog: [String] = []
    private var jumpDetails: [String] = []
    private var rowsBeforeMerge: [AnyHashable: String] = [:]

    init(context: any AccountContextProtocol, configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        self.context = context
        self.configuration = configuration
        self.completion = completion
        self.report = PerfLabReport(configuration: configuration)
    }

    func start() {
        let context = self.context
        let username = self.configuration.string("-PerfLabChannel", "")
        let title = self.configuration.string("-PerfLabPeerTitle", "Код.ру")
        let peerSignal: Signal<PeerId?, NoError>
        if !username.isEmpty {
            peerSignal = context.engine.peers.resolvePeerByName(name: username, referrer: nil)
            |> mapToSignal { result -> Signal<PeerId?, NoError> in
                if case let .result(peer) = result {
                    return .single(peer?.id)
                }
                return .complete()
            }
            |> take(1)
        } else {
            peerSignal = context.engine.contacts.searchLocalPeers(query: title)
            |> map { peers -> PeerId? in
                return peers.first(where: { $0.peer?._asPeer().isChannel == true })?.peerId ?? peers.first?.peerId
            }
            |> take(1)
        }
        let peer: Signal<Peer?, NoError> = peerSignal |> mapToSignal { peerId -> Signal<Peer?, NoError> in
            guard let peerId else {
                return .single(nil)
            }
            return context.account.postbox.loadedPeerWithId(peerId) |> map(Optional.init) |> take(1)
        }
        self.loadDisposable = (peer |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self else {
                return
            }
            guard let peer else {
                self.report.add(scenario: "open", run: 0, metrics: [:], notes: ["error": "peer not found"])
                self.finish()
                return
            }
            self.notes["peer"] = username.isEmpty ? title : username
            self.open(peer: peer)
        })
    }

    private func makeController<C: AccountContextProtocol>(context: C, peer: Peer) -> ViewController {
        return PeerInfoController(context: context, peer: peer)
    }

    private func open(peer: Peer) {
        let window = self.context.window
        let width = self.configuration.double("-PerfLabWindowWidth", 0)
        let height = self.configuration.double("-PerfLabWindowHeight", 0)
        if width > 0, height > 0 {
            window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - CGFloat(height), width: CGFloat(width), height: CGFloat(height)), display: true)
        }
        self.notes["window"] = "\(Int(window.frame.width))x\(Int(window.frame.height))"
        let controller = self.makeController(context: self.context, peer: peer)
        self.controller = controller
        self.context.bindings.rootNavigation().push(controller)
        self.waitForGrid(attempts: 120)
    }

    private func waitForGrid(attempts: Int) {
        if let media = PeerMediaGridDebug.tables.allObjects.first(where: { $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }), media.count > 4, let outer = self.enclosingTable(of: media) {
            self.mediaTable = media
            self.outerTable = outer
            self.installMergeHooks()
            if let item = (0 ..< media.count).lazy.compactMap({ media.item(at: $0) as? PeerPhotosMonthItem }).first {
                self.notes["columns"] = "\(item.items.count)"
            }
            Queue.mainQueue().after(self.configuration.double("-PerfLabOpenWait", 3.0), { [weak self] in
                self?.calibrate(completion: {
                    self?.runScenarios(self?.configuration.scenarios ?? [])
                })
            })
            return
        }
        guard attempts > 0 else {
            self.report.add(scenario: "open", run: 0, metrics: [:], notes: ["error": "media grid not found"])
            self.finish()
            return
        }
        Queue.mainQueue().after(0.25, { [weak self] in
            self?.waitForGrid(attempts: attempts - 1)
        })
    }

    private func enclosingTable(of media: TableView) -> TableView? {
        var view = media.superview
        while let current = view {
            if let table = current as? TableView, table !== media {
                return table
            }
            view = current.superview
        }
        return nil
    }

    private func finish() {
        PeerMediaGridDebug.willMerge = nil
        PeerMediaGridDebug.didMerge = nil
        let url = self.report.write()
        NSLog("PerfLab report written to %@", url?.path ?? "nil")
        self.completion()
    }

    private func installMergeHooks() {
        PeerMediaGridDebug.willMerge = { [weak self] table in
            guard let self, table === self.mediaTable else {
                return
            }
            self.beforeMerge = self.positions(table)
            var rows: [AnyHashable: String] = [:]
            for index in 0 ..< table.count {
                if let row = table.item(at: index) as? PeerPhotosMonthItem {
                    rows[row.stableId] = row.items.map { "\($0.id.id)" + ($0.id.namespace != 0 ? "n\($0.id.namespace)" : "") }.joined(separator: ",") + " ts\(row.items.first?.timestamp ?? 0)-\(row.items.last?.timestamp ?? 0)"
                }
            }
            self.rowsBeforeMerge = rows
        }
        PeerMediaGridDebug.didMerge = { [weak self] table in
            guard let self, table === self.mediaTable, let before = self.beforeMerge else {
                return
            }
            self.beforeMerge = nil
            let after = self.positions(table)
            var movedRows = Set<Int>()
            var changed = 0
            var horizontal = 0
            var vertical = 0
            var gone = 0
            for (id, point) in before {
                if let updated = after[id] {
                    if abs(updated.x - point.x) > 0.5 {
                        horizontal += 1
                        if let row = (0 ..< table.count).first(where: { (table.item(at: $0) as? PeerPhotosMonthItem)?.items.contains(where: { $0.id == id }) == true }) {
                            if !movedRows.contains(row), let item = table.item(at: row) as? PeerPhotosMonthItem {
                                let after = item.items.map { "\($0.id.id)" + ($0.id.namespace != 0 ? "n\($0.id.namespace)" : "") }.joined(separator: ",")
                                let ids = item.items.map { "\($0.id.id)" + ($0.id.namespace != 0 ? "n\($0.id.namespace)" : "") }
                                let before = self.rowsBeforeMerge.values.filter { value in ids.contains(where: { value.components(separatedBy: " ")[0].components(separatedBy: ",").contains($0) }) }.joined(separator: " / ")
                                let previousRow = row > 0 ? (table.item(at: row - 1) as? PeerPhotosMonthItem).map { $0.items.map { "\($0.id.id)" }.joined(separator: ",") } ?? "\(type(of: table.item(at: row - 1)))" : "-"
                                self.jumpDetails.append("row\(row) before[\(before)] after[\(after)] prev[\(previousRow)]")
                            }
                            movedRows.insert(row)
                        }
                    } else if abs(updated.y - point.y) > 0.5 {
                        vertical += 1
                    }
                    if abs(updated.x - point.x) > 0.5 || abs(updated.y - point.y) > 0.5 {
                        changed += 1
                    }
                } else {
                    gone += 1
                    changed += 1
                }
            }
            if changed > 0 {
                self.jumpMerges += 1
                self.jumpCells += changed
                self.jumpLog.append("h\(horizontal)/v\(vertical)/gone\(gone)/of\(before.count) rows\(table.count) off\(Int(table.contentView.bounds.minY)) movedRows\(movedRows.sorted()) [\(PeerMediaGridDebug.lastMerge)]")
            }
        }
    }

    private func positions(_ table: TableView) -> [MessageId: CGPoint] {
        let offset = table.contentView.bounds.minY
        var result: [MessageId: CGPoint] = [:]
        for cell in self.visibleCells(table) where !cell.isGif {
            result[cell.id] = CGPoint(x: cell.modelRect.minX, y: cell.modelRect.minY - offset)
        }
        return result
    }

    private func visibleCells(_ table: TableView) -> [PeerMediaLabCell] {
        guard let window = table.window, let outer = self.outerTable else {
            return []
        }
        let clip = table.contentView.bounds
        let windowVisible = outer.convert(outer.bounds, to: nil).intersection(table.convert(table.bounds, to: nil))
        let range = table.visibleRows()
        guard range.location != NSNotFound, range.length > 0 else {
            return []
        }
        _ = window
        var result: [PeerMediaLabCell] = []
        for row in range.location ..< range.location + range.length {
            guard let item = table.item(at: row) as? PeerPhotosMonthItem, let view = item.view, let container = view.subviews.first else {
                continue
            }
            let rowRect = table.rectOf(item: item)
            for case let cell as MediaCell in container.subviews {
                guard let layout = cell.layoutItem else {
                    continue
                }
                let modelRect = cell.frame.offsetBy(dx: rowRect.minX + container.frame.minX, dy: rowRect.minY + container.frame.minY)
                guard modelRect.intersects(clip) else {
                    continue
                }
                let windowRect = cell.convert(cell.bounds, to: nil)
                guard windowRect.intersects(windowVisible) else {
                    continue
                }
                let hasImage = (cell.subviews.first as? TransformImageView)?.image != nil
                result.append(PeerMediaLabCell(id: layout.id, modelRect: modelRect, windowRect: windowRect, isGif: cell is MediaGifCell, hasImage: hasImage))
            }
        }
        return result
    }

    private func missingRowViews() -> Int {
        guard let table = self.mediaTable else {
            return 0
        }
        let range = table.visibleRows()
        guard range.location != NSNotFound, range.length > 0 else {
            return 0
        }
        var missing = 0
        for row in range.location ..< range.location + range.length {
            if let item = table.item(at: row) as? PeerPhotosMonthItem, item.view?.superview == nil {
                missing += 1
            }
        }
        return missing
    }

    private func outerMetrics() -> [String: Double] {
        return [
            "outerOffset": Double(self.outerTable?.contentView.bounds.minY ?? 0),
            "outerMax": Double(self.outerMaxOffset),
            "handoff": Double(self.handoffOffset() ?? -1),
            "mediaOffset": Double(self.mediaTable?.contentView.bounds.minY ?? 0)
        ]
    }

    private func blankStats() -> (cells: Int, blank: Int) {
        guard let table = self.mediaTable else {
            return (0, 0)
        }
        let cells = self.visibleCells(table).filter { !$0.isGif }
        let blank = cells.filter { !$0.hasImage }.count
        return (cells.count, blank)
    }

    private func eventPoint() -> NSPoint? {
        guard let outer = self.outerTable else {
            return nil
        }
        return outer.convert(NSMakePoint(outer.bounds.midX, outer.bounds.midY), to: nil)
    }

    private func eventTarget() -> NSResponder? {
        guard let window = self.outerTable?.window, let content = window.contentView, let point = self.eventPoint() else {
            return nil
        }
        let local = content.superview?.convert(point, from: nil) ?? point
        return content.hitTest(local) ?? self.outerTable
    }

    private func post(delta: Double) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(delta), wheel2: 0, wheel3: 0), let nsEvent = NSEvent(cgEvent: event) else {
            return
        }
        self.eventTarget()?.scrollWheel(with: nsEvent)
    }

    private func reset(completion: @escaping () -> Void) {
        self.mediaTable?.scroll(to: .upOffset(false, 0))
        self.outerTable?.scroll(to: .up(false))
        Queue.mainQueue().after(1.0, completion)
    }

    private func calibrate(completion: @escaping () -> Void) {
        self.reset(completion: { [weak self] in
            guard let self, let outer = self.outerTable else {
                completion()
                return
            }
            let before = outer.contentView.bounds.minY
            self.post(delta: -300)
            Queue.mainQueue().after(0.5, { [weak self] in
                guard let self, let outer = self.outerTable else {
                    completion()
                    return
                }
                self.wheelSign = outer.contentView.bounds.minY > before ? -1 : 1
                self.notes["wheelSign"] = "\(self.wheelSign)"
                self.reset(completion: completion)
            })
        })
    }

    private func handoffOffset() -> CGFloat? {
        guard let media = self.mediaTable, let document = self.outerTable?.documentView else {
            return nil
        }
        var view: NSView? = media
        while let current = view, current.superview !== document {
            view = current.superview
        }
        guard let block = view else {
            return nil
        }
        return max(0, block.frame.minY - 64)
    }

    private var outerMaxOffset: CGFloat {
        guard let outer = self.outerTable else {
            return 0
        }
        return max(0, outer.documentSize.height - outer.frame.height)
    }

    private func drive(distance: Double, speed: Double, completion: @escaping () -> Void) {
        guard let media = self.mediaTable else {
            completion()
            return
        }
        let segments = [PerfLabScrollSegment(duration: abs(distance) / speed, velocity: distance > 0 ? speed : -speed)]
        let measurement = PerfLabScrollMeasurement(view: media, scrollView: media, segments: segments, wheelSign: self.wheelSign, processMonitor: self.processMonitor, eventTarget: { [weak self] in
            return self?.eventTarget()
        })
        self.measurement = measurement
        measurement.run(completion: { [weak self] _ in
            self?.measurement = nil
            completion()
        })
    }

    private func enterMedia(completion: @escaping () -> Void) {
        self.reset(completion: { [weak self] in
            guard let self else {
                return
            }
            self.drive(distance: Double(self.outerMaxOffset) + 40, speed: 12000, completion: {
                Queue.mainQueue().after(1.0, completion)
            })
        })
    }

    private func runScenarios(_ scenarios: [String]) {
        guard let scenario = scenarios.first else {
            self.finish()
            return
        }
        let rest = Array(scenarios.dropFirst())
        let next: () -> Void = { [weak self] in
            Queue.mainQueue().after(1.5, {
                self?.runScenarios(rest)
            })
        }
        let speed = self.configuration.double("-PerfLabScrollSpeed", 2400)
        let duration = self.configuration.double("-PerfLabScrollDuration", 6)
        switch scenario {
        case "enter":
            self.runEnter(index: 0, completion: next)
        case "scroll":
            self.runPasses(name: "scroll", index: 0, speed: speed, duration: duration, completion: next)
        case "fling":
            self.runPasses(name: "fling", index: 0, speed: self.configuration.double("-PerfLabFlingSpeed", 8000), duration: self.configuration.double("-PerfLabFlingDuration", 3), completion: next)
        case "deep":
            self.runPasses(name: "deep", index: 1, speed: self.configuration.double("-PerfLabDeepSpeed", 3000), duration: self.configuration.double("-PerfLabDeepDuration", 20), completion: next)
        case "settle":
            self.enterMedia(completion: { [weak self] in
                self?.runSettle(index: 0, results: [], completion: next)
            })
        case "verify":
            self.enterMedia(completion: { [weak self] in
                self?.runVerify(index: 0, completion: next)
            })
        default:
            self.report.add(scenario: scenario, run: 0, metrics: [:], notes: ["error": "unknown scenario"])
            next()
        }
    }

    private func passNotes() -> [String: String] {
        var notes = self.notes
        if !self.jumpLog.isEmpty {
            notes["jumps"] = self.jumpLog.joined(separator: "; ")
        }
        if !self.jumpDetails.isEmpty {
            notes["jumpDetails"] = self.jumpDetails.prefix(8).joined(separator: " | ")
        }
        return notes
    }

    private func resetCounters() {
        PeerMediaGridDebug.reset()
        self.jumpMerges = 0
        self.jumpCells = 0
        self.maxBlank = 0
        self.maxMissingRows = 0
        self.seenMessages.removeAll()
        self.jumpLog = []
        self.jumpDetails = []
    }

    private func counterMetrics() -> [String: Double] {
        return [
            "merges": Double(PeerMediaGridDebug.merges),
            "mergeMs": PeerMediaGridDebug.mergeSeconds * 1000,
            "worstMergeMs": PeerMediaGridDebug.worstMergeSeconds * 1000,
            "locationChanges": Double(PeerMediaGridDebug.locationChanges),
            "rowViewsCreated": Double(PeerMediaGridDebug.rowViewsCreated),
            "cellsCreated": Double(PeerMediaGridDebug.cellsCreated),
            "rowsSet": Double(PeerMediaGridDebug.rowsSet),
            "jumpMerges": Double(self.jumpMerges),
            "jumpCells": Double(self.jumpCells),
            "maxBlank": Double(self.maxBlank),
            "maxMissingRows": Double(self.maxMissingRows),
            "distinctMessages": Double(self.seenMessages.count)
        ]
    }

    private func measure(segments: [PerfLabScrollSegment], completion: @escaping ([String: Double]) -> Void) {
        guard let media = self.mediaTable else {
            completion([:])
            return
        }
        self.resetCounters()
        let measurement = PerfLabScrollMeasurement(view: media, scrollView: media, segments: segments, wheelSign: self.wheelSign, processMonitor: self.processMonitor, sampleInterval: 3, sampler: { [weak self] in
            guard let self else {
                return [:]
            }
            let stats = self.blankStats()
            self.maxBlank = max(self.maxBlank, stats.blank)
            let missing = self.missingRowViews()
            self.maxMissingRows = max(self.maxMissingRows, missing)
            var atBottom = 0.0
            if let media = self.mediaTable {
                for cell in self.visibleCells(media) {
                    self.seenMessages.insert(cell.id)
                }
                let maxOffset = media.documentSize.height - media.frame.height
                atBottom = maxOffset > 0 && media.contentView.bounds.minY >= maxOffset - 1 ? 100 : 0
            }
            return ["cells": Double(stats.cells), "blank": Double(stats.blank), "rows": Double(self.mediaTable?.count ?? 0), "missingRows": Double(missing), "atBottom": atBottom]
        }, eventTarget: { [weak self] in
            return self?.eventTarget()
        })
        self.measurement = measurement
        measurement.run(completion: { [weak self] metrics in
            guard let self else {
                return
            }
            self.measurement = nil
            var metrics = metrics
            for (key, value) in self.counterMetrics() {
                metrics[key] = value
            }
            if let cells = metrics["avg_cells"], cells > 0 {
                metrics["blankPercent"] = (metrics["avg_blank"] ?? 0) / cells * 100
            }
            for (key, value) in self.outerMetrics() {
                metrics[key] = value
            }
            completion(metrics)
        })
    }

    private func runEnter(index: Int, completion: @escaping () -> Void) {
        let runs = self.configuration.runs
        guard index < runs else {
            completion()
            return
        }
        let speed = self.configuration.double("-PerfLabScrollSpeed", 2400)
        self.reset(completion: { [weak self] in
            guard let self else {
                return
            }
            let distance = Double(self.outerMaxOffset) + self.configuration.double("-PerfLabEnterExtra", 2400)
            let segments = [
                PerfLabScrollSegment(duration: 0.2, velocity: 0),
                PerfLabScrollSegment(duration: distance / speed, velocity: speed),
                PerfLabScrollSegment(duration: 0.3, velocity: 0)
            ]
            self.measure(segments: segments, completion: { [weak self] metrics in
                guard let self else {
                    return
                }
                var metrics = metrics
                metrics["outerMaxOffset"] = Double(self.outerMaxOffset)
                self.report.add(scenario: "enter", run: index, metrics: metrics, notes: self.passNotes())
                self.runEnter(index: index + 1, completion: completion)
            })
        })
    }

    private func runPasses(name: String, index: Int, speed: Double, duration: Double, completion: @escaping () -> Void) {
        guard index <= self.configuration.runs else {
            completion()
            return
        }
        self.enterMedia(completion: { [weak self] in
            guard let self else {
                return
            }
            let segments = [
                PerfLabScrollSegment(duration: 0.2, velocity: 0),
                PerfLabScrollSegment(duration: duration, velocity: speed),
                PerfLabScrollSegment(duration: duration, velocity: -speed),
                PerfLabScrollSegment(duration: 0.3, velocity: 0)
            ]
            self.measure(segments: segments, completion: { [weak self] metrics in
                guard let self else {
                    return
                }
                let scenario = index == 0 ? "\(name)-first" : name
                self.report.add(scenario: scenario, run: max(0, index - 1), metrics: metrics, notes: self.passNotes())
                self.runPasses(name: name, index: index + 1, speed: speed, duration: duration, completion: completion)
            })
        })
    }

    private func waitForSettle(started: Double, timeout: Double, completion: @escaping (Double?, Int) -> Void) {
        let stats = self.blankStats()
        let elapsed = CACurrentMediaTime() - started
        if stats.cells > 0 && stats.blank == 0 {
            completion(elapsed, 0)
            return
        }
        if elapsed > timeout {
            completion(nil, stats.blank)
            return
        }
        Queue.mainQueue().after(1.0 / 60.0, { [weak self] in
            self?.waitForSettle(started: started, timeout: timeout, completion: completion)
        })
    }

    private func runSettle(index: Int, results: [(Double?, Int, Int)], completion: @escaping () -> Void) {
        let steps = Int(self.configuration.double("-PerfLabSettleSteps", 8))
        guard index < steps else {
            let times = results.compactMap { $0.0 }.sorted()
            let atStop = results.map { Double($0.1) }.sorted()
            var metrics: [String: Double] = [
                "steps": Double(results.count),
                "unsettled": Double(results.filter { $0.0 == nil }.count),
                "blankLeft": Double(results.reduce(0, { $0 + $1.2 }))
            ]
            if !times.isEmpty {
                metrics["settleMedianMs"] = times[times.count / 2] * 1000
                metrics["settleMaxMs"] = (times.last ?? 0) * 1000
                metrics["settleMeanMs"] = times.reduce(0, +) / Double(times.count) * 1000
            }
            if !atStop.isEmpty {
                metrics["blankAtStopMedian"] = atStop[atStop.count / 2]
                metrics["blankAtStopMean"] = atStop.reduce(0, +) / Double(atStop.count)
            }
            self.report.add(scenario: "settle", run: 0, metrics: metrics, notes: self.notes)
            completion()
            return
        }
        let jump = self.configuration.double("-PerfLabSettleJump", 2500)
        let direction: Double = index < steps / 2 ? 1 : -1
        self.drive(distance: jump * direction, speed: 15000, completion: { [weak self] in
            guard let self else {
                return
            }
            let atStop = self.blankStats().blank
            self.waitForSettle(started: CACurrentMediaTime(), timeout: 10, completion: { [weak self] time, left in
                guard let self else {
                    return
                }
                self.report.add(scenario: "settle-step", run: index, metrics: ["settleMs": (time ?? -1) * 1000, "blankAtStop": Double(atStop), "blankLeft": Double(left), "mediaOffset": Double(self.mediaTable?.contentView.bounds.minY ?? 0)], notes: [:])
                Queue.mainQueue().after(0.5, {
                    self.runSettle(index: index + 1, results: results + [(time, atStop, left)], completion: completion)
                })
            })
        })
    }

    private func runVerify(index: Int, completion: @escaping () -> Void) {
        let offsets = self.configuration.string("-PerfLabVerifyOffsets", "0,2500,6000,12000,20000").split(separator: ",").compactMap { Double($0) }
        guard index < offsets.count, let media = self.mediaTable else {
            completion()
            return
        }
        let target = CGFloat(offsets[index])
        let maxOffset = max(0, media.documentSize.height - media.frame.height)
        media.clipView.scroll(to: NSMakePoint(0, min(target, maxOffset)))
        media.reflectScrolledClipView(media.clipView)
        self.waitForQuiet(started: CACurrentMediaTime(), lastMerges: PeerMediaGridDebug.merges, quietSince: CACurrentMediaTime(), completion: { [weak self] in
            guard let self, let media = self.mediaTable else {
                return
            }
            if let outer = self.outerTable, let handoff = self.handoffOffset(), outer.contentView.bounds.minY != handoff {
                outer.clipView.scroll(to: NSMakePoint(0, handoff))
                outer.reflectScrolledClipView(outer.clipView)
            }
            if index == 0 || media.contentView.bounds.minY < target - 1, target <= media.documentSize.height - media.frame.height {
                media.clipView.scroll(to: NSMakePoint(0, target))
                media.reflectScrolledClipView(media.clipView)
            }
            self.waitForQuiet(started: CACurrentMediaTime(), lastMerges: PeerMediaGridDebug.merges, quietSince: CACurrentMediaTime(), completion: { [weak self] in
                guard let self else {
                    return
                }
                var (metrics, notes) = self.checkInvariants()
                metrics["targetOffset"] = Double(target)
                for (key, value) in self.outerMetrics() {
                    metrics[key] = value
                }
                if let name = self.capture(name: "verify\(index)") {
                    notes["capture"] = name
                }
                self.report.add(scenario: "verify", run: index, metrics: metrics, notes: notes)
                self.runVerify(index: index + 1, completion: completion)
            })
        })
    }

    private func waitForQuiet(started: Double, lastMerges: Int, quietSince: Double, completion: @escaping () -> Void) {
        let now = CACurrentMediaTime()
        let merges = PeerMediaGridDebug.merges
        let quietSince = merges != lastMerges ? now : quietSince
        let stats = self.blankStats()
        if (stats.blank == 0 && now - quietSince > 1.5) || now - started > 20 {
            completion()
            return
        }
        Queue.mainQueue().after(0.1, { [weak self] in
            self?.waitForQuiet(started: started, lastMerges: merges, quietSince: quietSince, completion: completion)
        })
    }

    private func checkInvariants() -> ([String: Double], [String: String]) {
        guard let table = self.mediaTable else {
            return ([:], ["error": "no table"])
        }
        let timeDifference = Int32(self.context.timeDifference)
        var problems: [String] = []
        var seen = Set<MessageId>()
        var duplicates = 0
        var orderViolations = 0
        var monthViolations = 0
        var missingHeaders = 0
        var partialRows = 0
        var rows = 0
        var messages = 0
        var previous: Message?
        var previousMonth: Int64?
        var previousRowMonth: Int64?
        var previousRowCount: Int?
        var sawHeader = false
        var previousRowWasFirst = false
        var columns = 0
        for index in 0 ..< table.count {
            let item = table.item(at: index)
            if item is PeerMediaDateItem {
                sawHeader = true
                continue
            }
            guard let row = item as? PeerPhotosMonthItem else {
                continue
            }
            rows += 1
            columns = max(columns, row.items.count)
            let rowMonth = row.items.first.map { mediaDateId(for: $0.timestamp - timeDifference) }
            if let rowMonth, let previousRowMonth, rowMonth != previousRowMonth, !sawHeader {
                missingHeaders += 1
                problems.append("no header before row \(index)")
            }
            if let rowMonth, let previousRowMonth, rowMonth == previousRowMonth, let previousRowCount, previousRowCount < columns, !(previousRowWasFirst && rows == 2) {
                partialRows += 1
                problems.append("partial row before row \(index) in the same month")
            }
            previousRowWasFirst = previousRowMonth != rowMonth || rows == 1
            sawHeader = false
            for message in row.items {
                messages += 1
                if !seen.insert(message.id).inserted {
                    duplicates += 1
                    problems.append("duplicate \(message.id.id)")
                }
                let month = mediaDateId(for: message.timestamp - timeDifference)
                if let rowMonth, month != rowMonth {
                    monthViolations += 1
                    problems.append("month mix in row \(index)")
                }
                if let previous, previous.timestamp < message.timestamp {
                    orderViolations += 1
                    problems.append("order \(previous.id.id)->\(message.id.id)")
                }
                previous = message
                previousMonth = month
            }
            previousRowMonth = rowMonth
            previousRowCount = row.items.count
        }
        _ = previousMonth
        var cellMismatches = 0
        let range = table.visibleRows()
        if range.location != NSNotFound {
            for index in range.location ..< range.location + range.length {
                guard let row = table.item(at: index) as? PeerPhotosMonthItem, let view = row.view, let container = view.subviews.first else {
                    continue
                }
                let cells = container.subviews.compactMap { $0 as? MediaCell }
                if cells.count != row.items.count {
                    cellMismatches += 1
                    problems.append("row \(index) has \(cells.count) cells for \(row.items.count) items")
                    continue
                }
                for (cell, message) in zip(cells, row.items) where cell.layoutItem?.id != message.id {
                    cellMismatches += 1
                    problems.append("row \(index) cell shows \(cell.layoutItem?.id.id ?? -1) instead of \(message.id.id)")
                }
            }
        }
        let blank = self.blankStats()
        let metrics: [String: Double] = [
            "rows": Double(rows),
            "messages": Double(messages),
            "duplicates": Double(duplicates),
            "orderViolations": Double(orderViolations),
            "monthViolations": Double(monthViolations),
            "missingHeaders": Double(missingHeaders),
            "partialRows": Double(partialRows),
            "cellMismatches": Double(cellMismatches),
            "visibleCells": Double(blank.cells),
            "blankAfterSettle": Double(blank.blank),
            "violations": Double(duplicates + orderViolations + monthViolations + missingHeaders + partialRows + cellMismatches + blank.blank)
        ]
        var notes: [String: String] = [:]
        if !problems.isEmpty {
            notes["problems"] = problems.prefix(12).joined(separator: "; ")
        }
        return (metrics, notes)
    }

    private func capture(name: String) -> String? {
        guard let media = self.mediaTable, let outer = self.outerTable, let window = media.window else {
            return nil
        }
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
            return nil
        }
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        guard let image = createImage(.null, CGWindowListOption.optionIncludingWindow.rawValue, UInt32(window.windowNumber), CGWindowImageOption.boundsIgnoreFraming.rawValue | CGWindowImageOption.bestResolution.rawValue)?.takeRetainedValue() else {
            return nil
        }
        let scale = CGFloat(image.width) / window.frame.width
        let visible = media.convert(media.bounds, to: nil).intersection(outer.convert(outer.bounds, to: nil))
        let crop = CGRect(x: floor(visible.minX * scale), y: floor((window.frame.height - visible.maxY) * scale), width: floor(visible.width * scale), height: floor(visible.height * scale))
        guard let cropped = image.cropping(to: crop) else {
            return nil
        }
        let width = cropped.width
        let height = cropped.height
        var data = Data(count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return nil
        }
        let fileName = "peer-media-\(self.configuration.label)-\(name)-\(width)x\(height).rgba"
        try? FileManager.default.createDirectory(at: self.configuration.outputDirectory, withIntermediateDirectories: true)
        try? data.write(to: self.configuration.outputDirectory.appendingPathComponent(fileName))
        return fileName
    }
}
#endif
