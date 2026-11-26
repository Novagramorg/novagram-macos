import Cocoa
import XCTest
import TGUIKit
@testable import PeerRows

final class PaidBadgeTests: XCTestCase {
    override func setUp() {
        initializeLab()
        theme = AccessoryGlobalTheme()
    }
    override func tearDown() {
        System.updateScaleFactor(2)
        super.tearDown()
    }

    private func pixels(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: image.width * image.height * 4)
    }
    private func assertEqual(_ before: PaidBadgeEnvironment, _ after: PaidBadgeEnvironment, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(before.photoBadge == nil, after.photoBadge == nil, file: file, line: line)
        XCTAssertEqual(before.photoBadge?.frame, after.photoBadge?.frame, file: file, line: line)
        XCTAssertEqual(before.photoBadge?.isAccessibilityDecorative, after.photoBadge?.isAccessibilityDecorative, file: file, line: line)
        if let lhs = before.photoBadge?.image, let rhs = after.photoBadge?.image {
            XCTAssertEqual(lhs.width, rhs.width, file: file, line: line)
            XCTAssertEqual(lhs.height, rhs.height, file: file, line: line)
            XCTAssertEqual(pixels(lhs), pixels(rhs), file: file, line: line)
            XCTAssertTrue(pixels(rhs).contains { $0 != 0 }, file: file, line: line)
        }
    }

    func testRepeatedSelectionUpdatesReusePaidBadgeImage() {
        let before = ReferencePaidBadgeView(), after = CurrentPaidBadgeView(), item = ShortPeerRowItem()
        item.drawStarsPaid = BadgeAmount(value: 2500)
        before.bind(item: item, value: nil, animated: false)
        after.bind(item: item, value: nil, animated: false)
        let original = before.photoBadge!.image!, cached = after.photoBadge!.image!, view = after.photoBadge!
        for index in 0..<1000 {
            let presentation = SelectPeerPresentation(premiumRequired: index % 2 == 0 ? [item.peerId] : [])
            before.bind(item: item, value: presentation, animated: false)
            after.bind(item: item, value: presentation, animated: false)
            XCTAssertTrue(after.photoBadge === view)
            XCTAssertTrue(after.photoBadge!.image === cached)
        }
        XCTAssertFalse(before.photoBadge!.image === original)
        assertEqual(before, after)
    }

    func testAmountThemeAndScalePixelsMatchBaseline() {
        let before = ReferencePaidBadgeView(), after = CurrentPaidBadgeView(), item = ShortPeerRowItem()
        let amounts: [Int64] = [0, 1, 9, 10, 99, 999, 1000, 1250, 9999, 1000000, 999999999, -1]
        for scale: CGFloat in [1, 2, 3] {
            System.updateScaleFactor(scale)
            for color: NSColor in [.systemBlue, .systemGreen, .systemRed] {
                theme.colors.accent = color
                theme.colors.background = color == .systemGreen ? .black : .white
                theme.colors.underSelectedColor = color == .systemRed ? .yellow : .white
                for amount in amounts {
                    item.drawStarsPaid = BadgeAmount(value: amount)
                    before.bind(item: item, value: nil, animated: false)
                    after.bind(item: item, value: nil, animated: false)
                    assertEqual(before, after)
                }
            }
        }
    }

    func testBadgeTransitionsClearCacheAndFollowNewPeer() {
        for previous in 0..<4 {
            for next in 0..<4 {
                let before = ReferencePaidBadgeView(), after = CurrentPaidBadgeView(), item = ShortPeerRowItem()
                for state in [previous, next] {
                    item.peerId += 1
                    item.drawStarsPaid = state >= 2 ? BadgeAmount(value: state == 2 ? 5 : 7000) : nil
                    let presentation = SelectPeerPresentation(premiumRequired: state == 1 ? [item.peerId] : [])
                    before.bind(item: item, value: presentation, animated: false)
                    after.bind(item: item, value: presentation, animated: false)
                    assertEqual(before, after)
                    XCTAssertEqual(after.paidMessageBadgeCache == nil, state < 2)
                }
            }
        }
    }

    func testRemovedBadgesReleaseCacheAndView() {
        let row = CurrentPaidBadgeView(), item = ShortPeerRowItem()
        weak var releasedCache: SendPaidMessageBadgeCache?
        weak var releasedView: ImageView?
        autoreleasepool {
            item.drawStarsPaid = BadgeAmount(value: 42)
            row.bind(item: item, value: nil, animated: false)
            releasedCache = row.paidMessageBadgeCache
            releasedView = row.photoBadge
            item.drawStarsPaid = nil
            row.bind(item: item, value: nil, animated: false)
        }
        XCTAssertNil(releasedCache)
        XCTAssertNil(releasedView)
        autoreleasepool {
            item.drawStarsPaid = BadgeAmount(value: 42)
            row.bind(item: item, value: nil, animated: false)
            releasedCache = row.paidMessageBadgeCache
            item.drawStarsPaid = nil
            row.bind(item: item, value: SelectPeerPresentation(premiumRequired: [item.peerId]), animated: false)
        }
        XCTAssertNil(releasedCache)
        XCTAssertNotNil(row.photoBadge)
    }

    func testCachedImageInvalidatesEveryRenderingInput() {
        let cache = SendPaidMessageBadgeCache()
        var text = "12.5K", bg: NSColor = .blue, outer: NSColor = .white, fg: NSColor = .yellow, font = NSFont.avatar(.small)
        func image() -> CGImage { cache.image(text: text, bgColor: bg, outerColor: outer, imageColor: fg, font: font) }
        let source = TelegramThemeHooks.shared.starSource
        defer { TelegramThemeHooks.shared.starSource = source }
        var previous = image()
        let changes: [() -> Void] = [
            { text = "12,5K" },
            { bg = .red },
            { outer = .black },
            { fg = .green },
            { font = .boldSystemFont(ofSize: 17) },
            { System.updateScaleFactor(3) },
            { TelegramThemeHooks.shared.starSource = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in NSColor.black.setFill(); rect.fill(); return true } }
        ]
        for change in changes {
            change()
            let current = image()
            XCTAssertFalse(current === previous)
            let reference = referenceGeneralSendPaidMessage(bgColor: bg, outerColor: outer, imageColor: fg, count: .initialize(string: text, color: fg, font: font))
            XCTAssertEqual(pixels(current), pixels(reference))
            XCTAssertTrue(current === image())
            previous = current
        }
    }

    func testCacheDropsPreviousImage() {
        let cache = SendPaidMessageBadgeCache()
        weak var previous: CGImage?
        autoreleasepool {
            previous = cache.image(text: "1", bgColor: .blue, outerColor: .white, imageColor: .white, font: .avatar(.small))
            XCTAssertNotNil(previous)
            _ = cache.image(text: "2", bgColor: .blue, outerColor: .white, imageColor: .white, font: .avatar(.small))
        }
        XCTAssertNil(previous)
    }

    func testDynamicColorsInvalidateForAppearanceChanges() {
        let cache = SendPaidMessageBadgeCache()
        let color = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
        }
        var previous: CGImage?
        for appearance in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                let current = cache.image(text: "50", bgColor: color, outerColor: .blue, imageColor: .red, font: .avatar(.small))
                let reference = referenceGeneralSendPaidMessage(bgColor: color, outerColor: .blue, imageColor: .red, count: .initialize(string: "50", color: .red, font: .avatar(.small)))
                XCTAssertEqual(pixels(current), pixels(reference))
                if let previous { XCTAssertFalse(previous === current) }
                previous = current
            }
        }
    }

    func testAnimatedInsertionAndRemovalMatchBaseline() {
        let before = ReferencePaidBadgeView(), after = CurrentPaidBadgeView(), item = ShortPeerRowItem()
        item.drawStarsPaid = BadgeAmount(value: 10)
        before.bind(item: item, value: nil, animated: true)
        after.bind(item: item, value: nil, animated: true)
        assertEqual(before, after)
        XCTAssertEqual(before.photoBadge?.layer?.animationKeys(), after.photoBadge?.layer?.animationKeys())
        let oldView = before.photoBadge!, newView = after.photoBadge!
        item.drawStarsPaid = nil
        before.bind(item: item, value: nil, animated: true)
        after.bind(item: item, value: nil, animated: true)
        XCTAssertNil(after.photoBadge)
        XCTAssertNil(after.paidMessageBadgeCache)
        XCTAssertEqual(oldView.layer?.animationKeys(), newView.layer?.animationKeys())
    }

    func testPaidBadgeBenchmark() throws {
        guard ProcessInfo.processInfo.environment["SHORT_PEER_PAID_BADGE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        var results: [[String: Any]] = []
        var checksum: CGFloat = 0
        let count = 2000
        for scenario in ["unchanged", "amount_changed", "new_row", "premium", "removed"] {
            let before = ReferencePaidBadgeView(), after = CurrentPaidBadgeView(), item = ShortPeerRowItem()
            var oldTrials: [Double] = [], newTrials: [Double] = []
            func measure(_ baseline: Bool) -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                for index in 0..<count {
                    autoreleasepool {
                        item.drawStarsPaid = scenario == "premium" || scenario == "removed" ? nil : BadgeAmount(value: scenario == "amount_changed" ? Int64(index % 100) : 1250)
                        let row: PaidBadgeEnvironment = scenario == "new_row" ? (baseline ? ReferencePaidBadgeView() : CurrentPaidBadgeView()) : (baseline ? before : after)
                        row.bind(item: item, value: SelectPeerPresentation(premiumRequired: scenario == "premium" ? [item.peerId] : []), animated: false)
                        checksum += row.photoBadge?.frame.width ?? 1
                    }
                }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(count) / 1000
            }
            _ = measure(true); _ = measure(false)
            for batch in 0..<9 {
                if batch % 2 == 0 { oldTrials.append(measure(true)); newTrials.append(measure(false)) }
                else { newTrials.append(measure(false)); oldTrials.append(measure(true)) }
            }
            results.append(["scenario": scenario, "baseline_us": oldTrials.sorted()[4], "candidate_us": newTrials.sorted()[4], "baseline_trials_us": oldTrials, "candidate_trials_us": newTrials])
        }
        XCTAssertGreaterThan(checksum, 0)
        let data = try JSONSerialization.data(withJSONObject: ["batches": 9, "iterations_per_batch": count, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/short-peer-paid-badge-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
