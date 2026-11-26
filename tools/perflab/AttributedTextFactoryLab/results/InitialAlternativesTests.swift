import Cocoa
import XCTest
import TGUIKit

private func literal(_ string: String, color: NSColor?, font: NSFont?) -> NSAttributedString {
    if let color, let font {
        return NSAttributedString(string: string, attributes: [.foregroundColor: color, .font: font])
    } else if let color {
        return NSAttributedString(string: string, attributes: [.foregroundColor: color])
    } else if let font {
        return NSAttributedString(string: string, attributes: [.font: font])
    } else {
        return NSAttributedString(string: string)
    }
}

private func mutable(_ string: String, color: NSColor?, font: NSFont?) -> NSAttributedString {
    let result = NSMutableAttributedString(string: string)
    let range = NSRange(location: 0, length: result.length)
    if let color { result.addAttribute(.foregroundColor, value: color, range: range) }
    if let font { result.addAttribute(.font, value: font, range: range) }
    return result.copy() as! NSAttributedString
}

final class AlternativesTests: XCTestCase {
    func testAlternativeConstructionBenchmark() throws {
        guard ProcessInfo.processInfo.environment["TEXT_FACTORY_ALTERNATIVES"] != nil else { throw XCTSkip("Opt-in construction alternatives") }
        TGUIKitTestBootstrap.install()
        let font = NSFont.normal(13), color = NSColor.labelColor
        let methods: [(String, (String, NSColor?, NSFont?) -> NSAttributedString)] = [
            ("reference", { NSAttributedString.referenceInitialize(string: $0, color: $1, font: $2) }),
            ("incremental", { NSAttributedString.initialize(string: $0, color: $1, font: $2) }),
            ("literal", literal), ("mutable", mutable)
        ]
        var report: [String: [Double]] = [:]
        for (name, text, color, font): (String, String, NSColor?, NSFont?) in [("short", "Alice Smith", color, font), ("emoji", "👩🏽‍💻 ❤️", color, font), ("long", String(repeating: "Hello world 🙂 ", count: 40), color, font), ("font", "Alice Smith", nil, font), ("plain", "Alice Smith", nil, nil)] {
            for batch in 0..<10 {
                for offset in 0..<methods.count {
                    let (method, make) = methods[(offset + batch) % methods.count]
                    let expected = NSAttributedString.referenceInitialize(string: text, color: color, font: font)
                    XCTAssertTrue(make(text, color, font).isEqual(to: expected))
                    var checksum = 0
                    let start = CFAbsoluteTimeGetCurrent()
                    for _ in 0..<4000 { autoreleasepool { checksum += make(text, color, font).length } }
                    let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000000 / 4000
                    XCTAssertEqual(checksum, expected.length * 4000)
                    if batch > 0 { report[name + "-" + method, default: []].append(elapsed) }
                }
            }
        }
        for key in report.keys.sorted() { print("TEXT_FACTORY_ALTERNATIVE \(key): \(report[key]!.sorted()[4]) us/call") }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/attributed-text-alternatives.json"))
    }
}
