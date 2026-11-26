import Cocoa
import XCTest
import TGUIKit

private final class FixtureWindow: NSWindow {
    var key = true
    var acceptsKey = true
    override var isKeyWindow: Bool { key }
    override var canBecomeKey: Bool { acceptsKey }
}

final class LifecycleTests: XCTestCase {
    private var windows: [FixtureWindow] = []
    override func setUp() { TGUIKitTestBootstrap.install() }
    override func tearDown() {
        windows.forEach { $0.contentView = nil; $0.close() }
        windows.removeAll()
        CATransaction.flush()
    }
    private struct Subject {
        let view: NSView
        let layer: InlineStickerItemLayer
    }
    private func subject(reference: Bool = false, external: Bool = false, playable: Bool = true, emoji: Bool = false) -> Subject {
        let size = NSSize(width: 24, height: 24)
        if reference {
            let view: ReferenceInlineStickerView
            if emoji {
                view = ReferenceInlineStickerView(account: Account(), inlinePacksContext: InlineStickersContext(), emoji: ChatTextCustomEmojiAttribute(), size: size, isPlayable: playable, controlContent: !external)
            } else {
                view = ReferenceInlineStickerView(account: Account(), file: TelegramMediaFile(), size: size, isPlayable: playable, playPolicy: .onceEnd, controlContent: !external, ignorePreview: true, synchronyous: true)
            }
            return Subject(view: view, layer: view.animateLayer)
        }
        let view: CandidateInlineStickerView
        if emoji {
            view = CandidateInlineStickerView(account: Account(), inlinePacksContext: InlineStickersContext(), emoji: ChatTextCustomEmojiAttribute(), size: size, isPlayable: playable, controlContent: !external)
        } else {
            view = CandidateInlineStickerView(account: Account(), file: TelegramMediaFile(), size: size, isPlayable: playable, playPolicy: .onceEnd, controlContent: !external, ignorePreview: true, synchronyous: true)
        }
        return Subject(view: view, layer: view.animateLayer)
    }
    private func host(scrollable: Bool = true) -> (FixtureWindow, NSScrollView?, NSView) {
        let rect = NSRect(x: 0, y: 0, width: 300, height: 300)
        let window = FixtureWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let document = View(frame: NSRect(x: 0, y: 0, width: 300, height: 1000))
        let scroll = scrollable ? NSScrollView(frame: rect) : nil
        if let scroll { scroll.documentView = document; window.contentView = scroll }
        else { window.contentView = document }
        windows.append(window)
        return (window, scroll, document)
    }
    private func observer(_ view: NSView) -> AnimatableContentTokenObserver? {
        for value in Mirror(reflecting: view).children where value.label == "contentObserver" {
            if let observer = value.value as? AnimatableContentTokenObserver { return observer }
            return Mirror(reflecting: value.value).children.first?.value as? AnimatableContentTokenObserver
        }
        return nil
    }
    private func tokenCount(_ view: NSView) -> Int {
        guard let observer = observer(view) else { return 0 }
        let tokens = Mirror(reflecting: observer).children.first { $0.label == "tokens" }
        return tokens.map { Mirror(reflecting: $0.value).children.count } ?? 0
    }
    private func post(_ name: Notification.Name, _ object: AnyObject) {
        NotificationCenter.default.post(name: name, object: object)
    }

    func testDetachedViewsDeferObserverAllocation() {
        for external in [false, true] {
            for emoji in [false, true] {
                let item = subject(external: external, emoji: emoji)
                XCTAssertNil(observer(item.view))
                XCTAssertEqual(tokenCount(item.view), 0)
            }
        }
    }

