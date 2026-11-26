import Cocoa
import XCTest
import SwiftSignalKit
import TGUIKit
@testable import ChatLayerEngine

final class TextReentrancyTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func fixture() throws -> (ChatLayerSceneView, ChatLayerTextNode) {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let node = ChatLayerTextNode(id: "body", selectable: true)
        try scene.root.setChildren([node])
        return (scene, node)
    }

    private func hover(_ node: ChatLayerTextNode, kind: ChatLayerPointerEvent.Kind = .moved) {
        _ = node.onPointer?(ChatLayerPointerEvent(kind: kind, location: NSPoint(x: 5, y: 5), sceneLocation: NSPoint(x: 5, y: 5), button: 0, clickCount: 1, modifiers: [], nativeEvent: nil))
    }

    private func pendingMenu(_ node: ChatLayerTextNode, layout: TextViewLayout, dispose: @escaping () -> Void) {
        layout.alwaysStaticItems = false
        layout.interactions.topWindow = { Signal { _ in ActionDisposable(action: dispose) } }
        node.update(layout)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
        XCTAssertTrue(node.requestMenu(at: NSPoint(x: 5, y: 5), event: event))
    }

    func testMenuDisposalBindingWinsOverOuterUpdateAndFrame() throws {
        let (scene, node) = try fixture()
        let old = TextTests().layout("Original message"), newest = TextTests().layout("Newest message")
        let newestFrame = NSRect(x: 12, y: 30, width: 180, height: 40)
        pendingMenu(node, layout: old) { [weak node] in node?.update(newest, frame: newestFrame) }
        node.update(TextTests().layout("Superseded message"), frame: NSRect(x: 1, y: 2, width: 10, height: 10))
        XCTAssertTrue(node.textLayout === newest)
        XCTAssertEqual(node.frame, newestFrame)
        XCTAssertEqual(node.accessibilityValue as? String, newest.attributedString.string)
        withExtendedLifetime(scene) {}
    }

    func testMenuDisposalRebindingSameLayoutPreservesNewFrame() throws {
        let (scene, node) = try fixture()
        let original = TextTests().layout("Original message")
        let newestFrame = NSRect(x: 12, y: 30, width: 180, height: 40)
        pendingMenu(node, layout: original) { [weak node] in node?.update(original, frame: newestFrame) }
        node.update(TextTests().layout("Superseded message"), frame: .zero)
        XCTAssertTrue(node.textLayout === original)
        XCTAssertEqual(node.frame, newestFrame)
        withExtendedLifetime(scene) {}
    }

    func testMenuDisposalSelectionSurvivesOuterReset() throws {
        let (scene, node) = try fixture()
        let old = TextTests().layout("Original message"), newest = TextTests().layout("Newest message")
        newest.selectedRange.range = NSRange(location: 2, length: 3)
        pendingMenu(node, layout: old) { [weak node] in node?.update(newest) }
        node.resetInteraction()
        XCTAssertTrue(node.textLayout === newest)
        XCTAssertEqual(newest.selectedRange.range, NSRange(location: 2, length: 3))
        withExtendedLifetime(scene) {}
    }

    func testSelectionNotificationBindingWinsOverOuterUpdate() throws {
        let (scene, node) = try fixture()
        let newest = TextTests().layout("Newest message")
        node.update(TextTests().layout("Original message"))
        node.setExternalSelection(NSRange(location: 1, length: 4))
        node.onSelectionChanged = { [weak node] range in
            if range.location == NSNotFound { node?.update(newest) }
        }
        node.update(TextTests().layout("Superseded message"))
        XCTAssertTrue(node.textLayout === newest)
        withExtendedLifetime(scene) {}
    }

    func testHeaderStateCallbackBindingWinsOverOuterUpdate() throws {
        let (scene, node) = try fixture()
        let newest = TextTests().layout("Newest message")
        node.update(TextTests().layout("Original message"))
        let button = ChatLayerButtonNode(id: "header", label: "Copy", action: {})
        try node.setChildren([button])
        var notified = false
        button.onStateChanged = { [weak node] _, _, _ in
            if !notified { notified = true; node?.update(newest) }
        }
        node.update(TextTests().layout("Superseded message"))
        XCTAssertTrue(node.textLayout === newest)
        withExtendedLifetime(scene) {}
    }

    func testHoverExitClearsStateBeforeRebinding() throws {
        let (scene, node) = try fixture()
        let old = TextTests().layout("Link original"), newest = TextTests().layout("Newest message")
        var exits = 0
        old.interactions.hoverOnLink = { [weak node] value in
            if case .exited = value {
                exits += 1
                if exits == 1 { node?.update(newest) }
            }
        }
        node.update(old)
        hover(node)
        node.update(TextTests().layout("Superseded message"))
        XCTAssertEqual(exits, 1)
        XCTAssertTrue(node.textLayout === newest)
    }

    func testHoverEntryBindingCannotLeaveOldCursor() throws {
        let (scene, node) = try fixture()
        let old = TextTests().layout("Link original"), newest = TextTests().layout("Newest message")
        let cursor = NSCursor(image: NSImage(size: NSSize(width: 2, height: 2)), hotSpot: .zero)
        old.interactions.hoverOnLink = { [weak node] value in
            if case .entered = value { node?.update(newest); node?.cursor = cursor }
        }
        node.update(old)
        hover(node)
        XCTAssertTrue(node.textLayout === newest)
        XCTAssertTrue(node.cursor === cursor)
        withExtendedLifetime(scene) {}
    }

    func testLinkTypeResolverBindingCannotEnterOldLinkOnNewLayout() throws {
        let (scene, node) = try fixture()
        let old = TextTests().layout("Link original"), newest = TextTests().layout("Newest message")
        var entries = 0
        newest.interactions.hoverOnLink = { value in if case .entered = value { entries += 1 } }
        let cursor = NSCursor(image: NSImage(size: NSSize(width: 2, height: 2)), hotSpot: .zero)
        old.interactions.makeLinkType = { [weak node] _ in node?.update(newest); node?.cursor = cursor; return .plain }
        node.update(old)
        hover(node)
        XCTAssertTrue(node.textLayout === newest)
        XCTAssertEqual(entries, 0)
        XCTAssertTrue(node.cursor === cursor)
        withExtendedLifetime(scene) {}
    }

    func testSelectionNotificationBindingSurvivesOuterReset() throws {
        let (scene, node) = try fixture()
        let newest = TextTests().layout("Newest message")
        newest.selectedRange.range = NSRange(location: 2, length: 3)
        node.update(TextTests().layout("Original message"))
        node.setExternalSelection(NSRange(location: 1, length: 4))
        node.onSelectionChanged = { [weak node] range in
            if range.location == NSNotFound { node?.update(newest) }
        }
        node.resetInteraction()
        XCTAssertTrue(node.textLayout === newest)
        XCTAssertEqual(newest.selectedRange.range, NSRange(location: 2, length: 3))
        withExtendedLifetime(scene) {}
    }

    func testSelectableChangeDisposalCannotOverrideNewBinding() throws {
        let (scene, node) = try fixture()
        let old = TextTests().layout("Original message"), newest = TextTests().layout("Newest message")
        pendingMenu(node, layout: old) { [weak node] in node?.update(newest) }
        node.isSelectable = false
        XCTAssertTrue(node.textLayout === newest)
        XCTAssertTrue(node.isSelectable)
        withExtendedLifetime(scene) {}
    }

    func testHoverExitCallbackCanEnterNewBindingWithoutLosingHoverState() throws {
        let (scene, node) = try fixture()
        let old = TextTests().layout("Link original"), newest = TextTests().layout("Link newest")
        var exits = 0, entries = 0
        newest.interactions.hoverOnLink = { value in if case .entered = value { entries += 1 } }
        old.interactions.hoverOnLink = { [weak self, weak node] value in
            if case .exited = value {
                exits += 1
                if exits == 1, let node { node.update(newest); self?.hover(node) }
            }
        }
        node.update(old)
        hover(node)
        hover(node, kind: .exited)
        hover(node)
        XCTAssertTrue(node.textLayout === newest)
        XCTAssertEqual(exits, 1)
        XCTAssertEqual(entries, 1)
        withExtendedLifetime(scene) {}
    }

    func testDetachDisposalPreservesNewBindingSelection() throws {
        let (scene, node) = try fixture()
        let old = TextTests().layout("Original message"), newest = TextTests().layout("Newest message")
        pendingMenu(node, layout: old) { [weak node] in
            node?.update(newest)
            node?.setExternalSelection(NSRange(location: 2, length: 3))
        }
        try scene.root.setChildren([])
        XCTAssertNil(node.scene)
        XCTAssertTrue(node.textLayout === newest)
        XCTAssertEqual(newest.selectedRange.range, NSRange(location: 2, length: 3))
    }
}
