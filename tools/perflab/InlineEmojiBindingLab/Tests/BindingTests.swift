import Cocoa
import XCTest
import TGUIKit
import TelegramContext
import InputView
import InlineStickerLayer
import CandidateBindingHarness
import NativeBindingHarness

private protocol BindingDriver {
    var root: NSView { get }
    var rendersLayers: Bool { get }
    var rendersNative: Bool { get }
    var texts: [TextViewLayout] { get }
    var media: [InlineStickerItemLayer] { get }
    func bind(_ index: Int)
    func selectFirst(_ range: NSRange)
    func copyFirst() -> NSAttributedString?
}
extension CandidateBindingHarness.BenchmarkDriver: BindingDriver {}
extension NativeBindingHarness.BenchmarkDriver: BindingDriver {}

private struct PreflightFailure: Error, CustomStringConvertible {
    let description: String
}

private final class BindingWindow: NSWindow {
    var scale: CGFloat = 2
    override var backingScaleFactor: CGFloat { scale }
    override var isKeyWindow: Bool { true }
}

private final class BindingHost {
    let window: BindingWindow
    let scroll: NSScrollView
    let document: View
    init(_ root: NSView, scale: CGFloat, viewportHeight: CGFloat? = nil) {
        let size = CGSize(width: root.frame.width, height: viewportHeight ?? root.frame.height)
        window = BindingWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.scale = scale
        window.isReleasedWhenClosed = false
        scroll = NSScrollView(frame: CGRect(origin: .zero, size: size))
        document = View(frame: CGRect(x: 0, y: 0, width: size.width, height: root.frame.height + 1200))
        window.contentView = scroll
        scroll.documentView = document
        scroll.contentView.postsBoundsChangedNotifications = false
        document.addSubview(root)
    }
    func move(to y: CGFloat) {
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }
    deinit { window.close() }
}

final class BindingTests: XCTestCase {
    private var preflightContext = ""

    override func setUp() {
        TGUIKitTestBootstrap.install()
        System.updateScaleFactor(2)
    }
    override func tearDown() { System.updateScaleFactor(2) }

