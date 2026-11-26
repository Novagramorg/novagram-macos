import Cocoa
import XCTest
import TGUIKit
import SwiftSignalKit
@testable import ChatLayerEngine

final class ForwardNameTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install(); forwardTooltipCapture = nil }

    func layout(_ text: String = "Forwarded from Alice", link: String? = nil) -> TextViewLayout {
        let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.systemBlue])
        if let link { value.addAttribute(.link, value: link, range: NSRange(location: 0, length: value.length)) }
        let layout = TextViewLayout(value, maximumNumberOfLines: 2, truncationType: .end, alwaysStaticItems: true)
        layout.mayItems = false
        layout.measure(width: 230)
        return layout
    }

    func attach(_ view: NSView) -> Window {
        let window = Window(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        return window
    }

    func testActualBindingReusesTextAndAvatarAndPreservesAccessoryTransitions() throws {
        let row = LayerForwardBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let host = try XCTUnwrap(row.rowView as? ChatLayerRowView)
        let first = ForwardBindingItem(layout(), photo: true)
        row.bind(first)
        let node = try XCTUnwrap(host.forwardName), avatar = try XCTUnwrap(row.forwardPhoto)
        XCTAssertEqual(viewTreeCount(row), 5)
        XCTAssertFalse(node.isSelectable)
        avatar.send(event: .Click)
        XCTAssertEqual(first.actions, 1)
        let second = ForwardBindingItem(layout("Forwarded from Bob"), photo: true)
        second.message = ForwardBindingMessage(forwardInfo: ForwardBindingInfo(author: 73))
        row.bind(second)
        XCTAssertTrue(host.forwardName === node)
        XCTAssertTrue(row.forwardPhoto === avatar)
        XCTAssertEqual(avatar.peer, 73)
        avatar.send(event: .Click)
        XCTAssertEqual(second.actions, 1)
        XCTAssertEqual(first.actions, 1)
        second.hasBubble = false
        row.bind(second)
        XCTAssertNil(host.forwardName)
        XCTAssertNil(row.forwardPhoto)
        XCTAssertNotNil(row.forwardAccessory)
        XCTAssertFalse(host.hasLayerContent)
        second.hasBubble = true
        row.bind(second)
        XCTAssertNil(row.forwardAccessory)
        XCTAssertNotNil(host.forwardName)
        row.bind(ForwardBindingItem(nil))
        XCTAssertNil(host.forwardName)
        XCTAssertNil(row.forwardPhoto)
        XCTAssertFalse(host.hasLayerContent)
    }

    func testTextAndAvatarPixelsMatchNativeAcrossLanguagesScalesAndBackgrounds() {
        for scale: CGFloat in [1, 2] {
            for text in ["Forwarded from Alice", "تمت إعادة التوجيه من المستخدم", "Forwarded 👩🏽‍💻 中文 from a very long sender name"] {
                for background in [NSColor.clear, .white, .darkGray] {
                    for photo in [false, true] {
                        let native = NativeForwardBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
                        let current = LayerForwardBindingRow(frame: native.frame)
                        native.bind(ForwardBindingItem(layout(text), photo: photo))
                        current.bind(ForwardBindingItem(layout(text), photo: photo))
                        native.updateNameBackground(background)
                        current.updateNameBackground(background)
                        native.bubbleView.backgroundColor = .systemGreen
                        current.bubbleView.backgroundColor = .systemGreen
                        let lhs = ViewSnapshot.render(native, scale: scale), rhs = ViewSnapshot.render(current, scale: scale)
                        if lhs.differingPixels(from: rhs, tolerance: 0) != 0 {
                            try? lhs.write(to: URL(fileURLWithPath: "/tmp/forward-native.png"))
                            try? rhs.write(to: URL(fileURLWithPath: "/tmp/forward-layer.png"))
                        }
                        XCTAssertEqual(lhs.differingPixels(from: rhs, tolerance: 0), 0, "scale=\(scale) text=\(text) background=\(background) photo=\(photo)")
                    }
                }
            }
        }
    }

    func testForwardLinksAndNativeAvatarKeepTheirOwnActionsAcrossReuse() throws {
        let row = LayerForwardBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let window = attach(row)
        defer { window.contentView = nil; window.close() }
        let text = layout(link: "first"), item = ForwardBindingItem(text, photo: true)
        var actions: [String] = []
        text.interactions.processURL = { actions.append($0 as! String) }
        row.bind(item)
        let host = try XCTUnwrap(row.rowView as? ChatLayerRowView), node = try XCTUnwrap(host.forwardName)
        let point = NSPoint(x: node.frame.minX + 3, y: node.frame.minY + 5)
        XCTAssertTrue(host.handlePointer(.down, at: point))
        XCTAssertTrue(host.handlePointer(.up, at: point))
        XCTAssertEqual(actions, ["first"])
        let avatar = try XCTUnwrap(row.forwardPhoto), avatarPoint = NSPoint(x: avatar.frame.midX, y: avatar.frame.midY)
        XCTAssertNil(host.hitNode(at: avatarPoint))
        XCTAssertTrue(host.hitTest(host.convert(avatarPoint, to: host.superview)) === avatar)
        avatar.send(event: .Click)
        XCTAssertEqual(item.actions, 1)
        XCTAssertTrue(host.handlePointer(.down, at: point))
        row.bind(ForwardBindingItem(layout(link: "next")))
        XCTAssertTrue(host.handlePointer(.up, at: point))
        XCTAssertEqual(actions, ["first"])
    }

    func testHiddenForwardTooltipUsesTheNativeAnchorAndClearsWithContent() throws {
        let native = NativeForwardBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let current = LayerForwardBindingRow(frame: native.frame)
        let windows = [native, current].map(attach)
        defer { windows.forEach { $0.contentView = nil; $0.close() } }
        native.bind(ForwardBindingItem(layout()))
        current.bind(ForwardBindingItem(layout()))
        native.showHiddenForwardTooltip()
        let old = try XCTUnwrap(forwardTooltipCapture), oldView = try XCTUnwrap(old.view)
        let expected = oldView.convert(old.rect, to: native.rowView)
        current.showHiddenForwardTooltip()
        let capture = try XCTUnwrap(forwardTooltipCapture)
        XCTAssertTrue(capture.view === current.rowView)
        XCTAssertEqual(capture.rect, expected)
        XCTAssertEqual(capture.text, old.text)
        XCTAssertFalse(capture.autoCorner)
        current.bind(ForwardBindingItem(nil))
        forwardTooltipCapture = nil
        current.showHiddenForwardTooltip()
        XCTAssertNil(forwardTooltipCapture)
    }

    func testRemovingForwardNameKeepsSenderAndHeaderNodes() throws {
        let host = ChatLayerRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        host.updateSenderName(layout("Sender"), toolTip: nil, frame: NSRect(x: 10, y: 10, width: 100, height: 20), animated: false)
        host.updateForwardHeader(layout("Header"), frame: NSRect(x: 10, y: 30, width: 100, height: 20), animated: false)
        host.updateForwardName(layout(), frame: NSRect(x: 10, y: 50, width: 230, height: 20), animated: false)
        let sender = host.senderName, header = host.forwardHeader
        host.updateForwardName(nil, frame: .zero, animated: true)
        XCTAssertTrue(host.senderName === sender)
        XCTAssertTrue(host.forwardHeader === header)
        XCTAssertEqual(host.root.children.count, 2)
        host.updateSenderName(nil, toolTip: nil, frame: .zero, animated: false)
        host.updateForwardHeader(nil, frame: .zero, animated: false)
        XCTAssertFalse(host.hasLayerContent)
    }

    func testPreviewDisposalCannotOverwriteNewerForwardNameOrAvatar() throws {
        for mode in 0..<3 {
            let row = LayerForwardBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
            let window = attach(row)
            defer { window.contentView = nil; window.close() }
            let old = layout(link: "old"), newest = ForwardBindingItem(layout("Newest", link: "newest"), photo: true)
            let ready = expectation(description: "Preview")
            old.interactions.longHoverOnLink = { _, _ in
                ready.fulfill()
                return ActionDisposable { row.bind(newest) }
            }
            row.bind(ForwardBindingItem(old))
            let host = try XCTUnwrap(row.rowView as? ChatLayerRowView), node = try XCTUnwrap(host.forwardName)
            _ = host.handlePointer(.moved, at: NSPoint(x: node.frame.minX + 3, y: node.frame.minY + 5))
            wait(for: [ready], timeout: 3)
            let superseded = ForwardBindingItem(mode == 0 ? nil : layout("Superseded", link: "superseded"))
            superseded.hasBubble = mode != 1
            row.bind(superseded)
            XCTAssertTrue(host.forwardName?.textLayout === newest.forwardNameLayout, "mode=\(mode)")
            XCTAssertNotNil(row.forwardPhoto, "mode=\(mode)")
            XCTAssertNil(row.forwardAccessory, "mode=\(mode)")
            XCTAssertTrue(host.forwardName?.scene === host)
        }
    }
}

