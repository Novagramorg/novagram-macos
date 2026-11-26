import Cocoa
import XCTest

__VALUES__
func -(lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
final class MouseWindow { var mouseLocationOutsideOfEventStream = CGPoint.zero }
class View {
    let layer = CALayer()
    var frame = CGRect.zero
    var subviews: [View] = []
    var window: MouseWindow? = MouseWindow()
    func layout() {}
    func setFrameSize(_ size: CGSize) { frame.size = size }
    func setFrameOrigin(_ point: CGPoint) { frame.origin = point }
    func center() { frame.origin.y = 2 }
    func convert(_ point: CGPoint, from: View?) -> CGPoint { point - frame.origin }
}
typealias Control = View
func makeScrubberValues(_ left: CGFloat = 0.2, _ right: CGFloat = 0.6, move: CGFloat = 0.3, paused: Bool = false, suspended: Bool = false, key: CGFloat? = nil) -> VideoScrubberValues {
    VideoScrubberValues(movePos: move, keyFrame: key, leftTrim: left, rightTrim: right, minDist: 0.01, maxDist: 1, paused: paused, suspended: suspended)
}
final class Scrubber: View {
    let imageViewsContainer = View(), leftTrim = View(), rightTrim = View(), scrubber = View(), distance = View(), overlay = View()
    var values: VideoScrubberValues
    var updates: [VideoScrubberValues] = []
    var updateValues: ((VideoScrubberValues) -> Void)?
    var long: ((Control) -> Void)!, up: ((Control) -> Void)!, drag: ((Control) -> Void)!, left: ((Control) -> Void)!, right: ((Control) -> Void)!
    init(_ value: VideoScrubberValues = GeometryTests.makeValues(), width: CGFloat = 116, height: CGFloat = 40) {
        values = value
        super.init()
        frame = CGRect(x: 0, y: 0, width: width, height: height)
        scrubber.frame.size.width = 4
        var chooseFrame = false
        var distanceStart: CGPoint? = .zero
        var leftTrimStart: CGPoint? = .zero
        var rightTrimStart: CGPoint? = .zero
        func possibleDrag(_ value: CGFloat) -> Bool { value >= 0 && value <= 1 }
        func checkDist(_ left: CGFloat, _ right: CGFloat, _ min: CGFloat, _ max: CGFloat) -> Bool { (left - right) >= min && (left - right) <= max }
        updateValues = { [weak self] value in
            self?.values = value
            self?.updates.append(value)
            self?.layout()
        }
        long = __LONG__
        up = __UP__
        drag = __DRAG__
        left = __LEFT__
        right = __RIGHT__
        layout()
    }
    func click(_ x: CGFloat, longPress: Bool = false) {
        distance.window?.mouseLocationOutsideOfEventStream = CGPoint(x: x, y: 10)
        if longPress { long(distance) } else { up(distance) }
    }
    func move(_ x: CGFloat) { distance.window?.mouseLocationOutsideOfEventStream.x = x; drag(distance) }
    __METHODS__
}
final class GeometryTests: XCTestCase {
    static func makeValues() -> VideoScrubberValues { makeScrubberValues() }
    func testFullRangeHandlesDoNotConsumeTimeline() {
        let s = Scrubber(makeScrubberValues(0, 1))
        XCTAssertEqual(s.leftTrim.frame.minX, 0)
        XCTAssertEqual(s.leftTrim.frame.maxX, s.imageViewsContainer.frame.minX)
        XCTAssertEqual(s.rightTrim.frame.minX, s.imageViewsContainer.frame.maxX)
        XCTAssertEqual(s.rightTrim.frame.maxX, s.frame.width)
        XCTAssertEqual(s.distance.frame.width, s.imageViewsContainer.frame.width)
    }
    func testLongVideoTenSecondRangeHasPositiveHitArea() {
        let s = Scrubber(makeScrubberValues(0.5, 0.5 + 10 / 600, move: 0.5), width: 370)
        XCTAssertGreaterThan(s.distance.frame.size.width, 0)
        XCTAssertGreaterThanOrEqual(s.rightTrim.frame.minX, s.leftTrim.frame.maxX)
        XCTAssertEqual(s.distance.frame.size.width, (370 - 16) * 10 / 600, accuracy: 0.00001)
    }
    func testOneSecondRangeOnHourClipHasPositiveHitArea() {
        let s = Scrubber(makeScrubberValues(0.9, 0.9 + 1 / 3600), width: 370)
        XCTAssertGreaterThan(s.distance.frame.size.width, 0)
        XCTAssertGreaterThanOrEqual(s.rightTrim.frame.minX, s.leftTrim.frame.maxX)
    }
    func testPlayheadCenterIsAtTrimStart() {
        let s = Scrubber(makeScrubberValues(move: 0.2))
        XCTAssertEqual(s.scrubber.frame.midX, s.leftTrim.frame.maxX, accuracy: 0.00001)
    }
    func testPlayheadCenterIsAtTrimEnd() {
        let s = Scrubber(makeScrubberValues(move: 0.6))
        XCTAssertEqual(s.scrubber.frame.midX, s.rightTrim.frame.minX, accuracy: 0.00001)
    }
    func testPlayheadClampedToNarrowSelection() {
        let s = Scrubber(makeScrubberValues(0.5, 0.5 + 1 / 600, move: 0), width: 370)
        XCTAssertGreaterThanOrEqual(s.scrubber.frame.midX, s.leftTrim.frame.maxX)
        XCTAssertLessThanOrEqual(s.scrubber.frame.midX, s.rightTrim.frame.minX)
    }
    func testTinyAndZeroBoundsNeverCreateNegativeSizes() {
        for width: CGFloat in [0, 1, 7, 15] {
            let s = Scrubber(width: width, height: 1)
            for view in [s.imageViewsContainer, s.leftTrim, s.rightTrim, s.scrubber, s.distance] {
                XCTAssertGreaterThanOrEqual(view.frame.size.width, 0)
                XCTAssertGreaterThanOrEqual(view.frame.size.height, 0)
                XCTAssertGreaterThanOrEqual(view.frame.minX, 0)
                XCTAssertLessThanOrEqual(view.frame.maxX, width)
            }
        }
    }
    func testImagesFitTimelineAfterResize() {
        let s = Scrubber()
        s.imageViewsContainer.subviews = (0..<3).map { _ in View() }
        s.layout()
        XCTAssertEqual(s.imageViewsContainer.subviews.last!.frame.maxX, s.imageViewsContainer.frame.width, accuracy: 0.00001)
        s.frame.size.width = 316
        s.layout()
        XCTAssertEqual(s.imageViewsContainer.subviews.last!.frame.maxX, 300, accuracy: 0.00001)
    }
    func testOverlayMatchesImageTimeline() {
        let s = Scrubber()
        XCTAssertEqual(s.overlay.frame, s.imageViewsContainer.frame)
    }
    func testClickUsesTimelinePosition() {
        let s = Scrubber()
        s.click(48)
        XCTAssertEqual(s.values.keyFrame!, 0.4, accuracy: 0.00001)
        XCTAssertEqual(s.values.movePos, 0.4, accuracy: 0.00001)
        XCTAssertTrue(s.values.paused)
        XCTAssertTrue(s.values.suspended)
    }
    func testClickBeforeSelectionClampsToStart() {
        let s = Scrubber(); s.click(-100)
        XCTAssertEqual(s.values.keyFrame, 0.2)
    }
    func testClickAfterSelectionClampsToEnd() {
        let s = Scrubber(); s.click(500)
        XCTAssertEqual(s.values.keyFrame, 0.6)
    }
    func testLongPressClampsToSelection() {
        let s = Scrubber(); s.click(-100, longPress: true)
        XCTAssertEqual(s.values.movePos, 0.2)
        XCTAssertTrue(s.values.suspended)
    }
    func testLongPressAtEndUsesTimelineEnd() {
        let s = Scrubber(); s.click(68, longPress: true)
        XCTAssertEqual(s.values.movePos, 0.6, accuracy: 0.00001)
    }
    func testLongPressReleaseKeepsSelectedFrame() {
        let s = Scrubber(); s.click(48, longPress: true); s.click(48)
        XCTAssertEqual(s.values.keyFrame!, 0.4, accuracy: 0.00001)
    }
    func testDetachedControlIgnoresClickAndLongPress() {
        let s = Scrubber(); s.distance.window = nil
        s.click(30); s.click(30, longPress: true)
        XCTAssertTrue(s.updates.isEmpty)
    }
    func testZeroWidthTimelineIgnoresClickAndLongPress() {
        let s = Scrubber(width: 16)
        s.click(30); s.click(30, longPress: true)
        XCTAssertTrue(s.updates.isEmpty)
    }
    func testNonFinitePointerIgnored() {
        let s = Scrubber(); s.click(.nan); s.click(.infinity, longPress: true)
        XCTAssertTrue(s.updates.isEmpty)
    }
    func testPausedClickResumes() {
        let s = Scrubber(makeScrubberValues(paused: true)); s.click(48)
        XCTAssertFalse(s.values.paused)
    }
    func testRangeDragUsesSameScaleAsLayout() {
        let s = Scrubber(); s.move(10)
        XCTAssertEqual(s.values.leftTrim, 0.3, accuracy: 0.00001)
        XCTAssertEqual(s.values.rightTrim, 0.7, accuracy: 0.00001)
    }
    func testLeftHandleDragUsesSameScaleAsLayout() {
        let s = Scrubber(); s.leftTrim.window?.mouseLocationOutsideOfEventStream.x = 10; s.left(s.leftTrim)
        XCTAssertEqual(s.values.leftTrim, 0.3, accuracy: 0.00001)
    }
    func testRightHandleDragUsesSameScaleAsLayout() {
        let s = Scrubber(); s.rightTrim.window?.mouseLocationOutsideOfEventStream.x = 10; s.right(s.rightTrim)
        XCTAssertEqual(s.values.rightTrim, 0.7, accuracy: 0.00001)
    }
    func testFrameDragBeyondTrimReachesBoundary() {
        let s = Scrubber(); s.click(48, longPress: true); s.move(1000)
        XCTAssertEqual(s.values.movePos, 0.6)
        XCTAssertEqual(s.values.leftTrim, 0.2)
        XCTAssertEqual(s.values.rightTrim, 0.6)
        s.move(990)
        XCTAssertEqual(s.values.movePos, 0.5, accuracy: 0.00001)
    }
    func testRangeDragDuringPreviewClearsSuspensionAndReleaseResumes() {
        let s = Scrubber(makeScrubberValues(paused: true, suspended: true, key: 0.3))
        s.move(10)
        XCTAssertFalse(s.values.suspended)
        XCTAssertTrue(s.values.paused)
        s.click(48)
        XCTAssertFalse(s.values.paused)
    }
    func testClickDuringPreviewResumesWithoutWaitingForOldAnimation() {
        let s = Scrubber(makeScrubberValues(paused: true, suspended: true, key: 0.3))
        s.click(48)
        XCTAssertFalse(s.values.paused)
        XCTAssertFalse(s.values.suspended)
    }
    func testLeftTrimDragDuringPreviewClearsSuspension() {
        let s = Scrubber(makeScrubberValues(paused: true, suspended: true, key: 0.3))
        s.leftTrim.window?.mouseLocationOutsideOfEventStream.x = 5
        s.left(s.leftTrim)
        XCTAssertFalse(s.values.suspended)
    }
    func testRightTrimDragDuringPreviewClearsSuspension() {
        let s = Scrubber(makeScrubberValues(paused: true, suspended: true, key: 0.3))
        s.rightTrim.window?.mouseLocationOutsideOfEventStream.x = 5
        s.right(s.rightTrim)
        XCTAssertFalse(s.values.suspended)
    }
    func testFrameDragBeforeTrimReachesBoundary() {
        let s = Scrubber(); s.click(48, longPress: true); s.move(-1000)
        XCTAssertEqual(s.values.movePos, 0.2)
    }
}

final class PreviewPosition {
    let controls = View()
    let scrubberView = Scrubber()
    let keyFrameDotView = View()
    init() { controls.frame.origin.x = 30; scrubberView.frame.origin.x = 20 }
    func initial(_ value: CGFloat) -> CGPoint {
        __POSITION0__
        return point
    }
    func relayout(_ value: CGFloat) -> CGPoint {
        __POSITION1__
        return point
    }
}
final class OverlayAndPreviewTests: XCTestCase {
    func testLeftMaskEndsAtActualTrimStart() { XCTAssertEqual(alpha(at: 25), 0); XCTAssertGreaterThan(alpha(at: 10), 0) }
    func testRightMaskStartsAtActualTrimEnd() { XCTAssertGreaterThan(alpha(at: 61), 0); XCTAssertEqual(alpha(at: 55), 0) }
    private func alpha(at x: Int) -> UInt8 {
        let s = Scrubber()
        let context = CGContext(data: nil, width: 100, height: 36, bitsPerComponent: 8, bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        s.draw(s.overlay.layer, in: context)
        return context.data!.assumingMemoryBound(to: UInt8.self)[(18 * 100 + x) * 4 + 3]
    }
    func testInitialPreviewAndDotAlignWithTimeline() {
        let v = PreviewPosition()
        let point = v.initial(0.4)
        XCTAssertEqual(point.x + 15, 30 + 20 + 8 + 40)
        XCTAssertEqual(v.keyFrameDotView.frame.midX, point.x + 15)
    }
    func testPreviewAndDotStayAlignedAfterResize() {
        let v = PreviewPosition()
        v.scrubberView.frame.size.width = 316
        let point = v.relayout(0.4)
        XCTAssertEqual(point.x + 15, 30 + 20 + 8 + 120)
        XCTAssertEqual(v.keyFrameDotView.frame.midX, point.x + 15)
    }
}
