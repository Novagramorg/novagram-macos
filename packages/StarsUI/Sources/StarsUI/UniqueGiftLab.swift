#if DEBUG
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import InlineStickerLayer
import PerfLab
import UniqueGiftBackground

public enum UniqueGiftLab {
    private static var session: AnyObject?
    private static var didStart = false

    @discardableResult
    public static func startIfRequested(context: any AccountContextProtocol, outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "unique-gifts" else {
            return false
        }
        self.didStart = true
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 4.0), {
            let session = UniqueGiftLabSession(context: context, configuration: configuration, completion: {
                UniqueGiftLab.session = nil
                if configuration.quitWhenDone {
                    NSApp.terminate(nil)
                }
            })
            UniqueGiftLab.session = session
            session.start()
        })
        return true
    }
}

private enum UniqueGiftLabMode {
    case unified
    case legacy
}

private func labColors(_ gift: StarGift.UniqueGift) -> (inner: NSColor, outer: NSColor, pattern: NSColor)? {
    for attribute in gift.attributes {
        if case let .backdrop(_, _, inner, outer, pattern, _, _) = attribute {
            return (NSColor(UInt32(bitPattern: inner)), NSColor(UInt32(bitPattern: outer)), NSColor(UInt32(bitPattern: pattern)))
        }
    }
    return nil
}

private final class UniqueGiftLabCell: View {
    private let sticker: NSView = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 80, 80))
    private var unified: UniqueGiftBackgroundView?
    private var legacyBackground: PeerInfoBackgroundView?
    private var legacyPattern: PeerInfoSpawnEmojiView?
    private var gift: StarGift.UniqueGift?
    private var context: (any AccountContextProtocol)?
    private var mode: UniqueGiftLabMode = .unified

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(sticker)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(gift: StarGift.UniqueGift, context: any AccountContextProtocol, mode: UniqueGiftLabMode, updateSticker: Bool = true) {
        self.gift = gift
        self.context = context
        self.mode = mode
        switch mode {
        case .unified:
            if unified == nil {
                let view = UniqueGiftBackgroundView(frame: bounds.insetBy(dx: 1, dy: 1))
                addSubview(view, positioned: .below, relativeTo: sticker)
                unified = view
            }
        case .legacy:
            if legacyBackground == nil {
                let background = PeerInfoBackgroundView(frame: bounds)
                addSubview(background, positioned: .below, relativeTo: sticker)
                legacyBackground = background
                let pattern = PeerInfoSpawnEmojiView(frame: bounds)
                addSubview(pattern, positioned: .below, relativeTo: sticker)
                legacyPattern = pattern
            }
            if let colors = labColors(gift) {
                legacyBackground?.gradient = [colors.inner, colors.outer]
                legacyBackground?.avatarBackgroundGradientLayer.opacity = 0.5
                legacyBackground?.layer?.cornerRadius = 10
                if let pattern = gift.pattern {
                    legacyPattern?.set(fileId: pattern.fileId.id, color: colors.pattern.withAlphaComponent(0.7), context: context, inlinePacksContext: context.inlinePacksContext, animated: false)
                    legacyPattern?.fraction = 0.68
                }
            }
        }
        if updateSticker, let file = gift.file {
            (sticker as? StarsStickerView)?.updateStarsSticker(file: file, size: sticker.frame.size, context: context, colors: [], playback: .previewFrames, animated: false)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        sticker.centerX(y: 5)
        if let unified, let gift, let context, let content = UniqueGiftBackgroundContent(gift: gift) {
            unified.frame = bounds.insetBy(dx: 1, dy: 1)
            unified.update(context: context, content: content, style: .item(giftCenterY: sticker.frame.midY - unified.frame.minY, cornerRadius: 10))
        }
        legacyBackground?.frame = NSMakeRect(1, 1, bounds.width - 2, bounds.height - 1)
        legacyPattern?.frame = bounds.insetBy(dx: 1, dy: 1).offsetBy(dx: 0, dy: 33)
    }
}

