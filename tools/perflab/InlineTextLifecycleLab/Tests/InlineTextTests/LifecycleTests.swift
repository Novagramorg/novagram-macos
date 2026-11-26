import Cocoa
import XCTest
@testable import TGUIKit

private final class KeyWindow: NSWindow { override var isKeyWindow: Bool { true } }
private final class Marker: NSObject {}
final class LifecycleTests: XCTestCase {
    private var windows: [NSWindow] = []
    private var created = 0
    private var renderers: [RendererFixture] = []
    override func setUp() {
        TGUIKitTestBootstrap.install()
        GeneralRowsHooks.shared.makeInlineTextRenderer = { [unowned self] in
            self.created += 1
            let renderer = RendererFixture()
            self.renderers.append(renderer)
            return renderer
        }
    }
    override func tearDown() {
        windows.forEach { $0.contentView = nil; $0.close() }
        windows.removeAll()
        GeneralRowsHooks.shared = GeneralRowsHooks()
        renderers.removeAll()
    }
    private func text(embedded: Bool, string: String = "Hello 🦆", width: CGFloat = 200) -> TextViewLayout {
        let value = NSMutableAttributedString(attributedString: .initialize(string: string, color: .blue, font: .normal(14)))
        if embedded { value.addAttribute(TextInputAttributes.embedded, value: Marker(), range: NSRange(location: 6, length: 2)) }
        let layout = TextViewLayout(value, maximumNumberOfLines: 1)
        layout.measure(width: width)
        return layout
    }
    private func host() -> (NSScrollView, NSView) {
        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let document = View(frame: NSRect(x: 0, y: 0, width: 300, height: 1000))
        scroll.documentView = document
        window.contentView = scroll
        windows.append(window)
        return (scroll, document)
    }
    private struct Subject {
        let view: NSView
        let textView: TextView
        let set: (TextViewLayout?, FixtureContext?, CGFloat, CGFloat, NSPoint) -> Void
    }
    private func subject(_ interactive: Bool, reference: Bool = false) -> Subject {
        if interactive {
            if reference {
                let view = ReferenceInteractiveTextView()
                return Subject(view: view, textView: view.textView, set: { view.set(text: $0, context: $1, insetEmoji: $2, decreaseAvatar: $3, emojiOffset: $4) })
            }
            let view = CandidateInteractiveTextView()
            return Subject(view: view, textView: view.textView, set: { view.set(text: $0, context: $1, insetEmoji: $2, decreaseAvatar: $3, emojiOffset: $4) })
        }
        if reference {
            let view = ReferenceInlineTextView()
            return Subject(view: view, textView: view, set: { view.set(text: $0, context: $1, insetEmoji: $2, decreaseAvatar: $3, emojiOffset: $4) })
        }
        let view = CandidateInlineTextView()
        return Subject(view: view, textView: view, set: { view.set(text: $0, context: $1, insetEmoji: $2, decreaseAvatar: $3, emojiOffset: $4) })
    }
    private func observer(_ view: NSView) -> AnimatableContentObserver? {
        for value in Mirror(reflecting: view).children where value.label == "animatableContentObserver" {
            if let observer = value.value as? AnimatableContentObserver { return observer }
            return Mirror(reflecting: value.value).children.first?.value as? AnimatableContentObserver
        }
        return nil
    }
    private func post(_ scroll: NSScrollView) {
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }

    func testPlainControlsAvoidRendererAndObserverAllocation() {
        for interactive in [false, true] {
            let before = created
            let (scroll, document) = host()
            let item = subject(interactive)
            document.addSubview(item.view)
            item.set(text(embedded: false), FixtureContext(), 0, 0, .zero)
            XCTAssertEqual(created, before)
            XCTAssertNil(observer(item.view))
            post(scroll)
            XCTAssertEqual(created, before)
        }
    }

    func testNewEmojiStartsPlaybackImmediatelyAndKeepsParameters() throws {
        for interactive in [false, true] {
            let (_, document) = host()
            let item = subject(interactive)
            document.addSubview(item.view)
            let layout = text(embedded: true)
            XCTAssertFalse(layout.embeddedItems.isEmpty)
            item.set(layout, FixtureContext(), 2, 3, NSPoint(x: 4, y: 5))
            let renderer = try XCTUnwrap(renderers.last)
            XCTAssertTrue(renderer.playable)
            XCTAssertEqual(renderer.events.last, "play")
            XCTAssertEqual(renderer.lastInset, 2)
            XCTAssertEqual(renderer.lastDecrease, 3)
            XCTAssertEqual(renderer.lastOffset, NSPoint(x: 4, y: 5))
            XCTAssertTrue(renderer.lastLayout === layout)
            XCTAssertNotNil(observer(item.view))
        }
    }

