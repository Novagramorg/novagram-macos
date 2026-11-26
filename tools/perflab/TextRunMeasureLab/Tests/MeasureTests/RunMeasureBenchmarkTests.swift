import Cocoa
import QuartzCore
import XCTest
import class TGUIKit.TextViewLayout
import class TGUIKitBaseline.TextViewLayout

final class RunMeasureBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["RUN_MEASURE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in quote measurement timing") }
        MeasureBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["RUN_MEASURE_REVERSE"] == "1"
        var output: [String: [[Double]]] = [:]
        var sink: CGFloat = 0
        func measure(_ name: String, count: Int, old: (Int) -> CGFloat, new: (Int) -> CGFloat) {
            for index in 0..<50 { sink += old(index); sink += new(index) }
            var values = [[Double](), [Double]()]
            for batch in 0..<9 {
                for variant in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                    autoreleasepool {
                        let start = CACurrentMediaTime()
                        if variant == 0 { for index in 0..<count { sink += old(index) } }
                        else { for index in 0..<count { sink += new(index) } }
                        values[variant].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                    }
                }
            }
            output[name] = values
        }
        let cases: [(String, String, [Int], Bool, Int)] = [
            ("truncated_plain", String(repeating: "hello world one two three ", count: 12), [], false, 1000),
            ("truncated_rich", String(repeating: "hello world one two three ", count: 12), [], true, 500),
            ("truncated_unicode", String(repeating: "مرحبا שלום 日本語 👨‍👩‍👧‍👦 e\u{301} ", count: 4), [], false, 500),
            ("immutable_short_plain", "Alice Parker", [], false, 3000),
            ("immutable_chat_plain", String(repeating: "hello world one two three ", count: 12), [], false, 1000),
            ("immutable_truncated_plain", String(repeating: "hello world one two three ", count: 12), [], false, 2000),
            ("immutable_truncated_rich", String(repeating: "hello world one two three ", count: 12), [], true, 1000),
            ("short_plain", "Alice Parker", [], false, 3000),
            ("chat_plain", String(repeating: "hello world one two three ", count: 12), [], false, 800),
            ("chat_quote", String(repeating: "hello world one two three ", count: 12), [1], false, 800),
            ("chat_code", String(repeating: "let value = example()\n", count: 12), [2], false, 600),
            ("unicode_plain", String(repeating: "مرحبا שלום 日本語 👨‍👩‍👧‍👦 e\u{301} ", count: 4), [], false, 500),
            ("colored_plain", String(repeating: "hello world one two three ", count: 12), [], false, 500),
            ("colored_quote", String(repeating: "hello world one two three ", count: 12), [1], false, 500),
            ("rich_plain", String(repeating: "hello world one two three ", count: 12), [], true, 250),
            ("long_plain", String(repeating: "hello world one two three ", count: 160), [], false, 80),
            ("long_quote", String(repeating: "hello world one two three ", count: 160), [1], false, 80),
            ("mixed_quotes", String(repeating: "hello world one two three ", count: 12), Array(repeating: 1, count: 35) + Array(repeating: 0, count: 35) + Array(repeating: 2, count: 35), false, 400)
        ]
        for (name, text, pattern, decorated, count) in cases {
            let oldText = TGUIKitBaseline.TextViewLayout.quoteFixture(text, pattern: pattern, decorated: decorated)
            let newText = TGUIKit.TextViewLayout.quoteFixture(text, pattern: pattern, decorated: decorated)
            if name.hasPrefix("colored_") {
                for index in stride(from: 0, to: oldText.length, by: 3) {
                    let range = NSRange(location: index, length: min(3, oldText.length - index))
                    let color = index % 2 == 0 ? NSColor.blue : NSColor.red
                    oldText.addAttribute(.foregroundColor, value: color, range: range)
                    newText.addAttribute(.foregroundColor, value: color, range: range)
                }
            }
            let oldValue: NSAttributedString = name.hasPrefix("immutable_") ? oldText.copy() as! NSAttributedString : oldText
            let newValue: NSAttributedString = name.hasPrefix("immutable_") ? newText.copy() as! NSAttributedString : newText
            let old = TGUIKitBaseline.TextViewLayout(oldValue, maximumNumberOfLines: name.contains("truncated_") ? 1 : 0)
            let new = TGUIKit.TextViewLayout(newValue, maximumNumberOfLines: name.contains("truncated_") ? 1 : 0)
            measure(name + "_cold", count: count, old: { _ in
                let value = TGUIKitBaseline.TextViewLayout(oldValue, maximumNumberOfLines: name.contains("truncated_") ? 1 : 0)
                value.measure(width: 280)
                return value.layoutSize.height
            }, new: { _ in
                let value = TGUIKit.TextViewLayout(newValue, maximumNumberOfLines: name.contains("truncated_") ? 1 : 0)
                value.measure(width: 280)
                return value.layoutSize.height
            })
            measure(name + "_resize", count: count, old: { index in
                old.measure(width: index % 2 == 0 ? 280 : 290)
                return old.layoutSize.height
            }, new: { index in
                new.measure(width: index % 2 == 0 ? 280 : 290)
                return new.layoutSize.height
            })
            XCTAssertEqual(old.quoteMeasurementSnapshot(), new.quoteMeasurementSnapshot())
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "reverse": reverse, "batches": output], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/run-measure-benchmark.json"))
    }
}