extension ForwardNameTests {
    func testAnimatedRemovalKeepsReplacementAndReleasesTheFinalScene() throws {
        let row = LayerForwardBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let window = attach(row)
        defer { window.contentView = nil; window.close() }
        let host = try XCTUnwrap(row.rowView as? ChatLayerRowView)
        row.bind(ForwardBindingItem(layout()))
        let old = try XCTUnwrap(host.forwardName)
        row.bind(ForwardBindingItem(nil), animated: true)
        XCTAssertNil(old.scene)
        XCTAssertNotNil(old.layer.superlayer)
        row.bind(ForwardBindingItem(layout("Replacement")))
        let replacement = host.forwardName
        CATransaction.flush()
        let done = expectation(description: "Replacement fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertNil(old.layer.superlayer)
        XCTAssertTrue(host.forwardName === replacement)
        row.bind(ForwardBindingItem(nil), animated: true)
        CATransaction.flush()
        let empty = expectation(description: "Final fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { empty.fulfill() }
        wait(for: [empty], timeout: 2)
        XCTAssertFalse(host.hasLayerContent)
    }

    func testShakePixelsWithAvatarMatchNative() throws {
        for scale: CGFloat in [1, 2] {
            let native = NativeForwardBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
            let current = LayerForwardBindingRow(frame: native.frame)
            native.bind(ForwardBindingItem(layout("Forwarded 中文"), photo: true))
            current.bind(ForwardBindingItem(layout("Forwarded 中文"), photo: true))
            native.updateNameBackground(.white)
            current.updateNameBackground(.white)
            native.bubbleView.backgroundColor = .systemGreen
            current.bubbleView.backgroundColor = .systemGreen
            let windows = [native, current].map { row -> SnapshotWindow in
                let window = SnapshotWindow(contentRect: row.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.scale = scale
                window.contentView = row
                row.layoutSubtreeIfNeeded()
                return window
            }
            defer { windows.forEach { $0.contentView = nil; $0.close() } }
            native.shakeContentView()
            current.shakeContentView()
            let node = try XCTUnwrap((current.rowView as? ChatLayerRowView)?.forwardName)
            XCTAssertTrue(node.layer.superlayer === current.bubbleView.layer)
            for angle in [-0.5, 0.5] {
                let transform = CATransform3DMakeRotation(angle * .pi / 180, 0, 0, 1)
                native.bubbleView.layer?.transform = transform
                current.bubbleView.layer?.transform = transform
                let lhs = ViewSnapshot.render(native, scale: scale, keepingWindow: true), rhs = ViewSnapshot.render(current, scale: scale, keepingWindow: true)
                XCTAssertEqual(lhs.differingPixels(from: rhs, tolerance: 2), 0, "scale=\(scale) angle=\(angle)")
            }
            native.bubbleView.layer?.transform = CATransform3DIdentity
            current.bubbleView.layer?.transform = CATransform3DIdentity
        }
    }

    func testShakeRebindingAndTooltipGeometryPreserveTheCurrentNames() throws {
        let row = LayerForwardBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let window = attach(row)
        defer { window.contentView = nil; window.close() }
        row.bind(ForwardBindingItem(layout()))
        let host = try XCTUnwrap(row.rowView as? ChatLayerRowView), old = try XCTUnwrap(host.forwardName)
        host.updateSenderName(layout("Sender"), toolTip: nil, frame: NSRect(x: 25, y: 2, width: 100, height: 20), animated: false)
        let sender = try XCTUnwrap(host.senderName)
        row.shakeContentView()
        XCTAssertTrue(old.layer.superlayer === row.bubbleView.layer)
        XCTAssertTrue(sender.layer.superlayer === row.bubbleView.layer)
        host.layoutForwardName(origin: NSPoint(x: 40, y: 24), transition: .immediate)
        row.showHiddenForwardTooltip()
        let rect = try XCTUnwrap(forwardTooltipCapture?.rect)
        XCTAssertEqual(rect.origin.x, 40, accuracy: 0.000001)
        XCTAssertEqual(rect.origin.y, 24, accuracy: 0.000001)
        row.bind(ForwardBindingItem(nil))
        row.bind(ForwardBindingItem(layout("Replacement", link: "next")))
        let replacement = try XCTUnwrap(host.forwardName)
        CATransaction.flush()
        let done = expectation(description: "Shake cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(host.forwardName === replacement)
        XCTAssertTrue(replacement.layer.superlayer === host.root.layer)
        XCTAssertTrue(sender.layer.superlayer === host.root.layer)
        XCTAssertNil(old.layer.superlayer)
        XCTAssertEqual(replacement.frame.origin, NSPoint(x: 25, y: 20))
    }
}

extension ForwardNameTests {
    func testRemovingForwardNameDismissesOnlyItsOwnVisibleTooltip() throws {
        for own in [false, true] {
            let row = LayerForwardBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
            let window = attach(row)
            defer { window.contentView = nil; window.close() }
            row.bind(ForwardBindingItem(layout()))
            let host = try XCTUnwrap(row.rowView as? ChatLayerRowView)
            let other = View(frame: NSRect(x: 200, y: 80, width: 30, height: 20))
            row.addSubview(other)
            let previous = Set(row.subviews.map(ObjectIdentifier.init))
            tooltip(for: own ? host : other, text: "Hidden sender", autoCorner: false, timeout: 10, rect: host.forwardNameFrame)
            let tooltipView = try XCTUnwrap(row.subviews.first { !previous.contains(ObjectIdentifier($0)) })
            row.bind(ForwardBindingItem(nil))
            CATransaction.flush()
            let done = expectation(description: "Tooltip dismissal")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
            wait(for: [done], timeout: 2)
            XCTAssertEqual(tooltipView.superview == nil, own)
            if !own { dismissTooltip(for: other) }
        }
    }
}
