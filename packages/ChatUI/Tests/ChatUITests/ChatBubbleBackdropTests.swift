import XCTest
import AppKit
import TGUIKit
@testable import ChatUI

private final class LegacyBubbleBackdrop: NSView {
    var backgroundContent: NSView?
    let borderView: SImageView = SImageView()
    var maskView: SImageView?
    private var lastUpdate: (rect: CGRect, containerSize: CGSize, rotated: Bool)?
    private var maskData: (CGImage, NSEdgeInsets)?
    private var borderData: (CGImage, NSEdgeInsets)?

    init() {
        super.init(frame: NSZeroRect)
        autoresizingMask = []
        autoresizesSubviews = false
        wantsLayer = true
        self.layer?.masksToBounds = true
        self.addSubview(self.borderView)
        self.layer?.disableActions()
    }

    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateLayout(size: NSSize) {
        if let view = maskView {
            view.frame = size.bounds
        }
        borderView.frame = size.bounds
        applyImages()
    }

    func setType(image: (CGImage, NSEdgeInsets)?, border: (CGImage, NSEdgeInsets)?, background: CGImage) {
        lastUpdate = nil
        if let _ = image {
            if self.maskView == nil {
                let maskView = SImageView()
                maskView.frame = self.bounds
                self.maskView = maskView
                self.layer?.mask = maskView.layer
            }
        } else if self.maskView != nil {
            self.layer?.mask = nil
            self.maskView = nil
        }
        self.maskData = image
        self.borderData = border
        if image == nil {
            self.backgroundContent?.removeFromSuperview()
            self.backgroundContent = nil
        } else {
            let current: NSView
            if let view = self.backgroundContent {
                current = view
            } else {
                current = NSView()
                current.wantsLayer = true
                self.backgroundContent = current
                addSubview(current, positioned: .below, relativeTo: self.borderView)
            }
            current.layer?.contents = background
        }
        applyImages()
    }

    private func applyImages() {
        self.maskView?.data = self.maskData
        self.borderView.data = self.borderData
    }

    func update(rect: CGRect, within containerSize: CGSize, rotated: Bool) {
        if let last = lastUpdate, last.rect == rect, last.containerSize == containerSize, last.rotated == rotated {
            return
        }
        if let backgroundContent = backgroundContent, let layer = backgroundContent.layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = CGRect(origin: CGPoint(x: -rect.minX, y: -rect.minY), size: containerSize)
            CATransaction.commit()
        }
        if lastUpdate?.rotated != rotated {
            backgroundContent?.rotate(byDegrees: rotated ? 180 : 0)
        }
        lastUpdate = (rect, containerSize, rotated)
    }
}

