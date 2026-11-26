import Cocoa
import XCTest
@testable import TGUIKit

extension LayerTests {
    func selectionLayout(_ kind: Int, width: CGFloat = 230) -> TextViewLayout {
        let ltr = "A paragraph with words and a second sentence.\n"
        let rtl = "مرحبا بالعالم שלום עולם\n"
        let value = NSMutableAttributedString(string: (0..<14).map { kind == 2 || (kind == 3 && $0 % 2 == 0) ? rtl : ltr }.joined(separator: "\n"), attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        if kind > 0 {
            let source = value.string as NSString
            var location = 0
            for index in 0..<14 {
                let range = source.lineRange(for: NSRange(location: location, length: 0))
                let quote = TextViewBlockQuoteData(id: index, colors: .init(main: .blue, secondary: nil, tertiary: nil), isCode: kind == 4)
                value.addAttribute(TextInputAttributes.quote, value: quote, range: range)
                location = range.max + 1
            }
        }
        let result = TextViewLayout(value, maximumNumberOfLines: 0)
        result.measure(width: width)
        return result
    }

    func testSelectionTraversalAgainstPreviousRenderer() {
        let old = PreviousTextRenderer(), new = TextView()
        let selections = [NSRange(location: NSNotFound, length: 0), NSRange(location: 0, length: 0), NSRange(location: 0, length: 8), NSRange(location: 20, length: 70), NSRange(location: 150, length: 50)]
        for kind in 0..<5 {
            for scale in [CGFloat(1), 2, 3] {
                System.updateScaleFactor(scale)
                for primary in selections {
                    for additional in [[], [selections[0]], [selections[2]], [selections[4], selections[3], selections[2]]] {
                        for selectable in [false, true] {
                            for view in [old as TextView, new] {
                                let value = selectionLayout(kind)
                                XCTAssertLessThan((value.layoutSize.height + 16) * scale, 4000)
                                XCTAssertLessThan((value.layoutSize.width + 16) * scale, 1000)
                                if kind > 0 { XCTAssertEqual(value.blockQuotes.count, 14) }
                                value.selectedRange = TextSelectedRange(range: primary, color: .yellow)
                                value.additionalSelections = additional.map { TextSelectedRange(range: $0, color: .green) }
                                view.isSelectable = selectable
                                view.update(nil)
                                view.update(value)
                                view.layout()
                            }
                            let before = selectionPixels(scale: scale) { old.draw(old.drawingLayer, in: $0) }
                            let after = selectionPixels(scale: scale) { new.draw(new.drawingLayer, in: $0) }
                            XCTAssertTrue(before == after, "kind=\(kind), scale=\(scale), primary=\(primary), additional=\(additional), selectable=\(selectable)")
                            XCTAssertTrue(before.contains { $0 != 0 })
                        }
                    }
                }
            }
        }
    }

    func selectionPixels(scale: CGFloat, _ draw: (CGContext) -> Void) -> Data {
        let context = CGContext(data: nil, width: 1000, height: 4000, bitsPerComponent: 8, bytesPerRow: 4000, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 8, y: 8)
        draw(context)
        return Data(bytes: context.data!, count: 16000000)
    }

    func testSelectionWorkBenchmark() throws {
        guard ProcessInfo.processInfo.environment["SELECTION_WORK_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        var results: [[String: Any]] = []
        for scenario in ["plain_short", "plain_long", "many_quotes_ltr", "many_quotes_rtl", "selected_tail", "additional_selections"] {
            let old = PreviousTextRenderer(), new = TextView()
            for view in [old as TextView, new] {
                let value = scenario == "plain_short" ? headerlessShortLayout() : selectionLayout(scenario == "many_quotes_ltr" ? 1 : scenario == "many_quotes_rtl" ? 2 : 0)
                XCTAssertLessThanOrEqual((value.layoutSize.height + 6) * 2, 2000)
                XCTAssertLessThanOrEqual((value.layoutSize.width + 4) * 2, 600)
                if scenario == "selected_tail" {
                    value.selectedRange = TextSelectedRange(range: NSRange(location: value.attributedString.length - 15, length: 10), color: .yellow)
                } else if scenario == "additional_selections" {
                    value.additionalSelections = (0..<12).map { TextSelectedRange(range: NSRange(location: $0 * 30, length: 10), color: .yellow) }
                }
                view.update(value)
                view.layout()
            }
            let context = CGContext(data: nil, width: 600, height: 2000, bitsPerComponent: 8, bytesPerRow: 2400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.scaleBy(x: 2, y: 2)
            let count = 1000
            func run(_ candidate: Bool) -> Double {
                let start = CACurrentMediaTime()
                if candidate { for _ in 0..<count { new.draw(new.drawingLayer, in: context) } }
                else { for _ in 0..<count { old.draw(old.drawingLayer, in: context) } }
                return (CACurrentMediaTime() - start) * 1_000_000 / Double(count)
            }
            _ = run(false); _ = run(true)
            var before: [Double] = [], after: [Double] = []
            for batch in 0..<9 {
                if batch % 2 == 0 { before.append(run(false)); after.append(run(true)) }
                else { after.append(run(true)); before.append(run(false)) }
            }
            results.append(["scenario": scenario, "baseline_us": before.sorted()[4], "candidate_us": after.sorted()[4], "baseline_trials_us": before, "candidate_trials_us": after])
        }
        let data = try JSONSerialization.data(withJSONObject: ["baseline": "f23a0ca31", "batches": 9, "iterations_per_batch": 1000, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/selection-work-benchmark.json"))
    }

    func headerlessShortLayout() -> TextViewLayout {
        let value = TextViewLayout(NSAttributedString(string: "Message preview", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black]))
        value.measure(width: 200)
        return value
    }
}
