import Cocoa
import XCTest
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

final class FoldingTransitionTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }
    let text = "First quoted line\nSecond quoted line\nThird quoted line\nFourth quoted line\nLast quoted line"
    func layout(_ revealed: Bool) -> FoldingTextLayout {
        FoldingQuoteTests().source(text, revealed: revealed)
    }
    func bind(_ body: ChatLayerMessageTextNode, _ layout: FoldingTextLayout, id: Int = 1, animated: Bool) throws {
        XCTAssertTrue(try body.update(ChatLayerMessageTextPresentation(layout), messageId: id, selectable: true, preservingSelectionGesture: true, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate))
    }
    func finish() {
        let done = expectation(description: "transition completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { done.fulfill() }
        wait(for: [done], timeout: 2)
    }
    func testRevealGeometryAndNativeMaskAnimationMatch() throws {
        for reveal in [true, false] {
            let previous = layout(!reveal), next = layout(reveal)
            let native = makeCandidateFoldingWrapper(previous.blocks[0])
            let body = ChatLayerMessageTextNode(id: "body")
            body.revealBlockAtIndex = { _ in }
            try bind(body, previous, animated: false)
            let node = body.textNodes[0]
            let mask = try XCTUnwrap(node.layer.sublayers?.first?.mask as? CAShapeLayer)
            let oldFrame = node.frame
            updateCandidateFoldingWrapper(native, layout: next.blocks[0], transition: .animated(duration: 0.2, curve: .easeOut))
            try bind(body, next, animated: true)
            let nativeAnimation = native.layer?.sublayers?.compactMap { $0.mask?.animation(forKey: "path") }.first ?? native.layer?.mask?.animation(forKey: "path")
            let expected = try XCTUnwrap(nativeAnimation as? CABasicAnimation)
            let actual = try XCTUnwrap(mask.animation(forKey: "path") as? CABasicAnimation)
            XCTAssertEqual(actual.duration, expected.duration)
            XCTAssertEqual(actual.timingFunction, expected.timingFunction)
            XCTAssertEqual((actual.fromValue as! CGPath).boundingBox, (expected.fromValue as! CGPath).boundingBox)
            XCTAssertEqual((actual.toValue as! CGPath).boundingBox, (expected.toValue as! CGPath).boundingBox)
            XCTAssertEqual((actual.fromValue as! CGPath).boundingBox.size, oldFrame.size)
            XCTAssertEqual((actual.toValue as! CGPath).boundingBox.size, node.frame.size)
            XCTAssertNotNil(node.layer.animation(forKey: "bounds"))
            let arrow = try XCTUnwrap(node.layer.sublayers?.last)
            XCTAssertNotNil(arrow.animation(forKey: "position"))
            let nativeArrow = try XCTUnwrap(native.layer?.sublayers?.first { $0.bounds.size == NSSize(width: 10, height: 7) })
            XCTAssertEqual(arrow.anchorPoint, nativeArrow.anchorPoint)
            let arrowMotion = try XCTUnwrap(arrow.animation(forKey: "position") as? CABasicAnimation)
            let nativeMotion = try XCTUnwrap(nativeArrow.animation(forKey: "position") as? CABasicAnimation)
            XCTAssertEqual((arrowMotion.fromValue as? NSValue)?.pointValue, (nativeMotion.fromValue as? NSValue)?.pointValue)
            XCTAssertEqual((arrowMotion.toValue as? NSValue)?.pointValue, (nativeMotion.toValue as? NSValue)?.pointValue)
            XCTAssertNotNil(arrow.animation(forKey: "contents"))
            if !reveal { XCTAssertNil(node.drawingLayer.mask) }
            finish()
            XCTAssertEqual(node.drawingLayer.mask == nil, reveal)
            let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
            try scene.root.setChildren([body])
            let reference = View(frame: scene.frame)
            reference.addSubview(native)
            XCTAssertEqual(ViewSnapshot.render(reference, scale: 2).differingPixels(from: ViewSnapshot.render(scene, scale: 2), tolerance: 0), 0)
        }
    }
    func testDelayedMaskDoesNotSurviveAnotherBinding() throws {
        for replacement in ["expanded", "plain", "removed"] {
            let body = ChatLayerMessageTextNode(id: "body")
            body.revealBlockAtIndex = { _ in }
            try bind(body, layout(true), animated: false)
            try bind(body, layout(false), animated: true)
            let node = body.textNodes[0]
            XCTAssertNil(node.drawingLayer.mask)
            if replacement == "expanded" { try bind(body, layout(true), animated: false) }
            else if replacement == "plain" { try bind(body, MessageTextTests().layout(["plain"]), animated: false) }
            else { try bind(body, MessageTextTests().layout([]), animated: false) }
            finish()
            XCTAssertNil(node.drawingLayer.mask, replacement)
        }
    }
    func testPendingCollapseDoesNotRetainRemovedNode() throws {
        weak var weakNode: ChatLayerTextNode?
        autoreleasepool {
            let body = ChatLayerMessageTextNode(id: "body")
            body.revealBlockAtIndex = { _ in }
            try! bind(body, layout(true), animated: false)
            try! bind(body, layout(false), animated: true)
            weakNode = body.textNodes[0]
        }
        XCTAssertNil(weakNode)
        finish()
        XCTAssertNil(weakNode)
    }
    func testFollowingBlockAnimatesAndNewMessageDoesNotAnimate() throws {
        let body = ChatLayerMessageTextNode(id: "body")
        body.revealBlockAtIndex = { _ in }
        func blocks(_ revealed: Bool) -> FoldingTextLayout {
            FoldingTextLayout(blocks: layout(revealed).blocks + MessageTextTests().layout(["After quote"]).blocks)
        }
        try bind(body, blocks(false), animated: false)
        try bind(body, blocks(true), animated: true)
        XCTAssertNotNil(body.textNodes[1].layer.animation(forKey: "position"))
        try bind(body, blocks(false), id: 2, animated: true)
        XCTAssertNil(body.textNodes[0].layer.animation(forKey: "bounds"))
        XCTAssertNil(body.textNodes[1].layer.animation(forKey: "position"))
    }
    func testImmediateRebindClearsFollowingBlockAnimations() throws {
        let body = ChatLayerMessageTextNode(id: "body")
        body.revealBlockAtIndex = { _ in }
        let first = FoldingTextLayout(blocks: layout(false).blocks + MessageTextTests().layout(["After quote"]).blocks)
        let second = FoldingTextLayout(blocks: layout(true).blocks + MessageTextTests().layout(["After quote"]).blocks)
        try bind(body, first, animated: false)
        try bind(body, second, animated: true)
        XCTAssertNotNil(body.textNodes[1].layer.animation(forKey: "position"))
        try bind(body, first, animated: false)
        XCTAssertNil(body.textNodes[0].layer.animation(forKey: "bounds"))
        XCTAssertNil(body.textNodes[1].layer.animation(forKey: "position"))
        XCTAssertNotNil(body.textNodes[0].drawingLayer.mask)
    }
    func testRapidRevealCancelsPreviousMaskAcrossSeveralBlocks() throws {
        let body = ChatLayerMessageTextNode(id: "body")
        body.revealBlockAtIndex = { _ in }
        func blocks(_ revealed: Bool) -> FoldingTextLayout {
            FoldingTextLayout(blocks: layout(revealed).blocks + layout(!revealed).blocks)
        }
        try bind(body, blocks(true), animated: false)
        for reveal in [false, true, false, true] { try bind(body, blocks(reveal), animated: true) }
        finish()
        XCTAssertNil(body.textNodes[0].drawingLayer.mask)
        XCTAssertNotNil(body.textNodes[1].drawingLayer.mask)
        XCTAssertEqual(body.textNodes[1].frame.minY, layout(true).size.height)
    }

}
