import Cocoa
import XCTest
import TGUIKit
import AvatarTrackingCurrent
import AvatarTrackingOriginal

final class CurrentAvatar: AvatarTrackingCurrent.AvatarControl {
    var additions = 0
    var removals = 0
    override func addTrackingArea(_ area: NSTrackingArea) {
        additions += 1
        super.addTrackingArea(area)
    }
    override func removeTrackingArea(_ area: NSTrackingArea) {
        removals += 1
        super.removeTrackingArea(area)
    }
}

final class OriginalAvatar: AvatarTrackingOriginal.AvatarControl {
    var additions = 0
    var removals = 0
    override func addTrackingArea(_ area: NSTrackingArea) {
        additions += 1
        super.addTrackingArea(area)
    }
    override func removeTrackingArea(_ area: NSTrackingArea) {
        removals += 1
        super.removeTrackingArea(area)
    }
}

final class AvatarPointerWindow: NSWindow {
    var pointer = CGPoint.zero
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}

final class AvatarEventParent: NSView {
    var events: [NSEvent.EventType] = []
    override func mouseEntered(with event: NSEvent) { events.append(event.type) }
    override func mouseExited(with event: NSEvent) { events.append(event.type) }
    override func mouseDown(with event: NSEvent) { events.append(event.type) }
    override func mouseUp(with event: NSEvent) { events.append(event.type) }
}

