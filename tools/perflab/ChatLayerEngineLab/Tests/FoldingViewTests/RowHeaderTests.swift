import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class RowHeaderTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func layout(_ text: String, color: NSColor = .black) -> TextViewLayout {
        let layout = TextViewLayout(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color]), maximumNumberOfLines: 1)
        layout.measure(width: 220)
        return layout
    }

    func testLiveBindingUsesTheExistingRowHostAndReusesItsHeaderLayer() throws {
        let row = LayerHeaderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let host = try XCTUnwrap(row.rowView as? ChatLayerRowView)
        row.fillForwardHeader(HeaderBindingItem(nil, frame: .zero), animated: false)
        XCTAssertFalse(host.hasLayerContent)
        let first = layout("Forwarded message"), frame = NSRect(origin: NSPoint(x: 17, y: 9), size: first.layoutSize)
        row.fillForwardHeader(HeaderBindingItem(first, frame: frame), animated: false)
        let node = try XCTUnwrap(host.forwardHeader)
        XCTAssertEqual(viewTreeCount(row), 2)
        XCTAssertEqual(node.frame, frame)
        XCTAssertTrue(host.root.children.first === node)
        XCTAssertFalse(node.acceptsPointerEvents)
        XCTAssertFalse(node.acceptsKeyboardFocus)
        row.fillForwardHeader(HeaderBindingItem(layout("Updated forwarded message"), frame: frame.offsetBy(dx: 30, dy: 10)), animated: true)
        XCTAssertTrue(host.forwardHeader === node)
        XCTAssertEqual(node.frame.origin, frame.origin)
        XCTAssertEqual(node.accessibilityValue, "Updated forwarded message")
        row.layoutHeader(HeaderBindingItem(first, frame: frame.offsetBy(dx: 30, dy: 10)), transition: .animated(duration: 0.2, curve: .easeOut))
        XCTAssertEqual(node.frame.origin, NSPoint(x: frame.minX + 30, y: frame.minY + 10))
        XCTAssertNotNil(node.layer.animation(forKey: "position"))
    }

    func testHeaderRemovalCannotRemoveANewerHeaderWhenAnimationFinishes() throws {
        let row = LayerHeaderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let window = Window(contentRect: row.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = row
        defer { window.contentView = nil; window.close() }
        let host = try XCTUnwrap(row.rowView as? ChatLayerRowView), text = layout("Forwarded")
        let item = HeaderBindingItem(text, frame: NSRect(origin: NSPoint(x: 10, y: 8), size: text.layoutSize))
        row.fillForwardHeader(item, animated: false)
        let oldLayer = try XCTUnwrap(host.forwardHeader?.layer)
        row.fillForwardHeader(HeaderBindingItem(nil, frame: .zero), animated: true)
        XCTAssertNil(host.forwardHeader)
        XCTAssertTrue(host.root.children.isEmpty)
        XCTAssertTrue(oldLayer.superlayer === host.root.layer)
        XCTAssertNotNil(oldLayer.animation(forKey: "opacity"))
        row.fillForwardHeader(item, animated: true)
        let newest = try XCTUnwrap(host.forwardHeader)
        XCTAssertFalse(newest.layer === oldLayer)
        CATransaction.flush()
        let done = expectation(description: "Removal animation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertNil(oldLayer.superlayer)
        XCTAssertTrue(host.forwardHeader === newest)
        XCTAssertTrue(newest.layer.superlayer === host.root.layer)
        XCTAssertEqual(viewTreeCount(row), 2)
        row.fillForwardHeader(HeaderBindingItem(nil, frame: .zero), animated: false)
        XCTAssertNil(host.forwardHeader)
        XCTAssertNil(newest.scene)
        XCTAssertNil(newest.layer.superlayer)
        XCTAssertFalse(host.hasLayerContent)
    }

    func testNativeChildrenReceiveClicksAndKeepTheirHierarchy() throws {
        let host = ChatLayerRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let window = Window(contentRect: host.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        let button = NSButton(title: "Media action", target: nil, action: nil)
        button.frame = NSRect(x: 30, y: 50, width: 130, height: 30)
        host.addSubview(button)
        host.updateForwardHeader(layout("Forwarded message"), frame: NSRect(x: 10, y: 5, width: 200, height: 20), animated: false)
        XCTAssertTrue(host.hitTest(host.convert(NSPoint(x: 50, y: 60), to: host.superview)) === button)
        XCTAssertEqual(host.subviews.count, 1)
        XCTAssertTrue(button.superview === host)
        XCTAssertNil(host.hitNode(at: NSPoint(x: 15, y: 10)))
    }

    func testLiveHeaderPixelsMatchNativeAcrossScalesColorsAndLanguages() throws {
        for scale: CGFloat in [1, 2] {
            for text in ["Forwarded message", "رسالة معاد توجيهها", "Forwarded 👩🏽‍💻 中文"] {
                for color in [NSColor.black, .white, .systemBlue] {
                    let native = NativeHeaderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
                    let current = LayerHeaderBindingRow(frame: native.frame)
                    for rowView in [native.rowView, current.rowView] {
                        let background = View(frame: rowView.bounds)
                        background.backgroundColor = NSColor.darkGray
                        rowView.addSubview(background)
                    }
                    let left = layout(text, color: color), right = layout(text, color: color)
                    let frame = NSRect(origin: NSPoint(x: 14, y: 11), size: left.layoutSize)
                    native.fillForwardHeader(HeaderBindingItem(left, frame: frame), animated: false)
                    current.fillForwardHeader(HeaderBindingItem(right, frame: frame), animated: false)
                    let lhs = ViewSnapshot.render(native, scale: scale), rhs = ViewSnapshot.render(current, scale: scale)
                    if lhs.differingPixels(from: rhs, tolerance: 0) != 0 {
                        try lhs.write(to: URL(fileURLWithPath: "/tmp/chat-header-native.png"))
                        try rhs.write(to: URL(fileURLWithPath: "/tmp/chat-header-layers.png"))
                    }
                    XCTAssertEqual(lhs.differingPixels(from: rhs, tolerance: 0), 0, "scale=\(scale) text=\(text) color=\(color)")
                }
            }
        }
    }
}

extension RowHeaderTests {
    func testBadgeReuseRemovesOldActionsAndRestoresInteractionForTheNextAuthor() throws {
        let previous = BadgeBindingItem(layout("Admin"), authorId: 1), passive = BadgeBindingItem(layout("Channel"), authorId: nil), next = BadgeBindingItem(layout("Owner"), authorId: 2)
        let native = NativeBadgeBindingRow(), current = LayerBadgeBindingRow()
        native.bind(previous)
        native.bind(passive)
        native.adminBadge?.send(event: .Click)
        XCTAssertEqual(previous.actions, 1)
        current.bind(previous)
        let badge = try XCTUnwrap(current.adminBadge)
        badge.send(event: .Click)
        XCTAssertEqual(previous.actions, 2)
        badge.controlState = .Highlight
        current.bind(passive)
        XCTAssertTrue(current.adminBadge === badge)
        XCTAssertFalse(badge.scaleOnClick)
        XCTAssertFalse(badge.userInteractionEnabled)
        XCTAssertEqual(badge.controlState, .Normal)
        badge.send(event: .Click)
        XCTAssertEqual(previous.actions, 2)
        XCTAssertEqual(passive.actions, 0)
        current.bind(next)
        XCTAssertTrue(current.adminBadge === badge)
        XCTAssertTrue(badge.scaleOnClick)
        XCTAssertTrue(badge.userInteractionEnabled)
        badge.send(event: .Click)
        XCTAssertEqual(next.actions, 1)
        XCTAssertEqual(previous.actions, 2)
    }

    func testUnattachedHeaderRemovalDoesNotRetainFadingLayers() throws {
        let host = ChatLayerRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        host.updateForwardHeader(layout("Forwarded"), frame: NSRect(x: 10, y: 5, width: 100, height: 20), animated: false)
        let layer = try XCTUnwrap(host.forwardHeader?.layer)
        host.updateForwardHeader(nil, frame: .zero, animated: true)
        XCTAssertNil(layer.superlayer)
        XCTAssertFalse(host.hasLayerContent)
    }
}

extension RowHeaderTests {
    func testSnapshotUsesLayerDepthAndRestoresOriginalSiblingOrder() {
        let native = View(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        native.backgroundColor = .red
        let current = View(frame: native.frame)
        let front = SimpleLayer(), back = SimpleLayer()
        front.frame = current.bounds
        front.backgroundColor = NSColor.red.cgColor
        front.zPosition = 1
        back.frame = current.bounds
        back.backgroundColor = NSColor.blue.cgColor
        current.layer?.addSublayer(front)
        current.layer?.addSublayer(back)
        let lhs = ViewSnapshot.render(native), rhs = ViewSnapshot.render(current)
        XCTAssertEqual(lhs.differingPixels(from: rhs, tolerance: 0), 0)
        XCTAssertTrue(current.layer?.sublayers?.first === front)
        XCTAssertTrue(current.layer?.sublayers?.last === back)
    }
}
