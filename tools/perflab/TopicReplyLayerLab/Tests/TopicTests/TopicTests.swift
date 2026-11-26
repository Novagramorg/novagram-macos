import Cocoa
import XCTest
import TGUIKit

final class TopicTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }
    private func pair(_ item: TopicReplyItemLayout, width: CGFloat? = nil) -> (NativeTopicView, CandidateTopicView) {
        let frame = NSRect(origin: .zero, size: NSSize(width: width ?? item.size.width, height: max(1, item.size.height)))
        let old = NativeTopicView(frame: frame)
        let new = CandidateTopicView(frame: frame)
        old.update(item: item, animated: false)
        new.update(item: item, animated: false)
        old.updateLayout(size: frame.size, transition: .immediate)
        new.updateLayout(size: frame.size, transition: .immediate)
        return (old, new)
    }
    func testTopicPixelsMatchNativeAcrossScriptsWrappingAndScales() {
        for scale: CGFloat in [1, 2, 3] {
            for width: CGFloat in [90, 180, 260] {
                for title in ["General", "A topic with a longer title that wraps across lines", "مرحبا بالعالم موضوع طويل", "你好 世界 👨‍👩‍👧‍👦"] {
                    let item = TopicReplyItemLayout(title, width: width, lines: 3)
                    let (old, new) = pair(item, width: item.size.width + 11)
                    let expected = ViewSnapshot.render(old, scale: scale)
                    let actual = ViewSnapshot.render(new, scale: scale)
                    XCTAssertEqual(actual.differingPixels(from: expected, tolerance: 0), 0, "scale=\(scale) width=\(width) title=\(title)")
                }
            }
        }
    }
    func testTopicUsesOneFewerViewAndTwoFewerLayers() {
        let (old, new) = pair(TopicReplyItemLayout("General"))
        let host = View(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        host.addSubview(old)
        host.addSubview(new)
        let window = NSWindow(contentRect: host.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        CATransaction.flush()
        defer { window.contentView = nil; window.close() }
        XCTAssertEqual(viewTreeCount(old) - viewTreeCount(new), 1)
        func count(_ layer: CALayer) -> Int { 1 + (layer.sublayers ?? []).reduce(0) { $0 + count($1) } }
        XCTAssertEqual(count(old.layer!) - count(new.layer!), 2)
    }
    func testIconReuseReplacementAndRemoval() throws {
        let (_, view) = pair(TopicReplyItemLayout("General"))
        let original = try XCTUnwrap(view.iconsForTesting.first)
        view.update(item: TopicReplyItemLayout("Another title"), animated: false)
        XCTAssertTrue(view.iconsForTesting.first === original)
        view.update(item: TopicReplyItemLayout("Replacement", id: 100), animated: false)
        XCTAssertNil(original.superlayer)
        XCTAssertFalse(original.isPlayable)
        let replacement = try XCTUnwrap(view.iconsForTesting.first)
        XCTAssertEqual(replacement.fileId, 100)
        view.update(item: TopicReplyItemLayout("No icon", id: nil), animated: false)
        XCTAssertTrue(view.iconsForTesting.isEmpty)
        XCTAssertNil(replacement.superlayer)
        XCTAssertFalse(replacement.isPlayable)
    }
    func testTopicActionAndAccessibleLabelRemainOnControl() {
        let item = TopicReplyItemLayout("General")
        let (_, view) = pair(item)
        var calls = 0
        view.set(handler: { _ in calls += 1 }, for: .Click)
        view.send(event: .Click)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(view.accessibilityDefaultLabel, item.text.attributedString.string)
        XCTAssertTrue(view.hitTest(NSPoint(x: 12, y: 6)) === view)
    }
}


private final class TopicKeyWindow: NSWindow {
    var key = true
    var permitsKey = true
    override var isKeyWindow: Bool { key }
    override var canBecomeKey: Bool { permitsKey }
}

extension TopicTests {
    func testPlaybackTracksAttachmentVisibilityAndWindowPolicy() throws {
        let item = TopicReplyItemLayout("General")
        let (_, view) = pair(item)
        let icon = try XCTUnwrap(view.iconsForTesting.first)
        XCTAssertFalse(icon.isPlayable)
        let window = TopicKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let document = View(frame: NSRect(x: 0, y: 0, width: 300, height: 1000))
        scroll.documentView = document
        document.addSubview(view)
        window.contentView = scroll
        defer { window.contentView = nil; window.close() }
        XCTAssertTrue(icon.isPlayable)
        window.key = false
        view.updateAnimatableContent()
        XCTAssertFalse(icon.isPlayable)
        window.permitsKey = false
        view.updateAnimatableContent()
        XCTAssertTrue(icon.isPlayable)
        window.permitsKey = true
        window.key = true
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 500))
        view.updateAnimatableContent()
        XCTAssertFalse(icon.isPlayable)
        scroll.contentView.scroll(to: .zero)
        view.updateAnimatableContent()
        XCTAssertTrue(icon.isPlayable)
        view.removeFromSuperview()
        XCTAssertFalse(icon.isPlayable)
    }

    func testAnimatedCenteringKeepsIconsInTextCoordinates() throws {
        let item = TopicReplyItemLayout("General")
        let (_, view) = pair(item)
        let icon = try XCTUnwrap(view.iconsForTesting.first)
        let originalIcon = icon.frame
        let drawing = try XCTUnwrap(view.layer?.sublayers?.first as? TextViewLayer)
        let origin = drawing.position
        view.setFrameSize(NSSize(width: item.size.width + 65, height: item.size.height))
        view.updateLayout(size: view.frame.size, transition: .animated(duration: 0.2, curve: .easeOut))
        XCTAssertEqual(icon.frame, originalIcon)
        let animation = try XCTUnwrap(drawing.animation(forKey: "position") as? CABasicAnimation)
        XCTAssertEqual((animation.fromValue as? NSValue)?.pointValue, origin)
        XCTAssertEqual((animation.toValue as? NSValue)?.pointValue, drawing.position)
        XCTAssertEqual(drawing.bounds.origin, NSPoint(x: -2, y: -3))
        XCTAssertTrue(icon.superlayer === drawing)
    }

    func testBackingScaleChangesPreserveLabelAndIconIdentity() throws {
        let item = TopicReplyItemLayout("General")
        let (_, view) = pair(item)
        let icon = try XCTUnwrap(view.iconsForTesting.first)
        let window = SnapshotWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        for scale: CGFloat in [1, 3, 2] {
            window.scale = scale
            view.viewDidChangeBackingProperties()
            XCTAssertEqual(view.layer?.sublayers?.first?.contentsScale, scale)
            XCTAssertTrue(view.iconsForTesting.first === icon)
        }
    }

    func testEmptyAndIconlessLabelsMatchNative() {
        for title in ["", "No icon", "مرحبا"] {
            let (old, new) = pair(TopicReplyItemLayout(title, id: nil), width: 150)
            let expected = ViewSnapshot.render(old)
            let actual = ViewSnapshot.render(new)
            XCTAssertEqual(actual.differingPixels(from: expected, tolerance: 0), 0)
            XCTAssertTrue(new.iconsForTesting.isEmpty)
        }
    }

    func testRemovedIconAndLabelCanBeReleased() {
        weak var label: CandidateTopicView?
        weak var icon: InlineStickerItemLayer?
        autoreleasepool {
            let (_, view) = pair(TopicReplyItemLayout("General"))
            label = view
            icon = view.iconsForTesting.first
            view.update(item: TopicReplyItemLayout("No icon", id: nil), animated: false)
        }
        CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertNil(label)
        XCTAssertNil(icon)
    }
}

