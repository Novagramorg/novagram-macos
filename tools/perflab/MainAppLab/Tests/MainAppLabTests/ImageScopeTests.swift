import XCTest
import AppKit
@testable import Production

final class ImageScopeTests: XCTestCase {
    func testClosingLastScopeStopsTimerWithZeroGrace() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let cache = ScopedImageCache(countLimit: 10, byteLimit: .max, idleTimeout: 300, closedScopeGrace: 0, sweepInterval: 3600)
        let image = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        cache.setImage(image, sampleBuffer: nil, forKey: 1)
        weak var released: NSScrollView?
        autoreleasepool {
            let scroll = NSScrollView(frame: window.contentView!.bounds)
            let view = NSView(frame: scroll.bounds)
            scroll.documentView = view
            window.contentView!.addSubview(scroll)
            released = scroll
            ScopedImageCache.noteDisplayed(image, in: view)
            scroll.removeFromSuperview()
        }
        XCTAssertNil(released)
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.cost, 0)
        XCTAssertFalse(cache.isSweeping)
    }
}
