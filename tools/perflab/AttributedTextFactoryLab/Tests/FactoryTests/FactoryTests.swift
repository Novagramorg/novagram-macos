import Cocoa
import XCTest
@testable import TGUIKit

final class FactoryTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private let texts: [String?] = [nil, "", "Hello", "12:34", "Alice Smith", "👩🏽‍💻", "🇦🇪 ❤️", "مرحبا بالعالم", "שלום", "漢字かな", "e\u{301}", "a\u{0}b", "first\nsecond\tline", " \n "]
    private var fonts: [NSFont?] { [nil, .normal(10), .systemFont(ofSize: 13, weight: .semibold), .monospacedSystemFont(ofSize: 12, weight: .regular), NSFontManager.shared.convert(.systemFont(ofSize: 15), toHaveTrait: .italicFontMask)] }
    private var colors: [NSColor?] { [nil, .clear, .red, .labelColor, NSColor(displayP3Red: 0.2, green: 0.6, blue: 0.8, alpha: 0.4)] }

    private func verify(_ string: String?, color: NSColor?, font: NSFont?, file: StaticString = #filePath, line: UInt = #line) {
        let old = NSAttributedString.referenceInitialize(string: string, color: color, font: font)
        let new = NSAttributedString.initialize(string: string, color: color, font: font)
        XCTAssertTrue(old.isEqual(to: new), "\(String(describing: string))", file: file, line: line)
        XCTAssertEqual(old.length, new.length, file: file, line: line)
        XCTAssertEqual(old.string, new.string, file: file, line: line)
        for offset in 0..<new.length {
            var oldRange = NSRange(), newRange = NSRange()
            let oldAttributes = old.attributes(at: offset, effectiveRange: &oldRange)
            let newAttributes = new.attributes(at: offset, effectiveRange: &newRange)
            XCTAssertEqual(oldRange, newRange, file: file, line: line)
            XCTAssertTrue(NSDictionary(dictionary: oldAttributes).isEqual(to: newAttributes), file: file, line: line)
            XCTAssertEqual(Set(newAttributes.keys), Set([color == nil ? nil : NSAttributedString.Key.foregroundColor, font == nil ? nil : NSAttributedString.Key.font].compactMap { $0 }), file: file, line: line)
        }
    }

    func testStringsColorsAndFontsMatchIncludingNilAndUnicode() {
        for text in texts { for color in colors { for font in fonts { verify(text, color: color, font: font) } } }
    }

    func testDefaultArgumentsAndOmittedAttributesMatch() {
        for text in texts {
            XCTAssertTrue(NSAttributedString.initialize(string: text).isEqual(to: .referenceInitialize(string: text)))
            XCTAssertTrue(NSAttributedString.initialize(string: text, color: .red).isEqual(to: .referenceInitialize(string: text, color: .red)))
            XCTAssertTrue(NSAttributedString.initialize(string: text, font: nil).isEqual(to: .referenceInitialize(string: text, font: nil)))
        }
        let plain = NSAttributedString.initialize(string: "plain", color: nil, font: nil)
        XCTAssertTrue(plain.attributes(at: 0, effectiveRange: nil).isEmpty)
    }

    func testEmptyMutableCopiesPreserveInsertionBehavior() {
        for text: String? in [nil, ""] {
            for color in colors {
                for font in fonts {
                    let old = NSAttributedString.referenceInitialize(string: text, color: color, font: font).mutableCopy() as! NSMutableAttributedString
                    let new = NSAttributedString.initialize(string: text, color: color, font: font).mutableCopy() as! NSMutableAttributedString
                    old.mutableString.append("Inserted")
                    new.mutableString.append("Inserted")
                    XCTAssertTrue(old.isEqual(to: new))
                    old.append(NSAttributedString(string: " tail"))
                    new.append(NSAttributedString(string: " tail"))
                    XCTAssertTrue(old.isEqual(to: new))
                }
            }
        }
    }

    func testMutableCopyDoesNotChangeOtherResults() {
        let first = NSAttributedString.initialize(string: "Hello", color: .red, font: .normal(10))
        let second = NSAttributedString.initialize(string: "Hello", color: .red, font: .normal(10))
        let copy = first.mutableCopy() as! NSMutableAttributedString
        copy.setAttributes([.foregroundColor: NSColor.blue], range: NSRange(location: 0, length: copy.length))
        copy.replaceCharacters(in: NSRange(location: 0, length: copy.length), with: "Different")
        XCTAssertEqual(first.string, "Hello")
        XCTAssertTrue(first.isEqual(to: second))
        XCTAssertFalse(first.isEqual(to: copy))
    }

    func testDynamicColorObjectIsPreservedAcrossAppearances() throws {
        let dynamic = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
        }
        let old = NSAttributedString.referenceInitialize(string: "Dynamic", color: dynamic, font: .normal(12))
        let new = NSAttributedString.initialize(string: "Dynamic", color: dynamic, font: .normal(12))
        let stored = try XCTUnwrap(new.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        XCTAssertTrue(stored === dynamic)
        for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                XCTAssertTrue(old.isEqual(to: new))
                XCTAssertTrue(stored.isEqual(dynamic))
            }
        }
    }

    func testRandomizedStringsAndAttributesMatch() {
        var state: UInt64 = 48271
        let atoms = ["a", "Z", "0", " ", "\n", "\t", "🙂", "👩🏽‍💻", "e\u{301}", "漢", "ب", "\u{0}", "\u{200F}"]
        let fonts = fonts, colors = colors
        func next(_ maximum: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 32) % UInt64(maximum))
        }
        for _ in 0..<1000 {
            let text = (0..<next(20)).map { _ in atoms[next(atoms.count)] }.joined()
            verify(text, color: colors[next(colors.count)], font: fonts[next(fonts.count)])
        }
    }

    func testConcurrentConstructionKeepsResultsIndependent() {
        let font = NSFont.normal(13), color = NSColor.labelColor
        let lock = NSLock()
        var failures = 0
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for index in 0..<250 {
                autoreleasepool {
                    let text = "Worker \(worker) message \(index) 👋"
                    let old = NSAttributedString.referenceInitialize(string: text, color: color, font: font)
                    let new = NSAttributedString.initialize(string: text, color: color, font: font)
                    let copy = new.mutableCopy() as! NSMutableAttributedString
                    copy.mutableString.append(" modified")
                    if !new.isEqual(to: old) || new.string != text || copy.string != text + " modified" {
                        lock.lock()
                        failures += 1
                        lock.unlock()
                    }
                }
            }
        }
        XCTAssertEqual(failures, 0)
    }

    private func layout(_ attributed: NSAttributedString) -> TextViewLayout {
        let layout = TextViewLayout(attributed, maximumNumberOfLines: 3)
        layout.measure(width: 180)
        return layout
    }

    private func pixels(_ layout: TextViewLayout, scale: Int) -> Data {
        let layer = TextViewLayer()
        layer.contentsScale = CGFloat(scale)
        layer.update(layout, size: layout.layoutSize)
        layer.bounds = CGRect(origin: .zero, size: layout.layoutSize).insetBy(dx: -2, dy: -3)
        layer.display()
        let side = 256 * scale
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.translateBy(x: 8, y: 8)
        layer.render(in: context)
        return Data(bytes: context.data!, count: side * side * 4)
    }

    func testMeasuredGeometryAndRenderedPixelsMatch() {
        var pairs = 0
        for text in ["12:34", "Alice Smith", "Message body with several words that wraps across lines", "👩🏽‍💻 ❤️", "مرحبا بالعالم", "漢字かな", "e\u{301}", ""] {
            for color: NSColor? in [nil, .red] {
                let old = layout(.referenceInitialize(string: text, color: color, font: .normal(13)))
                let new = layout(.initialize(string: text, color: color, font: .normal(13)))
                XCTAssertEqual(old.layoutSize, new.layoutSize)
                XCTAssertEqual(old.perfectSize, new.perfectSize)
                XCTAssertEqual(old.lines.count, new.lines.count)
                for (a, b) in zip(old.lines, new.lines) {
                    XCTAssertEqual(a.frame, b.frame)
                    XCTAssertEqual(a.range, b.range)
                }
                for scale in [1, 2, 3] {
                    let oldPixels = pixels(old, scale: scale), newPixels = pixels(new, scale: scale)
                    XCTAssertEqual(oldPixels, newPixels)
                    if !text.isEmpty { XCTAssertTrue(newPixels.contains { $0 != 0 }) }
                    pairs += 1
                }
            }
        }
        XCTAssertEqual(pairs, 48)
    }

    func testFactoryAndRowBindingBenchmark() throws {
        guard ProcessInfo.processInfo.environment["TEXT_FACTORY_BENCHMARK"] != nil else { throw XCTSkip("Opt-in attributed text benchmark") }
        let font = NSFont.normal(13), color = NSColor.labelColor
        let rows = (0..<40).map { "Message \($0): Hello 👋, this is a chat preview." }
        var report: [String: Any] = [:]
        let view = TextView()
        for scenario in ["short", "emoji", "long", "font-only", "color-only", "plain", "empty", "nil", "row-binding"] {
            let string: String? = scenario == "nil" ? nil : scenario == "empty" ? "" : scenario == "emoji" ? "👩🏽‍💻 ❤️" : scenario == "long" ? String(repeating: "Hello world 🙂 ", count: 40) : "Alice Smith"
            let textFont: NSFont? = scenario == "plain" || scenario == "color-only" ? nil : font
            let textColor: NSColor? = scenario == "plain" || scenario == "font-only" ? nil : color
            let count = scenario == "row-binding" ? 400 : 4000
            func measure(_ reference: Bool) -> Double {
                var checksum = 0
                let start = CFAbsoluteTimeGetCurrent()
                for index in 0..<count {
                    autoreleasepool {
                        let text = scenario == "row-binding" ? rows[index % rows.count] : string
                        let attributed = reference ? NSAttributedString.referenceInitialize(string: text, color: textColor, font: textFont) : NSAttributedString.initialize(string: text, color: textColor, font: textFont)
                        checksum += attributed.length
                        if scenario == "row-binding" {
                            let layout = self.layout(attributed)
                            view.update(layout)
                            checksum += layout.lines.count
                        }
                    }
                }
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000000 / Double(count)
                if scenario != "nil" && scenario != "empty" { XCTAssertGreaterThan(checksum, 0) }
                return elapsed
            }
            _ = measure(true); _ = measure(false)
            let reverse = ProcessInfo.processInfo.environment["TEXT_FACTORY_REVERSE"] != nil
            var old: [Double] = [], new: [Double] = []
            for batch in 0..<9 {
                if batch % 2 == (reverse ? 1 : 0) { old.append(measure(true)); new.append(measure(false)) }
                else { new.append(measure(false)); old.append(measure(true)) }
            }
            report[scenario] = ["baseline_us": old, "candidate_us": new, "baseline_median_us": old.sorted()[4], "candidate_median_us": new.sorted()[4]]
            print("TEXT_FACTORY \(scenario): \(old.sorted()[4]) -> \(new.sorted()[4]) us/call")
        }
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/attributed-text-factory-benchmark.json"))
    }
}
