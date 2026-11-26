import Cocoa
import XCTest
import TGUIKit
@testable import PeerRows

final class SelectionLayoutTests: XCTestCase {
    override func setUp() { initializeLab() }

    private func cached(_ item: ShortPeerRowItem, _ name: String) -> Bool {
        let value = Mirror(reflecting: item).children.first { $0.label == name }!.value
        return !Mirror(reflecting: value).children.isEmpty
    }

    func testUnselectedRowsDoNotCreateSelectedText() {
        let item = ShortPeerRowItem()
        XCTAssertNil(item.titleSelected)
        XCTAssertNil(item.statusSelected)
        for _ in 0..<1000 { item.prepare(false) }
        XCTAssertNotNil(item.title)
        XCTAssertNotNil(item.status)
        XCTAssertFalse(cached(item, "selectedTitleLayout"))
        XCTAssertFalse(cached(item, "selectedStatusLayout"))
        _ = item.titleSelected
        XCTAssertTrue(cached(item, "selectedTitleLayout"))
        XCTAssertFalse(cached(item, "selectedStatusLayout"))
        let title = item.titleSelected!
        let status = item.statusSelected!
        for _ in 0..<1000 {
            XCTAssertTrue(title.0 === item.titleSelected?.0)
            XCTAssertTrue(title.1 === item.titleSelected?.1)
            XCTAssertTrue(status.0 === item.statusSelected?.0)
            XCTAssertTrue(status.1 === item.statusSelected?.1)
        }
    }

    func testSelectedPreparationWarmsBothLayoutsIncludingUnchangedWidth() {
        for warm in [false, true] {
            let item = ShortPeerRowItem()
            if warm { item.prepare(false) }
            item.prepare(true)
            XCTAssertTrue(cached(item, "selectedTitleLayout"))
            XCTAssertTrue(cached(item, "selectedStatusLayout"))
            let oldTitle = item.titleSelected!.0
            let oldStatus = item.statusSelected!.0
            item.prepare(false)
            XCTAssertTrue(item.titleSelected!.0 === oldTitle)
            XCTAssertTrue(item.statusSelected!.0 === oldStatus)
            item.size.width += 100
            item.prepare(true)
            XCTAssertTrue(cached(item, "selectedTitleLayout"))
            XCTAssertTrue(cached(item, "selectedStatusLayout"))
            XCTAssertFalse(item.titleSelected!.0 === oldTitle)
            XCTAssertFalse(item.statusSelected!.0 === oldStatus)
        }
    }

    func testResizeReleasesSelectedLayoutsAndUsesLatestWidth() {
        let item = ShortPeerRowItem()
        let reference = EagerRowItem()
        item.prepare(true)
        weak var title = item.titleSelected?.0
        weak var titleNode = item.titleSelected?.1
        weak var status = item.statusSelected?.0
        weak var statusNode = item.statusSelected?.1
        for width in [CGFloat(110), 200, 390, 97.5, 720] {
            item.size.width = width
            item.prepare(false)
            XCTAssertFalse(cached(item, "selectedTitleLayout"))
            XCTAssertFalse(cached(item, "selectedStatusLayout"))
        }
        XCTAssertNil(title)
        XCTAssertNil(titleNode)
        XCTAssertNil(status)
        XCTAssertNil(statusNode)
        reference.size.width = item.size.width
        reference.prepare(false)
        XCTAssertEqual(item.titleSelected?.0.size, reference.titleSelected?.0.size)
        XCTAssertEqual(item.statusSelected?.0.size, reference.statusSelected?.0.size)
    }

    func testIndependentMissingAndEmptyText() {
        for title in [String?.none, "", "Ada"] {
            for status in [String?.none, "", "online"] {
                let item = ShortPeerRowItem(title: title, status: status)
                let reference = EagerRowItem(title: title, status: status)
                for selected in [false, true, false] {
                    item.prepare(selected)
                    reference.prepare(selected)
                    XCTAssertEqual(item.titleSelected?.0.size, reference.titleSelected?.0.size)
                    XCTAssertEqual(item.statusSelected?.0.size, reference.statusSelected?.0.size)
                    XCTAssertEqual(item.titleSelected == nil, title == nil)
                    XCTAssertEqual(item.statusSelected == nil, status == nil)
                }
            }
        }
    }