private final class UniqueGiftLabRowItem: TableRowItem {
    fileprivate let gifts: [StarGift.UniqueGift]
    fileprivate let context: any AccountContextProtocol
    fileprivate let mode: UniqueGiftLabMode
    private let rowIndex: Int

    init(_ initialSize: NSSize, index: Int, gifts: [StarGift.UniqueGift], context: any AccountContextProtocol, mode: UniqueGiftLabMode) {
        self.rowIndex = index
        self.gifts = gifts
        self.context = context
        self.mode = mode
        super.init(initialSize)
    }

    override var stableId: AnyHashable {
        return self.rowIndex
    }

    override var height: CGFloat {
        return UniqueGiftLabSession.cellSize.height + 10
    }

    override func viewClass() -> AnyClass {
        return UniqueGiftLabRowView.self
    }
}

private final class UniqueGiftLabRowView: TableRowView {
    private var cells: [UniqueGiftLabCell] = []

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? UniqueGiftLabRowItem else {
            return
        }
        while cells.count < item.gifts.count {
            let cell = UniqueGiftLabCell(frame: NSRect(origin: .zero, size: UniqueGiftLabSession.cellSize))
            addSubview(cell)
            cells.append(cell)
        }
        for (index, cell) in cells.enumerated() {
            cell.isHidden = index >= item.gifts.count
            if index < item.gifts.count {
                cell.set(gift: item.gifts[index], context: item.context, mode: item.mode)
            }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        for (index, cell) in cells.enumerated() {
            cell.frame = NSRect(origin: NSMakePoint(10 + CGFloat(index) * (UniqueGiftLabSession.cellSize.width + 10), 5), size: UniqueGiftLabSession.cellSize)
        }
    }
}

private final class UniqueGiftLabSession {
    static let cellSize = NSMakeSize(114, 135)

    private let context: any AccountContextProtocol
    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private let processMonitor = PerfLabProcessMonitor()
    private let loadDisposable = MetaDisposable()
    private let sourceDisposable = MetaDisposable()
    private var profileContext: ProfileGiftsContext?
    private var resaleContexts: [ResaleGiftsContext] = []
    private var loadLog: [String] = []
    private var gifts: [StarGift.UniqueGift] = []
    private var pending: [(scenario: String, run: Int)] = []
    private var window: Window?
    private var tableView: TableView?
    private var measurement: PerfLabScrollMeasurement?
    private var clock: PerfLabFrameClock?
    private var wheelSign: Double = -1

    init(context: any AccountContextProtocol, configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        self.context = context
        self.configuration = configuration
        self.completion = completion
        self.report = PerfLabReport(configuration: configuration)
    }

    func start() {
        for scenario in self.configuration.scenarios {
            for run in 0 ..< self.configuration.runs {
                self.pending.append((scenario, run))
            }
        }
        self.loadGifts { [weak self] in
            guard let self else {
                return
            }
            self.next()
        }
    }

    private func loadGifts(completion: @escaping () -> Void) {
        let target = Int(self.configuration.double("-PerfLabGiftCount", 60))
        let source = self.configuration.string("-PerfLabGiftSource", "auto")
        let keepUpdated = self.context.engine.payments.keepStarGiftsUpdated().start()
        var finished = false
        let finish: () -> Void = { [weak self] in
            guard let self, !finished else {
                return
            }
            finished = true
            keepUpdated.dispose()
            self.sourceDisposable.set(nil)
            self.loadDisposable.set(nil)
            self.resaleContexts.removeAll()
            self.gifts = Array(self.gifts.prefix(target))
            self.log("loaded \(self.gifts.count)")
            completion()
        }
        Queue.mainQueue().after(self.configuration.double("-PerfLabLoadTimeout", 40), { [weak self] in
            if !finished {
                self?.log("timeout")
            }
            finish()
        })
        if source == "resale" {
            self.loadResaleGifts(target: target, isFinished: { finished }, done: finish)
            return
        }
        self.loadProfileGifts(target: target, isFinished: { finished }, done: { [weak self] in
            guard let self else {
                return
            }
            if self.gifts.count >= target || source == "profile" {
                finish()
            } else {
                self.loadResaleGifts(target: target, isFinished: { finished }, done: finish)
            }
        })
    }