extension TopicTests {
    func testCenteredIconVisibilityMatchesNativeClipping() throws {
        let item = TopicReplyItemLayout("General")
        let (old, new) = pair(item, width: 230)
        let window = TopicKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 140, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = View(frame: NSRect(x: 0, y: 0, width: 140, height: 100))
        host.addSubview(old)
        host.addSubview(new)
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        let oldIcon = try XCTUnwrap(old.iconsForTesting.first)
        let newIcon = try XCTUnwrap(new.iconsForTesting.first)
        var outcomes = Set<Bool>()
        for x: CGFloat in [-200, -120, -40, 0, 60, 180] {
            old.setFrameOrigin(NSPoint(x: x, y: 0))
            new.setFrameOrigin(NSPoint(x: x, y: 0))
            old.updateAnimatableContent()
            new.updateAnimatableContent()
            XCTAssertEqual(newIcon.isPlayable, oldIcon.isPlayable, "x=\(x)")
            outcomes.insert(newIcon.isPlayable)
        }
        XCTAssertEqual(outcomes, Set([false, true]))
    }
}


extension TopicTests {
    func testChangedTitlePreservesPositionUntilAnimatedLayout() throws {
        let first = TopicReplyItemLayout("Short", width: 190)
        let second = TopicReplyItemLayout("A longer title", width: 190)
        let (old, new) = pair(first, width: 240)
        let previous = old.textFrameForTesting.origin
        old.update(item: second, animated: true)
        new.update(item: second, animated: true)
        XCTAssertEqual(new.textFrameForTesting, old.textFrameForTesting)
        XCTAssertEqual(new.textFrameForTesting.origin, previous)
        old.updateLayout(size: old.frame.size, transition: .animated(duration: 0.2, curve: .easeOut))
        new.updateLayout(size: new.frame.size, transition: .animated(duration: 0.2, curve: .easeOut))
        XCTAssertEqual(new.textFrameForTesting, old.textFrameForTesting)
        let drawing = try XCTUnwrap(new.layer?.sublayers?.first as? TextViewLayer)
        let animation = try XCTUnwrap(drawing.animation(forKey: "position") as? CABasicAnimation)
        XCTAssertEqual((animation.fromValue as? NSValue)?.pointValue, NSPoint(x: previous.x - 2, y: previous.y - 3))
        XCTAssertEqual((animation.toValue as? NSValue)?.pointValue, drawing.position)
    }
}
