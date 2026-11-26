import Cocoa
import XCTest
import SwiftSignalKit
@testable import TGUIKit

private final class ReuseTestTextView: TextView {
    override func mouseInside() -> Bool { true }
}

final class TextViewReuseTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func layout(_ text: String = "Message link", link: Bool = false) -> TextViewLayout {
        let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        if link { value.addAttribute(.link, value: "https://example.com", range: value.range) }
        let result = TextViewLayout(value, disableTooltips: false)
        result.measure(width: 240)
        return result
    }

    func testOlderHighlightCompletionCannotRemoveANewerHighlight() {
        let view = TextView()
        view.update(layout())
        view.highlight(text: "Message", color: .yellow)
        let completed = expectation(description: "Old highlight deadline passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            view.highlight(text: "link", color: .green)
            let replacement = view.layer!.sublayers!.first!
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                XCTAssertTrue(replacement.superlayer === view.layer)
                completed.fulfill()
            }
        }
        wait(for: [completed], timeout: 6)
    }

    func testResetDoesNotTransferSelectionToUnrelatedIdenticalText() {
        let view = TextView(), old = layout(), next = layout()
        view.update(old)
        old.selectedRange.range = NSRange(location: 0, length: 7)
        view.selectionWasCleared = true
        view.moveNextEventDeep = true
        XCTAssertTrue(view.resetForContentChange())
        XCTAssertNil(view.textLayout)
        XCTAssertFalse(view.selectionWasCleared)
        XCTAssertFalse(view.moveNextEventDeep)
        view.update(next)
        XCTAssertEqual(next.selectedRange.range.location, NSNotFound)
        XCTAssertEqual(old.selectedRange.range, NSRange(location: 0, length: 7))
    }

    func testActiveSelectionAndAnimationRejectResetWithoutMutatingLayout() {
        let view = TextView(), value = layout()
        view.update(value)
        view.controlState = .Highlight
        XCTAssertFalse(view.resetForContentChange())
        XCTAssertTrue(view.textLayout === value)
        view.controlState = .Normal
        view.canBeResponder = false
        XCTAssertFalse(view.resetForContentChange())
        view.canBeResponder = true
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0; animation.toValue = 1; animation.duration = 10
        view.layer?.add(animation, forKey: "test")
        XCTAssertFalse(view.resetForContentChange())
        XCTAssertTrue(view.textLayout === value)
        view.layer?.removeAllAnimations()
        XCTAssertTrue(view.resetForContentChange())
    }

    func window(_ view: TextView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView!.addSubview(view)
        return window
    }

    func event(_ type: NSEvent.EventType, view: TextView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: view.convert(NSPoint(x: 5, y: 5), to: nil), modifierFlags: [], timestamp: 1, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }

    func testMousePressRejectsResetUntilRelease() {
        let view = TextView(), value = layout()
        view.update(value)
        let window = window(view)
        defer { window.contentView = nil; window.close() }
        view.mouseDown(with: event(.leftMouseDown, view: view))
        XCTAssertFalse(view.resetForContentChange())
        XCTAssertTrue(view.textLayout === value)
        view.mouseUp(with: event(.leftMouseUp, view: view))
        XCTAssertTrue(view.resetForContentChange())
    }

    func testResetCancelsPendingMenuAndReleasesItsOldLayout() {
        let view = ReuseTestTextView(), value = layout(link: true)
        var started = false, disposed = false
        value.interactions.menuItems = { _ in
            Signal { _ in
                started = true
                return ActionDisposable { disposed = true }
            }
        }
        view.update(value)
        let window = window(view)
        defer { window.contentView = nil; window.close() }
        view.rightMouseDown(with: event(.rightMouseDown, view: view))
        XCTAssertTrue(started)
        XCTAssertFalse(disposed)
        XCTAssertTrue(view.resetForContentChange())
        XCTAssertTrue(disposed)
    }

    func testResetCancelsPendingLinkPreviewAndEmitsHoverExit() {
        let view = ReuseTestTextView(), value = layout(link: true)
        var previews = 0, exits = 0
        value.interactions.longHoverOnLink = { _, _ in previews += 1; return nil }
        value.interactions.hoverOnLink = { if case .exited = $0 { exits += 1 } }
        view.update(value)
        let window = window(view)
        defer { window.contentView = nil; window.close() }
        view.checkCursor(event(.mouseMoved, view: view))
        XCTAssertTrue(view.resetForContentChange())
        XCTAssertEqual(exits, 1)
        let completed = expectation(description: "Old hover deadline passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { completed.fulfill() }
        wait(for: [completed], timeout: 3)
        XCTAssertEqual(previews, 0)
    }

    func testResetDisposesActiveLinkPreview() {
        let view = ReuseTestTextView(), value = layout(link: true)
        let started = expectation(description: "Preview started")
        var disposed = false
        value.interactions.longHoverOnLink = { _, _ in
            started.fulfill()
            return ActionDisposable { disposed = true }
        }
        view.update(value)
        let window = window(view)
        defer { window.contentView = nil; window.close() }
        view.checkCursor(event(.mouseMoved, view: view))
        wait(for: [started], timeout: 3)
        XCTAssertFalse(disposed)
        XCTAssertTrue(view.resetForContentChange())
        XCTAssertTrue(disposed)
    }

}
