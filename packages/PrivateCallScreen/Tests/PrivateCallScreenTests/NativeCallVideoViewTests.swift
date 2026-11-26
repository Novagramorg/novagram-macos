import XCTest
import AppKit
import TGUIKit
import TelegramVoip
@testable import CallVideoLayer

private final class FakeTgcallsVideo {
    let view = NSView(frame: .zero)
    var firstFrame: ((Float) -> Void)?
    var aspect: CGFloat = 0
    var gravity: [CALayerContentsGravity] = []
    var paused: [Bool] = []
    var clearedFirstFrameHandler = false

    func make() -> OngoingCallContextPresentationCallVideoView {
        return OngoingCallContextPresentationCallVideoView(view: self.view, setOnFirstFrameReceived: { [weak self] f in
            self?.firstFrame = f
            if f == nil {
                self?.clearedFirstFrameHandler = true
            }
        }, getOrientation: {
            return .rotation90
        }, getAspect: { [weak self] in
            return self?.aspect ?? 0
        }, setOnOrientationUpdated: { _ in
        }, setVideoContentMode: { [weak self] gravity in
            self?.gravity.append(gravity)
        }, setOnIsMirroredUpdated: { _ in
        }, setIsPaused: { [weak self] value in
            self?.paused.append(value)
        }, renderToSize: { _, _ in
        })
    }
}

final class NativeCallVideoViewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = TestTheme.prepared
    }
    
    private func drainMainQueue(_ seconds: Double = 0.05) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func waitUntil(timeout: Double, _ condition: () -> Bool) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() {
            if Date() > deadline {
                return false
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return true
    }

    func testHostsTgcallsViewWithAspectFit() {
        let fake = FakeTgcallsVideo()
        let view = NativeCallVideoView(video: fake.make())
        XCTAssertTrue(fake.view.superview === view)
        XCTAssertEqual(fake.gravity, [.resizeAspect])
        XCTAssertNil(view.videoMetrics)
        XCTAssertFalse(view.userInteractionEnabled)
    }

    func testFirstFrameUsesDisplayAspectNotRawFrameAspect() {
        let fake = FakeTgcallsVideo()
        let view = NativeCallVideoView(video: fake.make())
        var metricsUpdates = 0
        var firstFrameCalls = 0
        view.videoMetricsDidUpdate = { _ in metricsUpdates += 1 }
        view.firstFrameRendered = { firstFrameCalls += 1 }
        fake.aspect = 720.0 / 1280.0
        fake.firstFrame?(1280.0 / 720.0)
        drainMainQueue()
        let resolution = try! XCTUnwrap(view.videoMetrics?.displayResolution)
        XCTAssertEqual(Double(resolution.width / resolution.height), 720.0 / 1280.0, accuracy: 0.001)
        XCTAssertEqual(view.videoMetrics?.rotationAngle, 0)
        XCTAssertEqual(metricsUpdates, 1)
        XCTAssertEqual(firstFrameCalls, 1)
        XCTAssertNil(view.firstFrameRendered)
    }

    func testFirstFrameFallsBackToRawAspect() {
        let fake = FakeTgcallsVideo()
        let view = NativeCallVideoView(video: fake.make())
        fake.aspect = 0
        fake.firstFrame?(4.0 / 3.0)
        drainMainQueue()
        let resolution = try! XCTUnwrap(view.videoMetrics?.displayResolution)
        XCTAssertEqual(Double(resolution.width / resolution.height), 4.0 / 3.0, accuracy: 0.001)
    }

    func testInvalidFirstFrameKeepsViewHidden() {
        let fake = FakeTgcallsVideo()
        let view = NativeCallVideoView(video: fake.make())
        fake.aspect = 0
        fake.firstFrame?(0)
        drainMainQueue()
        XCTAssertNil(view.videoMetrics)
    }

    func testAspectPollingFollowsRotationWhileOnScreen() {
        let fake = FakeTgcallsVideo()
        let view = NativeCallVideoView(video: fake.make())
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 400, 400), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView?.addSubview(view)
        fake.aspect = 16.0 / 9.0
        fake.firstFrame?(16.0 / 9.0)
        drainMainQueue()
        let landscape = try! XCTUnwrap(view.videoMetrics?.displayResolution)
        XCTAssertGreaterThan(landscape.width, landscape.height)
        fake.aspect = 9.0 / 16.0
        XCTAssertTrue(waitUntil(timeout: 5) {
            guard let resolution = view.videoMetrics?.displayResolution else {
                return false
            }
            return resolution.width < resolution.height
        })
        view.removeFromSuperview()
        fake.aspect = 16.0 / 9.0
        drainMainQueue(1.5)
        let afterRemoval = try! XCTUnwrap(view.videoMetrics?.displayResolution)
        XCTAssertLessThan(afterRemoval.width, afterRemoval.height)
    }

    func testPauseForwardsOnlyChanges() {
        let fake = FakeTgcallsVideo()
        let view = NativeCallVideoView(video: fake.make())
        view.isPaused = true
        view.isPaused = true
        view.isPaused = false
        XCTAssertEqual(fake.paused, [true, false])
    }

    func testGravityForwarded() {
        let fake = FakeTgcallsVideo()
        let view = NativeCallVideoView(video: fake.make())
        view.setGravity(.resizeAspectFill)
        XCTAssertEqual(fake.gravity, [.resizeAspect, .resizeAspectFill])
    }

    func testLayoutResizesHostedView() {
        let fake = FakeTgcallsVideo()
        let view = NativeCallVideoView(video: fake.make())
        view.frame = NSMakeRect(0, 0, 190, 106)
        view.updateLayout(size: view.frame.size, transition: .immediate)
        XCTAssertEqual(fake.view.frame, NSMakeRect(0, 0, 190, 106))
    }

    func testReleasingViewClearsTgcallsCallback() {
        let fake = FakeTgcallsVideo()
        weak var weakView: NativeCallVideoView?
        autoreleasepool {
            let view = NativeCallVideoView(video: fake.make())
            weakView = view
            XCTAssertNotNil(fake.firstFrame)
        }
        XCTAssertNil(weakView)
        XCTAssertTrue(fake.clearedFirstFrameHandler)
    }

    func testMirroringFlipsHostedLayerOnlyWhenEnabled() {
        let fake = FakeTgcallsVideo()
        let view = NativeCallVideoView(video: fake.make())
        view.frame = NSMakeRect(0, 0, 190, 106)
        view.updateLayout(size: view.frame.size, transition: .immediate)
        XCTAssertTrue(CATransform3DIsIdentity(view.layer?.sublayerTransform ?? CATransform3DIdentity))
        view.isMirrored = true
        let mirrored = CATransform3DGetAffineTransform(view.layer!.sublayerTransform)
        XCTAssertEqual(CGPoint(x: 0, y: 0).applying(mirrored), CGPoint(x: 190, y: 0))
        view.frame = NSMakeRect(0, 0, 300, 200)
        view.updateLayout(size: view.frame.size, transition: .immediate)
        XCTAssertEqual(CGPoint(x: 0, y: 0).applying(CATransform3DGetAffineTransform(view.layer!.sublayerTransform)), CGPoint(x: 300, y: 0))
        view.isMirrored = false
        XCTAssertTrue(CATransform3DIsIdentity(view.layer!.sublayerTransform))
    }

    func testMetalViewDeallocates() {
        weak var weakView: MetalCallVideoView?
        autoreleasepool {
            let view = MetalCallVideoView(frame: NSMakeRect(0, 0, 100, 100))
            weakView = view
        }
        XCTAssertNil(weakView)
    }
}
