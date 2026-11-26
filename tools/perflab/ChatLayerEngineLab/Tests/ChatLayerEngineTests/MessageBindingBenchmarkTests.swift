import Cocoa
import XCTest
import Darwin
import TGUIKit
@testable import ChatLayerEngine

private protocol MessageBindingBenchmarkNode: AnyObject {
    var frame: NSRect { get }
    func update(_ presentation: ChatLayerMessageTextPresentation, messageId: AnyHashable, selectable: Bool) throws -> Bool
}

extension ReferenceMessageBindingNode: MessageBindingBenchmarkNode {}
extension PrepassMessageBindingNode: MessageBindingBenchmarkNode {}
extension ChatLayerMessageTextNode: MessageBindingBenchmarkNode {}

final class MessageBindingBenchmarkTests: XCTestCase {
    func testMessageConstructionUpdateAndReuse() throws {
        guard ProcessInfo.processInfo.environment["CHAT_MESSAGE_BINDING_BENCHMARK"] != nil else { throw XCTSkip("Opt-in message binding variants") }
        TGUIKitTestBootstrap.install()
        var report: [String: Any] = [:]
        let reverse = ProcessInfo.processInfo.environment["CHAT_MESSAGE_BINDING_REVERSE"] != nil
        for blockCount in [1, 3, 12] {
            let source = MessageTextTests().layout((0..<blockCount).map { "Paragraph \($0): a representative message to measure binding, construction and reuse." })
            let presentation = ChatLayerMessageTextPresentation(source)
            let original = ReferenceMessageBindingNode(id: "old")
            let prepass = PrepassMessageBindingNode(id: "prepass")
            let candidate = ChatLayerMessageTextNode(id: "new")
            try original.update(presentation, messageId: 1, selectable: true)
            try prepass.update(presentation, messageId: 1, selectable: true)
            try candidate.update(presentation, messageId: 1, selectable: true)
            report["allocation_bytes"] = ["baseline": malloc_size(Unmanaged.passUnretained(original).toOpaque()), "prepass": malloc_size(Unmanaged.passUnretained(prepass).toOpaque()), "candidate": malloc_size(Unmanaged.passUnretained(candidate).toOpaque())]
            for scenario in ["construct", "update", "reuse"] {
                func measureNode<Node: MessageBindingBenchmarkNode>(_ persistent: Node, factory: (Int) -> Node) throws -> Double {
                    let count = 1000
                    var sink: CGFloat = 0
                    let start = CFAbsoluteTimeGetCurrent()
                    for index in 0..<count {
                        try autoreleasepool {
                            let id = scenario == "reuse" ? index : 1
                            let node = scenario == "construct" ? factory(index) : persistent
                            _ = try node.update(presentation, messageId: id, selectable: true)
                            sink += node.frame.height
                        }
                    }
                    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000000 / Double(count)
                    XCTAssertGreaterThan(sink, 0)
                    return elapsed
                }
                func measure(_ mode: Int) throws -> Double {
                    switch mode {
                    case 0: return try measureNode(original, factory: { ReferenceMessageBindingNode(id: $0) })
                    case 1: return try measureNode(prepass, factory: { PrepassMessageBindingNode(id: $0) })
                    default: return try measureNode(candidate, factory: { ChatLayerMessageTextNode(id: $0) })
                    }
                }
                for mode in 0..<3 { _ = try measure(mode) }
                var values = [[Double](), [Double](), [Double]()]
                for batch in 0..<9 {
                    let order = (0..<3).map { ($0 + batch) % 3 }
                    for mode in reverse ? Array(order.reversed()) : order { values[mode].append(try measure(mode)) }
                }
                let medians = values.map { $0.sorted()[4] }
                report["\(scenario)_\(blockCount)"] = ["baseline_us": values[0], "prepass_us": values[1], "candidate_us": values[2], "median_us": medians]
                print("MESSAGE_BINDING \(scenario) \(blockCount): \(medians)")
            }
        }
        print("MESSAGE_BINDING allocation: \(report["allocation_bytes"]!)")
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-message-binding-benchmark.json"))
    }
}
