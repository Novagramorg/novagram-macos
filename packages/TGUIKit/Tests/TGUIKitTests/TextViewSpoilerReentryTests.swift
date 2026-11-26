import AppKit
import QuartzCore
import XCTest
@testable import TGUIKit

final class TextViewSpoilerReentryTests: XCTestCase {
    private var windows: [Window] = []

    override func setUp() {
        TGUIKitTestBootstrap.install()
    }

    override func tearDown() {
        for window in windows { window.contentView = nil; window.close() }
        windows.removeAll()
    }

    private func layout(_ string: String, hidden: NSRange? = nil, reveal: @escaping () -> Void = {}) -> TextViewLayout {
        let text = NSMutableAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        text.addAttribute(TextInputAttributes.spoiler, value: true, range: hidden ?? text.range)
        let layout = TextViewLayout(text, spoilerColor: .blue, onSpoilerReveal: reveal)
        layout.measure(width: 160)
        return layout
    }

    private func attach(_ view: TextView) {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 260, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 160))
        window.contentView?.addSubview(view)
        windows.append(window)
    }

    private func click(_ view: TextView, count: Int = 1, modifiers: NSEvent.ModifierFlags = []) throws {
        let layout = try XCTUnwrap(view.textLayout)
        let window = try XCTUnwrap(view._window)
        let rect = try XCTUnwrap(layout.spoilerRectFrames().first { $0.width > 0 && $0.height > 0 })
        let point = NSPoint(x: rect.minX + min(2, rect.width / 2), y: rect.midY)
        XCTAssertNotNil(layout.spoiler(at: point))
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: modifiers, timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: count, pressure: 1))
            if type == .leftMouseDown { view.mouseDown(with: event) }
            else { view.mouseUp(with: event) }
        }
    }

    private func inks(_ view: TextView) -> [InvisibleInkDustView] {
        return view.subviews.compactMap { $0 as? InvisibleInkDustView }
    }

    private func pixels(_ view: TextView) -> Data {
        view.layout()
        let context = CGContext(data: nil, width: 520, height: 320, bitsPerComponent: 8, bytesPerRow: 2080, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: 2, y: 2)
        view.draw(view.drawingLayer, in: context)
        return Data(bytes: context.data!, count: 2080 * 320)
    }

    private func waitForAnimations() {
        CATransaction.flush()
        let done = expectation(description: "Reveal animation completions drain")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { done.fulfill() }
        wait(for: [done], timeout: 3)
    }

    private func assertHiddenContent(_ view: TextView, matches expected: TextView, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(view.subviews.compactMap { $0 as? TextView }.isEmpty, "An obsolete reveal inserted a second TextView", file: file, line: line)
        XCTAssertEqual(inks(view).map(\.frame), inks(expected).map(\.frame), file: file, line: line)
        XCTAssertTrue(inks(view).allSatisfy { $0.layer?.animationKeys()?.isEmpty != false }, "Replacement ink is being removed by an obsolete reveal", file: file, line: line)
        XCTAssertEqual(pixels(view), pixels(expected), file: file, line: line)
    }

    func testRevealCallbackReplacementKeepsNewHiddenLayoutAndSelection() throws {
        let view = TextView(), expected = TextView()
        attach(view)
        attach(expected)
        let nextText = "New hidden text wraps across lines\nVisible ending"
        let hidden = NSRange(location: 0, length: 32)
        let next = layout(nextText, hidden: hidden)
        let selection = NSRange(location: nextText.utf16.count - 6, length: 6)
        let expectedLayout = layout(nextText, hidden: hidden)
        expectedLayout.selectedRange.range = selection
        expected.update(expectedLayout)
        expected.layout()
        var calls = 0
        let original = layout("Obsolete concealed message") { [weak view] in
            calls += 1
            next.selectedRange.range = selection
            view?.update(next)
        }
        view.update(original)
        view.layout()
        try click(view)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(view.textLayout === next)
        XCTAssertTrue(original.spoilerRectFrames().isEmpty)
        XCTAssertFalse(next.spoilerRectFrames().isEmpty)
        XCTAssertEqual(next.selectedRange.range, selection)
        assertHiddenContent(view, matches: expected)
        waitForAnimations()
        assertHiddenContent(view, matches: expected)
        XCTAssertEqual(next.selectedRange.range, selection)
    }

    func testRevealCallbackClearingLayoutPreservesCallerStateAndAllowsReuse() throws {
        let view = TextView(), expected = TextView()
        attach(view)
        attach(expected)
        var calls = 0
        let original = layout("Obsolete concealed message") { [weak view] in
            calls += 1
            view?.update(nil)
            view?.selectionWasCleared = true
        }
        view.update(original)
        view.layout()
        try click(view)
        XCTAssertEqual(calls, 1)
        XCTAssertNil(view.textLayout)
        XCTAssertTrue(view.selectionWasCleared)
        XCTAssertTrue(inks(view).isEmpty)
        XCTAssertTrue(view.subviews.compactMap { $0 as? TextView }.isEmpty)
        let replacement = layout("New hidden replacement after clearing")
        view.update(replacement)
        expected.update(layout("New hidden replacement after clearing"))
        expected.layout()
        assertHiddenContent(view, matches: expected)
        waitForAnimations()
        XCTAssertTrue(view.textLayout === replacement)
        assertHiddenContent(view, matches: expected)
    }

    func testOrdinaryRevealStillPrecedesMultipleClickSelection() throws {
        for selectable in [false, true] {
            for count in [1, 2, 3] {
                let view = TextView()
                view.isSelectable = selectable
                attach(view)
                var calls = 0
                let text = layout("Hidden words to reveal") { calls += 1 }
                view.update(text)
                view.layout()
                try click(view, count: count)
                XCTAssertEqual(calls, 1)
                XCTAssertTrue(view.textLayout === text)
                XCTAssertTrue(text.spoilerRectFrames().isEmpty)
                XCTAssertFalse(text.selectedRange.hasSelectText)
            }
        }
        waitForAnimations()
    }
}
