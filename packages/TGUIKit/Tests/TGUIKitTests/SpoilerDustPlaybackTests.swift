import XCTest
import AppKit
@testable import TGUIKit

final class SpoilerDustPlaybackTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func wait(_ seconds: Double) {
        let done = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            done.fulfill()
        }
        self.wait(for: [done], timeout: seconds + 3)
    }

    private func borderlessWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 200, 100), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = NSView(frame: NSMakeRect(0, 0, 200, 100))
        return window
    }

    func testTextDustRunsOnlyInAKeyWindowAndStopsAfterReveal() {
        let dust = InvisibleInkDustView()
        dust.update(size: CGSize(width: 120, height: 20), color: .white, textColor: .black, rects: [CGRect(x: 0, y: 0, width: 120, height: 20)], wordRects: [CGRect(x: 0, y: 0, width: 120, height: 20)])
        XCTAssertFalse(dust.isEmitterPlaying)

        let window = self.borderlessWindow()
        window.contentView?.addSubview(dust)
        XCTAssertTrue(dust.isEmitterPlaying)

        dust.update(revealed: true)
        XCTAssertTrue(dust.isEmitterPlaying)
        self.wait(0.5)
        XCTAssertFalse(dust.isEmitterPlaying)

        dust.update(revealed: false)
        XCTAssertTrue(dust.isEmitterPlaying)

        dust.removeFromSuperview()
        XCTAssertFalse(dust.isEmitterPlaying)
    }

    func testMediaDustRunsOnlyInAKeyWindow() {
        let dust = MediaDustView()
        dust.update(size: CGSize(width: 100, height: 100), color: .white, textColor: .black, mask: CGPath(rect: CGRect(x: 0, y: 0, width: 100, height: 100), transform: nil))
        XCTAssertFalse(dust.isEmitterPlaying)

        let window = self.borderlessWindow()
        window.contentView?.addSubview(dust)
        XCTAssertTrue(dust.isEmitterPlaying)

        dust.update(revealed: true)
        self.wait(0.5)
        XCTAssertFalse(dust.isEmitterPlaying)
    }
}
