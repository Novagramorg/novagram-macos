import XCTest
import AppKit
import SwiftSignalKit
@testable import TGUIKit

private final class ManualClock {
    var now: CFAbsoluteTime = 1000
}

private final class Screen {
    private(set) var scrollView: NSScrollView?
    private(set) var document: NSView?

    init(in window: NSWindow, frame: NSRect = NSMakeRect(0, 0, 200, 200)) {
        autoreleasepool {
            let scrollView = NSScrollView(frame: frame)
            let document = NSView(frame: NSMakeRect(0, 0, frame.width, frame.height * 4))
            scrollView.documentView = document
            window.contentView?.addSubview(scrollView)
            self.scrollView = scrollView
            self.document = document
        }
    }

    @discardableResult
    func show(_ image: CGImage) -> TransformImageView {
        return autoreleasepool {
            let view = TransformImageView(frame: NSMakeRect(0, 0, 50, 50))
            document?.addSubview(view)
            view.image = image
            return view
        }
    }

    func dismantle() {
        scrollView?.removeFromSuperview()
        scrollView = nil
        document = nil
    }
}

final class ScopedImageCacheTests: XCTestCase {
    private var window: NSWindow!
    private var clock: ManualClock!

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        clock = ManualClock()
        window = NSWindow(contentRect: NSMakeRect(0, 0, 400, 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSMakeRect(0, 0, 400, 400))
    }

    override func tearDown() {
        window.contentView = nil
        window = nil
        clock = nil
        super.tearDown()
    }

    private func makeCache(countLimit: Int = 100, byteLimit: Int = 100 * 1024 * 1024, idleTimeout: TimeInterval = 300, grace: TimeInterval = 15) -> ScopedImageCache {
        let clock = self.clock!
        return ScopedImageCache(countLimit: countLimit, byteLimit: byteLimit, idleTimeout: idleTimeout, closedScopeGrace: grace, sweepInterval: 3600, clock: { clock.now })
    }

    private func close(_ screen: Screen) {
        weak var scrollView: NSScrollView?
        autoreleasepool {
            scrollView = screen.scrollView
            screen.dismantle()
        }
        waitUntilReleased { scrollView }
    }

    private func waitUntilReleased(_ object: () -> AnyObject?) {
        let deadline = Date().addingTimeInterval(3)
        while object() != nil && Date() < deadline {
            autoreleasepool {
                CATransaction.flush()
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
        }
        XCTAssertNil(object(), "the closed view must be deallocated for the test to mean anything")
    }

    private func drain() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }

    private func bytes(_ image: CGImage) -> Int {
        return image.bytesPerRow * image.height
    }

