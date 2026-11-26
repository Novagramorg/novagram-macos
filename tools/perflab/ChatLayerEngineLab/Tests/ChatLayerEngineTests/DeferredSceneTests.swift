import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class DeferredSceneTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install(); TGUIKitAccessibility.isEnabled = true }

    func testNativeLifecycleDoesNotAllocateAnUnusedScene() {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100), deferred: true)
        let window = Window(contentRect: scene.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let native = TextView()
        native.update(TextTests().layout("Native contents"))
        scene.addSubview(native)
        window.contentView = scene
        scene.layoutSubtreeIfNeeded()
        scene.updateTrackingAreas()
        scene.viewDidChangeBackingProperties()
        scene.isHidden = true
        scene.isHidden = false
        scene.cancelInput()
        scene.focus(nil)
        scene.updateHover(at: NSPoint(x: 200, y: 50))
        XCTAssertFalse(scene.handlePointer(.down, at: NSPoint(x: 200, y: 50)))
        scene.removeAllToolTips()
        scene.selectableTextNodeIds = []
        XCTAssertNil(scene.node(id: "unused"))
        XCTAssertFalse(scene.hasActiveInput)
        XCTAssertNil(scene.focusedNode)
        XCTAssertFalse(scene.acceptsFirstResponder)
        _ = scene.accessibilityChildren()
        _ = scene.isAccessibilityElement()
        _ = scene.accessibilityRole()
        _ = scene.accessibilityHitTest(window.convertPoint(toScreen: NSPoint(x: 5, y: 5)))
        XCTAssertFalse(scene.hasLayerContent)
        XCTAssertEqual(scene.trackingAreas.count, 0)
        XCTAssertLessThanOrEqual(scene.layer?.sublayers?.count ?? 0, 1)
        XCTAssertTrue(scene.hitTest(scene.convert(NSPoint(x: 5, y: 5), to: scene.superview)) === native)
        window.contentView = nil
        XCTAssertFalse(scene.hasLayerContent)
    }

    func testFirstLayerActivatesAttachedHostAndWindowCancellation() throws {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100), deferred: true)
        let window = Window(contentRect: scene.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scene
        defer { window.contentView = nil; window.close() }
        var activated = 0
        let button = ChatLayerButtonNode(id: "button", label: "Action", action: { activated += 1 })
        button.frame = NSRect(x: 5, y: 5, width: 80, height: 25)
        try scene.root.setChildren([button])
        scene.layoutSubtreeIfNeeded()
        XCTAssertTrue(scene.hasLayerContent)
        XCTAssertTrue(scene.node(id: "button") === button)
        XCTAssertEqual(scene.trackingAreas.count, 1)
        XCTAssertTrue(scene.handlePointer(.down, at: NSPoint(x: 10, y: 10)))
        XCTAssertTrue(scene.hasActiveInput)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        _ = scene.handlePointer(.up, at: NSPoint(x: 10, y: 10))
        XCTAssertEqual(activated, 0)
        window.contentView = nil
        XCTAssertFalse(scene.hasActiveInput)
    }

    func testNativeAccessibilityChildrenRemainWhenLayersActivate() throws {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100), deferred: true)
        let window = Window(contentRect: scene.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scene
        defer { window.contentView = nil; window.close() }
        let native = NSButton(title: "Native action", target: nil, action: nil)
        native.frame = NSRect(x: 180, y: 10, width: 100, height: 30)
        scene.addSubview(native)
        let text = ChatLayerTextNode(id: "text", selectable: false)
        text.update(TextTests().layout("Layer label"))
        try scene.root.setChildren([text])
        let children = try XCTUnwrap(scene.accessibilityChildren())
        XCTAssertTrue(children.contains { ($0 as? NSButtonCell) === native.cell }, "\(children)")
        XCTAssertTrue(children.contains { ($0 as? NSAccessibilityElement)?.accessibilityValue() as? String == "Layer label" })
        XCTAssertTrue(scene.hitTest(scene.convert(NSPoint(x: 200, y: 20), to: scene.superview)) === native)
    }

    func testFrameTransitionsUpdateHitIndexAndTextDrawingSize() throws {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100), deferred: true)
        let text = ChatLayerTextNode(id: "text", selectable: true)
        text.update(TextTests().layout("Move me"))
        try scene.root.setChildren([text])
        scene.layout()
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 3, y: 5)) === text)
        let next = NSRect(x: 100, y: 20, width: 120, height: 35)
        let generation = scene.geometryVersion
        text.updateFrame(next, transition: .animated(duration: 0.2, curve: .easeOut))
        XCTAssertGreaterThan(scene.geometryVersion, generation)
        XCTAssertEqual(text.frame, next)
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 3, y: 5)))
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 105, y: 25)) === text)
        XCTAssertNotNil(text.layer.animation(forKey: "position"))
        text.layer.removeAllAnimations()
        text.updateFrame(next.offsetBy(dx: 20, dy: 0), transition: .immediate)
        XCTAssertEqual(text.frame.origin.x, 120)
        text.updateFrame(NSRect(x: 20, y: 20, width: -5, height: -2), transition: .immediate)
        let reference = ChatLayerNode(id: "reference")
        reference.frame = NSRect(x: 20, y: 20, width: -5, height: -2)
        XCTAssertEqual(text.frame, reference.frame)
    }
}

