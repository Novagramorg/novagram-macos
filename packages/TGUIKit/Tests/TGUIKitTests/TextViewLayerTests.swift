import XCTest
import AppKit
@testable import TGUIKit

final class TextViewLayerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func layout(_ value: String) -> TextViewLayout {
        let layout = TextViewLayout(NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black]))
        layout.measure(width: 180)
        return layout
    }

    func testClearingReleasesLayoutAndResetsTextSize() {
        let layer = TextViewLayer()
        weak var previous: TextViewLayout?
        autoreleasepool {
            let value = layout("A decorative label")
            previous = value
            layer.update(value)
            XCTAssertEqual(layer.textSize, value.layoutSize)
        }
        XCTAssertNotNil(previous)
        layer.update(nil)
        XCTAssertNil(previous)
        XCTAssertNil(layer.textLayout)
        XCTAssertEqual(layer.textSize, .zero)
    }

    func testRebindingMutableLayoutInvalidatesDrawingWithoutChangingSelection() {
        let layer = TextViewLayer()
        let value = layout("A decorative label")
        value.selectedRange = TextSelectedRange(range: NSRange(location: 2, length: 3))
        layer.bounds = CGRect(origin: .zero, size: value.layoutSize)
        layer.update(value)
        layer.display()
        value.maxGlyphDrawCount = 2
        layer.update(value)
        XCTAssertTrue(layer.needsDisplay())
        XCTAssertEqual(value.selectedRange.range, NSRange(location: 2, length: 3))
    }

    func testCopyPreservesDrawingInputs() {
        let layer = TextViewLayer()
        let value = layout("مرحبا Hello 👩🏽‍💻")
        layer.contentsScale = 3
        layer.canDrawBlocks = false
        layer.update(value, size: NSSize(width: 200, height: 40))
        let copy = TextViewLayer(layer: layer)
        XCTAssertEqual(copy.contentsScale, 3)
        XCTAssertEqual(copy.textSize, layer.textSize)
        XCTAssertTrue(copy.textLayout === value)
        XCTAssertFalse(copy.canDrawBlocks)
    }
}

extension TextViewLayerTests {
    func testSelectableLayerCopiesSelectionPresentationInputs() {
        let layer = TextViewLayer()
        layer.update(layout("Selected text"))
        layer.isTextSelectable = true
        layer.isKeyWindow = true
        let copy = TextViewLayer(layer: layer)
        XCTAssertTrue(copy.isTextSelectable)
        XCTAssertTrue(copy.isKeyWindow)
        XCTAssertFalse(TextViewLayer().isTextSelectable)
    }

    func testWindowFocusInvalidatesOnlySelectablePrimarySelection() {
        let layer = TextViewLayer()
        let value = layout("Selected text")
        layer.bounds = CGRect(origin: .zero, size: value.layoutSize)
        layer.update(value)
        layer.isTextSelectable = true
        layer.display()
        layer.isKeyWindow = true
        XCTAssertFalse(layer.needsDisplay())
        value.selectedRange.range = NSRange(location: 0, length: 4)
        layer.isKeyWindow = false
        XCTAssertTrue(layer.needsDisplay())
        layer.isTextSelectable = false
        layer.display()
        layer.isKeyWindow = true
        XCTAssertFalse(layer.needsDisplay())
    }
}
