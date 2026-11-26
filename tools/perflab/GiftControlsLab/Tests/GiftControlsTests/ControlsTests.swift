import XCTest
import Cocoa
import TGUIKit
@testable import GiftControls

final class ControlsTests: XCTestCase {
    override func setUp() { initializeLab() }

    func testActionGlassReuseTintAndResize() {
        let view = ActionView(frame: NSMakeRect(0, 0, 100, 60))
        let item = HeaderItem.ActionItem()
        view.set(item: item, tintColor: .red, useGlass: true)
        view.layout()
        let glass = view.subviews.compactMap { $0 as? LiquidGlassView }.first!
        XCTAssertTrue(view.subviews.first === glass)
        XCTAssertFalse(view.layer!.masksToBounds)
        XCTAssertEqual(glass.customTint, .red)
        XCTAssertEqual(glass.frame, view.bounds)
        XCTAssertTrue(view.stretchReferenceView === glass)
        for _ in 0..<100 { view.set(item: item, tintColor: .white, useGlass: true) }
        view.setFrameSize(NSMakeSize(160, 80))
        view.layout()
        XCTAssertEqual(view.subviews.compactMap { $0 as? LiquidGlassView }.count, 1)
        XCTAssertTrue(view.subviews.contains { $0 === glass })
        XCTAssertEqual(glass.customTint, .white)
        XCTAssertEqual(glass.frame, view.bounds)
    }

    func testActionFallbackRemovesGlassAndKeepsSingleLatestHandler() {
        let view = ActionView(frame: NSMakeRect(0, 0, 100, 60))
        let old = HeaderItem.ActionItem()
        var oldCalls = 0
        old.action = { oldCalls += 1 }
        view.set(item: old, tintColor: .red, useGlass: true)
        let item = HeaderItem.ActionItem()
        var calls = 0
        item.action = { calls += 1 }
        for _ in 0..<10 { view.set(item: item, tintColor: .white, useGlass: false) }
        view.send(event: .Click)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(oldCalls, 0)
        XCTAssertNil(view.stretchReferenceView)
        XCTAssertFalse(view.subviews.contains { $0 is LiquidGlassView })
        XCTAssertEqual(view.layer?.cornerRadius, 20)
        view.set(item: item, tintColor: .red, useGlass: true)
        XCTAssertEqual(view.subviews.compactMap { $0 as? LiquidGlassView }.count, 1)
    }

    func testQrWrapperKeepsShadowUnclippedAcrossReuse() {
        let view = QrStudioGlassButtonView(frame: NSMakeRect(0, 0, 40, 40))
        var calls = 0
        view.action = { _ in calls += 1 }
        for color in [NSColor.red, .white, .blue] {
            view.update(size: view.frame.size, appearance: QrStudioGlassAppearance(tintColor: color), icon: nil, reveal: nil, transition: .immediate)
            XCTAssertFalse(view.layer!.masksToBounds)
            XCTAssertEqual(view.subviews.count, 1)
            XCTAssertFalse(view.subviews[0].layer!.masksToBounds)
        }
        view.send(event: .Click)
        XCTAssertEqual(calls, 1)
    }

    func testNativeGlassReuse() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native glass requires macOS 26") }
        System.liquidGlass = true
        defer { System.liquidGlass = false }
        testActionGlassReuseTintAndResize()
        testQrWrapperKeepsShadowUnclippedAcrossReuse()
    }
    func testLabelsStayAboveGlassAndRender() throws {
        System.liquidGlass = true
        defer { System.liquidGlass = false }
        let root = View(frame: NSMakeRect(0, 0, 400, 120))
        root.backgroundColor = NSColor(srgbRed: 0.2, green: 0.6, blue: 0.3, alpha: 1)
        let window = NSWindow(contentRect: root.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = root
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for (index, title) in ["Transfer", "Wear", "Sell"].enumerated() {
            let view = ActionView(frame: NSMakeRect(CGFloat(index) * 125 + 15, 25, 115, 60))
            root.addSubview(view)
            let item = HeaderItem.ActionItem(title)
            view.set(item: item, tintColor: root.backgroundColor, useGlass: true)
            view.layoutSubtreeIfNeeded()
            let text = try XCTUnwrap(view.subviews.compactMap { $0 as? InteractiveTextView }.first)
            XCTAssertTrue(view.subviews.first is LiquidGlassView)
            XCTAssertGreaterThan(text.frame.height, 10)
            XCTAssertTrue(view.bounds.contains(text.frame))
            XCTAssertEqual(text.textView.textLayout?.attributedString.string, title)
            text.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(text.textView.bitmapImageRepForCachingDisplay(in: text.textView.bounds))
            text.textView.cacheDisplay(in: text.textView.bounds, to: bitmap)
            var visiblePixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.5 { visiblePixels += 1 }
                }
            }
            XCTAssertGreaterThan(visiblePixels, 20)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/gift-label-\(title).png"))
        }

    }

}
