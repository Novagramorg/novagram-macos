import Quartz
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class QuartzCompatibilityTests: XCTestCase {
    func testTextLayerSelectionWithImageKitImported() {
        let layer = TextViewLayer()
        XCTAssertFalse(layer.isTextSelectable)
        layer.isTextSelectable = true
        XCTAssertTrue(layer.isTextSelectable)
    }

    func testTextNodeSelectionWithImageKitImported() {
        TGUIKitTestBootstrap.install()
        let node = ChatLayerTextNode(id: "text", selectable: false)
        XCTAssertFalse(node.isSelectable)
        node.isSelectable = true
        XCTAssertTrue(node.isSelectable)
        XCTAssertTrue(node.drawingLayer.isTextSelectable)
        XCTAssertTrue(node.acceptsKeyboardFocus)
        XCTAssertTrue(node.acceptsPointerEvents)
        node.isSelectable = false
        XCTAssertFalse(node.isSelectable)
        XCTAssertFalse(node.drawingLayer.isTextSelectable)
        XCTAssertFalse(node.acceptsKeyboardFocus)
        XCTAssertFalse(node.acceptsPointerEvents)
    }
}
