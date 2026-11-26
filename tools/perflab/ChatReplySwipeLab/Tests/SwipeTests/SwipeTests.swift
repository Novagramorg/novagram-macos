import Cocoa
import XCTest
import TGUIKit

final class SwipeTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }
    private var left: SwipeDirection { .left(.failed(delta: 0, controller: ViewController())) }
    private var right: SwipeDirection { .right(.success(delta: 0, controller: ViewController())) }
    private func row() -> CandidateRow { CandidateRow(frame: NSRect(x: 0, y: 0, width: 400, height: 80)) }
    private func finish(_ animation: CAAnimation) { animation.delegate?.animationDidStop?(animation, finished: true) }

    func testIdleRowsAllocateNoSwipeContainerDuringLayoutOrCompletion() {
        let view = row()
        XCTAssertNil(view.swipeContainer)
        for _ in 0..<100 { view.layoutSwipe() }
        XCTAssertNil(view.swipeContainer)
        view.completeReveal(direction: left)
        XCTAssertNil(view.swipeContainer)
        XCTAssertFalse(view.hasRevealState)
    }

    func testInvalidItemDoesNotCreateSwipeViewsOrShiftContent() {
        let view = row()
        view.item = nil
        view.moveReveal(delta: -50)
        XCTAssertNil(view.swipeContainer)
        XCTAssertEqual(view.containerX, 0)
    }

    func testOldDismissalCannotRemoveNewGesture() throws {
        let view = row()
        view.moveReveal(delta: -40)
        let previous = try XCTUnwrap(view.swipeContainer?.subviews.first as? ChatSwipeToReplyView)
        view.completeReveal(direction: left)
        let animation = try XCTUnwrap(previous.layer?.animation(forKey: "opacity"))
        view.initRevealState()
        view.moveReveal(delta: -60)
        let next = try XCTUnwrap(view.swipeContainer?.subviews.first)
        finish(animation)
        XCTAssertTrue(view.hasRevealState)
        XCTAssertTrue(view.swipeContainer?.subviews.first === next)
        XCTAssertEqual(view.containerX, -60)
    }

    func testCompletedGestureReleasesContainer() throws {
        let view = row()
        view.moveReveal(delta: -40)
        let control = try XCTUnwrap(view.swipeContainer?.subviews.first as? ChatSwipeToReplyView)
        view.completeReveal(direction: left)
        finish(try XCTUnwrap(control.layer?.animation(forKey: "opacity")))
        XCTAssertNil(view.swipeContainer)
        XCTAssertFalse(view.hasRevealState)
        XCTAssertEqual(view.containerX, 0)
    }

    func testProgressGeometryAndHapticThresholdMatchNative() throws {
        let old = NativeRow(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        let new = row()
        old.layoutSwipe()
        new.layoutSwipe()
        for delta: CGFloat in [-10, -75, -100, -120, -100, -90, -105, 20] {
            old.moveReveal(delta: delta)
            new.moveReveal(delta: delta)
            XCTAssertEqual(old.rowView.frame, new.rowView.frame)
            XCTAssertEqual(old.swipeContainer?.frame, new.swipeContainer?.frame)
            XCTAssertEqual(old.swipeContainer?.subviews.first?.frame, new.swipeContainer?.subviews.first?.frame)
            XCTAssertEqual(old.haptics, new.haptics)
        }
        XCTAssertEqual(new.haptics, 2)
    }

    func testOnlyRightGestureAtThresholdReplies() {
        for (direction, invokesReply) in [(left, false), (right, true)] {
            for delta: CGFloat in [-99, -100, -120] {
                let view = row()
                let item = view.item as! ChatRowItem
                view.moveReveal(delta: delta)
                view.completeReveal(direction: direction)
                XCTAssertEqual(item.replies, invokesReply && delta <= -100 ? 1 : 0)
                view.completeReveal(direction: direction)
                XCTAssertEqual(item.replies, invokesReply && delta <= -100 ? 1 : 0)
            }
        }
    }

    func testReplyCallbackStartingNewGestureIsNotReset() {
        let view = row()
        let item = view.item as! ChatRowItem
        item.onReply = { [weak view] in view?.initRevealState(); view?.moveReveal(delta: -30) }
        view.moveReveal(delta: -100)
        view.completeReveal(direction: right)
        XCTAssertEqual(item.replies, 1)
        XCTAssertEqual(view.containerX, -30)
        XCTAssertTrue(view.hasRevealState)
    }
}

extension SwipeTests {
    func testRestartCancelsReturnPositionAnimation() {
        let view = row()
        view.moveReveal(delta: -60)
        view.completeReveal(direction: left)
        XCTAssertNotNil(view.rowView.layer?.animation(forKey: "position"))
        view.moveReveal(delta: -20)
        XCTAssertNil(view.rowView.layer?.animation(forKey: "position"))
        XCTAssertEqual(view.containerX, -20)
        XCTAssertTrue(view.hasRevealState)
    }

    func testResizeKeepsActiveSwipeAligned() {
        let old = NativeRow(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        let new = row()
        old.layoutSwipe()
        new.layoutSwipe()
        old.moveReveal(delta: -70)
        new.moveReveal(delta: -70)
        for size in [NSSize(width: 450, height: 130), NSSize(width: 250, height: 55)] {
            old.setFrameSize(size)
            new.setFrameSize(size)
            old.layoutSwipe()
            new.layoutSwipe()
            XCTAssertEqual(old.swipeContainer?.frame, new.swipeContainer?.frame)
        }
    }

    func testDismissedControlAndContainerAreReleased() throws {
        let view = row()
        weak var container: View?
        weak var control: ChatSwipeToReplyView?
        try autoreleasepool {
            view.moveReveal(delta: -60)
            container = view.swipeContainer
            control = view.swipeContainer?.subviews.first as? ChatSwipeToReplyView
            view.completeReveal(direction: left)
            finish(try XCTUnwrap(control?.layer?.animation(forKey: "opacity")))
        }
        CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertNil(container)
        XCTAssertNil(control)
    }

    func testSwipePixelsMatchNative() {
        for scale: CGFloat in [1, 2, 3] {
            for delta: CGFloat in [-25, -60, -99] {
                let old = NativeRow(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
                let new = row()
                old.layoutSwipe()
                new.layoutSwipe()
                old.moveReveal(delta: delta)
                new.moveReveal(delta: delta)
                let expected = ViewSnapshot.render(old, scale: scale)
                let actual = ViewSnapshot.render(new, scale: scale)
                XCTAssertGreaterThan(expected.bytes.filter { $0 != 0 }.count, 0)
                XCTAssertEqual(actual.differingPixels(from: expected, tolerance: 0), 0, "scale=\(scale), delta=\(delta)")
            }
        }
    }
}
