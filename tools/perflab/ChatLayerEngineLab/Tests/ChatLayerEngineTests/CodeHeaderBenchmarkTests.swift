import Cocoa
import QuartzCore
import XCTest
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

final class CodeHeaderBenchmarkTests: XCTestCase {
    func testCopyAndHeaderBindingCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_CODE_HEADER_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in code header benchmark") }
        TGUIKitTestBootstrap.install()
        var results: [String: [[Double]]] = [:]
        var sink = 0
        let fixture = CodeHeaderTests()
        func record(_ name: String, count: Int, original: (Int) throws -> Void, current: (Int) throws -> Void) rethrows {
            var batches = [[Double](), [Double]()]
            for index in 0..<100 { try original(index); try current(index) }
            for batch in 0..<9 {
                for mode in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    for index in 0..<count {
                        try autoreleasepool {
                            if mode == 0 { try original(index) }
                            else { try current(index) }
                        }
                    }
                    batches[mode].append((CACurrentMediaTime() - start) * 1_000_000 / Double(count))
                }
            }
            results[name] = batches
        }
        for length in [32, 4096, 32768] {
            for fragmented in [false, true] {
                let value = NSMutableAttributedString(string: String(repeating: "a", count: length), attributes: [TextInputAttributes.quote: "code"])
                if fragmented {
                    for index in 0..<length { value.addAttribute(.foregroundColor, value: index % 2 == 0 ? NSColor.blue : NSColor.red, range: NSRange(location: index, length: 1)) }
                }
                let text = TextViewLayout(value)
                let range = NSRange(location: 0, length: min(10, length))
                record("copy_\(length)_fragmented_\(fragmented)", count: length > 4096 ? 100 : 1000, original: { _ in
                    sink += fixture.legacyText(value, range: range).utf16.count
                }, current: { _ in
                    sink += text.blockQuoteText(startingWith: range)!.utf16.count
                })
            }
        }
        let sources = [CodeHeaderTests().source(), CodeHeaderTests().source("func run() {\n    print(42)\n}\nrun()", width: 200)]
        try record("header_construction", count: 1000, original: { index in
            sink += Int(makeReferenceFoldingWrapper(sources[index % 2].blocks[0]).frame.height)
        }, current: { index in
            let scene = ChatLayerSceneView(frame: .zero)
            let body = ChatLayerMessageTextNode(id: "body")
            try scene.root.setChildren([body])
            try body.update(ChatLayerMessageTextPresentation(sources[index % 2]), messageId: index, selectable: true)
            sink += Int(body.frame.height)
        })
        let native = makeReferenceFoldingWrapper(sources[0].blocks[0])
        let scene = ChatLayerSceneView(frame: .zero)
        let body = ChatLayerMessageTextNode(id: "body")
        try scene.root.setChildren([body])
        try record("header_changed_rebind", count: 10000, original: { index in
            updateReferenceFoldingWrapper(native, layout: sources[index % 2].blocks[0])
            sink += Int(native.frame.height)
        }, current: { index in
            try body.update(ChatLayerMessageTextPresentation(sources[index % 2]), messageId: index, selectable: true)
            sink += Int(body.frame.height)
        })
        XCTAssertGreaterThan(sink, 0)
        let data = try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_original_then_current": results, "sink": sink], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-code-header-benchmark.json"))
    }
}
