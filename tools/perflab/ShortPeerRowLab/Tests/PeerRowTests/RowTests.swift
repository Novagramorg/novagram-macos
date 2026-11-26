import Cocoa
import XCTest
import TGUIKit
@testable import PeerRows

final class RowTests: XCTestCase {
    override func setUp() {
        initializeLab()
    }
    private func pixels(_ pair: (TextNodeLayout, TextNode), scale: CGFloat) -> Data {
        let context = CGContext(data: nil, width: 1000, height: 120, bitsPerComponent: 8, bytesPerRow: 4000, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 5, y: 5)
        pair.1.draw(CGRect(origin: .zero, size: pair.0.size), in: context, backingScaleFactor: scale, backgroundColor: .clear)
        return Data(bytes: context.data!, count: 480000)
    }
    private func assertEqual(_ old: ItemEnvironment, _ new: ItemEnvironment, render: Bool = false, scale: CGFloat = 2, file: StaticString = #filePath, line: UInt = #line) {
        for (a, b) in zip(old.layouts, new.layouts) {
            XCTAssertEqual(a == nil, b == nil, file: file, line: line)
            if let a, let b {
                XCTAssertEqual(a.0.size, b.0.size, file: file, line: line)
                XCTAssertEqual(a.0.numberOfLines, b.0.numberOfLines, file: file, line: line)
                XCTAssertEqual(a.0.firstLineWidth, b.0.firstLineWidth, file: file, line: line)
                if render { XCTAssertEqual(pixels(a, scale: scale), pixels(b, scale: scale), file: file, line: line) }
            }
        }
    }
    func testRenderingAcrossSelectionLanguagesScalesAndTruncation() {
        for scale in [CGFloat(1), 2, 3] {
            for text in ["Ada Lovelace", "أحمد محمد", "שלום עולם", "中文名字 👨‍👩‍👧‍👦", "café 🏳️‍🌈", "", String(repeating: "Long name ", count: 10)] {
                let old = ReferenceRowItem(title: text, status: "online")
                let new = ShortPeerRowItem(title: text, status: "online")
                for width in [CGFloat(100), 240, 550] {
                    old.size.width = width; new.size.width = width
                    for selected in [false, true, false] {
                        old.prepare(selected); new.prepare(selected)
                        assertEqual(old, new, render: true, scale: scale)
                    }
                }
                if !text.isEmpty {
                    XCTAssertNotEqual(pixels(new.title!, scale: scale), pixels(new.titleSelected!, scale: scale))
                    XCTAssertTrue(pixels(new.title!, scale: scale).contains { $0 != 0 })
                }
            }
        }
    }
    func testRepeatedPreparationRetainsAllFourLayouts() {
        let item = ShortPeerRowItem()
        item.prepare(false)
        let initial = item.layouts
        for i in 0..<1000 {
            item.prepare(i % 2 == 0)
            for (old, new) in zip(initial, item.layouts) {
                XCTAssertTrue(old!.0 === new!.0)
                XCTAssertTrue(old!.1 === new!.1)
            }
        }
        item.size.width += 1
        item.prepare(false)
        for (old, new) in zip(initial, item.layouts) { XCTAssertFalse(old!.0 === new!.0) }
    }
    func testGeometryInvalidationMatchesBaseline() {
        let old = ReferenceRowItem()
        let new = ShortPeerRowItem()
        let icon = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let badgeText = TextViewLayout(NSAttributedString(string: "42", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        badgeText.measure(width: 100)
        for i in 0..<1500 {
            for item in [old as ItemEnvironment, new] {
                item.size.width = CGFloat(90 + (i * 37) % 570) + CGFloat(i % 4) * 0.25
                item.titleInset = CGFloat(36 + i % 28)
                item.statusInset = item.titleInset + CGFloat(i % 2 * 20)
                item.inset = NSEdgeInsets(top: 0, left: CGFloat(i % 20), bottom: 0, right: CGFloat(i % 30))
                item.textAdditionInset = CGFloat(i % 9)
                item.viewType = i % 2 == 0 ? .legacy : .modern(0, NSEdgeInsets(top: 0, left: CGFloat(i % 12), bottom: 0, right: CGFloat(i % 17)))
                switch i % 6 {
                case 0: item.type = .none
                case 1: item.type = .switchable
                case 2: item.type = .selectable
                case 3: item.type = .context("\(i % 100) members")
                case 4: item.type = .contextColored("Badge \(i % 40)", .red)
                default: item.type = .nextContext("A longer context")
                }
                switch i % 3 {
                case 0: item.interactionType = .plain
                case 1: item.interactionType = .selectable(SelectPeerInteraction(), 0)
                default: item.interactionType = .deletable
                }
                item.statusImage = i % 3 == 0 ? icon : nil
                item.rightActions.actions = Array(repeating: Action(icon: icon), count: i % 3)
                item.peer = Peer(isScam: i % 11 == 0, isFake: i % 13 == 0, isPremium: i % 7 == 0, isVerified: i % 5 == 0)
                item.highlightVerified = i % 4 == 0
                item.badgeNode = i % 8 == 0 ? true : nil
                item.monoforumMessagesSelected = i % 9 == 0 ? badgeText : nil
                item.customActionText = i % 10 == 0 ? badgeText : nil
            }
            old.prepare(false); new.prepare(false)
            assertEqual(old, new, render: i % 75 == 0)
            old.prepare(true); new.prepare(true)
            assertEqual(old, new)
        }
    }
    func testContextChangesAndNewItemAppearanceDoNotUseStaleText() {
        for color in [NSColor.black, .red, .white] {
            for text in [String?.none, "", "First", "Second 👻"] {
                let old = ReferenceRowItem(title: text, status: text, color: color)
                let new = ShortPeerRowItem(title: text, status: text, color: color)
                for type in [RowType.context("1"), .context("12345"), .none, .nextContext("1"), .contextColored("abc", .blue)] {
                    old.type = type; new.type = type
                    old.prepare(false); new.prepare(false)
                    assertEqual(old, new, render: true)
                }
            }
        }
    }
    func testSameWidthAccessoriesInvalidateLayouts() {
        for modern in [false, true] {
            let old = ReferenceRowItem(), new = ShortPeerRowItem()
            if modern {
                old.viewType = .modern(0, NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10))
                new.viewType = old.viewType
            }
            let mutations: [(ItemEnvironment) -> Void] = [
                { $0.titleInset += 5 },
                { $0.statusInset += 8 },
                { $0.inset.right += 2 },
                { $0.textAdditionInset += 3 },
                { $0.type = .context("A long badge") },
                { $0.type = .context("1") },
                { $0.type = .none },
                { $0.peer.isScam = true },
                { $0.peer.isFake = true },
                { $0.highlightVerified = true },
                { $0.badgeNode = true },
                { $0.interactionType = .selectable(SelectPeerInteraction(), 0) },
                { $0.interactionType = .plain },
                { $0.viewType = .modern(0, NSEdgeInsets(top: 0, left: 3, bottom: 0, right: 5)) }
            ]
            old.prepare(false); new.prepare(false)
            for mutate in mutations {
                mutate(old); mutate(new)
                old.prepare(false); new.prepare(false)
                assertEqual(old, new, render: true)
            }
        }
    }
    func testBaselineReproducesStaleObserverBug() {
        let a = SelectPeerInteraction(), b = SelectPeerInteraction(), parent = NSView()
        let first = ShortPeerRowItem(), second = ShortPeerRowItem()
        first.interactionType = .selectable(a, 0)
        second.interactionType = .interactable(b)
        let old = ReferenceObserverView(), new = RowObserverView()
        old.set(first); new.item = first
        parent.addSubview(old); parent.addSubview(new)
        old.set(second); new.item = second
        a.emit(1); b.emit(2)
        XCTAssertEqual(old.received, [1, 2])
        XCTAssertEqual(new.received, [2])
        old.removeFromSuperview(); new.removeFromSuperview()
        a.emit(3); b.emit(4)
        XCTAssertEqual(old.received, [1, 2, 3])
        XCTAssertEqual(new.received, [2])
    }
    func testObserverFollowsReuseAttachmentAndInteractionKind() {
        let a = SelectPeerInteraction(), b = SelectPeerInteraction()
        let parent = NSView()
        let row = RowObserverView()
        let first = ShortPeerRowItem(), second = ShortPeerRowItem(), plain = ShortPeerRowItem()
        first.interactionType = .selectable(a, 0)
        second.interactionType = .interactable(b)
        row.item = first
        a.emit(1)
        XCTAssertEqual(row.received, [])
        parent.addSubview(row)
        a.emit(2)
        XCTAssertEqual(row.received, [2])
        for _ in 0..<100 { row.item = first }
        a.emit(3)
        XCTAssertEqual(row.received, [2, 3])
        row.item = second
        a.emit(4); b.emit(5)
        XCTAssertEqual(row.received, [2, 3, 5])
        row.item = plain
        a.emit(6); b.emit(7)
        XCTAssertEqual(row.received, [2, 3, 5])
        row.item = second
        b.emit(8)
        row.removeFromSuperview()
        b.emit(9)
        XCTAssertEqual(row.received, [2, 3, 5, 8])
        row.item = first
        parent.addSubview(row)
        a.emit(10); b.emit(11)
        XCTAssertEqual(row.received, [2, 3, 5, 8, 10])
        row.removeFromSuperview()
    }
    func testObserverReuseTransitionsExhaustively() {
        let a = SelectPeerInteraction(), b = SelectPeerInteraction()
        let types: [ShortPeerItemInteractionType] = [.plain, .selectable(a, 0), .interactable(a), .selectable(b, 1), .interactable(b), .deletable]
        for from in types {
            for to in types {
                let parent = NSView(), row = RowObserverView()
                let first = ShortPeerRowItem(), second = ShortPeerRowItem()
                first.interactionType = from; second.interactionType = to
                row.item = first; parent.addSubview(row); row.item = second
                a.emit(1); b.emit(2)
                switch to {
                case let .selectable(value, _), let .interactable(value): XCTAssertEqual(row.received, [value === a ? 1 : 2])
                default: XCTAssertEqual(row.received, [])
                }
                row.received.removeAll(); row.removeFromSuperview(); a.emit(1); b.emit(2)
                XCTAssertEqual(row.received, [])
            }
        }
        weak var released: RowObserverView?
        autoreleasepool {
            let row = RowObserverView(), parent = NSView(), item = ShortPeerRowItem()
            item.interactionType = .selectable(a, 0)
            row.item = item; parent.addSubview(row); released = row
        }
        XCTAssertNil(released)
        a.emit(42)
    }
    func testBenchmark() throws {
        guard ProcessInfo.processInfo.environment["SHORT_PEER_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        let old = ReferenceRowItem(), new = ShortPeerRowItem()
        var checksum: CGFloat = 0
        var results: [[String: Any]] = []
        func measure(count: Int, _ body: (Int) -> Void) -> Double {
            let start = CFAbsoluteTimeGetCurrent()
            for i in 0..<count { body(i) }
            return (CFAbsoluteTimeGetCurrent() - start) * 1_000_000 / Double(count)
        }
        for scenario in ["warm", "selection", "context", "resize", "cold"] {
            old.type = scenario == "context" ? .context("1,234 members") : .none
            new.type = old.type
            old.prepare(false); new.prepare(false)
            let count = 2000
            var before: [Double] = [], after: [Double] = []
            func baseline(_ i: Int) {
                let item = scenario == "cold" ? ReferenceRowItem() : old
                if scenario == "resize" { item.size.width = CGFloat(200 + i % 100) }
                item.prepare(scenario == "selection" && i % 2 == 0)
                checksum += item.title!.0.size.width
            }
            func candidate(_ i: Int) {
                let item = scenario == "cold" ? ShortPeerRowItem() : new
                if scenario == "resize" { item.size.width = CGFloat(200 + i % 100) }
                item.prepare(scenario == "selection" && i % 2 == 0)
                checksum += item.title!.0.size.width
            }
            for i in 0..<9 {
                if i % 2 == 0 { before.append(measure(count: count, baseline)); after.append(measure(count: count, candidate)) }
                else { after.append(measure(count: count, candidate)); before.append(measure(count: count, baseline)) }
            }
            results.append(["scenario": scenario, "baseline_us": before.sorted()[4], "candidate_us": after.sorted()[4], "speedup": before.sorted()[4] / after.sorted()[4]])
        }
        let interaction = SelectPeerInteraction()
        let item = ShortPeerRowItem()
        item.interactionType = .selectable(interaction, 0)
        let newInteraction = SelectPeerInteraction(), newItem = ShortPeerRowItem()
        newItem.interactionType = .selectable(newInteraction, 0)
        let oldParent = NSView(), newParent = NSView()
        let oldRows = (0..<100).map { _ in ReferenceObserverView() }
        let newRows = (0..<100).map { _ in RowObserverView() }
        for row in oldRows { row.set(item); oldParent.addSubview(row) }
        for row in newRows { row.item = newItem; newParent.addSubview(row) }
        var before: [Double] = [], after: [Double] = []
        for i in 0..<9 {
            let oldBody: (Int) -> Void = { oldRows[$0 % 100].set(item) }
            let newBody: (Int) -> Void = { newRows[$0 % 100].item = newItem }
            if i % 2 == 0 { before.append(measure(count: 2000, oldBody)); after.append(measure(count: 2000, newBody)) }
            else { after.append(measure(count: 2000, newBody)); before.append(measure(count: 2000, oldBody)) }
        }
        results.append(["scenario": "observer_rebind_100_rows", "baseline_us": before.sorted()[4], "candidate_us": after.sorted()[4], "speedup": before.sorted()[4] / after.sorted()[4]])
        oldRows.forEach { $0.removeFromSuperview() }; newRows.forEach { $0.removeFromSuperview() }
        XCTAssertGreaterThan(checksum, 0)
        let data = try JSONSerialization.data(withJSONObject: ["batches": 9, "iterations_per_batch": 2000, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/short-peer-row-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
