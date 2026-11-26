import Cocoa
import XCTest
import TGUIKit
@testable import TooltipRows

final class TooltipTests: XCTestCase {
    private var windows: [NSWindow] = []
    private var oldItems: [ReferenceRowItem] = []
    private var event: NSEvent {
        NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
    }
    override func setUp() { initializeLab() }
    override func tearDown() {
        windows.forEach { $0.contentView = nil; $0.close() }
        windows.removeAll()
        oldItems.forEach { $0.stop() }
        oldItems.removeAll()
        XCTAssertFalse(LabTimer.records.contains { $0.active })
    }
    private func host(_ view: NSView) -> NSView {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        window.contentView = parent
        parent.addSubview(view)
        windows.append(window)
        XCTAssertFalse(view.visibleRect.isEmpty)
        return parent
    }
    private func pump(_ duration: Double = 0.05) {
        let done = expectation(description: "main queue timers")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { done.fulfill() }
        wait(for: [done], timeout: duration + 3)
    }
    private func current() -> CurrentTooltipView {
        let view = CurrentTooltipView(frame: NSRect(x: 0, y: 0, width: 120, height: 30))
        _ = host(view)
        return view
    }
    private func reference() -> ReferenceTooltipView {
        let view = ReferenceTooltipView(frame: NSRect(x: 0, y: 0, width: 120, height: 30))
        _ = host(view)
        return view
    }

    func testBaselineReproducesWrongTooltipAfterRebinding() {
        let old = reference(), new = current()
        let oldA = ReferenceRowItem(date: "A"), oldB = ReferenceRowItem(date: "B")
        oldItems += [oldA, oldB]
        let newA = ChatRowItem(date: "A"), newB = ChatRowItem(date: "B")
        old.set(oldA); old.mouseMoved(with: event)
        new.set(newA); new.mouseMoved(with: event)
        let firstNewTimer = LabTimer.records.last!
        old.set(oldB); new.set(newB)
        XCTAssertFalse(firstNewTimer.active)
        pump()
        XCTAssertEqual(old.toolTip, "A\n\nAuto delete: 50s")
        XCTAssertEqual(new.toolTip, "B\n\nAuto delete: 50s")
    }

    func testBaselineReproducesCallbackStolenByCopiedMediaView() {
        let clock = Clock()
        let old = reference(), oldCopy = reference(), new = current(), newCopy = current()
        let oldItem = ReferenceRowItem(clock: clock), newItem = ChatRowItem(clock: clock)
        oldItems.append(oldItem)
        old.set(oldItem); old.mouseMoved(with: event)
        new.set(newItem); new.mouseMoved(with: event)
        oldCopy.set(oldItem); newCopy.set(newItem)
        clock.timestamp = 110
        pump()
        XCTAssertEqual(old.toolTip, "message date")
        XCTAssertEqual(oldCopy.toolTip, "message date\n\nAuto delete: 40s")
        XCTAssertEqual(new.toolTip, "message date\n\nAuto delete: 40s")
        XCTAssertEqual(newCopy.toolTip, "message date")
        newCopy.mouseMoved(with: event)
        let copyTimer = LabTimer.records.last!
        newCopy.removeFromSuperview()
        XCTAssertFalse(copyTimer.active)
        clock.timestamp = 115
        pump()
        XCTAssertEqual(new.toolTip, "message date\n\nAuto delete: 35s")
        XCTAssertEqual(newItem.fullDate, "message date")
    }

    func testDetachedViewCancelsImmediatelyAndDoesNotReceiveTicks() {
        let old = reference(), new = current()
        let oldItem = ReferenceRowItem(), newItem = ChatRowItem()
        oldItems.append(oldItem)
        old.set(oldItem); old.mouseMoved(with: event)
        let oldTimer = LabTimer.records.last!
        new.set(newItem); new.mouseMoved(with: event)
        let newTimer = LabTimer.records.last!
        old.removeFromSuperview(); new.removeFromSuperview()
        XCTAssertTrue(oldTimer.active)
        XCTAssertFalse(newTimer.active)
        let count = newTimer.fires
        pump()
        XCTAssertGreaterThan(oldTimer.fires, 0)
        XCTAssertEqual(newTimer.fires, count)
        _ = host(new)
        new.mouseEntered(with: event)
        XCTAssertTrue(LabTimer.records.last!.active)
    }