    private func log(_ text: String) {
        self.loadLog.append(text)
        NSLog("UniqueGiftLab: %@", text)
    }

    private func loadProfileGifts(target: Int, isFinished: @escaping () -> Bool, done: @escaping () -> Void) {
        let username = self.configuration.string("-PerfLabGiftPeer", "")
        let peerId: Signal<PeerId?, NoError>
        if username.isEmpty {
            peerId = .single(self.context.peerId)
        } else {
            peerId = self.context.engine.peers.resolvePeerByName(name: username, referrer: nil) |> mapToSignal { result -> Signal<PeerId?, NoError> in
                if case let .result(peer) = result {
                    return .single(peer?.id)
                }
                return .complete()
            } |> take(1)
        }
        self.sourceDisposable.set((peerId |> deliverOnMainQueue).start(next: { [weak self] peerId in
            guard let self, let peerId else {
                self?.log("profile: no peer")
                done()
                return
            }
            let giftsContext = ProfileGiftsContext(account: self.context.account, peerId: peerId)
            self.profileContext = giftsContext
            self.loadDisposable.set((giftsContext.state |> deliverOnMainQueue).start(next: { [weak self] state in
                guard let self, !isFinished() else {
                    return
                }
                guard case let .ready(canLoadMore, _) = state.dataState else {
                    return
                }
                let unique = state.gifts.compactMap { $0.gift.unique }
                self.gifts = unique.filter { labColors($0) != nil && $0.pattern != nil }
                if self.gifts.count >= target || !canLoadMore {
                    self.log("profile: gifts=\(state.gifts.count) unique=\(unique.count) usable=\(self.gifts.count)")
                    self.profileContext = nil
                    done()
                } else {
                    giftsContext.loadMore()
                }
            }))
        }))
    }

    private func loadResaleGifts(target: Int, isFinished: @escaping () -> Bool, done: @escaping () -> Void) {
        let typeCount = Int(self.configuration.double("-PerfLabGiftTypes", 6))
        let base = self.gifts
        self.sourceDisposable.set((self.context.engine.payments.cachedStarGifts() |> filter { $0 != nil } |> take(1) |> deliverOnMainQueue).start(next: { [weak self] list in
            guard let self, !isFinished() else {
                return
            }
            let ids: [Int64] = (list ?? []).compactMap { gift -> (Int64, Int64)? in
                if case let .generic(gift) = gift, let resale = gift.availability?.resale, resale > 0 {
                    return (gift.id, resale)
                }
                return nil
            }.sorted(by: { $0.1 > $1.1 }).prefix(typeCount).map { $0.0 }
            self.log("resale: list=\(list?.count ?? -1) types=\(ids.count)")
            if ids.isEmpty {
                done()
                return
            }
            let perType = max(1, (target - base.count + ids.count - 1) / ids.count)
            var collected: [Int64: [StarGift.UniqueGift]] = [:]
            var completed = Set<Int64>()
            let disposables = DisposableSet()
            self.loadDisposable.set(disposables)
            for id in ids {
                let resaleContext = ResaleGiftsContext(account: self.context.account, giftId: id, forCrafting: false)
                self.resaleContexts.append(resaleContext)
                disposables.add((resaleContext.state |> deliverOnMainQueue).start(next: { [weak self] state in
                    guard let self, !isFinished(), !completed.contains(id) else {
                        return
                    }
                    guard case let .ready(canLoadMore, _) = state.dataState else {
                        return
                    }
                    let unique = state.gifts.compactMap { $0.unique }.filter { labColors($0) != nil && $0.pattern != nil }
                    collected[id] = Array(unique.prefix(perType))
                    if unique.count >= perType || !canLoadMore {
                        completed.insert(id)
                    } else {
                        resaleContext.loadMore()
                    }
                    var mixed = base
                    let lists = ids.map { collected[$0] ?? [] }
                    for index in 0 ..< (lists.map { $0.count }.max() ?? 0) {
                        for list in lists where index < list.count {
                            mixed.append(list[index])
                        }
                    }
                    self.gifts = mixed
                    if completed.count == ids.count {
                        self.log("resale: \(ids.map { "\($0):\(collected[$0]?.count ?? 0)" }.joined(separator: ","))")
                        done()
                    }
                }))
            }
        }))
    }