    func testExternalOwnershipNeverSubscribesOrOverridesPlayback() {
        for emoji in [false, true] {
            let (window, scroll, document) = host()
            let item = subject(external: true, emoji: emoji)
            document.addSubview(item.view)
            XCTAssertNil(observer(item.view))
            XCTAssertEqual(tokenCount(item.view), 0)
            for playable in [true, false] {
                item.layer.isPlayable = playable
                item.layer.writes = 0
                post(NSView.boundsDidChangeNotification, scroll!.contentView)
                post(NSView.frameDidChangeNotification, document)
                window.key = false
                post(NSWindow.didResignKeyNotification, window)
                post(NSWindow.didResizeNotification, window)
                item.view.removeFromSuperview()
                document.addSubview(item.view)
                XCTAssertEqual(item.layer.isPlayable, playable)
                XCTAssertEqual(item.layer.writes, 0)
            }
        }
    }

    func testAutomaticAttachmentDetachmentAndReattachment() throws {
        for emoji in [false, true] {
            let (_, scroll, document) = host()
            let item = subject(emoji: emoji)
            document.addSubview(item.view)
            weak var oldObserver = try XCTUnwrap(observer(item.view))
            XCTAssertEqual(tokenCount(item.view), 4)
            XCTAssertEqual(item.layer.isPlayable, true)
            item.view.removeFromSuperview()
            XCTAssertEqual(item.layer.isPlayable, false)
            XCTAssertNil(observer(item.view))
            XCTAssertNil(oldObserver)
            item.layer.writes = 0
            post(NSView.boundsDidChangeNotification, scroll!.contentView)
            XCTAssertEqual(item.layer.writes, 0)
            document.addSubview(item.view)
            XCTAssertEqual(item.layer.isPlayable, true)
            XCTAssertEqual(tokenCount(item.view), 4)
        }
    }

    func testKeyWindowAndNonKeyCapableWindowPolicies() {
        let (window, _, document) = host()
        let item = subject()
        document.addSubview(item.view)
        XCTAssertEqual(item.layer.isPlayable, true)
        window.key = false
        post(NSWindow.didResignKeyNotification, window)
        XCTAssertEqual(item.layer.isPlayable, false)
        window.key = true
        post(NSWindow.didBecomeKeyNotification, window)
        XCTAssertEqual(item.layer.isPlayable, true)
        window.key = false
        window.acceptsKey = false
        post(NSWindow.didResignKeyNotification, window)
        XCTAssertEqual(item.layer.isPlayable, true)
    }

    func testScrollClippingStopsAndRestoresPlayback() {
        let (_, scroll, document) = host()
        let item = subject()
        document.addSubview(item.view)
        XCTAssertEqual(item.layer.isPlayable, true)
        scroll!.contentView.scroll(to: NSPoint(x: 0, y: 400))
        post(NSView.boundsDidChangeNotification, scroll!.contentView)
        XCTAssertEqual(item.view.visibleRect, .zero)
        XCTAssertEqual(item.layer.isPlayable, false)
        scroll!.contentView.scroll(to: .zero)
        post(NSView.boundsDidChangeNotification, scroll!.contentView)
        XCTAssertEqual(item.layer.isPlayable, true)
    }

    func testReparentingMovesNotificationScopeWithoutDuplicates() throws {
        let (oldWindow, oldScroll, oldDocument) = host()
        let (newWindow, newScroll, newDocument) = host()
        let item = subject()
        oldDocument.addSubview(item.view)
        newDocument.addSubview(item.view)
        for _ in 0..<5 { item.view.viewDidMoveToWindow(); item.view.viewDidMoveToSuperview() }
        XCTAssertEqual(tokenCount(item.view), 4)
        item.layer.writes = 0
        post(NSView.boundsDidChangeNotification, oldScroll!.contentView)
        post(NSView.frameDidChangeNotification, oldDocument)
        post(NSWindow.didResignKeyNotification, oldWindow)
        XCTAssertEqual(item.layer.writes, 0)
        post(NSView.boundsDidChangeNotification, newScroll!.contentView)
        post(NSView.frameDidChangeNotification, newDocument)
        post(NSWindow.didBecomeKeyNotification, newWindow)
        XCTAssertEqual(item.layer.writes, 3)
    }

