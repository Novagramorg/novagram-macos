import XCTest
import Cocoa
@testable import TGUIKit

final class TextRunDrawingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func line(_ text: String, style: Int) -> CTLine {
        let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.blue])
        if value.length > 1 {
            let range = NSRange(location: value.length / 2, length: value.length - value.length / 2)
            switch style {
            case 1: value.addAttribute(.foregroundColor, value: NSColor.red, range: range)
            case 2: value.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 20), range: range)
            case 3: value.addAttribute(.underlineStyle, value: 1, range: range)
            case 4: value.addAttribute(.strikethroughStyle, value: 1, range: range)
            case 5: value.addAttribute(.kern, value: 2, range: range)
            case 6: value.addAttribute(.baselineOffset, value: 3, range: range)
            case 7: value.addAttributes([.strokeWidth: -2, .strokeColor: NSColor.green], range: range)
            case 8: value.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
            default: break
            }
        }
        return CTLineCreateWithAttributedString(value)
    }

    private func draw(_ lines: [CTLine], scale: CGFloat, flipped: Bool, resetPosition: Bool, limit: Int?, legacy: Bool) -> (Data, Int, CGPoint, CGAffineTransform) {
        let context = CGContext(data: nil, width: 1200, height: 300, bitsPerComponent: 8, bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: flipped ? -1 : 1)
        context.setFillColor(NSColor.magenta.cgColor)
        var drawn = 0
        for (index, line) in lines.enumerated() {
            let point = CGPoint(x: 12.5, y: 30.5 + CGFloat(index) * 24)
            context.textPosition = point
            if legacy {
                legacyDrawTextLineRuns(line, in: context, at: resetPosition ? point : nil, maximumGlyphCount: limit, drawnGlyphCount: &drawn)
            } else {
                drawTextLineRuns(line, in: context, at: resetPosition ? point : nil, maximumGlyphCount: limit, drawnGlyphCount: &drawn)
            }
        }
        context.fill(CGRect(x: 350, y: 0, width: 3, height: 3))
        return (Data(bytes: context.data!, count: 1440000), drawn, context.textPosition, context.textMatrix)
    }

    func testExactPixelsAndContextForStylesLanguagesAndScales() {
        for text in ["Plain text 12:34", "Emoji 👨‍👩‍👧‍👦 🦆 🇦🇪", "مرحبا بالعالم English שלום", "中文 日本語 한글", "café ffi AV", "", "first\tsecond"] {
            for style in 0..<9 {
                let line = line(text, style: style)
                for scale in [CGFloat(1), 2, 3] {
                    for flipped in [false, true] {
                        for reset in [false, true] {
                            let old = draw([line], scale: scale, flipped: flipped, resetPosition: reset, limit: nil, legacy: true)
                            let new = draw([line], scale: scale, flipped: flipped, resetPosition: reset, limit: nil, legacy: false)
                            XCTAssertEqual(old.0, new.0, "\(text) style \(style), scale \(scale), flipped \(flipped), reset \(reset)")
                            XCTAssertEqual(old.1, new.1)
                            XCTAssertEqual(old.2, new.2)
                            XCTAssertEqual(old.3, new.3)
                        }
                    }
                }
            }
        }
    }

    func testPartialGlyphDrawingMatchesAcrossRunsAndLines() {
        let lines = [line("Start 🦆 مرحبا", style: 1), line("café ffi second", style: 2), line("中文 last", style: 6)]
        let count = lines.reduce(0) { $0 + CTLineGetGlyphCount($1) }
        for limit in -1...count + 2 {
            for scale in [CGFloat(1), 2, 3] {
                let old = draw(lines, scale: scale, flipped: true, resetPosition: true, limit: limit, legacy: true)
                let new = draw(lines, scale: scale, flipped: true, resetPosition: true, limit: limit, legacy: false)
                XCTAssertEqual(old.0, new.0, "limit \(limit), scale \(scale)")
                XCTAssertEqual(old.1, new.1)
                XCTAssertEqual(old.2, new.2)
            }
        }
    }

    func testRunsStayAliveWhenDrawingTemporaryLinesRepeatedly() {
        for index in 0..<1000 {
            autoreleasepool {
                let context = CGContext(data: nil, width: 400, height: 80, bitsPerComponent: 8, bytesPerRow: 1600, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                var count = 0
                drawTextLineRuns(line("\(index) 👩🏽‍💻 שלום", style: index % 9), in: context, at: CGPoint(x: 5, y: 30), drawnGlyphCount: &count)
                XCTAssertEqual(count, 0)
                XCTAssertTrue(Data(bytes: context.data!, count: 128000).contains { $0 != 0 })
            }
        }
    }
    func testAlternatingRendererBenchmark() throws {
        guard ProcessInfo.processInfo.environment["TEXT_RUN_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        var results: [[String: Any]] = []
        for runCount in [1, 4, 16, 64] {
            let value = NSMutableAttributedString(string: String(repeating: "abc ", count: runCount), attributes: [.font: NSFont.systemFont(ofSize: 14)])
            for index in 0..<runCount {
                value.addAttribute(.foregroundColor, value: index % 2 == 0 ? NSColor.red : NSColor.blue, range: NSRange(location: index * 4, length: 4))
            }
            let line = CTLineCreateWithAttributedString(value)
            let context = CGContext(data: nil, width: 1200, height: 100, bitsPerComponent: 8, bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            func measure(_ legacy: Bool) -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<2000 {
                    var count = 0
                    if legacy { legacyDrawTextLineRuns(line, in: context, at: CGPoint(x: 10, y: 30), drawnGlyphCount: &count) }
                    else { drawTextLineRuns(line, in: context, at: CGPoint(x: 10, y: 30), drawnGlyphCount: &count) }
                }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / 2000
            }
            var old: [Double] = [], new: [Double] = []
            for i in 0..<9 {
                if i % 2 == 0 { old.append(measure(true)); new.append(measure(false)) }
                else { new.append(measure(false)); old.append(measure(true)) }
            }
            results.append(["runs": runCount, "baseline_ns": old.sorted()[4], "candidate_ns": new.sorted()[4], "baseline_trials_ns": old, "candidate_trials_ns": new])
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/text-run-alternating.json"))
    }
}
