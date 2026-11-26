import Cocoa
import XCTest
import QuartzCore
import ObjectiveC
import TGUIKit
@testable import ChatLayerEngine
@testable import ChatLayerEngineBaseline
@testable import FoldingViewHarness
@testable import FoldingViewHarnessBaseline

final class FormattedDateBenchmarkTests: XCTestCase {
    private let currentContext = FoldingViewHarness.BlockContext()
    private let baselineContext = FoldingViewHarnessBaseline.BlockContext()
    private typealias Items = (current: FoldingViewHarness.ChatMessageItem, baseline: FoldingViewHarnessBaseline.ChatMessageItem)

    private func text(_ id: Int, count: Int, dates: Bool) -> (full: NSMutableAttributedString, blocks: [TextViewLayout], ranges: [NSRange]) {
        let full = NSMutableAttributedString()
        var blocks: [TextViewLayout] = [], ranges: [NSRange] = []
        for index in 0..<count {
            let value = NSMutableAttributedString(string: "Tomorrow, message \(id), block \(index)\nAfter lunch مرحبا 👩🏽‍💻", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
            if dates {
                value.addAttribute(TextInputAttributes.formattedDate, value: TextViewFormattedDateData(text: "Tomorrow", date: Int32(1_800_000_000 + id * 60 + index), isRelative: true), range: NSRange(location: 0, length: 8))
            }
            ranges.append(NSRange(location: full.length, length: value.length))
            full.append(value)
            let block = TextViewLayout(value, disableTooltips: true)
            block.interactions.resolveLink = { $0 as? String }
            blocks.append(block)
        }
        return (full, blocks, ranges)
    }

    private func items(_ id: Int, count: Int, dates: Bool) -> Items {
        let currentText = text(id, count: count, dates: dates)
        let baselineText = text(id, count: count, dates: dates)
        let current = FoldingViewHarness.FoldingTextLayout(attributedString: currentText.full, blocks: currentText.blocks, blockRanges: currentText.ranges, context: currentContext, revealed: [])
        let baseline = FoldingViewHarnessBaseline.FoldingTextLayout(attributedString: baselineText.full, blocks: baselineText.blocks, blockRanges: baselineText.ranges, context: baselineContext, revealed: [])
        current.measure(width: 240)
        baseline.measure(width: 240)
        XCTAssertEqual(current.size, baseline.size)
        XCTAssertEqual(current.attributedString.string, baseline.attributedString.string)
        XCTAssertFalse(current.attributedString === baseline.attributedString)
        XCTAssertEqual(current.blockRanges, baseline.blockRanges)
        for (a, b) in zip(current.blocks, baseline.blocks) {
            XCTAssertFalse(a.text === b.text)
            XCTAssertFalse(a.text.attributedString === b.text.attributedString)
            XCTAssertEqual(a.text.layoutSize, b.text.layoutSize)
            if dates {
                let first = a.text.attributedString.attribute(TextInputAttributes.formattedDate, at: 0, effectiveRange: nil) as? TextViewFormattedDateData
                let second = b.text.attributedString.attribute(TextInputAttributes.formattedDate, at: 0, effectiveRange: nil) as? TextViewFormattedDateData
                XCTAssertNotNil(first)
                XCTAssertNotNil(second)
                XCTAssertFalse(first === second)
                XCTAssertEqual(first?.text, second?.text)
                XCTAssertEqual(first?.date, second?.date)
                XCTAssertEqual(first?.isRelative, second?.isRelative)
            }
        }
        return (FoldingViewHarness.ChatMessageItem(id: id, layout: current), FoldingViewHarnessBaseline.ChatMessageItem(id: id, layout: baseline))
    }

    func testCompleteFormattedDateBindingCosts() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CHAT_FORMATTED_DATE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in formatted date binding benchmark") }
        TGUIKitTestBootstrap.install()
        let reversed = environment["CHAT_FORMATTED_DATE_REVERSE"] == "1"
        var batches: [String: [[Double]]] = [:]
        var counts: [String: [Int]] = [:]
        var iterations: [String: Int] = [:]
        var sink = 0
        func measure(_ name: String, count: Int, operations: [() -> Void]) {
            for index in reversed ? [1, 0] : [0, 1] {
                autoreleasepool { for _ in 0..<20 { operations[index]() } }
            }
            var samples = [[Double](), [Double]()]
            for batch in 0..<9 {
                for index in (batch % 2 == 0) != reversed ? [0, 1] : [1, 0] {
                    let elapsed = autoreleasepool { () -> Double in
                        let start = CACurrentMediaTime()
                        for _ in 0..<count { operations[index]() }
                        return (CACurrentMediaTime() - start) * 1_000_000 / Double(count)
                    }
                    samples[index].append(elapsed)
                }
            }
            batches[name] = samples
            iterations[name] = count
        }
        for dates in [false, true] {
            let kind = dates ? "formatted_date" : "plain_control"
            for count in [1, 3, 12] {
                let first = items(1, count: count, dates: dates)
                let next = items(2, count: count, dates: dates)
                let baseline = FoldingViewHarnessBaseline.LayerChatTextRow(frame: .zero)
                let current = FoldingViewHarness.LayerChatTextRow(frame: .zero)
                baseline.bind(first.baseline)
                current.bind(first.current)
                XCTAssertNotNil(current.layerText)
                if dates {
                    XCTAssertNotNil(baseline.text)
                    XCTAssertNil(baseline.layerText)
                } else {
                    XCTAssertNotNil(baseline.layerText)
                    XCTAssertNil(baseline.text)
                }
                let bodyKey = "body_\(kind)_\(count)"
                counts[bodyKey] = [viewTreeCount(baseline), viewTreeCount(current)]
                measure("construct_\(bodyKey)", count: 150, operations: [
                    { let row = FoldingViewHarnessBaseline.LayerChatTextRow(frame: .zero); row.bind(first.baseline); sink &+= row.subviews.count },
                    { let row = FoldingViewHarness.LayerChatTextRow(frame: .zero); row.bind(first.current); sink &+= row.subviews.count }
                ])
                measure("same_\(bodyKey)", count: 400, operations: [
                    { baseline.bind(first.baseline); sink &+= baseline.subviews.count },
                    { current.bind(first.current); sink &+= current.subviews.count }
                ])
                var baselineIndex = 0, currentIndex = 0
                measure("recycle_\(bodyKey)", count: 400, operations: [
                    { baselineIndex &+= 1; baseline.bind(baselineIndex % 2 == 0 ? first.baseline : next.baseline); sink &+= baseline.subviews.count },
                    { currentIndex &+= 1; current.bind(currentIndex % 2 == 0 ? first.current : next.current); sink &+= current.subviews.count }
                ])
                let captionFirst = items(1, count: count, dates: dates)
                let captionNext = items(2, count: count, dates: dates)
                let baselineCaption = FoldingViewHarnessBaseline.LayerCaptionRow(frame: .zero)
                let currentCaption = FoldingViewHarness.LayerCaptionRow(frame: .zero)
                let baselineFirst = FoldingViewHarnessBaseline.ChatRowItem([.init(messageId: 1, id: 1, layout: captionFirst.baseline.textLayout)])
                let currentFirst = FoldingViewHarness.ChatRowItem([.init(messageId: 1, id: 1, layout: captionFirst.current.textLayout)])
                let baselineNext = FoldingViewHarnessBaseline.ChatRowItem([.init(messageId: 2, id: 2, layout: captionNext.baseline.textLayout)])
                let currentNext = FoldingViewHarness.ChatRowItem([.init(messageId: 2, id: 2, layout: captionNext.current.textLayout)])
                baselineCaption.bind(baselineFirst)
                currentCaption.bind(currentFirst)
                XCTAssertNotNil(currentCaption.captionViews.first?.layerView)
                if dates {
                    XCTAssertNotNil(baselineCaption.captionViews.first?.nativeView)
                    XCTAssertNil(baselineCaption.captionViews.first?.layerView)
                } else {
                    XCTAssertNotNil(baselineCaption.captionViews.first?.layerView)
                    XCTAssertNil(baselineCaption.captionViews.first?.nativeView)
                }
                let captionKey = "caption_\(kind)_\(count)"
                counts[captionKey] = [viewTreeCount(baselineCaption), viewTreeCount(currentCaption)]
                measure("construct_\(captionKey)", count: 150, operations: [
                    { let row = FoldingViewHarnessBaseline.LayerCaptionRow(frame: .zero); row.bind(baselineFirst); sink &+= row.subviews.count },
                    { let row = FoldingViewHarness.LayerCaptionRow(frame: .zero); row.bind(currentFirst); sink &+= row.subviews.count }
                ])
                measure("same_\(captionKey)", count: 400, operations: [
                    { baselineCaption.bind(baselineFirst); sink &+= baselineCaption.subviews.count },
                    { currentCaption.bind(currentFirst); sink &+= currentCaption.subviews.count }
                ])
                var baselineCaptionIndex = 0, currentCaptionIndex = 0
                measure("recycle_\(captionKey)", count: 400, operations: [
                    { baselineCaptionIndex &+= 1; baselineCaption.bind(baselineCaptionIndex % 2 == 0 ? baselineFirst : baselineNext); sink &+= baselineCaption.subviews.count },
                    { currentCaptionIndex &+= 1; currentCaption.bind(currentCaptionIndex % 2 == 0 ? currentFirst : currentNext); sink &+= currentCaption.subviews.count }
                ])
            }
        }
        XCTAssertGreaterThan(sink, 0)
        let payload: [String: Any] = [
            "batches": batches,
            "view_counts": counts,
            "iterations_per_batch": iterations,
            "variant_order": ["archived_pre_live_folding_baseline", "current"],
            "units": "microseconds_per_operation",
            "batch_count": 9,
            "warmup_iterations": 20,
            "reversed": reversed,
            "independently_owned_layouts_and_date_payloads": true,
            "premeasured": true,
            "attached": false,
            "rasterized": false,
            "scope": "Complete fixture binding and construction; excludes layout measurement, rasterization, media and full-app scrolling",
            "text_node_runtime_bytes": [class_getInstanceSize(ChatLayerEngineBaseline.ChatLayerTextNode.self), class_getInstanceSize(ChatLayerEngine.ChatLayerTextNode.self)],
            "message_node_runtime_bytes": [class_getInstanceSize(ChatLayerEngineBaseline.ChatLayerMessageTextNode.self), class_getInstanceSize(ChatLayerEngine.ChatLayerMessageTextNode.self)]
        ]
        let output = environment["CHAT_FORMATTED_DATE_OUTPUT"] ?? "/tmp/chat-formatted-date-binding-benchmark.json"
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
    }
}
