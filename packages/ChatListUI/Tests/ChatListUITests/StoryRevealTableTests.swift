import XCTest
import Cocoa
import TGUIKit
@testable import ChatListUI

private final class SpacerItem: TableRowItem {
    private let fraction: () -> CGFloat

    init(_ size: NSSize, fraction: @escaping () -> CGFloat) {
        self.fraction = fraction
        super.init(size, stableId: AnyHashable("space"))
    }

    override var height: CGFloat {
        return 30 + StoryRevealModel.span * self.fraction()
    }
}

private final class ChatItem: TableRowItem {
    init(_ size: NSSize, id: Int) {
        super.init(size, stableId: AnyHashable(id))
    }

    override var height: CGFloat {
        return 60
    }
}

final class StoryRevealTableTests: XCTestCase {
    private static let registerThemeImages: Void = {
        for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand"] where NSImage(named: name) == nil {
            let image = NSImage(size: NSSize(width: 10, height: 10))
            image.lockFocus()
            NSColor.gray.setFill()
            NSRect(x: 0, y: 0, width: 10, height: 10).fill()
            image.unlockFocus()
            image.setName(name)
        }
    }()

    private var window: Window!
    private var table: TableView!
    private var model: StoryRevealModel!
    private var driver: StoryRevealDriver!
    private var clock: Double = 1000
    private var eventInterval: Double = 1.0 / 120.0
    private var seen = 0

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        _ = StoryRevealTableTests.registerThemeImages
        self.window = Window(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        self.window.isReleasedWhenClosed = false
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        self.window.contentView?.addSubview(table)
        self.table = table
        let model = StoryRevealModel()
        self.model = model
        _ = table.addItem(item: SpacerItem(NSSize(width: 400, height: 30), fraction: { [weak model] in model?.fraction ?? 0 }))
        for i in 0 ..< 80 {
            _ = table.addItem(item: ChatItem(NSSize(width: 400, height: 60), id: i))
        }
        let driver = StoryRevealDriver(table: table, model: model, now: { [weak self] in self?.clock ?? 0 })
        driver.didChange = { [weak table] _, _ in
            table?.noteHeightOfRow(0, false)
        }
        self.driver = driver
        table.applyExternalScroll = { [weak self] event in
            guard let self = self else {
                return false
            }
            self.seen += 1
            self.clock += self.eventInterval
            return self.driver.handle(event)
        }
        self.window.orderFrontRegardless()
        self.spin(0.05)
    }

    override func tearDown() {
        self.driver = nil
        self.window.orderOut(nil)
        self.window = nil
        super.tearDown()
    }

    private func animate(_ seconds: Double) -> [CGFloat] {
        var travel: [CGFloat] = []
        let end = self.clock + seconds
        while self.clock < end {
            self.clock += 1.0 / 120.0
            self.driver.tick()
            travel.append((1 - self.model.fraction) * StoryRevealModel.span + self.table.documentOffset.y)
        }
        return travel
    }

    private func flickUp(_ deltas: [CGFloat]) {
        self.gesture {
            self.send(phase: 128, dy: 0)
            for (i, delta) in deltas.enumerated() {
                self.send(phase: i == 0 ? 1 : 2, dy: delta)
            }
            self.send(phase: 4, dy: 0)
        }
    }

    private var listLimit: CGFloat {
        return self.table.documentSize.height - self.table.clipView.bounds.height
    }

    private func spin(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.004))
        }
    }

    private var queued: [NSEvent] = []

    private func send(phase: Int64, momentum: Int64 = 0, dy: CGFloat) {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy.rounded()), wheel2: 0, wheel3: 0) else {
            XCTFail("no event")
            return
        }
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(dy))
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(dy))
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        cg.timestamp = CGEventTimestamp(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
        guard let event = NSEvent(cgEvent: cg) else {
            XCTFail("no event")
            return
        }
        NSApp.postEvent(event, atStart: false)
        if !self.batching {
            self.dispatchQueued()
        }
    }

    private var batching = false

    private func gesture(_ body: () -> Void) {
        self.batching = true
        body()
        self.batching = false
        self.dispatchQueued()
    }

    private func dispatchQueued() {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, let event = NSApp.nextEvent(matching: .scrollWheel, until: Date(), inMode: .default, dequeue: true) {
            self.table.scrollWheel(with: event)
        }
        self.spin(1.0 / 120.0)
    }

    private func spacerHeight() -> CGFloat {
        return self.table.item(at: 0).height
    }

    func testCollapsingHandsTheRestOfTheGestureToTheList() {
        self.driver.setRevealed(true, animated: false)
        self.gesture {
            self.send(phase: 128, dy: 0)
            self.send(phase: 1, dy: -20)
            for _ in 0 ..< 7 {
                self.send(phase: 2, dy: -20)
            }
            self.send(phase: 4, dy: 0)
        }
        self.spin(0.2)
        XCTAssertEqual(self.model.fraction, 0)
        XCTAssertEqual(self.spacerHeight(), 30)
        XCTAssertGreaterThan(self.table.documentOffset.y, 30, "the part of the swipe left after collapsing scrolls the list")
        XCTAssertEqual(self.seen, 6, "once the list takes the gesture the scroll view keeps the rest of it")
    }

    func testAFlickUpClosesTheStoriesAndGlidesTheList() {
        self.driver.setRevealed(true, animated: false)
        self.flickUp([-8, -12, -16])
        guard let glide = self.model.glide else {
            return XCTFail("a flick up glides")
        }
        XCTAssertTrue(self.driver.isTicking)
        XCTAssertEqual(self.table.documentOffset.y, 0, accuracy: 0.5)
        let travel = self.animate(3)
        XCTAssertEqual(self.model.fraction, 0)
        XCTAssertEqual(self.spacerHeight(), 30)
        XCTAssertEqual(self.table.documentOffset.y, glide.totalDistance - glide.fromFraction * StoryRevealModel.span, accuracy: 1)
        XCTAssertEqual(self.table.clipView.bounds.origin.x, 0, "the glide never moves the list sideways")
        XCTAssertNil(self.model.glide)
        XCTAssertFalse(self.driver.isTicking)
        var lastStep = CGFloat.greatestFiniteMagnitude
        for i in 1 ..< travel.count {
            let step = travel[i] - travel[i - 1]
            XCTAssertGreaterThanOrEqual(step, -0.01)
            XCTAssertLessThanOrEqual(step, lastStep + 0.01, "header and list move as one decelerating motion")
            lastStep = step
        }
    }

    func testSystemMomentumDuringAGlideDoesNotScrollTwice() {
        self.driver.setRevealed(true, animated: false)
        self.flickUp([-8, -12, -16])
        guard let glide = self.model.glide else {
            return XCTFail("a flick up glides")
        }
        self.gesture {
            var delta: CGFloat = -24
            self.send(phase: 0, momentum: 1, dy: delta)
            for _ in 0 ..< 30 {
                delta *= 0.9
                self.send(phase: 0, momentum: 2, dy: delta)
            }
            self.send(phase: 0, momentum: 3, dy: 0)
        }
        _ = self.animate(3)
        XCTAssertEqual(self.table.documentOffset.y, glide.totalDistance - glide.fromFraction * StoryRevealModel.span, accuracy: 1)
    }

    func testTouchingTheTrackpadStopsTheGlideWhereItIs() {
        self.driver.setRevealed(true, animated: false)
        self.flickUp([-8, -12, -16])
        _ = self.animate(0.25)
        let offset = self.table.documentOffset.y
        XCTAssertGreaterThan(offset, 50)
        self.send(phase: 128, dy: 0)
        XCTAssertNil(self.model.glide)
        _ = self.animate(0.5)
        XCTAssertEqual(self.table.documentOffset.y, offset, accuracy: 13, "at most the one frame up to the touch")
        XCTAssertFalse(self.driver.isTicking)
    }

    func testTheGlideKeepsGoingWhenTheListShiftsUnderIt() {
        self.driver.setRevealed(true, animated: false)
        self.flickUp([-8, -12, -16])
        guard let glide = self.model.glide else {
            return XCTFail("a flick up glides")
        }
        _ = self.animate(0.2)
        let shifted = self.table.documentOffset.y + 60
        self.table.clipView.scroll(to: NSPoint(x: 0, y: shifted), animated: false)
        _ = self.animate(3)
        XCTAssertEqual(self.table.documentOffset.y, glide.totalDistance - glide.fromFraction * StoryRevealModel.span + 60, accuracy: 1, "a row inserted above moves the list and the glide continues from there")
    }

    func testANonAnimatedScrollOnlyMovesVertically() {
        self.table.clipView.scroll(to: NSPoint(x: 0, y: 120), animated: false)
        XCTAssertEqual(self.table.clipView.bounds.origin.x, 0)
        XCTAssertEqual(self.table.clipView.bounds.origin.y, 120)
        self.table.clipView.scroll(to: NSPoint(x: 0, y: 0), animated: false)
        XCTAssertEqual(self.table.clipView.bounds.origin, .zero)
    }

    func testTheGlideStopsAtTheEndOfTheList() {
        self.driver.setRevealed(true, animated: false)
        self.eventInterval = 1.0 / 1000.0
        self.flickUp([-25, -25, -26])
        self.eventInterval = 1.0 / 120.0
        XCTAssertNotNil(self.model.glide)
        XCTAssertGreaterThan(self.model.glide?.totalDistance ?? 0, self.listLimit)
        _ = self.animate(1.5)
        XCTAssertEqual(self.table.documentOffset.y, self.listLimit, accuracy: 0.5)
        XCTAssertNil(self.model.glide, "stops instead of pushing against the end")
        XCTAssertFalse(self.driver.isTicking)
    }

    func testASlowCloseOnlySnapsTheStories() {
        self.driver.setRevealed(true, animated: false)
        self.gesture {
            self.send(phase: 128, dy: 0)
            self.send(phase: 1, dy: -5)
            for _ in 0 ..< 8 {
                self.send(phase: 2, dy: -5)
            }
        }
        self.clock += 0.3
        self.send(phase: 4, dy: 0)
        XCTAssertEqual(self.model.spring?.target, 0)
        _ = self.animate(1)
        XCTAssertEqual(self.model.fraction, 0)
        XCTAssertEqual(self.table.documentOffset.y, 0, accuracy: 0.5)
    }

    func testPullingAtTheTopMovesOnlyTheStories() {
        self.send(phase: 128, dy: 0)
        self.send(phase: 1, dy: 3)
        for _ in 0 ..< 19 {
            self.send(phase: 2, dy: 3)
        }
        XCTAssertEqual(self.model.fraction, 60 / StoryRevealModel.span, accuracy: 1e-9)
        XCTAssertEqual(self.spacerHeight(), 90, accuracy: 1e-9)
        XCTAssertEqual(self.table.documentOffset.y, 0, accuracy: 0.5, "the list itself does not rubber-band while the stories open")
        self.send(phase: 4, dy: 0)
        XCTAssertEqual(self.model.spring?.target, 1)
    }

    func testAPullWhoseFirstEventHasNoDeltaStillRevealsTheStories() {
        self.gesture {
            self.send(phase: 128, dy: 0)
            self.send(phase: 1, dy: 0)
            for _ in 0 ..< 20 {
                self.send(phase: 2, dy: 3)
            }
            self.send(phase: 4, dy: 0)
        }
        self.spin(0.2)
        XCTAssertEqual(self.model.fraction, 60 / StoryRevealModel.span, accuracy: 1e-9)
        XCTAssertEqual(self.model.spring?.target, 1)
        XCTAssertEqual(self.table.documentOffset.y, 0, accuracy: 0.5)
    }

    func testScrollingDownFromTheTopStaysWithTheList() {
        self.gesture {
            self.send(phase: 128, dy: 0)
            self.send(phase: 1, dy: 0)
            for _ in 0 ..< 10 {
                self.send(phase: 2, dy: -10)
            }
            self.send(phase: 4, dy: 0)
        }
        self.spin(0.2)
        XCTAssertEqual(self.model.fraction, 0)
        XCTAssertGreaterThan(self.table.documentOffset.y, 80)
    }

    func testAPullThatStartsBelowTheTopBouncesTheListInstead() {
        self.table.clipView.scroll(to: NSPoint(x: 0, y: 90), animated: false)
        self.spin(0.05)
        XCTAssertEqual(self.table.documentOffset.y, 90, accuracy: 0.5)
        self.gesture {
            self.send(phase: 128, dy: 0)
            self.send(phase: 1, dy: 10)
            for _ in 0 ..< 15 {
                self.send(phase: 2, dy: 10)
            }
            self.send(phase: 4, dy: 0)
        }
        self.spin(0.6)
        XCTAssertEqual(self.model.fraction, 0)
        XCTAssertLessThan(self.table.documentOffset.y, 1, "the list scrolled back to the top on its own")
    }
}
