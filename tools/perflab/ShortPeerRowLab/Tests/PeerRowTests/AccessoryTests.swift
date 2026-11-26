import Cocoa
import XCTest
import TGUIKit
@testable import PeerRows

final class AccessoryTests: XCTestCase {
    override func setUp() {
        initializeLab()
        theme = AccessoryGlobalTheme()
    }

    private func pixels(_ text: TextView, scale: CGFloat) -> Data {
        let context = CGContext(data: nil, width: 1500, height: 180, bitsPerComponent: 8, bytesPerRow: 6000, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        text.draw(text.drawingLayer, in: context)
        return Data(bytes: context.data!, count: 6000 * 180)
    }

    private func pixels(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: image.width * image.height * 4)
    }

    private func assertEqual(_ old: AccessoryEnvironment, _ new: AccessoryEnvironment, scale: CGFloat = 2, render: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(old.containerView.subviews.count, new.containerView.subviews.count, file: file, line: line)
        XCTAssertEqual(old.contextLabel == nil, new.contextLabel == nil, file: file, line: line)
        XCTAssertEqual(old.choiceControl == nil, new.choiceControl == nil, file: file, line: line)
        XCTAssertEqual(old.switchView == nil, new.switchView == nil, file: file, line: line)
        XCTAssertEqual(old.switchView?.isOn, new.switchView?.isOn, file: file, line: line)
        XCTAssertEqual(old.switchView?.isEnabled, new.switchView?.isEnabled, file: file, line: line)
        if let old = old.contextLabel, let new = new.contextLabel {
            XCTAssertEqual(old.frame.size, new.frame.size, file: file, line: line)
            XCTAssertEqual(old.backgroundColor, new.backgroundColor, file: file, line: line)
            XCTAssertEqual(old.layer?.cornerRadius, new.layer?.cornerRadius, file: file, line: line)
            XCTAssertEqual(old.textLayout?.attributedString, new.textLayout?.attributedString, file: file, line: line)
            XCTAssertEqual(old.textLayout?.penFlush, new.textLayout?.penFlush, file: file, line: line)
            XCTAssertEqual(old.userInteractionEnabled, new.userInteractionEnabled, file: file, line: line)
            XCTAssertEqual(old.scaleOnClick, new.scaleOnClick, file: file, line: line)
            XCTAssertEqual(old.hasHandlers, new.hasHandlers, file: file, line: line)
            if render {
                XCTAssertEqual(pixels(old, scale: scale), pixels(new, scale: scale), file: file, line: line)
                XCTAssertTrue(pixels(new, scale: scale).contains { $0 != 0 }, file: file, line: line)
            }
        }
        if let old = old.choiceControl, let new = new.choiceControl {
            XCTAssertEqual(old.frame.size, new.frame.size, file: file, line: line)
            XCTAssertEqual(old.isAccessibilityDecorative, new.isAccessibilityDecorative, file: file, line: line)
            if render {
                XCTAssertEqual(pixels(old.image!), pixels(new.image!), file: file, line: line)
                XCTAssertTrue(pixels(new.image!).contains { $0 != 0 }, file: file, line: line)
            }
        }
    }

    func testUnchangedLabelsRetainLayoutsWithoutSuppressingNewCallbacks() {
        let row = CurrentAccessoryView(), item = AccessoryItem()
        item.type = .context("1,234 members")
        var clicks: [Int] = []
        item.badgeAction = { _ in clicks.append(1) }
        row.bind(item)
        let view = row.contextLabel!, layout = view.textLayout!
        view.send(event: .Click)
        for _ in 0..<1000 { row.bind(item) }
        XCTAssertTrue(row.contextLabel === view)
        XCTAssertTrue(row.contextLabel!.textLayout === layout)
        item.badgeAction = { _ in clicks.append(2) }
        row.bind(item)
        view.send(event: .Click)
        XCTAssertEqual(clicks, [1, 2])
        item.badgeAction = nil
        row.bind(item)
        view.send(event: .Click)
        XCTAssertEqual(clicks, [1, 2])
        XCTAssertFalse(view.userInteractionEnabled)
        XCTAssertFalse(view.hasHandlers)
    }

