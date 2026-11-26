import Cocoa
import XCTest
import QuartzCore
@testable import FoldingViewHarness

final class FoldingViewBenchmarkTests: XCTestCase {
    func testNativeViewUpdateCosts() throws {
        guard ProcessInfo.processInfo.environment["FOLDING_VIEW_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in native folding view benchmark") }
        TGUIKitTestBootstrap.install()
        let fixtures = FoldingViewTests()
        var results: [String: Any] = [:]
        var sink = 0
        func measure(_ name: String, iterations: Int, before: () -> Void, after: () -> Void) {
            var batches = [[Double](), [Double]()]
            for _ in 0..<10 { before(); after() }
            for batch in 0..<9 {
                for mode in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    for _ in 0..<iterations {
                        autoreleasepool { if mode == 0 { before() } else { after() } }
                    }
                    batches[mode].append((CACurrentMediaTime() - start) * 1e6 / Double(iterations))
                }
            }
            results[name] = batches
        }
        for count in [1, 3, 12, 128] {
            for quoted in [false, true] {
                let a = fixtures.legacy(count, quoted: quoted), b = fixtures.layout(count, quoted: quoted)
                let iterations = count > 12 ? 25 : 250
                let suffix = "\(count)_quote_\(quoted)"
                measure("construct_\(suffix)", iterations: iterations, before: {
                    let view = LegacyFoldingTextView(frame: .zero)
                    view.update(layout: a, animated: false)
                    sink += view.subviews.count
                }, after: {
                    let view = FoldingTextView(frame: .zero)
                    view.update(layout: b, animated: false)
                    sink += view.subviews.count
                })
                let old = LegacyFoldingTextView(frame: .zero), current = FoldingTextView(frame: .zero)
                old.update(layout: a, animated: false); current.update(layout: b, animated: false)
                measure("rebind_\(suffix)", iterations: iterations * 4, before: { old.update(layout: a, animated: false) }, after: { current.update(layout: b, animated: false) })
            }
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_original_then_current": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/folding-view-benchmark.json"))
    }
}
