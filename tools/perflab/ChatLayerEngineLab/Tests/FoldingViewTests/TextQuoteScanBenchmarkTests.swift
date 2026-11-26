import Cocoa
import XCTest
import QuartzCore
import TGUIKit
@testable import FoldingViewHarness
@testable import ChatLayerEngine

final class TextQuoteScanBenchmarkTests: XCTestCase {
    func testLookupAndBindingCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_QUOTE_SCAN_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in quote lookup and binding benchmark") }
        TGUIKitTestBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["CHAT_QUOTE_SCAN_REVERSE"] == "1"
        let context = BlockContext(), factory = ChatTextReuseTests()
        var results: [String: [[Double]]] = [:]
        var sink = 0
        func record(_ name: String, count: Int, operations: [() -> Int]) {
            for operation in operations { for _ in 0..<40 { sink += operation() } }
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                for mode in (batch % 2 == 0) != reverse ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    for _ in 0..<count { autoreleasepool { sink += operations[mode]() } }
                    batches[mode].append((CACurrentMediaTime() - start) * 1e9 / Double(count))
                }
            }
            results[name] = batches
        }
        for runs in [1, 16, 128] {
            for variant in 0..<5 {
                let text = NSMutableAttributedString(string: String(repeating: "word ", count: runs), attributes: [.font: NSFont.systemFont(ofSize: 14)])
                for index in 0..<runs { text.addAttribute(.foregroundColor, value: index % 2 == 0 ? NSColor.black : .blue, range: NSRange(location: index * 5, length: 5)) }
                let quote = TextViewBlockQuoteData(id: 1, colors: .init(main: .blue), collapsable: true)
                if variant == 1 { text.addAttribute(TextInputAttributes.quote, value: quote, range: NSRange(location: 0, length: 1)) }
                if variant == 2 { text.addAttribute(TextInputAttributes.quote, value: quote, range: NSRange(location: text.length - 1, length: 1)) }
                if variant == 3 { text.addAttribute(TextInputAttributes.quote, value: quote, range: text.range) }
                if variant == 4 { for index in 0..<runs { text.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: index, colors: .init(main: .blue)), range: NSRange(location: index * 5, length: 1)) } }
                let layout = TextViewLayout(text)
                layout.measure(width: 400)
                record("has_quote_runs_\(runs)_variant_\(variant)", count: 4000, operations: [
                    { layout.attributedString.containsAttribute(attributeName: TextInputAttributes.quote) is TextViewBlockQuoteData ? 1 : 0 },
                    { layout.hasBlockQuotes ? 1 : 0 }
                ])
                record("last_line_runs_\(runs)_variant_\(variant)", count: 4000, operations: [
                    { guard let range = layout.lines.last?.range else { return 0 }; return layout.attributedString.attributedSubstring(from: range).containsAttribute(attributeName: TextInputAttributes.quote) is TextViewBlockQuoteData ? 1 : 0 },
                    { layout.lastLineIsQuote ? 1 : 0 }
                ])
            }
        }
        let windows = (0..<2).map { _ -> Window in
            let window = Window(contentRect: NSRect(x: 0, y: 0, width: 260, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            return window
        }
        defer { windows.forEach { $0.contentView = nil; $0.close() } }
        for blocks in [1, 3, 12] {
            for quoted in [false, true] {
                let items = (0..<2).map { _ in (0..<2).map { factory.item($0, count: blocks, quoted: quoted, context: context) } }
                record("prepare_blocks_\(blocks)_quoted_\(quoted)", count: 4000, operations: [
                    { ChatLayerMessageTextPresentation.referenceSimpleText(items[0][0].textLayout)?.blocks.count ?? 0 },
                    { ChatLayerMessageTextPresentation.simpleText(items[1][0].textLayout)?.blocks.count ?? 0 }
                ])
                let rows: [ChatTextRow] = [ReferencePreparationChatTextRow(frame: .zero), LayerChatTextRow(frame: .zero)]
                for mode in 0..<2 { windows[mode].contentView = rows[mode]; rows[mode].bind(items[mode][0]); rows[mode].layoutSubtreeIfNeeded() }
                var indices = [0, 0]
                let operations = (0..<2).map { mode -> () -> Int in
                    return {
                        indices[mode] = 1 - indices[mode]
                        rows[mode].bind(items[mode][indices[mode]])
                        rows[mode].layoutSubtreeIfNeeded()
                        return rows[mode].subviews.count
                    }
                }
                record("attached_rebind_blocks_\(blocks)_quoted_\(quoted)", count: 2000, operations: operations)
            }
        }
        XCTAssertGreaterThan(sink, 0)
        let data = try JSONSerialization.data(withJSONObject: ["unit": "nanoseconds_per_operation", "batches_before_after": results, "reverse": reverse, "sink": sink, "binding_attached_to_window": true, "binding_completed_layout": true], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-quote-scan-benchmark.json"))
    }
}