    func testRepeatedBindingAndMouseMovementKeepOneTimer() {
        let view = current(), item = ChatRowItem()
        view.set(item); view.mouseEntered(with: event)
        let timer = LabTimer.records.last!
        for _ in 0..<1000 {
            view.set(item)
            view.mouseMoved(with: event)
        }
        XCTAssertEqual(LabTimer.records.count, 1)
        XCTAssertEqual(timer.starts, 1)
        XCTAssertEqual(view.toolTip, "message date\n\nAuto delete: 50s")
        view.mouseExited(with: event)
        XCTAssertFalse(timer.active)
        view.mouseMoved(with: event)
        XCTAssertEqual(LabTimer.records.count, 2)
        XCTAssertTrue(LabTimer.records.last!.active)
    }

    func testInactiveViewsStopOnTheirNextTick() {
        for state in 0..<4 {
            let view = current(), item = ChatRowItem()
            view.set(item); view.mouseMoved(with: event)
            let timer = LabTimer.records.last!
            switch state {
            case 0: view.pointerInside = false
            case 1: view.isHidden = true
            case 2: view.superview!.isHidden = true
            default: view.setFrameOrigin(NSPoint(x: 1000, y: 0))
            }
            pump()
            XCTAssertFalse(timer.active)
            let count = timer.fires
            pump()
            XCTAssertEqual(timer.fires, count)
        }
    }

    func testUnchangedDateAvoidsNativeTooltipAssignments() {
        let old = reference(), new = current()
        let oldItem = ReferenceRowItem(begin: nil), newItem = ChatRowItem(begin: nil)
        oldItems.append(oldItem)
        old.set(oldItem); new.set(newItem)
        var oldChanges = 0, newChanges = 0
        let oldObservation = old.observe(\.toolTip, options: [.new]) { _, _ in oldChanges += 1 }
        let newObservation = new.observe(\.toolTip, options: [.new]) { _, _ in newChanges += 1 }
        for _ in 0..<1000 { old.set(oldItem); new.set(newItem) }
        XCTAssertEqual(oldChanges, 1000)
        XCTAssertEqual(newChanges, 0)
        let sameDate = ChatRowItem(begin: nil)
        new.set(sameDate)
        XCTAssertEqual(newChanges, 0)
        let changed = ChatRowItem(date: "different", begin: nil)
        new.set(changed)
        XCTAssertEqual(newChanges, 1)
        XCTAssertEqual(new.toolTip, "different")
        let empty = ChatRowItem(date: nil, begin: nil)
        new.set(empty)
        XCTAssertEqual(newChanges, 2)
        XCTAssertNil(new.toolTip)
        withExtendedLifetime((oldObservation, newObservation)) {}
    }

