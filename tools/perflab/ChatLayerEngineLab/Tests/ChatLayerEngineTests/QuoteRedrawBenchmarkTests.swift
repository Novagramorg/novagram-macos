import Cocoa
import XCTest
import ObjectiveC
import TGUIKit
import InputTextView

final class QuoteRedrawBenchmarkTests: XCTestCase {
    func testAssignmentAndRasterizationCosts() throws {
        guard ProcessInfo.processInfo.environment["QUOTE_REDRAW_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in quote redraw benchmark") }
        TGUIKitTestBootstrap.install()
        System.updateScaleFactor(2)
        let reverse = ProcessInfo.processInfo.environment["QUOTE_REDRAW_REVERSE"] == "1"
        var batches: [String: [[Double]]] = [:]
        var sink = 0
        func measure(_ name: String, operations: [() -> Void]) {
            for action in operations { autoreleasepool { for _ in 0..<20 { action() } } }
            var samples = [[Double](), [Double]()]
            for batch in 0..<9 {
                for index in (batch % 2 == 0) != reverse ? [0, 1] : [1, 0] {
                    let elapsed = autoreleasepool { () -> Double in
                        let start = CACurrentMediaTime()
                        for _ in 0..<200 { operations[index]() }
                        return (CACurrentMediaTime() - start) * 1_000_000 / 200
                    }
                    samples[index].append(elapsed)
                }
            }
            batches[name] = samples
        }
        for count in [1, 3, 12] {
            for header in [false, true] {
                let values = (0..<count).flatMap { index -> [TextViewBlockQuote] in
                    let value = QuoteRedrawTests().quotes(code: header, header: header)
                    value[0].frame.origin.y = CGFloat(index) * 68
                    return value
                }
                let current = FoldingTextQuoteLayer(), original = OriginalRedrawQuoteLayer()
                let frame = CGRect(x: 0, y: 0, width: 260, height: count * 68)
                current.frame = frame; original.frame = frame
                current.blockQuotes = values; original.blockQuotes = values
                current.displayIfNeeded(); original.displayIfNeeded()
                for display in [false, true] {
                    measure("same_\(count)_header\(header)_display\(display)", operations: [
                        { original.blockQuotes = values; if display { original.displayIfNeeded() }; sink &+= original.needsDisplay() ? 1 : 0 },
                        { current.blockQuotes = values; if display { current.displayIfNeeded() }; sink &+= current.needsDisplay() ? 1 : 0 }
                    ])
                    original.displayIfNeeded(); current.displayIfNeeded()
                }
                measure("changed_\(count)_header\(header)", operations: [
                    { values[0].frame.origin.x = values[0].frame.origin.x == 0 ? 1 : 0; original.blockQuotes = values; original.displayIfNeeded(); sink &+= original.contents == nil ? 0 : 1 },
                    { values[0].frame.origin.x = values[0].frame.origin.x == 0 ? 1 : 0; current.blockQuotes = values; current.displayIfNeeded(); sink &+= current.contents == nil ? 0 : 1 }
                ])
                measure("construct_\(count)_header\(header)", operations: [
                    { let layer = OriginalRedrawQuoteLayer(); layer.frame = frame; layer.blockQuotes = values; layer.displayIfNeeded(); sink &+= layer.contents == nil ? 0 : 1 },
                    { let layer = FoldingTextQuoteLayer(); layer.frame = frame; layer.blockQuotes = values; layer.displayIfNeeded(); sink &+= layer.contents == nil ? 0 : 1 }
                ])
            }
        }
        let result: [String: Any] = ["batches": batches, "reverse": reverse, "sink": sink, "runtimeBytes": [class_getInstanceSize(OriginalRedrawQuoteLayer.self), class_getInstanceSize(FoldingTextQuoteLayer.self)]]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/quote-redraw-benchmark.json"))
    }
}
