import XCTest
import Cocoa
import TGUIKit
@testable import StatusLayers

final class LayerTests: XCTestCase {
    override func setUp() { initializeLab() }
    private func layout(_ text: String = "12:34", color: NSColor = .white) -> TextViewLayout {
        let result = TextViewLayout(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: color]), maximumNumberOfLines: 1)
        result.measure(width: 300)
        return result
    }

    func testUnchangedLayoutDoesNotMutateGeometry() {
        let baseline = ReferenceChatRightTextLayer()
        let candidate = ChatRightTextLayer()
        let text = layout()
        baseline.update(text)
        candidate.update(text)
        let old = baseline.sublayers!.first!, new = candidate.sublayers!.first!
        var oldChanges = 0, newChanges = 0
        let oldObservation = old.observe(\.bounds, options: [.old, .new]) { _, change in
            if change.oldValue != change.newValue { oldChanges += 1 }
        }
        let newObservation = new.observe(\.bounds, options: [.old, .new]) { _, change in
            if change.oldValue != change.newValue { newChanges += 1 }
        }
        for _ in 0..<1000 { baseline.updateDrawLayer(); candidate.updateDrawLayer() }
        withExtendedLifetime([oldObservation, newObservation]) {}
        XCTAssertEqual(oldChanges, 2000)
        XCTAssertEqual(newChanges, 0)
        XCTAssertEqual(old.bounds, new.bounds)
        XCTAssertEqual(old.frame, new.frame)
        XCTAssertEqual(old.position, new.position)
    }

    func testGeometryMatchesThroughResizingAndMoving() {
        let baseline = ReferenceChatRightTextLayer()
        let candidate = ChatRightTextLayer()
        let text = layout()
        baseline.update(text)
        candidate.update(text)
        for i in 0..<500 {
            let rect = CGRect(x: Double(i % 7) - 3.5, y: Double(i % 13) - 6.25, width: Double(i % 200) * 0.5, height: Double(i % 37) * 0.5)
            baseline.bounds = rect
            candidate.bounds = rect
            baseline.position = CGPoint(x: CGFloat(i), y: CGFloat(i * 2))
            candidate.position = baseline.position
            baseline.updateDrawLayer()
            candidate.updateDrawLayer()
            let old = baseline.sublayers!.first!, new = candidate.sublayers!.first!
            XCTAssertEqual(old.bounds, new.bounds)
            XCTAssertEqual(old.frame, new.frame)
            XCTAssertEqual(old.position, new.position)
        }
    }

    private func pixels(_ layer: CALayer, scale: CGFloat) -> Data {
        let side = 400
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 20, y: 50)
        context.scaleBy(x: scale, y: scale)
        let child = layer.sublayers!.first!
        child.display()
        layer.render(in: context)
        return Data(bytes: context.data!, count: side * side * 4)
    }

    func testPixelsMatchForStatusStringsAndScales() {
        for scale in [CGFloat(1), 2, 3] {
            let baseline = ReferenceChatRightTextLayer()
            let candidate = ChatRightTextLayer()
            for text in ["12:34", "edited", "1.2K", "يوم ١٢:٣٤", "👋 9:41", ""] {
                let value = layout(text)
                baseline.update(value)
                candidate.update(value)
                baseline.updateScale(scale)
                candidate.updateScale(scale)
                let old = pixels(baseline, scale: scale), new = pixels(candidate, scale: scale)
                XCTAssertEqual(old, new, "\(text) at \(scale)x")
                if !text.isEmpty { XCTAssertTrue(new.contains { $0 != 0 }) }
            }
        }
    }

    func testMutableLayoutStillRedrawsOnUpdate() {
        let baseline = ReferenceChatRightTextLayer()
        let candidate = ChatRightTextLayer()
        let text = layout()
        baseline.update(text)
        candidate.update(text)
        let before = pixels(candidate, scale: 2)
        text.setAttributedString(NSAttributedString(string: "15:59", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.red]))
        text.measure(width: 300)
        baseline.update(text)
        candidate.update(text)
        XCTAssertTrue(candidate.sublayers!.first!.needsDisplay())
        let after = pixels(candidate, scale: 2)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(after, pixels(baseline, scale: 2))
    }

    func testBenchmark() throws {
        guard ProcessInfo.processInfo.environment["STATUS_LAYER_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in benchmark") }
        let baseline = (0..<100).map { _ in ReferenceChatRightTextLayer() }
        let candidate = (0..<100).map { _ in ChatRightTextLayer() }
        let text = layout()
        baseline.forEach { $0.update(text) }
        candidate.forEach { $0.update(text) }
        let count = 1000
        func measure(_ body: () -> Void) -> Double {
            let start = CFAbsoluteTimeGetCurrent()
            for _ in 0..<count { body() }
            return (CFAbsoluteTimeGetCurrent() - start) * 1_000_000 / Double(count)
        }
        var old: [Double] = [], new: [Double] = []
        for i in 0..<9 {
            if i % 2 == 0 {
                old.append(measure { baseline.forEach { $0.updateDrawLayer() } })
                new.append(measure { candidate.forEach { $0.updateDrawLayer() } })
            } else {
                new.append(measure { candidate.forEach { $0.updateDrawLayer() } })
                old.append(measure { baseline.forEach { $0.updateDrawLayer() } })
            }
        }
        let result: [String: Any] = ["layers": 100, "passes_per_batch": count, "batches": 9, "baseline_us": old.sorted()[4], "candidate_us": new.sorted()[4], "speedup": old.sorted()[4] / new.sorted()[4]]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-status-layer-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
