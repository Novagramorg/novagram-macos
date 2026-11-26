import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class AdminBadgeNodeTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func layout(_ text: String = "Sender", color: NSColor = .systemBlue, size: CGFloat = 13) -> TextViewLayout {
        let layout = TextViewLayout(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color]), maximumNumberOfLines: 1)
        layout.mayItems = false
        layout.measure(width: .greatestFiniteMagnitude)
        return layout
    }

    func item(rank: Bool, interactive: Bool) -> SenderBindingItem {
        let item = SenderBindingItem(layout())
        item.adminBadge = layout(" admin", color: .systemGreen, size: 12)
        item.adminBadgeIsRank = rank
        item.adminBadgeColor = rank ? .systemGreen : nil
        item.adminBadgeAuthorId = interactive ? 7 : nil
        return item
    }

    func attach(_ row: NSView) -> Window {
        let window = Window(contentRect: row.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = row
        row.layoutSubtreeIfNeeded()
        return window
    }

    func testNodeBadgeReplacesTextViewsAndKeepsGeometry() throws {
        let row = LayerSenderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        row.badgeNodes = true
        let host = try XCTUnwrap(row.rowView as? ChatLayerRowView)
        let item = item(rank: true, interactive: true)
        row.bind(item)
        XCTAssertNil(row.adminBadge)
        XCTAssertNil(row.adminBadgeBg)
        let node = try XCTUnwrap(host.adminBadgeNode)
        XCTAssertEqual(node.frame, NSRect(origin: row.adminBadgePoint(item), size: try XCTUnwrap(item.adminBadge).layoutSize))
        let children = host.root.children
        let background = try XCTUnwrap(children.first { $0.id == AnyHashable("admin-badge-background") })
        XCTAssertLessThan(try XCTUnwrap(children.firstIndex { $0 === background }), try XCTUnwrap(children.firstIndex { $0 === node }))
        XCTAssertEqual(background.frame, row.adminBadgeBgRect(item))
        XCTAssertEqual(background.layer.cornerRadius, row.adminBadgeBgRect(item).height / 2)
        XCTAssertTrue(node.scaleOnClick)
        XCTAssertTrue(node.userInteractionEnabled)
        row.bind(item)
        XCTAssertTrue(host.adminBadgeNode === node)
        XCTAssertEqual(host.root.children.filter { $0.id == AnyHashable("admin-badge-background") }.count, 1)
        let plain = self.item(rank: false, interactive: false)
        row.bind(plain)
        XCTAssertTrue(host.adminBadgeNode === node)
        XCTAssertNil(host.root.children.first { $0.id == AnyHashable("admin-badge-background") })
        XCTAssertFalse(node.scaleOnClick)
        XCTAssertFalse(node.userInteractionEnabled)
        row.bind(SenderBindingItem(layout()))
        XCTAssertNil(host.adminBadgeNode)
        XCTAssertNil(host.root.children.first { ($0.id as? String)?.hasPrefix("admin-badge") == true })
    }

    func testNodeBadgeClickHitTestAndShake() throws {
        let row = LayerSenderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        row.badgeNodes = true
        let window = attach(row)
        defer { window.contentView = nil; window.close() }
        let host = try XCTUnwrap(row.rowView as? ChatLayerRowView)
        let item = item(rank: true, interactive: true)
        row.bind(item)
        let node = try XCTUnwrap(host.adminBadgeNode)
        let center = NSPoint(x: node.frame.midX, y: node.frame.midY)
        XCTAssertTrue(host.hitNode(at: center).map { $0 === node || $0.parent === node } == true)
        XCTAssertTrue(row.hitTest(host.convert(center, to: row.superview)) === host)
        node.send(event: .Click)
        XCTAssertEqual(item.badgeActions.count, 1)
        XCTAssertTrue(item.badgeActions.first === row.rowView)
        let initial = node.frame
        row.shakeContentView()
        XCTAssertTrue(node.layer.superlayer === row.bubbleView.layer)
        XCTAssertEqual(row.bubbleView.convert(node.frame, to: host), initial)
        CATransaction.flush()
        let done = expectation(description: "Shake")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { done.fulfill() }
        wait(for: [done], timeout: 2)
        XCTAssertTrue(node.layer.superlayer === host.root.layer)
        XCTAssertEqual(node.frame.origin.x, initial.origin.x, accuracy: 0.00000001)
        XCTAssertEqual(node.frame.origin.y, initial.origin.y, accuracy: 0.00000001)
        let plain = self.item(rank: false, interactive: false)
        row.bind(plain)
        node.send(event: .Click)
        XCTAssertEqual(item.badgeActions.count, 1)
        XCTAssertTrue(plain.badgeActions.isEmpty)
    }

    func testNodeBadgePixelsMatchTextView() {
        for scale: CGFloat in [1, 2] {
            for rank in [true, false] {
                for text in [" admin", " مشرف", " 管理员 👩🏽‍💻"] {
                    let native = LayerSenderBindingRow(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
                    let current = LayerSenderBindingRow(frame: native.frame)
                    current.badgeNodes = true
                    let lhsItem = item(rank: rank, interactive: true), rhsItem = item(rank: rank, interactive: true)
                    lhsItem.adminBadge = layout(text, color: .systemGreen, size: 12)
                    rhsItem.adminBadge = layout(text, color: .systemGreen, size: 12)
                    native.bind(lhsItem)
                    current.bind(rhsItem)
                    native.bubbleView.backgroundColor = .darkGray
                    current.bubbleView.backgroundColor = .darkGray
                    XCTAssertNotNil(native.adminBadge)
                    XCTAssertNotNil((current.rowView as? ChatLayerRowView)?.adminBadgeNode)
                    let lhs = ViewSnapshot.render(native, scale: scale), rhs = ViewSnapshot.render(current, scale: scale)
                    if lhs.differingPixels(from: rhs, tolerance: 0) != 0 {
                        try? lhs.write(to: URL(fileURLWithPath: "/tmp/badge-native.png"))
                        try? rhs.write(to: URL(fileURLWithPath: "/tmp/badge-layer.png"))
                    }
                    XCTAssertEqual(lhs.differingPixels(from: rhs, tolerance: 0), 0, "scale=\(scale) rank=\(rank) text=\(text)")
                }
            }
        }
    }
}