    func testWindowResizeFallbackAndObserverReuse() throws {
        let (window, _, document) = host(scrollable: false)
        let item = subject()
        document.addSubview(item.view)
        let original = try XCTUnwrap(observer(item.view))
        XCTAssertEqual(tokenCount(item.view), 3)
        item.view.viewDidMoveToSuperview()
        XCTAssertTrue(observer(item.view) === original)
        item.layer.writes = 0
        post(NSWindow.didResizeNotification, window)
        XCTAssertEqual(item.layer.writes, 1)
    }

    func testDisabledAutomaticPlaybackStillEnforcesItsPolicy() {
        for emoji in [false, true] {
            let (_, scroll, document) = host()
            let item = subject(playable: false, emoji: emoji)
            document.addSubview(item.view)
            XCTAssertEqual(item.layer.isPlayable, false)
            item.layer.isPlayable = true
            post(NSView.boundsDidChangeNotification, scroll!.contentView)
            XCTAssertEqual(item.layer.isPlayable, false)
            XCTAssertEqual(tokenCount(item.view), 4)
        }
    }

    func testConstructorAndGeometryParity() {
        for external in [false, true] {
            for playable in [false, true] {
                for emoji in [false, true] {
                    let before = subject(reference: true, external: external, playable: playable, emoji: emoji)
                    let after = subject(external: external, playable: playable, emoji: emoji)
                    XCTAssertEqual(before.layer.isPlayable, after.layer.isPlayable)
                    XCTAssertEqual(before.view.frame, after.view.frame)
                    XCTAssertEqual(before.layer.frame, after.layer.frame)
                    XCTAssertEqual(before.layer.ignorePreview, after.layer.ignorePreview)
                    XCTAssertEqual(before.layer.synchronyous, after.layer.synchronyous)
                    XCTAssertEqual(before.layer.emoji == nil, after.layer.emoji == nil)
                    XCTAssertEqual(before.layer.file == nil, after.layer.file == nil)
                    XCTAssertTrue(after.layer.superview === after.view)
                    XCTAssertTrue(after.layer.superlayer === after.view.layer)
                    XCTAssertEqual((before.view as! Control).userInteractionEnabled, (after.view as! Control).userInteractionEnabled)
                    if emoji { if case .loop = after.layer.policy {} else { XCTFail("Lost emoji policy") } }
                    else { if case .onceEnd = after.layer.policy {} else { XCTFail("Lost file policy") } }
                }
            }
        }
    }

    func testViewAndObserverReleaseAfterRemoval() {
        let (_, scroll, document) = host()
        weak var oldView: NSView?
        weak var oldObserver: AnimatableContentTokenObserver?
        autoreleasepool {
            let item = subject()
            document.addSubview(item.view)
            oldView = item.view
            oldObserver = observer(item.view)
            item.view.removeFromSuperview()
        }
        CATransaction.flush()
        XCTAssertNil(oldView)
        XCTAssertNil(oldObserver)
        post(NSView.boundsDidChangeNotification, scroll!.contentView)
    }