    func testContextInvalidationMatchesFreshBaseline() {
        let old = ReferenceAccessoryView(), new = CurrentAccessoryView(), item = AccessoryItem()
        item.type = .context("count")
        old.bind(item); new.bind(item)
        let mutations: [(AccessoryItem) -> Void] = [
            { $0.type = .context("123,456") },
            { $0.statusStyle.font = .boldSystemFont(ofSize: 18) },
            { $0.customTheme = AccessoryTheme(grayTextColor: .red, accentColor: .green) },
            { $0.type = .contextColored("123,456", .red) },
            { $0.type = .contextColored("123,456", .purple) },
            { $0.type = .nextContext("123,456") },
            { $0.customTheme = nil },
            { _ in theme.colors.grayText = .orange }
        ]
        for mutate in mutations {
            let previous = new.contextLabel!.textLayout!
            mutate(item)
            old.bind(item); new.bind(item)
            XCTAssertFalse(previous === new.contextLabel!.textLayout)
            assertEqual(old, new, render: true)
        }
    }

    func testContextPixelsAcrossLanguagesScalesAndStyles() {
        let old = ReferenceAccessoryView(), new = CurrentAccessoryView(), item = AccessoryItem()
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for text in ["123", "1,234 members", "أعضاء المجموعة", "שלום עולם", "中文标签", "👨‍👩‍👧‍👦 🦆", "café", "First\nSecond"] {
                for type in [AccessoryType.context(text), .nextContext(text), .contextColored(text, .purple)] {
                    item.type = type
                    for _ in 0..<2 {
                        old.bind(item); new.bind(item)
                        assertEqual(old, new, scale: scale, render: true)
                    }
                }
            }
        }
    }

    func testEveryAccessoryTransitionAndRemoval() {
        let types: [AccessoryType] = [.none, .selectable(false), .selectable(true), .switchable(false), .switchable(true), .context(""), .context("members"), .nextContext(""), .nextContext("next"), .contextColored("", .red), .contextColored("badge", .red)]
        for from in types {
            for to in types {
                let old = ReferenceAccessoryView(), new = CurrentAccessoryView(), item = AccessoryItem()
                item.type = from
                old.bind(item); new.bind(item)
                item.type = to
                item.enabled = false
                item.badgeAction = { _ in }
                old.bind(item); new.bind(item)
                assertEqual(old, new, render: true)
                item.type = .none
                old.bind(item); new.bind(item)
                assertEqual(old, new)
                XCTAssertTrue(new.containerView.subviews.isEmpty)
            }
        }
    }

    func testChoiceRetainsViewAndImageAndInvalidatesStyle() {
        let old = ReferenceAccessoryView(), new = CurrentAccessoryView(), item = AccessoryItem()
        item.type = .selectable(true)
        old.bind(item); new.bind(item)
        let view = new.choiceControl!, image = view.image!
        for _ in 0..<1000 { new.bind(item) }
        XCTAssertTrue(new.choiceControl === view)
        XCTAssertTrue(new.choiceControl!.image === image)
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for color in [NSColor.red, .green, .white] {
                let previous = new.choiceControl!.image!
                item.customTheme = AccessoryTheme(accentColor: color)
                old.bind(item); new.bind(item)
                XCTAssertTrue(new.choiceControl === view)
                XCTAssertFalse(new.choiceControl!.image === previous)
                assertEqual(old, new, scale: scale, render: true)
            }
        }
        let originalSource = TelegramThemeHooks.shared.source
        defer { TelegramThemeHooks.shared.source = originalSource }
        let previous = new.choiceControl!.image!
        TelegramThemeHooks.shared.source = NSImage(size: NSSize(width: 24, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()
            return true
        }
        old.bind(item); new.bind(item)
        XCTAssertFalse(new.choiceControl!.image === previous)
        assertEqual(old, new, render: true)
        item.type = .selectable(false)
        new.bind(item)
        XCTAssertNil(new.choiceControl)
        XCTAssertNil(view.superview)
    }

    func testRemovedAccessoriesReleaseViewsAndLayouts() {
        let row = CurrentAccessoryView(), item = AccessoryItem()
        weak var label: TextView?
        weak var layout: TextViewLayout?
        weak var choice: ImageView?
        autoreleasepool {
            item.type = .context("members")
            row.bind(item)
            label = row.contextLabel
            layout = label?.textLayout
            item.type = .selectable(true)
            row.bind(item)
            choice = row.choiceControl
            item.type = .none
            row.bind(item)
        }
        XCTAssertNil(label)
        XCTAssertNil(layout)
        XCTAssertNil(choice)
    }

    func testRightActionsUseDeclaredIndicesAndFollowPeerReuse() {
        let old = ReferenceAccessoryView(), new = CurrentAccessoryView()
        let icon = TelegramThemeHooks.shared.source.precomposed(.blue)
        var received: [(Int, Int)] = []
        let first = AccessoryItem(), second = AccessoryItem()
        first.peerId = 12
        first.rightActions.actions = [.init(icon: icon, index: 7, accessibilityLabel: "Audio"), .init(icon: icon, index: 3, accessibilityLabel: "Video")]
        first.rightActions.callback = { received.append(($0, $1)) }
        old.bind(first)
        old.rightsActions.forEach { $0.send(event: .Click) }
        XCTAssertEqual(received.map { $0.1 }, [0, 1])
        received.removeAll()
        new.bind(first)
        let button = new.rightsActions[0]
        new.rightsActions.forEach { $0.send(event: .Click) }
        XCTAssertEqual(received.map { $0.0 }, [12, 12])
        XCTAssertEqual(received.map { $0.1 }, [7, 3])
        XCTAssertEqual(button.accessibilityLabel(), "Audio")
        second.peerId = 99
        second.rightActions.actions = [.init(icon: icon, index: -4, accessibilityLabel: "Other")]
        second.rightActions.callback = { received.append(($0, $1)) }
        new.bind(second)
        XCTAssertTrue(new.rightsActions[0] === button)
        XCTAssertEqual(new.rightsActions.count, 1)
        XCTAssertEqual(button.accessibilityLabel(), "Other")
        button.send(event: .Click)
        XCTAssertEqual(received.last!.0, 99)
        XCTAssertEqual(received.last!.1, -4)
        weak var released: AccessoryItem?
        autoreleasepool {
            let transient = AccessoryItem()
            transient.rightActions = second.rightActions
            new.bind(transient)
            released = transient
        }
        XCTAssertNil(released)
        button.send(event: .Click)
        XCTAssertEqual(received.count, 3)
    }

    func testAccessoryBenchmark() throws {
        guard ProcessInfo.processInfo.environment["SHORT_PEER_ACCESSORY_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        var results: [[String: Any]] = []
        var checksum: CGFloat = 0
        for scenario in ["context_repeat", "context_changed", "context_cold", "colored_repeat", "choice_repeat", "choice_toggle", "choice_cold"] {
            let old = ReferenceAccessoryView(), new = CurrentAccessoryView(), item = AccessoryItem()
            let count = 2000
            var before: [Double] = [], after: [Double] = []
            func measure(_ baseline: Bool) -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                for i in 0..<count {
                    autoreleasepool {
                        if scenario.hasPrefix("choice") { item.type = .selectable(scenario != "choice_toggle" || i % 2 == 0) }
                        else if scenario == "colored_repeat" { item.type = .contextColored("1,234 members", .purple) }
                        else { item.type = .context(scenario == "context_changed" ? "\(i % 100) members" : "1,234 members") }
                        let row: AccessoryEnvironment = scenario.hasSuffix("cold") ? (baseline ? ReferenceAccessoryView() : CurrentAccessoryView()) : (baseline ? old : new)
                        row.bind(item)
                        checksum += row.contextLabel?.frame.width ?? row.choiceControl?.frame.width ?? 1
                    }
                }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(count) / 1000
            }
            _ = measure(true); _ = measure(false)
            for batch in 0..<9 {
                if batch % 2 == 0 { before.append(measure(true)); after.append(measure(false)) }
                else { after.append(measure(false)); before.append(measure(true)) }
            }
            results.append(["scenario": scenario, "baseline_us": before.sorted()[4], "candidate_us": after.sorted()[4], "baseline_trials_us": before, "candidate_trials_us": after])
        }
        XCTAssertGreaterThan(checksum, 0)
        let data = try JSONSerialization.data(withJSONObject: ["batches": 9, "iterations_per_batch": 2000, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/short-peer-accessory-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