    private func next() {
        guard !self.pending.isEmpty else {
            let url = self.report.write()
            NSLog("PerfLab report written to %@", url?.path ?? "nil")
            self.completion()
            return
        }
        let (scenario, run) = self.pending.removeFirst()
        self.runScenario(scenario, run: run) { [weak self] metrics, notes in
            guard let self else {
                return
            }
            self.report.add(scenario: scenario, run: run, metrics: metrics, notes: notes.merging(["load": self.loadLog.joined(separator: "; ")], uniquingKeysWith: { $1 }))
            self.closeWindow()
            Queue.mainQueue().after(1.5, { [weak self] in
                self?.next()
            })
        }
    }

    private func openWindow(title: String, size: NSSize) -> Window {
        let window = Window(contentRect: NSMakeRect(80, 80, size.width, size.height), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.backgroundColor = theme.colors.listBackground
        window.makeKeyAndOrderFront(nil)
        self.window = window
        return window
    }

    private func closeWindow() {
        self.measurement = nil
        self.clock?.stop()
        self.clock = nil
        self.tableView = nil
        self.window?.orderOut(nil)
        self.window = nil
    }

    private func snapshot(_ window: NSWindow, name: String) -> String {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
            return "no CGWindowListCreateImage"
        }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        guard let image = create(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0 | 1 << 3)?.takeRetainedValue() else {
            return "no image"
        }
        let url = self.configuration.outputDirectory.appendingPathComponent("\(self.configuration.label)-\(name).png")
        try? FileManager.default.createDirectory(at: self.configuration.outputDirectory, withIntermediateDirectories: true)
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        return url.path
    }

    private func layerCount(_ layer: CALayer?) -> Int {
        guard let layer else {
            return 0
        }
        return 1 + (layer.sublayers ?? []).reduce(0) { $0 + layerCount($1) } + layerCount(layer.mask)
    }

    private func sticker(_ gift: StarGift.UniqueGift, size: CGFloat, center: NSPoint, in container: NSView, playback: StarsStickerPlayback = .previewFrames) {
        let view = StarsHooks.shared.makeStickerView(NSMakeRect(center.x - size / 2, center.y - size / 2, size, size))
        container.addSubview(view)
        if let file = gift.file {
            (view as? StarsStickerView)?.updateStarsSticker(file: file, size: view.frame.size, context: self.context, colors: [], playback: playback, animated: false)
        }
    }

    private func unified(_ gift: StarGift.UniqueGift, frame: NSRect, style: UniqueGiftBackgroundStyle, in container: NSView, fraction: CGFloat = 0) {
        guard let content = UniqueGiftBackgroundContent(gift: gift) else {
            return
        }
        let view = UniqueGiftBackgroundView(frame: frame)
        container.addSubview(view)
        view.update(context: self.context, content: content, style: style)
        view.patternTransitionFraction = fraction
    }

    private func legacyCell(_ gift: StarGift.UniqueGift, frame: NSRect, in container: NSView) {
        let cell = UniqueGiftLabCell(frame: frame)
        container.addSubview(cell)
        cell.set(gift: gift, context: self.context, mode: .legacy)
    }

    private func unifiedCell(_ gift: StarGift.UniqueGift, frame: NSRect, in container: NSView) {
        let cell = UniqueGiftLabCell(frame: frame)
        container.addSubview(cell)
        cell.set(gift: gift, context: self.context, mode: .unified)
    }

