import XCTest
import Production
import Baseline

final class SpoilerTests: XCTestCase {
    func testEveryValidUTF16RangeMatchesOriginal() {
        let strings = ["", "secret 123-456", "Привет мир", "漢字かな", "👨‍👩‍👧‍👦🦊🇦🇪", "e\u{301}o\u{308}", "a\n\t\0b", "مرحبا بالعالم", String(repeating: "abc🙂", count: 10)]
        for text in strings {
            for start in 0 ... text.utf16.count {
                for length in 0 ... text.utf16.count - start {
                    let range = NSRange(location: start, length: length)
                    let current = text.spoiler(range)
                    let original = text.legacySpoiler(range)
                    XCTAssertEqual(current, original, "\(text.debugDescription) \(range)")
                    XCTAssertEqual(Array(current.utf16), Array(original.utf16))
                }
            }
        }
    }

    func testEveryUTF16CodeUnitRetainsOriginalMaskMapping() {
        let bmp = (0 ... 0xffff).compactMap { UnicodeScalar($0) }
        let supplementary = (0 ..< 1024).compactMap { UnicodeScalar(0x10000 + $0 * 1024 + $0) }
        let text = String(String.UnicodeScalarView(bmp + supplementary))
        let range = NSRange(location: 0, length: text.utf16.count)
        XCTAssertEqual(Array(text.spoiler(range).utf16), Array(text.legacySpoiler(range).utf16))
    }

    func testInvalidRangesAreSafeAndPartialRangesMaskAvailableText() {
        let text = "secret"
        for range in [NSRange(location: NSNotFound, length: 1), NSRange(location: .max, length: .max), NSRange(location: -1, length: 2), NSRange(location: 0, length: -1), NSRange(location: 6, length: 1), NSRange(location: 7, length: 0)] {
            XCTAssertEqual(text.spoiler(range), text)
        }
        XCTAssertEqual(text.spoiler(NSRange(location: 2, length: .max)), text.legacySpoiler(NSRange(location: 2, length: 4)))
        XCTAssertEqual("".spoiler(NSRange(location: 0, length: .max)), "")
        XCTAssertEqual(text.spoiler(NSRange(location: 0, length: .max)), text.legacySpoiler(NSRange(location: 0, length: 6)))
    }

    func testConcurrentSpoilersAndIndependentFormatters() {
        let text = "Привет 👨‍👩‍👧‍👦 secret"
        let range = NSRange(location: 0, length: text.utf16.count)
        let expected = text.legacySpoiler(range)
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for _ in 0 ..< 300 {
                XCTAssertEqual(text.spoiler(range), expected)
                let formatter = makeNewDateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = worker % 2 == 0 ? "yyyy" : "MM"
                XCTAssertEqual(formatter.string(from: Date(timeIntervalSince1970: 0)), worker % 2 == 0 ? "1970" : "01")
            }
        }
    }
}
