import Cocoa
import XCTest
import SwiftSignalKit
import TGUIKit
@testable import ChatLayerEngine

private final class NativeLinkView: TextView {
    override func mouseInside() -> Bool { true }
}

final class LinkInteractionTests: XCTestCase {
    final class TrackingScene: ChatLayerSceneView {
        var entries: [NSView.ToolTipTag: (NSRect, AnyObject)] = [:]
        var additions = 0
        override func addToolTip(_ rect: NSRect, owner: Any, userData data: UnsafeMutableRawPointer?) -> NSView.ToolTipTag {
            let tag = super.addToolTip(rect, owner: owner, userData: data)
            entries[tag] = (rect, owner as AnyObject)
            additions += 1
            return tag
        }
        override func removeToolTip(_ tag: NSView.ToolTipTag) {
            entries.removeValue(forKey: tag)
            super.removeToolTip(tag)
        }
        override func removeAllToolTips() {
            entries.removeAll()
            super.removeAllToolTips()
        }
    }

    private enum ValueLink { case peer(String) }
    private struct Pair {
        let native: NativeLinkView
        let nativeLayout: TextViewLayout
        let scene: TrackingScene
        let node: ChatLayerTextNode
        let layerLayout: TextViewLayout
    }
    private var windows: [NSWindow] = []

    override func setUp() { TGUIKitTestBootstrap.install() }
    override func tearDown() {
        windows.forEach { $0.contentView = nil; $0.close() }
        windows.removeAll()
    }

