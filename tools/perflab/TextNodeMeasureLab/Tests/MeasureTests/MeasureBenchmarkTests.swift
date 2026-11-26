import AppKit
import CoreText
import QuartzCore
import XCTest
import class TGUIKit.TextNode
import class TGUIKit.TextNodeLayout
import class TGUIKitBaseline.TextNode
import class TGUIKitBaseline.TextNodeLayout

final class MeasureBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["TEXTNODE_MEASURE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in TextNode measurement timing") }
        MeasureBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["TEXTNODE_MEASURE_REVERSE"] == "1"
        var output: [String: [[Double]]] = [:]
        var sink: CGFloat = 0
        func measure(_ name: String, count: Int = 5000, old: () -> CGFloat, new: () -> CGFloat) {
            for _ in 0..<100 { sink += old(); sink += new() }
            var values = [[Double](), [Double]()]
            for batch in 0..<9 {
                for variant in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                    autoreleasepool {
                        let start = CACurrentMediaTime()
                        if variant == 0 { for _ in 0..<count { sink += old() } }
                        else { for _ in 0..<count { sink += new() } }
                        values[variant].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                    }
                }
            }
            output[name] = values
        }
        let cases: [(String, String, Int, CGFloat)] = [
            ("short_fits", "Alice Parker", 1, 160),
            ("short_unbounded", "Alice Parker", 1, .greatestFiniteMagnitude),
            ("filename_truncated", "Holiday video from the family trip 2026 final.mov", 1, 100),
            ("rtl_truncated", "مرحبا بالعالم שלום עולם mixed 123", 1, 90),
            ("emoji_truncated", "👨‍👩‍👧‍👦 🏳️‍🌈 hello 🎉", 1, 70),
            ("two_lines", String(repeating: "word hello ", count: 15), 2, 160),
            ("three_lines", String(repeating: "word hello ", count: 15), 3, 160),
            ("unlimited", String(repeating: "word hello ", count: 6), 0, 160),
            ("zero_width", "Alice Parker", 1, 0),
            ("narrow_width", "Alice Parker", 1, 1)
        ]
        for (name, string, limit, width) in cases {
            let value = NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black, NSAttributedString.Key("KSelectedColorAttributeName"): NSColor.red])
            let size = CGSize(width: width, height: 500)
            for selected in [false, true] {
                measure(name + "_selected_\(selected)", old: {
                    let layout = TGUIKitBaseline.TextNode.layoutText(value, nil, limit, .middle, size, nil, selected, .left).0
                    return layout.size.width + layout.size.height
                }, new: {
                    let layout = TGUIKit.TextNode.layoutText(value, nil, limit, .middle, size, nil, selected, .left).0
                    return layout.size.width + layout.size.height
                })
            }
        }
        let title = NSAttributedString(string: "Alice Parker", attributes: [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.black])
        let status = NSAttributedString(string: "last seen recently", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.gray])
        let detail = NSAttributedString(string: "12:42", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.gray])
        let labels = [title, status, detail]
        measure("three_label_construction", old: {
            var sum: CGFloat = 0
            for label in labels { sum += TGUIKitBaseline.TextNode.layoutText(label, nil, 1, .end, CGSize(width: 160, height: 20), nil, false, .left).0.size.width }
            return sum
        }, new: {
            var sum: CGFloat = 0
            for label in labels { sum += TGUIKit.TextNode.layoutText(label, nil, 1, .end, CGSize(width: 160, height: 20), nil, false, .left).0.size.width }
            return sum
        })
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 80, bitsPerComponent: 8, bytesPerRow: 1600, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 2, y: 2)
        measure("label_measure_and_draw", count: 2000, old: {
            let value = TGUIKitBaseline.TextNode.layoutText(title, nil, 1, .end, CGSize(width: 160, height: 20), nil, false, .left)
            value.1.draw(CGRect(x: 2, y: 2, width: 160, height: 20), in: context, backingScaleFactor: 2, backgroundColor: .clear)
            return value.0.size.width
        }, new: {
            let value = TGUIKit.TextNode.layoutText(title, nil, 1, .end, CGSize(width: 160, height: 20), nil, false, .left)
            value.1.draw(CGRect(x: 2, y: 2, width: 160, height: 20), in: context, backingScaleFactor: 2, backgroundColor: .clear)
            return value.0.size.width
        })
        let old = TGUIKitBaseline.TextNode.layoutText(title, nil, 1, .end, CGSize(width: 160, height: 20), nil, false, .left)
        let new = TGUIKit.TextNode.layoutText(title, nil, 1, .end, CGSize(width: 160, height: 20), nil, false, .left)
        measure("unchanged_layout_reuse", count: 200000, old: {
            TGUIKitBaseline.TextNode.layoutText(maybeNode: old.1, title, nil, 1, .end, CGSize(width: 160, height: 20), nil, false, .left).0.size.width
        }, new: {
            TGUIKit.TextNode.layoutText(maybeNode: new.1, title, nil, 1, .end, CGSize(width: 160, height: 20), nil, false, .left).0.size.width
        })
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "reverse": reverse, "batches": output], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/text-node-measure-benchmark.json"))
    }
}
