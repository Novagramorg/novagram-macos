import Cocoa
import XCTest
import TGUIKit

final class BindingTests: XCTestCase {
    private var windows: [NSWindow] = []
    override func setUp() {
        TGUIKitTestBootstrap.install()
        InlineStickerItemLayer.resolvesImmediately = true
        InlineStickerItemLayer.created = 0
    }
    override func tearDown() {
        windows.forEach { $0.contentView = nil; $0.close() }
        windows.removeAll()
        InlineStickerItemLayer.resolvesImmediately = true
        theme = FixtureTheme()
        CATransaction.flush()
    }
    private struct Options {
        var account = Account()
        var packs: InlineStickersContext? = InlineStickersContext()
        var color: NSColor? = nil
        var selected = false
        var big = false
        var playTwice = true
    }
    private struct Binding {
        let view: NSView
        let peer: Peer
        let set: (Options) -> Void
    }
    private func subject(reference: Bool = false) -> Binding {
        let peer = Peer()
        peer.isPremium = true
        peer.emojiStatus = EmojiStatus(1)
        let rect = NSRect(x: 0, y: 0, width: 300, height: 300)
        let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        if reference {
            let view = ReferencePremiumStatusControl(frame: .zero)
            window.contentView?.addSubview(view)
            return Binding(view: view, peer: peer, set: { view.set(peer, account: $0.account, inlinePacksContext: $0.packs, left: false, color: $0.color, isSelected: $0.selected, isBig: $0.big, animated: false, playTwice: $0.playTwice, isLite: false, autoupdate: false) })
        }
        let view = CandidatePremiumStatusControl(frame: .zero)
        window.contentView?.addSubview(view)
        return Binding(view: view, peer: peer, set: { view.set(peer, account: $0.account, inlinePacksContext: $0.packs, left: false, color: $0.color, isSelected: $0.selected, isBig: $0.big, animated: false, playTwice: $0.playTwice, isLite: false, autoupdate: false) })
    }
    private func stateMirror(_ view: NSView) -> Mirror {
        let mirror = Mirror(reflecting: view)
        if let lazy = mirror.children.first(where: { $0.label == "$__lazy_storage_$_renderer" }), let renderer = Mirror(reflecting: lazy.value).children.first?.value {
            return Mirror(reflecting: renderer)
        }
        return mirror
    }
    private func layer(_ view: NSView) throws -> InlineStickerItemLayer {
        let item = stateMirror(view).children.first { $0.label == "animateLayer" }
        return try XCTUnwrap(item.flatMap { Mirror(reflecting: $0.value).children.first?.value as? InlineStickerItemLayer })
    }
    private func configuration(_ view: NSView) -> AnyObject? {
        guard let field = stateMirror(view).children.first(where: { $0.label == "statusConfiguration" }), let object = Mirror(reflecting: field.value).children.first?.value, Mirror(reflecting: object).displayStyle == .class else { return nil }
        return object as AnyObject
    }

    func testRepeatedPendingUpdatesRetainOneLayerAndConfiguration() throws {
        InlineStickerItemLayer.resolvesImmediately = false
        let item = subject(), options = Options()
        item.set(options)
        let original = try layer(item.view)
        let originalConfiguration = try XCTUnwrap(configuration(item.view))
        let created = InlineStickerItemLayer.created
        for _ in 0..<20 { item.set(options) }
        XCTAssertTrue(try layer(item.view) === original)
        XCTAssertTrue(configuration(item.view) === originalConfiguration)
        XCTAssertEqual(InlineStickerItemLayer.created, created)
    }

    func testPendingResolutionKeepsLayerAndDefaultStatusOpacity() throws {
        InlineStickerItemLayer.resolvesImmediately = false
        let item = subject()
        var options = Options()
        options.color = .blue
        item.set(options)
        let original = try layer(item.view)
        let file = TelegramMediaFile(1)
        file.emojiReference = 1
        original.resolve(file)
        XCTAssertEqual(item.view.layer?.opacity, 0.4)
        item.set(options)
        XCTAssertTrue(try layer(item.view) === original)
        XCTAssertEqual(item.view.layer?.opacity, 0.4)
    }

    func testPendingChangesInvalidateCapturedParameters() throws {
        InlineStickerItemLayer.resolvesImmediately = false
        let changes: [(inout Options) -> Void] = [
            { $0.account = Account() }, { $0.packs = InlineStickersContext() }, { $0.packs = nil },
            { $0.selected = true }, { $0.color = .red }, { $0.big = true }
        ]
        for change in changes {
            let item = subject()
            var options = Options()
            item.set(options)
            let original = try layer(item.view)
            change(&options)
            item.set(options)
            let updated = try layer(item.view)
            XCTAssertFalse(original === updated)
            XCTAssertTrue(updated.account === options.account)
            XCTAssertTrue(updated.inlinePacksContext === options.packs)
            XCTAssertEqual(updated.frame.size, item.view.frame.size)
            let tinted = TelegramMediaFile(1)
            tinted.paintToText = true
            XCTAssertEqual(updated.colors(tinted).first?.color, options.selected ? theme.colors.underSelectedColor : options.color ?? theme.colors.accent)
            item.set(options)
            XCTAssertTrue(try layer(item.view) === updated)
        }
    }

