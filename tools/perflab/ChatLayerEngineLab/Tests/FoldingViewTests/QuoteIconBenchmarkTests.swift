import Cocoa
import XCTest
import QuartzCore
import TGUIKit
@testable import FoldingViewHarness

final class QuoteIconBenchmarkTests: XCTestCase {
    func testTintAndCompleteDrawingCosts() throws {
        guard ProcessInfo.processInfo.environment["CHAT_QUOTE_ICON_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in quote icon benchmark") }
        guard let path = ProcessInfo.processInfo.environment["CHAT_COPY_ICON_BUNDLE"], let bundle = Bundle(path: path) else { throw XCTSkip("Supply the asset-only probe bundle") }
        TGUIKitTestBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["CHAT_QUOTE_ICON_REVERSE"] == "1"
        let oldScale = System.backingScale, previous = TelegramThemeHooks.imageOverride
        System.updateScaleFactor(2)
        defer { System.updateScaleFactor(oldScale); TelegramThemeHooks.imageOverride = previous }
        let factory = QuoteIconTests()
        let makeSource = { bundle.image(forResource: NSImage.Name("Icon_CopyCode"))! }
        TelegramThemeHooks.imageOverride = { name in name == .iconCopyCode ? makeSource() : NSImage(named: "Icon_Quote")! }
        var results: [String: [[Double]]] = [:]
        var sink = 0
        func record(_ name: String, count: Int, operations: [() -> Int]) {
            for operation in operations { for _ in 0..<40 { sink += operation() } }
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                for mode in (batch % 2 == 0) != reverse ? [0, 1] : [1, 0] {
                    let start = CACurrentMediaTime()
                    for _ in 0..<count { autoreleasepool { sink += operations[mode]() } }
                    batches[mode].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                }
            }
            results[name] = batches
        }
        let cache = FoldingTextQuoteLayer.CopyIconCache()
        for cardinality in [1, 4, 32] {
            let colors = (0..<cardinality).map { NSColor(calibratedHue: CGFloat($0) / CGFloat(cardinality), saturation: 0.7, brightness: 0.8, alpha: 1) }
            var indices = [0, 0]
            record("tint_colors_\(cardinality)", count: 2000, operations: [
                { let color = colors[indices[0] % cardinality]; indices[0] += 1; return makeSource().precomposed(color, flipVertical: true, scale: 2).width },
                { let color = colors[indices[1] % cardinality]; indices[1] += 1; return cache.image(makeSource(), color: color, scale: 2).width }
            ])
        }
        for count in [1, 3, 12] {
            for code in [false, true] {
                let blocks = factory.quotes(count, code: code)
                let reference = ReferenceIconQuoteLayer(), current = FoldingTextQuoteLayer()
                reference.blockQuotes = blocks; current.blockQuotes = blocks
                let layers: [CALayer] = [reference, current]
                let contexts = (0..<2).map { _ in CGContext(data: nil, width: 520, height: count * 220, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)! }
                contexts.forEach { $0.scaleBy(x: 2, y: 2) }
                let operations = (0..<2).map { mode -> () -> Int in
                    return { contexts[mode].clear(CGRect(x: 0, y: 0, width: 260, height: count * 110)); layers[mode].draw(in: contexts[mode]); return count }
                }
                record("complete_painter_blocks_\(count)_code_\(code)", count: 600, operations: operations)
            }
        }
        let value = NSMutableAttributedString(string: "let value = 1\nprint(value)\nlet title = \"Hello\"\nprint(title)\nreturn value", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.black])
        let header = TextNode.layoutText(NSAttributedString(string: "Swift", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.blue]), nil, 1, .end, NSSize(width: 200, height: 40), nil, false, .left)
        value.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: 0, colors: .init(main: .blue), isCode: true, header: header), range: value.range)
        let text = TextViewLayout(value)
        text.measure(width: 240)
        let reference = ReferenceIconQuoteLayer(), current = FoldingTextQuoteLayer()
        reference.blockQuotes = text.blockQuotes; current.blockQuotes = text.blockQuotes
        let decorations: [CALayer] = [reference, current]
        let textLayers = (0..<2).map { _ -> TextViewLayer in
            let layer = TextViewLayer()
            layer.contentsScale = 2
            layer.canDrawBlocks = false
            layer.frame = CGRect(origin: .zero, size: text.layoutSize)
            layer.update(text)
            return layer
        }
        let contexts = (0..<2).map { _ in CGContext(data: nil, width: 520, height: Int(ceil(text.layoutSize.height * 2)), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)! }
        contexts.forEach { $0.scaleBy(x: 2, y: 2) }
        record("composed_code_text_five_lines", count: 1200, operations: (0..<2).map { mode -> () -> Int in
            return {
                contexts[mode].clear(CGRect(x: 0, y: 0, width: 260, height: text.layoutSize.height))
                decorations[mode].draw(in: contexts[mode])
                textLayers[mode].draw(in: contexts[mode])
                return text.lines.count
            }
        })
        XCTAssertGreaterThan(sink, 0)
        let data = try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_before_after": results, "reverse": reverse, "sink": sink, "uses_production_copy_asset": true, "asset_loader": "Xcode-generated Bundle.image(forResource:)"], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/chat-quote-icon-benchmark.json"))
    }
}
