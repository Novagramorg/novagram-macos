import XCTest
import Metal
@testable import CallVideoLayer
@testable import PrivateCallScreen

final class PeerCallVideoTests: XCTestCase {
    private func metrics(_ width: CGFloat, _ height: CGFloat, rotation: Float) -> CallVideoView.VideoMetrics {
        return CallVideoView.VideoMetrics(resolution: CGSize(width: width, height: height), rotationAngle: rotation, followsDeviceOrientation: false, sourceId: 0)
    }

    func testDisplayResolutionSwapsOnlyForQuarterTurns() {
        XCTAssertEqual(metrics(1280, 720, rotation: 0).displayResolution, CGSize(width: 1280, height: 720))
        XCTAssertEqual(metrics(1280, 720, rotation: Float.pi).displayResolution, CGSize(width: 1280, height: 720))
        XCTAssertEqual(metrics(1280, 720, rotation: Float.pi * 0.5).displayResolution, CGSize(width: 720, height: 1280))
        XCTAssertEqual(metrics(1280, 720, rotation: Float.pi * 3.0 / 2.0).displayResolution, CGSize(width: 720, height: 1280))
    }

    func testSmallVideoSizeLandscape() {
        let size = peerCallSmallVideoSize(CGSize(width: 1280, height: 720))
        XCTAssertEqual(size, CGSize(width: 190, height: 106))
    }

    func testSmallVideoSizePortraitFromRotatedPhone() {
        let size = peerCallSmallVideoSize(metrics(1280, 720, rotation: Float.pi * 0.5).displayResolution)
        XCTAssertEqual(size, CGSize(width: 106, height: 190))
    }

    func testSmallVideoSizeSquareAndPlaceholder() {
        XCTAssertEqual(peerCallSmallVideoSize(CGSize(width: 640, height: 640)), CGSize(width: 190, height: 190))
        XCTAssertEqual(peerCallSmallVideoSize(nil), CGSize(width: 190, height: 100))
        XCTAssertEqual(peerCallSmallVideoSize(.zero), CGSize(width: 190, height: 100))
        XCTAssertEqual(peerCallSmallVideoSize(CGSize(width: 0, height: 720)), CGSize(width: 190, height: 100))
    }

    func testSmallVideoNeverExceedsBox() {
        for (width, height) in [(1920.0, 1080.0), (1080.0, 1920.0), (4000.0, 100.0), (100.0, 4000.0), (190.0, 190.0), (50.0, 30.0)] {
            let size = peerCallSmallVideoSize(CGSize(width: width, height: height))
            XCTAssertLessThanOrEqual(size.width, 190)
            XCTAssertLessThanOrEqual(size.height, 190)
            XCTAssertTrue(size.width == 190 || size.height == 190, "\(width)x\(height) -> \(size)")
        }
    }

    func testNativeMetricsFromDisplayAspect() {
        let landscape = try! XCTUnwrap(callVideoMetrics(displayAspect: 16.0 / 9.0))
        XCTAssertEqual(Double(landscape.displayResolution.width / landscape.displayResolution.height), 16.0 / 9.0, accuracy: 0.001)
        XCTAssertEqual(landscape.rotationAngle, 0)
        let portrait = try! XCTUnwrap(callVideoMetrics(displayAspect: 9.0 / 16.0))
        XCTAssertEqual(Double(portrait.displayResolution.width / portrait.displayResolution.height), 9.0 / 16.0, accuracy: 0.001)
        XCTAssertEqual(peerCallSmallVideoSize(portrait.displayResolution).height, 190)
    }

    func testNativeMetricsRejectInvalidAspect() {
        XCTAssertNil(callVideoMetrics(displayAspect: 0))
        XCTAssertNil(callVideoMetrics(displayAspect: -1))
        XCTAssertNil(callVideoMetrics(displayAspect: .nan))
        XCTAssertNil(callVideoMetrics(displayAspect: .infinity))
    }

    func testMirrorTransformFlipsAroundCenter() {
        let transform = callVideoMirrorTransform(width: 200)
        let affine = CATransform3DGetAffineTransform(transform)
        XCTAssertEqual(CGPoint(x: 0, y: 10).applying(affine), CGPoint(x: 200, y: 10))
        XCTAssertEqual(CGPoint(x: 200, y: 10).applying(affine), CGPoint(x: 0, y: 10))
        XCTAssertEqual(CGPoint(x: 100, y: 10).applying(affine), CGPoint(x: 100, y: 10))
    }

