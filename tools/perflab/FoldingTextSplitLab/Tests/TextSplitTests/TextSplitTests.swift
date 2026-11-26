import Foundation
import AppKit
import XCTest
@testable import TextSplit

private final class Quote: NSObject {
    override func isEqual(_ object: Any?) -> Bool { (object as AnyObject?) === self }
}

private final class CountingString: NSAttributedString {
    let value: NSAttributedString
    var substrings = 0
    override var string: String { value.string }
    override var length: Int { value.length }
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        value.attributes(at: location, effectiveRange: range)
    }
    override func attributedSubstring(from range: NSRange) -> NSAttributedString {
        substrings += 1
        return value.attributedSubstring(from: range)
    }
    init(_ value: NSAttributedString) {
        self.value = value
        super.init()
    }
    required init?(coder: NSCoder) { fatalError() }
    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) { fatalError() }
}

final class TextSplitTests: XCTestCase {
    private let quote = TextInputAttributes.quote
    private let style = NSAttributedString.Key("test.style")

    private func verify(_ text: NSAttributedString, file: StaticString = #filePath, line: UInt = #line) {
        let before = ReferenceSplit.breakString(text), after = CurrentSplit.breakString(text)
        XCTAssertEqual(before, after, file: file, line: line)
        XCTAssertEqual(before.map { text.attributedSubstring(from: $0) }, after.map { text.attributedSubstring(from: $0) }, file: file, line: line)
        for range in after {
            XCTAssertGreaterThan(range.length, 0, file: file, line: line)
            XCTAssertGreaterThanOrEqual(range.location, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(NSMaxRange(range), text.length, file: file, line: line)
        }
    }

    func testPlainUnicodeAndLeadingNewlineRules() {
        let cases = ["", "\n", "\n\n", "plain", "\nplain", "\r\nplain", "\n\u{0301}x", "é", "e\u{0301}", "👩🏽‍🚀", "🇺🇦", "עברית العربية", "\u{2028}line", "\u{0085}line", "\u{200D}\n", "\n\0x"]
        for text in cases { verify(NSAttributedString(string: text)) }
        XCTAssertEqual(CurrentSplit.breakString(NSAttributedString(string: "\n\nabc")), [NSRange(location: 1, length: 4)])
        XCTAssertEqual(CurrentSplit.breakString(NSAttributedString(string: "\r\nabc")), [NSRange(location: 0, length: 5)])
    }

    func testQuoteBoundariesAndFinalQuoteNewlineMatchExistingBehavior() {
        let mixed = NSMutableAttributedString(string: "\nabc\nquote\nend")
        mixed.addAttribute(quote, value: Quote(), range: NSRange(location: 5, length: 5))
        verify(mixed)
        XCTAssertEqual(CurrentSplit.breakString(mixed), [NSRange(location: 1, length: 4), NSRange(location: 5, length: 5), NSRange(location: 11, length: 3)])
        let full = NSAttributedString(string: "\nquote", attributes: [quote: Quote()])
        verify(full)
        XCTAssertEqual(CurrentSplit.breakString(full), [NSRange(location: 1, length: 5)])
        let prefix = NSMutableAttributedString(string: "\nQ\nplain")
        prefix.addAttribute(quote, value: Quote(), range: NSRange(location: 0, length: 2))
        verify(prefix)
        XCTAssertEqual(CurrentSplit.breakString(prefix), [NSRange(location: 0, length: 2), NSRange(location: 3, length: 5)])
    }

    func testOtherAttributesAndQuoteIdentityChangesDoNotSplitBlocks() {
        let text = NSMutableAttributedString(string: String(repeating: "a", count: 1000))
        for index in 0..<text.length {
            text.addAttribute(style, value: index % 5, range: NSRange(location: index, length: 1))
        }
        text.addAttribute(quote, value: Quote(), range: NSRange(location: 100, length: 200))
        text.addAttribute(quote, value: Quote(), range: NSRange(location: 300, length: 200))
        text.addAttribute(quote, value: NSNumber(value: false), range: NSRange(location: 500, length: 100))
        verify(text)
        XCTAssertEqual(CurrentSplit.breakString(text), [NSRange(location: 0, length: 100), NSRange(location: 100, length: 500), NSRange(location: 600, length: 400)])
    }

    func testEveryUTF16QuoteBoundaryInUnicodeText() {
        for string in ["\n👩🏽‍🚀e\u{0301}\r\n🇺🇦x", "\nעברית العربية\n", "\n\u{2028}a\u{0085}\0"] {
            let length = (string as NSString).length
            for start in 0...length {
                for end in start...length {
                    let text = NSMutableAttributedString(string: string)
                    if end > start { text.addAttribute(quote, value: Quote(), range: NSRange(location: start, length: end - start)) }
                    verify(text)
                }
            }
        }
    }

    func testSeededOverlappingAttributesMatchReference() {
        var random: UInt64 = 0x261016
        func next(_ bound: Int) -> Int {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            return Int((random >> 32) % UInt64(bound))
        }
        let tokens = ["a", "é", "e\u{0301}", "👩🏽‍🚀", "🇺🇦", "א", "中", "\n", "\r\n", "\u{2028}", "\t", " "]
        for _ in 0..<2500 {
            let string = (0..<next(150)).map { _ in tokens[next(tokens.count)] }.joined()
            let text = NSMutableAttributedString(string: string)
            if text.length > 0 {
                for index in 0..<next(35) {
                    let start = next(text.length)
                    let range = NSRange(location: start, length: next(text.length - start) + 1)
                    if index % 3 == 0 { text.addAttribute(quote, value: Quote(), range: range) }
                    else if index % 3 == 1 { text.removeAttribute(quote, range: range) }
                    else { text.addAttribute(style, value: next(8), range: range) }
                }
            }
            verify(text)
        }
    }

    func testSplitDoesNotConstructTemporaryAttributedSubstrings() {
        let value = NSMutableAttributedString(string: "\nfirst\nquote\nlast")
        value.addAttribute(quote, value: Quote(), range: NSRange(location: 7, length: 5))
        let text = CountingString(value)
        XCTAssertEqual(text.length, value.length)
        let before = ReferenceSplit.breakString(text)
        XCTAssertGreaterThan(text.substrings, 0)
        text.substrings = 0
        let after = CurrentSplit.breakString(text)
        XCTAssertEqual(before, after)
        XCTAssertEqual(text.substrings, 0)
    }

    func testMutatedInputIsReevaluatedWithoutRetainedState() {
        let text = NSMutableAttributedString(string: "\ntext\nquote")
        for index in 0..<40 {
            text.addAttribute(quote, value: Quote(), range: NSRange(location: index % text.length, length: 1))
            verify(text)
            text.replaceCharacters(in: NSRange(location: 0, length: 1), with: index % 2 == 0 ? "x" : "\n")
            verify(text)
        }
    }

    func testSplitBenchmark() throws {
        guard ProcessInfo.processInfo.environment["FOLDING_SPLIT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        var cases: [(String, NSAttributedString)] = []
        cases.append(("short_plain", NSAttributedString(string: "A short chat message")))
        cases.append(("long_plain", NSAttributedString(string: String(repeating: "message 👩🏽‍🚀 text ", count: 250))))
        let styled = NSMutableAttributedString(string: String(repeating: "x", count: 4096))
        for index in 0..<512 { styled.addAttribute(style, value: index % 7, range: NSRange(location: index * 8, length: 8)) }
        cases.append(("styled_plain", styled))
        let quoted = NSMutableAttributedString(string: String(repeating: "\nquote text and ordinary message ", count: 200))
        for index in stride(from: 0, to: quoted.length - 32, by: 64) { quoted.addAttribute(quote, value: Quote(), range: NSRange(location: index, length: 32)) }
        cases.append(("many_quotes", quoted))
        let dense = NSMutableAttributedString(attributedString: quoted)
        for index in stride(from: 0, to: dense.length - 4, by: 4) { dense.addAttribute(style, value: index % 7, range: NSRange(location: index, length: 4)) }
        cases.append(("styled_quotes", dense))
        var results: [[String: Any]] = [], checksum = 0
        let iterations = 500
        for (name, text) in cases {
            verify(text)
            var before: [Double] = [], after: [Double] = []
            func measure(_ baseline: Bool) -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<iterations {
                    autoreleasepool {
                        let result = baseline ? ReferenceSplit.breakString(text) : CurrentSplit.breakString(text)
                        checksum += result.count
                    }
                }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations) / 1000
            }
            _ = measure(true); _ = measure(false)
            for batch in 0..<9 {
                if batch % 2 == 0 { before.append(measure(true)); after.append(measure(false)) }
                else { after.append(measure(false)); before.append(measure(true)) }
            }
            results.append(["scenario": name, "utf16_length": text.length, "baseline_us": before.sorted()[4], "candidate_us": after.sorted()[4], "baseline_trials_us": before, "candidate_trials_us": after])
        }
        XCTAssertGreaterThan(checksum, 0)
        let data = try JSONSerialization.data(withJSONObject: ["batches": 9, "iterations_per_batch": iterations, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/folding-text-split-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
