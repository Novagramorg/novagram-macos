import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class FullLabelTooltipTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func testFullLabelTooltipRegistersMovesReusesAndClearsWithoutLinks() throws {
        let scene = LinkInteractionTests.TrackingScene(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let node = ChatLayerTextNode(id: "name", selectable: false)
        try scene.root.setChildren([node])
        node.update(TextTests().layout("Hidden sender"))
        node.toolTip = "Hidden sender description"
        let entry = try XCTUnwrap(scene.entries.first)
        let owner = try XCTUnwrap(entry.value.1 as? ChatLayerTextLinkState)
        XCTAssertEqual(owner.view(scene, stringForToolTip: entry.key, point: NSPoint(x: 2, y: 2), userData: nil), "Hidden sender description")
        XCTAssertEqual(entry.value.0, node.frame)
        let count = scene.additions
        node.toolTip = "Hidden sender description"
        node.update(TextTests().layout("Hidden sender"))
        scene.layout()
        XCTAssertEqual(scene.additions, count)
        node.frame.origin = NSPoint(x: 30, y: 20)
        scene.layout()
        XCTAssertEqual(scene.entries.first?.value.0, node.frame)
        scene.removeAllToolTips()
        node.update(node.textLayout)
        XCTAssertEqual(scene.entries.count, 1)
        node.isHidden = true
        XCTAssertEqual(owner.view(scene, stringForToolTip: entry.key, point: .zero, userData: nil), "")
        node.isHidden = false
        node.toolTip = nil
        XCTAssertTrue(scene.entries.isEmpty)
        node.toolTip = "Restored"
        try scene.root.setChildren([])
        XCTAssertTrue(scene.entries.isEmpty)
    }
}