    func testDelayedSelectionPixelsAfterUnvisitedResizes() {
        func pixels(_ pair: (TextNodeLayout, TextNode), scale: CGFloat) -> Data {
            let width = Int(400 * scale), height = Int(40 * scale)
            let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: 2, y: 2)
            pair.1.draw(CGRect(origin: .zero, size: pair.0.size), in: ctx, backingScaleFactor: scale, backgroundColor: .clear)
            return Data(bytes: ctx.data!, count: width * height * 4)
        }
        for text in ["Ada Lovelace", "أحمد محمد", "שלום עולם", "中文名字 👨‍👩‍👧‍👦", "café 🏳️‍🌈", String(repeating: "long name ", count: 20)] {
            for modern in [false, true] {
                for scale in [CGFloat(1), 2, 3] {
                    let item = ShortPeerRowItem(title: text, status: text)
                    let reference = EagerRowItem(title: text, status: text)
                    if modern {
                        item.viewType = .modern(0, NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8))
                        reference.viewType = item.viewType
                    }
                    for width in [CGFloat(150), 500, 120.5, 320] {
                        item.size.width = width
                        reference.size.width = width
                        item.prepare(false)
                        reference.prepare(false)
                    }
                    XCTAssertFalse(cached(item, "selectedTitleLayout"))
                    XCTAssertFalse(cached(item, "selectedStatusLayout"))
                    for (old, new) in zip([reference.titleSelected!, reference.statusSelected!], [item.titleSelected!, item.statusSelected!]) {
                        XCTAssertEqual(old.0.size, new.0.size)
                        let before = pixels(old, scale: scale), after = pixels(new, scale: scale)
                        XCTAssertTrue(before.contains { $0 != 0 })
                        XCTAssertEqual(before, after)
                    }
                }
            }
        }
    }

    func testSelectedTextReleasedWithItem() {
        weak var title: TextNodeLayout?
        weak var node: TextNode?
        autoreleasepool {
            let item = ShortPeerRowItem()
            item.prepare(true)
            title = item.titleSelected?.0
            node = item.statusSelected?.1
            XCTAssertNotNil(title)
            XCTAssertNotNil(node)
        }
        XCTAssertNil(title)
        XCTAssertNil(node)
    }

    func testRetainedTextObjectCounts() {
        let rows = (0..<1000).map { _ -> ShortPeerRowItem in
            let item = ShortPeerRowItem()
            item.prepare(false)
            return item
        }
        XCTAssertEqual(rows.filter { $0.title != nil && $0.status != nil }.count, 1000)
        XCTAssertEqual(rows.filter { cached($0, "selectedTitleLayout") || cached($0, "selectedStatusLayout") }.count, 0)
        for row in rows.prefix(20) { row.prepare(true) }
        XCTAssertEqual(rows.filter { cached($0, "selectedTitleLayout") && cached($0, "selectedStatusLayout") }.count, 20)
    }

    func testSelectionBenchmark() throws {
        guard ProcessInfo.processInfo.environment["SHORT_PEER_SELECTION_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        let count = 2000
        var checksum: CGFloat = 0
        var results: [[String: Any]] = []
        func run(_ name: String, candidate: Bool) -> Double {
            let old = EagerRowItem(), new = ShortPeerRowItem()
            old.prepare(false)
            new.prepare(false)
            let oldRows = name == "first_hover" && !candidate ? (0..<count).map { _ -> EagerRowItem in let row = EagerRowItem(); row.prepare(false); return row } : []
            let newRows = name == "first_hover" && candidate ? (0..<count).map { _ -> ShortPeerRowItem in let row = ShortPeerRowItem(); row.prepare(false); return row } : []
            let start = CACurrentMediaTime()
            for i in 0..<count {
                if candidate {
                    let row = name.hasPrefix("cold") ? ShortPeerRowItem() : name == "first_hover" ? newRows[i] : new
                    if name.hasPrefix("resize") { row.size.width = CGFloat(180 + i % 400) }
                    if name != "first_hover" { row.prepare(name.hasSuffix("selected") || name == "warm_selection") }
                    checksum += row.title!.0.size.width
                    if name == "first_hover" || name == "cold_all" || name == "warm_selection" {
                        checksum += row.titleSelected!.0.size.width + row.statusSelected!.0.size.width
                    }
                } else {
                    let row = name.hasPrefix("cold") ? EagerRowItem() : name == "first_hover" ? oldRows[i] : old
                    if name.hasPrefix("resize") { row.size.width = CGFloat(180 + i % 400) }
                    if name != "first_hover" { row.prepare(name.hasSuffix("selected") || name == "warm_selection") }
                    checksum += row.title!.0.size.width
                    if name == "first_hover" || name == "cold_all" || name == "warm_selection" {
                        checksum += row.titleSelected!.0.size.width + row.statusSelected!.0.size.width
                    }
                }
            }
            return (CACurrentMediaTime() - start) * 1_000_000 / Double(count)
        }
        for name in ["cold", "cold_selected", "cold_all", "resize", "resize_selected", "warm", "warm_selection", "first_hover"] {
            _ = run(name, candidate: false)
            _ = run(name, candidate: true)
            var before: [Double] = [], after: [Double] = []
            for iteration in 0..<9 {
                if iteration % 2 == 0 {
                    before.append(run(name, candidate: false)); after.append(run(name, candidate: true))
                } else {
                    after.append(run(name, candidate: true)); before.append(run(name, candidate: false))
                }
            }
            results.append(["scenario": name, "baseline_us": before.sorted()[4], "candidate_us": after.sorted()[4], "baseline_trials_us": before, "candidate_trials_us": after])
        }
        XCTAssertGreaterThan(checksum, 0)
        let data = try JSONSerialization.data(withJSONObject: ["batches": 9, "iterations_per_batch": count, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/short-peer-selection-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
