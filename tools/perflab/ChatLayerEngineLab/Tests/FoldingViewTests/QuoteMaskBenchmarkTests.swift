import Cocoa
import XCTest
import QuartzCore
import TGUIKit
@testable import FoldingViewHarness

final class QuoteMaskBenchmarkTests: XCTestCase {
    func testMaskAndLayoutCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_QUOTE_MASK_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in quote mask benchmark") }
        TGUIKitTestBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["CHAT_QUOTE_MASK_REVERSE"] == "1"
        let factory = QuoteMaskTests()
        var results: [String: [[Double]]] = [:]
        var sink = 0
        func record(_ name: String, count: Int, operations: [() -> Int]) {
            for operation in operations { for _ in 0..<30 { sink += operation() } }
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                for mode in (batch % 2 == 0) != reverse ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    for _ in 0..<count { autoreleasepool { sink += operations[mode]() } }
                    batches[mode].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                }
            }
            results[name] = batches
        }
        let cache = FoldingQuoteMaskCache()
        for cardinality in [1, 8, 128] {
            var indices = [0, 0]
            let operations = (0..<2).map { mode -> () -> Int in
                return {
                    let size = NSSize(width: 200 + CGFloat(indices[mode] % cardinality) * 0.125, height: 40)
                    indices[mode] += 1
                    return (mode == 0 ? referenceMaskImage(size: size, y: 20, scale: 2) : cache.image(size: size, y: 20, scale: 2))?.width ?? 0
                }
            }
            record("mask_geometries_\(cardinality)", count: 1500, operations: operations)
        }
        for count in [1, 3, 12] {
            let a = factory.content(count), b = factory.content(count)
            let current = FoldingTextLayout(attributedString: a.0, blocks: a.1, blockRanges: a.2, context: BlockContext(), revealed: [])
            let reference = ReferenceMaskFoldingTextLayout(attributedString: b.0, blocks: b.1, blockRanges: b.2, context: BlockContext(), revealed: [])
            for geometries in [1, 8, 128] {
                var indices = [0, 0]
                record("measure_blocks_\(count)_widths_\(geometries)", count: 150, operations: [
                    { let width = 240 + CGFloat(indices[0] % geometries); indices[0] += 1; reference.measure(width: width); return Int(reference.size.height) },
                    { let width = 240 + CGFloat(indices[1] % geometries); indices[1] += 1; current.measure(width: width); return Int(current.size.height) }
                ])
            }
            record("construct_and_measure_blocks_\(count)", count: 100, operations: [
                { let c = factory.content(count); let value = ReferenceMaskFoldingTextLayout(attributedString: c.0, blocks: c.1, blockRanges: c.2, context: BlockContext(), revealed: []); value.measure(width: 240); return Int(value.size.height) },
                { let c = factory.content(count); let value = FoldingTextLayout(attributedString: c.0, blocks: c.1, blockRanges: c.2, context: BlockContext(), revealed: []); value.measure(width: 240); return Int(value.size.height) }
            ])
        }
        XCTAssertGreaterThan(sink, 0)
        let data = try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_before_after": results, "reverse": reverse, "sink": sink], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-quote-mask-benchmark.json"))
    }
}
