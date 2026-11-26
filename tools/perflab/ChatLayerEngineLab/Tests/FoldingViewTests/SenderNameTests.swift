import Cocoa
import XCTest
import TGUIKit
import SwiftSignalKit
@testable import ChatLayerEngine

final class SenderNameTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func layout(_ text: String = "Sender name", link: String? = nil, color: NSColor = .systemBlue) -> TextViewLayout {
        let text = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: color])
        if let link { text.addAttribute(.link, value: link, range: NSRange(location: 0, length: text.length)) }
        let layout = TextViewLayout(text, maximumNumberOfLines: 1)
        layout.mayItems = false
        layout.measure(width: 200)
        return layout
    }

    func attach(_ row: NSView) -> Window {
        let window = Window(contentRect: row.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = row
        row.layoutSubtreeIfNeeded()
        return window
    }

    func testActualBindingReusesLayerAndPreservesAccessoryAndEmptyTransitions() throws {
        let row = LayerSenderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let host = try XCTUnwrap(row.rowView as? ChatLayerRowView)
        let item = SenderBindingItem(layout(), toolTip: "Hidden sender")
        row.bind(item)
        let first = try XCTUnwrap(host.senderName)
        XCTAssertEqual(viewTreeCount(row), 4)
        XCTAssertEqual(first.toolTip, "Hidden sender")
        XCTAssertFalse(first.isSelectable)
        row.bind(SenderBindingItem(layout("Next sender")))
        XCTAssertTrue(host.senderName === first)
        XCTAssertNil(first.toolTip)
        row.layoutName(item, transition: .animated(duration: 0.2, curve: .easeOut))
        XCTAssertEqual(first.frame.origin, row.namePoint(item))
        item.hasBubble = false
        row.bind(item)
        XCTAssertNil(host.senderName)
        XCTAssertFalse(host.hasLayerContent)
        XCTAssertNotNil(row.viaAccessory)
        item.hasBubble = true
        row.bind(item)
        XCTAssertNotNil(host.senderName)
        XCTAssertNil(row.viaAccessory)
        row.bind(SenderBindingItem(nil))
        XCTAssertNil(host.senderName)
        XCTAssertFalse(host.hasLayerContent)
    }

    func testSenderPixelsMatchNativeAcrossLanguagesScalesAndBackgrounds() {
        for scale: CGFloat in [1, 2] {
            for text in ["Sender name", "اسم المرسل", "Sender 👩🏽‍💻 中文"] {
                for background in [NSColor.clear, .white, .darkGray] {
                    let native = NativeSenderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
                    let current = LayerSenderBindingRow(frame: native.frame)
                    native.bind(SenderBindingItem(layout(text)))
                    current.bind(SenderBindingItem(layout(text)))
                    native.updateNameBackground(background)
                    current.updateNameBackground(background)
                    native.bubbleView.backgroundColor = .systemGreen
                    current.bubbleView.backgroundColor = .systemGreen
                    let lhs = ViewSnapshot.render(native, scale: scale), rhs = ViewSnapshot.render(current, scale: scale)
                    if lhs.differingPixels(from: rhs, tolerance: 0) != 0 {
                        try? lhs.write(to: URL(fileURLWithPath: "/tmp/sender-native.png"))
                        try? rhs.write(to: URL(fileURLWithPath: "/tmp/sender-layer.png"))
                    }
                    XCTAssertEqual(lhs.differingPixels(from: rhs, tolerance: 0), 0, "scale=\(scale) text=\(text) background=\(background)")
                }
            }
        }
    }

    func testLayerLinksWinOverBubbleAndNativeControlsKeepPriority() throws {
        let row = LayerSenderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let text = layout(link: "first"), item = SenderBindingItem(text)
        var actions: [String] = []
        text.interactions.processURL = { actions.append($0 as! String) }
        row.bind(item)
        let window = attach(row)
        defer { window.contentView = nil; window.close() }
        let host = try XCTUnwrap(row.rowView as? ChatLayerRowView), node = try XCTUnwrap(host.senderName)
        let point = NSPoint(x: node.frame.minX + 5, y: node.frame.minY + 5)
        XCTAssertTrue(host.hitTest(host.convert(point, to: host.superview)) === host)
        XCTAssertTrue(host.handlePointer(.down, at: point))
        XCTAssertTrue(host.handlePointer(.up, at: point))
        XCTAssertEqual(actions, ["first"])
        let overlay = NSButton(title: "Native", target: nil, action: nil)
        overlay.frame = node.frame
        host.addSubview(overlay)
        XCTAssertTrue(host.hitTest(host.convert(point, to: host.superview)) === overlay)
        XCTAssertNil(host.hitNode(at: point))
        NSCursor.iBeam.set()
        host.updateHover(at: point)
        XCTAssertEqual(NSCursor.current, NSCursor.iBeam)
        TGUIKitAccessibility.isEnabled = true
        XCTAssertTrue(host.accessibilityHitTest(window.convertPoint(toScreen: host.convert(point, to: nil))) as AnyObject === overlay.cell)
        XCTAssertFalse(host.handlePointer(.down, at: point))
        overlay.isHidden = true
        XCTAssertTrue(host.hitNode(at: point) === node)
        XCTAssertNil(host.hitTest(NSPoint(x: 500, y: 300)))
        XCTAssertTrue(host.hitTest(NSPoint(x: 200, y: 40)) === row.bubbleView)
        row.bind(SenderBindingItem(layout(link: "second")))
        XCTAssertTrue(host.handlePointer(.down, at: point))
        row.bind(SenderBindingItem(layout(link: "third")))
        XCTAssertTrue(host.handlePointer(.up, at: point))
        XCTAssertEqual(actions, ["first"])
    }

    func testAnimatedRemovalReleasesSceneAndCannotRemoveReplacement() throws {
        let row = LayerSenderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let window = attach(row)
        defer { window.contentView = nil; window.close() }
        let host = try XCTUnwrap(row.rowView as? ChatLayerRowView)
        row.bind(SenderBindingItem(layout()))
        let old = try XCTUnwrap(host.senderName)
        row.bind(SenderBindingItem(nil), animated: true)
        XCTAssertNil(old.scene)
        XCTAssertNotNil(old.layer.superlayer)
        row.bind(SenderBindingItem(layout("Replacement")))
        let replacement = host.senderName
        CATransaction.flush()
        let done = expectation(description: "Fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertNil(old.layer.superlayer)
        XCTAssertTrue(host.senderName === replacement)
        row.bind(SenderBindingItem(nil), animated: true)
        CATransaction.flush()
        let empty = expectation(description: "Empty fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { empty.fulfill() }
        wait(for: [empty], timeout: 2)
        XCTAssertFalse(host.hasLayerContent)
    }

    func testActualShakeUsesBubblePivotAndRestoresLayerGeometry() throws {
        let row = LayerSenderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let window = attach(row)
        defer { window.contentView = nil; window.close() }
        let item = SenderBindingItem(layout())
        row.bind(item)
        let node = try XCTUnwrap((row.rowView as? ChatLayerRowView)?.senderName)
        let initial = node.frame
        row.shakeContentView()
        let bubbleAnimation = try XCTUnwrap(row.bubbleView.layer?.animation(forKey: "shake") as? CAAnimationGroup)
        XCTAssertEqual(bubbleAnimation.duration, 0.5)
        XCTAssertTrue(node.layer.superlayer === row.bubbleView.layer)
        XCTAssertEqual(row.bubbleView.convert(node.frame, to: row.rowView), initial)
        CATransaction.flush()
        let done = expectation(description: "Shake")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(node.layer.superlayer === node.scene?.root.layer)
        XCTAssertEqual(node.layer.anchorPoint, .zero)
        XCTAssertEqual(node.frame.origin.x, initial.origin.x, accuracy: 0.00000001)
        XCTAssertEqual(node.frame.origin.y, initial.origin.y, accuracy: 0.00000001)
        XCTAssertEqual(node.frame.size, initial.size)
        row.layoutName(item)
        XCTAssertEqual(node.frame.origin.x, initial.origin.x, accuracy: 0.00000001)
        XCTAssertEqual(node.frame.origin.y, initial.origin.y, accuracy: 0.00000001)
        XCTAssertEqual(node.frame.size, initial.size)
    }
}


extension SenderNameTests {
    func testPreviewDisposalRebindingPreservesNewestNameAndTooltip() throws {
        for remove in [false, true] {
            let row = LayerSenderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
            let window = attach(row)
            defer { window.contentView = nil; window.close() }
            let first = layout(link: "old"), newest = layout("Newest", link: "newest")
            let ready = expectation(description: "Preview")
            var disposals = 0
            first.interactions.longHoverOnLink = { _, _ in
                ready.fulfill()
                return ActionDisposable {
                    disposals += 1
                    row.bind(SenderBindingItem(newest, toolTip: "Newest tooltip"))
                }
            }
            row.bind(SenderBindingItem(first))
            let host = try XCTUnwrap(row.rowView as? ChatLayerRowView), node = try XCTUnwrap(host.senderName)
            _ = host.handlePointer(.moved, at: NSPoint(x: node.frame.minX + 5, y: node.frame.minY + 5))
            wait(for: [ready], timeout: 3)
            row.bind(SenderBindingItem(remove ? nil : layout("Superseded", link: "superseded"), toolTip: "Superseded tooltip"))
            XCTAssertEqual(disposals, 1)
            XCTAssertTrue(host.senderName?.textLayout === newest)
            XCTAssertEqual(host.senderName?.toolTip, "Newest tooltip")
            XCTAssertTrue(host.senderName?.scene === host)
        }
    }

    func testShakePixelsMatchTheNativeBubbleTransform() throws {
        for scale: CGFloat in [1, 2] {
            let native = NativeSenderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
            let current = LayerSenderBindingRow(frame: native.frame)
            native.bind(SenderBindingItem(layout("Sender 中文")))
            current.bind(SenderBindingItem(layout("Sender 中文")))
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
            let node = try XCTUnwrap((current.rowView as? ChatLayerRowView)?.senderName)
            for angle in [-0.5, 0.5] {
                let transform = CATransform3DMakeRotation(angle * .pi / 180, 0, 0, 1)
                native.bubbleView.layer?.transform = transform
                current.bubbleView.layer?.transform = transform
                let lhs = ViewSnapshot.render(native, scale: scale, keepingWindow: true), rhs = ViewSnapshot.render(current, scale: scale, keepingWindow: true)
                if lhs.differingPixels(from: rhs, tolerance: 2) != 0 {
                    try lhs.write(to: URL(fileURLWithPath: "/tmp/sender-shake-native.png"))
                    try rhs.write(to: URL(fileURLWithPath: "/tmp/sender-shake-layer.png"))
                }
                XCTAssertEqual(lhs.differingPixels(from: rhs, tolerance: 2), 0, "scale=\(scale) angle=\(angle)")
            }
            native.bubbleView.layer?.transform = CATransform3DIdentity
            current.bubbleView.layer?.transform = CATransform3DIdentity
            node.layer.transform = CATransform3DIdentity
            node.layer.removeAllAnimations()
        }
    }
}


extension SenderNameTests {
    func testShakeLayoutAndRemovalDoNotResurrectAnOldName() throws {
        let row = LayerSenderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let window = attach(row)
        defer { window.contentView = nil; window.close() }
        let item = SenderBindingItem(layout())
        row.bind(item)
        let host = try XCTUnwrap(row.rowView as? ChatLayerRowView), old = try XCTUnwrap(host.senderName)
        row.shakeContentView()
        host.layoutSenderName(origin: NSPoint(x: 40, y: 24), transition: .immediate)
        XCTAssertEqual(row.bubbleView.convert(old.frame, to: host).origin, NSPoint(x: 40, y: 24))
        row.bind(SenderBindingItem(nil))
        XCTAssertNil(old.layer.superlayer)
        row.bind(SenderBindingItem(layout("Replacement", link: "next")))
        let replacement = try XCTUnwrap(host.senderName)
        CATransaction.flush()
        let done = expectation(description: "Shake cleanup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(host.senderName === replacement)
        XCTAssertTrue(replacement.layer.superlayer === host.root.layer)
        XCTAssertEqual(replacement.frame.origin, row.namePoint(item))
        XCTAssertNil(old.layer.superlayer)
    }
}
