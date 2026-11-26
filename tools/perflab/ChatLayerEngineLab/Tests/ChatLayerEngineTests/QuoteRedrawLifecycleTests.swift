import Cocoa
import XCTest
import TGUIKit
import InputTextView

final class QuoteRedrawLifecycleTests: XCTestCase {
    override func setUp() {
        TGUIKitTestBootstrap.install()
        System.updateScaleFactor(2)
    }

    override func tearDown() {
        System.updateScaleFactor(2)
        DeviceGraphicsContextSettings.install(nil)
    }

    func testCopiedLayerFirstAssignmentRendersAndThenCachesCurrentQuotes() {
        let helper = QuoteRedrawTests()
        let initial = helper.quotes()
        let source = helper.layer(initial)
        let sourcePixels = helper.pixels(source)
        let originalSource = OriginalRedrawQuoteLayer()
        originalSource.frame = source.frame
        originalSource.contentsScale = source.contentsScale
        originalSource.blockQuotes = initial
        originalSource.displayIfNeeded()
        let copied = FoldingTextQuoteLayer(layer: source)
        let original = OriginalRedrawQuoteLayer(layer: originalSource)
        XCTAssertEqual(copied.contents == nil, original.contents == nil)
        XCTAssertEqual(copied.bounds, original.bounds)
        XCTAssertEqual(copied.contentsScale, original.contentsScale)
        copied.frame = source.frame
        copied.contentsScale = source.contentsScale
        original.frame = source.frame
        original.contentsScale = source.contentsScale
        let next = helper.quotes(code: true)
        next[0].frame.size.width -= 31
        copied.blockQuotes = next
        XCTAssertTrue(copied.needsDisplay())
        original.blockQuotes = next
        XCTAssertEqual(helper.pixels(copied).differingPixels(from: helper.pixels(original), tolerance: 0), 0)
        copied.blockQuotes = next
        XCTAssertFalse(copied.needsDisplay())
        XCTAssertEqual(helper.pixels(source), sourcePixels)
        source.blockQuotes = initial
        XCTAssertFalse(source.needsDisplay())
    }

    func testAttachedLayerReparentsAndCachesCompletedAnimatedBounds() throws {
        let helper = QuoteRedrawTests()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        content.wantsLayer = true
        window.contentView = content
        defer { window.contentView = nil; window.close() }
        let firstHost = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 180))
        let secondHost = NSView(frame: NSRect(x: 300, y: 0, width: 280, height: 180))
        for host in [firstHost, secondHost] {
            host.wantsLayer = true
            content.addSubview(host)
        }
        let firstParent = try XCTUnwrap(firstHost.layer)
        let secondParent = try XCTUnwrap(secondHost.layer)
        let quotes = helper.quotes()
        let current = helper.layer(quotes)
        let original = OriginalRedrawQuoteLayer()
        original.frame = current.frame
        original.contentsScale = current.contentsScale
        original.blockQuotes = quotes
        firstParent.addSublayer(current)
        firstParent.addSublayer(original)
        XCTAssertTrue(firstHost.window === window)
        XCTAssertEqual(helper.pixels(current).differingPixels(from: helper.pixels(original), tolerance: 0), 0)
        current.blockQuotes = quotes
        XCTAssertFalse(current.needsDisplay())
        current.removeFromSuperlayer()
        original.removeFromSuperlayer()
        XCTAssertNil(current.superlayer)
        secondParent.addSublayer(current)
        secondParent.addSublayer(original)
        XCTAssertTrue(current.superlayer === secondParent)
        XCTAssertTrue(secondHost.window === window)
        XCTAssertEqual(helper.pixels(current).differingPixels(from: helper.pixels(original), tolerance: 0), 0)
        current.blockQuotes = quotes
        XCTAssertFalse(current.needsDisplay())

        let transition = ContainedViewLayoutTransition.animated(duration: 0.15, curve: .easeOut)
        let target = NSRect(x: 0, y: 0, width: 180, height: 90)
        original.blockQuotes = quotes
        transition.updateFrame(layer: current, frame: target)
        transition.updateFrame(layer: original, frame: target)
        XCTAssertTrue(current.needsDisplay())
        let animation = try XCTUnwrap(current.animation(forKey: "bounds") as? CABasicAnimation)
        XCTAssertEqual(animation.duration, 0.15)
        CATransaction.flush()
        let completion = expectation(description: "attached quote bounds animation completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { completion.fulfill() }
        wait(for: [completion], timeout: 3)
        XCTAssertEqual(current.frame, target)
        XCTAssertEqual(helper.pixels(current).differingPixels(from: helper.pixels(original), tolerance: 0), 0)
        current.blockQuotes = quotes
        XCTAssertFalse(current.needsDisplay())
        if let presentation = current.presentation() {
            XCTAssertEqual(presentation.bounds, current.bounds)
        }
    }
}
