import Cocoa
import Darwin
import XCTest
@testable import TGUIKit

private final class KeyWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
}
private final class CountingCandidate: CandidateAccessory {
    var calls = 0
    var lastLayoutPass = -1
    override func updateAnimatableContent() {
        calls += 1
        lastLayoutPass = layoutPass
        super.updateAnimatableContent()
    }
}
private final class CountingReference: ReferenceAccessory {
    var calls = 0
    override func updateAnimatableContent() {
        calls += 1
        super.updateAnimatableContent()
    }
}
final class LifecycleTests: XCTestCase {
    private var windows: [KeyWindow] = []
    override func setUp() { TGUIKitTestBootstrap.install() }
    override func tearDown() {
        windows.forEach { $0.contentView = nil; $0.close() }
        windows.removeAll()
    }
    private func host() -> (KeyWindow, NSScrollView, NSView) {
        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let document = View(frame: NSRect(x: 0, y: 0, width: 300, height: 1000))
        scroll.documentView = document
        window.contentView = scroll
        windows.append(window)
        return (window, scroll, document)
    }
    private func text(_ emoji: Int64? = nil) -> TextViewLayout {
        let value = NSMutableAttributedString(attributedString: .initialize(string: emoji == nil ? "Plain text" : "🐥 name", color: .blue, font: .normal(13)))
        if let emoji { value.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(emoji), range: NSRange(location: 0, length: 2)) }
        let result = TextViewLayout(value, maximumNumberOfLines: 1)
        result.measure(width: 200)
        return result
    }
    private func model(header: Int64?, message: Int64?, context: FixtureContext = FixtureContext()) -> FixtureModel {
        FixtureModel(header: text(header), message: text(message), context: context)
    }
    private func post(_ name: Notification.Name, _ object: AnyObject) { NotificationCenter.default.post(name: name, object: object) }

    func testPlainPreviewAllocatesNoObserverAndReceivesNoScrollCallbacks() {
        let (_, scroll, document) = host()
        let view = CountingCandidate(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        document.addSubview(view)
        view.apply(model(header: nil, message: nil))
        XCTAssertNil(view.observerForTesting)
        view.calls = 0
        for _ in 0..<100 { post(NSView.boundsDidChangeNotification, scroll.contentView) }
        XCTAssertEqual(view.calls, 0)
    }

    func testMissingHeaderRemovesItsEmojiWithoutRemovingMessageEmoji() throws {
        let (_, _, document) = host()
        let view = CountingCandidate(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        document.addSubview(view)
        var value = model(header: 10, message: 20)
        view.apply(value)
        let header = try XCTUnwrap(view.headerLayers.first)
        let message = try XCTUnwrap(view.messageLayers.first)
        XCTAssertNotNil(header.superlayer)
        value.header = nil
        view.apply(value)
        XCTAssertTrue(view.headerLayers.isEmpty)
        XCTAssertNil(header.superlayer)
        XCTAssertFalse(header.isPlayable)
        XCTAssertTrue(view.messageLayers.first === message)
        XCTAssertNotNil(view.observerForTesting)
    }

    func testMissingMessageRemovesItsEmojiAndObserver() throws {
        let (_, scroll, document) = host()
        let view = CountingCandidate(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        document.addSubview(view)
        var value = model(header: nil, message: 20)
        view.apply(value)
        let message = try XCTUnwrap(view.messageLayers.first)
        value.message = nil
        view.apply(value)
        XCTAssertTrue(view.messageLayers.isEmpty)
        XCTAssertNil(message.superlayer)
        XCTAssertFalse(message.isPlayable)
        XCTAssertNil(view.observerForTesting)
        view.calls = 0
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertEqual(view.calls, 0)
    }

    func testPlaybackRunsOnceAfterFinalTextPositioning() {
        let (_, _, document) = host()
        let view = CountingCandidate(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        document.addSubview(view)
        view.calls = 0
        view.apply(model(header: 10, message: 20))
        XCTAssertEqual(view.calls, 1)
        XCTAssertEqual(view.lastLayoutPass, view.layoutPass)
    }

    func testAnimatedReuseAndKeyLiteTransitions() throws {
        let (window, scroll, document) = host()
        let view = CountingCandidate(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        document.addSubview(view)
        let context = FixtureContext()
        let value = model(header: 10, message: 20, context: context)
        view.apply(value)
        let header = try XCTUnwrap(view.headerLayers.first), message = try XCTUnwrap(view.messageLayers.first)
        let observer = try XCTUnwrap(view.observerForTesting)
        for _ in 0..<10 {
            view.apply(value)
            XCTAssertTrue(view.headerLayers.first === header)
            XCTAssertTrue(view.messageLayers.first === message)
            XCTAssertTrue(view.observerForTesting === observer)
        }
        view.calls = 0
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertEqual(view.calls, 1)
        XCTAssertTrue(header.isPlayable)
        XCTAssertTrue(message.isPlayable)
        window.key = false
        post(NSWindow.didResignKeyNotification, window)
        XCTAssertFalse(header.isPlayable)
        XCTAssertFalse(message.isPlayable)
        window.key = true
        post(NSWindow.didBecomeKeyNotification, window)
        XCTAssertTrue(header.isPlayable)
        context.lite = true
        view.apply(value)
        XCTAssertFalse(header.isPlayable)
        XCTAssertFalse(message.isPlayable)
        context.lite = false
        view.apply(value)
        XCTAssertTrue(message.isPlayable)
    }

    func testReparentAndDetachMoveNotificationScope() {
        let (_, firstScroll, firstDocument) = host(), (_, secondScroll, secondDocument) = host()
        let view = CountingCandidate(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        firstDocument.addSubview(view)
        view.apply(model(header: 10, message: nil))
        secondDocument.addSubview(view)
        view.calls = 0
        post(NSView.boundsDidChangeNotification, firstScroll.contentView)
        XCTAssertEqual(view.calls, 0)
        post(NSView.boundsDidChangeNotification, secondScroll.contentView)
        XCTAssertEqual(view.calls, 1)
        view.removeFromSuperview()
        view.calls = 0
        post(NSView.boundsDidChangeNotification, secondScroll.contentView)
        XCTAssertEqual(view.calls, 0)
        XCTAssertFalse(view.headerLayers[0].isPlayable)
    }

    func testRemovingAllEmojiReleasesObserverAndLayers() {
        let (_, _, document) = host()
        let view = CountingCandidate(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        document.addSubview(view)
        weak var observer: AnimatableContentTokenObserver?
        weak var header: InlineStickerItemLayer?
        weak var message: InlineStickerItemLayer?
        autoreleasepool {
            view.apply(model(header: 10, message: 20))
            observer = view.observerForTesting
            header = view.headerLayers.first
            message = view.messageLayers.first
            view.apply(FixtureModel(header: nil, message: nil, context: FixtureContext()))
        }
        CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        XCTAssertNil(observer)
        XCTAssertNil(header)
        XCTAssertNil(message)
    }

    func testReplacingEmojiStopsPreviousLayer() throws {
        let (_, _, document) = host()
        let view = CountingCandidate(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        document.addSubview(view)
        view.apply(model(header: 10, message: 20))
        let original = try XCTUnwrap(view.messageLayers.first)
        XCTAssertTrue(original.isPlayable)
        view.apply(model(header: 10, message: 30))
        XCTAssertNil(original.superlayer)
        XCTAssertFalse(original.isPlayable)
        XCTAssertEqual(view.messageLayers.first?.fileId, 30)
        XCTAssertTrue(view.messageLayers.first?.isPlayable == true)
    }

    func testDetachedAnimatedPreviewDefersObserverUntilAttachment() {
        let view = CountingCandidate(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        view.apply(model(header: 10, message: 20))
        XCTAssertNil(view.observerForTesting)
        XCTAssertFalse(view.headerLayers[0].isPlayable)
        let (_, _, document) = host()
        document.addSubview(view)
        XCTAssertNotNil(view.observerForTesting)
        XCTAssertTrue(view.headerLayers[0].isPlayable)
        view.removeFromSuperview()
        XCTAssertNil(view.observerForTesting)
        XCTAssertFalse(view.headerLayers[0].isPlayable)
    }

    func testScrollVisibilityStopsAndResumesEmoji() {
        let (_, scroll, document) = host()
        let view = CountingCandidate(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        document.addSubview(view)
        view.apply(model(header: 10, message: 20))
        XCTAssertTrue(view.messageLayers[0].isPlayable)
        view.textView?.setFrameOrigin(NSPoint(x: 8, y: 2000))
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertFalse(view.messageLayers[0].isPlayable)
        view.textView?.setFrameOrigin(NSPoint(x: 8, y: 20))
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertTrue(view.messageLayers[0].isPlayable)
    }

    func testNotificationBenchmark() throws {
        guard ProcessInfo.processInfo.environment["CHAT_ACCESSORY_BENCHMARK"] != nil else { throw XCTSkip("Opt-in accessory notification benchmark") }
        let (_, oldScroll, oldDocument) = host(), (_, newScroll, newDocument) = host()
        var report: [String: Any] = [:]
        let posts = 1000
        for active in [0, 20, 40] {
            let originals = (0..<40).map { _ in CountingReference(frame: NSRect(x: 0, y: 0, width: 250, height: 50)) }
            let candidates = (0..<40).map { _ in CountingCandidate(frame: NSRect(x: 0, y: 0, width: 250, height: 50)) }
            for index in 0..<40 {
                oldDocument.addSubview(originals[index])
                newDocument.addSubview(candidates[index])
                let value = model(header: index < active ? 10 : nil, message: index < active ? 20 : nil)
                originals[index].apply(value)
                candidates[index].apply(value)
            }
            let oldObservers = originals.compactMap { $0.observerForTesting }
            let newObservers = candidates.compactMap { $0.observerForTesting }
            func tokens(_ observers: [AnimatableContentTokenObserver]) -> Int {
                observers.reduce(0) { total, observer in
                    total + ((Mirror(reflecting: observer).children.first { $0.label == "tokens" }?.value as? [NSObjectProtocol])?.count ?? 0)
                }
            }
            func bytes(_ observers: [AnimatableContentTokenObserver]) -> Int {
                observers.reduce(0) { $0 + malloc_size(Unmanaged.passUnretained($1).toOpaque()) }
            }
            func before() -> Double {
                originals.forEach { $0.calls = 0 }
                let start = CFAbsoluteTimeGetCurrent()
                for _ in 0..<posts { post(NSView.boundsDidChangeNotification, oldScroll.contentView) }
                let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000000 / Double(posts)
                XCTAssertEqual(originals.reduce(0) { $0 + $1.calls }, 40 * posts)
                return duration
            }
            func after() -> Double {
                candidates.forEach { $0.calls = 0 }
                let start = CFAbsoluteTimeGetCurrent()
                for _ in 0..<posts { post(NSView.boundsDidChangeNotification, newScroll.contentView) }
                let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000000 / Double(posts)
                XCTAssertEqual(candidates.reduce(0) { $0 + $1.calls }, active * posts)
                return duration
            }
            _ = before(); _ = after()
            var old: [Double] = [], new: [Double] = []
            let reverse = ProcessInfo.processInfo.environment["CHAT_ACCESSORY_REVERSE"] != nil
            for batch in 0..<9 {
                if batch % 2 == (reverse ? 1 : 0) { old.append(before()); new.append(after()) }
                else { new.append(after()); old.append(before()) }
            }
            report["animated-\(active)-of-40"] = ["baseline_us_per_post": old, "candidate_us_per_post": new, "baseline_median_us": old.sorted()[4], "candidate_median_us": new.sorted()[4], "baseline_observers": oldObservers.count, "candidate_observers": newObservers.count, "baseline_tokens": tokens(oldObservers), "candidate_tokens": tokens(newObservers), "baseline_observer_object_bytes": bytes(oldObservers), "candidate_observer_object_bytes": bytes(newObservers)]
            print("ACCESSORY animated=\(active): \(old.sorted()[4]) -> \(new.sorted()[4]) us/post; observers \(oldObservers.count) -> \(newObservers.count); tokens \(tokens(oldObservers)) -> \(tokens(newObservers))")
            originals.forEach { $0.removeFromSuperview() }
            candidates.forEach { $0.removeFromSuperview() }
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-accessory-benchmark.json"))
    }

    func testSwitchingToPlainLayoutsRemovesEmoji() {
        let (_, _, document) = host()
        let view = CountingCandidate(frame: NSRect(x: 0, y: 0, width: 250, height: 50))
        document.addSubview(view)
        view.apply(model(header: 10, message: 20))
        view.apply(model(header: nil, message: nil))
        XCTAssertTrue(view.headerLayers.isEmpty)
        XCTAssertTrue(view.messageLayers.isEmpty)
        XCTAssertNil(view.observerForTesting)
    }
}
