import XCTest
import AppKit
@testable import TGUIKit

final class TextViewUpdateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func layout(_ text: String) -> TextViewLayout {
        let layout = TextViewLayout(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black]), maximumNumberOfLines: 2)
        layout.measure(width: 200)
        return layout
    }

    func testRepeatedUpdatesKeepTheLayerOrder() {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 300, 100), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = NSView(frame: NSMakeRect(0, 0, 300, 100))
        let view = TextView(frame: NSMakeRect(0, 0, 200, 40))
        _ = view.embeddedContainer
        window.contentView?.addSubview(view)
        let first = self.layout("Hello world")
        view.update(first)
        let order = view.layer?.sublayers?.map { ObjectIdentifier($0) }
        XCTAssertTrue(view.layer!.sublayers!.first! is TextViewLayer)
        XCTAssertTrue(view.layer?.sublayers?[1] === view.embeddedContainer)
        for i in 0 ..< 20 {
            view.update(i % 2 == 0 ? first : self.layout("Message \(i)"))
            XCTAssertEqual(view.layer?.sublayers?.map { ObjectIdentifier($0) }, order)
        }
        XCTAssertNil(view.layer?.mask)
    }

    func testUpdateCost() {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 300, 100), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = NSView(frame: NSMakeRect(0, 0, 300, 100))
        let views = (0 ..< 20).map { _ in TextView(frame: NSMakeRect(0, 0, 200, 40)) }
        views.forEach { window.contentView?.addSubview($0) }
        let layouts = (0 ..< 20).map { self.layout("Chat list preview text number \($0) with a few words") }
        let start = CFAbsoluteTimeGetCurrent()
        for round in 0 ..< 1000 {
            for (i, view) in views.enumerated() {
                view.update(layouts[(i + round) % layouts.count])
                view.layoutSubtreeIfNeeded()
            }
            CATransaction.flush()
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        print(String(format: "TextViewUpdateTests: 20000 update+layout calls %.1f ms (%.2f µs each)", elapsed * 1000, elapsed / 20000 * 1e6))
    }
}