    private func layout(valueLink: Bool = false, sameURL: Bool = false, longText: Bool = false, tooltips: Bool = true) -> TextViewLayout {
        let text = NSMutableAttributedString(string: "First link Next link", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        let first = "https://example.com/%F0%9F%A6%86" + (longText ? String(repeating: "long", count: 30) : "")
        text.addAttribute(.link, value: valueLink ? ValueLink.peer("first") as Any : first as Any, range: NSRange(location: 0, length: 10))
        text.addAttribute(.link, value: valueLink ? ValueLink.peer("second") as Any : (sameURL ? first : "https://second.example/") as Any, range: NSRange(location: 11, length: 9))
        let layout = TextViewLayout(text, disableTooltips: !tooltips)
        layout.interactions.resolveLink = { $0 as? String }
        layout.measure(width: 240)
        return layout
    }

    private func attach(_ view: NSView) {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 320, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = View(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        window.contentView = root
        root.addSubview(view)
        windows.append(window)
    }

    private func pair(valueLink: Bool = false, sameURL: Bool = false, longText: Bool = false, tooltips: Bool = true) throws -> Pair {
        let native = NativeLinkView(), nativeLayout = layout(valueLink: valueLink, sameURL: sameURL, longText: longText, tooltips: tooltips)
        native.update(nativeLayout)
        attach(native)
        let scene = TrackingScene(frame: NSRect(x: 0, y: 0, width: 280, height: 100))
        let node = ChatLayerTextNode(id: "text", selectable: true)
        try scene.root.setChildren([node])
        let layerLayout = layout(valueLink: valueLink, sameURL: sameURL, longText: longText, tooltips: tooltips)
        node.update(layerLayout, knownHasLinks: true, frame: NSRect(origin: NSPoint(x: 13, y: 7), size: layerLayout.layoutSize))
        attach(scene)
        return Pair(native: native, nativeLayout: nativeLayout, scene: scene, node: node, layerLayout: layerLayout)
    }

    private func point(_ layout: TextViewLayout, second: Bool = false) -> NSPoint {
        for x in stride(from: CGFloat(1), to: layout.layoutSize.width, by: 1) {
            let point = NSPoint(x: x, y: 5)
            if layout.link(at: point)?.2.location == (second ? 11 : 0) { return point }
        }
        XCTFail("Missing link hit point")
        return .zero
    }

    private func hover(_ pair: Pair, second: Bool = false, outside: Bool = false) {
        var nativePoint = point(pair.nativeLayout, second: second)
        var layerPoint = point(pair.layerLayout, second: second)
        if outside { nativePoint.x = 300; layerPoint.x = 300 }
        let event = NSEvent.mouseEvent(with: .mouseMoved, location: pair.native.convert(nativePoint, to: nil), modifierFlags: [], timestamp: 0, windowNumber: pair.native.window?.windowNumber ?? 0, context: nil, eventNumber: 1, clickCount: 0, pressure: 0)!
        pair.native.cursorUpdate(with: event)
        _ = pair.scene.handlePointer(.moved, at: pair.node.layer.convert(layerPoint, to: pair.scene.root.layer))
    }

    private func passDeadline() {
        let done = expectation(description: "Preview deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { done.fulfill() }
        wait(for: [done], timeout: 3)
    }

    func testDelayedPreviewAndRepeatedMovementMatchNativeForStringAndValueLinks() throws {
        for valueLink in [false, true] {
            let pair = try pair(valueLink: valueLink)
            let started = expectation(description: "Both previews")
            started.expectedFulfillmentCount = 2
            var starts = [0, 0], cancellations = [0, 0]
            for (index, layout) in [pair.nativeLayout, pair.layerLayout].enumerated() {
                layout.interactions.longHoverOnLink = { _, owner in
                    XCTAssertTrue(owner === (index == 0 ? pair.native as NSView : pair.scene))
                    starts[index] += 1
                    started.fulfill()
                    return ActionDisposable { cancellations[index] += 1 }
                }
            }
            for _ in 0..<30 { hover(pair) }
            XCTAssertEqual(starts, [0, 0])
            wait(for: [started], timeout: 3)
            for _ in 0..<30 { hover(pair) }
            XCTAssertEqual(starts, [1, 1])
            XCTAssertEqual(cancellations, [0, 0])
            hover(pair, outside: true)
            XCTAssertEqual(cancellations, [1, 1])
        }
    }

    func testMovingToAnotherOccurrenceOfSameURLKeepsPreviewLikeNative() throws {
        let pair = try pair(sameURL: true)
        let started = expectation(description: "Both previews")
        started.expectedFulfillmentCount = 2
        var starts = [0, 0], cancellations = [0, 0]
        for (index, layout) in [pair.nativeLayout, pair.layerLayout].enumerated() {
            layout.interactions.longHoverOnLink = { _, _ in
                starts[index] += 1
                if starts[index] == 1 { started.fulfill() }
                return ActionDisposable { cancellations[index] += 1 }
            }
        }
        hover(pair)
        wait(for: [started], timeout: 3)
        hover(pair, second: true)
        passDeadline()
        XCTAssertEqual(starts, [1, 1])
        XCTAssertEqual(cancellations, [0, 0])
        hover(pair, outside: true)
        XCTAssertEqual(cancellations, [1, 1])
    }

    func testDifferentLinkAndReentryRestartPreviewsLikeNative() throws {
        let pair = try pair()
        var starts = [0, 0], cancellations = [0, 0]
        for (index, layout) in [pair.nativeLayout, pair.layerLayout].enumerated() {
            layout.interactions.longHoverOnLink = { _, _ in
                starts[index] += 1
                return ActionDisposable { cancellations[index] += 1 }
            }
        }
        hover(pair)
        passDeadline()
        XCTAssertEqual(starts, [1, 1])
        hover(pair, second: true)
        XCTAssertEqual(cancellations, [1, 1])
        passDeadline()
        XCTAssertEqual(starts, [2, 2])
        hover(pair, outside: true)
        hover(pair, second: true)
        passDeadline()
        XCTAssertEqual(starts, [3, 3])
        XCTAssertEqual(cancellations, [2, 2])
    }

    func testReplacementMutationHiddenDisabledAndDetachedNodesCannotStartOldPreview() throws {
        var pairs: [Pair] = [], starts = Array(repeating: 0, count: 6)
        for mode in 0..<6 {
            let pair = try pair()
            pair.layerLayout.interactions.longHoverOnLink = { link, _ in
                if link as? String != "replacement" { starts[mode] += 1 }
                return nil
            }
            hover(pair)
            switch mode {
            case 0: pair.node.update(layout(), knownHasLinks: true)
            case 1:
                let string = try XCTUnwrap(pair.layerLayout.attributedString as? NSMutableAttributedString)
                string.addAttribute(.link, value: "replacement", range: NSRange(location: 0, length: 10))
                pair.node.update(pair.layerLayout, knownHasLinks: true)
            case 2: pair.node.isHidden = true
            case 3: pair.node.isEnabled = false
            case 4: try pair.scene.root.setChildren([])
            default: pair.scene.removeFromSuperview()
            }
            pairs.append(pair)
        }
        passDeadline()
        XCTAssertEqual(starts, [0, 0, 0, 0, 0, 0])
        withExtendedLifetime(pairs) {}
    }

    func testReentrantPreviewStartDisposesOldResultWithoutCancellingNewPreview() throws {
        let pair = try pair()
        let next = layout()
        let newest = expectation(description: "Replacement preview")
        var cancelled = 0
        next.interactions.longHoverOnLink = { _, _ in newest.fulfill(); return nil }
        pair.layerLayout.interactions.longHoverOnLink = { [weak self] _, _ in
            pair.node.update(next, knownHasLinks: true)
            if let self {
                _ = pair.scene.handlePointer(.moved, at: pair.node.layer.convert(self.point(next), to: pair.scene.root.layer))
            }
            return ActionDisposable { cancelled += 1 }
        }
        hover(pair)
        wait(for: [newest], timeout: 4)
        XCTAssertEqual(cancelled, 1)
        XCTAssertTrue(pair.node.textLayout === next)
    }

    func testPreviewDisposalRebindingKeepsNewHoverAndCursor() throws {
        let pair = try pair()
        let first = expectation(description: "First preview"), second = expectation(description: "Second preview")
        let next = layout()
        var cancelled = 0
        next.interactions.longHoverOnLink = { _, _ in second.fulfill(); return nil }
        pair.layerLayout.interactions.longHoverOnLink = { [weak self] _, _ in
            first.fulfill()
            return ActionDisposable {
                cancelled += 1
                pair.node.update(next, knownHasLinks: true)
                if let self { _ = pair.scene.handlePointer(.moved, at: pair.node.layer.convert(self.point(next), to: pair.scene.root.layer)) }
            }
        }
        hover(pair)
        wait(for: [first], timeout: 3)
        _ = pair.scene.handlePointer(.moved, at: NSPoint(x: 270, y: 90))
        wait(for: [second], timeout: 3)
        XCTAssertEqual(cancelled, 1)
        XCTAssertTrue(pair.node.textLayout === next)
        XCTAssertNotNil(pair.node.cursor)
    }

    func testTooltipsUseNativeRectsAndResolveCurrentDecodedTruncatedText() throws {
        let pair = try pair(longText: true)
        let rects = pair.layerLayout.toolTipRects.map { pair.node.layer.convert($0, to: pair.scene.root.layer) }
        XCTAssertEqual(pair.scene.entries.count, rects.count)
        XCTAssertTrue(rects.allSatisfy { rect in pair.scene.entries.values.contains { $0.0 == rect } })
        let nativePoint = point(pair.nativeLayout), scenePoint = pair.node.layer.convert(point(pair.layerLayout), to: pair.scene.root.layer)
        let entry = try XCTUnwrap(pair.scene.entries.first)
        let owner = try XCTUnwrap(entry.value.1 as? ChatLayerTextLinkState)
        let native = pair.native.view(pair.native, stringForToolTip: 0, point: nativePoint, userData: nil)
        let current = owner.view(pair.scene, stringForToolTip: entry.key, point: scenePoint, userData: nil)
        XCTAssertEqual(current, native)
        XCTAssertTrue(current.contains("🦆"))
        XCTAssertTrue(current.hasSuffix("..."))
        XCTAssertEqual(current.count, 70)
        pair.layerLayout.interactions.resolveLink = { _ in "https://changed.example/%20space" }
        XCTAssertEqual(owner.view(pair.scene, stringForToolTip: entry.key, point: scenePoint, userData: nil), "https://changed.example/ space")
        XCTAssertEqual(owner.view(pair.scene, stringForToolTip: entry.key, point: NSPoint(x: 275, y: 90), userData: nil), "")
    }

    func testTooltipRegistrationReusesGeometryAndTracksMovesAndExternalRemoval() throws {
        let pair = try pair()
        let count = pair.scene.entries.count, additions = pair.scene.additions
        XCTAssertGreaterThan(count, 0)
        for _ in 0..<20 { pair.node.update(pair.layerLayout, knownHasLinks: true, frame: pair.node.frame) }
        XCTAssertEqual(pair.scene.additions, additions)
        pair.node.frame.origin = NSPoint(x: 31, y: 19)
        pair.scene.layoutSubtreeIfNeeded()
        XCTAssertEqual(pair.scene.entries.count, count)
        XCTAssertEqual(pair.scene.additions, additions + count)
        XCTAssertTrue(pair.layerLayout.toolTipRects.allSatisfy { rect in
            pair.scene.entries.values.contains { $0.0 == pair.node.layer.convert(rect, to: pair.scene.root.layer) }
        })
        pair.layerLayout.interactions.longHoverOnLink = { _, _ in nil }
        pair.scene.removeAllToolTips()
        hover(pair)
        XCTAssertTrue(pair.scene.entries.isEmpty)
        pair.scene.layout()
        XCTAssertTrue(pair.scene.entries.isEmpty)
        pair.node.update(pair.layerLayout, knownHasLinks: true, frame: pair.node.frame)
        XCTAssertEqual(pair.scene.entries.count, count)
        try pair.scene.root.setChildren([])
        XCTAssertTrue(pair.scene.entries.isEmpty)
    }

    func testTooltipGeometryInvalidatesForParentTransformsAndTextRemeasurement() throws {
        let pair = try pair()
        let parent = ChatLayerNode(id: "parent")
        try pair.scene.root.setChildren([])
        try parent.setChildren([pair.node])
        try pair.scene.root.setChildren([parent])
        for transform in [CATransform3DMakeTranslation(20, 10, 0), CATransform3DMakeScale(1.5, 1.2, 1)] {
            parent.transform = transform
            pair.scene.layout()
            XCTAssertFalse(pair.scene.entries.isEmpty)
            XCTAssertEqual(pair.scene.entries.count, pair.layerLayout.toolTipRects.count)
            XCTAssertTrue(pair.layerLayout.toolTipRects.allSatisfy { rect in
                pair.scene.entries.values.contains { $0.0 == pair.node.layer.convert(rect, to: pair.scene.root.layer) }
            })
        }
        pair.layerLayout.measure(width: 60)
        pair.node.update(pair.layerLayout, knownHasLinks: true)
        XCTAssertEqual(pair.scene.entries.count, pair.layerLayout.toolTipRects.count)
        XCTAssertTrue(pair.layerLayout.toolTipRects.allSatisfy { rect in
            pair.scene.entries.values.contains { $0.0 == pair.node.layer.convert(rect, to: pair.scene.root.layer) }
        })
    }

    func testRemovingNodeReleasesPreviewThatRetainsTheScene() throws {
        let source = ValuePipe<Int>(), started = expectation(description: "Preview")
        var cancellations = 0
        var subscription: Disposable?
        defer { subscription?.dispose() }
        weak var released: ChatLayerTextNode?
        let scene = TrackingScene(frame: NSRect(x: 0, y: 0, width: 280, height: 100))
        attach(scene)
        try autoreleasepool {
            let node = ChatLayerTextNode(id: "temporary", selectable: true)
            released = node
            let text = layout()
            text.interactions.longHoverOnLink = { _, owner in
                let disposable = (source.signal() |> afterDisposed { cancellations += 1 }).start(next: { _ in owner.needsDisplay = true })
                subscription = disposable
                started.fulfill()
                return disposable
            }
            try scene.root.setChildren([node])
            node.update(text, knownHasLinks: true)
            _ = scene.handlePointer(.moved, at: point(text))
            wait(for: [started], timeout: 3)
            try scene.root.setChildren([])
        }
        XCTAssertEqual(cancellations, 1)
        XCTAssertNil(released)
        XCTAssertTrue(scene.entries.isEmpty)
    }

    func testStationaryPointerRetargetsPreviewAfterLayoutMovesTheLinks() throws {
        let pair = try pair()
        var opened: [String] = []
        pair.layerLayout.interactions.longHoverOnLink = { link, _ in opened.append(link as! String); return nil }
        hover(pair)
        pair.node.frame.origin.x -= point(pair.layerLayout, second: true).x - point(pair.layerLayout).x
        pair.scene.layout()
        passDeadline()
        XCTAssertEqual(opened, ["https://second.example/"])
    }

    func testInPlaceLinkMutationCannotActivateEitherTarget() throws {
        for rebind in [false, true] {
            let pair = try pair()
            var opened = 0
            pair.layerLayout.interactions.processURL = { _ in opened += 1 }
            let position = pair.node.layer.convert(point(pair.layerLayout), to: pair.scene.root.layer)
            _ = pair.scene.handlePointer(.down, at: position)
            try XCTUnwrap(pair.layerLayout.attributedString as? NSMutableAttributedString).addAttribute(.link, value: "replacement", range: NSRange(location: 0, length: 10))
            if rebind { pair.node.update(pair.layerLayout, knownHasLinks: true, preservingSelectionGesture: true) }
            _ = pair.scene.handlePointer(.up, at: position)
            XCTAssertEqual(opened, 0)
        }
    }

    func testMutationWithoutRebindingCannotStartStalePreview() throws {
        let pair = try pair()
        var opened = 0
        pair.layerLayout.interactions.longHoverOnLink = { link, _ in
            if link as? String != "replacement" { opened += 1 }
            return nil
        }
        hover(pair)
        try XCTUnwrap(pair.layerLayout.attributedString as? NSMutableAttributedString).addAttribute(.link, value: "replacement", range: NSRange(location: 0, length: 10))
        passDeadline()
        XCTAssertEqual(opened, 0)
    }

    func testLinkedSelectionGestureSurvivesEquivalentLayoutButChangedURLCannotActivate() throws {
        for variant in 0..<4 {
            let changedURL = variant % 2 == 1, tooltips = variant < 2
            let pair = try pair(tooltips: tooltips)
            var opened: [String] = []
            let next = layout(tooltips: tooltips)
            if changedURL {
                try XCTUnwrap(next.attributedString as? NSMutableAttributedString).addAttribute(.link, value: "changed", range: NSRange(location: 0, length: 10))
            }
            next.interactions.processURL = { opened.append($0 as! String) }
            let point = pair.node.layer.convert(point(pair.layerLayout), to: pair.scene.root.layer)
            _ = pair.scene.handlePointer(.down, at: point)
            pair.node.update(next, knownHasLinks: true, frame: pair.node.frame, preservingSelectionGesture: true)
            _ = pair.scene.handlePointer(.up, at: point)
            XCTAssertEqual(opened.count, changedURL ? 0 : 1)
        }
    }
}
