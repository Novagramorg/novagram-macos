import AppKit
import XCTest
@testable import TGUIKit

private protocol RevealGenerationDust: AnyObject {
    var isEmitterPlaying: Bool { get }
    var isRevealed: Bool { get }
    func update(revealed: Bool)
}

extension InvisibleInkDustView: RevealGenerationDust {}
extension MediaDustView: RevealGenerationDust {}

final class SpoilerDustRevealGenerationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        XCTAssertTrue(Thread.isMainThread)
    }

    private func textDust() -> InvisibleInkDustView {
        let dust = InvisibleInkDustView()
        let rect = CGRect(x: 0, y: 0, width: 120, height: 24)
        dust.frame = rect
        dust.update(size: rect.size, color: .white, textColor: .black, rects: [rect], wordRects: [rect.insetBy(dx: 2, dy: 2)])
        return dust
    }

    private func mediaDust() -> MediaDustView {
        let dust = MediaDustView()
        let rect = CGRect(x: 0, y: 0, width: 120, height: 80)
        dust.frame = rect
        dust.update(size: rect.size, color: .white, textColor: .black, mask: CGPath(rect: rect, transform: nil))
        return dust
    }

    private func attach(_ views: [NSView]) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        for view in views { window.contentView?.addSubview(view) }
        return window
    }

    private func finishCurrentFade() {
        let finished = expectation(description: "Current reveal timer finishes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { finished.fulfill() }
        wait(for: [finished], timeout: 3)
    }

    private func verifySupersededReveal<Dust: View & RevealGenerationDust>(make: () -> Dust) {
        let dust = make(), ordinaryReveal = make()
        let window = attach([dust, ordinaryReveal])
        defer { window.contentView = nil; window.close() }
        XCTAssertTrue(dust.isEmitterPlaying)
        XCTAssertTrue(ordinaryReveal.isEmitterPlaying)
        dust.update(revealed: true)
        ordinaryReveal.update(revealed: true)
        Thread.sleep(forTimeInterval: 0.5)
        let overdueTimersDrained = expectation(description: "Old reveal timers run before the new reveal timer")
        DispatchQueue.main.async {
            XCTAssertFalse(ordinaryReveal.isEmitterPlaying, "The ordinary reveal proves the overdue timer batch ran")
            XCTAssertTrue(dust.isRevealed)
            XCTAssertTrue(dust.isEmitterPlaying, "An obsolete timer must not freeze the new reveal")
            dust.removeFromSuperview()
            XCTAssertFalse(dust.isEmitterPlaying)
            window.contentView?.addSubview(dust)
            XCTAssertTrue(dust.isEmitterPlaying, "Reattaching preserves the current reveal until its timer finishes")
            overdueTimersDrained.fulfill()
        }
        dust.update(revealed: false)
        dust.update(revealed: true)
        XCTAssertTrue(dust.isEmitterPlaying)
        wait(for: [overdueTimersDrained], timeout: 3)
        finishCurrentFade()
        XCTAssertFalse(dust.isEmitterPlaying)
        XCTAssertEqual(dust.layer?.opacity, 0)
        dust.update(revealed: false)
        XCTAssertTrue(dust.isEmitterPlaying)
        XCTAssertEqual(dust.layer?.opacity, 1)
    }

    private func verifyRepeatedRevealAndHide<Dust: View & RevealGenerationDust>(make: () -> Dust) {
        let repeatedReveal = make(), hidden = make()
        let window = attach([repeatedReveal, hidden])
        defer { window.contentView = nil; window.close() }
        repeatedReveal.update(revealed: true)
        hidden.update(revealed: true)
        Thread.sleep(forTimeInterval: 0.5)
        let overdueTimersDrained = expectation(description: "Repeated reveal keeps its timer and hiding invalidates it")
        DispatchQueue.main.async {
            XCTAssertTrue(repeatedReveal.isRevealed)
            XCTAssertFalse(repeatedReveal.isEmitterPlaying, "An unchanged reveal must not invalidate its pending completion")
            XCTAssertFalse(hidden.isRevealed)
            XCTAssertTrue(hidden.isEmitterPlaying)
            XCTAssertEqual(hidden.layer?.opacity, 1)
            overdueTimersDrained.fulfill()
        }
        repeatedReveal.update(revealed: true)
        hidden.update(revealed: false)
        wait(for: [overdueTimersDrained], timeout: 3)
    }

    func testTextDustObsoleteTimerCannotFreezeNewReveal() {
        verifySupersededReveal(make: textDust)
    }

    func testMediaDustObsoleteTimerCannotFreezeNewReveal() {
        verifySupersededReveal(make: mediaDust)
    }

    func testTextDustRepeatedRevealAndHidePreserveCompletionRules() {
        verifyRepeatedRevealAndHide(make: textDust)
    }

    func testMediaDustRepeatedRevealAndHidePreserveCompletionRules() {
        verifyRepeatedRevealAndHide(make: mediaDust)
    }

    func testSupersededTimersDoNotRetainDustViews() {
        weak var text: InvisibleInkDustView?
        weak var media: MediaDustView?
        autoreleasepool {
            let textDust = self.textDust(), mediaDust = self.mediaDust()
            text = textDust
            media = mediaDust
            for revealed in [true, false, true] {
                textDust.update(revealed: revealed)
                mediaDust.update(revealed: revealed)
            }
        }
        XCTAssertNil(text)
        XCTAssertNil(media)
        finishCurrentFade()
        XCTAssertNil(text)
        XCTAssertNil(media)
    }
}
