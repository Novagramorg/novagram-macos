import Cocoa
import QuartzCore
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class SelectionManagerBenchmarkTests: XCTestCase {
    func testSelectionCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_SELECTION_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in selection manager benchmark") }
        TGUIKitTestBootstrap.install()
        var results: [String: [[Double]]] = [:]
        var sink = 0
        func measure(_ name: String, count: Int, original: () -> Void, current: () -> Void) {
            var batches = [[Double](), [Double]()]
            for _ in 0..<10 { original(); current() }
            for batch in 0..<9 {
                for mode in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    for _ in 0..<count {
                        autoreleasepool {
                            if mode == 0 { original() }
                            else { current() }
                        }
                    }
                    batches[mode].append((CACurrentMediaTime() - start) * 1_000_000 / Double(count))
                }
            }
            results[name] = batches
        }
        for rows in [1, 16, 128, 512] {
            let original = LegacySelectManager(), current = SelectManager()
            let strings = (0..<rows).map { index in NSAttributedString(string: "Row \(index) " + String(repeating: "Latin 🦆 مرحبا 中文 ", count: 16), attributes: [.foregroundColor: NSColor.blue]) }
            for (index, text) in strings.enumerated() {
                original.add(range: NSRange(location: 0, length: text.length), textView: nil, layout: nil, text: text, header: "Author", stableId: index, index: 0)
                current.add(range: NSRange(location: 0, length: text.length), textView: nil, layout: nil, text: text, header: "Author", stableId: index, index: 0)
            }
            XCTAssertTrue(original.selectedText.isEqual(to: current.selectedText))
            measure("copy_\(rows)_rows", count: rows > 100 ? 25 : 200, original: { sink += original.selectedText.length }, current: { sink += current.selectedText.length })
            let sources = (0..<rows).map { _ in SelectionManagerTests.Source() }
            measure("native_drag_update_\(rows)_rows", count: rows > 100 ? 50 : 500, original: {
                original.removeAll()
                for (index, text) in strings.enumerated() { original.add(range: NSRange(location: 0, length: text.length), textView: nil, layout: nil, text: text, header: nil, stableId: index, index: 0) }
                sink += original.isEmpty ? 0 : 1
            }, current: {
                current.removeAll()
                for (index, text) in strings.enumerated() { current.add(range: NSRange(location: 0, length: text.length), textView: nil, layout: nil, text: text, header: nil, stableId: index, index: 0) }
                sink += current.isEmpty ? 0 : 1
            })
            original.removeAll(); current.removeAll()
            measure("custom_drag_update_\(rows)_rows", count: rows > 100 ? 50 : 500, original: {
                original.removeAll()
                for (index, text) in strings.enumerated() { original.addBubble(fragment: .init(attributedString: text, range: NSRange(location: 0, length: text.length), index: 0), source: sources[index], header: nil, stableId: index) }
                sink += original.isEmpty ? 0 : 1
            }, current: {
                current.removeAll()
                for (index, text) in strings.enumerated() { current.addBubble(fragment: .init(attributedString: text, range: NSRange(location: 0, length: text.length), index: 0), source: sources[index], header: nil, stableId: index) }
                sink += current.isEmpty ? 0 : 1
            })
        }
        XCTAssertGreaterThan(sink, 0)
        let data = try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_original_then_current": results, "sink": sink], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-selection-manager-benchmark.json"))
    }
}
