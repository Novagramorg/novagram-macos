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
        let set: (Peer, Bool, Bool, Bool, Bool) -> Void
    }
    private func subject(reference: Bool = false) -> Subject {
        let account = Account()
        if reference {
            let view = ReferencePremiumStatusControl(frame: .zero)
            return Subject(view: view, set: { view.set($0, account: account, inlinePacksContext: nil, left: $1, color: nil, isSelected: $2, isBig: false, animated: $3, isLite: $4) })
        }
        let view = CandidatePremiumStatusControl(frame: .zero)
        return Subject(view: view, set: { view.set($0, account: account, inlinePacksContext: nil, left: $1, color: nil, isSelected: $2, isBig: false, animated: $3, isLite: $4) })
    }
    private func peer(_ kind: Int = 0, id: Int64 = 1) -> Peer {
        let peer = Peer()
        switch kind {
        case 0: peer.isVerified = true
        case 1: peer.isPremium = true
        case 2: peer.isFake = true
        case 3: peer.isScam = true
        case 4: peer.isPremium = true; peer.emojiStatus = EmojiStatus(id)
        case 5: peer.isPremium = true; peer.emojiStatus = EmojiStatus(id, gift: true)
        case 6: peer.verificationIconFileId = id
        case 7: peer.isFake = true; peer.emojiStatus = EmojiStatus(id, gift: true)
        default: break
        }
        return peer
    }
    private func value<T>(_ view: NSView, _ name: String) -> T? {
        var mirrors = [Mirror(reflecting: view)]
        if let lazy = mirrors[0].children.first(where: { $0.label == "$__lazy_storage_$_renderer" }), let renderer = Mirror(reflecting: lazy.value).children.first?.value {
            mirrors.append(Mirror(reflecting: renderer))
        }
        for mirror in mirrors {
            for item in mirror.children where item.label == name {
                if let object = item.value as? T { return object }
                return Mirror(reflecting: item.value).children.first?.value as? T
            }
        }
        return nil
    }
    private func observer(_ view: NSView) -> AnimatableContentObserver? { value(view, "animatableContentObserver") }
    private func emoji(_ view: NSView) -> InlineStickerItemLayer? { value(view, "animateLayer") }
    private func stars(_ view: NSView) -> StarsEffectLayer? { value(view, "starsLayer") }
    private func host() -> (FixtureWindow, NSScrollView, NSView) {
        let rect = NSRect(x: 0, y: 0, width: 300, height: 300)
        let window = FixtureWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let document = View(frame: NSRect(x: 0, y: 0, width: 300, height: 1000))
        let scroll = NSScrollView(frame: rect)
        scroll.documentView = document
        window.contentView = scroll
        windows.append(window)
        return (window, scroll, document)
    }
    private func post(_ name: Notification.Name, _ object: AnyObject) {
        NotificationCenter.default.post(name: name, object: object)
    }

    func testStaticBadgesNeverAllocateObserver() {
        let (_, scroll, document) = host()
        for kind in 0...3 {
            let item = subject()
            XCTAssertNil(observer(item.view))
            document.addSubview(item.view)
            item.set(peer(kind), false, false, false, false)
            XCTAssertNil(observer(item.view))
            XCTAssertNil(emoji(item.view))
            XCTAssertNil(stars(item.view))
            post(NSView.boundsDidChangeNotification, scroll.contentView)
            XCTAssertNil(observer(item.view))
        }
    }

    func testDetachedEmojiDefersObserverUntilAttachment() throws {
        let (_, _, document) = host()
        let item = subject()
        item.set(peer(4), false, false, false, false)
        XCTAssertNil(observer(item.view))
        let layer = try XCTUnwrap(emoji(item.view))
        XCTAssertEqual(layer.isPlayable, false)
        document.addSubview(item.view)
        XCTAssertNotNil(observer(item.view))
        XCTAssertEqual(layer.isPlayable, true)
    }

    func testReplacementStopsOldEmojiBeforeAnimatedRemoval() throws {
        let (_, _, document) = host()
        let item = subject()
        document.addSubview(item.view)
        item.set(peer(4, id: 1), false, false, false, false)
        let old = try XCTUnwrap(emoji(item.view))
        XCTAssertEqual(old.isPlayable, true)
        item.set(peer(4, id: 2), false, false, true, false)
        let new = try XCTUnwrap(emoji(item.view))
        XCTAssertFalse(new === old)
        XCTAssertEqual(old.isPlayable, false)
        XCTAssertEqual(new.isPlayable, true)
    }

    func testSelectionReplacementStopsTintedEmoji() throws {
        let (_, _, document) = host()
        let item = subject(), currentPeer = peer(4)
        document.addSubview(item.view)
        item.set(currentPeer, false, false, false, false)
        let old = try XCTUnwrap(emoji(item.view))
        old.file?.paintToText = true
        item.set(currentPeer, false, true, true, false)
        XCTAssertFalse(emoji(item.view) === old)
        XCTAssertEqual(old.isPlayable, false)
        XCTAssertEqual(emoji(item.view)?.isPlayable, true)
    }

    func testRemovedFileCallbackCannotChangeReusedControlOpacity() throws {
        let (_, _, document) = host()
        for replacement in [0, 4] {
            let view = CandidatePremiumStatusControl(frame: .zero), account = Account()
            document.addSubview(view)
            view.set(peer(4), account: account, inlinePacksContext: nil, left: false, color: .blue, isSelected: false, isBig: false, animated: false, isLite: false)
            let old = try XCTUnwrap(emoji(view))
            old.file?.emojiReference = 1
            view.set(peer(replacement, id: 2), account: account, inlinePacksContext: nil, left: false, color: nil, isSelected: false, isBig: false, animated: true, isLite: false)
            let opacity = try XCTUnwrap(view.layer?.opacity)
            XCTAssertEqual(opacity, 1)
            old.fileDidUpdate?(old.file)
            XCTAssertEqual(view.layer?.opacity, opacity)
            XCTAssertNil(old.fileDidUpdate)
        }
    }

    func testStoppingRemovalPreservesDisplayedFrameInsteadOfPreview() throws {
        let (_, _, document) = host()
        for replacement in [0, 4] {
            let item = subject()
            document.addSubview(item.view)
            item.set(peer(4), false, false, false, false)
            let old = try XCTUnwrap(emoji(item.view))
            let bitmap = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            bitmap.setFillColor(NSColor.red.cgColor)
            bitmap.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            let displayed = try XCTUnwrap(bitmap.makeImage())
            old.contents = displayed
            old.preview = theme.icons.verifyDialog
            item.set(peer(replacement, id: 2), false, false, true, false)
            XCTAssertEqual(old.isPlayable, false)
            XCTAssertTrue((old.contents as AnyObject?) === displayed)
        }
    }

    func testPlainTransitionStopsEmojiAndStarsAndReleasesObserver() throws {
        let (_, scroll, document) = host()
        let item = subject()
        document.addSubview(item.view)
        item.set(peer(5), false, false, false, false)
        let oldEmoji = try XCTUnwrap(emoji(item.view))
        let oldStars = try XCTUnwrap(stars(item.view))
        weak var oldObserver = try XCTUnwrap(observer(item.view))
        item.set(peer(0), false, false, true, false)
        XCTAssertEqual(oldEmoji.isPlayable, false)
        XCTAssertFalse(oldStars.isPlaying)
        XCTAssertNil(emoji(item.view)); XCTAssertNil(stars(item.view))
        XCTAssertNil(observer(item.view)); XCTAssertNil(oldObserver)
        oldEmoji.writes = 0; oldStars.writes = 0
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertEqual(oldEmoji.writes, 0); XCTAssertEqual(oldStars.writes, 0)
    }

    func testStarsOnlyContentStillObservesVisibility() throws {
        let (window, _, document) = host()
        let item = subject()
        document.addSubview(item.view)
        item.set(peer(7), false, false, false, false)
        XCTAssertNil(emoji(item.view))
        let layer = try XCTUnwrap(stars(item.view))
        XCTAssertNotNil(observer(item.view))
        XCTAssertTrue(layer.isPlaying)
        window.key = false
        post(NSWindow.didResignKeyNotification, window)
        XCTAssertFalse(layer.isPlaying)
    }

    func testReusingEmojiPreservesLayerAndObserver() throws {
        let (_, scroll, document) = host()
        let item = subject(), currentPeer = peer(4)
        document.addSubview(item.view)
        item.set(currentPeer, false, false, false, false)
        let layer = try XCTUnwrap(emoji(item.view)), oldObserver = try XCTUnwrap(observer(item.view))
        for _ in 0..<5 { item.set(currentPeer, false, false, false, false) }
        XCTAssertTrue(emoji(item.view) === layer)
        XCTAssertTrue(observer(item.view) === oldObserver)
        layer.writes = 0
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertEqual(layer.writes, 1)
    }

    func testLiteKeyWindowAndNonKeyCapableWindowPolicies() throws {
        let (window, _, document) = host()
        let item = subject(), currentPeer = peer(5)
        document.addSubview(item.view)
        item.set(currentPeer, false, false, false, false)
        let layer = try XCTUnwrap(emoji(item.view)), particles = try XCTUnwrap(stars(item.view))
        item.set(currentPeer, false, false, false, true)
        XCTAssertEqual(layer.isPlayable, false); XCTAssertFalse(particles.isPlaying)
        item.set(currentPeer, false, false, false, false)
        XCTAssertEqual(layer.isPlayable, true); XCTAssertTrue(particles.isPlaying)
        window.key = false
        post(NSWindow.didResignKeyNotification, window)
        XCTAssertEqual(layer.isPlayable, false); XCTAssertFalse(particles.isPlaying)
        window.acceptsKey = false
        post(NSWindow.didBecomeKeyNotification, window)
        XCTAssertEqual(layer.isPlayable, true); XCTAssertTrue(particles.isPlaying)
    }

    func testScrollingAndOwnFrameChangesUpdatePlayback() throws {
        let (_, scroll, document) = host()
        let item = subject()
        document.addSubview(item.view)
        item.set(peer(5), false, false, false, false)
        let layer = try XCTUnwrap(emoji(item.view)), particles = try XCTUnwrap(stars(item.view))
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 400))
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertEqual(layer.isPlayable, false)
        XCTAssertFalse(particles.isPlaying, "visibleRect=\(item.view.visibleRect), empty=\(item.view.visibleRect.isEmpty), emojiFrame=\(layer.frame)")
        scroll.contentView.scroll(to: .zero)
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertEqual(layer.isPlayable, true); XCTAssertTrue(particles.isPlaying)
        item.view.setFrameOrigin(NSPoint(x: 500, y: 0))
        post(NSView.frameDidChangeNotification, item.view)
        XCTAssertEqual(layer.isPlayable, false)
        XCTAssertFalse(particles.isPlaying, "visibleRect=\(item.view.visibleRect), empty=\(item.view.visibleRect.isEmpty), emojiFrame=\(layer.frame)")
    }

    func testDetachAndReparentReleaseOldScope() throws {
        let (oldWindow, oldScroll, oldDocument) = host()
        let (_, newScroll, newDocument) = host()
        let item = subject()
        oldDocument.addSubview(item.view)
        item.set(peer(5), false, false, false, false)
        let layer = try XCTUnwrap(emoji(item.view)), particles = try XCTUnwrap(stars(item.view))
        weak var oldObserver = try XCTUnwrap(observer(item.view))
        item.view.removeFromSuperview()
        XCTAssertNil(oldObserver); XCTAssertNil(observer(item.view))
        XCTAssertEqual(layer.isPlayable, false); XCTAssertFalse(particles.isPlaying)
        newDocument.addSubview(item.view)
        layer.writes = 0; particles.writes = 0
        post(NSView.boundsDidChangeNotification, oldScroll.contentView)
        post(NSWindow.didResignKeyNotification, oldWindow)
        XCTAssertEqual(layer.writes, 0); XCTAssertEqual(particles.writes, 0)
        post(NSView.boundsDidChangeNotification, newScroll.contentView)
        XCTAssertEqual(layer.writes, 1); XCTAssertEqual(particles.writes, 1)
    }

    func testParticlesRemainActiveUntilTheirOwnFrameLeavesViewport() throws {
        let (_, scroll, document) = host()
        let item = subject()
        document.addSubview(item.view)
        item.set(peer(5), false, false, false, false)
        let layer = try XCTUnwrap(stars(item.view))
        XCTAssertGreaterThan(layer.frame.maxY, item.view.bounds.maxY)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: layer.frame.maxY - 1))
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertTrue(layer.isPlaying)
        XCTAssertEqual(emoji(item.view)?.isPlayable, false)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: layer.frame.maxY))
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertFalse(layer.isPlaying)
        scroll.contentView.scroll(to: .zero)
        post(NSView.boundsDidChangeNotification, scroll.contentView)
        XCTAssertTrue(layer.isPlaying)
    }

    func testLeftVerificationAndGeometryMatchReference() {
        let (_, _, document) = host()
        for kind in 0...7 {
            for selected in [false, true] {
                let before = subject(reference: true), after = subject(), currentPeer = peer(kind)
                document.addSubview(before.view); document.addSubview(after.view)
                before.set(currentPeer, kind == 6, selected, false, false)
                after.set(currentPeer, kind == 6, selected, false, false)
                before.view.layout(); after.view.layout()
                XCTAssertEqual(before.view.frame, after.view.frame)
                XCTAssertEqual(before.view.layer?.opacity, after.view.layer?.opacity)
                XCTAssertEqual(emoji(before.view)?.frame, emoji(after.view)?.frame)
                XCTAssertEqual(emoji(before.view)?.fileId, emoji(after.view)?.fileId)
                XCTAssertEqual(emoji(before.view)?.isPlayable, emoji(after.view)?.isPlayable)
                let oldImage: SimpleLayer? = value(before.view, "imageLayer")
                let newImage: SimpleLayer? = value(after.view, "imageLayer")
                XCTAssertEqual(oldImage?.frame, newImage?.frame)
                XCTAssertEqual(oldImage?.contentsScale, newImage?.contentsScale)
                XCTAssertEqual(stars(before.view)?.frame, stars(after.view)?.frame)
                XCTAssertEqual(stars(before.view)?.isPlaying, stars(after.view)?.isPlaying)
                before.view.removeFromSuperview(); after.view.removeFromSuperview()
            }
        }
    }

    func testNotificationBenchmark() throws {
        guard ProcessInfo.processInfo.environment["PREMIUM_STATUS_BENCHMARK"] != nil else { throw XCTSkip("Opt-in notification benchmark") }
        var report: [String: Any] = [:]
        for active in [0, 20, 40] {
            let (_, oldScroll, oldDocument) = host(), (_, newScroll, newDocument) = host()
            let before = (0..<40).map { _ in subject(reference: true) }, after = (0..<40).map { _ in subject() }
            for index in 0..<40 {
                oldDocument.addSubview(before[index].view); newDocument.addSubview(after[index].view)
                before[index].set(peer(index < active ? 4 : 0), false, false, false, false)
                after[index].set(peer(index < active ? 4 : 0), false, false, false, false)
            }
            let oldLayers = before.compactMap { emoji($0.view) }, newLayers = after.compactMap { emoji($0.view) }
            func measure(_ scroll: NSScrollView, _ layers: [InlineStickerItemLayer]) -> Double {
                layers.forEach { $0.writes = 0 }
                let start = CFAbsoluteTimeGetCurrent()
                for _ in 0..<1000 { post(NSView.boundsDidChangeNotification, scroll.contentView) }
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
                XCTAssertEqual(layers.reduce(0) { $0 + $1.writes }, active * 1000)
                return elapsed
            }
            _ = measure(oldScroll, oldLayers); _ = measure(newScroll, newLayers)
            var baseline: [Double] = [], candidate: [Double] = []
            let reverse = ProcessInfo.processInfo.environment["PREMIUM_STATUS_REVERSE"] != nil
            for batch in 0..<9 {
                if batch % 2 == (reverse ? 1 : 0) { baseline.append(measure(oldScroll, oldLayers)); candidate.append(measure(newScroll, newLayers)) }
                else { candidate.append(measure(newScroll, newLayers)); baseline.append(measure(oldScroll, oldLayers)) }
            }
            let oldObservers = before.compactMap { observer($0.view) }, newObservers = after.compactMap { observer($0.view) }
            XCTAssertEqual(oldObservers.count, 40); XCTAssertEqual(newObservers.count, active)
            report["animated-\(active)"] = ["baseline_us": baseline, "candidate_us": candidate, "baseline_median_us": baseline.sorted()[4], "candidate_median_us": candidate.sorted()[4], "baseline_observers": oldObservers.count, "candidate_observers": newObservers.count]
            print("PREMIUM_STATUS animated-\(active): \(baseline.sorted()[4]) -> \(candidate.sorted()[4]) us/post; observers \(oldObservers.count) -> \(newObservers.count)")
            before.forEach { $0.view.removeFromSuperview() }; after.forEach { $0.view.removeFromSuperview() }
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/premium-status-lifecycle-benchmark.json"))
    }
}
