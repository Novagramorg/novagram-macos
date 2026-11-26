#if DEBUG
import Cocoa
import ImageIO
import TGUIKit
import SwiftSignalKit
import AvatarUI
import TelegramContext
import TelegramUtils
import TelegramCore
import PerfLab

public enum StoryMorphLab {
    private static var session: AnyObject?
    private static var didStart = false
    static var closeActiveStory: (() -> Void)?

    @discardableResult
    public static func startIfRequested(context: any AccountContextProtocol, outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "story-morph" else {
            return false
        }
        self.didStart = true
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 4.0), {
            let session = StoryMorphLabSession(context: context, configuration: configuration, completion: {
                StoryMorphLab.session = nil
                if configuration.quitWhenDone {
                    NSApp.terminate(nil)
                }
            })
            StoryMorphLab.session = session
            session.start()
        })
        return true
    }
}

private typealias WindowListCreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

private final class StoryMorphLabCapture {
    private let queue = DispatchQueue(label: "StoryMorphLab.capture", qos: .userInteractive)
    private let windowNumber: UInt32
    private let crop: CGRect
    private let directory: URL
    private let create: WindowListCreateImage?
    private var running = false
    private let lock = NSLock()
    private(set) var frames: [(index: Int, time: Double)] = []

    init(window: NSWindow, crop: CGRect, directory: URL) {
        self.windowNumber = UInt32(window.windowNumber)
        self.crop = crop
        self.directory = directory
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            self.create = unsafeBitCast(symbol, to: WindowListCreateImage.self)
        } else {
            self.create = nil
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func snapshot() -> CGImage? {
        guard let create = self.create, let image = create(.null, 8, self.windowNumber, 1 | 8)?.takeRetainedValue() else {
            return nil
        }
        return image.cropping(to: self.crop)
    }

    func write(_ image: CGImage, name: String) {
        let url = self.directory.appendingPathComponent(name) as CFURL
        guard let destination = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    func start(prefix: String, interval: Double) {
        self.lock.lock()
        self.running = true
        self.frames = []
        self.lock.unlock()
        self.queue.async {
            var index = 0
            while true {
                self.lock.lock()
                let running = self.running
                self.lock.unlock()
                if !running {
                    break
                }
                let before = CACurrentMediaTime()
                if let image = self.snapshot() {
                    let after = CACurrentMediaTime()
                    self.write(image, name: String(format: "%@-%03d.png", prefix, index))
                    self.lock.lock()
                    self.frames.append((index, (before + after) / 2))
                    self.lock.unlock()
                    index += 1
                }
                let elapsed = CACurrentMediaTime() - before
                if elapsed < interval {
                    Thread.sleep(forTimeInterval: interval - elapsed)
                }
            }
        }
    }

    func stop() -> [(index: Int, time: Double)] {
        self.lock.lock()
        self.running = false
        self.lock.unlock()
        self.queue.sync {}
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.frames
    }
}

private struct StoryMorphLabSample {
    let time: Double
    let phase: String
    let morphTime: Double
    let expected: CGRect
    let actual: CGRect
    let expectedRadius: CGFloat
    let actualRadius: CGFloat
    let contentScale: CGFloat
    let expectedScale: CGFloat
    let snapshotOpacity: Float
    let expectedSnapshot: CGFloat
    let sourceOpacity: Float
    let keyframeHeight: Double
    let presentationTime: Double
}

private final class StoryMorphLabSession {
    private let context: any AccountContextProtocol
    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private var scenarios: [String]
    private var frameClock: PerfLabFrameClock?
    private var samples: [StoryMorphLabSample] = []
    private var lastTransition: StoryMorphTransition?
    private var lastPhase: StoryMorphTransition.Phase?
    private var phaseChanges: [(Double, String)] = []
    private weak var source: AvatarStoryControl?
    private var notes: [String: String] = [:]
    private var directory: URL
    private var ownList: PeerStoryListContext?
    private var ownStoryId: Int32?
    private var ownDisposable: Disposable?

    init(context: any AccountContextProtocol, configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        self.context = context
        self.configuration = configuration
        self.completion = completion
        self.report = PerfLabReport(configuration: configuration)
        self.scenarios = configuration.scenarios == ["warm"] ? ["openclose", "interrupt", "rapid"] : configuration.scenarios
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        self.directory = configuration.outputDirectory.appendingPathComponent("story-morph-\(configuration.label)-\(formatter.string(from: Date()))")
    }

    private var window: Window {
        return self.context.window
    }

    func start() {
        StoryMorphTransition.debugDidRun = { [weak self] transition in
            guard let self = self, self.notes["context"] == nil, transition.phase == .opening else {
                return
            }
            let context = NSAnimationContext.current
            self.notes["context"] = "caDur \(CATransaction.animationDuration()) caTF \(String(describing: CATransaction.animationTimingFunction())) nsDur \(context.duration) implicit \(context.allowsImplicitAnimation) disable \(CATransaction.disableActions()) | " + Thread.callStackSymbols.prefix(28).map { line -> String in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                return parts.count > 3 ? parts[3...].joined(separator: " ").prefix(110).description : line
            }.joined(separator: " \n ")
        }
        NSApp.activate(ignoringOtherApps: true)
        self.window.makeKeyAndOrderFront(nil)
        self.waitForCandidates(deadline: CACurrentMediaTime() + self.configuration.double("-PerfLabWait", 30))
    }

    private func unlockPasscodeIfNeeded() {
        guard let root = self.window.contentView else {
            return
        }
        func find(_ view: NSView) -> NSSecureTextField? {
            if let field = view as? NSSecureTextField, !field.isHiddenOrHasHiddenAncestor {
                return field
            }
            for subview in view.subviews {
                if let field = find(subview) {
                    return field
                }
            }
            return nil
        }
        let selector = NSSelectorFromString("checkPasscode")
        if let field = find(root), let delegate = field.delegate as? NSObject, delegate.responds(to: selector) {
            field.stringValue = self.configuration.string("-PerfLabPasscode", "q")
            delegate.perform(selector)
            self.notes["unlocked"] = "1"
        }
    }

    private func anyAvatar() -> AvatarStoryControl? {
        guard let root = self.window.contentView else {
            return nil
        }
        var result: [AvatarStoryControl] = []
        func visit(_ view: NSView) {
            if let control = view as? AvatarStoryControl, !control.isHiddenOrHasHiddenAncestor, StoryMorphEndpoint.visibleFraction(of: control) > 0.999, control.avatar.imageContents != nil, control.bounds.width >= 30 {
                result.append(control)
            }
            for subview in view.subviews {
                visit(subview)
            }
        }
        visit(root)
        let index = Int(self.configuration.double("-PerfLabSourceIndex", 1))
        let sorted = result.sorted { root.convert($0.bounds, from: $0).minY < root.convert($1.bounds, from: $1).minY }
        return sorted.isEmpty ? nil : sorted[min(index, sorted.count - 1)]
    }

    private func prepareOwnStories(archived: Bool, completion: @escaping () -> Void) {
        let list = PeerStoryListContext(account: self.context.account, peerId: self.context.peerId, isArchived: archived, folderId: nil)
        self.ownList = list
        var finished = false
        self.ownDisposable?.dispose()
        self.ownDisposable = (list.state |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let self = self, !finished else {
                return
            }
            if let first = state.items.first {
                finished = true
                self.ownStoryId = first.storyItem.id
                self.notes["ownStories"] = "\(archived ? "archived" : "pinned"):\(state.items.count)"
                completion()
            } else if !state.isLoading, state.loadMoreToken != nil {
                list.loadMore()
            } else if !state.isLoading, state.loadMoreToken == nil {
                finished = true
                if archived {
                    completion()
                } else {
                    self.prepareOwnStories(archived: true, completion: completion)
                }
            }
        })
        Queue.mainQueue().after(8.0, {
            if !finished {
                finished = true
                if archived {
                    completion()
                } else {
                    self.prepareOwnStories(archived: true, completion: completion)
                }
            }
        })
    }

    private func openOwnStory(from control: AvatarStoryControl) -> Bool {
        guard let list = self.ownList, let id = self.ownStoryId else {
            return false
        }
        let peerId = self.context.peerId
        StoriesHooks.shared.showListStory(self.context, list, peerId, StoryInitialIndex(peerId: peerId, id: id, messageId: nil, takeControl: { [weak control] _, _, _ in
            return control
        }))
        return true
    }

    private func waitForCandidates(deadline: Double) {
        if !self.candidates().isEmpty {
            self.next()
            return
        }
        if CACurrentMediaTime() > deadline || (self.configuration.string("-PerfLabSource", "auto") == "own" && self.anyAvatar() != nil) {
            if self.anyAvatar() != nil {
                self.prepareOwnStories(archived: false, completion: { [weak self] in
                    self?.next()
                })
            } else {
                self.next()
            }
            return
        }
        self.unlockPasscodeIfNeeded()
        Queue.mainQueue().after(0.5, {
            self.waitForCandidates(deadline: deadline)
        })
    }

    private func finish() {
        let url = self.report.write()
        NSLog("StoryMorphLab done %@ %@", url?.path ?? "-", self.directory.path)
        self.completion()
    }

    private func next() {
        guard !self.scenarios.isEmpty else {
            self.finish()
            return
        }
        let scenario = self.scenarios.removeFirst()
        Queue.mainQueue().after(1.0, {
            self.run(scenario: scenario)
        })
    }

    private func candidates() -> [AvatarStoryControl] {
        guard let root = self.window.contentView else {
            return []
        }
        var result: [AvatarStoryControl] = []
        func visit(_ view: NSView) {
            if let control = view as? AvatarStoryControl, !control.isHiddenOrHasHiddenAncestor, StoryMorphEndpoint.visibleFraction(of: control) > 0.999, control.superview is Control {
                if let indicator = control.subviews.compactMap({ $0 as? AvatarStoryIndicatorComponent.IndicatorView }).first, let counters = indicator.component?.counters, counters.totalCount > 0, counters.unseenCount == 0, control.avatar.imageContents != nil {
                    result.append(control)
                }
            }
            for subview in view.subviews {
                visit(subview)
            }
        }
        visit(root)
        let rootView = root
        return result.sorted { rootView.convert($0.bounds, from: $0).minY < rootView.convert($1.bounds, from: $1).minY }
    }

    private func sampleFrame() {
        let now = CACurrentMediaTime()
        guard let transition = StoryMorphTransition.activeTransitions.first else {
            if let last = self.lastTransition, self.lastPhase != last.phase {
                self.lastPhase = last.phase
                self.phaseChanges.append((now, "\(last.phase)"))
            }
            return
        }
        if transition !== self.lastTransition || transition.phase != self.lastPhase {
            self.lastTransition = transition
            self.lastPhase = transition.phase
            self.phaseChanges.append((now, "\(transition.phase)"))
        }
        guard !transition.isStartPending, let timeline = transition.timeline, let bubble = transition.bubble.layer?.presentation(), let host = transition.host.superview else {
            return
        }
        _ = host
        let morphTime = now - transition.startTime
        if self.notes["timing"] == nil, let layer = transition.bubble.layer, let animation = layer.animation(forKey: "storyMorph.bounds") {
            var chain: [String] = []
            var current: CALayer? = layer
            while let l = current {
                chain.append(String(format: "%@ s=%.3f to=%.3f bt=%.3f dt=%.4f", "\(type(of: l))", l.speed, l.timeOffset, l.beginTime, l.convertTime(now, from: nil) - now))
                current = l.superlayer
            }
            func describe(_ layer: CALayer?) -> String {
                guard let layer = layer else {
                    return "nil"
                }
                return (layer.animationKeys() ?? []).map { key -> String in
                    let a = layer.animation(forKey: key)
                    return "\(key)[\(type(of: a!)) \((a as? CAPropertyAnimation)?.keyPath ?? "") add=\((a as? CAPropertyAnimation)?.isAdditive ?? false) dur=\(a?.duration ?? -1)]"
                }.joined(separator: ",")
            }
            self.notes["active"] = "\(StoryMorphTransition.activeCount) hosts=\(self.hostCount())"
            self.notes["anims"] = "bubble: " + describe(layer) + " | host: " + describe(transition.host.layer) + " | content: " + describe(transition.content.layer) + " | root: " + describe(transition.host.superview?.layer)
            self.notes["timing"] = String(format: "start=%.4f now=%.4f animBegin=%.4f animDur=%.4f animSpeed=%.3f planDur=%.4f keyCount=%d | ", transition.startTime, now, animation.beginTime, animation.duration, animation.speed, timeline.plan.duration, (animation as? CAKeyframeAnimation)?.values?.count ?? -1) + chain.joined(separator: " > ")
        }
        let state = timeline.plan.state(at: morphTime)
        let geometry = StoryMorphGeometry(state: state, contentSize: transition.content.frame.size)
        let fades = timeline.samples.min(by: { abs($0.time - morphTime) < abs($1.time - morphTime) })?.fades
        var keyframeHeight: Double = -1
        if let layer = transition.bubble.layer, let animation = layer.animation(forKey: "storyMorph.bounds") as? CAKeyframeAnimation, let values = animation.values as? [NSValue], let keyTimes = animation.keyTimes, keyTimes.count == values.count, animation.duration > 0 {
            let local = (layer.convertTime(now, from: nil) - animation.beginTime) / animation.duration
            let p = max(0, min(1, local))
            var index = 0
            while index + 1 < keyTimes.count, keyTimes[index + 1].doubleValue < p {
                index += 1
            }
            if index + 1 < keyTimes.count {
                let a = keyTimes[index].doubleValue
                let b = keyTimes[index + 1].doubleValue
                let f = b > a ? (p - a) / (b - a) : 0
                keyframeHeight = Double(values[index].rectValue.height) * (1 - f) + Double(values[index + 1].rectValue.height) * f
            } else {
                keyframeHeight = Double(values[values.count - 1].rectValue.height)
            }
        }
        if self.notes["ptiming"] == nil, let p = transition.bubble.layer?.presentation() {
            self.notes["ptiming"] = "speed \(p.speed) offset \(p.timeOffset) begin \(p.beginTime) | host \(transition.host.layer?.presentation()?.speed ?? -1)"
        }
        let contentScale = transition.content.layer?.presentation()?.transform.m11 ?? 0
        let snapshot = transition.snapshotLayer.presentation()?.opacity ?? -1
        let sourceOpacity = self.source?.avatar.layer?.presentation()?.opacity ?? -1
        self.samples.append(StoryMorphLabSample(time: now, phase: "\(transition.phase)", morphTime: morphTime, expected: geometry.bubble, actual: bubble.frame, expectedRadius: geometry.cornerRadius, actualRadius: bubble.cornerRadius, contentScale: contentScale, expectedScale: geometry.contentScale, snapshotOpacity: snapshot, expectedSnapshot: fades?.snapshot ?? -1, sourceOpacity: sourceOpacity, keyframeHeight: keyframeHeight, presentationTime: CACurrentMediaTime() - now))
    }

    private func hostCount() -> Int {
        return self.window.contentView?.subviews.filter { $0 is StoryMorphHostView }.count ?? 0
    }

    private func trigger(_ control: AvatarStoryControl) {
        if self.ownStoryId != nil {
            _ = self.openOwnStory(from: control)
        } else {
            (control.superview as? Control)?.send(event: .Click)
        }
    }

    private func run(scenario: String) {
        let useOwn = self.ownStoryId != nil
        guard let control = useOwn ? self.anyAvatar() : self.candidates().first, let root = self.window.contentView else {
            var total = 0
            var withIndicator: [String] = []
            func visit(_ view: NSView) {
                if let control = view as? AvatarStoryControl {
                    total += 1
                    withIndicator.append("ctl \(control.bounds.size) vis \(StoryMorphEndpoint.visibleFraction(of: control)) img \(control.avatar.imageContents.map { "\(type(of: $0))" } ?? "nil") layer \(control.avatar.layer?.contents.map { "\(type(of: $0))" } ?? "nil") avatarFrame \(control.avatar.frame)")
                    if let indicator = control.subviews.compactMap({ $0 as? AvatarStoryIndicatorComponent.IndicatorView }).first {
                        let counters = indicator.component?.counters
                        withIndicator.append("\(counters?.totalCount ?? -1)/\(counters?.unseenCount ?? -1) hidden=\(control.isHiddenOrHasHiddenAncestor) vis=\(StoryMorphEndpoint.visibleFraction(of: control) > 0.999) ctl=\(control.superview is Control) img=\(control.avatar.imageContents != nil)")
                    }
                }
                for subview in view.subviews {
                    visit(subview)
                }
            }
            if let root = self.window.contentView {
                visit(root)
            }
            let capture = StoryMorphLabCapture(window: self.window, crop: CGRect(x: 0, y: 0, width: 100000, height: 100000), directory: self.directory)
            if let image = capture.snapshot() {
                capture.write(image, name: "no-candidate-\(scenario).png")
            }
            self.report.add(scenario: scenario, run: 0, metrics: ["storyControls": Double(total)], notes: ["error": "no seen story avatar visible in the main window", "indicators": withIndicator.joined(separator: "; "), "directory": self.directory.path])
            self.next()
            return
        }
        self.source = control
        self.samples = []
        self.phaseChanges = []
        self.lastTransition = nil
        self.lastPhase = nil
        let windowHeight = root.bounds.height
        func topLeft(_ rect: CGRect) -> CGRect {
            return root.isFlipped ? rect : CGRect(x: rect.minX, y: windowHeight - rect.maxY, width: rect.width, height: rect.height)
        }
        let sourceRect = topLeft(root.convert(control.avatar.bounds, from: control.avatar))
        let storyGuess = CGRect(origin: .zero, size: root.bounds.size).insetBy(dx: max(0, (root.bounds.width - 520) / 2), dy: 0)
        let unionView = sourceRect.union(storyGuess).insetBy(dx: -20, dy: -10).intersection(CGRect(origin: .zero, size: root.bounds.size))
        let scale = self.window.backingScaleFactor
        let titlebar = self.window.frame.height - root.frame.height
        let crop = CGRect(x: unionView.minX * scale, y: (unionView.minY + titlebar) * scale, width: unionView.width * scale, height: unionView.height * scale).integral
        let capture = StoryMorphLabCapture(window: self.window, crop: crop, directory: self.directory.appendingPathComponent(scenario))
        let avatarCrop = CGRect(x: (sourceRect.minX - unionView.minX - 4) * scale, y: (sourceRect.minY - unionView.minY - 4) * scale, width: (sourceRect.width + 8) * scale, height: (sourceRect.height + 8) * scale).integral

        let before = capture.snapshot()
        if let before = before {
            capture.write(before, name: "before.png")
        }

        let clock = PerfLabFrameClock(view: root)
        clock.onFrame = { [weak self] _ in
            self?.sampleFrame()
        }
        self.frameClock = clock
        clock.start()
        capture.start(prefix: "f", interval: 1.0 / 60.0)
        let clickTime = CACurrentMediaTime()
        self.notes["mode"] = useOwn ? "own" : "click"
        self.trigger(control)

        let finishScenario: (Double) -> Void = { [weak self] settle in
            Queue.mainQueue().after(settle, {
                guard let self = self else {
                    return
                }
                clock.stop()
                let frames = capture.stop()
                let after = capture.snapshot()
                if let after = after {
                    capture.write(after, name: "after.png")
                }
                self.summarize(scenario: scenario, clickTime: clickTime, frames: frames, before: before, after: after, avatarCrop: avatarCrop, sourceRect: sourceRect, crop: unionView, clock: clock)
                self.next()
            })
        }

        switch scenario {
        case "resize":
            let originalFrame = self.window.frame
            self.waitForPhase(.opening, timeout: 6, then: {
                Queue.mainQueue().after(0.1, {
                    var frame = originalFrame
                    frame.size.width += 60
                    frame.origin.x -= 30
                    self.window.setFrame(frame, display: true)
                    self.notes["resizedDuringPhase"] = StoryMorphTransition.activeTransitions.first.map { "\($0.phase)" } ?? "none"
                    Queue.mainQueue().after(0.8, {
                        self.notes["contentRestored"] = StoryMorphTransition.activeCount == 0 ? "1" : "0"
                        StoryMorphLab.closeActiveStory?()
                        Queue.mainQueue().after(0.9, {
                            self.window.setFrame(originalFrame, display: true)
                            finishScenario(0.3)
                        })
                    })
                })
            })
        case "closeall":
            self.waitForPhase(.opening, timeout: 6, then: {
                Queue.mainQueue().after(0.12, {
                    closeAllModals(window: self.window)
                    finishScenario(1.2)
                })
            })
        case "interrupt":
            self.waitForPhase(.opening, timeout: 6, then: {
                Queue.mainQueue().after(self.configuration.double("-PerfLabInterruptAt", 0.12), {
                    StoryMorphLab.closeActiveStory?()
                    finishScenario(1.2)
                })
            })
        case "rapid":
            self.waitForPhase(.opening, timeout: 6, then: {
                Queue.mainQueue().after(0.7, {
                    StoryMorphLab.closeActiveStory?()
                    Queue.mainQueue().after(0.1, {
                        self.trigger(control)
                        self.waitForPhase(.opening, timeout: 6, then: {
                            Queue.mainQueue().after(1.0, {
                                StoryMorphLab.closeActiveStory?()
                                finishScenario(1.2)
                            })
                        })
                    })
                })
            })
        default:
            self.waitForPhase(.opening, timeout: 6, then: {
                Queue.mainQueue().after(self.configuration.double("-PerfLabHold", 1.4), {
                    StoryMorphLab.closeActiveStory?()
                    finishScenario(1.2)
                })
            })
        }
    }

    private func waitForPhase(_ phase: StoryMorphTransition.Phase, timeout: Double, then: @escaping () -> Void) {
        let deadline = CACurrentMediaTime() + timeout
        func poll() {
            if StoryMorphTransition.activeTransitions.contains(where: { $0.phase == phase }) || CACurrentMediaTime() > deadline {
                if CACurrentMediaTime() > deadline {
                    self.notes["timeout"] = "\(phase)"
                }
                then()
            } else {
                Queue.mainQueue().after(0.004, poll)
            }
        }
        poll()
    }

    private func pixelDifference(_ a: CGImage?, _ b: CGImage?, in rect: CGRect) -> Double {
        guard let a = a?.cropping(to: rect), let b = b?.cropping(to: rect), a.width == b.width, a.height == b.height else {
            return -1
        }
        func pixels(_ image: CGImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return data
        }
        let pa = pixels(a)
        let pb = pixels(b)
        var maximum = 0
        var total = 0
        for i in 0 ..< pa.count where i % 4 != 3 {
            let d = abs(Int(pa[i]) - Int(pb[i]))
            maximum = max(maximum, d)
            total += d
        }
        return Double(total) / Double(pa.count / 4 * 3)
    }

    private func summarize(scenario: String, clickTime: Double, frames: [(index: Int, time: Double)], before: CGImage?, after: CGImage?, avatarCrop: CGRect, sourceRect: CGRect, crop: CGRect, clock: PerfLabFrameClock) {
        var metrics: [String: Double] = [:]
        var notes = self.notes
        self.notes = [:]
        let opening = self.samples.filter { $0.phase == "opening" }
        let closing = self.samples.filter { $0.phase == "closing" }
        func deviation(_ samples: [StoryMorphLabSample]) -> Double {
            return samples.map { s in
                Double(max(abs(s.actual.midX - s.expected.midX), abs(s.actual.midY - s.expected.midY), abs(s.actual.width - s.expected.width), abs(s.actual.height - s.expected.height)))
            }.max() ?? -1
        }
        func percentile(_ values: [Double], _ p: Double) -> Double {
            guard !values.isEmpty else {
                return -1
            }
            let sorted = values.sorted()
            return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
        }
        let openingDeviations = opening.map { s in Double(max(abs(s.actual.midX - s.expected.midX), abs(s.actual.midY - s.expected.midY), abs(s.actual.width - s.expected.width), abs(s.actual.height - s.expected.height))) }
        metrics["samplesOpening"] = Double(opening.count)
        metrics["samplesClosing"] = Double(closing.count)
        metrics["maxDevOpening"] = deviation(opening)
        metrics["p90DevOpening"] = percentile(openingDeviations, 0.9)
        metrics["maxDevClosing"] = deviation(closing)
        metrics["maxRadiusDev"] = self.samples.map { Double(abs($0.actualRadius - $0.expectedRadius)) }.max() ?? -1
        metrics["maxScaleDev"] = self.samples.map { Double(abs($0.contentScale - $0.expectedScale)) }.max() ?? -1
        if let first = opening.first {
            metrics["firstOpeningMorphTime"] = first.morphTime
            metrics["firstOpeningDistanceToSource"] = Double(max(abs(first.actual.midX - sourceRect.midX), abs(first.actual.midY - sourceRect.midY)))
        }
        if let last = closing.last {
            metrics["lastClosingDistanceToSource"] = Double(max(abs(last.actual.midX - sourceRect.midX), abs(last.actual.midY - sourceRect.midY), abs(last.actual.width - sourceRect.width)))
        }
        var maxStep: Double = 0
        for i in 1 ..< max(1, self.samples.count) {
            let a = self.samples[i - 1]
            let b = self.samples[i]
            if a.phase == b.phase || (a.phase == "opening" && b.phase == "closing") {
                let dt = max(b.time - a.time, 1.0 / 240.0)
                let step = Double(max(abs(b.actual.midX - a.actual.midX), abs(b.actual.midY - a.actual.midY), abs(b.actual.height - a.actual.height))) / (dt * 120.0)
                maxStep = max(maxStep, step)
            }
        }
        metrics["maxStepPer120Hz"] = maxStep
        if let switchIndex = self.samples.firstIndex(where: { $0.phase == "closing" }), switchIndex > 0, self.samples[switchIndex - 1].phase == "opening" {
            let a = self.samples[switchIndex - 1]
            let b = self.samples[switchIndex]
            metrics["interruptJump"] = Double(max(abs(b.actual.midX - a.actual.midX), abs(b.actual.midY - a.actual.midY), abs(b.actual.height - a.actual.height)))
            metrics["interruptDt"] = b.time - a.time
        }
        metrics["leftoverHosts"] = Double(self.hostCount())
        metrics["activeTransitions"] = Double(StoryMorphTransition.activeCount)
        metrics["sourceAlphaAfter"] = Double(self.source?.avatar.alphaValue ?? -1)
        metrics["sourceHeldAfter"] = (self.source.map { StoryMorphHold.isHeld($0.avatar) } ?? false) ? 1 : 0
        metrics["avatarDiffBeforeAfter"] = self.pixelDifference(before, after, in: avatarCrop)
        metrics["frames"] = Double(clock.stats.frames)
        metrics["hitches"] = Double(clock.stats.hitches)
        metrics["worstGapMs"] = clock.stats.worstGap * 1000
        metrics["captures"] = Double(frames.count)
        notes["phases"] = self.phaseChanges.map { String(format: "%.3f:%@", $0.0 - clickTime, $0.1) }.joined(separator: ",")
        notes["directory"] = self.directory.appendingPathComponent(scenario).path
        notes["crop"] = "\(crop)"
        notes["source"] = "\(sourceRect)"

        var rows: [[String: Any]] = []
        for s in self.samples {
            rows.append([
                "t": s.time - clickTime, "phase": s.phase, "mt": s.morphTime,
                "ex": [s.expected.minX, s.expected.minY, s.expected.width, s.expected.height].map { Double($0) },
                "ac": [s.actual.minX, s.actual.minY, s.actual.width, s.actual.height].map { Double($0) },
                "er": Double(s.expectedRadius), "ar": Double(s.actualRadius),
                "es": Double(s.expectedScale), "as": Double(s.contentScale),
                "so": Double(s.snapshotOpacity), "eso": Double(s.expectedSnapshot), "src": Double(s.sourceOpacity), "kfh": s.keyframeHeight
            ])
        }
        let frameRows = frames.map { ["i": $0.index, "t": $0.time - clickTime] as [String: Any] }
        let document: [String: Any] = ["scenario": scenario, "metrics": metrics, "notes": notes, "samples": rows, "frames": frameRows, "crop": [crop.minX, crop.minY, crop.width, crop.height].map { Double($0) }, "source": [sourceRect.minX, sourceRect.minY, sourceRect.width, sourceRect.height].map { Double($0) }]
        if let data = try? JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: self.directory.appendingPathComponent(scenario).appendingPathComponent("samples.json"))
        }
        self.report.add(scenario: scenario, run: 0, metrics: metrics, notes: notes)
    }
}
#endif