    func testClearStopsRendererBeforeRemovingItAndUnsubscribes() throws {
        for interactive in [false, true] {
            let (scroll, document) = host()
            let item = subject(interactive)
            document.addSubview(item.view)
            item.set(text(embedded: true), FixtureContext(), 0, 0, .zero)
            let renderer = try XCTUnwrap(renderers.last)
            renderer.events.removeAll()
            item.set(nil, nil, 0, 0, .zero)
            XCTAssertEqual(renderer.events, ["stop", "clear"])
            XCTAssertNil(observer(item.view))
            let calls = renderer.playbackCalls
            post(scroll)
            XCTAssertEqual(renderer.playbackCalls, calls)
        }
    }

    func testPlainTransitionReleasesRendererAndObserver() {
        for interactive in [false, true] {
            let (_, document) = host()
            let item = subject(interactive)
            document.addSubview(item.view)
            item.set(text(embedded: true), FixtureContext(), 0, 0, .zero)
            weak var renderer = renderers.last
            weak var oldObserver = observer(item.view)
            renderers.removeAll()
            item.set(text(embedded: false), FixtureContext(), 0, 0, .zero)
            XCTAssertNil(renderer)
            XCTAssertNil(oldObserver)
        }
    }

    func testReuseLiteAndWindowTransitions() throws {
        for interactive in [false, true] {
            let (scroll, document) = host()
            let item = subject(interactive)
            document.addSubview(item.view)
            let layout = text(embedded: true), context = FixtureContext()
            item.set(layout, context, 0, 0, .zero)
            let renderer = try XCTUnwrap(renderers.last)
            let count = created
            context.lite = true
            item.set(layout, context, 0, 0, .zero)
            XCTAssertEqual(created, count)
            XCTAssertFalse(renderer.playable)
            context.lite = false
            item.set(layout, context, 0, 0, .zero)
            XCTAssertTrue(renderer.playable)
            let before = renderer.playbackCalls
            post(scroll)
            XCTAssertEqual(renderer.playbackCalls, before + 1)
            item.view.removeFromSuperview()
            XCTAssertFalse(renderer.playable)
            XCTAssertNil(observer(item.view))
            let detachedCalls = renderer.playbackCalls
            post(scroll)
            XCTAssertEqual(renderer.playbackCalls, detachedCalls)
            document.addSubview(item.view)
            XCTAssertTrue(renderer.playable)
        }
    }

    func testDetachedEmojiDefersObserver() {
        for interactive in [false, true] {
            let item = subject(interactive)
            item.set(text(embedded: true), FixtureContext(), 0, 0, .zero)
            XCTAssertNil(observer(item.view))
            XCTAssertFalse(renderers.last!.playable)
        }
    }
    func testMissingContextClearsAndPlainTextPreservesLiteState() throws {
        for interactive in [false, true] {
            let (_, document) = host()
            let item = subject(interactive)
            document.addSubview(item.view)
            let context = FixtureContext()
            let embedded = text(embedded: true)
            item.set(embedded, context, 0, 0, .zero)
            let renderer = try XCTUnwrap(renderers.last)
            renderer.events.removeAll()
            item.set(embedded, nil, 0, 0, .zero)
            XCTAssertEqual(Array(renderer.events.suffix(2)), ["stop", "clear"])
            XCTAssertNil(observer(item.view))
            context.lite = true
            item.set(text(embedded: false), context, 0, 0, .zero)
            if let view = item.view as? CandidateInteractiveTextView { XCTAssertTrue(view.isLite) }
        }
    }

