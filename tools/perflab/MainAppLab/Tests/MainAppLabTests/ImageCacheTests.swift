import XCTest
import AppKit
@testable import Production

final class ImageCacheTests: XCTestCase {
    private func image(_ size: Int = 8) -> CGImage {
        return CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    func testRemovingOneOfSeveralImagesKeepsTimer() {
        let cache = ScopedImageCache(countLimit: 10, byteLimit: .max, idleTimeout: 300, closedScopeGrace: 0, sweepInterval: 3600)
        let first = image()
        let second = image(16)
        cache.setImage(first, sampleBuffer: nil, forKey: 1)
        cache.setImage(second, sampleBuffer: nil, forKey: 2)
        cache.removeImage(forKey: 1)
        XCTAssertEqual(cache.count, 1)
        XCTAssertTrue(cache.isSweeping)
        XCTAssertTrue(cache.image(forKey: 2)?.0 === second)
        XCTAssertEqual(cache.cost, second.bytesPerRow * second.height)
    }

    func testReplacingOnlyImageKeepsTimerAndCorrectCost() {
        let cache = ScopedImageCache(countLimit: 10, byteLimit: .max, idleTimeout: 300, closedScopeGrace: 0, sweepInterval: 3600)
        for size in 1 ... 32 {
            let value = image(size)
            cache.setImage(value, sampleBuffer: nil, forKey: 1)
            XCTAssertEqual(cache.count, 1)
            XCTAssertTrue(cache.isSweeping)
            XCTAssertTrue(cache.image(forKey: 1)?.0 === value)
            XCTAssertEqual(cache.cost, value.bytesPerRow * value.height)
        }
    }

    func testOversizedReplacementStopsExistingTimer() {
        let cache = ScopedImageCache(countLimit: 10, byteLimit: 256, idleTimeout: 300, closedScopeGrace: 0, sweepInterval: 3600)
        cache.setImage(image(), sampleBuffer: nil, forKey: 1)
        XCTAssertTrue(cache.isSweeping)
        cache.setImage(image(32), sampleBuffer: nil, forKey: 1)
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.cost, 0)
        XCTAssertFalse(cache.isSweeping)
    }

    func testZeroCountLimitDoesNotStartTimer() {
        let cache = ScopedImageCache(countLimit: 0, byteLimit: .max, idleTimeout: 300, closedScopeGrace: 0)
        cache.setImage(image(), sampleBuffer: nil, forKey: 1)
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.cost, 0)
        XCTAssertFalse(cache.isSweeping)
    }

    func testLRUEvictionAndSweepPreserveAccounting() {
        var now = 0.0
        let cache = ScopedImageCache(countLimit: 2, byteLimit: 512, idleTimeout: 10, closedScopeGrace: 0, sweepInterval: 3600, clock: { now })
        for key in 1 ... 2 {
            now += 1
            cache.setImage(image(), sampleBuffer: nil, forKey: key)
        }
        now += 1
        XCTAssertNotNil(cache.image(forKey: 1))
        now += 1
        cache.setImage(image(), sampleBuffer: nil, forKey: 3)
        XCTAssertNil(cache.image(forKey: 2))
        XCTAssertNotNil(cache.image(forKey: 1))
        XCTAssertNotNil(cache.image(forKey: 3))
        XCTAssertEqual(cache.cost, 512)
        now = 20
        cache.sweep()
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.cost, 0)
        XCTAssertFalse(cache.isSweeping)
    }

    func testConcurrentMutationAndSweepLeaveNoTimerOrCost() {
        let cache = ScopedImageCache(countLimit: 50, byteLimit: 256 * 40, idleTimeout: 0.001, closedScopeGrace: 0, sweepInterval: 3600)
        let images = (0 ..< 64).map { _ in image() }
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for step in 0 ..< 2000 {
                let key = (worker * 31 + step) % images.count
                switch step % 4 {
                case 0: cache.setImage(images[key], sampleBuffer: nil, forKey: key)
                case 1: _ = cache.image(forKey: key)
                case 2: cache.removeImage(forKey: key)
                default: cache.sweep()
                }
            }
        }
        XCTAssertLessThanOrEqual(cache.count, 40)
        XCTAssertEqual(cache.cost, cache.count * 256)
        for key in 0 ..< 64 {
            cache.removeImage(forKey: key)
        }
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.cost, 0)
        XCTAssertFalse(cache.isSweeping)
    }
}