    func testLoadedSourceAndSizeChangesReplaceLayer() throws {
        let changes: [(inout Options) -> Void] = [{ $0.account = Account() }, { $0.packs = InlineStickersContext() }, { $0.big = true }]
        for change in changes {
            let item = subject()
            var options = Options()
            item.set(options)
            let original = try layer(item.view)
            change(&options)
            item.set(options)
            let updated = try layer(item.view)
            XCTAssertFalse(original === updated)
            XCTAssertTrue(updated.account === options.account)
            XCTAssertTrue(updated.inlinePacksContext === options.packs)
            XCTAssertEqual(updated.frame.size, item.view.frame.size)
        }
    }

    func testPaintedStatusRespondsToCustomAndThemeColorChanges() throws {
        let item = subject()
        var options = Options()
        options.color = .blue
        item.set(options)
        let first = try layer(item.view)
        first.file?.paintToText = true
        options.color = .red
        item.set(options)
        let second = try layer(item.view)
        XCTAssertFalse(second === first)
        second.file?.paintToText = true
        XCTAssertEqual(second.colors(second.file).first?.color, .red)
        options.color = nil
        item.set(options)
        let third = try layer(item.view)
        third.file?.paintToText = true
        theme.colors.accent = .green
        item.set(options)
        let fourth = try layer(item.view)
        XCTAssertFalse(third === fourth)
        fourth.file?.paintToText = true
        XCTAssertEqual(fourth.colors(fourth.file).first?.color, .green)
    }

    func testUntintedStatusDoesNotRecreateForSelectionOrPalette() throws {
        let item = subject()
        var options = Options()
        item.set(options)
        let original = try layer(item.view)
        options.selected = true
        options.color = .red
        theme.colors.accent = .green
        theme.colors.underSelectedColor = .yellow
        item.set(options)
        XCTAssertTrue(try layer(item.view) === original)
        XCTAssertTrue(original.colors(original.file).isEmpty)
    }

    func testTintComparisonPreservesPrecisionAndReusesEqualValues() throws {
        let item = subject()
        var options = Options()
        let firstColor = NSColor(srgbRed: 0.5001, green: 0.3, blue: 0.2, alpha: 1)
        let secondColor = NSColor(srgbRed: 0.5002, green: 0.3, blue: 0.2, alpha: 1)
        XCTAssertEqual(firstColor.argb, secondColor.argb)
        XCTAssertFalse(firstColor.isEqual(secondColor))
        options.color = firstColor
        item.set(options)
        let original = try layer(item.view)
        original.file?.paintToText = true
        options.color = secondColor
        item.set(options)
        let updated = try layer(item.view)
        updated.file?.paintToText = true
        XCTAssertFalse(updated === original)
        XCTAssertTrue(try XCTUnwrap(updated.colors(updated.file).first?.color).isEqual(secondColor))
        options.color = NSColor(srgbRed: 0.5002, green: 0.3, blue: 0.2, alpha: 1)
        item.set(options)
        XCTAssertTrue(try layer(item.view) === updated)
    }

    func testPendingThemeChangesRefreshFutureTint() throws {
        InlineStickerItemLayer.resolvesImmediately = false
        let item = subject(), options = Options()
        item.set(options)
        let original = try layer(item.view)
        theme.colors.accent = .red
        item.set(options)
        let updated = try layer(item.view)
        XCTAssertFalse(updated === original)
        let file = TelegramMediaFile(1)
        file.paintToText = true
        updated.resolve(file)
        XCTAssertEqual(updated.colors(file).first?.color, .red)
        item.set(options)
        XCTAssertTrue(try layer(item.view) === updated)
    }

    func testCustomColorPresenceRefreshesDefaultStatusOpacity() throws {
        let item = subject()
        var options = Options()
        item.set(options)
        let original = try layer(item.view)
        original.file?.emojiReference = 1
        options.color = theme.colors.accent
        item.set(options)
        let updated = try layer(item.view)
        XCTAssertFalse(original === updated)
        updated.file?.emojiReference = 1
        updated.fileDidUpdate?(updated.file)
        item.set(options)
        XCTAssertEqual(item.view.layer?.opacity, 0.4)
        options.color = nil
        item.set(options)
        XCTAssertEqual(item.view.layer?.opacity, 1)
    }

    func testLoopPolicyChangeRestartsPreviouslyFinishedStatus() throws {
        let item = subject()
        var options = Options()
        options.big = true
        item.set(options)
        let original = try layer(item.view)
        XCTAssertEqual(original.policy, .playCount(2))
        original.stopped = true
        options.playTwice = false
        item.set(options)
        let updated = try layer(item.view)
        XCTAssertFalse(updated === original)
        XCTAssertEqual(updated.policy, .loop)
        XCTAssertFalse(updated.stopped)
    }

