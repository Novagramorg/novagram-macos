import Cocoa
import XCTest
import class TGUIKit.TextViewLayout
import struct TGUIKit.TextViewCutout
import class TGUIKitBaseline.TextViewLayout
import struct TGUIKitBaseline.TextViewCutout

final class QuoteMeasureTests: XCTestCase {
    override func setUp() { MeasureBootstrap.install() }

    func testEveryQuotePatternAndRangeMatchesEnumeration() {
        for value in 0..<1024 {
            let pattern = (0..<5).map { (value >> ($0 * 2)) & 3 }
            let layout = TGUIKit.TextViewLayout(TGUIKit.TextViewLayout.quoteFixture("abcde", pattern: pattern))
            for start in 0..<5 {
                for length in 1...(5 - start) {
                    let result = layout.quoteLookupIDs(NSRange(location: start, length: length))
                    XCTAssertEqual(result[0], result[1], "\(pattern), \(start), \(length)")
                }
            }
        }
    }

    func compare(_ text: String, pattern: [Int], decorated: Bool, width: CGFloat, limit: Int32 = 0, alignment: NSTextAlignment = .left, pixels: Bool = false, cutout: Bool = false) {
        let old = TGUIKitBaseline.TextViewLayout(TGUIKitBaseline.TextViewLayout.quoteFixture(text, pattern: pattern, decorated: decorated), maximumNumberOfLines: limit, cutout: cutout ? TGUIKitBaseline.TextViewCutout(topLeft: CGSize(width: 20, height: 30), bottomRight: CGSize(width: 15, height: 20)) : nil, alignment: alignment)
        let new = TGUIKit.TextViewLayout(TGUIKit.TextViewLayout.quoteFixture(text, pattern: pattern, decorated: decorated), maximumNumberOfLines: limit, cutout: cutout ? TGUIKit.TextViewCutout(topLeft: CGSize(width: 20, height: 30), bottomRight: CGSize(width: 15, height: 20)) : nil, alignment: alignment)
        for step in 0..<2 {
            old.measure(width: width + CGFloat(step * 11))
            new.measure(width: width + CGFloat(step * 11))
            XCTAssertEqual(old.quoteMeasurementSnapshot(), new.quoteMeasurementSnapshot(), "\(text), \(pattern), \(width), \(limit), \(alignment.rawValue), \(step)")
            if pixels {
                for scale in [1, 2] {
                    let expected = old.quotePixels(scale: scale)
                    XCTAssertEqual(expected, new.quotePixels(scale: scale))
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { XCTAssertTrue(expected.contains { $0 != 0 }) }
                }
            }
        }
    }

    func testCompleteMeasurementAndRasterParity() {
        let texts = ["", "plain text", "abc\ndef\nghi\n", "مرحبا שלום world 123", "👨‍👩‍👧‍👦 e\u{301} 日本語", String(repeating: "one two three four ", count: 12)]
        let patterns = [[], [1], [2], [0, 1, 0, 2, 0, 0, 0], [1, 3, 0, 0], [2, 0, 0, 3, 1, 0]]
        for (textIndex, text) in texts.enumerated() {
            for (patternIndex, pattern) in patterns.enumerated() {
                for width: CGFloat in [40, 120, 300] {
                    for limit: Int32 in [0, 1, 3] {
                        for alignment: NSTextAlignment in [.left, .center, .right] {
                            compare(text, pattern: pattern, decorated: patternIndex % 2 == 1, width: width, limit: limit, alignment: alignment, pixels: width == 120 && limit == 0 && alignment == .left, cutout: textIndex % 2 == 1)
                        }
                    }
                }
            }
        }
    }

    func testRandomizedQuoteBoundaries() {
        var seed: UInt64 = 0x1345789
        func next(_ bound: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 32) % UInt64(bound)) }
        let words = ["hello", "שלום", "مرحبا", "👨‍👩‍👧‍👦", "日本語", "e\u{301}", "\n", "\t"]
        for index in 0..<256 {
            let text = (0..<(1 + next(15))).map { _ in words[next(words.count)] }.joined(separator: " ")
            let pattern = (0..<(1 + next(20))).map { _ in next(4) }
            compare(text, pattern: pattern, decorated: index % 3 == 0, width: CGFloat(50 + next(250)), limit: [0, 1, 2, 3][next(4)], alignment: [.left, .center, .right][next(3)], pixels: index < 16, cutout: index % 2 == 0)
        }
    }

    func testMutableSourcesInvalidatePreparedLayouts() {
        let text = String(repeating: "word hello world ", count: 12)
        let oldSource = TGUIKitBaseline.TextViewLayout.quoteFixture(text, pattern: [])
        let newSource = TGUIKit.TextViewLayout.quoteFixture(text, pattern: [])
        let old = TGUIKitBaseline.TextViewLayout(oldSource)
        let new = TGUIKit.TextViewLayout(newSource)
        for step in 0..<24 {
            let pattern = step % 3 == 0 ? [] : step % 3 == 1 ? [1, 0, 2, 0] : [2, 3, 0]
            oldSource.setAttributedString(TGUIKitBaseline.TextViewLayout.quoteFixture(text, pattern: pattern, decorated: step % 2 == 0))
            newSource.setAttributedString(TGUIKit.TextViewLayout.quoteFixture(text, pattern: pattern, decorated: step % 2 == 0))
            old.measure(width: CGFloat(120 + step))
            new.measure(width: CGFloat(120 + step))
            XCTAssertEqual(old.quoteMeasurementSnapshot(), new.quoteMeasurementSnapshot())
            XCTAssertEqual(old.quotePixels(scale: 2), new.quotePixels(scale: 2))
        }
    }
    func testIndependentConcurrentMeasurements() {
        let text = String(repeating: "hello مرحبا 日本語 ", count: 8)
        let patterns = [[], [1], [2], [1, 0, 2, 0, 3, 0]]
        let expected = patterns.map { pattern -> [Double] in
            let layout = TGUIKitBaseline.TextViewLayout(TGUIKitBaseline.TextViewLayout.quoteFixture(text, pattern: pattern), maximumNumberOfLines: 0)
            layout.measure(width: 160)
            return layout.quoteMeasurementSnapshot()
        }
        let lock = NSLock()
        var mismatches = 0
        DispatchQueue.concurrentPerform(iterations: 256) { index in
            let layout = TGUIKit.TextViewLayout(TGUIKit.TextViewLayout.quoteFixture(text, pattern: patterns[index % patterns.count]), maximumNumberOfLines: 0)
            layout.measure(width: 160)
            if layout.quoteMeasurementSnapshot() != expected[index % patterns.count] {
                lock.lock()
                mismatches += 1
                lock.unlock()
            }
        }
        XCTAssertEqual(mismatches, 0)
    }

}
