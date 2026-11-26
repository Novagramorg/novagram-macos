import XCTest
import Cocoa
@testable import StoriesUI

final class StoryStripScrollRouterTests: XCTestCase {
    private var time: Double = 100

    private func now() -> Double {
        self.time += 1.0 / 120.0
        return self.time
    }

    private func gesture(_ router: inout StoryStripScrollRouter, _ deltas: [(CGFloat, CGFloat)], expanded: Bool = true) -> [StoryStripScrollRoute] {
        var routes: [StoryStripScrollRoute] = []
        for (i, delta) in deltas.enumerated() {
            routes.append(router.route(phase: i == 0 ? .began : .changed, momentumPhase: [], dx: delta.0, dy: delta.1, precise: true, expanded: expanded, time: self.now()))
        }
        routes.append(router.route(phase: .ended, momentumPhase: [], dx: 0, dy: 0, precise: true, expanded: expanded, time: self.now()))
        return routes
    }

    func testHorizontalSwipesScrollTheStripNatively() {
        var router = StoryStripScrollRouter()
        let routes = self.gesture(&router, [(-6, 0.4), (-6, 1.5), (-8, 3), (-2, 4)])
        XCTAssertEqual(routes, [.native, .native, .native, .native, .native], "a vertical wobble never turns a sideways swipe into a reveal, and the end stays with the strip")
        XCTAssertEqual(router.axis, .horizontal)
    }

    func testVerticalSwipesGoToTheChatList() {
        var router = StoryStripScrollRouter()
        let routes = self.gesture(&router, [(0.3, -3), (2, -3), (6, -1)])
        XCTAssertEqual(routes, [.forward, .forward, .forward, .forward])
        XCTAssertEqual(router.axis, .vertical)
    }

    func testTheAxisIsDecidedByTheFirstMovementAndKeptForTheGesture() {
        var router = StoryStripScrollRouter()
        XCTAssertEqual(router.route(phase: .began, momentumPhase: [], dx: 0, dy: 0, precise: true, expanded: true, time: self.now()), .forward, "an empty start reaches the chat list so it can hold the gesture at the top")
        XCTAssertNil(router.axis)
        XCTAssertEqual(router.route(phase: .changed, momentumPhase: [], dx: 0, dy: 0, precise: true, expanded: true, time: self.now()), .ignore)
        XCTAssertEqual(router.route(phase: .changed, momentumPhase: [], dx: 0.5, dy: 3, precise: true, expanded: true, time: self.now()), .forward)
        XCTAssertEqual(router.route(phase: .changed, momentumPhase: [], dx: 9, dy: 0, precise: true, expanded: true, time: self.now()), .forward, "a vertical gesture stays vertical")
        XCTAssertEqual(router.route(phase: .began, momentumPhase: [], dx: -6, dy: 1, precise: true, expanded: true, time: self.now()), .native, "a new gesture decides again")
    }

    func testMomentumFollowsTheGestureAxis() {
        var router = StoryStripScrollRouter()
        _ = self.gesture(&router, [(0, -4), (0, -6)])
        XCTAssertEqual(router.route(phase: [], momentumPhase: .began, dx: 0, dy: -8, precise: true, expanded: true, time: self.now()), .forward)
        XCTAssertEqual(router.route(phase: [], momentumPhase: .ended, dx: 0, dy: 0, precise: true, expanded: true, time: self.now()), .forward)
    }

    func testEverythingGoesToTheChatListWhileTheStripIsNotFullyOpen() {
        var router = StoryStripScrollRouter()
        let routes = self.gesture(&router, [(-8, 0), (-8, 0)], expanded: false)
        XCTAssertEqual(routes, [.forward, .forward, .forward])
    }

    func testTouchingTheTrackpadReachesTheChatList() {
        var router = StoryStripScrollRouter()
        _ = self.gesture(&router, [(-6, 0)])
        XCTAssertEqual(router.route(phase: .mayBegin, momentumPhase: [], dx: 0, dy: 0, precise: true, expanded: true, time: self.now()), .forward)
        XCTAssertNil(router.axis)
    }

    func testAMouseWheelScrollsTheOpenStripSideways() {
        var router = StoryStripScrollRouter()
        XCTAssertEqual(router.route(phase: [], momentumPhase: [], dx: 0, dy: 2, precise: false, expanded: true, time: self.now()), .scrollHorizontally(2))
        XCTAssertEqual(router.route(phase: [], momentumPhase: [], dx: 0, dy: -1, precise: false, expanded: true, time: self.now()), .scrollHorizontally(-1))
        XCTAssertEqual(router.route(phase: [], momentumPhase: [], dx: 0, dy: 1, precise: false, expanded: false, time: self.now()), .forward, "while the strip is closed the wheel opens it")
        XCTAssertEqual(router.route(phase: [], momentumPhase: [], dx: 1, dy: 0, precise: false, expanded: true, time: self.now()), .native)
        XCTAssertEqual(router.route(phase: [], momentumPhase: [], dx: 0, dy: 0, precise: false, expanded: true, time: self.now()), .ignore)
    }