    func testTintChangePreservesCompletedFinitePlayback() throws {
        let item = subject()
        var options = Options()
        item.set(options)
        let original = try layer(item.view)
        original.stopped = true
        original.file?.paintToText = true
        options.selected = true
        item.set(options)
        let updated = try layer(item.view)
        XCTAssertFalse(original === updated)
        XCTAssertTrue(updated.stopped)
    }

    func testDifferentFileAndAccountDoNotCarryCompletedPlayback() throws {
        for changeAccount in [false, true] {
            let item = subject()
            var options = Options()
            item.set(options)
            let original = try layer(item.view)
            original.stopped = true
            if changeAccount { options.account = Account() }
            else { item.peer.emojiStatus = EmojiStatus(2) }
            item.set(options)
            let updated = try layer(item.view)
            XCTAssertFalse(updated === original)
            XCTAssertFalse(updated.stopped)
        }
    }

    func testConfigurationIsReleasedWhenStatusBecomesStatic() throws {
        let item = subject(), options = Options()
        item.set(options)
        weak var old = try XCTUnwrap(configuration(item.view))
        item.peer.emojiStatus = nil
        item.set(options)
        XCTAssertNil(configuration(item.view))
        XCTAssertNil(old)
    }

    func testNilResolutionAllowsRetryInsteadOfPermanentPendingReuse() throws {
        InlineStickerItemLayer.resolvesImmediately = false
        let item = subject(), options = Options()
        item.set(options)
        let original = try layer(item.view)
        XCTAssertFalse(original.hasFileResolutionResult)
        var resolvedBeforeCallback = false
        let callback = original.fileDidUpdate
        original.fileDidUpdate = { [weak original] file in
            resolvedBeforeCallback = original?.hasFileResolutionResult == true
            callback?(file)
        }
        original.resolve(nil)
        XCTAssertTrue(resolvedBeforeCallback)
        XCTAssertTrue(original.hasFileResolutionResult)
        item.set(options)
        let retry = try layer(item.view)
        XCTAssertFalse(original === retry)
        XCTAssertFalse(retry.hasFileResolutionResult)
        item.set(options)
        XCTAssertTrue(try layer(item.view) === retry)
    }

    func testResolutionStateIsAvailableForImmediateAndDelayedFiles() throws {
        for immediate in [false, true] {
            InlineStickerItemLayer.resolvesImmediately = immediate
            let item = subject(), options = Options()
            item.set(options)
            let current = try layer(item.view)
            XCTAssertEqual(current.hasFileResolutionResult, immediate)
            if !immediate { current.resolve(TelegramMediaFile(1)) }
            XCTAssertTrue(current.hasFileResolutionResult)
            item.set(options)
            XCTAssertTrue(try layer(item.view) === current)
        }
    }

    func testBindingBenchmark() throws {
        guard ProcessInfo.processInfo.environment["STATUS_BINDING_BENCHMARK"] != nil else { throw XCTSkip("Opt-in binding benchmark") }
        var report: [String: Any] = [:]
        for pending in [true, false] {
            InlineStickerItemLayer.resolvesImmediately = !pending
            let before = subject(reference: true), after = subject(), options = Options()
            before.set(options); after.set(options)
            let count = 1000
            func measure(_ item: Binding, expected: Int) -> Double {
                let created = InlineStickerItemLayer.created
                let start = CFAbsoluteTimeGetCurrent()
                autoreleasepool { for _ in 0..<count { item.set(options) } }
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000000 / Double(count)
                XCTAssertEqual(InlineStickerItemLayer.created - created, expected)
                return elapsed
            }
            _ = measure(before, expected: pending ? count : 0); _ = measure(after, expected: 0)
            var baseline: [Double] = [], candidate: [Double] = []
            let reverse = ProcessInfo.processInfo.environment["STATUS_BINDING_REVERSE"] != nil
            for batch in 0..<9 {
                if batch % 2 == (reverse ? 1 : 0) { baseline.append(measure(before, expected: pending ? count : 0)); candidate.append(measure(after, expected: 0)) }
                else { candidate.append(measure(after, expected: 0)); baseline.append(measure(before, expected: pending ? count : 0)) }
            }
            let config = try XCTUnwrap(configuration(after.view))
            let configurationBytes = malloc_size(Unmanaged.passUnretained(config).toOpaque())
            let oldViewBytes = malloc_size(Unmanaged.passUnretained(before.view).toOpaque())
            let newViewBytes = malloc_size(Unmanaged.passUnretained(after.view).toOpaque())
            report[pending ? "pending" : "resolved"] = ["baseline_us": baseline, "candidate_us": candidate, "baseline_median_us": baseline.sorted()[4], "candidate_median_us": candidate.sorted()[4], "baseline_creations_per_1000_updates": pending ? count : 0, "candidate_creations_per_1000_updates": 0, "configuration_bytes": configurationBytes, "baseline_view_bytes": oldViewBytes, "candidate_view_bytes": newViewBytes]
            print("STATUS_BINDING pending=\(pending): \(baseline.sorted()[4]) -> \(candidate.sorted()[4]) us/update")
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/premium-status-binding-benchmark.json"))
    }
}
