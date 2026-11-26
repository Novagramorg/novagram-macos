import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

private final class TestWindow: Window {
    var scale: CGFloat = 2
    var key = false
    override var backingScaleFactor: CGFloat { scale }
    override var isKeyWindow: Bool { key }
}

final class TextTests: XCTestCase {
    override func setUp() {
        TGUIKitTestBootstrap.install()
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
    }
    override func tearDown() { System.updateScaleFactor(2) }
    func layout(_ string: String, width: CGFloat = 230, alignment: NSTextAlignment = .left) -> TextViewLayout {
        let text = NSMutableAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        if string.hasPrefix("Link") { text.addAttribute(.link, value: "https://example.org", range: NSRange(location: 0, length: 4)) }
        let value = TextViewLayout(text, alignment: alignment, selectText: NSColor.blue.withAlphaComponent(0.3))
        value.measure(width: width)
        return value
    }
    func pixels(_ scale: CGFloat, _ draw: (CGContext) -> Void) -> Data {
        let context = CGContext(data: nil, width: 900, height: 600, bitsPerComponent: 8, bytesPerRow: 3600, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 8, y: 8)
        draw(context)
        return Data(bytes: context.data!, count: 900 * 600 * 4)
    }
    func mouse(_ type: NSEvent.EventType, _ point: NSPoint, in view: NSView, clicks: Int = 1, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: modifiers, timestamp: 1, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!
    }
    func testSelectionPixelsAcrossScalesLanguagesAlignmentAndWindowState() throws {
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let view = TextView(), node = ChatLayerTextNode(id: "body", selectable: true)
        view.disableBackgroundDrawing = true
        window.contentView = view
        var comparisons = 0
        for scale in [CGFloat(1), 2, 3] {
            window.scale = scale
            System.updateScaleFactor(scale)
            node.updateOwnScale(scale)
            for text in ["A simple message\nSecond line", "مرحبا English שלום", "👩🏽‍💻 🦆 café ffi", "Link and the rest of the message", "中文 日本語 한글"] {
                for alignment in [NSTextAlignment.left, .center, .right] {
                    for key in [false, true] {
                        window.key = key
                        for range in [NSRange(location: NSNotFound, length: 0), NSRange(location: 0, length: 3), NSRange(location: 3, length: 5)] {
                            let old = layout(text, alignment: alignment), new = layout(text, alignment: alignment)
                            for value in [old, new] {
                                value.selectedRange.range = range
                                value.additionalSelections = [TextSelectedRange(range: NSRange(location: 1, length: 2), color: .yellow)]
                            }
                            view.update(nil); view.update(old); view.layout()
                            node.update(new, size: view.frame.size)
                            node.drawingLayer.isKeyWindow = key
                            XCTAssertEqual(node.drawingLayer.bounds, view.drawingLayer.bounds)
                            let a = pixels(scale) { view.draw(view.drawingLayer, in: $0) }
                            let b = pixels(scale) { node.drawingLayer.draw(in: $0) }
                            XCTAssertEqual(a, b, "\(text), \(scale), \(alignment), \(range), \(key)")
                            XCTAssertTrue(a.contains { $0 != 0 })
                            comparisons += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 270)
    }
    func testNativeAndLayerSelectionGestures() throws {
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let host = View(frame: window.contentView!.bounds)
        let native = TextView(), scene = ChatLayerSceneView(frame: host.bounds), node = ChatLayerTextNode(id: "text", selectable: true)
        window.contentView = host
        host.addSubview(native); host.addSubview(scene)
        scene.layout()
        try scene.root.setChildren([node])
        for text in ["One two three four\nFive six seven eight", "مرحبا English שלום", "👩🏽‍💻 🦆 café ffi", "中文 日本語 한글"] {
            for clicks in [1, 2, 3] {
                for reversed in [false, true] {
                    for drag in [false, true] {
                        let a = layout(text), b = layout(text)
                        native.update(nil); native.update(a); native.layout(); node.update(b)
                        let start = NSPoint(x: reversed ? 90 : 8, y: 6), end = NSPoint(x: reversed ? 8 : 90, y: 6)
                        let down = mouse(.leftMouseDown, start, in: native, clicks: clicks)
                        native.mouseDown(with: down)
                        if drag {
                            let event = mouse(.leftMouseDragged, end, in: native, clicks: clicks)
                            native.mouseDragged(with: event)
                        }
                        let point = drag ? end : start
                        let up = mouse(.leftMouseUp, point, in: native, clicks: clicks)
                        native.mouseUp(with: up)
                        let expected = a.selectedRange.range
                        _ = scene.handlePointer(.down, at: start, native: down)
                        if drag { _ = scene.handlePointer(.dragged, at: end, native: mouse(.leftMouseDragged, end, in: native, clicks: clicks)) }
                        _ = scene.handlePointer(.up, at: point, native: up)
                        XCTAssertEqual(expected, b.selectedRange.range, "\(text), \(clicks), \(reversed), \(drag)")
                    }
                }
            }
        }
    }
    func testLinkRequiresMatchingPressAndReleaseAndNoDrag() throws {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        scene.layout()
        let node = ChatLayerTextNode(id: "text", selectable: true), value = layout("Link and other text")
        var opens = 0
        value.interactions.processURL = { _ in opens += 1 }
        node.update(value); try scene.root.setChildren([node])
        _ = scene.handlePointer(.down, at: NSPoint(x: 8, y: 6))
        _ = scene.handlePointer(.up, at: NSPoint(x: 8, y: 6))
        XCTAssertEqual(opens, 1)
        _ = scene.handlePointer(.down, at: NSPoint(x: 80, y: 6))
        _ = scene.handlePointer(.up, at: NSPoint(x: 8, y: 6))
        _ = scene.handlePointer(.down, at: NSPoint(x: 8, y: 6))
        _ = scene.handlePointer(.dragged, at: NSPoint(x: 20, y: 6))
        _ = scene.handlePointer(.up, at: NSPoint(x: 8, y: 6))
        XCTAssertEqual(opens, 1)
    }
    func testCopyKeyboardSelectionAndLayoutReplacement() throws {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let node = ChatLayerTextNode(id: "text", selectable: true)
        node.update(layout("copy me 🦆")); try scene.root.setChildren([node])
        scene.focus(node)
        var copied = ""
        node.copyText = { copied = $0.string }
        scene.selectAll(nil); scene.copy(nil)
        XCTAssertEqual(copied, "copy me 🦆")
        node.textLayout!.mayItems = false
        node.setSelection(NSRange(location: 0, length: 4))
        scene.copy(nil)
        XCTAssertEqual(copied, "copy me 🦆")
        weak var released = node.textLayout
        node.update(layout("replacement"))
        XCTAssertNil(released)
        node.setSelection(NSRange(location: Int.max - 1, length: Int.max))
        XCTAssertEqual(node.textLayout!.selectedRange.range, NSRange(location: 11, length: 0))
        node.update(nil)
        XCTAssertNil(node.accessibilityValue)
        XCTAssertEqual(node.frame.size, .zero)
    }
    func testLayerCopyAndSelectionInvalidation() {
        let node = ChatLayerTextNode(id: "text", selectable: true)
        node.update(layout("selected text"))
        node.drawingLayer.isKeyWindow = true
        let copy = TextViewLayer(layer: node.drawingLayer)
        XCTAssertTrue(copy.isTextSelectable)
        XCTAssertTrue(copy.isKeyWindow)
        node.drawingLayer.display()
        node.drawingLayer.isKeyWindow = false
        XCTAssertFalse(node.drawingLayer.needsDisplay())
        node.setSelection(NSRange(location: 0, length: 4))
        node.drawingLayer.display()
        node.drawingLayer.isKeyWindow = true
        XCTAssertTrue(node.drawingLayer.needsDisplay())
    }
}
