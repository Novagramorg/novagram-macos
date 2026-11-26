import AppKit
import XCTest
@testable import TGUIKit

final class WindowResponderTests: XCTestCase {
    func testTypingPreservesTheActiveTextEditorAndRestoresDefaultFocusAfterItLeaves() throws {
        TGUIKitTestBootstrap.install()
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let composer = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        let field = NSTextField(frame: NSRect(x: 0, y: 120, width: 200, height: 30))
        let textarea = NSTextView(frame: NSRect(x: 210, y: 120, width: 180, height: 100))
        window.contentView?.addSubview(composer)
        window.contentView?.addSubview(field)
        window.contentView?.addSubview(textarea)
        window.set(responder: { composer }, with: composer, priority: .medium)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18))
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor())
        window.applyResponderIfNeeded(event)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertTrue(window.makeFirstResponder(textarea))
        window.applyResponderIfNeeded(event)
        XCTAssertTrue(window.firstResponder === textarea)
        XCTAssertTrue(window.makeFirstResponder(nil))
        window.applyResponderIfNeeded(event)
        XCTAssertTrue(window.firstResponder === composer)
    }
}