    private func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else {
            let description = "\(preflightContext): \(message)"
            FileHandle.standardError.write(Data("INLINE_EMOJI_PREFLIGHT_FAILURE \(description)\n".utf8))
            throw PreflightFailure(description: description)
        }
    }

    private func copyIds(_ text: NSAttributedString?) -> [Int64] {
        guard let text else { return [] }
        var ids: [Int64] = []
        text.enumerateAttribute(TextInputAttributes.customEmoji, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let emoji = value as? TextInputTextCustomEmojiAttribute { ids.append(emoji.fileId) }
        }
        return ids
    }

    private struct MediaRecord: Equatable {
        let source: Int64
        let base: NSColor
        let tint: NSColor?
        let size: CGSize
        let frame: CGRect
    }

    private func records(_ driver: any BindingDriver) -> [MediaRecord] {
        return driver.media.map {
            MediaRecord(source: $0.source.fileId, base: $0.textColor, tint: $0.color, size: $0.size, frame: driver.root.layer!.convert($0.bounds, from: $0))
        }.sorted {
            if $0.frame.minY != $1.frame.minY { return $0.frame.minY < $1.frame.minY }
            if $0.frame.minX != $1.frame.minX { return $0.frame.minX < $1.frame.minX }
            return $0.source < $1.source
        }
    }

    private func verifyMedia(_ driver: any BindingDriver, expected: Int, account: Account) throws {
        try require(driver.media.count == expected, "Missing media: expected \(expected), found \(driver.media.count)")
        let embedded = driver.texts.flatMap { $0.embeddedItems }
        let expectedSources = embedded.compactMap { item -> Int64? in
            guard let sticker = item.value as? InlineStickerItem, case let .attribute(emoji) = sticker.source else { return nil }
            return emoji.fileId
        }.sorted()
        try require(driver.media.map { $0.source.fileId }.sorted() == expectedSources, "Rendered source IDs differ from measured input")
        try require(driver.media.allSatisfy { $0.accountId == ObjectIdentifier(account) && $0.contents != nil && $0.size.width > 10 && $0.textColor == NSColor.black }, "Account/color/size/bitmap preflight failed")
        try require(driver.media.allSatisfy { $0.color == $0.source.color }, "Explicit tint lost")
        try require(driver.media.map { $0.size }.sorted { $0.width < $1.width } == embedded.map { $0.rect.size }.sorted { $0.width < $1.width }, "Media dimensions differ from measured input")
    }

    private func preflight() throws {
        var pixels = 0
        for scale: CGFloat in [1, 2, 3] {
            System.updateScaleFactor(scale)
            for caption in [false, true] {
                for blocks in [1, 4, 12] {
                    let fixtureContext = "scale=\(scale), captions=\(caption), blocks=\(blocks)"
                    preflightContext = fixtureContext + ", phase=construction"
                    try autoreleasepool {
                        let account = Account()
                        let nativeFixtures = NativeBindingHarness.BenchmarkFixtures(account: account, caption: caption, blocks: blocks)
                        let layerFixtures = CandidateBindingHarness.BenchmarkFixtures(account: account, caption: caption, blocks: blocks)
                        let native = NativeBindingHarness.BenchmarkDriver(fixtures: nativeFixtures)
                        let layer = CandidateBindingHarness.BenchmarkDriver(fixtures: layerFixtures)
                        let nativeHost = BindingHost(native.root, scale: scale), layerHost = BindingHost(layer.root, scale: scale)
                        for variant in 0..<5 {
                            preflightContext = fixtureContext + ", variant=\(variant), phase=binding"
                            native.bind(variant)
                            layer.bind(variant)
                            nativeHost.window.contentView?.layoutSubtreeIfNeeded()
                            layerHost.window.contentView?.layoutSubtreeIfNeeded()
                            CATransaction.flush()
                            try require(native.rendersNative, "Pre-inline baseline did not instantiate native FoldingTextView")
                            try require(layer.rendersLayers, "Candidate did not instantiate layer host")
                            try verifyMedia(native, expected: blocks * 3, account: account)
                            try verifyMedia(layer, expected: blocks * 3, account: account)
                            let nativeRecords = records(native), layerRecords = records(layer)
                            if nativeRecords != layerRecords {
                                FileHandle.standardError.write(Data("INLINE_EMOJI_MEDIA_RECORDS \(preflightContext)\nnative=\(nativeRecords)\nlayer=\(layerRecords)\n".utf8))
                            }
                            try require(nativeRecords == layerRecords, "Native/layer media source, tint, size or row-coordinate frame differs")
                            preflightContext = fixtureContext + ", variant=\(variant), phase=pixels"
                            let a = ViewSnapshot.render(native.root, scale: scale, keepingWindow: true)
                            let b = ViewSnapshot.render(layer.root, scale: scale, keepingWindow: true)
                            try require(a.differingPixels(from: b, tolerance: 0) == 0, "Pixel mismatch scale=\(scale), captions=\(caption), blocks=\(blocks), variant=\(variant)")
                            pixels += 1
                        }
                        native.bind(0)
                        layer.bind(0)
                        preflightContext = fixtureContext + ", variant=0, phase=selection"
                        let range = NSRange(location: 0, length: native.texts[0].attributedString.length)
                        native.selectFirst(range)
                        layer.selectFirst(range)
                        try require(copyIds(native.copyFirst()) == copyIds(layer.copyFirst()) && copyIds(layer.copyFirst()).count == 3, "Selected custom emoji copy metadata differs")
                        try require(native.texts[0].selectedRange.range == layer.texts[0].selectedRange.range, "Selection range differs")
                        try require(ViewSnapshot.render(native.root, scale: scale, keepingWindow: true).differingPixels(from: ViewSnapshot.render(layer.root, scale: scale, keepingWindow: true), tolerance: 0) == 0, "Selected pixels differ")
                        pixels += 1
                        native.selectFirst(NSRange(location: NSNotFound, length: 0))
                        layer.selectFirst(NSRange(location: NSNotFound, length: 0))
                        for y in [CGFloat(0), native.root.frame.height + 50, 0] {
                            preflightContext = fixtureContext + ", variant=0, phase=visibility, scrollY=\(y)"
                            nativeHost.move(to: y)
                            layerHost.move(to: y)
                            try require(native.media.filter { $0.isPlayable == true }.count == layer.media.filter { $0.isPlayable == true }.count, "Visible playback counts differ")
                        }
                        preflightContext = fixtureContext + ", phase=view-count"
                        try require(viewTreeCount(native.root) > viewTreeCount(layer.root), "Candidate did not reduce row NSView count")
                    }
                }
            }
        }
        print("INLINE_EMOJI_PREFLIGHT pixels=\(pixels) matched_native_media=true")
    }

    func testPreflight() throws { try preflight() }

    private func measure<D: BindingDriver>(role: String, caption: Bool, blocks: Int, make: () -> D) throws {
        let samples = 9
        let iterations = 120
        let phases = ["construction", "same", "edited", "changed_source", "visibility"] + (caption ? ["caption_reorder"] : [])
        for phase in phases {
            var times: [Double] = []
            let driver = make()
            let host = phase == "visibility" ? BindingHost(driver.root, scale: 2, viewportHeight: 160) : nil
            driver.bind(0)
            for _ in 0..<20 { driver.bind(1); driver.bind(0) }
            for _ in 0..<samples {
                let elapsed: Double = autoreleasepool {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    let start = CACurrentMediaTime()
                    for iteration in 0..<iterations {
                        switch phase {
                        case "construction":
                            autoreleasepool {
                                let created = make()
                                created.bind(0)
                                withExtendedLifetime(created) {}
                            }
                        case "same": driver.bind(iteration % 2 == 0 ? 0 : 1)
                        case "edited": driver.bind(iteration % 2 == 0 ? 0 : 2)
                        case "changed_source": driver.bind(iteration % 2 == 0 ? 0 : 3)
                        case "caption_reorder": driver.bind(iteration % 2 == 0 ? 0 : 4)
                        default: host?.move(to: iteration % 2 == 0 ? 0 : 190)
                        }
                    }
                    let elapsed = CACurrentMediaTime() - start
                    CATransaction.commit()
                    CATransaction.flush()
                    return elapsed
                }
                times.append(elapsed * 1_000_000_000 / Double(iterations))
            }
            try require(driver.media.count == blocks * 3, "Measured driver lost media")
            let sorted = times.sorted()
            let result: [String: Any] = ["role": role, "caption": caption, "blocks": blocks, "phase": phase, "iterations": iterations, "samples": times, "median_ns": sorted[sorted.count / 2], "max_ns": sorted.last!, "views": viewTreeCount(driver.root), "media": driver.media.count]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print("INLINE_EMOJI_BINDING " + String(data: data, encoding: .utf8)!)
        }
    }

    func testBenchmark() throws {
        guard ProcessInfo.processInfo.environment["INLINE_EMOJI_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in serial benchmark") }
        try preflight()
        System.updateScaleFactor(2)
        let role = ProcessInfo.processInfo.environment["INLINE_EMOJI_ROLE"] ?? ""
        try require(["native", "layer"].contains(role), "Set INLINE_EMOJI_ROLE to native or layer")
        let account = Account()
        for caption in [false, true] {
            for blocks in [1, 4, 12] {
                if role == "native" {
                    let fixtures = NativeBindingHarness.BenchmarkFixtures(account: account, caption: caption, blocks: blocks)
                    try measure(role: role, caption: caption, blocks: blocks) { NativeBindingHarness.BenchmarkDriver(fixtures: fixtures) }
                } else {
                    let fixtures = CandidateBindingHarness.BenchmarkFixtures(account: account, caption: caption, blocks: blocks)
                    try measure(role: role, caption: caption, blocks: blocks) { CandidateBindingHarness.BenchmarkDriver(fixtures: fixtures) }
                }
            }
        }
    }
}
