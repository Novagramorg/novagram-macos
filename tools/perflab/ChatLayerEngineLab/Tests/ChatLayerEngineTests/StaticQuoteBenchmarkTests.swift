import Cocoa
import QuartzCore
import XCTest
import TGUIKit
import InputTextView
@testable import ChatLayerEngine

final class StaticQuoteBenchmarkTests: XCTestCase {
    func testNativeWrapperAndLayerQuoteConstructionAndRebinding() throws {
        try measure(folded: false)
    }

    func testNativeWrapperAndLayerFoldConstructionAndRebinding() throws {
        try measure(folded: true)
    }

    private func measure(folded: Bool) throws {
        guard ProcessInfo.processInfo.environment["CHAT_QUOTE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in static quote benchmark") }
        TGUIKitTestBootstrap.install()
        let fixture = StaticQuoteTests()
        let sources = folded ? [FoldingQuoteTests().source("First quoted line\nSecond line\nThird line\nFourth line\nLast line", revealed: false), FoldingQuoteTests().source("First quoted line\nSecond line\nThird line\nFourth line\nLast line", revealed: true)] : [fixture.source("A quoted paragraph with several words that wrap onto lines.\nAnother quoted line.", colors: 2), fixture.source("مرحبا English שלום\nAnother different quoted message.", width: 200, colors: 1)]
        var results: [String: [[Double]]] = [:]
        var sink: CGFloat = 0
        func record(_ name: String, count: Int, native: (Int) throws -> Void, layers: (Int) throws -> Void) rethrows {
            var samples = [[Double](), [Double]()]
            for index in 0..<100 { try native(index); try layers(index) }
            for batch in 0..<9 {
                for mode in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    for index in 0..<count {
                        try autoreleasepool {
                            if mode == 0 { try native(index) }
                            else { try layers(index) }
                        }
                    }
                    samples[mode].append((CACurrentMediaTime() - start) * 1_000_000 / Double(count))
                }
            }
            results[name] = samples
        }
        try record("construction", count: 1000, native: { index in
            let view = makeReferenceFoldingWrapper(sources[index % 2].blocks[0])
            sink += view.frame.height
        }, layers: { index in
            let scene = ChatLayerSceneView(frame: .zero)
            let body = ChatLayerMessageTextNode(id: "body")
            if folded { body.revealBlockAtIndex = { _ in } }
            try scene.root.setChildren([body])
            try body.update(ChatLayerMessageTextPresentation(sources[index % 2]), messageId: index, selectable: true)
            scene.frame.size = body.frame.size
            sink += scene.frame.height
        })
        let native = makeReferenceFoldingWrapper(sources[0].blocks[0])
        let scene = ChatLayerSceneView(frame: .zero)
        let body = ChatLayerMessageTextNode(id: "body")
        if folded { body.revealBlockAtIndex = { _ in } }
        try scene.root.setChildren([body])
        try record("changed_content_rebind", count: 10000, native: { index in
            updateReferenceFoldingWrapper(native, layout: sources[index % 2].blocks[0])
            sink += native.frame.height
        }, layers: { index in
            try body.update(ChatLayerMessageTextPresentation(sources[index % 2]), messageId: index, selectable: true)
            scene.frame.size = body.frame.size
            sink += scene.frame.height
        })
        XCTAssertGreaterThan(sink, 0)
        let data = try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_native_then_layer": results, "sink": sink], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: folded ? "/tmp/chat-fold-quote-benchmark.json" : "/tmp/chat-static-quote-benchmark.json"))
    }
}