extension DeferredSceneTests {
    func testReleasingEmptyContentFreesItsRootAndReactivationDoesNotDuplicateWindowObservers() throws {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100), deferred: true)
        let window = Window(contentRect: scene.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scene
        defer { window.contentView = nil; window.close() }
        for _ in 0..<20 {
            weak var root = scene.root
            XCTAssertTrue(scene.hasLayerContent)
            XCTAssertTrue(scene.releaseEmptyLayerContent())
            XCTAssertNil(root)
            XCTAssertFalse(scene.hasLayerContent)
            XCTAssertEqual(scene.trackingAreas.count, 0)
        }
        let node = ChatLayerNode(id: "observer")
        var notifications = 0
        node.onWindowKeyChanged = { _ in notifications += 1 }
        try scene.root.setChildren([node])
        XCTAssertFalse(scene.releaseEmptyLayerContent())
        notifications = 0
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertEqual(notifications, 1)
        try scene.root.setChildren([])
        XCTAssertTrue(scene.releaseEmptyLayerContent())
        let owned = ChatLayerSceneView(frame: .zero, ownedRoot: ChatLayerNode(id: "external-owner"))
        XCTAssertFalse(owned.releaseEmptyLayerContent())
        XCTAssertTrue(owned.hasLayerContent)
    }

    func testCleanupCannotReleaseContentCreatedByAnInputCancellationCallback() throws {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100), deferred: true)
        let root = scene.root
        root.acceptsPointerEvents = true
        root.onPointer = { event in
            if event.kind == .cancelled {
                let replacement = ChatLayerNode(id: "replacement")
                try! root.setChildren([replacement])
            }
            return event.kind == .down
        }
        scene.layout()
        XCTAssertTrue(scene.handlePointer(.down, at: NSPoint(x: 10, y: 10)))
        XCTAssertFalse(scene.releaseEmptyLayerContent())
        XCTAssertTrue(scene.hasLayerContent)
        XCTAssertNotNil(scene.node(id: "replacement"))
    }
}

extension DeferredSceneTests {
    func testTrackingAreaReusesVisibleRectTrackingAndIsRemovedOnDetach() throws {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        scene.updateTrackingAreas()
        XCTAssertTrue(scene.trackingAreas.isEmpty)
        let window = Window(contentRect: scene.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scene
        defer { window.contentView = nil; window.close() }
        let initial = try XCTUnwrap(scene.trackingAreas.first)
        for index in 0..<50 {
            scene.frame.size.width = CGFloat(200 + index)
            scene.updateTrackingAreas()
            XCTAssertEqual(scene.trackingAreas.count, 1)
            XCTAssertTrue(scene.trackingAreas.first === initial)
        }
        XCTAssertTrue(initial.options.contains(.inVisibleRect))
        window.contentView = nil
        XCTAssertTrue(scene.trackingAreas.isEmpty)
        window.contentView = scene
        XCTAssertEqual(scene.trackingAreas.count, 1)
        XCTAssertFalse(scene.trackingAreas.first === initial)
    }
}