    private func legacyHeader(_ gift: StarGift.UniqueGift, frame: NSRect, in container: NSView) {
        guard let colors = labColors(gift) else {
            return
        }
        let host = View(frame: frame)
        host.layer?.masksToBounds = true
        container.addSubview(host)
        let background = PeerInfoBackgroundView(frame: .zero)
        host.addSubview(background)
        background.gradient = [colors.inner, colors.outer]
        background.offset = 30
        background.frame = NSMakeSize(340, 278).bounds
        background.updateLayout(size: background.frame.size, transition: .immediate)
        let pattern = PeerInfoSpawnEmojiView(frame: host.bounds.focusX(NSMakeSize(180, 180), y: 30))
        host.addSubview(pattern)
        if let file = gift.pattern {
            pattern.set(fileId: file.fileId.id, color: colors.pattern.withAlphaComponent(0.5), context: self.context, inlinePacksContext: self.context.inlinePacksContext, animated: false)
        }
        self.sticker(gift, size: 100, center: NSMakePoint(host.frame.width / 2, 80), in: host, playback: .standard)
    }

    private func gallery(page: String, completion: @escaping ([String: Double], [String: String]) -> Void) {
        let gifts = self.gifts
        let container = View()
        container.backgroundColor = theme.colors.listBackground
        var size = NSMakeSize(0, 0)
        let gap: CGFloat = 16
        switch page {
        case "cells":
            let rows = Array(gifts.prefix(6))
            size = NSMakeSize(gap + (114 + gap) * 2 + 110 + gap + 80 + gap + 60 + gap, gap + CGFloat(rows.count) * (154 + gap))
            container.frame = size.bounds
            for (index, gift) in rows.enumerated() {
                let y = gap + CGFloat(index) * (154 + gap)
                var x = gap
                self.legacyCell(gift, frame: NSMakeRect(x, y, 114, 135), in: container)
                x += 114 + gap
                self.unifiedCell(gift, frame: NSMakeRect(x, y, 114, 135), in: container)
                x += 114 + gap
                self.unified(gift, frame: NSMakeRect(x, y, 110, 154), style: .item(giftCenterY: 60, cornerRadius: 10), in: container)
                self.sticker(gift, size: 88, center: NSMakePoint(x + 55, y + 60), in: container)
                x += 110 + gap
                self.unified(gift, frame: NSMakeRect(x, y, 80, 80), style: .item(giftCenterY: 40, cornerRadius: 20), in: container)
                self.sticker(gift, size: 50, center: NSMakePoint(x + 40, y + 40), in: container)
                x += 80 + gap
                self.unified(gift, frame: NSMakeRect(x, y, 60, 60), style: .item(giftCenterY: 30, cornerRadius: 10), in: container)
                self.sticker(gift, size: 40, center: NSMakePoint(x + 30, y + 30), in: container)
            }
        case "headers":
            let rows = Array(gifts.prefix(3))
            size = NSMakeSize(gap + 212 + gap + 340 + gap + 340 + gap, gap + CGFloat(rows.count) * (278 + gap))
            container.frame = size.bounds
            for (index, gift) in rows.enumerated() {
                let y = gap + CGFloat(index) * (278 + gap)
                var x = gap
                self.unified(gift, frame: NSMakeRect(x, y, 212, 232), style: .message(patternCenterY: 81 + 32, cornerRadius: 20), in: container)
                self.sticker(gift, size: 150, center: NSMakePoint(x + 106, y + 81), in: container, playback: .standard)
                x += 212 + gap
                self.legacyHeader(gift, frame: NSMakeRect(x, y, 340, 278), in: container)
                x += 340 + gap
                self.unified(gift, frame: NSMakeRect(x, y, 340, 278), style: .header(patternCenterY: 80 + 16), in: container)
                self.sticker(gift, size: 100, center: NSMakePoint(x + 170, y + 80), in: container, playback: .standard)
            }
        default:
            let rows = Array(gifts.prefix(2))
            let fractions: [CGFloat] = [0.0, 0.35, 0.7]
            size = NSMakeSize(gap + CGFloat(fractions.count) * (320 + gap), gap + CGFloat(rows.count) * (300 + gap))
            container.frame = size.bounds
            for (index, gift) in rows.enumerated() {
                let y = gap + CGFloat(index) * (300 + gap)
                for (column, fraction) in fractions.enumerated() {
                    let x = gap + CGFloat(column) * (320 + gap)
                    self.unified(gift, frame: NSMakeRect(x, y, 320, 300), style: .profile(avatarCenter: NSMakePoint(160, 90), avatarSize: 100, defaultHeight: 300, gradientCenter: NSMakePoint(0.5, 0.45)), in: container, fraction: fraction)
                }
            }
        }
        let window = self.openWindow(title: "Unique Gift Lab: \(page)", size: size)
        window.contentView?.addSubview(container)
        let start = CFAbsoluteTimeGetCurrent()
        Queue.mainQueue().after(self.configuration.double("-PerfLabSettleSeconds", 6.0), { [weak self] in
            guard let self, let window = self.window else {
                completion([:], ["error": "window closed"])
                return
            }
            let path = self.snapshot(window, name: "gallery-\(page)")
            completion([
                "gifts": Double(gifts.count),
                "layers": Double(self.layerCount(container.layer)),
                "cacheMB": Double(UniqueGiftBackgroundCache.shared.byteCount) / 1048576.0,
                "settleSeconds": CFAbsoluteTimeGetCurrent() - start
            ], ["snapshot": path])
        })
    }

