import Cocoa
import XCTest
import CoreProbe
import KitProbe

private final class CountingColor: NSColor {
    var conversions = 0
    var value = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
    override func usingColorSpaceName(_ colorSpace: NSColorSpaceName) -> NSColor? {
        conversions += 1
        return value.usingColorSpaceName(colorSpace)
    }
}

final class EqualityTests: XCTestCase {
    private let implementations: [(String, (NSColor, NSColor) -> Bool, (NSColor, NSColor) -> Bool)] = [("kit", kitCandidate, kitReference), ("core", coreCandidate, coreReference)]
    override func setUp() { ColorProbeBootstrap.install() }
    private func colors(_ count: Int) -> [NSColor] {
        var state: UInt64 = 0x47263091
        func component() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 32) & 0xffff) / 65535
        }
        return (0..<count).map { _ in NSColor(srgbRed: component(), green: component(), blue: component(), alpha: component()) }
    }

    func testSameInstancePerformsNoColorSpaceConversions() {
        for (_, candidate, reference) in implementations {
            let color = CountingColor()
            XCTAssertTrue(reference(color, color))
            XCTAssertEqual(color.conversions, 2)
            color.conversions = 0
            XCTAssertTrue(candidate(color, color))
            XCTAssertEqual(color.conversions, 0)
        }
    }

    func testDifferentInstancesKeepBothConversionsAndPackedSemantics() {
        for (_, candidate, reference) in implementations {
            let first = CountingColor(), second = CountingColor()
            XCTAssertFalse(first === second)
            let expected = reference(first, second)
            first.conversions = 0; second.conversions = 0
            XCTAssertEqual(candidate(first, second), expected)
            XCTAssertEqual(first.conversions, 1); XCTAssertEqual(second.conversions, 1)
            second.value = .red
            XCTAssertEqual(candidate(first, second), reference(first, second))
        }
    }

    func testRandomizedComparisonMatrixMatchesReference() {
        let values = colors(128)
        for (_, candidate, reference) in implementations {
            for first in values {
                for second in values { XCTAssertEqual(candidate(first, second), reference(first, second)) }
            }
        }
    }

    func testQuantizationAlphaAndColorSpacesRemainUnchanged() {
        let closeA = NSColor(deviceRed: 0.5001, green: 0.3, blue: 0.2, alpha: 1)
        let closeB = NSColor(deviceRed: 0.5002, green: 0.3, blue: 0.2, alpha: 1)
        XCTAssertFalse(closeA.isEqual(closeB))
        XCTAssertEqual(corePacked(closeA), corePacked(closeB))
        let values: [NSColor] = [closeA, closeB, .black, .white, .clear,
            NSColor(deviceRed: 0.5, green: 0.3, blue: 0.2, alpha: 0.5),
            NSColor(srgbRed: 0.3, green: 0.4, blue: 0.5, alpha: 0.7),
            NSColor(displayP3Red: 0.3, green: 0.4, blue: 0.5, alpha: 0.7),
            NSColor(calibratedWhite: 0.5, alpha: 0.8),
            NSColor(deviceCyan: 0.2, magenta: 0.3, yellow: 0.4, black: 0.1, alpha: 0.9)]
        for (_, candidate, reference) in implementations {
            XCTAssertTrue(candidate(closeA, closeB))
            for first in values {
                for second in values { XCTAssertEqual(candidate(first, second), reference(first, second)) }
            }
        }
    }

    func testDynamicAndSystemColorsAcrossAppearanceChanges() throws {
        let previous = NSAppearance.current
        defer { NSAppearance.current = previous }
        let dynamic = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
        }
        let other = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
        }
        for name in [NSAppearance.Name.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua] {
            NSAppearance.current = try XCTUnwrap(NSAppearance(named: name))
            let values = [dynamic, other, .labelColor, .controlTextColor, .windowBackgroundColor, .separatorColor]
            for (_, candidate, reference) in implementations {
                for first in values {
                    for second in values { XCTAssertEqual(candidate(first, second), reference(first, second)) }
                }
            }
        }
    }

    func testOptionalEqualityKeepsFoundationBehavior() {
        let first = NSColor(deviceRed: 0.5001, green: 0.3, blue: 0.2, alpha: 1)
        let second = NSColor(deviceRed: 0.5002, green: 0.3, blue: 0.2, alpha: 1)
        let values: [NSColor?] = [nil, first, second, .white]
        for compare in [kitOptional, coreOptional] {
            for lhs in values {
                for rhs in values {
                    let expected = lhs.map { left in rhs.map { left.isEqual($0) } ?? false } ?? (rhs == nil)
                    XCTAssertEqual(compare(lhs, rhs), expected)
                }
            }
        }
    }

    func testControlStylesPreserveComparisonResults() {
        let values = colors(24)
        for index in values.indices {
            let first = StylePair(values[index], values[(index + 1) % values.count])
            let second = StylePair(values[index], values[(index + 1) % values.count], otherForeground: values[(index + 2) % values.count])
            let third = StylePair(values[index], values[(index + 1) % values.count], differentFont: true)
            for pair in [first, second, third] { XCTAssertEqual(pair.candidate(), pair.reference()) }
        }
    }

    func testSharedControlStyleColorsAvoidConversion() {
        let foreground = CountingColor(), background = CountingColor()
        let pair = StylePair(foreground, background)
        XCTAssertTrue(pair.reference())
        XCTAssertEqual(foreground.conversions, 2); XCTAssertEqual(background.conversions, 2)
        foreground.conversions = 0; background.conversions = 0
        XCTAssertTrue(pair.candidate())
        XCTAssertEqual(foreground.conversions, 0); XCTAssertEqual(background.conversions, 0)
    }

    func testBenchmark() throws {
        guard ProcessInfo.processInfo.environment["COLOR_EQUALITY_BENCHMARK"] != nil else { throw XCTSkip("Opt-in color equality benchmark") }
        let palette = colors(128)
        var report: [String: Any] = [:]
        let reverse = ProcessInfo.processInfo.environment["COLOR_EQUALITY_REVERSE"] != nil
        func batches(_ reference: () -> Int, _ candidate: () -> Int, count: Int, expected: Int) -> [String: Any] {
            func measure(_ operation: () -> Int) -> Double {
                let start = CFAbsoluteTimeGetCurrent()
                let result = operation()
                let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000000 / Double(count)
                XCTAssertEqual(result, expected)
                return elapsed
            }
            _ = measure(reference); _ = measure(candidate)
            var old: [Double] = [], new: [Double] = []
            for batch in 0..<9 {
                if batch % 2 == (reverse ? 1 : 0) { old.append(measure(reference)); new.append(measure(candidate)) }
                else { new.append(measure(candidate)); old.append(measure(reference)) }
            }
            return ["baseline_us": old, "candidate_us": new, "baseline_median_us": old.sorted()[4], "candidate_median_us": new.sorted()[4]]
        }
        for (module, candidate, reference) in implementations {
            for scenario in ["shared", "mixed", "different", "equal-distinct"] {
                let pairs: [(NSColor, NSColor)] = palette.enumerated().map { index, color in
                    switch scenario {
                    case "shared": return (color, color)
                    case "mixed": return (color, index % 2 == 0 ? color : palette[(index + 1) % palette.count])
                    case "equal-distinct":
                        let duplicate = NSColor(srgbRed: color.redComponent, green: color.greenComponent, blue: color.blueComponent, alpha: color.alphaComponent)
                        XCTAssertFalse(color === duplicate)
                        return (color, duplicate)
                    default: return (color, palette[(index + 1) % palette.count])
                    }
                }
                let repetitions = 100
                func run(_ compare: (NSColor, NSColor) -> Bool) -> Int {
                    var sum = 0
                    for _ in 0..<repetitions { for pair in pairs { sum += compare(pair.0, pair.1) ? 1 : 0 } }
                    return sum
                }
                let expected = pairs.reduce(0) { $0 + (reference($1.0, $1.1) ? 1 : 0) } * repetitions
                let result = batches({ run(reference) }, { run(candidate) }, count: pairs.count * repetitions, expected: expected)
                report[module + "-" + scenario] = result
                print("COLOR_EQUALITY \(module)-\(scenario): \(result["baseline_median_us"]!) -> \(result["candidate_median_us"]!) us/comparison")
            }
        }
        let styles = palette.map { StylePair($0, .white) }
        func stylesRun(_ candidate: Bool) -> Int {
            var sum = 0
            for _ in 0..<100 { for pair in styles { sum += (candidate ? pair.candidate() : pair.reference()) ? 1 : 0 } }
            return sum
        }
        let result = batches({ stylesRun(false) }, { stylesRun(true) }, count: styles.count * 100, expected: styles.count * 100)
        report["control-style-shared"] = result
        print("COLOR_EQUALITY control-style-shared: \(result["baseline_median_us"]!) -> \(result["candidate_median_us"]!) us/comparison")
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/color-equality-benchmark.json"))
    }
}
