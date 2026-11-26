import Cocoa

_ = NSApplication.shared
let normal = NSFont.systemFont(ofSize: 14)
let combined = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14, weight: .medium), toHaveTrait: .italicFontMask)
let text = String(repeating: "Hello 👨‍👩‍👧‍👦 café مرحبا 日本語\n", count: 80)
let length = (text as NSString).length
let original = NSMutableAttributedString(string: text, attributes: [.font: normal, .foregroundColor: NSColor.red])
original.addAttribute(.underlineStyle, value: 1, range: NSRange(location: 5, length: 50))
original.addAttribute(.link, value: "https://example.com", range: NSRange(location: 20, length: 70))
original.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), range: NSRange(location: 15, length: 100))
typealias ApplyRanges = ([NSRange], [NSRange], (NSRange) -> Void) -> Void

func formatted(_ bold: [NSRange], _ italic: [NSRange], using apply: ApplyRanges) -> NSAttributedString {
    let string = NSMutableAttributedString(attributedString: original)
    apply(bold, italic) { range in string.addAttribute(.font, value: combined, range: range) }
    return string
}
var state: UInt64 = 0x12345678
func random(_ limit: Int) -> Int {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return Int((state >> 32) % UInt64(limit))
}
func ranges(_ count: Int) -> [NSRange] {
    (0..<count).map { _ in
        let start = random(length + 1)
        return NSRange(location: start, length: random(length - start + 1))
    }
}
var comparisons = 0
func check(_ bold: [NSRange], _ italic: [NSRange]) {
    let baseline = formatted(bold, italic, using: referenceForEachBoldItalicRange)
    let candidate = formatted(bold, italic, using: chatForEachBoldItalicRange)
    precondition(baseline.isEqual(to: candidate), "Mismatch: \(bold), \(italic)")
    comparisons += 1
}
for b in [0, 1, 2, 8, 9, 16, 17, 32, 80] {
    for i in [0, 1, 2, 8, 9, 16, 17, 32, 80] {
        for _ in 0..<20 { check(ranges(b), ranges(i)) }
    }
}
for count in [1, 8, 9, 32, 128] {
    let adjacent = (0..<count).map { NSRange(location: $0 * 4, length: 4) }
    let nested = (0..<count).map { NSRange(location: $0, length: 512 - $0 * 2) }
    let duplicated = Array(repeating: NSRange(location: 0, length: 512), count: count)
    let zero = Array(repeating: NSRange(location: 20, length: 0), count: count)
    for bold in [adjacent, nested, duplicated, zero] {
        for italic in [adjacent, nested, duplicated, zero] { check(bold, italic) }
    }
}
print("Passed \(comparisons) exact attributed-string comparisons")

if CommandLine.arguments.contains("--benchmark") {
    var results: [[String: Any]] = []
    var checksum = 0
    func measure(_ bold: [NSRange], _ italic: [NSRange], iterations: Int, apply: ApplyRanges) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            autoreleasepool {
                checksum &+= formatted(bold, italic, using: apply).length
            }
        }
        return (CFAbsoluteTimeGetCurrent() - start) * 1_000_000 / Double(iterations)
    }
    for count in [0, 1, 8, 16, 32, 128, 512] {
        for shape in ["disjoint", "paired", "overlapping-stress"] {
            let stride = shape == "paired" ? 4 : 2
            let span = shape == "disjoint" ? 1 : (shape == "paired" ? 3 : 900)
            let bold = (0..<count).map { NSRange(location: $0 * stride, length: span) }
            let italic = (0..<count).map { NSRange(location: $0 * stride + 1, length: span) }
            precondition((bold + italic).allSatisfy { NSMaxRange($0) <= length })
            check(bold, italic)
            let iterations = count >= 128 ? 12 : 200
            _ = measure(bold, italic, iterations: 5, apply: referenceForEachBoldItalicRange)
            _ = measure(bold, italic, iterations: 5, apply: chatForEachBoldItalicRange)
            var baseline: [Double] = []
            var candidate: [Double] = []
            for trial in 0..<7 {
                if trial % 2 == 0 {
                    baseline.append(measure(bold, italic, iterations: iterations, apply: referenceForEachBoldItalicRange))
                    candidate.append(measure(bold, italic, iterations: iterations, apply: chatForEachBoldItalicRange))
                } else {
                    candidate.append(measure(bold, italic, iterations: iterations, apply: chatForEachBoldItalicRange))
                    baseline.append(measure(bold, italic, iterations: iterations, apply: referenceForEachBoldItalicRange))
                }
            }
            let old = baseline.sorted()[3], new = candidate.sorted()[3]
            print("\(count)+\(count) \(shape): \(String(format: "%.2f", old)) → \(String(format: "%.2f", new)) µs (\(String(format: "%.2f", old/new))x)")
            results.append(["ranges_per_style": count, "shape": shape, "baseline_us": old, "candidate_us": new, "speedup": old/new])
        }
    }
    let output: [String: Any] = ["comparisons": comparisons, "results": results, "checksum": checksum]
    let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    if let path = ProcessInfo.processInfo.environment["FONT_BENCH_RESULTS"] { try data.write(to: URL(fileURLWithPath: path)) }
}