    func testReturnsStoredImageAndReplacesByKey() {
        let cache = makeCache()
        let first = testImage(CGSize(width: 10, height: 10))
        let second = testImage(CGSize(width: 20, height: 20))
        XCTAssertNil(cache.image(forKey: 1))
        cache.setImage(first, sampleBuffer: nil, forKey: 1)
        XCTAssertTrue(cache.image(forKey: 1)?.0 === first)
        cache.setImage(second, sampleBuffer: nil, forKey: 1)
        XCTAssertTrue(cache.image(forKey: 1)?.0 === second)
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.cost, bytes(second))
        cache.removeImage(forKey: 1)
        XCTAssertNil(cache.image(forKey: 1))
        XCTAssertEqual(cache.cost, 0)
    }

    func testCountLimitEvictsLeastRecentlyUsed() {
        let cache = makeCache(countLimit: 3)
        for key in 0 ..< 3 {
            cache.setImage(testImage(CGSize(width: 4, height: 4)), sampleBuffer: nil, forKey: key)
            clock.now += 1
        }
        _ = cache.image(forKey: 0)
        clock.now += 1
        cache.setImage(testImage(CGSize(width: 4, height: 4)), sampleBuffer: nil, forKey: 3)
        XCTAssertEqual(cache.count, 3)
        XCTAssertNotNil(cache.image(forKey: 0))
        XCTAssertNil(cache.image(forKey: 1))
        XCTAssertNotNil(cache.image(forKey: 2))
        XCTAssertNotNil(cache.image(forKey: 3))
    }

    func testByteLimitEvictsUntilUnderBudget() {
        let small = testImage(CGSize(width: 10, height: 10))
        let cache = makeCache(byteLimit: bytes(small) * 3)
        for key in 0 ..< 3 {
            cache.setImage(testImage(CGSize(width: 10, height: 10)), sampleBuffer: nil, forKey: key)
            clock.now += 1
        }
        let large = testImage(CGSize(width: 10, height: 20))
        cache.setImage(large, sampleBuffer: nil, forKey: 9)
        XCTAssertLessThanOrEqual(cache.cost, bytes(small) * 3)
        XCTAssertNil(cache.image(forKey: 0))
        XCTAssertNil(cache.image(forKey: 1))
        XCTAssertNotNil(cache.image(forKey: 2))
        XCTAssertNotNil(cache.image(forKey: 9))
    }

    func testIdleEntriesExpireAndReadsKeepThemAlive() {
        let cache = makeCache(idleTimeout: 60)
        cache.setImage(testImage(CGSize(width: 4, height: 4)), sampleBuffer: nil, forKey: 1)
        cache.setImage(testImage(CGSize(width: 4, height: 4)), sampleBuffer: nil, forKey: 2)
        clock.now += 40
        _ = cache.image(forKey: 1)
        clock.now += 30
        cache.sweep()
        XCTAssertNotNil(cache.image(forKey: 1))
        XCTAssertNil(cache.image(forKey: 2))
    }

    func testSweepTimerRunsOnlyWhileTheCacheHoldsImages() {
        let cache = makeCache(idleTimeout: 60)
        XCTAssertFalse(cache.isSweeping)
        cache.setImage(testImage(CGSize(width: 4, height: 4)), sampleBuffer: nil, forKey: 1)
        XCTAssertTrue(cache.isSweeping)
        clock.now += 61
        cache.sweep()
        XCTAssertEqual(cache.count, 0)
        XCTAssertFalse(cache.isSweeping)
        cache.setImage(testImage(CGSize(width: 4, height: 4)), sampleBuffer: nil, forKey: 1)
        XCTAssertTrue(cache.isSweeping)
        cache.removeAll()
        XCTAssertFalse(cache.isSweeping)
        XCTAssertEqual(cache.cost, 0)
    }

    func testClosedScreenReleasesItsImagesAfterTheGrace() {
        let cache = makeCache(grace: 15)
        let image = testImage(CGSize(width: 8, height: 8))
        cache.setImage(image, sampleBuffer: nil, forKey: 1)
        let screen = Screen(in: window)
        screen.show(image)
        close(screen)

        clock.now += 14
        cache.sweep()
        XCTAssertNotNil(cache.image(forKey: 1))

        clock.now += 1
        cache.sweep()
        XCTAssertNil(cache.image(forKey: 1))
        XCTAssertEqual(cache.cost, 0)
    }

    func testScrolledPastImagesStayWhileTheScreenIsOpen() {
        let cache = makeCache(grace: 15)
        let image = testImage(CGSize(width: 8, height: 8))
        cache.setImage(image, sampleBuffer: nil, forKey: 1)
        let screen = Screen(in: window)
        autoreleasepool {
            let view = screen.show(image)
            view.removeFromSuperview()
        }
        drain()
        clock.now += 120
        cache.sweep()
        XCTAssertTrue(cache.image(forKey: 1)?.0 === image)
        withExtendedLifetime(screen) {}
    }

    func testImagesNeverShownOnAScreenKeepTheIdleRule() {
        let cache = makeCache(idleTimeout: 300, grace: 15)
        let shown = testImage(CGSize(width: 8, height: 8))
        let hidden = testImage(CGSize(width: 8, height: 8))
        cache.setImage(shown, sampleBuffer: nil, forKey: 1)
        cache.setImage(hidden, sampleBuffer: nil, forKey: 2)
        let screen = Screen(in: window)
        screen.show(shown)
        close(screen)
        clock.now += 60
        cache.sweep()
        XCTAssertNil(cache.image(forKey: 1))
        XCTAssertNotNil(cache.image(forKey: 2))
    }

    func testImageSharedWithAnotherOpenScreenSurvives() {
        let cache = makeCache(grace: 15)
        let image = testImage(CGSize(width: 8, height: 8))
        cache.setImage(image, sampleBuffer: nil, forKey: 1)
        let closing = Screen(in: window)
        let staying = Screen(in: window, frame: NSMakeRect(200, 0, 200, 200))
        closing.show(image)
        staying.show(image)
        close(closing)
        clock.now += 60
        cache.sweep()
        XCTAssertNotNil(cache.image(forKey: 1))
        withExtendedLifetime(staying) {}
    }

    func testReopeningWithinTheGraceKeepsTheImage() {
        let cache = makeCache(grace: 15)
        let image = testImage(CGSize(width: 8, height: 8))
        cache.setImage(image, sampleBuffer: nil, forKey: 1)
        let first = Screen(in: window)
        first.show(image)
        close(first)

        clock.now += 5
        let reopened = Screen(in: window)
        reopened.show(cache.image(forKey: 1)!.0)
        clock.now += 60
        cache.sweep()
        XCTAssertNotNil(cache.image(forKey: 1))

        close(reopened)
        clock.now += 15
        cache.sweep()
        XCTAssertNil(cache.image(forKey: 1))
    }

    func testZeroGraceReleasesWhenTheScreenCloses() {
        let cache = makeCache(grace: 0)
        let image = testImage(CGSize(width: 8, height: 8))
        cache.setImage(image, sampleBuffer: nil, forKey: 1)
        let screen = Screen(in: window)
        screen.show(image)
        close(screen)
        XCTAssertNil(cache.image(forKey: 1))
        XCTAssertEqual(cache.cost, 0)
    }

    func testGraceExpiryRunsWithoutAPeriodicSweep() {
        let cache = ScopedImageCache(countLimit: 100, byteLimit: .max, idleTimeout: 300, closedScopeGrace: 0.1, sweepInterval: 3600)
        let image = testImage(CGSize(width: 8, height: 8))
        cache.setImage(image, sampleBuffer: nil, forKey: 1)
        let screen = Screen(in: window)
        screen.show(image)
        close(screen)
        XCTAssertEqual(cache.count, 1)
        let deadline = Date().addingTimeInterval(3)
        while cache.count > 0 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(cache.count, 0)
    }

    func testOrphansAreEvictedBeforeLiveImagesUnderPressure() {
        let unit = testImage(CGSize(width: 10, height: 10))
        let cache = makeCache(byteLimit: bytes(unit) * 2, grace: 15)
        let live = testImage(CGSize(width: 10, height: 10))
        cache.setImage(live, sampleBuffer: nil, forKey: 1)
        clock.now += 1
        let orphan = testImage(CGSize(width: 10, height: 10))
        cache.setImage(orphan, sampleBuffer: nil, forKey: 2)
        let screen = Screen(in: window)
        screen.show(orphan)
        close(screen)
        clock.now += 1
        cache.setImage(testImage(CGSize(width: 10, height: 10)), sampleBuffer: nil, forKey: 3)
        XCTAssertNotNil(cache.image(forKey: 1))
        XCTAssertNil(cache.image(forKey: 2))
        XCTAssertNotNil(cache.image(forKey: 3))
    }

    func testNestedScrollViewsBelongToTheOutermostScreen() {
        let cache = makeCache(grace: 0)
        let image = testImage(CGSize(width: 8, height: 8))
        cache.setImage(image, sampleBuffer: nil, forKey: 1)
        let screen = Screen(in: window)
        weak var inner: NSScrollView?
        autoreleasepool {
            let strip = NSScrollView(frame: NSMakeRect(0, 0, 100, 60))
            let content = NSView(frame: NSMakeRect(0, 0, 300, 60))
            strip.documentView = content
            screen.document?.addSubview(strip)
            let view = TransformImageView(frame: NSMakeRect(0, 0, 50, 50))
            content.addSubview(view)
            view.image = image
            inner = strip
            strip.removeFromSuperview()
        }
        waitUntilReleased { inner }
        XCTAssertNotNil(cache.image(forKey: 1))
        withExtendedLifetime(screen) {}
    }

    func testViewsOutsideScrollViewsShareTheWindowScope() {
        let first = TransformImageView(frame: NSMakeRect(0, 0, 10, 10))
        let second = TransformImageView(frame: NSMakeRect(20, 0, 10, 10))
        let detached = TransformImageView(frame: NSMakeRect(0, 0, 10, 10))
        window.contentView?.addSubview(first)
        window.contentView?.addSubview(second)
        let firstScope = ScopedImageCache.displayScope(for: first)
        XCTAssertNotNil(firstScope)
        XCTAssertTrue(firstScope === ScopedImageCache.displayScope(for: second))
        XCTAssertNil(ScopedImageCache.displayScope(for: detached))
    }

    func testImageShownBeforeTheRowJoinsTheWindowIsAttributedOnAttach() {
        let cache = makeCache(grace: 0)
        let image = testImage(CGSize(width: 8, height: 8))
        cache.setImage(image, sampleBuffer: nil, forKey: 1)
        let screen = Screen(in: window)
        autoreleasepool {
            let row = NSView(frame: NSMakeRect(0, 0, 50, 50))
            let view = TransformImageView(frame: row.bounds)
            row.addSubview(view)
            view.image = image
            screen.document?.addSubview(row)
        }
        close(screen)
        XCTAssertNil(cache.image(forKey: 1))
    }

    func testCachedResultShownThroughSetSignalIsAttributed() {
        let cache = makeCache(grace: 0)
        let image = testImage(CGSize(width: 8, height: 8))
        cache.setImage(image, sampleBuffer: nil, forKey: 1)
        let screen = Screen(in: window)
        autoreleasepool {
            let view = TransformImageView(frame: NSMakeRect(0, 0, 50, 50))
            screen.document?.addSubview(view)
            let cached = cache.image(forKey: 1).map { TransformImageResult($0.0, true, $0.1) }
            view.setSignal(signal: .single(cached), clearInstantly: true)
            waitUntil { view.image === image }
        }
        close(screen)
        XCTAssertNil(cache.image(forKey: 1))
    }

    func testFreshRenderCachedAfterDisplayIsAttributed() {
        let cache = makeCache(grace: 0)
        let screen = Screen(in: window)
        autoreleasepool {
            let view = TransformImageView(frame: NSMakeRect(0, 0, 50, 50))
            screen.document?.addSubview(view)
            let transformation = ImageDataTransformation(data: ImageRenderData(nil, nil, true), execute: { arguments, _ in
                let context = DrawingContext(size: arguments.imageSize, scale: 2, clear: true)
                context.withContext { ctx in
                    ctx.setFillColor(NSColor.red.cgColor)
                    ctx.fill(CGRect(origin: .zero, size: arguments.imageSize))
                }
                return context
            })
            view.setSignal(.single(transformation), synchronousLoad: true, cacheImage: { result in
                if let image = result.image {
                    cache.setImage(image, sampleBuffer: nil, forKey: 7)
                }
            })
            view.set(arguments: TransformImageArguments(corners: ImageCorners(), imageSize: NSMakeSize(20, 20), boundingSize: NSMakeSize(20, 20), intrinsicInsets: NSEdgeInsets()))
            waitUntil { cache.image(forKey: 7) != nil }
        }
        XCTAssertNotNil(cache.image(forKey: 7))
        close(screen)
        XCTAssertNil(cache.image(forKey: 7))
    }

    func testSameImageUnderTwoKeysIsReleasedForBoth() {
        let cache = makeCache(grace: 0)
        let image = testImage(CGSize(width: 8, height: 8))
        cache.setImage(image, sampleBuffer: nil, forKey: 1)
        cache.setImage(image, sampleBuffer: nil, forKey: 2)
        let screen = Screen(in: window)
        screen.show(image)
        close(screen)
        XCTAssertNil(cache.image(forKey: 1))
        XCTAssertNil(cache.image(forKey: 2))
        XCTAssertEqual(cache.cost, 0)
    }

    func testReplacedEntryForgetsTheOldImage() {
        let cache = makeCache(grace: 0)
        let old = testImage(CGSize(width: 8, height: 8))
        let new = testImage(CGSize(width: 8, height: 8))
        cache.setImage(old, sampleBuffer: nil, forKey: 1)
        let screen = Screen(in: window)
        screen.show(old)
        cache.setImage(new, sampleBuffer: nil, forKey: 1)
        close(screen)
        XCTAssertTrue(cache.image(forKey: 1)?.0 === new)
    }

    func testDeallocatedCacheIsSkippedWhenAScreenCloses() {
        weak var released: ScopedImageCache?
        let image = testImage(CGSize(width: 8, height: 8))
        let screen = Screen(in: window)
        autoreleasepool {
            let cache = makeCache(grace: 0)
            cache.setImage(image, sampleBuffer: nil, forKey: 1)
            screen.show(image)
            released = cache
        }
        XCTAssertNil(released)
        close(screen)
    }

    func testConcurrentAccessKeepsTheBookkeepingConsistent() {
        let unit = testImage(CGSize(width: 4, height: 4))
        let cache = ScopedImageCache(countLimit: 50, byteLimit: bytes(unit) * 40, idleTimeout: 0.001, closedScopeGrace: 0, sweepInterval: 3600)
        let images = (0 ..< 64).map { _ in testImage(CGSize(width: 4, height: 4)) }
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for step in 0 ..< 2000 {
                let key = (worker * 31 + step) % images.count
                switch step % 4 {
                case 0:
                    cache.setImage(images[key], sampleBuffer: nil, forKey: key)
                case 1:
                    _ = cache.image(forKey: key)
                case 2:
                    cache.removeImage(forKey: key)
                default:
                    if step % 100 == 3 {
                        cache.sweep()
                    }
                }
            }
        }
        XCTAssertLessThanOrEqual(cache.count, 50)
        XCTAssertLessThanOrEqual(cache.cost, bytes(unit) * 40)
        cache.removeAll()
        XCTAssertEqual(cache.cost, 0)
    }

    private func waitUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition())
    }
}
