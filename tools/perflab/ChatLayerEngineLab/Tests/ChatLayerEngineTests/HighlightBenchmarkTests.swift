import Cocoa
import XCTest
import Darwin
import TGUIKit
@testable import ChatLayerEngine

final class HighlightBenchmarkTests: XCTestCase {
    func testInactiveHighlightOverhead() throws {
        guard ProcessInfo.processInfo.environment["CHAT_HIGHLIGHT_BENCHMARK"] != nil else { throw XCTSkip("Opt-in inactive highlight overhead") }
        TGUIKitTestBootstrap.install()
        let layout = MessageTextTests().layout(["An ordinary message without an active search highlight."]).blocks[0].text
        let old = ReferenceHighlightTextNode(id: "old", selectable: true)
        let new = ChatLayerTextNode(id: "new", selectable: true)
        old.update(layout); new.update(layout)
        let oldBytes = malloc_size(Unmanaged.passUnretained(old).toOpaque())
        let newBytes = malloc_size(Unmanaged.passUnretained(new).toOpaque())
        var report: [String: Any] = ["baseline_node_malloc_bytes": oldBytes, "candidate_node_malloc_bytes": newBytes]
        for scenario in ["construct", "update"] {
            func measure(_ reference: Bool) -> Double {
                let count = 1000
                var sublayers = 0
                let start = CFAbsoluteTimeGetCurrent()
                for index in 0..<count {
                    autoreleasepool {
                        if scenario == "construct" {
                            if reference {
                                let node = ReferenceHighlightTextNode(id: index, selectable: true)
                                node.update(layout)
                                sublayers += node.layer.sublayers?.count ?? 0
                            } else {
                                let node = ChatLayerTextNode(id: index, selectable: true)
                                node.update(layout)
                                sublayers += node.layer.sublayers?.count ?? 0
                            }
                        } else if reference { old.update(layout) }
                        else { new.update(layout) }
                    }
                }
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000000 / Double(count)
                if scenario == "construct" { XCTAssertEqual(sublayers, count) }
                return elapsed
            }
            _ = measure(true); _ = measure(false)
            var baseline: [Double] = [], candidate: [Double] = []
            let reverse = ProcessInfo.processInfo.environment["CHAT_HIGHLIGHT_REVERSE"] != nil
            for batch in 0..<9 {
                if batch % 2 == (reverse ? 1 : 0) { baseline.append(measure(true)); candidate.append(measure(false)) }
                else { candidate.append(measure(false)); baseline.append(measure(true)) }
            }
            report[scenario] = ["baseline_us": baseline, "candidate_us": candidate, "baseline_median_us": baseline.sorted()[4], "candidate_median_us": candidate.sorted()[4]]
            print("CHAT_HIGHLIGHT \(scenario): \(baseline.sorted()[4]) -> \(candidate.sorted()[4]) us/call")
        }
        print("CHAT_HIGHLIGHT node allocation: \(oldBytes) -> \(newBytes) bytes")
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-highlight-benchmark.json"))
    }
}
