import Cocoa
import XCTest
import SwiftSignalKit
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

final class MessageBindingTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func fixture(_ source: FoldingTextLayout) throws -> (ChatLayerSceneView, ChatLayerMessageTextNode) {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        let body = ChatLayerMessageTextNode(id: "body")
        try scene.root.setChildren([body])
        try body.update(ChatLayerMessageTextPresentation(source), messageId: 1, selectable: true)
        return (scene, body)
    }

    private func source(_ count: Int, prefix: String) -> FoldingTextLayout {
        MessageTextTests().layout((0..<count).map { "\(prefix) block \($0) with text" })
    }

    private var unsupported: ChatLayerMessageTextPresentation {
        ChatLayerMessageTextPresentation(blocks: [], size: .zero, nativeFeatures: [.spoiler], requiresRevealAction: false)
    }

    private func pendingMenu(_ node: ChatLayerTextNode, dispose: @escaping () -> Void) {
        let layout = node.textLayout!
        layout.alwaysStaticItems = false
        layout.interactions.topWindow = { Signal { _ in ActionDisposable(action: dispose) } }
        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
        XCTAssertTrue(node.requestMenu(at: NSPoint(x: 5, y: 5), event: event))
    }

    private func bind(_ body: ChatLayerMessageTextNode?, _ presentation: ChatLayerMessageTextPresentation, id: Int) {
        do { _ = try body?.update(presentation, messageId: id, selectable: true) }
        catch { XCTFail("Reentrant binding failed: \(error)") }
    }

    private func assertBinding(_ body: ChatLayerMessageTextNode, _ scene: ChatLayerSceneView, _ source: FoldingTextLayout, id: Int = 3, file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = ChatLayerMessageTextPresentation(source)
        XCTAssertEqual(body.textNodes.count, source.blocks.count, file: file, line: line)
        XCTAssertEqual(body.children.count, source.blocks.count, file: file, line: line)
        XCTAssertEqual(body.frame.size, expected.size, file: file, line: line)
        for (index, pair) in zip(body.textNodes, expected.blocks).enumerated() {
            let (node, block) = pair
            XCTAssertTrue(node.textLayout === block.layout, "Block \(index)", file: file, line: line)
            XCTAssertEqual(node.frame, block.frame, file: file, line: line)
            XCTAssertTrue(node.parent === body, file: file, line: line)
            XCTAssertTrue(node.scene === scene, file: file, line: line)
            XCTAssertTrue(node.layer.superlayer === body.layer, file: file, line: line)
            XCTAssertTrue(scene.node(id: node.id) === node, file: file, line: line)
        }
        if body.textNodes.count == source.blocks.count, let first = body.textNodes.first {
            first.setExternalSelection(NSRange(location: 0, length: 2))
            try body.update(expected, messageId: id, selectable: true)
            XCTAssertEqual(first.textLayout?.selectedRange.range, NSRange(location: 0, length: 2), file: file, line: line)
        }
    }

    func testRetainedBlockMenuCancellationKeepsNewestWholeMessage() throws {
        for count in [1, 3] {
            let (scene, body) = try fixture(source(2, prefix: "Original"))
            let newest = source(count, prefix: "Newest")
            pendingMenu(body.textNodes[0]) { [weak self, weak body] in self?.bind(body, ChatLayerMessageTextPresentation(newest), id: 3) }
            XCTAssertFalse(try body.update(ChatLayerMessageTextPresentation(source(2, prefix: "Superseded")), messageId: 2, selectable: true))
            try assertBinding(body, scene, newest)
        }
    }

    func testRemovingBlockCancelsBeforeMutatingHierarchy() throws {
        let (scene, body) = try fixture(source(3, prefix: "Original"))
        let newest = source(4, prefix: "Newest")
        pendingMenu(body.textNodes[2]) { [weak self, weak body] in self?.bind(body, ChatLayerMessageTextPresentation(newest), id: 3) }
        XCTAssertFalse(try body.update(ChatLayerMessageTextPresentation(source(1, prefix: "Superseded")), messageId: 1, selectable: true))
        try assertBinding(body, scene, newest)
    }

    func testFallbackCancellationCannotEraseNewSupportedMessage() throws {
        let (scene, body) = try fixture(source(2, prefix: "Original"))
        let newest = source(3, prefix: "Newest")
        pendingMenu(body.textNodes[1]) { [weak self, weak body] in self?.bind(body, ChatLayerMessageTextPresentation(newest), id: 3) }
        XCTAssertFalse(try body.update(unsupported, messageId: 2, selectable: true))
        try assertBinding(body, scene, newest)
    }

    func testSupportedUpdateCannotOverwriteNewFallback() throws {
        let (scene, body) = try fixture(source(2, prefix: "Original"))
        let fallback = unsupported
        pendingMenu(body.textNodes[0]) { [weak self, weak body] in self?.bind(body, fallback, id: 3) }
        XCTAssertFalse(try body.update(ChatLayerMessageTextPresentation(source(3, prefix: "Superseded")), messageId: 2, selectable: true))
        XCTAssertTrue(body.textNodes.isEmpty)
        XCTAssertTrue(body.children.isEmpty)
        XCTAssertEqual(body.frame.size, .zero)
        XCTAssertTrue(scene.root.children.first === body)
    }

    func testSelectionNotificationKeepsNewMessageAndSiblingState() throws {
        let (scene, body) = try fixture(source(3, prefix: "Original"))
        let newest = source(2, prefix: "Newest")
        let first = body.textNodes[0]
        first.setExternalSelection(NSRange(location: 0, length: 4))
        var notified = false
        first.onSelectionChanged = { [weak self, weak body] range in
            if !notified, range.location == NSNotFound {
                notified = true
                self?.bind(body, ChatLayerMessageTextPresentation(newest), id: 3)
            }
        }
        XCTAssertFalse(try body.update(ChatLayerMessageTextPresentation(source(3, prefix: "Superseded")), messageId: 2, selectable: true))
        try assertBinding(body, scene, newest)
    }

    func testCodeHeaderCallbackSupersedesWholeMessageUpdate() throws {
        let (scene, body) = try fixture(source(2, prefix: "Original"))
        let newest = source(3, prefix: "Newest")
        let header = ChatLayerButtonNode(id: "header", label: "Copy", action: {})
        try body.textNodes[0].setChildren([header])
        var notified = false
        header.onStateChanged = { [weak self, weak body] _, _, _ in
            if !notified { notified = true; self?.bind(body, ChatLayerMessageTextPresentation(newest), id: 3) }
        }
        XCTAssertFalse(try body.update(ChatLayerMessageTextPresentation(source(1, prefix: "Superseded")), messageId: 2, selectable: true))
        try assertBinding(body, scene, newest)
    }

    func testSameMessageHoverExitCannotOverwriteNewBlocks() throws {
        let original = FoldingTextLayout(blocks: [FoldingTextLayout.ViewLayout(text: TextTests().layout("Link original"))])
        let (scene, body) = try fixture(original)
        let newest = source(3, prefix: "Newest")
        original.blocks[0].text.interactions.hoverOnLink = { [weak self, weak body] value in
            if case .exited = value { self?.bind(body, ChatLayerMessageTextPresentation(newest), id: 1) }
        }
        scene.handlePointer(.moved, at: NSPoint(x: 5, y: 5))
        XCTAssertFalse(try body.update(ChatLayerMessageTextPresentation(source(2, prefix: "Superseded")), messageId: 1, selectable: true))
        try assertBinding(body, scene, newest, id: 1)
    }

    func testNonselectableUpdateCannotOverrideNewSelectableMessage() throws {
        let (scene, body) = try fixture(source(2, prefix: "Original"))
        let newest = source(2, prefix: "Newest")
        pendingMenu(body.textNodes[0]) { [weak self, weak body] in self?.bind(body, ChatLayerMessageTextPresentation(newest), id: 3) }
        XCTAssertFalse(try body.update(ChatLayerMessageTextPresentation(source(2, prefix: "Superseded")), messageId: 1, selectable: false))
        try assertBinding(body, scene, newest)
        XCTAssertTrue(body.textNodes.allSatisfy(\.isSelectable))
    }
}