    func testInteractiveLayoutRefreshesAfterCentering() throws {
        let (_, document) = host()
        let view = CandidateInteractiveTextView()
        document.addSubview(view)
        view.set(text: text(embedded: true), context: FixtureContext())
        let renderer = try XCTUnwrap(renderers.last)
        view.setFrameSize(NSSize(width: 250, height: 80))
        renderer.events.removeAll()
        view.layout()
        XCTAssertEqual(view.textView.frame.midX, view.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(view.textView.frame.midY, view.bounds.midY, accuracy: 0.5)
        XCTAssertEqual(renderer.events.last, "play")
    }

    func testPlainTextGeometryAndPixelsMatchOriginal() throws {
        for interactive in [false, true] {
            let original = subject(interactive, reference: true), candidate = subject(interactive)
            for string in ["Hello", "A long message that must truncate at narrow widths", "رسالة باللغة العربية"] {
                for width: CGFloat in [60, 200] {
                    original.set(text(embedded: false, string: string, width: width), FixtureContext(), 0, 0, .zero)
                    candidate.set(text(embedded: false, string: string, width: width), FixtureContext(), 0, 0, .zero)
                    original.view.layout(); candidate.view.layout()
                    XCTAssertEqual(original.view.frame.size, candidate.view.frame.size)
                    XCTAssertEqual(original.textView.frame, candidate.textView.frame)
                    for scale: CGFloat in [1, 2] {
                        XCTAssertEqual(try render(original.textView, scale: scale), try render(candidate.textView, scale: scale))
                    }
                }
            }
            original.set(nil, nil, 0, 0, .zero); candidate.set(nil, nil, 0, 0, .zero)
            XCTAssertEqual(original.view.frame.size, candidate.view.frame.size)
            XCTAssertEqual(original.textView.frame.size, candidate.textView.frame.size)
        }
    }

    private func render(_ view: TextView, scale: CGFloat) throws -> Data {
        let width = 500, height = 100
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        view.draw(view.drawingLayer, in: context)
        let data = Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
        XCTAssertTrue(data.contains { $0 != 0 })
        return data
    }

    func testReparentingChangesNotificationScope() throws {
        for interactive in [false, true] {
            let (oldScroll, oldDocument) = host(), (newScroll, newDocument) = host()
            let item = subject(interactive)
            oldDocument.addSubview(item.view)
            item.set(text(embedded: true), FixtureContext(), 0, 0, .zero)
            let renderer = try XCTUnwrap(renderers.last)
            newDocument.addSubview(item.view)
            renderer.playbackCalls = 0
            post(oldScroll)
            XCTAssertEqual(renderer.playbackCalls, 0)
            post(newScroll)
            XCTAssertEqual(renderer.playbackCalls, 1)
            XCTAssertTrue(renderer.playable)
        }
    }

    func testNotificationBenchmark() throws {
        guard ProcessInfo.processInfo.environment["INLINE_TEXT_BENCHMARK"] != nil else { throw XCTSkip("Opt-in inline text notification benchmark") }
        var report: [String: Any] = [:]
        for interactive in [false, true] {
            let (oldScroll, oldDocument) = host(), (newScroll, newDocument) = host()
            for active in [0, 20, 40] {
                let startOld = renderers.count
                let old = (0..<40).map { _ in subject(interactive, reference: true) }
                for index in 0..<40 {
                    oldDocument.addSubview(old[index].view)
                    old[index].set(text(embedded: index < active), FixtureContext(), 0, 0, .zero)
                }
                let oldRenderers = Array(renderers[startOld...])
                let startNew = renderers.count
                let new = (0..<40).map { _ in subject(interactive) }
                for index in 0..<40 {
                    newDocument.addSubview(new[index].view)
                    new[index].set(text(embedded: index < active), FixtureContext(), 0, 0, .zero)
                }
                let newRenderers = Array(renderers[startNew...])
                for renderer in oldRenderers + newRenderers { renderer.recordsEvents = false; renderer.events.removeAll() }
                let posts = 1000
                func measure(_ scroll: NSScrollView, _ items: [RendererFixture], expectedCalls: Int) -> Double {
                    items.forEach { $0.playbackCalls = 0 }
                    let start = CFAbsoluteTimeGetCurrent()
                    for _ in 0..<posts { post(scroll) }
                    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000000 / Double(posts)
                    XCTAssertEqual(items.reduce(0) { $0 + $1.playbackCalls }, expectedCalls)
                    return elapsed
                }
                func before() -> Double { measure(oldScroll, oldRenderers, expectedCalls: 40 * posts) }
                func after() -> Double { measure(newScroll, newRenderers, expectedCalls: active * posts) }
                _ = before(); _ = after()
                var baseline: [Double] = [], candidate: [Double] = []
                let reverse = ProcessInfo.processInfo.environment["INLINE_TEXT_REVERSE"] != nil
                for batch in 0..<9 {
                    if batch % 2 == (reverse ? 1 : 0) { baseline.append(before()); candidate.append(after()) }
                    else { candidate.append(after()); baseline.append(before()) }
                }
                let name = "\(interactive ? "interactive" : "inline")-animated-\(active)"
                report[name] = ["baseline_us": baseline, "candidate_us": candidate, "baseline_median_us": baseline.sorted()[4], "candidate_median_us": candidate.sorted()[4], "baseline_renderers": oldRenderers.count, "candidate_renderers": newRenderers.count, "baseline_observers": old.compactMap { observer($0.view) }.count, "candidate_observers": new.compactMap { observer($0.view) }.count]
                print("INLINE_TEXT \(name): \(baseline.sorted()[4]) -> \(candidate.sorted()[4]) us/post; renderers \(oldRenderers.count) -> \(newRenderers.count)")
                old.forEach { $0.view.removeFromSuperview() }; new.forEach { $0.view.removeFromSuperview() }
            }
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/inline-text-benchmark.json"))
    }

}