    func testVideoRenderersAreExclusivePerArchitecture() {
        let hasMetal = MTLCreateSystemDefaultDevice() != nil
        XCTAssertFalse(isMetalVideoRenderingAvailable && isNativeCallVideoRenderingAvailable)
        #if arch(arm64)
        XCTAssertEqual(isMetalVideoRenderingAvailable, hasMetal)
        XCTAssertFalse(isNativeCallVideoRenderingAvailable)
        #else
        XCTAssertFalse(isMetalVideoRenderingAvailable)
        XCTAssertEqual(isNativeCallVideoRenderingAvailable, hasMetal)
        #endif
    }
}

final class PeerCallVideoRequestsTests: XCTestCase {
    func testBeginOncePerDirection() {
        var requests = PeerCallVideoRequests()
        let incoming = requests.begin(isIncoming: true)
        XCTAssertNotNil(incoming)
        XCTAssertNil(requests.begin(isIncoming: true))
        XCTAssertTrue(requests.isPending(isIncoming: true))
        XCTAssertFalse(requests.isPending(isIncoming: false))
        let outgoing = requests.begin(isIncoming: false)
        XCTAssertNotNil(outgoing)
        XCTAssertNotEqual(incoming, outgoing)
    }

    func testCompleteClearsPending() {
        var requests = PeerCallVideoRequests()
        let token = requests.begin(isIncoming: true)!
        XCTAssertTrue(requests.complete(isIncoming: true, token: token))
        XCTAssertFalse(requests.isPending(isIncoming: true))
        XCTAssertFalse(requests.complete(isIncoming: true, token: token))
        XCTAssertNotNil(requests.begin(isIncoming: true))
    }

    func testCancelledResponseIsIgnored() {
        var requests = PeerCallVideoRequests()
        let token = requests.begin(isIncoming: true)!
        requests.cancel(isIncoming: true)
        XCTAssertFalse(requests.complete(isIncoming: true, token: token))
    }

    func testStaleResponseAfterRestartIsIgnored() {
        var requests = PeerCallVideoRequests()
        let first = requests.begin(isIncoming: false)!
        requests.cancel(isIncoming: false)
        let second = requests.begin(isIncoming: false)!
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(requests.complete(isIncoming: false, token: first))
        XCTAssertTrue(requests.isPending(isIncoming: false))
        XCTAssertTrue(requests.complete(isIncoming: false, token: second))
    }

    func testDirectionsAreIndependent() {
        var requests = PeerCallVideoRequests()
        let incoming = requests.begin(isIncoming: true)!
        let outgoing = requests.begin(isIncoming: false)!
        requests.cancel(isIncoming: true)
        XCTAssertTrue(requests.complete(isIncoming: false, token: outgoing))
        XCTAssertFalse(requests.complete(isIncoming: true, token: incoming))
    }
}

final class NativeCallVideoAspectTests: XCTestCase {
    func testReportedDisplayAspectWins() {
        XCTAssertEqual(nativeCallVideoDisplayAspect(reported: 9.0 / 16.0, fallback: 16.0 / 9.0), 9.0 / 16.0)
    }

    func testFallbackWhenNothingReported() {
        XCTAssertEqual(nativeCallVideoDisplayAspect(reported: 0, fallback: 16.0 / 9.0), 16.0 / 9.0)
        XCTAssertEqual(nativeCallVideoDisplayAspect(reported: -1, fallback: 4.0 / 3.0), 4.0 / 3.0)
        XCTAssertEqual(nativeCallVideoDisplayAspect(reported: .nan, fallback: 4.0 / 3.0), 4.0 / 3.0)
        XCTAssertEqual(nativeCallVideoDisplayAspect(reported: .infinity, fallback: 4.0 / 3.0), 4.0 / 3.0)
    }

    func testPortraitDisplayAspectGivesPortraitPip() {
        let metrics = callVideoMetrics(displayAspect: nativeCallVideoDisplayAspect(reported: 720.0 / 1280.0, fallback: 1280.0 / 720.0))
        XCTAssertEqual(peerCallSmallVideoSize(metrics?.displayResolution), CGSize(width: 106, height: 190))
    }
}
