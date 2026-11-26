import Cocoa
import QuartzCore
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class EmbeddedSelectionBenchmarkTests: XCTestCase {
    func testEmbeddedSelectionCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_EMBEDDED_SELECTION_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in embedded selection benchmark") }
        TGUIKitTestBootstrap.install()
        let fixtures = EmbeddedTextSelectionTests()
        let window = fixtures.window()
        defer { window.contentView = nil; window.close() }
        var results: [String: [[Double]]] = [:]
        var sink = 0
        for count in [1, 16, 64] {
            let reference = ReferenceEmbeddedSelectionLoopHarness(SelectionTable(views: try (0..<count).map { try fixtures.makeRow($0, mask: 0) }))
            let native = SelectionLoopHarness(SelectionTable(views: try (0..<count).map { try fixtures.makeRow($0, mask: 0) }))
            let mixed = SelectionLoopHarness(SelectionTable(views: try (0..<count).map { try fixtures.makeRow($0, mask: 2) }))
            let layers = SelectionLoopHarness(SelectionTable(views: try (0..<count).map { try fixtures.makeRow($0, mask: 7) }))
            let end = NSPoint(x: 299, y: CGFloat(count * 100 - 1))
            let operations: [() -> Void] = [
                { reference.select(begin: .zero, end: end, window: window); sink += reference.selectManager.isEmpty ? 0 : 1 },
                { native.select(begin: .zero, end: end, window: window); sink += native.selectManager.isEmpty ? 0 : 1 },
                { mixed.select(begin: .zero, end: end, window: window); sink += mixed.selectManager.isEmpty ? 0 : 1 },
                { layers.select(begin: .zero, end: end, window: window); sink += layers.selectManager.isEmpty ? 0 : 1 }
            ]
            for operation in operations { for _ in 0..<10 { operation() } }
            XCTAssertTrue(reference.selectManager.selectedText.isEqual(to: native.selectManager.selectedText))
            XCTAssertTrue(reference.selectManager.selectedText.isEqual(to: mixed.selectManager.selectedText))
            XCTAssertTrue(reference.selectManager.selectedText.isEqual(to: layers.selectManager.selectedText))
            var batches = Array(repeating: [Double](), count: 4)
            let iterations = count == 64 ? 50 : 200
            for batch in 0..<9 {
                let modes = ProcessInfo.processInfo.environment["CHAT_EMBEDDED_SELECTION_REVERSE"] == "1" ? Array((0..<4).reversed()) : Array(0..<4)
                for offset in modes {
                    let mode = (offset + batch) % 4
                    let operation = operations[mode]
                    let start = CACurrentMediaTime()
                    for _ in 0..<iterations { autoreleasepool { operation() } }
                    batches[mode].append((CACurrentMediaTime() - start) * 1_000_000 / Double(iterations))
                }
            }
            results["drag_\(count)_rows_three_fragments"] = batches
        }
        XCTAssertGreaterThan(sink, 0)
        let data = try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_drag_update", "modes": ["original_native", "shared_native", "mixed", "layers"], "batches": results, "sink": sink], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-embedded-selection-benchmark.json"))
    }
}