final class AvatarTrackingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func window() -> AvatarPointerWindow {
        let window = AvatarPointerWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = AvatarEventParent(frame: CGRect(x: 0, y: 0, width: 300, height: 160))
        return window
    }

    func pair() -> (CurrentAvatar, OriginalAvatar) {
        let current = CurrentAvatar(font: .systemFont(ofSize: 16))
        let original = OriginalAvatar(font: .systemFont(ofSize: 16))
        current.frame = CGRect(x: 20, y: 30, width: 36, height: 36)
        original.frame = current.frame
        return (current, original)
    }

    func area(_ view: NSView) throws -> NSTrackingArea {
        let areas = view.trackingAreas.filter { ($0.owner as AnyObject?) === view }
        XCTAssertEqual(areas.count, 1)
        return try XCTUnwrap(areas.first)
    }

    func testRepeatedTrackingReusesAreaWithoutChangingOptions() throws {
        let window = window()
        defer { window.close() }
        let (current, original) = pair()
        XCTAssertTrue(current.trackingAreas.isEmpty)
        window.contentView!.addSubview(current)
        window.contentView!.addSubview(original)
        current.updateTrackingAreas()
        original.updateTrackingAreas()
        let retained = try area(current)
        let replaced = try area(original)
        let expected: NSTrackingArea.Options = [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        XCTAssertEqual(retained.options, expected)
        XCTAssertEqual(retained.options, replaced.options)
        let currentAdds = current.additions
        let originalAdds = original.additions
        for _ in 0..<100 {
            current.updateTrackingAreas()
            original.updateTrackingAreas()
            XCTAssertTrue(try area(current) === retained)
            XCTAssertFalse(try area(original) === replaced)
        }
        XCTAssertEqual(current.additions - currentAdds, 0)
        XCTAssertEqual(original.additions - originalAdds, 100)
    }

    func testAncestorAttachmentReparentAndWindowMigration() throws {
        let first = window(), second = window()
        defer { first.close(); second.close() }
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let nested = NSView(frame: container.bounds)
        container.addSubview(nested)
        let (current, _) = pair()
        nested.addSubview(current)
        XCTAssertTrue(current.trackingAreas.isEmpty)
        first.contentView!.addSubview(container)
        XCTAssertTrue(current.window === first)
        _ = try area(current)
        let detachedParent = NSView(frame: container.bounds)
        detachedParent.addSubview(nested)
        XCTAssertNil(current.window)
        XCTAssertTrue(current.trackingAreas.isEmpty)
        first.contentView!.addSubview(detachedParent)
        let firstArea = try area(current)
        let sibling = NSView(frame: container.bounds)
        first.contentView!.addSubview(sibling)
        sibling.addSubview(current)
        XCTAssertTrue(current.window === first)
        _ = try area(current)
        current.updateTrackingAreas()
        let movedArea = try area(current)
        current.updateTrackingAreas()
        XCTAssertTrue(try area(current) === movedArea)
        XCTAssertTrue((firstArea.owner as AnyObject?) === current)
        second.contentView!.addSubview(sibling)
        XCTAssertTrue(current.window === second)
        XCTAssertEqual(try area(current).options, movedArea.options)
        sibling.removeFromSuperview()
        XCTAssertNil(current.window)
        XCTAssertTrue(current.trackingAreas.isEmpty)
    }

    func testClippedScrollAndResizeRetainAreas() throws {
        let window = window()
        defer { window.close() }
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        let document = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 1000))
        scroll.documentView = document
        window.contentView!.addSubview(scroll)
        let (current, original) = pair()
        current.frame.origin.y = 400
        original.frame = current.frame
        document.addSubview(current)
        document.addSubview(original)
        current.updateTrackingAreas()
        original.updateTrackingAreas()
        let retained = try area(current)
        var visibleStates = Set<Bool>()
        for y: CGFloat in [0, 350, 390, 430, 500, 350, 0] {
            scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            current.updateTrackingAreas()
            original.updateTrackingAreas()
            XCTAssertTrue(try area(current) === retained)
            XCTAssertEqual(current.visibleRect, original.visibleRect)
            XCTAssertEqual(try area(current).options, try area(original).options)
            visibleStates.insert(scroll.contentView.bounds.intersects(current.frame))
        }
        XCTAssertEqual(visibleStates, Set([false, true]))
        for size in [CGSize(width: 20, height: 20), CGSize(width: 0, height: 0), CGSize(width: 55, height: 42)] {
            current.setFrameSize(size)
            original.setFrameSize(size)
            current.updateTrackingAreas()
            original.updateTrackingAreas()
            XCTAssertTrue(try area(current) === retained)
            XCTAssertEqual(try area(current).options, try area(original).options)
        }
    }

    private func deliverEntered(_ view: NSView, window: NSWindow) throws -> Int {
        let event = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: view.convert(CGPoint(x: 4, y: 4), to: nil), modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, trackingNumber: 0, userData: nil))
        var delivered = 0
        for area in view.trackingAreas where (area.owner as AnyObject?) === view {
            let owner = try XCTUnwrap(area.owner as? NSResponder)
            owner.mouseEntered(with: event)
            delivered += 1
        }
        return delivered
    }

    func testDisabledTrackingStillForwardsAndPruningMutationFails() throws {
        let window = window()
        defer { window.close() }
        let parent = try XCTUnwrap(window.contentView as? AvatarEventParent)
        let (current, original) = pair()
        current.userInteractionEnabled = false
        original.userInteractionEnabled = false
        for view: NSView in [original, current] {
            parent.addSubview(view)
            view.updateTrackingAreas()
            parent.events = []
            XCTAssertEqual(try deliverEntered(view, window: window), 1)
            XCTAssertEqual(parent.events, [.mouseEntered])
            let tracking = try area(view)
            view.removeTrackingArea(tracking)
            parent.events = []
            XCTAssertEqual(try deliverEntered(view, window: window), 0)
            XCTAssertTrue(parent.events.isEmpty)
            view.addTrackingArea(tracking)
            XCTAssertEqual(try deliverEntered(view, window: window), 1)
            XCTAssertEqual(parent.events, [.mouseEntered])
            view.removeFromSuperview()
        }
    }

    func testEnabledAndDisabledClickForwardingMatchBaseline() throws {
        let window = window()
        defer { window.close() }
        let parent = try XCTUnwrap(window.contentView as? AvatarEventParent)
        let (current, original) = pair()
        var currentClicks: [String] = [], originalClicks: [String] = []
        current.set(handler: { _ in currentClicks.append("single") }, for: .SingleClick)
        current.set(handler: { _ in currentClicks.append("click") }, for: .Click)
        original.set(handler: { _ in originalClicks.append("single") }, for: .SingleClick)
        original.set(handler: { _ in originalClicks.append("click") }, for: .Click)
        for enabled in [true, false] {
            current.userInteractionEnabled = enabled
            original.userInteractionEnabled = enabled
            var forwarded: [[NSEvent.EventType]] = []
            for view: NSView in [original, current] {
                parent.addSubview(view)
                window.pointer = view.convert(CGPoint(x: 10, y: 12), to: nil)
                let hit = try XCTUnwrap(parent.hitTest(view.convert(CGPoint(x: 10, y: 12), to: parent.superview)))
                XCTAssertTrue(hit === view)
                parent.events = []
                for clicks in [1, 2] {
                    for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                        let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: window.pointer, modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: clicks, pressure: 1))
                        if type == .leftMouseDown { hit.mouseDown(with: event) } else { hit.mouseUp(with: event) }
                    }
                }
                forwarded.append(parent.events)
                view.removeFromSuperview()
            }
            XCTAssertEqual(currentClicks, originalClicks)
            XCTAssertEqual(currentClicks, ["single", "click", "click"])
            XCTAssertEqual(forwarded[0], forwarded[1])
            XCTAssertEqual(forwarded[0].count, enabled ? 0 : 4)
        }
        XCTAssertEqual(current.isAccessibilityElement(), original.isAccessibilityElement())
        XCTAssertEqual(current.accessibilityRole(), original.accessibilityRole())
        XCTAssertEqual(current.subviews.count, original.subviews.count)
    }

    func testImageDisplayLifecycleCallbackStillRuns() {
        let window = window()
        defer { window.close() }
        let (current, original) = pair()
        let a = current.imageDisplayNotifications, b = original.imageDisplayNotifications
        window.contentView!.addSubview(current)
        window.contentView!.addSubview(original)
        current.removeFromSuperview()
        original.removeFromSuperview()
        XCTAssertGreaterThan(current.imageDisplayNotifications - a, 0)
        XCTAssertEqual(current.imageDisplayNotifications - a, original.imageDisplayNotifications - b)
    }

    func testRemovedAvatarsReleaseTrackingAreas() {
        let window = window()
        defer { window.close() }
        weak var currentView: NSView?
        weak var originalView: NSView?
        weak var currentArea: NSTrackingArea?
        weak var originalArea: NSTrackingArea?
        autoreleasepool {
            let (current, original) = pair()
            window.contentView!.addSubview(current)
            window.contentView!.addSubview(original)
            current.updateTrackingAreas()
            original.updateTrackingAreas()
            currentView = current
            originalView = original
            currentArea = current.trackingAreas.first
            originalArea = original.trackingAreas.first
            current.removeFromSuperview()
            original.removeFromSuperview()
        }
        CATransaction.flush()
        XCTAssertNil(currentView)
        XCTAssertNil(originalView)
        XCTAssertNil(currentArea)
        XCTAssertNil(originalArea)
    }
}
