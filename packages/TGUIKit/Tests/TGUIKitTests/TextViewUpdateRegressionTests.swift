import AppKit
import XCTest
@testable import TGUIKit

private final class UpdateCountingLayer: CALayer {
    var insertions = 0
    override func insertSublayer(_ layer: CALayer, at index: UInt32) {
        insertions += 1
        super.insertSublayer(layer, at: index)
    }
}

private final class UpdateCountingTextView: TextView {
    var additions = 0
    var removals = 0
    var redraws = 0
    override func addToolTip(_ rect: NSRect, owner: Any, userData data: UnsafeMutableRawPointer?) -> NSView.ToolTipTag {
        additions += 1
        return super.addToolTip(rect, owner: owner, userData: data)
    }
    override func removeAllToolTips() {
        removals += 1
        super.removeAllToolTips()
    }
    override func setNeedsDisplayLayer() {
        redraws += 1
        super.setNeedsDisplayLayer()
    }
}

final class TextViewUpdateRegressionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func makeLayout(_ text: String = "Message link and hidden text 中文 👋", link: String? = nil, spoiler: Bool = false, width: CGFloat = 220) -> TextViewLayout {
        let string = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        if let link { string.addAttribute(.link, value: link, range: NSRange(location: 0, length: 7)) }
        if spoiler { string.addAttribute(TextInputAttributes.spoiler, value: true, range: NSRange(location: 8, length: 10)) }
        let layout = TextViewLayout(string, disableTooltips: false)
        layout.interactions.resolveLink = { $0 as? String }
        layout.measure(width: width)
        return layout
    }

    func testRepeatedUpdatesDoNotReinsertDrawingLayersAndStillRedraw() {
        let view = UpdateCountingTextView()
        _ = view.embeddedContainer
        let root = UpdateCountingLayer()
        view.layer = root
        let layout = makeLayout()
        view.update(layout)
        view.layoutSubtreeIfNeeded()
        let original = root.sublayers!.map(ObjectIdentifier.init)
        root.insertions = 0
        let redraws = view.redraws
        for _ in 0..<10 { view.update(layout); view.layoutSubtreeIfNeeded() }
        XCTAssertEqual(root.insertions, 0)
        XCTAssertEqual(root.sublayers!.map(ObjectIdentifier.init), original)
        XCTAssertGreaterThan(view.redraws, redraws)
        let decoration = CALayer()
        root.insertSublayer(decoration, at: 0)
        view.update(layout)
        XCTAssertEqual(root.sublayers!.prefix(2).map(ObjectIdentifier.init), Array(original.prefix(2)))
        XCTAssertTrue(decoration.superlayer === root)
    }

    func testHighlightLayerOrderAndReplacementStayCorrect() {
        let view = TextView()
        _ = view.embeddedContainer
        let layout = makeLayout()
        view.update(layout)
        let drawLayer = view.layer!.sublayers![0]
        view.highlight(text: "Message", color: .yellow)
        view.update(layout)
        XCTAssertTrue(view.layer!.sublayers![1] === view.embeddedContainer)
        XCTAssertTrue(view.layer!.sublayers![2] === drawLayer)
        let order = view.layer!.sublayers!.map(ObjectIdentifier.init)
        for _ in 0..<5 { view.update(layout) }
        XCTAssertEqual(view.layer!.sublayers!.map(ObjectIdentifier.init), order)
        view.update(makeLayout("Another message"))
        XCTAssertTrue(view.layer!.sublayers![0] === drawLayer)
        XCTAssertEqual(view.layer!.sublayers!.count, 2)
    }

    func testTooltipGeometryReuseStillResolvesChangedLink() {
        let view = UpdateCountingTextView()
        let first = makeLayout(link: "https://first.example")
        view.update(first)
        let additions = view.additions
        let removals = view.removals
        XCTAssertGreaterThan(additions, 0)
        let second = makeLayout(link: "https://second.example")
        view.update(second)
        XCTAssertEqual(view.additions, additions)
        XCTAssertEqual(view.removals, removals)
        XCTAssertEqual(view.view(view, stringForToolTip: 0, point: NSPoint(x: 5, y: 5), userData: nil), "https://second.example")
        second.measure(width: 35)
        view.update(second)
        XCTAssertGreaterThan(view.additions, additions)
        view.update(makeLayout())
        XCTAssertEqual(view.removals, removals + 2)
    }

    func testExternalTooltipChangesInvalidateManagedRectangles() {
        let view = UpdateCountingTextView()
        let layout = makeLayout(link: "https://example.com")
        view.update(layout)
        var additions = view.additions
        view.removeAllToolTips()
        view.update(layout)
        XCTAssertGreaterThan(view.additions, additions)
        let tag = view.addToolTip(view.bounds, owner: view, userData: nil)
        additions = view.additions
        view.update(layout)
        XCTAssertGreaterThan(view.additions, additions)
        additions = view.additions
        view.removeToolTip(tag)
        view.update(layout)
        XCTAssertGreaterThan(view.additions, additions)
    }

    func testPlainUpdatesDoNotRebuildEmptyTooltipList() {
        let view = UpdateCountingTextView()
        view.update(makeLayout())
        let removals = view.removals
        for _ in 0..<10 { view.update(makeLayout()) }
        XCTAssertEqual(view.removals, removals)
    }

    func testSelectionInheritanceMutableLayoutAndNilUpdate() {
        let view = UpdateCountingTextView()
        let first = makeLayout()
        first.selectedRange = TextSelectedRange(range: NSRange(location: 0, length: 4))
        view.update(first)
        let second = makeLayout()
        view.update(second, origin: NSPoint(x: 12, y: 18))
        XCTAssertEqual(second.selectedRange.range, first.selectedRange.range)
        XCTAssertEqual(view.frame.origin, NSPoint(x: 12, y: 18))
        second.measure(width: 80)
        view.update(second)
        XCTAssertEqual(view.frame.size, second.layoutSize)
        view.update(makeLayout("Changed"))
        XCTAssertEqual(view.textLayout?.selectedRange.range.location, NSNotFound)
        view.update(nil)
        XCTAssertNil(view.textLayout)
        XCTAssertEqual(view.frame, .zero)
    }

    func testSpoilerVisibilityTracksSelectionRevealAndNewEmbeddedLayers() {
        let view = TextView()
        let layout = makeLayout(spoiler: true)
        view.update(layout)
        let rect = layout.spoilerRects().first!.0
        let embedded = CALayer()
        embedded.frame = NSRect(x: rect.midX - 1, y: rect.midY - 1, width: 2, height: 2)
        view.addEmbeddedLayer(embedded)
        view.update(layout)
        XCTAssertEqual(embedded.opacity, 0)
        XCTAssertFalse(view.subviews.filter { $0 is InvisibleInkDustView }.isEmpty)
        layout.selectedRange = TextSelectedRange(range: NSRange(location: 8, length: 3))
        view.update(layout)
        let expected: Float = layout.spoilerRects().contains { $0.0.intersects(NSRect(x: embedded.frame.midX, y: embedded.frame.midY, width: 1, height: 1)) } ? 0 : 1
        XCTAssertEqual(embedded.opacity, expected)
        layout.revealSpoiler()
        view.update(layout)
        XCTAssertEqual(embedded.opacity, 1)
        XCTAssertTrue(view.subviews.filter { $0 is InvisibleInkDustView }.isEmpty)
        embedded.opacity = 0
        view.checkEmbeddedUnderSpoiler()
        XCTAssertEqual(embedded.opacity, 1)
    }

    func testUnchangedBaseViewSkipsLayoutButRepairsExternalGeometry() {
        let view = TextView()
        let layout = makeLayout()
        view.update(layout)
        view.layoutSubtreeIfNeeded()
        XCTAssertFalse(view.needsLayout)
        view.update(layout)
        XCTAssertFalse(view.needsLayout)
        view.embeddedContainer.frame = .zero
        view.update(layout)
        XCTAssertTrue(view.needsLayout)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.embeddedContainer.frame, view.bounds)
        let draw = view.layer!.sublayers![0]
        draw.bounds = .zero
        view.update(layout)
        XCTAssertTrue(view.needsLayout)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(draw.bounds, view.bounds.insetBy(dx: -2, dy: -3))
        layout.measure(width: 70)
        view.update(layout)
        view.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.frame.size, layout.layoutSize)
        XCTAssertEqual(draw.frame, view.bounds.insetBy(dx: -2, dy: -3))
    }

    func testSubclassAndCustomLayoutCallbacksContinueOnEveryUpdate() {
        let subclass = UpdateCountingTextView()
        subclass.update(makeLayout())
        subclass.layoutSubtreeIfNeeded()
        subclass.update(makeLayout())
        XCTAssertTrue(subclass.needsLayout)
        let view = TextView()
        var calls = 0
        view.customHandler.layout = { _ in calls += 1 }
        for _ in 0..<5 { view.update(makeLayout()); view.layoutSubtreeIfNeeded() }
        XCTAssertEqual(calls, 5)
    }

    func testBlurAndDrawingLockRestoreLayerHierarchy() {
        let view = TextView()
        _ = view.embeddedContainer
        let layout = makeLayout()
        view.update(layout)
        let root = view.layer!
        let drawLayer = root.sublayers![0]
        view.blurBackground = .red
        view.update(layout)
        XCTAssertFalse(drawLayer.superlayer === root)
        XCTAssertTrue(root.masksToBounds)
        view.lockDrawingLayer = true
        view.blurBackground = nil
        view.update(layout)
        XCTAssertFalse(drawLayer.superlayer === root)
        view.lockDrawingLayer = false
        view.update(layout)
        XCTAssertTrue(root.sublayers![0] === drawLayer)
        XCTAssertTrue(root.sublayers![1] === view.embeddedContainer)
        XCTAssertFalse(root.masksToBounds)
        XCTAssertNil(root.mask)
        XCTAssertTrue(view.subviews.isEmpty)
    }
}