final class ChatBubbleBackdropTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func image(_ size: CGSize, _ color: NSColor) -> CGImage {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2), cornerWidth: 16, cornerHeight: 16, transform: nil))
        context.fillPath()
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width / 3, height: 3))
        return context.makeImage()!
    }

    private lazy var mask = (image(CGSize(width: 80, height: 80), .white), NSEdgeInsets(top: 36, left: 36, bottom: 36, right: 36))
    private lazy var border = (image(CGSize(width: 80, height: 80), .gray), NSEdgeInsets(top: 30, left: 30, bottom: 30, right: 32))
    private lazy var background = image(CGSize(width: 400, height: 800), .systemBlue)

    private struct Scenario {
        let hasMask: Bool
        let rotated: Bool
    }

    private let scenarios: [Scenario] = [
        Scenario(hasMask: true, rotated: false),
        Scenario(hasMask: true, rotated: true),
        Scenario(hasMask: false, rotated: false),
    ]

    private func host(_ view: NSView) -> NSWindow {
        let window = SnapshotWindow(contentRect: NSMakeRect(0, 0, 400, 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSMakeRect(0, 0, 400, 300))
        root.wantsLayer = true
        window.contentView = root
        view.frame = NSMakeRect(30, 40, 220, 64)
        root.addSubview(view)
        return window
    }

    private func make(_ scenario: Scenario) -> (legacy: LegacyBubbleBackdrop, current: ChatMessageBubbleBackdrop, windows: [NSWindow]) {
        let legacy = LegacyBubbleBackdrop()
        let current = ChatMessageBubbleBackdrop()
        let windows = [host(legacy), host(current)]
        let maskData: (CGImage, NSEdgeInsets)? = scenario.hasMask ? mask : nil
        legacy.setType(image: maskData, border: border, background: background)
        current.setType(image: maskData, border: border, background: background)
        legacy.updateLayout(size: legacy.frame.size)
        current.updateLayout(size: current.frame.size, transition: .immediate)
        CATransaction.flush()
        let rect = NSMakeRect(30, 120, 220, 64)
        let container = NSMakeSize(400, 800)
        legacy.update(rect: rect, within: container, rotated: scenario.rotated)
        current.update(rect: rect, within: container, transition: .immediate, rotated: scenario.rotated)
        CATransaction.flush()
        return (legacy, current, windows)
    }

    private func ownLayers(_ view: NSView) -> [CALayer] {
        return (view.layer?.sublayers ?? []).filter { !($0.delegate is NSView) }
    }

    private func assertSameSlice(_ legacy: CALayer?, _ current: CALayer?, _ label: String) {
        XCTAssertNotNil(legacy, label)
        XCTAssertNotNil(current, label)
        guard let legacy = legacy, let current = current else {
            return
        }
        XCTAssertTrue((legacy.contents as AnyObject?) === (current.contents as AnyObject?), label)
        XCTAssertEqual(legacy.contentsCenter, current.contentsCenter, label)
        XCTAssertEqual(legacy.contentsGravity, current.contentsGravity, label)
        XCTAssertEqual(legacy.contentsScale, current.contentsScale, label)
        XCTAssertEqual(legacy.frame, current.frame, label)
    }

    private func assertClose(_ lhs: CGAffineTransform, _ rhs: CGAffineTransform, _ label: String) {
        let left = [lhs.a, lhs.b, lhs.c, lhs.d, lhs.tx, lhs.ty]
        let right = [rhs.a, rhs.b, rhs.c, rhs.d, rhs.tx, rhs.ty]
        for (l, r) in zip(left, right) {
            XCTAssertEqual(l, r, accuracy: 0.0001, label)
        }
    }

    private func assertClose(_ lhs: [CGPoint], _ rhs: [CGPoint], _ label: String) {
        XCTAssertEqual(lhs.count, rhs.count, label)
        for (l, r) in zip(lhs, rhs) {
            XCTAssertEqual(l.x, r.x, accuracy: 0.0001, label)
            XCTAssertEqual(l.y, r.y, accuracy: 0.0001, label)
        }
    }

    private func visibleRect(_ layer: CALayer, in parent: CALayer) -> CGRect {
        let points = corners(layer, in: parent)
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        let visible = box.intersection(parent.bounds)
        if visible.isNull || visible.width * visible.height == 0 {
            return .zero
        }
        return visible
    }

    private func corners(_ layer: CALayer, in parent: CALayer) -> [CGPoint] {
        let bounds = layer.bounds
        return [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY), CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY)].map { layer.convert($0, to: parent) }
    }

    func testMessageRowBubbleHasNoSubviews() {
        let row = ChatRowView(frame: NSMakeRect(0, 0, 400, 60))
        XCTAssertEqual(row.bubbleView.subviews.count, 0)
    }

    func testBackdropHasNoSubviews() {
        for scenario in scenarios {
            let made = make(scenario)
            XCTAssertEqual(made.current.subviews.count, 0)
            XCTAssertEqual(made.legacy.subviews.count, scenario.hasMask ? 2 : 1)
            made.windows.forEach { $0.close() }
        }
    }

    func testBorderMatchesTheLegacySlice() {
        for scenario in scenarios {
            let made = make(scenario)
            assertSameSlice(made.legacy.borderView.layer, ownLayers(made.current).last, "border \(scenario)")
            made.windows.forEach { $0.close() }
        }
    }

    func testMaskMatchesTheLegacySlice() {
        for scenario in scenarios {
            let made = make(scenario)
            if scenario.hasMask {
                assertSameSlice(made.legacy.layer?.mask, made.current.layer?.mask, "mask \(scenario)")
            } else {
                XCTAssertNil(made.legacy.layer?.mask)
                XCTAssertNil(made.current.layer?.mask)
            }
            made.windows.forEach { $0.close() }
        }
    }

    func testBackgroundSitsBelowTheBorderWithTheSameGeometry() {
        for scenario in scenarios {
            let made = make(scenario)
            let layers = ownLayers(made.current)
            if scenario.hasMask {
                XCTAssertEqual(layers.count, 2, "\(scenario)")
                guard let legacyLayer = made.legacy.backgroundContent?.layer, let currentLayer = layers.first, let legacyParent = made.legacy.layer, let currentParent = made.current.layer else {
                    XCTFail("missing background \(scenario)")
                    continue
                }
                XCTAssertTrue((legacyLayer.contents as AnyObject?) === (currentLayer.contents as AnyObject?))
                XCTAssertEqual(visibleRect(legacyLayer, in: legacyParent), visibleRect(currentLayer, in: currentParent), "\(scenario)")
                if !scenario.rotated {
                    XCTAssertEqual(legacyLayer.frame, currentLayer.frame, "\(scenario)")
                    assertClose(legacyLayer.affineTransform(), currentLayer.affineTransform(), "\(scenario)")
                    assertClose(corners(legacyLayer, in: legacyParent), corners(currentLayer, in: currentParent), "\(scenario)")
                }
            } else {
                XCTAssertEqual(layers.count, 1, "\(scenario)")
                XCTAssertNil(made.legacy.backgroundContent)
            }
            made.windows.forEach { $0.close() }
        }
    }

    func testPreviewRotationShowsTheSameAreaAsTheViewBackground() {
        let legacy = LegacyBubbleBackdrop()
        let current = ChatMessageBubbleBackdrop()
        let windows = [host(legacy), host(current)]
        legacy.setType(image: mask, border: border, background: background)
        current.setType(image: mask, border: border, background: background)
        CATransaction.flush()
        let steps: [(CGRect, Bool)] = [
            (NSMakeRect(10, 10, 220, 64), false),
            (NSMakeRect(10, 10, 220, 64), true),
            (NSMakeRect(10, 10, 220, 64), false),
            (NSMakeRect(14, 30, 220, 64), false),
            (NSMakeRect(14, 30, 220, 64), false),
        ]
        for (index, step) in steps.enumerated() {
            legacy.update(rect: step.0, within: NSMakeSize(400, 800), rotated: step.1)
            current.update(rect: step.0, within: NSMakeSize(400, 800), transition: .immediate, rotated: step.1)
            CATransaction.flush()
            guard let legacyLayer = legacy.backgroundContent?.layer, let currentLayer = ownLayers(current).first else {
                XCTFail("missing background")
                continue
            }
            XCTAssertEqual(visibleRect(legacyLayer, in: legacy.layer!), visibleRect(currentLayer, in: current.layer!), "step \(index)")
        }
        windows.forEach { $0.close() }
    }

    func testRepeatedIdenticalSetTypeCost() {
        let backdrop = ChatMessageBubbleBackdrop()
        let window = host(backdrop)
        let rect = NSMakeRect(30, 120, 220, 64)
        let container = NSMakeSize(400, 800)
        backdrop.setType(image: mask, border: border, background: background)
        backdrop.updateLayout(size: backdrop.frame.size, transition: .immediate)
        backdrop.update(rect: rect, within: container, transition: .immediate)
        let maskLayer = backdrop.layer?.mask
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0 ..< 100000 {
            backdrop.setType(image: mask, border: border, background: background)
            backdrop.update(rect: rect, within: container, transition: .immediate)
        }
        CATransaction.flush()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print(String(format: "ChatBubbleBackdrop identical setType+update: %.2f µs each", elapsed / 100000 * 1e6))
        XCTAssertTrue(backdrop.layer?.mask === maskLayer)
        withExtendedLifetime(window) {}
    }
}