    private func openGrid(mode: UniqueGiftLabMode, completion: @escaping () -> Void) {
        let perRow = 3
        let width = 10 + CGFloat(perRow) * (UniqueGiftLabSession.cellSize.width + 10)
        let window = self.openWindow(title: "Unique Gift Lab: grid", size: NSMakeSize(width, self.configuration.double("-PerfLabHeight", 700)))
        let tableView = TableView(frame: window.contentView?.bounds ?? .zero)
        tableView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(tableView)
        let chunks = stride(from: 0, to: self.gifts.count, by: perRow).map { Array(self.gifts[$0 ..< min($0 + perRow, self.gifts.count)]) }
        for (index, chunk) in chunks.enumerated() {
            _ = tableView.addItem(item: UniqueGiftLabRowItem(tableView.frame.size, index: index, gifts: chunk, context: self.context, mode: mode))
        }
        self.tableView = tableView
        Queue.mainQueue().after(self.configuration.double("-PerfLabWarmupSeconds", 6.0), completion)
    }

    private func detectWheelSign() {
        guard let tableView = self.tableView else {
            return
        }
        tableView.clipView.scroll(to: NSPoint(x: 0, y: 0))
        tableView.reflectScrolledClipView(tableView.clipView)
        let before = tableView.contentView.bounds.minY
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -20, wheel2: 0, wheel3: 0), let nsEvent = NSEvent(cgEvent: event) {
            tableView.scrollWheel(with: nsEvent)
        }
        self.wheelSign = tableView.contentView.bounds.minY > before ? -1 : 1
        tableView.clipView.scroll(to: NSPoint(x: 0, y: 0))
        tableView.reflectScrolledClipView(tableView.clipView)
    }

    private func gridScroll(mode: UniqueGiftLabMode, completion: @escaping ([String: Double], [String: String]) -> Void) {
        self.openGrid(mode: mode) { [weak self] in
            guard let self, let tableView = self.tableView, let contentView = self.window?.contentView else {
                completion([:], ["error": "no grid"])
                return
            }
            self.detectWheelSign()
            let speed = self.configuration.double("-PerfLabSpeed", 1.0)
            let segments = [
                PerfLabScrollSegment(duration: 0.3, velocity: 0),
                PerfLabScrollSegment(duration: 3.0, velocity: 900 * speed),
                PerfLabScrollSegment(duration: 3.0, velocity: -900 * speed),
                PerfLabScrollSegment(duration: 3.0, velocity: 1600 * speed),
                PerfLabScrollSegment(duration: 0.3, velocity: 0)
            ]
            let measurement = PerfLabScrollMeasurement(view: contentView, scrollView: tableView, segments: segments, wheelSign: self.wheelSign, processMonitor: self.processMonitor, sampler: { [weak self] in
                return [
                    "layers": Double(self?.layerCount(tableView.layer) ?? 0),
                    "cacheMB": Double(UniqueGiftBackgroundCache.shared.byteCount) / 1048576.0
                ]
            })
            self.measurement = measurement
            measurement.run(completion: { [weak self] metrics in
                self?.measurement = nil
                completion(metrics.merging(["gifts": Double(self?.gifts.count ?? 0)], uniquingKeysWith: { $1 }), ["mode": mode == .unified ? "unified" : "legacy"])
            })
        }
    }

    private func churn(mode: UniqueGiftLabMode, completion: @escaping ([String: Double], [String: String]) -> Void) {
        let columns = 6
        let rows = 4
        let size = NSMakeSize(10 + CGFloat(columns) * (UniqueGiftLabSession.cellSize.width + 10), 10 + CGFloat(rows) * (UniqueGiftLabSession.cellSize.height + 10))
        let window = self.openWindow(title: "Unique Gift Lab: churn", size: size)
        guard let contentView = window.contentView, !self.gifts.isEmpty else {
            completion([:], ["error": "no gifts"])
            return
        }
        var cells: [UniqueGiftLabCell] = []
        for index in 0 ..< columns * rows {
            let cell = UniqueGiftLabCell(frame: NSRect(origin: NSMakePoint(10 + CGFloat(index % columns) * (UniqueGiftLabSession.cellSize.width + 10), 10 + CGFloat(index / columns) * (UniqueGiftLabSession.cellSize.height + 10)), size: UniqueGiftLabSession.cellSize))
            contentView.addSubview(cell)
            cell.set(gift: self.gifts[index % self.gifts.count], context: self.context, mode: mode)
            cells.append(cell)
        }
        let gifts = self.gifts
        Queue.mainQueue().after(self.configuration.double("-PerfLabWarmupSeconds", 6.0), { [weak self] in
            guard let self else {
                return
            }
            let clock = PerfLabFrameClock(view: contentView)
            self.clock = clock
            var offset = 0
            var updates = 0
            let updateEvery = Int(self.configuration.double("-PerfLabChurnEvery", 2))
            let updateSticker = self.configuration.double("-PerfLabChurnSticker", 1) != 0
            let clearCache = self.configuration.double("-PerfLabChurnClearCache", 0) != 0
            var frame = 0
            clock.onFrame = { _ in
                frame += 1
                guard frame % max(1, updateEvery) == 0 else {
                    return
                }
                offset += cells.count
                if clearCache {
                    UniqueGiftBackgroundCache.shared.removeAll()
                }
                for (index, cell) in cells.enumerated() {
                    cell.set(gift: gifts[(index + offset) % gifts.count], context: self.context, mode: mode, updateSticker: updateSticker)
                    cell.layoutSubtreeIfNeeded()
                    updates += 1
                }
            }
            let start = self.processMonitor.snapshot()
            clock.start()
            Queue.mainQueue().after(self.configuration.double("-PerfLabChurnSeconds", 8.0), { [weak self] in
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
                    "updates": Double(updates),
                    "mainThreadMsPerUpdate": updates > 0 ? (end.mainThreadCpuTime - start.mainThreadCpuTime) * 1000 / Double(updates) : 0,
                    "cpuCores": duration > 0 ? (end.cpuTime - start.cpuTime) / duration : 0,
                    "mainThreadBusyPercent": duration > 0 ? (end.mainThreadCpuTime - start.mainThreadCpuTime) / duration * 100 : 0,
                    "footprintMB": Double(end.footprint) / 1048576.0,
                    "layers": Double(self.layerCount(contentView.layer))
                ], ["mode": mode == .unified ? "unified" : "legacy"])
            })
        })
    }

    private func runScenario(_ scenario: String, run: Int, completion: @escaping ([String: Double], [String: String]) -> Void) {
        switch scenario {
        case "gallery-cells":
            self.gallery(page: "cells", completion: completion)
        case "gallery-headers":
            self.gallery(page: "headers", completion: completion)
        case "gallery-profile":
            self.gallery(page: "profile", completion: completion)
        case "grid-unified":
            self.gridScroll(mode: .unified, completion: completion)
        case "grid-legacy":
            self.gridScroll(mode: .legacy, completion: completion)
        case "churn-unified":
            self.churn(mode: .unified, completion: completion)
        case "churn-legacy":
            self.churn(mode: .legacy, completion: completion)
        default:
            completion([:], ["error": "unknown scenario \(scenario)"])
        }
    }
}
#endif
