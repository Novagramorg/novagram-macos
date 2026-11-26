import XCTest
import AppKit
import TGUIKit
import Postbox
import TelegramUtils
@testable import ChatListUI

final class GCChatListIndicatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        TelegramUtilsHooks.install(TelegramUtilsHooks(animationsAreLite: { false }, isLite: { _ in false }, peerTitle: { _ in "" }, peerLetters: { _ in [] }, peerIsForum: { _ in false }, peerCompactTitle: { _ in "" }, repliesPeerId: { PeerId(0) }))
    }

    func testIndicatorUsesOneCoreAnimationAndFreezesOutsideAKeyWindow() {
        let indicator = GCChatListIndicator(color: .white)
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 100, 40), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = NSView(frame: NSMakeRect(0, 0, 100, 40))
        window.contentView?.addSubview(indicator)
        XCTAssertTrue(indicator.isIndicatorPlaying)
        let animation = indicator.layer?.animation(forKey: "path") as? CAKeyframeAnimation
        XCTAssertEqual(animation?.values?.count, 9)
        XCTAssertEqual(animation?.duration ?? 0, 3.2, accuracy: 1e-9)
        XCTAssertEqual(animation?.repeatCount, .infinity)

        let titled = NSWindow(contentRect: NSMakeRect(0, 0, 100, 40), styleMask: [.titled], backing: .buffered, defer: true)
        titled.contentView?.addSubview(indicator)
        XCTAssertFalse(indicator.isIndicatorPlaying)

        indicator.removeFromSuperview()
        XCTAssertNil(indicator.layer?.animation(forKey: "path"))
    }

    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6 + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    }

    private func measure(_ make: () -> NSView) -> Double {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 400, 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSView(frame: NSMakeRect(0, 0, 400, 100))
        window.orderFrontRegardless()
        for i in 0 ..< 20 {
            let view = make()
            view.setFrameOrigin(NSMakePoint(CGFloat(i) * 15, 40))
            window.contentView?.addSubview(view)
        }
        let warm = expectation(description: "warm")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { warm.fulfill() }
        wait(for: [warm], timeout: 3)
        let start = self.cpuSeconds()
        let done = expectation(description: "done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { done.fulfill() }
        wait(for: [done], timeout: 5)
        let cpu = (self.cpuSeconds() - start) / 2.0 * 100
        window.orderOut(nil)
        window.contentView?.subviews.forEach { $0.removeFromSuperview() }
        return cpu
    }

    func testCoreAnimationIndicatorCostsLessThanTheDisplayLinkOne() {
        let legacy = self.measure { LegacyGCChatListIndicator(color: .white) }
        let current = self.measure { GCChatListIndicator(color: .white) }
        print(String(format: "GCChatListIndicator 20 visible: display link %.2f%% CPU, Core Animation %.2f%% CPU", legacy, current))
        XCTAssertLessThan(current, legacy)
    }
}
