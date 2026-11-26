import XCTest
import AppKit
import ObjectiveC
@testable import TGUIKit

private final class HoverTestControl: Control {
    var pointerInside = true

    override func mouseInside() -> Bool {
        return pointerInside
    }
}

final class ControlHoverTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func makeControl() -> HoverTestControl {
        let control = HoverTestControl()
        control.canHighlight = false
        return control
    }

    private func waitForHover(_ condition: @escaping () -> Bool) {
        let delivered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        wait(for: [delivered], timeout: 2)
    }

    private func withPressedMouseButtons(_ mask: Int, _ body: () -> Void) throws {
        let method = try XCTUnwrap(class_getClassMethod(NSEvent.self, #selector(getter: NSEvent.pressedMouseButtons)))
        let replacement = imp_implementationWithBlock({ (_: AnyObject) -> Int in mask } as @convention(block) (AnyObject) -> Int)
        let original = method_setImplementation(method, replacement)
        defer {
            method_setImplementation(method, original)
            imp_removeBlock(replacement)
        }
        XCTAssertEqual(NSEvent.pressedMouseButtons, mask)
        body()
    }

    func testFixtureHoverDoesNotDependOnPhysicalMouseButtons() throws {
        try withPressedMouseButtons(1) {
            let control = makeControl()
            control.mouseEntered(with: event())
            XCTAssertEqual(control.controlState, .Hover)
        }
    }

    private func event(_ type: NSEvent.EventType = .mouseMoved) -> NSEvent {
        return NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
    }

    private func settleHover() {
        let settled = expectation(description: "Hover timer settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 2)
    }

    func testFirstMovementStartsHoverWithoutEnteredEvent() {
        let control = makeControl()
        var count = 0
        control.set(handler: { _ in count += 1 }, for: .LongOver)
        control.mouseMoved(with: event())
        waitForHover { count == 1 }
        XCTAssertEqual(count, 1)
    }

    func testOtherControlCannotCancelHover() {
        let control = makeControl()
        let other = makeControl()
        other.pointerInside = false
        var count = 0
        control.set(handler: { _ in count += 1 }, for: .LongOver)
        control.mouseEntered(with: event())
        other.mouseExited(with: event())
        waitForHover { count == 1 }
        XCTAssertEqual(count, 1)
    }

    func testParentEntryCannotReplaceChildHover() {
        let parent = makeControl()
        let control = makeControl()
        parent.addSubview(control)
        var count = 0
        control.set(handler: { _ in count += 1 }, for: .LongOver)
        control.mouseEntered(with: event())
        parent.mouseEntered(with: event())
        waitForHover { count == 1 }
        XCTAssertEqual(count, 1)
    }

    func testMovementDoesNotRepeatHoverUntilExitAndReentry() {
        let control = makeControl()
        var count = 0
        control.set(handler: { _ in count += 1 }, for: .LongOver)
        control.mouseEntered(with: event())
        control.mouseMoved(with: event())
        waitForHover { count == 1 }
        control.mouseMoved(with: event())
        settleHover()
        XCTAssertEqual(count, 1)
        control.pointerInside = false
        control.mouseExited(with: event())
        control.pointerInside = true
        control.mouseMoved(with: event())
        waitForHover { count == 2 }
        XCTAssertEqual(count, 2)
    }

    func testExitCancelsPendingHover() {
        let control = makeControl()
        var count = 0
        control.set(handler: { _ in count += 1 }, for: .LongOver)
        control.mouseEntered(with: event())
        control.pointerInside = false
        control.mouseExited(with: event())
        settleHover()
        XCTAssertEqual(count, 0)
    }

    func testDisabledInteractionDoesNotStartHover() {
        let control = makeControl()
        control.userInteractionEnabled = false
        var count = 0
        control.set(handler: { _ in count += 1 }, for: .LongOver)
        control.mouseMoved(with: event())
        settleHover()
        XCTAssertEqual(count, 0)
    }

    func testDisablingInteractionCancelsPendingHover() {
        let control = makeControl()
        var count = 0
        control.set(handler: { _ in count += 1 }, for: .LongOver)
        control.mouseEntered(with: event())
        control.userInteractionEnabled = false
        settleHover()
        XCTAssertEqual(count, 0)
        control.userInteractionEnabled = true
        control.mouseMoved(with: event())
        waitForHover { count == 1 }
        XCTAssertEqual(count, 1)
    }

    func testClickCancelsPendingHover() {
        let control = makeControl()
        control.handleLongEvent = false
        var count = 0
        control.set(handler: { _ in count += 1 }, for: .LongOver)
        control.mouseEntered(with: event())
        control.mouseDown(with: event(.leftMouseDown))
        control.mouseUp(with: event(.leftMouseUp))
        settleHover()
        XCTAssertEqual(count, 0)
    }

    func testPhysicalPressStillHighlightsProductionControls() throws {
        try withPressedMouseButtons(1) {
            let control = makeControl()
            control.canHighlight = true
            control.updateState()
            XCTAssertEqual(control.controlState, .Highlight)
        }
    }

    func testHoverIsDeliveredWithPhysicalButtonHeldInFixture() throws {
        try withPressedMouseButtons(1) {
            let control = makeControl()
            var count = 0
            control.set(handler: { _ in count += 1 }, for: .LongOver)
            control.mouseEntered(with: event())
            waitForHover { count == 1 }
            XCTAssertEqual(count, 1)
        }
    }

    func testHoverCallbackCanExitAndScheduleAnotherHover() {
        let control = makeControl()
        var count = 0
        control.set(handler: { [weak control] _ in
            count += 1
            if count == 1, let control {
                control.pointerInside = false
                control.mouseExited(with: self.event())
                control.pointerInside = true
                control.mouseEntered(with: self.event())
            }
        }, for: .LongOver)
        control.mouseEntered(with: event())
        waitForHover { count == 2 }
        XCTAssertEqual(count, 2)
    }

    func testDeinitCancelsPendingHoverWithoutRetainingControl() {
        weak var released: HoverTestControl?
        var count = 0
        autoreleasepool {
            let control = makeControl()
            released = control
            control.set(handler: { _ in count += 1 }, for: .LongOver)
            control.mouseEntered(with: event())
        }
        XCTAssertNil(released)
        settleHover()
        XCTAssertEqual(count, 0)
    }
}
