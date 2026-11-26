import Cocoa
import XCTest
import QuartzCore
@testable import FoldingViewHarness

final class CaptionReuseBenchmarkTests: XCTestCase {
    func testCaptionBindingCosts() throws {
        guard ProcessInfo.processInfo.environment["CAPTION_REUSE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in caption binding benchmark") }
        TGUIKitTestBootstrap.install()
        let fixture = CaptionReuseTests()
        var results: [String: [[Double]]] = [:]
        for count in [1, 3, 10] {
            for quoted in [false, true] {
                for scenario in ["unchanged", "edited", "recycled", "reorder", "construct"] {
                    let context = BlockContext()
                    let rows: [CaptionRowEnvironment] = [ReplacementCaptionRow(frame: .zero), ReusedCaptionRow(frame: .zero)]
                    let items = (0..<2).map { _ in (0..<2).map { step in
                        let values = (0..<count).map { index in
                            fixture.caption(index + 1 + (scenario == "recycled" ? step * 100 : 0), text: "Caption \(index) revision \(["edited", "recycled"].contains(scenario) ? step : 0) مرحبا 👩🏽‍💻\nMore text", context: context, blocks: quoted ? 3 : 1, quoted: quoted, offset: NSPoint(x: 5, y: index * 120))
                        }
                        return ChatRowItem(scenario == "reorder" && step == 1 ? values.reversed() : values)
                    } }
                    for index in 0..<2 { rows[index].bind(items[index][0]) }
                    for iteration in 0..<20 {
                        for variant in 0..<2 { rows[variant].bind(items[variant][iteration % 2]) }
                    }
                    var samples = [[Double](), [Double]()]
                    for batch in 0..<9 {
                        for variant in batch % 2 == 0 ? [0, 1] : [1, 0] {
                            let start = CFAbsoluteTimeGetCurrent()
                            for iteration in 0..<300 {
                                autoreleasepool {
                                    let row = scenario == "construct" ? (variant == 0 ? ReplacementCaptionRow(frame: .zero) as CaptionRowEnvironment : ReusedCaptionRow(frame: .zero)) : rows[variant]
                                    row.bind(items[variant][iteration % 2])
                                }
                            }
                            samples[variant].append((CFAbsoluteTimeGetCurrent() - start) * 1_000_000 / 300)
                        }
                    }
                    XCTAssertEqual(rows[0].views.count, count)
                    XCTAssertEqual(rows[1].views.count, count)
                    results["\(scenario)_\(count)_quoted_\(quoted)"] = samples
                }
            }
        }
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_caption_set", "batches_baseline_then_candidate": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-caption-benchmark.json"))
    }
}
