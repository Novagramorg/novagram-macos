import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class SceneTests: XCTestCase {
    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        TGUIKitAccessibility.isEnabled = true
    }
    func scene() -> ChatLayerSceneView {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scene.layout()
        return scene
    }
    func node(_ id: String, _ frame: NSRect = NSRect(x: 10, y: 10, width: 100, height: 50)) -> ChatLayerNode {
        let node = ChatLayerNode(id: id)
        node.frame = frame
        node.acceptsPointerEvents = true
        return node
    }

    func testTrackingEventsUseSafeClickCountsAndPreserveModifiers() throws {
        let scene = scene(), target = node("target")
        try scene.root.setChildren([target])
        var received: [ChatLayerPointerEvent] = []
        target.onPointer = { event in
            if event.nativeEvent != nil { received.append(event) }
            return false
        }
        for type in [NSEvent.EventType.mouseEntered, .mouseExited, .cursorUpdate] {
            let native = try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: NSPoint(x: 20, y: 20), modifierFlags: .shift, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, trackingNumber: 0, userData: nil))
            scene.handlePointer(.moved, at: NSPoint(x: 20, y: 20), native: native)
            XCTAssertEqual(received.last?.clickCount, 1)
            XCTAssertEqual(received.last?.modifiers, .shift)
            XCTAssertTrue(received.last?.nativeEvent === native)
        }
        XCTAssertEqual(received.count, 3)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
            let native = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 3, pressure: 0))
            scene.handlePointer(.moved, at: NSPoint(x: 20, y: 20), native: native)
            XCTAssertEqual(received.last?.clickCount, 3)
        }
        XCTAssertEqual(received.count, 6)
    }
    func testOrderingReorderingAndDecorativeNodes() throws {
        let scene = scene(), a = node("a"), b = node("b"), c = node("c")
        try scene.root.setChildren([a, b, c])
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 30, y: 30)) === c)
        c.acceptsPointerEvents = false
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 30, y: 30)) === b)
        a.zIndex = 2
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 30, y: 30)) === a)
        a.zIndex = 0
        try scene.root.setChildren([b, a, c])
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 30, y: 30)) === a)
        XCTAssertTrue(scene.root.layer.sublayers?[0] === b.layer)
        XCTAssertTrue(scene.root.layer.sublayers?[1] === a.layer)
        XCTAssertTrue(scene.node(id: "a") === a)
    }
    func testNestedCoordinatesOverflowAndClipping() throws {
        let scene = scene(), parent = node("parent", NSRect(x: 20, y: 30, width: 50, height: 50))
        let child = node("child", NSRect(x: 40, y: 20, width: 40, height: 20))
        try parent.setChildren([child]); try scene.root.setChildren([parent])
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 80, y: 55)) === child)
        parent.clipsChildren = true
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 80, y: 55)))
        var local: NSPoint?
        child.onPointer = { event in if event.kind == .down { local = event.location; return true }; return false }
        _ = scene.handlePointer(.down, at: NSPoint(x: 65, y: 55))
        XCTAssertEqual(local, NSPoint(x: 5, y: 5))
        parent.isHidden = true
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 65, y: 55)))
    }
    func testCaptureOutsideReleaseAndRemovalCancellation() throws {
        let scene = scene(), node = node("button")
        var events: [ChatLayerPointerEvent.Kind] = []
        node.onPointer = { events.append($0.kind); return $0.kind == .down }
        try scene.root.setChildren([node])
        XCTAssertTrue(scene.handlePointer(.down, at: NSPoint(x: 20, y: 20)))
        XCTAssertTrue(scene.handlePointer(.dragged, at: NSPoint(x: 700, y: 700)))
        XCTAssertTrue(scene.handlePointer(.up, at: NSPoint(x: 700, y: 700)))
        XCTAssertTrue(events.contains(.dragged)); XCTAssertTrue(events.contains(.up))
        _ = scene.handlePointer(.down, at: NSPoint(x: 20, y: 20))
        try scene.root.setChildren([])
        XCTAssertTrue(events.contains(.cancelled))
        XCTAssertTrue(scene.handlePointer(.up, at: NSPoint(x: 20, y: 20)))
        XCTAssertNil(scene.node(id: "button"))
    }
    func testTreeErrorsAreAtomic() throws {
        let scene = scene(), a = node("a"), b = node("b")
        try scene.root.setChildren([a, b])
        XCTAssertThrowsError(try a.setChildren([scene.root]))
        XCTAssertThrowsError(try scene.root.setChildren([node("a"), node("a")]))
        XCTAssertThrowsError(try a.setChildren([b]))
        XCTAssertEqual(scene.root.children.count, 2)
        XCTAssertTrue(scene.node(id: "a") === a)
    }
    func testReentrantRemovalDoesNotCaptureDetachedNode() throws {
        let scene = scene(), node = node("button")
        var up = 0
        node.onPointer = { [weak scene] event in
            if event.kind == .down { try! scene?.root.setChildren([]); return true }
            if event.kind == .up { up += 1 }
            return false
        }
        try scene.root.setChildren([node])
        _ = scene.handlePointer(.down, at: NSPoint(x: 20, y: 20))
        XCTAssertTrue(scene.handlePointer(.dragged, at: NSPoint(x: 20, y: 20)))
        XCTAssertTrue(scene.handlePointer(.up, at: NSPoint(x: 20, y: 20)))
        XCTAssertEqual(up, 0)
    }
    func testAccessibilityFrameActionAndLifetime() throws {
        weak var released: ChatLayerSceneView?
        var retainedElement: NSAccessibilityProtocol?
        try autoreleasepool {
        let window = NSWindow(contentRect: NSRect(x: 80, y: 100, width: 400, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var scene: ChatLayerSceneView? = self.scene()
        window.contentView = scene
        let node = self.node("button")
        node.accessibilityRole = .button
        node.accessibilityLabel = "Open profile"
        var presses = 0
        node.onAccessibilityPress = { presses += 1; return true }
        try scene!.root.setChildren([node])
        let element = try XCTUnwrap(scene!.accessibilityChildren()?.first as? NSAccessibilityProtocol)
        XCTAssertEqual(element.accessibilityLabel(), "Open profile")
        XCTAssertEqual(element.accessibilityFrame(), window.convertToScreen(scene!.convert(node.frame, to: nil)))
        XCTAssertTrue(element.accessibilityPerformPress()); XCTAssertEqual(presses, 1)
        node.isEnabled = false
        XCTAssertFalse(element.accessibilityPerformPress()); XCTAssertEqual(presses, 1)
        released = scene
        retainedElement = element
        window.contentView = nil
        scene = nil
        CATransaction.flush()
        }
        XCTAssertNil(released)
        XCTAssertFalse(retainedElement!.isAccessibilityElement())
    }
}

extension SceneTests {
    func testNativeAncestorHidingCancelsCaptureAndDisabledNodesExitHover() throws {
        let scene = scene(), button = node("button")
        let parent = View(frame: scene.frame)
        parent.addSubview(scene)
        try scene.root.setChildren([button])
        var events: [ChatLayerPointerEvent.Kind] = []
        button.onPointer = { events.append($0.kind); return $0.kind == .down }
        _ = scene.handlePointer(.moved, at: NSPoint(x: 20, y: 20))
        XCTAssertEqual(events.filter { $0 == .entered }.count, 1)
        button.isEnabled = false
        XCTAssertEqual(events.filter { $0 == .exited }.count, 1)
        button.isEnabled = true
        XCTAssertEqual(events.filter { $0 == .entered }.count, 2)
        _ = scene.handlePointer(.down, at: NSPoint(x: 20, y: 20))
        parent.isHidden = true
        XCTAssertTrue(scene.handlePointer(.up, at: NSPoint(x: 20, y: 20)))
        XCTAssertEqual(events.filter { $0 == .cancelled }.count, 1)
        XCTAssertFalse(events.contains(.up))
        parent.isHidden = false
        _ = scene.handlePointer(.down, at: NSPoint(x: 20, y: 20))
        XCTAssertTrue(scene.handlePointer(.up, at: NSPoint(x: 20, y: 20)))
        XCTAssertEqual(events.filter { $0 == .up }.count, 1)
    }

    func testDisabledAncestorsCaptureCancellationAndButtonIsolation() throws {
        let scene = scene(), parent = node("parent"), child = node("child", NSRect(x: 0, y: 0, width: 50, height: 40))
        try parent.setChildren([child]); try scene.root.setChildren([parent])
        var events: [(ChatLayerPointerEvent.Kind, Int)] = []
        child.onPointer = { events.append(($0.kind, $0.button)); return $0.kind == .down }
        _ = scene.handlePointer(.down, at: NSPoint(x: 20, y: 20))
        _ = scene.handlePointer(.down, at: NSPoint(x: 20, y: 20), button: 1)
        XCTAssertTrue(scene.handlePointer(.up, at: NSPoint(x: 180, y: 180), button: 1))
        parent.isEnabled = false
        XCTAssertEqual(events.filter { $0.0 == .cancelled && $0.1 == 0 }.count, 1)
        XCTAssertTrue(scene.handlePointer(.dragged, at: NSPoint(x: 20, y: 20)))
        XCTAssertTrue(scene.handlePointer(.up, at: NSPoint(x: 20, y: 20)))
        XCTAssertEqual(events.filter { $0.0 == .up && $0.1 == 0 }.count, 0)
        parent.isEnabled = true
        XCTAssertTrue(scene.handlePointer(.down, at: NSPoint(x: 20, y: 20)))
        XCTAssertTrue(scene.handlePointer(.up, at: NSPoint(x: 20, y: 20)))
    }
    func testBubblingToNonTargetableParentAndRepeatedDown() throws {
        let scene = scene(), parent = node("parent"), child = node("child", NSRect(x: 0, y: 0, width: 50, height: 40))
        parent.acceptsPointerEvents = false
        try parent.setChildren([child]); try scene.root.setChildren([parent])
        var events: [ChatLayerPointerEvent.Kind] = []
        parent.onPointer = { events.append($0.kind); return $0.kind == .down }
        _ = scene.handlePointer(.down, at: NSPoint(x: 20, y: 20))
        child.isEnabled = true
        XCTAssertFalse(events.contains(.cancelled))
        _ = scene.handlePointer(.down, at: NSPoint(x: 20, y: 20))
        XCTAssertEqual(events.filter { $0 == .cancelled }.count, 1)
        _ = scene.handlePointer(.up, at: NSPoint(x: 180, y: 180))
        XCTAssertEqual(events.filter { $0 == .up }.count, 1)
    }
    func testHoverReentrantRemovalAndFocusOrder() throws {
        let scene = scene(), a = node("a"), b = node("b", NSRect(x: 140, y: 10, width: 100, height: 50))
        for node in [a, b] { node.acceptsKeyboardFocus = true }
        try scene.root.setChildren([a, b])
        XCTAssertTrue(scene.moveFocus(backward: false)); XCTAssertTrue(scene.focusedNode === a)
        XCTAssertTrue(scene.moveFocus(backward: false)); XCTAssertTrue(scene.focusedNode === b)
        XCTAssertTrue(scene.moveFocus(backward: true)); XCTAssertTrue(scene.focusedNode === a)
        a.isEnabled = false
        XCTAssertNil(scene.focusedNode)
        XCTAssertTrue(scene.moveFocus(backward: true)); XCTAssertTrue(scene.focusedNode === b)
        var entered = 0, exited = 0
        b.onPointer = { [weak scene] event in
            if event.kind == .entered { entered += 1; try! scene?.root.setChildren([a]) }
            if event.kind == .exited { exited += 1 }
            return false
        }
        _ = scene.handlePointer(.moved, at: NSPoint(x: 150, y: 20))
        XCTAssertEqual(entered, 1); XCTAssertEqual(exited, 1)
        XCTAssertNil(scene.focusedNode)
    }
    func testNodeContentRemainsBelowChildrenAndUnchangedTreeDoesNotRebind() throws {
        let scene = scene(), parent = node("parent"), a = node("a"), b = node("b")
        let drawing = SimpleLayer()
        parent.layer.addSublayer(drawing)
        try parent.setChildren([a, b]); try scene.root.setChildren([parent])
        var attachments = 0
        a.onWindowKeyChanged = { _ in attachments += 1 }
        try parent.setChildren([b, a])
        XCTAssertTrue(parent.layer.sublayers?.first === drawing)
        XCTAssertTrue(parent.layer.sublayers?[1] === b.layer)
        XCTAssertTrue(parent.layer.sublayers?[2] === a.layer)
        try parent.setChildren([b, a])
        XCTAssertEqual(attachments, 0)
    }
    func testDynamicPointerTargetsAndTransparentAncestors() throws {
        let scene = scene(), parent = node("parent"), child = node("child", NSRect(x: 0, y: 0, width: 30, height: 30))
        parent.acceptsPointerEvents = false; child.acceptsPointerEvents = false
        try parent.setChildren([child]); try scene.root.setChildren([parent])
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 20, y: 20)))
        child.acceptsPointerEvents = true
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 20, y: 20)) === child)
        parent.opacity = 0
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 20, y: 20)))
        parent.opacity = 1
        child.acceptsPointerEvents = false
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 20, y: 20)))
    }
    func testNestedAccessibilityHitAndWindowCancellation() throws {
        let window = NSWindow(contentRect: NSRect(x: 50, y: 70, width: 400, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let scene = scene(), parent = node("group"), child = node("button", NSRect(x: 0, y: 0, width: 50, height: 40))
        window.contentView = scene
        parent.accessibilityRole = .group; child.accessibilityRole = .button
        child.accessibilityLabel = "nested action"
        try parent.setChildren([child]); try scene.root.setChildren([parent])
        let point = window.convertPoint(toScreen: scene.convert(NSPoint(x: 20, y: 20), to: nil))
        let hit = try XCTUnwrap(scene.accessibilityHitTest(point) as? NSAccessibilityProtocol)
        XCTAssertEqual(hit.accessibilityLabel(), "nested action")
        var cancellations = 0
        child.onPointer = { event in if event.kind == .cancelled { cancellations += 1 }; return event.kind == .down }
        _ = scene.handlePointer(.down, at: NSPoint(x: 20, y: 20))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertEqual(cancellations, 1)
        XCTAssertTrue(scene.handlePointer(.up, at: NSPoint(x: 20, y: 20)))
        _ = scene.handlePointer(.down, at: NSPoint(x: 20, y: 20))
        scene.isHidden = true
        XCTAssertEqual(cancellations, 2)
        XCTAssertNil(scene.accessibilityChildren())
    }
}

extension SceneTests {
    func testKeyboardFocusDoesNotWrapOrActivateHiddenAncestors() throws {
        let scene = scene(), a = node("a"), b = node("b")
        for node in [a, b] { node.acceptsKeyboardFocus = true }
        try scene.root.setChildren([a, b])
        XCTAssertTrue(scene.moveFocus(backward: false))
        XCTAssertFalse(scene.moveFocus(backward: true))
        XCTAssertTrue(scene.focusedNode === a)
        XCTAssertTrue(scene.moveFocus(backward: false))
        XCTAssertFalse(scene.moveFocus(backward: false))
        XCTAssertTrue(scene.focusedNode === b)
        var commands = 0
        b.onCommand = { _ in commands += 1; return true }
        let parent = View(frame: scene.frame)
        parent.addSubview(scene)
        scene.copy(nil)
        XCTAssertEqual(commands, 1)
        parent.isHidden = true
        scene.copy(nil)
        XCTAssertEqual(commands, 1)
        XCTAssertFalse(scene.acceptsFirstResponder)
    }
}

extension SceneTests {
    func testHitIndexInvalidatesOnGeometryTransformsOrderingAndCustomRegions() throws {
        let scene = scene(), parent = node("parent", NSRect(x: 0, y: 0, width: 120, height: 100)), child = node("child")
        parent.acceptsPointerEvents = false
        try parent.setChildren([child]); try scene.root.setChildren([parent])
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 20, y: 20)) === child)
        parent.frame.origin.x = 100
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 20, y: 20)))
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 120, y: 20)) === child)
        parent.transform = CATransform3DMakeTranslation(80, 0, 0)
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 120, y: 20)))
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 200, y: 20)) === child)
        child.hitRegion = { $0.x >= -20 && $0.x < 100 && $0.y >= 0 && $0.y < 50 }
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 175, y: 20)) === child)
        child.hitRegion = nil
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 175, y: 20)))
        let top = node("top", NSRect(x: 190, y: 10, width: 100, height: 50))
        try scene.root.setChildren([parent, top])
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 200, y: 20)) === top)
        parent.zIndex = 1
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 200, y: 20)) === child)
        parent.sublayerTransform = CATransform3DMakeTranslation(80, 0, 0)
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 200, y: 20)) === top)
    }
}

extension SceneTests {
    func testHitIndexReleasesRemovedNodesAndHonorsRoundedSelfClipping() throws {
        let scene = scene()
        weak var released: ChatLayerNode?
        try autoreleasepool {
            let node = node("rounded")
            node.clipsChildren = true
            node.layer.cornerRadius = 20
            try scene.root.setChildren([node])
            XCTAssertNil(scene.hitNode(at: NSPoint(x: 10.1, y: 10.1)))
            XCTAssertTrue(scene.hitNode(at: NSPoint(x: 50, y: 30)) === node)
            released = node
        }
        try scene.root.setChildren([])
        XCTAssertNil(released)
    }
}
