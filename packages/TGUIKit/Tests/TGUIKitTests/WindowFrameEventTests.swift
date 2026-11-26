import AppKit
import XCTest
@testable import TGUIKit

final class WindowFrameEventTests: XCTestCase {
    func testFrameGestureBypassesHandlersAndContentGestureKeepsThemAcrossTheFrame() throws {
        let fixture = try WindowFrameEventFixture()
        defer { fixture.window.close() }
        try fixture.send(.leftMouseDown, at: fixture.framePoint)
        try fixture.send(.leftMouseDragged, at: fixture.contentPoint)
        try fixture.send(.leftMouseUp, at: fixture.contentPoint)
        XCTAssertTrue(fixture.handledEvents.isEmpty)
        try fixture.send(.leftMouseDown, at: fixture.contentPoint)
        try fixture.send(.leftMouseDragged, at: fixture.framePoint)
        try fixture.send(.leftMouseUp, at: fixture.framePoint)
        XCTAssertEqual(fixture.handledEvents, [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
    }

    func testNewContentGestureResetsFrameOwnershipWhenAppKitConsumesMouseUp() throws {
        let fixture = try WindowFrameEventFixture()
        defer { fixture.window.close() }
        try fixture.send(.leftMouseDown, at: fixture.framePoint)
        try fixture.send(.leftMouseDragged, at: fixture.contentPoint)
        XCTAssertTrue(fixture.handledEvents.isEmpty)
        try fixture.send(.leftMouseDown, at: fixture.contentPoint)
        try fixture.send(.leftMouseDragged, at: fixture.contentPoint)
        try fixture.send(.leftMouseUp, at: fixture.contentPoint)
        XCTAssertEqual(fixture.handledEvents, [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
    }
}

private final class WindowFrameEventFixture {
    let window: Window
    let framePoint = NSPoint(x: 40, y: 100)
    let contentPoint = NSPoint(x: 200, y: 100)
    var handledEvents: [NSEvent.EventType] = []
    private let owner = NSObject()

    init() throws {
        TGUIKitTestBootstrap.install()
        window = Window(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let contentView = MouseSinkView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = contentView
        let descendant = MouseSinkView(frame: NSRect(x: 150, y: 50, width: 100, height: 100))
        contentView.addSubview(descendant)
        let frameView = try XCTUnwrap(contentView.superview)
        let chrome = MouseSinkView(frame: NSRect(x: 30, y: 50, width: 30, height: 100))
        frameView.addSubview(chrome, positioned: .above, relativeTo: contentView)
        XCTAssertTrue(frameView.hitTest(framePoint) === chrome)
        XCTAssertTrue(frameView.hitTest(contentPoint) === descendant)
        for eventType: NSEvent.EventType in [.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
            window.set(mouseHandler: { [weak self] event in
                self?.handledEvents.append(event.type)
                return .invoked
            }, with: owner, for: eventType, priority: .medium)
        }
    }

    func send(_ type: NSEvent.EventType, at point: NSPoint) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        window.sendEvent(event)
    }
}

private final class MouseSinkView: NSView {
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
}
