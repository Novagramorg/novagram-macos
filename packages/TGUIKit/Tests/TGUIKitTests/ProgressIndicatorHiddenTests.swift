import XCTest
import AppKit
@testable import TGUIKit

final class ProgressIndicatorHiddenTests: XCTestCase {
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

    func testSpinnerInsideAHiddenContainerStops() {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 100, 100), styleMask: [.borderless], backing: .buffered, defer: true)
        let container = NSView(frame: NSMakeRect(0, 0, 40, 40))
        window.contentView = NSView(frame: NSMakeRect(0, 0, 100, 100))
        window.contentView?.addSubview(container)
        let progress = ProgressIndicator(frame: NSMakeRect(0, 0, 22, 22))
        container.addSubview(progress)
        XCTAssertTrue(progress.isSpinning)

        container.isHidden = true
        self.wait(1.0)
        XCTAssertFalse(progress.isSpinning)

        container.isHidden = false
        XCTAssertTrue(progress.isSpinning)

        progress.removeFromSuperview()
        self.wait(1.0)
        XCTAssertFalse(progress.isSpinning)
    }
}
