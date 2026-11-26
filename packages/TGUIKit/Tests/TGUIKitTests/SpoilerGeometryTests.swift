import XCTest
import Cocoa
@testable import TGUIKit

final class SpoilerGeometryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func fixture(_ text: String, ranges: [NSRange], width: CGFloat = 220, revealed: Bool = false, alignment: NSTextAlignment = .left, cutout: TextViewCutout? = nil, maximumLines: Int32 = .max) -> (TextViewLayout, [TextViewLayout.Spoiler]) {
        let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        for range in ranges { value.addAttribute(TextInputAttributes.spoiler, value: true, range: range) }
        let layout = TextViewLayout(value, maximumNumberOfLines: maximumLines, cutout: cutout, alignment: alignment, spoilerColor: .blue, isSpoilerRevealed: revealed)
        layout.measure(width: width)
        var spoilers: [TextViewLayout.Spoiler] = []
        value.enumerateAttribute(TextInputAttributes.spoiler, in: value.range) { value, range, _ in
            if value != nil { spoilers.append(.init(range: range, color: .blue, isRevealed: revealed)) }
        }
        return (layout, spoilers)
    }

    private func assertMatches(_ value: (TextViewLayout, [TextViewLayout.Spoiler]), file: StaticString = #filePath, line: UInt = #line) {
        for checkRevealed in [false, true] {
            let old = value.0.legacySpoilerRects(value.1, checkRevealed)
            let new = value.0.spoilerRects(checkRevealed)
            XCTAssertEqual(old.count, new.count, file: file, line: line)
            XCTAssertEqual(value.0.spoilerRectFrames(checkRevealed), old.map { $0.0 }, file: file, line: line)
            for (a, b) in zip(old, new) {
                XCTAssertEqual(a.0, b.0, file: file, line: line)
                XCTAssertEqual(a.1.range, b.1.range, file: file, line: line)
                XCTAssertEqual(a.1.color, b.1.color, file: file, line: line)
                XCTAssertEqual(a.1.isRevealed, b.1.isRevealed, file: file, line: line)
            }
        }
    }

    func testSelectionBoundariesWrappingAndMultipleScriptsMatchBaseline() {
        for text in ["One hidden paragraph with wrapping words and text", "مرحبا بالعالم שלום English 👨‍👩‍👧‍👦 café 中文", "a\n\nb\nc", ""] {
            let length = text.utf16.count
            let ranges = length == 0 ? [] : [NSRange(location: 0, length: length)]
            for width in [CGFloat(40), 120, 350] {
                let value = fixture(text, ranges: ranges, width: width)
                assertMatches(value)
                for start in 0...length {
                    for end in [start, min(start + 3, length), length] {
                        value.0.selectedRange.range = NSRange(location: start, length: end - start)
                        assertMatches(value)
                    }
                }
            }
        }
    }

    func testSeededRangesAndSelectionsMatchBaseline() {
        var seed: UInt64 = 0x5A01E2
        func random(_ limit: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(limit))
        }
        let text = String(repeating: "abc 👩🏽‍💻 שלום العربية 中文 café\n", count: 30)
        let length = text.utf16.count
        for index in 0..<1200 {
            let count = [0, 1, 4, 8, 9, 16, 64][index % 7]
            var ranges: [NSRange] = []
            for _ in 0..<count {
                let start = random(length)
                ranges.append(NSRange(location: start, length: 1 + random(min(60, length - start))))
            }
            let value = fixture(text, ranges: ranges, width: CGFloat(40 + random(400)), revealed: index % 3 == 0, alignment: [NSTextAlignment.left, .center, .right][index % 3], cutout: index % 4 == 0 ? TextViewCutout(topLeft: NSSize(width: 20, height: 40)) : nil, maximumLines: index % 5 == 0 ? 3 : .max)
            if index % 2 == 0 {
                let start = random(length)
                value.0.selectedRange.range = NSRange(location: start, length: random(length - start + 1))
            }
            assertMatches(value)
        }
    }

    func testLineOrderAndMutableGeometryDoNotRequireAnOrderedLayout() {
        let text = String(repeating: "hidden visible\n", count: 50)
        let ranges = stride(from: 0, to: text.utf16.count, by: 15).map { NSRange(location: $0, length: 6) }
        let value = fixture(text, ranges: ranges)
        value.0.lines.reverse()
        assertMatches(value)
        for (index, line) in value.0.lines.enumerated() {
            line.frame.origin.x += CGFloat(index % 7) * 0.25
            line.frame.origin.y -= CGFloat(index % 3) * 0.5
        }
        assertMatches(value)
        value.0.measure(width: 100)
        assertMatches(value)
        value.0.setAttributedString(NSAttributedString(string: "short", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
        value.0.measure(width: 80)
        assertMatches(value)
        value.0.lines.removeAll()
        assertMatches(value)
    }

    func testRevealModeAndHitTestingRetainSpoilerIdentity() {
        let value = fixture("visible hidden visible hidden", ranges: [NSRange(location: 8, length: 6), NSRange(location: 23, length: 6)])
        let hidden = value.0.spoilerRects()
        XCTAssertFalse(hidden.isEmpty)
        for (rect, spoiler) in hidden where rect.width > 0 {
            XCTAssertTrue(value.0.spoiler(at: NSPoint(x: rect.midX, y: rect.midY)) === spoiler)
        }
        for (a, b) in zip(hidden, value.0.spoilerRects()) { XCTAssertTrue(a.1 === b.1) }
        value.0.revealSpoiler()
        XCTAssertTrue(value.0.spoilerRects().isEmpty)
        let revealed = value.1.map { TextViewLayout.Spoiler(range: $0.range, color: $0.color, isRevealed: true) }
        assertMatches((value.0, revealed))
        for (a, b) in zip(hidden, value.0.spoilerRects(false)) {
            XCTAssertEqual(a.0, b.0)
            XCTAssertTrue(a.1 === b.1)
        }
    }

    func testEarlyHitTestingMatchesBaselineAtEdgesAndSelectionGaps() {
        let text = String(repeating: "hidden visible ", count: 64)
        let ranges = stride(from: 0, to: text.utf16.count, by: 15).map { NSRange(location: $0, length: 6) }
        for revealed in [false, true] {
            let value = fixture(text, ranges: ranges, revealed: revealed)
            for selection in [NSRange(location: NSNotFound, length: 0), NSRange(location: 2, length: 35), NSRange(location: 0, length: text.utf16.count)] {
                value.0.selectedRange.range = selection
                let expected = value.0.legacySpoilerRects(value.1)
                for (rect, _) in value.0.legacySpoilerRects(value.1, false) {
                    for point in [NSPoint(x: rect.midX, y: rect.midY), rect.origin, NSPoint(x: rect.maxX, y: rect.maxY), NSPoint(x: rect.minX - 0.01, y: rect.midY), NSPoint(x: rect.maxX + 0.01, y: rect.midY)] {
                        let old = expected.first { $0.0.contains(point) && !$0.1.isRevealed }?.1
                        let new = value.0.spoiler(at: point)
                        XCTAssertEqual(old?.range, new?.range)
                        XCTAssertEqual(old?.color, new?.color)
                    }
                }
                XCTAssertNil(value.0.spoiler(at: NSPoint(x: -100, y: -100)))
            }
        }
    }

    func testAlternatingGeometryBenchmark() throws {
        guard ProcessInfo.processInfo.environment["SPOILER_GEOMETRY_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        var results: [[String: Any]] = []
        var checksum: CGFloat = 0
        for count in [1, 8, 64, 256] {
            let text = String(repeating: "hidden visible ", count: count)
            let ranges = stride(from: 0, to: text.utf16.count, by: 15).map { NSRange(location: $0, length: 6) }
            for revealed in [false, true] {
                let value = fixture(text, ranges: ranges, revealed: revealed)
                assertMatches(value)
                let first = value.0.legacySpoilerRects(value.1, false).first!.0
                let hit = NSPoint(x: first.midX, y: first.midY)
                for scenario in ["frames", "first_hit", "miss"] {
                    func measure(_ legacy: Bool) -> Double {
                        let start = DispatchTime.now().uptimeNanoseconds
                        for _ in 0..<1000 {
                            if scenario == "frames" {
                                let rects = legacy ? value.0.legacySpoilerRects(value.1).map { $0.0 } : value.0.spoilerRectFrames()
                                checksum += CGFloat(rects.count) + (rects.first?.width ?? 0)
                            } else {
                                let point = scenario == "first_hit" ? hit : NSPoint(x: -100, y: -100)
                                let spoiler = legacy ? value.0.legacySpoilerRects(value.1).first { $0.0.contains(point) && !$0.1.isRevealed }?.1 : value.0.spoiler(at: point)
                                checksum += CGFloat(spoiler?.range.length ?? 0)
                            }
                        }
                        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1000
                    }
                    var old: [Double] = [], new: [Double] = []
                    for i in 0..<9 {
                        if i % 2 == 0 { old.append(measure(true)); new.append(measure(false)) }
                        else { new.append(measure(false)); old.append(measure(true)) }
                    }
                    results.append(["scenario": scenario, "spoilers": value.1.count, "lines": value.0.lines.count, "revealed": revealed, "baseline_ns": old.sorted()[4], "candidate_ns": new.sorted()[4], "baseline_trials_ns": old, "candidate_trials_ns": new])
                }
            }
        }
        XCTAssertGreaterThan(checksum, 0)
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/spoiler-geometry-benchmark.json"))
    }
}
