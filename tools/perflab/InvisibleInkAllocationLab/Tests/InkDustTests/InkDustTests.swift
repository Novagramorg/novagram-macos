import AppKit
import QuartzCore
import XCTest
@testable import TGUIKit
@testable import OriginalInkDust

private final class InkWindow: NSWindow {
    var key = true
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { key }
}

final class InkDustTests: XCTestCase {
    private static var speckle: NSImage?

    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        if Self.speckle == nil {
            let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
                NSColor.white.setFill()
                rect.insetBy(dx: 1, dy: 1).fill()
                return true
            }
            XCTAssertTrue(image.setName("textSpeckle_Normal"))
            Self.speckle = image
        }
    }

    func configure(_ original: OriginalInvisibleInkDustView, _ current: InvisibleInkDustView, size: NSSize = NSSize(width: 120, height: 24), color: NSColor = .blue, rects: [CGRect]? = nil) {
        let rects = rects ?? [CGRect(origin: .zero, size: size)]
        let words = rects.map { $0.insetBy(dx: 2, dy: 2) }
        original.frame.size = size
        current.frame.size = size
        original.update(size: size, color: color, textColor: .white, rects: rects, wordRects: words)
        current.update(size: size, color: color, textColor: .white, rects: rects, wordRects: words)
    }

    func emitter(_ view: NSView) throws -> CAEmitterLayer {
        let host = try XCTUnwrap(view.subviews.first)
        XCTAssertEqual(view.subviews.count, 1)
        XCTAssertTrue(host.subviews.isEmpty)
        XCTAssertNil(host.layer?.mask)
        return try XCTUnwrap(host.layer?.sublayers?.first as? CAEmitterLayer)
    }

    func ownViewReferences(_ view: NSView) -> [NSView] {
        return Mirror(reflecting: view).children.compactMap { $0.value as? NSView }
    }

    private func assertEquivalent(_ original: OriginalInvisibleInkDustView, _ current: InvisibleInkDustView, file: StaticString = #filePath, line: UInt = #line) throws {
        let a = try emitter(original), b = try emitter(current)
        XCTAssertEqual(original.subviews[0].frame, current.subviews[0].frame, file: file, line: line)
        XCTAssertEqual(a.frame, b.frame, file: file, line: line)
        XCTAssertEqual(a.masksToBounds, b.masksToBounds, file: file, line: line)
        XCTAssertEqual(a.allowsGroupOpacity, b.allowsGroupOpacity, file: file, line: line)
        XCTAssertEqual(a.lifetime, b.lifetime, file: file, line: line)
        XCTAssertEqual(a.emitterPosition, b.emitterPosition, file: file, line: line)
        XCTAssertEqual(a.emitterSize, b.emitterSize, file: file, line: line)
        XCTAssertEqual(a.emitterShape, b.emitterShape, file: file, line: line)
        XCTAssertEqual(a.value(forKey: "emitterRects") as? NSArray, b.value(forKey: "emitterRects") as? NSArray, file: file, line: line)
        for key in ["stiffness", "enabled", "radius", "falloff"] {
            XCTAssertEqual(a.value(forKeyPath: "emitterBehaviors.fingerAttractor.\(key)") as? NSObject, b.value(forKeyPath: "emitterBehaviors.fingerAttractor.\(key)") as? NSObject, file: file, line: line)
        }
        let x = try XCTUnwrap(a.emitterCells?.first), y = try XCTUnwrap(b.emitterCells?.first)
        XCTAssertNotNil(x.contents, file: file, line: line)
        XCTAssertNotNil(y.contents, file: file, line: line)
        XCTAssertEqual(x.name, y.name, file: file, line: line)
        XCTAssertEqual(x.contentsScale, y.contentsScale, file: file, line: line)
        XCTAssertEqual(x.emissionRange, y.emissionRange, file: file, line: line)
        XCTAssertEqual(x.lifetime, y.lifetime, file: file, line: line)
        XCTAssertEqual(x.scale, y.scale, file: file, line: line)
        XCTAssertEqual(x.velocityRange, y.velocityRange, file: file, line: line)
        XCTAssertEqual(x.alphaRange, y.alphaRange, file: file, line: line)
        XCTAssertEqual(x.birthRate, y.birthRate, file: file, line: line)
        XCTAssertEqual(x.color, y.color, file: file, line: line)
        XCTAssertEqual(original.isEmitterPlaying, current.isEmitterPlaying, file: file, line: line)
    }

    func testOnlyUnusedRetainedViewsDisappearWhileAttachedTreeAndEmitterRemainEquivalent() throws {
        let original = OriginalInvisibleInkDustView(), current = InvisibleInkDustView()
        configure(original, current)
        XCTAssertEqual(ownViewReferences(original).count, 6)
        XCTAssertEqual(ownViewReferences(current).count, 1)
        XCTAssertTrue(ownViewReferences(original).filter { $0 !== original.subviews[0] }.allSatisfy { $0.window == nil && !$0.isDescendant(of: original) })
        XCTAssertTrue(ownViewReferences(current)[0] === current.subviews[0])
        XCTAssertNil(original.layer?.mask)
        XCTAssertNil(current.layer?.mask)
        try assertEquivalent(original, current)
    }

    func testResizeColorAndWordRectUpdatesPreserveEmitterAndHitGeometry() throws {
        let original = OriginalInvisibleInkDustView(), current = InvisibleInkDustView()
        configure(original, current)
        let oldEmitter = try emitter(original), newEmitter = try emitter(current)
        let sizes = [NSSize(width: 120, height: 24), NSSize(width: 260, height: 80), .zero]
        for size in sizes {
            for color in [NSColor.blue, .red, .labelColor] {
                let rects = size == .zero ? [] : [CGRect(x: 0, y: 0, width: size.width / 3, height: 12), CGRect(x: size.width / 2, y: 15, width: size.width / 3, height: 8)]
                configure(original, current, size: size, color: color, rects: rects)
                XCTAssertTrue(try emitter(original) === oldEmitter)
                XCTAssertTrue(try emitter(current) === newEmitter)
                try assertEquivalent(original, current)
                for point in [NSPoint(x: -1, y: -1), .zero, NSPoint(x: 5, y: 5), NSPoint(x: 100, y: 19), NSPoint(x: 270, y: 90)] {
                    XCTAssertEqual(original.point(inside: point, with: nil), current.point(inside: point, with: nil))
                }
            }
        }
    }

    private func waitForFade() {
        let done = expectation(description: "Reveal fade finishes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { done.fulfill() }
        wait(for: [done], timeout: 3)
    }

    func testWindowPlaybackRevealHideAndReparentingMatchOriginal() throws {
        let original = OriginalInvisibleInkDustView(), current = InvisibleInkDustView()
        configure(original, current)
        XCTAssertFalse(current.isEmitterPlaying)
        let window = InkWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        defer { window.contentView = nil; window.close() }
        window.contentView?.addSubview(original)
        window.contentView?.addSubview(current)
        XCTAssertTrue(current.isEmitterPlaying)
        try assertEquivalent(original, current)
        for key in [false, true] {
            window.key = key
            NotificationCenter.default.post(name: key ? NSWindow.didBecomeKeyNotification : NSWindow.didResignKeyNotification, object: window)
            XCTAssertEqual(current.isEmitterPlaying, key)
            try assertEquivalent(original, current)
        }
        original.update(revealed: true)
        current.update(revealed: true)
        XCTAssertFalse(current.point(inside: NSPoint(x: 5, y: 5), with: nil))
        waitForFade()
        XCTAssertFalse(current.isEmitterPlaying)
        XCTAssertEqual(original.alphaValue, current.alphaValue)
        try assertEquivalent(original, current)
        original.update(revealed: false)
        current.update(revealed: false)
        XCTAssertTrue(current.isEmitterPlaying)
        XCTAssertTrue(current.point(inside: NSPoint(x: 5, y: 5), with: nil))
        original.removeFromSuperview()
        current.removeFromSuperview()
        XCTAssertFalse(current.isEmitterPlaying)
        try assertEquivalent(original, current)
        window.contentView?.addSubview(original)
        window.contentView?.addSubview(current)
        XCTAssertTrue(current.isEmitterPlaying)
        try assertEquivalent(original, current)
    }

    func testPendingRevealTimersDoNotRetainDetachedViews() {
        weak var original: OriginalInvisibleInkDustView?
        weak var current: InvisibleInkDustView?
        autoreleasepool {
            let a = OriginalInvisibleInkDustView(), b = InvisibleInkDustView()
            configure(a, b)
            original = a
            current = b
            a.update(revealed: true)
            b.update(revealed: true)
        }
        waitForFade()
        XCTAssertNil(original)
        XCTAssertNil(current)
    }
}
