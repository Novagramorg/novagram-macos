#if DEBUG
import Cocoa
import ObjectiveC
import TGUIKit
import SwiftSignalKit
import TelegramContext
import PerfLab

public enum ChatListStoriesLab {
    private static var session: AnyObject?
    private static var didStart = false

    @discardableResult
    public static func startIfRequested(context: any AccountContextProtocol, outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "chatlist-stories" else {
            return false
        }
        self.didStart = true
        if configuration.string("-StoryLabScrolling", "classic") == "classic" {
            self.disableResponsiveScrolling()
        }
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 4.0), {
            let session = ChatListStoriesLabSession(configuration: configuration, completion: {
                ChatListStoriesLab.session = nil
                if configuration.quitWhenDone {
                    NSApp.terminate(nil)
                }
            })
            ChatListStoriesLab.session = session
            session.start()
        })
        return true
    }

    private static func disableResponsiveScrolling() {
        let selector = NSSelectorFromString("isCompatibleWithResponsiveScrolling")
        let block: @convention(block) (AnyObject) -> Bool = { _ in
            return false
        }
        let implementation = imp_implementationWithBlock(block)
        for cls in [ScrollView.self, TableView.self, TableRowView.self] as [AnyClass] {
            if let method = class_getClassMethod(cls, selector) {
                method_setImplementation(method, implementation)
            }
        }
    }
}

private struct LabEvent {
    enum Kind {
        case scroll(phase: Int64, momentum: Int64, dx: CGFloat, dy: CGFloat, precise: Bool, target: LabTarget)
        case wait
        case mark(String)
    }
    var kind: Kind
    var delay: Double
}

private enum LabTarget {
    case list
    case strip
}

private struct LabSample {
    var time: Double
    var gesture: Int
    var tracking: Bool
    var snapshot: StoryRevealLabSnapshot
}

private final class ChatListStoriesLabSession {
    static var fakeMouse: NSPoint?
    static let marker: Int64 = 0x5354_5259
    private static var installedFakeMouse = false

    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private var scenarios: [String]
    private var clock: PerfLabFrameClock?
    private var samples: [LabSample] = []
    private var posted = 0
    private var windowed = 0
    private var delivered = 0
    private var monitor: Any?
    private var gesture = 0
    private var inGesture = false
    private var gestureDeltas: [Int: CGFloat] = [:]
    private var notes: [String: String] = [:]
    private let directory: URL

    init(configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        self.configuration = configuration
        self.completion = completion
        self.report = PerfLabReport(configuration: configuration)
        let all = ["reveal-slow", "reveal-cancel", "reveal-flick", "collapse-slow", "collapse-flick", "momentum-to-top", "pull-from-below", "reversal", "wheel", "strip-horizontal", "strip-vertical", "strip-diagonal", "collapse-after-strip-scroll", "catch-snap", "scroll-down-from-top"]
        self.scenarios = configuration.scenarios == ["warm"] ? all : configuration.scenarios
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        self.directory = configuration.outputDirectory.appendingPathComponent("chatlist-stories-\(configuration.label)-\(formatter.string(from: Date()))")
    }

    private var target: StoryRevealLabProbing? {
        return StoryRevealLabRegistry.target
    }