    func testBindingBenchmark() throws {
        guard ProcessInfo.processInfo.environment["CHAT_TOOLTIP_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        let old = reference(), new = current()
        var results: [[String: Any]] = []
        for scenario in ["same_item", "same_date_reuse", "changing_date"] {
            let before = (0..<100).map { ReferenceRowItem(date: scenario == "changing_date" ? "date \($0)" : "message date", begin: nil) }
            let after = (0..<100).map { ChatRowItem(date: scenario == "changing_date" ? "date \($0)" : "message date", begin: nil) }
            oldItems += before
            let count = 5000
            func measure(_ baseline: Bool) -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                for i in 0..<count {
                    let index = scenario == "same_item" ? 0 : i % 100
                    if baseline { old.set(before[index]) } else { new.set(after[index]) }
                }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(count)
            }
            _ = measure(true); _ = measure(false)
            var oldTrials: [Double] = [], newTrials: [Double] = []
            for batch in 0..<9 {
                if batch % 2 == 0 { oldTrials.append(measure(true)); newTrials.append(measure(false)) }
                else { newTrials.append(measure(false)); oldTrials.append(measure(true)) }
            }
            XCTAssertEqual(old.toolTip, new.toolTip)
            results.append(["scenario": scenario, "baseline_ns": oldTrials.sorted()[4], "candidate_ns": newTrials.sorted()[4], "baseline_trials_ns": oldTrials, "candidate_trials_ns": newTrials])
        }
        let data = try JSONSerialization.data(withJSONObject: ["iterations_per_batch": 5000, "batches": 9, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-tooltip-binding-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }

    func testUnchangedCountdownDoesNotReassignTheNativeTooltip() {
        let view = current(), clock = Clock()
        let item = ChatRowItem(clock: clock)
        view.set(item); view.mouseMoved(with: event)
        var changes = 0
        let observation = view.observe(\.toolTip, options: [.new]) { _, _ in changes += 1 }
        pump()
        XCTAssertGreaterThan(LabTimer.records.last!.fires, 0)
        XCTAssertEqual(changes, 0)
        clock.timestamp = 110
        pump()
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(view.toolTip, "message date\n\nAuto delete: 40s")
        withExtendedLifetime(observation) {}
    }

    func testExpiryRestoresBaseDateAndDoesNotRestart() {
        let view = current(), clock = Clock()
        let item = ChatRowItem(clock: clock)
        view.set(item); view.mouseMoved(with: event)
        clock.timestamp = 150
        pump()
        XCTAssertEqual(view.toolTip, "message date\n\nAuto delete: 0s")
        clock.timestamp = 151
        pump()
        XCTAssertEqual(view.toolTip, "message date")
        XCTAssertFalse(LabTimer.records.last!.active)
        view.mouseMoved(with: event)
        XCTAssertEqual(LabTimer.records.count, 1)
    }

    func testMissingCountdownAndPlainRowReuseDoNotStartTimers() {
        for item in [ChatRowItem(date: nil), ChatRowItem(begin: nil), ChatRowItem(begin: 0, timeout: 1)] {
            let view = current()
            view.set(item); view.mouseMoved(with: event)
            XCTAssertTrue(LabTimer.records.isEmpty)
            XCTAssertEqual(view.toolTip, item.fullDate)
        }
        let view = current(), timed = ChatRowItem(), plain = ChatRowItem(date: "plain", begin: nil)
        view.set(timed); view.mouseMoved(with: event)
        let timer = LabTimer.records.last!
        view.set(plain)
        XCTAssertFalse(timer.active)
        XCTAssertEqual(view.toolTip, "plain")
        let detached = CurrentTooltipView(frame: NSRect(x: 0, y: 0, width: 120, height: 30))
        detached.set(timed); detached.mouseMoved(with: event)
        XCTAssertEqual(LabTimer.records.count, 1)
    }

    func testViewAndItemReleaseDoNotLeaveLiveTimers() {
        weak var released: CurrentTooltipView?
        let item = ChatRowItem()
        autoreleasepool {
            let view = current()
            view.set(item); view.mouseMoved(with: event)
            view.removeFromSuperview()
            released = view
        }
        XCTAssertNil(released)
        XCTAssertFalse(LabTimer.records.last!.active)
        let view = current()
        weak var releasedItem: ChatRowItem?
        autoreleasepool {
            let item = ChatRowItem()
            releasedItem = item
            view.set(item); view.mouseMoved(with: event)
        }
        XCTAssertNil(releasedItem)
        pump()
        XCTAssertFalse(LabTimer.records.last!.active)
        XCTAssertNil(view.toolTip)
    }

    func testCountdownArithmeticDoesNotOverflowAtInt32Boundaries() {
        let clock = Clock()
        clock.timestamp = .max
        let item = ChatRowItem(date: "future", begin: .max - 5, timeout: 10, clock: clock)
        XCTAssertEqual(item.tooltipCountdownText(), "future\n\nAuto delete: 5s")
        clock.timestamp = .min
        let large = ChatRowItem(date: "large", begin: .max, timeout: .max, clock: clock)
        XCTAssertEqual(large.tooltipCountdownText(), "large\n\nAuto delete: 6442450942s")
        let expired = ChatRowItem(begin: .min, timeout: 1)
        XCTAssertNil(expired.tooltipCountdownText())
    }

    func testRealOneSecondTimersStopAfterThirtyScrollReuses() throws {
        LabTimer.scale = 1
        let old = reference(), new = current()
        let originals = (0..<30).map { ReferenceRowItem(date: "message \($0)") }
        let candidates = (0..<30).map { ChatRowItem(date: "message \($0)") }
        oldItems += originals
        for item in originals { old.set(item); old.mouseMoved(with: event) }
        let before = LabTimer.records
        for item in candidates { new.set(item); new.mouseMoved(with: event) }
        let after = Array(LabTimer.records.dropFirst(before.count))
        XCTAssertEqual(before.filter { $0.active }.count, 30)
        XCTAssertEqual(after.filter { $0.active }.count, 1)
        old.removeFromSuperview(); new.removeFromSuperview()
        XCTAssertEqual(after.filter { $0.active }.count, 0)
        pump(1.3)
        let baselineFires = before.reduce(0) { $0 + $1.fires }
        let candidateFires = after.reduce(0) { $0 + $1.fires }
        XCTAssertGreaterThanOrEqual(baselineFires, 30)
        XCTAssertEqual(candidateFires, 0)
        let result: [String: Any] = ["reuses": 30, "timer_interval_seconds": 1, "observation_seconds": 1.3, "baseline_active_after_detach": before.filter { $0.active }.count, "candidate_active_after_detach": after.filter { $0.active }.count, "baseline_fires_after_detach": baselineFires, "candidate_fires_after_detach": candidateFires]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-tooltip-timers.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