    func testPreciseEventsWithoutPhasesFollowTheDominantAxis() {
        var router = StoryStripScrollRouter()
        XCTAssertEqual(router.route(phase: [], momentumPhase: [], dx: 0, dy: 1, precise: true, expanded: true, time: self.now()), .forward)
        XCTAssertEqual(router.route(phase: [], momentumPhase: [], dx: 1, dy: 0, precise: true, expanded: true, time: self.now()), .native)
    }

    func testTheEndOfANativeSwipeStaysWithTheStrip() {
        var router = StoryStripScrollRouter()
        XCTAssertEqual(router.route(phase: .began, momentumPhase: [], dx: -6, dy: 0, precise: true, expanded: true, time: self.now()), .native)
        XCTAssertEqual(router.route(phase: .ended, momentumPhase: [], dx: 0, dy: 0, precise: true, expanded: true, time: self.now()), .native)
        XCTAssertEqual(router.route(phase: [], momentumPhase: .began, dx: -8, dy: 0, precise: true, expanded: true, time: self.now()), .native)
        XCTAssertEqual(router.route(phase: [], momentumPhase: .ended, dx: 0, dy: 0, precise: true, expanded: true, time: self.now()), .native)
        XCTAssertEqual(router.route(phase: .began, momentumPhase: [], dx: 0, dy: 0, precise: true, expanded: true, time: self.now()), .forward, "the next gesture starts fresh")
    }

    func testAnUnseenEndOfANativeSwipeDoesNotCaptureALaterPull() {
        var router = StoryStripScrollRouter()
        XCTAssertEqual(router.route(phase: .began, momentumPhase: [], dx: -6, dy: 0, precise: true, expanded: true, time: self.now()), .native)
        self.time += StoryStripScrollRouter.nativeTail + 0.2
        XCTAssertEqual(router.route(phase: .ended, momentumPhase: [], dx: 0, dy: 0, precise: true, expanded: true, time: self.now()), .forward, "a pull that ends over the strip: the chat list must see the end of its own gesture")
    }

    func testANativeSwipeDoesNotLeaveAStaleAxisForTheNextGesture() {
        var router = StoryStripScrollRouter()
        XCTAssertEqual(router.route(phase: .began, momentumPhase: [], dx: -6, dy: 0, precise: true, expanded: true, time: self.now()), .native)
        self.time += StoryStripScrollRouter.nativeTail + 0.2
        XCTAssertEqual(router.route(phase: .changed, momentumPhase: [], dx: 0.5, dy: 4, precise: true, expanded: true, time: self.now()), .forward, "the strip owned that swipe and the router never saw it end: a pull that started over the list and reached the strip stays with the list")
        XCTAssertEqual(router.axis, .vertical)
    }

    func testAPullThatReachesTheStripIsNeverTakenByIt() {
        var router = StoryStripScrollRouter()
        XCTAssertEqual(router.route(phase: .changed, momentumPhase: [], dx: -5, dy: 1, precise: true, expanded: true, time: self.now()), .forward, "the strip never saw this gesture begin, so a sideways drift at the end of a pull stays with the chat list")
        XCTAssertNil(router.axis)
        XCTAssertEqual(router.route(phase: .ended, momentumPhase: [], dx: 0, dy: 0, precise: true, expanded: true, time: self.now()), .forward)
    }

    func testOwnershipEndsWithTheGesture() {
        var router = StoryStripScrollRouter()
        XCTAssertEqual(router.route(phase: .began, momentumPhase: [], dx: 0, dy: 0, precise: true, expanded: true, time: self.now()), .forward)
        XCTAssertEqual(router.route(phase: .ended, momentumPhase: [], dx: 0, dy: 0, precise: true, expanded: true, time: self.now()), .forward)
        XCTAssertNil(router.axis)
        XCTAssertEqual(router.route(phase: .changed, momentumPhase: [], dx: -6, dy: 0, precise: true, expanded: true, time: self.now()), .forward, "the next gesture started over the list")
    }

    func testTheWheelOnlyScrollsTheStripWhenItCanMove() {
        XCTAssertNil(StoryStripScrollRouter.wheelOffset(current: 0, delta: -1, limit: 0), "a strip that fits passes the wheel on to the chat list")
        XCTAssertNil(StoryStripScrollRouter.wheelOffset(current: 0, delta: 2, limit: 300), "already at the start")
        XCTAssertNil(StoryStripScrollRouter.wheelOffset(current: 300, delta: -2, limit: 300), "already at the end")
        XCTAssertEqual(StoryStripScrollRouter.wheelOffset(current: 0, delta: -2, limit: 300), 20)
        XCTAssertEqual(StoryStripScrollRouter.wheelOffset(current: 295, delta: -2, limit: 300), 300)
        XCTAssertEqual(StoryStripScrollRouter.wheelOffset(current: 100, delta: 3, limit: 300), 70)
    }
}
