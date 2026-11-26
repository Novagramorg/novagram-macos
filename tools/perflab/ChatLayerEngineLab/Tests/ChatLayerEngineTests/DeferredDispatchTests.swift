import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class DeferredDispatchTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func scene() -> ChatLayerSceneView {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 200, height: 80), deferred: true)
        _ = scene.root
        scene.layout()
        return scene
    }

    func testHoverCallbackCanReleaseTheScene() {
        let scene = scene(), root = scene.root
        root.acceptsPointerEvents = true
        var entered = 0
        root.onPointer = { event in
            if event.kind == .entered {
                entered += 1
                XCTAssertTrue(scene.releaseEmptyLayerContent())
            }
            return false
        }
        scene.updateHover(at: NSPoint(x: 10, y: 10))
        XCTAssertEqual(entered, 1)
        XCTAssertFalse(scene.hasLayerContent)
        XCTAssertFalse(scene.hasActiveInput)
    }

    func testDownCallbackReleaseDoesNotCaptureAReplacementScene() throws {
        for replace in [false, true] {
            let scene = scene(), root = scene.root
            root.acceptsPointerEvents = true
            var replacementEvents = 0
            root.onPointer = { event in
                if event.kind == .down {
                    XCTAssertTrue(scene.releaseEmptyLayerContent())
                    if replace {
                        let next = scene.root
                        next.acceptsPointerEvents = true
                        next.onPointer = { _ in replacementEvents += 1; return true }
                        scene.layout()
                    }
                    return true
                }
                return false
            }
            XCTAssertTrue(scene.handlePointer(.down, at: NSPoint(x: 10, y: 10)))
            XCTAssertEqual(scene.hasLayerContent, replace)
            XCTAssertEqual(replacementEvents, 0)
            XCTAssertNil(scene.focusedNode)
            XCTAssertFalse(scene.handlePointer(.up, at: NSPoint(x: 250, y: 90)))
            XCTAssertEqual(replacementEvents, 0)
        }
    }

    func testFocusLossCanReleaseTheSceneDuringCancellation() {
        let scene = scene(), root = scene.root
        root.acceptsKeyboardFocus = true
        scene.focus(root)
        var focusLosses = 0
        root.onFocusChanged = { focused in
            if !focused {
                focusLosses += 1
                XCTAssertTrue(scene.releaseEmptyLayerContent())
            }
        }
        scene.cancelInput()
        XCTAssertEqual(focusLosses, 1)
        XCTAssertFalse(scene.hasLayerContent)
    }

    func testHitRegionCanReleaseTheSceneWithoutReactivatingIt() {
        let scene = scene(), root = scene.root
        root.acceptsPointerEvents = true
        root.hitRegion = { _ in
            XCTAssertTrue(scene.releaseEmptyLayerContent())
            return true
        }
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 10, y: 10)))
        XCTAssertFalse(scene.hasLayerContent)
    }

    func testWindowCancellationCanReleaseTheScene() {
        let scene = scene(), root = scene.root
        let window = Window(contentRect: scene.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scene
        defer { window.contentView = nil; window.close() }
        root.acceptsPointerEvents = true
        root.onPointer = { event in
            if event.kind == .cancelled { XCTAssertTrue(scene.releaseEmptyLayerContent()) }
            return event.kind == .down
        }
        XCTAssertTrue(scene.handlePointer(.down, at: NSPoint(x: 10, y: 10)))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(scene.hasLayerContent)
    }

    func testLayoutHoverExitCanReleaseTheScene() throws {
        let scene = scene(), root = scene.root
        root.acceptsPointerEvents = true
        root.onPointer = { event in
            if event.kind == .exited { XCTAssertTrue(scene.releaseEmptyLayerContent()) }
            return false
        }
        _ = scene.handlePointer(.moved, at: NSPoint(x: 150, y: 10))
        scene.frame.size.width = 100
        scene.layout()
        XCTAssertFalse(scene.hasLayerContent)
    }
}


extension DeferredDispatchTests {
    func testRemovingLastChildDuringDownStopsBubblingIntoReleasedRoot() throws {
        for handled in [false, true] {
            let scene = scene(), root = scene.root
            let child = ChatLayerNode(id: "action")
            child.frame = scene.bounds
            child.acceptsPointerEvents = true
            var parentDowns = 0
            root.onPointer = { event in
                if event.kind == .down { parentDowns += 1 }
                return true
            }
            child.onPointer = { event in
                if event.kind == .down {
                    try! root.setChildren([])
                    XCTAssertTrue(scene.releaseEmptyLayerContent())
                    return handled
                }
                return false
            }
            try root.setChildren([child])
            XCTAssertTrue(scene.handlePointer(.down, at: NSPoint(x: 10, y: 10)))
            XCTAssertEqual(parentDowns, 0)
            XCTAssertFalse(scene.hasLayerContent)
            XCTAssertNil(child.scene)
        }
    }

    func testInvalidCaptureCancellationCanReleaseTheScene() throws {
        let scene = scene(), root = scene.root
        let child = ChatLayerNode(id: "action")
        child.frame = scene.bounds
        child.acceptsPointerEvents = true
        var cancellations = 0
        child.onPointer = { event in
            if event.kind == .cancelled {
                cancellations += 1
                XCTAssertTrue(scene.releaseEmptyLayerContent())
            }
            return event.kind == .down
        }
        try root.setChildren([child])
        XCTAssertTrue(scene.handlePointer(.down, at: NSPoint(x: 10, y: 10)))
        try root.setChildren([])
        XCTAssertEqual(cancellations, 1)
        XCTAssertFalse(scene.hasLayerContent)
    }

    func testCancellationDoesNotClearNewSceneHover() {
        let scene = scene(), root = scene.root
        root.acceptsPointerEvents = true
        var newExits = 0
        root.onPointer = { event in
            if event.kind == .cancelled {
                XCTAssertTrue(scene.releaseEmptyLayerContent())
                let replacement = scene.root
                replacement.acceptsPointerEvents = true
                replacement.onPointer = { event in
                    if event.kind == .exited { newExits += 1 }
                    return false
                }
                scene.layout()
                scene.updateHover(at: NSPoint(x: 10, y: 10))
            }
            return event.kind == .down
        }
        XCTAssertTrue(scene.handlePointer(.down, at: NSPoint(x: 10, y: 10)))
        scene.cancelInput()
        XCTAssertTrue(scene.hasLayerContent)
        XCTAssertTrue(scene.hasActiveInput)
        XCTAssertEqual(newExits, 0)
        scene.updateHover(at: nil)
        XCTAssertEqual(newExits, 1)
        scene.root.onPointer = nil
        XCTAssertTrue(scene.releaseEmptyLayerContent())
    }

    func testContextMenuFromReleasedSceneIsDiscarded() {
        let scene = scene(), root = scene.root
        let window = Window(contentRect: scene.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scene
        defer { window.contentView = nil; window.close() }
        root.acceptsPointerEvents = true
        root.menu = { _ in
            XCTAssertTrue(scene.releaseEmptyLayerContent())
            return NSMenu(title: "Obsolete")
        }
        let point = scene.convert(NSPoint(x: 10, y: 10), to: nil)
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        XCTAssertNil(scene.menu(for: event))
        XCTAssertFalse(scene.hasLayerContent)
    }
}