    func start() {
        StoryRevealLabRegistry.isRecording = true
        Self.installFakeMouse()
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard let self = self, event.cgEvent?.getIntegerValueField(.eventSourceUserData) == ChatListStoriesLabSession.marker, let window = self.target?.storyLabWindow, let point = ChatListStoriesLabSession.fakeMouse else {
                return event
            }
            self.delivered += 1
            if event.window != nil {
                self.windowed += 1
                return event
            }
            ChatListStoriesLabSession.attach(event, to: window, at: point)
            window.sendEvent(event)
            return nil
        })
        NSApp.activate(ignoringOtherApps: true)
        self.target?.storyLabWindow?.makeKeyAndOrderFront(nil)
        self.waitForTarget(deadline: CACurrentMediaTime() + self.configuration.double("-PerfLabWait", 30))
    }

    private func waitForTarget(deadline: Double) {
        if let target = self.target, target.storyLabHasStories, target.storyLabWindow != nil {
            self.notes["scrolling"] = self.configuration.string("-StoryLabScrolling", "classic")
            self.next()
            return
        }
        self.unlockPasscodeIfNeeded()
        if CACurrentMediaTime() > deadline {
            self.report.add(scenario: "setup", run: 0, metrics: [:], notes: ["error": self.target == nil ? "no chat list" : "no stories in the chat list"])
            self.finish()
            return
        }
        Queue.mainQueue().after(0.5, {
            self.waitForTarget(deadline: deadline)
        })
    }

    private func unlockPasscodeIfNeeded() {
        guard let root = NSApp.windows.first(where: { $0 is Window })?.contentView else {
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
        }
    }

    private static func installFakeMouse() {
        guard !self.installedFakeMouse else {
            return
        }
        self.installedFakeMouse = true
        let selector = #selector(getter: NSWindow.mouseLocationOutsideOfEventStream)
        guard let original = class_getInstanceMethod(NSWindow.self, selector) else {
            return
        }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSPoint
        let originalFunction = unsafeBitCast(method_getImplementation(original), to: Getter.self)
        let block: @convention(block) (AnyObject) -> NSPoint = { object in
            if let point = ChatListStoriesLabSession.fakeMouse {
                return point
            }
            return originalFunction(object, selector)
        }
        let implementation = imp_implementationWithBlock(block)
        if !class_addMethod(Window.self, selector, implementation, method_getTypeEncoding(original)), let method = class_getInstanceMethod(Window.self, selector) {
            method_setImplementation(method, implementation)
        }
    }

    private func finish() {
        StoryRevealLabRegistry.isRecording = false
        Self.fakeMouse = nil
        if let monitor = self.monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        self.target?.storyLabReset(revealed: false)
        let url = self.report.write()
        NSLog("ChatListStoriesLab done %@", url?.path ?? "-")
        self.completion()
    }

    private func next() {
        guard !self.scenarios.isEmpty else {
            self.finish()
            return
        }
        let scenario = self.scenarios.removeFirst()
        Queue.mainQueue().after(0.6, {
            self.run(scenario)
        })
    }

    private func point(_ target: LabTarget) -> NSPoint? {
        switch target {
        case .list:
            return self.target?.storyLabListPoint()
        case .strip:
            return self.target?.storyLabStripPoint()
        }
    }

    private func trackpad(_ target: LabTarget, _ deltas: [CGPoint], interval: Double, momentum: [CGPoint] = []) -> [LabEvent] {
        var events: [LabEvent] = [LabEvent(kind: .mark("begin"), delay: 0)]
        events.append(LabEvent(kind: .scroll(phase: 128, momentum: 0, dx: 0, dy: 0, precise: true, target: target), delay: interval))
        for (i, delta) in deltas.enumerated() {
            events.append(LabEvent(kind: .scroll(phase: i == 0 ? 1 : 2, momentum: 0, dx: delta.x, dy: delta.y, precise: true, target: target), delay: interval))
        }
        events.append(LabEvent(kind: .scroll(phase: 4, momentum: 0, dx: 0, dy: 0, precise: true, target: target), delay: interval))
        events.append(LabEvent(kind: .mark("end"), delay: 0))
        for (i, delta) in momentum.enumerated() {
            events.append(LabEvent(kind: .scroll(phase: 0, momentum: i == 0 ? 1 : 2, dx: delta.x, dy: delta.y, precise: true, target: target), delay: 1.0 / 120.0))
        }
        if !momentum.isEmpty {
            events.append(LabEvent(kind: .scroll(phase: 0, momentum: 3, dx: 0, dy: 0, precise: true, target: target), delay: 1.0 / 120.0))
        }
        return events
    }

    private func decay(_ start: CGPoint, count: Int, factor: CGFloat = 0.92) -> [CGPoint] {
        var result: [CGPoint] = []
        var current = start
        for _ in 0 ..< count {
            result.append(current)
            current = CGPoint(x: current.x * factor, y: current.y * factor)
        }
        return result
    }

    private func repeated(_ delta: CGPoint, _ count: Int) -> [CGPoint] {
        return Array(repeating: delta, count: count)
    }

    private func wheel(_ notches: [CGFloat], interval: Double) -> [LabEvent] {
        var events: [LabEvent] = [LabEvent(kind: .mark("begin"), delay: 0)]
        for notch in notches {
            events.append(LabEvent(kind: .scroll(phase: 0, momentum: 0, dx: 0, dy: notch, precise: false, target: .list), delay: interval))
        }
        events.append(LabEvent(kind: .mark("end"), delay: 0))
        return events
    }

    private func wait(_ seconds: Double) -> [LabEvent] {
        return [LabEvent(kind: .wait, delay: seconds)]
    }

    private struct Plan {
        var startRevealed: Bool
        var startOffset: CGFloat = 0
        var events: [LabEvent]
        var expectRevealed: Bool
        var listMayScroll: Bool
        var monotonicGestures: Bool = true
        var stripMustScroll: Bool = false
        var listMustScroll: Bool = false
        var stripMustStay: Bool = false
        var prepareStrip: CGFloat? = nil
    }

    private func plan(_ scenario: String) -> Plan? {
        let slow = 1.0 / 60.0
        let fast = 1.0 / 120.0
        switch scenario {
        case "reveal-slow":
            return Plan(startRevealed: false, events: self.trackpad(.list, self.repeated(CGPoint(x: 0, y: 3), 40), interval: slow) + self.wait(0.8), expectRevealed: true, listMayScroll: false)
        case "reveal-cancel":
            return Plan(startRevealed: false, events: self.trackpad(.list, self.repeated(CGPoint(x: 0, y: 2), 12), interval: slow) + self.wait(0.8), expectRevealed: false, listMayScroll: false)
        case "reveal-flick":
            return Plan(startRevealed: false, events: self.trackpad(.list, [CGPoint(x: 0, y: 6), CGPoint(x: 0, y: 10), CGPoint(x: 0, y: 14)], interval: fast, momentum: self.decay(CGPoint(x: 0, y: 14), count: 40)) + self.wait(0.8), expectRevealed: true, listMayScroll: false)
        case "collapse-slow":
            return Plan(startRevealed: true, events: self.trackpad(.list, self.repeated(CGPoint(x: 0, y: -2), 50), interval: slow) + self.wait(0.8), expectRevealed: false, listMayScroll: true)
        case "collapse-flick":
            return Plan(startRevealed: true, events: self.trackpad(.list, [CGPoint(x: 0, y: -8), CGPoint(x: 0, y: -12), CGPoint(x: 0, y: -16)], interval: fast, momentum: self.decay(CGPoint(x: 0, y: -18), count: 50)) + self.wait(0.8), expectRevealed: false, listMayScroll: true)
        case "momentum-to-top":
            return Plan(startRevealed: false, startOffset: 300, events: self.trackpad(.list, [CGPoint(x: 0, y: 10), CGPoint(x: 0, y: 20), CGPoint(x: 0, y: 30)], interval: fast, momentum: self.decay(CGPoint(x: 0, y: 30), count: 70, factor: 0.95)) + self.wait(1.0), expectRevealed: false, listMayScroll: true)
        case "pull-from-below":
            return Plan(startRevealed: false, startOffset: 60, events: self.trackpad(.list, self.repeated(CGPoint(x: 0, y: 3), 45), interval: slow) + self.wait(1.0), expectRevealed: false, listMayScroll: true)
        case "reversal":
            return Plan(startRevealed: false, events: self.trackpad(.list, self.repeated(CGPoint(x: 0, y: 3), 15) + self.repeated(CGPoint(x: 0, y: -3), 10) + self.repeated(CGPoint(x: 0, y: 3), 20), interval: slow) + self.wait(0.8), expectRevealed: true, listMayScroll: false, monotonicGestures: false)
        case "wheel":
            return Plan(startRevealed: false, events: self.wheel([1], interval: slow) + self.wait(0.6) + self.wheel([-1], interval: slow) + self.wait(0.6) + self.wheel([1, 1], interval: 0.05) + self.wait(0.6), expectRevealed: true, listMayScroll: false)
        case "strip-horizontal":
            return Plan(startRevealed: true, events: self.trackpad(.strip, self.repeated(CGPoint(x: -6, y: 0.4), 30), interval: fast, momentum: self.decay(CGPoint(x: -8, y: 0.3), count: 30)) + self.wait(0.6), expectRevealed: true, listMayScroll: false, stripMustScroll: true)
        case "strip-vertical":
            return Plan(startRevealed: true, events: self.trackpad(.strip, self.repeated(CGPoint(x: 0.3, y: -3), 40), interval: slow) + self.wait(0.8), expectRevealed: false, listMayScroll: true, stripMustStay: true)
        case "strip-diagonal":
            return Plan(startRevealed: true, events: self.trackpad(.strip, self.repeated(CGPoint(x: -5, y: -2), 25), interval: fast) + self.wait(0.6), expectRevealed: true, listMayScroll: false, stripMustScroll: true)
        case "collapse-after-strip-scroll":
            return Plan(startRevealed: true, events: self.trackpad(.strip, self.repeated(CGPoint(x: -8, y: 0), 25), interval: fast) + self.wait(0.4) + self.trackpad(.list, self.repeated(CGPoint(x: 0, y: -3), 30), interval: slow) + self.wait(0.8), expectRevealed: false, listMayScroll: true, monotonicGestures: true)
        case "scroll-down-from-top":
            return Plan(startRevealed: false, events: self.trackpad(.list, [CGPoint(x: 0, y: 0)] + self.repeated(CGPoint(x: 0, y: -10), 20), interval: slow) + self.wait(0.6), expectRevealed: false, listMayScroll: true, listMustScroll: true)
        case "catch-snap":
            return Plan(startRevealed: false, events: self.trackpad(.list, self.repeated(CGPoint(x: 0, y: 5), 11), interval: slow) + self.wait(0.06) + self.trackpad(.list, self.repeated(CGPoint(x: 0, y: -3), 20), interval: slow) + self.wait(0.8), expectRevealed: false, listMayScroll: true, monotonicGestures: false)
        default:
            return nil
        }
    }

    private func run(_ scenario: String) {
        guard let target = self.target, let plan = self.plan(scenario) else {
            self.report.add(scenario: scenario, run: 0, metrics: [:], notes: ["error": "unknown scenario or no target"])
            self.next()
            return
        }
        self.notes["occluded"] = NSApp.occlusionState.contains(.visible) ? "0" : "1"
        SharedDisplayLinkDriver.shared.updateForegroundState(true)
        target.storyLabReset(revealed: plan.startRevealed)
        if plan.startOffset > 0 {
            target.storyLabScrollList(to: plan.startOffset)
        }
        self.samples = []
        self.gesture = 0
        self.inGesture = false
        self.gestureDeltas = [:]
        self.posted = 0
        self.delivered = 0
        self.windowed = 0
        StoryRevealLabRegistry.routing = [:]
        StoryRevealLabRegistry.layoutMs = []
        StoryRevealLabRegistry.eventMs = []
        Queue.mainQueue().after(0.35, {
            let before = target.storyLabSnapshot()
            if plan.startRevealed && before.progress < 1 {
                self.report.add(scenario: scenario, run: 0, metrics: ["startProgress": Double(before.progress)], notes: ["error": "could not start revealed"])
                self.next()
                return
            }
            if let window = target.storyLabWindow {
                let clock = PerfLabFrameClock(view: window.contentView!)
                clock.onFrame = { [weak self] _ in
                    self?.sample()
                }
                self.clock = clock
                clock.start()
            }
            self.play(plan.events, index: 0, completion: {
                self.clock?.stop()
                self.summarize(scenario, plan: plan, before: before)
                self.next()
            })
        })
    }

    private func sample() {
        guard let target = self.target else {
            return
        }
        self.samples.append(LabSample(time: CACurrentMediaTime(), gesture: self.inGesture ? self.gesture : -self.gesture, tracking: self.inGesture, snapshot: target.storyLabSnapshot()))
    }

    private func play(_ events: [LabEvent], index: Int, completion: @escaping () -> Void) {
        guard index < events.count else {
            completion()
            return
        }
        let event = events[index]
        Queue.mainQueue().after(event.delay, {
            switch event.kind {
            case .wait:
                break
            case let .mark(name):
                if name == "begin" {
                    self.gesture += 1
                    self.inGesture = true
                } else {
                    self.inGesture = false
                }
            case let .scroll(phase, momentum, dx, dy, precise, target):
                if let point = self.point(target) {
                    self.deliver(phase: phase, momentum: momentum, dx: dx, dy: dy, precise: precise, at: point)
                    if self.inGesture, dy != 0 {
                        self.gestureDeltas[self.gesture, default: 0] += dy
                    }
                }
            }
            self.play(events, index: index + 1, completion: completion)
        })
    }

    private func deliver(phase: Int64, momentum: Int64, dx: CGFloat, dy: CGFloat, precise: Bool, at point: NSPoint) {
        guard let window = self.target?.storyLabWindow else {
            return
        }
        let screen = window.convertPoint(toScreen: point)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let global = CGPoint(x: screen.x, y: primaryHeight - screen.y)
        let cgEvent: CGEvent?
        if precise {
            cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)
        } else {
            cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)
        }
        guard let cg = cgEvent else {
            return
        }
        cg.location = global
        if precise {
            cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(dy))
            cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(dx))
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(dy))
            cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(dx))
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        }
        cg.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        cg.timestamp = CGEventTimestamp(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
        guard let event = NSEvent(cgEvent: cg) else {
            return
        }
        Self.fakeMouse = point
        if self.configuration.string("-StoryLabDelivery", "queue") == "pid" {
            cg.postToPid(getpid())
        } else {
            NSApp.postEvent(event, atStart: false)
        }
        self.posted += 1
    }

    static func attach(_ event: NSEvent, to window: NSWindow, at point: NSPoint) {
        let base = Unmanaged.passUnretained(event).toOpaque()
        if let ivar = class_getInstanceVariable(NSEvent.self, "_window") {
            object_setIvar(event, ivar, window)
        }
        if let ivar = class_getInstanceVariable(NSEvent.self, "_windowNumber") {
            base.advanced(by: ivar_getOffset(ivar)).assumingMemoryBound(to: Int.self).pointee = window.windowNumber
        }
        if let ivar = class_getInstanceVariable(NSEvent.self, "_location") {
            base.advanced(by: ivar_getOffset(ivar)).assumingMemoryBound(to: CGPoint.self).pointee = point
        }
    }

    private func summarize(_ scenario: String, plan: Plan, before: StoryRevealLabSnapshot) {
        var metrics: [String: Double] = [:]
        var notes = self.notes
        let after = self.target?.storyLabSnapshot()
        let finalProgress = Double(after?.progress ?? -1)
        metrics["finalProgress"] = finalProgress
        metrics["pass"] = ((plan.expectRevealed && finalProgress >= 0.999) || (!plan.expectRevealed && finalProgress <= 0.001)) ? 1 : 0
        notes["final"] = after?.interface ?? "-"
        notes["driver"] = after?.driver ?? "-"
        notes["routing"] = StoryRevealLabRegistry.routing.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")

        var maxJump: Double = 0
        var flips = 0
        var maxDesync: Double = 0
        var maxStripStep: Double = 0
        var stripTravel: Double = 0
        var listTravel: Double = 0
        var maxListOffset: Double = 0
        var maxSideways: Double = 0
        var lastDirection: [Int: Double] = [:]
        var restGap: Double? = nil
        if let row = before.firstRowTopVisual, abs(before.tableOffsetVisual) <= 0.5 {
            restGap = Double(row - before.searchBottomVisual)
        }
        for i in 0 ..< self.samples.count {
            let s = self.samples[i].snapshot
            maxListOffset = max(maxListOffset, Double(s.tableOffsetVisual))
            maxSideways = max(maxSideways, abs(Double(s.tableOffsetX)))
            if let row = s.firstRowTopVisual, abs(s.tableOffsetVisual) <= 0.5 {
                if restGap == nil {
                    restGap = Double(row - s.searchBottomVisual)
                }
                maxDesync = max(maxDesync, abs(Double(row - s.searchBottomVisual) - (restGap ?? 0)))
            }
            guard i > 0 else {
                continue
            }
            let p = self.samples[i - 1].snapshot
            let step = Double(s.progress - p.progress)
            let g = self.samples[i].gesture
            if g <= 0 {
                maxJump = max(maxJump, abs(step))
            }
            if g > 0, plan.monotonicGestures, abs(step) > 0.002 {
                let direction = step > 0 ? 1.0 : -1.0
                if let last = lastDirection[g], last != direction {
                    flips += 1
                }
                lastDirection[g] = direction
            }
            if let a = s.stripOffsetVisual, let b = p.stripOffsetVisual {
                let step = abs(Double(a - b))
                maxStripStep = max(maxStripStep, step)
                if step >= 0.5 {
                    stripTravel += step
                }
            }
            listTravel += abs(Double(s.tableOffsetVisual - p.tableOffsetVisual))
        }
        metrics["frames"] = Double(self.samples.count)
        metrics["maxProgressStep"] = maxJump
        metrics["flips"] = Double(flips)
        metrics["maxDesyncPt"] = maxDesync
        metrics["maxStripStepPt"] = maxStripStep
        metrics["stripTravelPt"] = stripTravel
        metrics["listTravelPt"] = listTravel
        metrics["maxListOffset"] = maxListOffset
        metrics["maxSidewaysPt"] = max(maxSideways, abs(Double(after?.tableOffsetX ?? 0)))
        metrics["finalListOffset"] = Double(after?.tableOffset ?? -1)
        let events = StoryRevealLabRegistry.eventMs.sorted()
        if !events.isEmpty {
            metrics["eventMsP50"] = events[events.count / 2]
            metrics["eventMsP95"] = events[min(events.count - 1, Int(Double(events.count) * 0.95))]
            metrics["eventMsMax"] = events[events.count - 1]
        }
        let layout = StoryRevealLabRegistry.layoutMs.sorted()
        if !layout.isEmpty {
            metrics["layouts"] = Double(layout.count)
            metrics["layoutMsP50"] = layout[layout.count / 2]
            metrics["layoutMsP95"] = layout[min(layout.count - 1, Int(Double(layout.count) * 0.95))]
            metrics["layoutMsMax"] = layout[layout.count - 1]
        }
        metrics["posted"] = Double(self.posted)
        metrics["delivered"] = Double(self.delivered)
        metrics["windowed"] = Double(self.windowed)
        if let stats = self.clock?.stats {
            metrics["hitches"] = Double(stats.hitches)
            metrics["worstGapMs"] = stats.worstGap * 1000
        }
        var problems: [String] = []
        if metrics["pass"] == 0 {
            problems.append("ended \(after?.interface ?? "-") at \(String(format: "%.2f", finalProgress))")
        }
        if flips > 0 {
            problems.append("\(flips) direction flips")
        }
        if (metrics["maxSidewaysPt"] ?? 0) > 0.5 {
            problems.append(String(format: "list moved sideways %.0f pt", metrics["maxSidewaysPt"] ?? 0))
        }
        if maxDesync > 1.5 {
            problems.append(String(format: "header/list desync %.1f pt", maxDesync))
        }
        if !plan.listMayScroll && listTravel > 2 {
            problems.append(String(format: "list moved %.0f pt", listTravel))
        }
        if plan.listMustScroll && listTravel < 20 {
            problems.append(String(format: "list did not scroll (%.0f pt)", listTravel))
        }
        if plan.stripMustScroll && stripTravel < 20 {
            problems.append(String(format: "strip did not scroll (%.0f pt)", stripTravel))
        }
        if plan.stripMustStay && stripTravel > 2 {
            problems.append(String(format: "strip scrolled %.0f pt on a vertical gesture", stripTravel))
        }
        if maxStripStep > 60 {
            problems.append(String(format: "strip jumped %.0f pt in one frame", maxStripStep))
        }
        if maxJump > 0.34 {
            problems.append(String(format: "progress jumped %.2f in one frame", maxJump))
        }
        notes["problems"] = problems.isEmpty ? "none" : problems.joined(separator: "; ")
        metrics["problems"] = Double(problems.count)

        var rows: [[String: Any]] = []
        for s in self.samples {
            rows.append(["t": s.time, "g": s.gesture, "p": Double(s.snapshot.progress), "st": s.snapshot.interface, "off": Double(s.snapshot.tableOffsetVisual), "row": s.snapshot.firstRowTopVisual.map { Double($0) } ?? -1, "search": Double(s.snapshot.searchBottomVisual), "strip": s.snapshot.stripOffsetVisual.map { Double($0) } ?? -1, "space": Double(s.snapshot.spaceRowHeight), "nav": Double(s.snapshot.navigationHeight)])
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: ["scenario": scenario, "metrics": metrics, "notes": notes, "samples": rows], options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: self.directory.appendingPathComponent("\(scenario).json"))
        }
        notes["directory"] = self.directory.path
        self.report.add(scenario: scenario, run: 0, metrics: metrics, notes: notes)
    }
}
#endif
