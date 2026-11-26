import Cocoa
import XCTest
import QuartzCore
@testable import FoldingViewHarness

final class ChatTextReuseBenchmarkTests: XCTestCase {
    func testChatTextBindingCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_TEXT_REUSE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in chat text binding benchmark") }
        TGUIKitTestBootstrap.install()
        let fixtures = ChatTextReuseTests()
        var results: [String: Any] = [:]
        for count in [1, 3, 12, 128] {
            for quoted in [false, true] {
                let context = BlockContext()
                let baseline = ReplacementChatTextRow(frame: .zero), candidate = ReusedChatTextRow(frame: .zero)
                let rows: [ChatTextRow] = [baseline, candidate]
                let items = (0..<2).map { _ in (1...2).map { fixtures.item($0, count: count, quoted: quoted, context: context) } }
                let iterations = count > 12 ? 40 : 500
                var batches = [[Double](), [Double]()]
                for index in 0..<20 { for mode in 0..<2 { rows[mode].bind(items[mode][index % 2]) } }
                for batch in 0..<9 {
                    for mode in batch % 2 == 0 ? [0, 1] : [1, 0] {
                        let start = CACurrentMediaTime()
                        for index in 0..<iterations {
                            autoreleasepool { rows[mode].bind(items[mode][index % 2]) }
                        }
                        batches[mode].append((CACurrentMediaTime() - start) * 1e6 / Double(iterations))
                    }
                }
                XCTAssertEqual(candidate.subviews.count, 1)
                XCTAssertEqual(candidate.text?.textViews.count, count)
                results["\(count)_quote_\(quoted)"] = batches
            }
        }
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_binding", "batches_replacement_then_reuse": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-text-reuse-benchmark.json"))
    }
}