    func testNotificationBenchmark() throws {
        guard ProcessInfo.processInfo.environment["INLINE_STICKER_BENCHMARK"] != nil else { throw XCTSkip("Opt-in notification benchmark") }
        var report: [String: Any] = [:]
        for automatic in [0, 20, 40] {
            let (_, oldScroll, oldDocument) = host()
            let (_, newScroll, newDocument) = host()
            let before = (0..<40).map { subject(reference: true, external: $0 >= automatic) }
            let after = (0..<40).map { subject(external: $0 >= automatic) }
            before.forEach { oldDocument.addSubview($0.view) }
            after.forEach { newDocument.addSubview($0.view) }
            func measure(_ scroll: NSScrollView, _ items: [Subject]) -> Double {
                items.forEach { $0.layer.writes = 0 }
                let start = CFAbsoluteTimeGetCurrent()
                for _ in 0..<1000 { post(NSView.boundsDidChangeNotification, scroll.contentView) }
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                XCTAssertEqual(items.reduce(0) { $0 + $1.layer.writes }, automatic * 1000)
                return elapsed
            }
            _ = measure(oldScroll!, before); _ = measure(newScroll!, after)
            var baseline: [Double] = [], candidate: [Double] = []
            let reverse = ProcessInfo.processInfo.environment["INLINE_STICKER_REVERSE"] != nil
            for batch in 0..<9 {
                if batch % 2 == (reverse ? 1 : 0) { baseline.append(measure(oldScroll!, before)); candidate.append(measure(newScroll!, after)) }
                else { candidate.append(measure(newScroll!, after)); baseline.append(measure(oldScroll!, before)) }
            }
            let oldCount = before.compactMap { observer($0.view) }.count
            let newCount = after.compactMap { observer($0.view) }.count
            let oldTokens = before.reduce(0) { $0 + tokenCount($1.view) }
            let newTokens = after.reduce(0) { $0 + tokenCount($1.view) }
            XCTAssertEqual(oldCount, 40); XCTAssertEqual(newCount, automatic)
            XCTAssertEqual(oldTokens, 160); XCTAssertEqual(newTokens, automatic * 4)
            let oldBytes = before.compactMap { observer($0.view) }.reduce(0) { $0 + malloc_size(Unmanaged.passUnretained($1).toOpaque()) }
            let newBytes = after.compactMap { observer($0.view) }.reduce(0) { $0 + malloc_size(Unmanaged.passUnretained($1).toOpaque()) }
            var measurement: [String: Any] = ["baseline_us": baseline, "candidate_us": candidate, "baseline_median_us": baseline.sorted()[4], "candidate_median_us": candidate.sorted()[4], "baseline_observers": oldCount, "candidate_observers": newCount, "baseline_tokens": oldTokens, "candidate_tokens": newTokens, "baseline_helper_bytes": oldBytes, "candidate_helper_bytes": newBytes]
            print("INLINE_STICKER automatic-\(automatic): \(baseline.sorted()[4]) -> \(candidate.sorted()[4]) us/post; observers \(oldCount) -> \(newCount); tokens \(oldTokens) -> \(newTokens)")
            before.forEach { $0.view.removeFromSuperview() }; after.forEach { $0.view.removeFromSuperview() }
            func cycle(_ document: NSView, _ items: [Subject]) -> Double {
                let start = CFAbsoluteTimeGetCurrent()
                for _ in 0..<50 {
                    autoreleasepool {
                        for item in items { document.addSubview(item.view); item.view.removeFromSuperview() }
                    }
                }
                return (CFAbsoluteTimeGetCurrent() - start) * 1000000 / Double(50 * items.count)
            }
            _ = cycle(oldDocument, before); _ = cycle(newDocument, after)
            var oldCycles: [Double] = [], newCycles: [Double] = []
            for batch in 0..<9 {
                if batch % 2 == (reverse ? 1 : 0) { oldCycles.append(cycle(oldDocument, before)); newCycles.append(cycle(newDocument, after)) }
                else { newCycles.append(cycle(newDocument, after)); oldCycles.append(cycle(oldDocument, before)) }
            }
            measurement["baseline_cycle_us"] = oldCycles
            measurement["candidate_cycle_us"] = newCycles
            measurement["baseline_cycle_median_us"] = oldCycles.sorted()[4]
            measurement["candidate_cycle_median_us"] = newCycles.sorted()[4]
            report["automatic-\(automatic)"] = measurement
            print("INLINE_STICKER automatic-\(automatic) attach/remove: \(oldCycles.sorted()[4]) -> \(newCycles.sorted()[4]) us/view")
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/inline-sticker-benchmark.json"))
    }
}
