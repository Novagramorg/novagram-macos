import Cocoa
import XCTest
@testable import TGUIKit

final class CounterTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private var fonts: [NSFont] {
        [NSFont.systemFont(ofSize: 13), NSFont.boldSystemFont(ofSize: 17), NSFont(name: "Menlo", size: 12), NSFont(name: "Times New Roman Italic", size: 15), NSFont(name: "Apple Color Emoji", size: 14)].compactMap { $0 }
    }

    func testCounterValuesMatchOriginalAcrossFontsAndModes() {
        for font in fonts {
            for (text, count) in [("12 participants", "12"), ("1,234 views", "1,234"), ("typing…", ""), ("Paid -12.50 stars", "-12.50"), ("١٢ رسالة", "١٢"), ("T minus 00:59", "00:59"), ("no count", "missing"), ("", "")] {
                for width: CGFloat in [20, 70, 250] {
                    for kerned in [false, true] {
                        for fade in [false, true] {
                            let actual = DynamicCounterTextView.make(for: text, count: count, font: font, textColor: .black, width: width, onlyFade: fade, kerned: kerned, rolling: kerned)
                            let original = ReferenceDynamicCounterTextView.make(for: text, count: count, font: font, textColor: .black, width: width, onlyFade: fade, kerned: kerned, rolling: kerned)
                            XCTAssertEqual(actual.numSize, original.numSize)
                            XCTAssertEqual(actual.size, original.size)
                            XCTAssertEqual(actual.offsets, original.offsets)
                            XCTAssertEqual(actual.rolling, original.rolling)
                            XCTAssertEqual(actual.values.count, original.values.count)
                            for (first, second) in zip(actual.values, original.values) {
                                XCTAssertEqual(first.0.layoutSize, second.0.layoutSize)
                                XCTAssertEqual(first.0.lines.map { $0.frame }, second.0.lines.map { $0.frame })
                                XCTAssertEqual(first.1.text, second.1.text)
                                XCTAssertEqual(first.1.index, second.1.index)
                                XCTAssertEqual(first.1.animation == .numeric, second.1.animation == .numeric)
                            }
                        }
                    }
                }
            }
        }
    }

    private func referenceWidth(_ font: NSFont) -> CGFloat {
        (0...9).map { digit in
            let layout = TextViewLayout(.initialize(string: "\(digit)", color: nil, font: font), maximumNumberOfLines: 1, truncationType: .end, alignment: .center)
            layout.measure(width: .greatestFiniteMagnitude)
            return layout.layoutSize.width
        }.max()!
    }

    private func cachedFonts(_ cache: DynamicCounterDigitWidthCache) -> [NSFont] {
        let entries = Mirror(reflecting: cache).children.first { $0.label == "entries" }!.value
        return Mirror(reflecting: entries).children.map { entry in
            Mirror(reflecting: entry.value).children.first { $0.label == "font" }!.value as! NSFont
        }
    }

    func testDigitWidthsMatchRealLayoutAcrossInstalledFontsAndFractionalSizes() {
        let cache = DynamicCounterDigitWidthCache()
        for name in NSFontManager.shared.availableFonts {
            for size: CGFloat in [7.25, 13, 21.5, 48] {
                guard let font = NSFont(name: name, size: size) else { continue }
                let expected = referenceWidth(font)
                XCTAssertEqual(cache.width(for: font), expected, "\(name) \(size)")
                XCTAssertEqual(cache.width(for: font), expected, "cached \(name) \(size)")
            }
        }
    }

    func testFontFeaturesAndTransformsKeepExactMetrics() {
        let cache = DynamicCounterDigitWidthCache()
        for font in fonts {
            let matrix = AffineTransform(m11: 1.2, m12: 0.15, m21: 0.1, m22: 0.9, tX: 0, tY: 0)
            let transformed = font.fontDescriptor.withMatrix(matrix)
            let features = font.fontDescriptor.addingAttributes([.featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType, NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
            for descriptor in [transformed, features] {
                guard let variant = NSFont(descriptor: descriptor, size: font.pointSize) else { continue }
                XCTAssertEqual(cache.width(for: variant), referenceWidth(variant))
                XCTAssertEqual(cache.width(for: variant), referenceWidth(variant))
            }
        }
    }

    func testApplicationFontMetrics() {
        let cache = DynamicCounterDigitWidthCache()
        for size: CGFloat in [9, 13, 17, 50] {
            let fonts: [NSFont] = [.normal(size), .medium(size), .avatar(size), .digitalRound(size), .normalMonospaced(size)]
            for font in fonts {
                let expected = referenceWidth(font)
                XCTAssertEqual(cache.width(for: font), expected)
                XCTAssertEqual(cache.width(for: font), expected)
            }
        }
    }

    func testCacheIsBoundedAndRetainsExactFontIdentity() {
        let cache = DynamicCounterDigitWidthCache()
        let fonts = (0..<32).map { NSFont.systemFont(ofSize: CGFloat($0) + 9.125) }
        for font in fonts {
            XCTAssertEqual(cache.width(for: font), referenceWidth(font))
            XCTAssertLessThanOrEqual(cachedFonts(cache).count, 16)
        }
        XCTAssertEqual(cachedFonts(cache).count, 16)
        XCTAssertTrue(cachedFonts(cache).contains { $0 === fonts.last! })
        XCTAssertFalse(cachedFonts(cache).contains { $0 === fonts.first! })
        let identities = cachedFonts(cache).map(ObjectIdentifier.init)
        _ = cache.width(for: fonts.last!)
        XCTAssertEqual(cachedFonts(cache).map(ObjectIdentifier.init), identities)
        XCTAssertEqual(cache.width(for: fonts.first!), referenceWidth(fonts.first!))
        XCTAssertEqual(cachedFonts(cache).count, 16)
    }

    func testFallbackFontsAreNotRetained() {
        let cache = DynamicCounterDigitWidthCache()
        var fallbackCount = 0
        for name in NSFontManager.shared.availableFonts {
            guard let font = NSFont(name: name, size: 13) else { continue }
            let line = CTLineCreateWithAttributedString(NSAttributedString.initialize(string: "0123456789", color: nil, font: font))
            let usesFallback = (CTLineGetGlyphRuns(line) as! [CTRun]).contains { run in
                let attributes = CTRunGetAttributes(run) as NSDictionary
                return !CFEqual(attributes[kCTFontAttributeName] as CFTypeRef?, font)
            }
            if usesFallback {
                fallbackCount += 1
                XCTAssertEqual(cache.width(for: font), referenceWidth(font))
                XCTAssertFalse(cachedFonts(cache).contains { $0 === font })
            }
        }
        XCTAssertGreaterThan(fallbackCount, 0)
    }

    func testConcurrentColdAndWarmMeasurements() {
        let cache = DynamicCounterDigitWidthCache()
        let fonts = (0..<24).map { NSFont.systemFont(ofSize: CGFloat($0) + 8.375) }
        let expected = fonts.map(referenceWidth)
        let lock = NSLock()
        var failures = 0
        DispatchQueue.concurrentPerform(iterations: 2400) { index in
            let slot = index % fonts.count
            let actual = cache.width(for: fonts[slot])
            if actual != expected[slot] {
                lock.lock(); failures += 1; lock.unlock()
            }
        }
        XCTAssertEqual(failures, 0)
        XCTAssertLessThanOrEqual(cachedFonts(cache).count, 16)
    }

    func testCounterSubviewsRenderIdenticallyToOriginal() throws {
        var pairs = 0
        defer { System.updateScaleFactor(2) }
        for scale: CGFloat in [1, 2] {
            System.updateScaleFactor(scale)
            for font in fonts.prefix(3) {
                for rolling in [false, true] {
                    for color in [NSColor.black, .white] {
                        let candidate = DynamicCounterTextView(frame: .zero)
                        let original = ReferenceDynamicCounterTextView(frame: .zero)
                        for (text, count) in [("12 participants", "12"), ("13 participants", "13"), ("00:59", "00:59"), ("01:00", "01:00")] {
                            let actual = DynamicCounterTextView.make(for: text, count: count, font: font, textColor: color, width: 200, kerned: rolling, rolling: rolling)
                            let expected = ReferenceDynamicCounterTextView.make(for: text, count: count, font: font, textColor: color, width: 200, kerned: rolling, rolling: rolling)
                            candidate.update(actual, animated: false)
                            original.update(expected, animated: false)
                            XCTAssertEqual(candidate.accessibilityText, original.accessibilityText)
                            XCTAssertEqual(candidate.effectiveSubviews.count, original.effectiveSubviews.count)
                            XCTAssertEqual(try render(candidate.effectiveSubviews, scale: scale), try render(original.effectiveSubviews, scale: scale))
                            pairs += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(pairs, 96)
    }

    private func render(_ views: [TextView], scale: CGFloat) throws -> Data {
        let width = Int(240 * scale), height = Int(70 * scale)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        for view in views.sorted(by: { $0.frame.minX < $1.frame.minX }) {
            context.saveGState()
            context.translateBy(x: view.frame.minX, y: view.frame.minY)
            view.draw(view.drawingLayer, in: context)
            context.restoreGState()
        }
        let data = Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
        XCTAssertTrue(data.contains { $0 != 0 })
        return data
    }

    func testCounterViewInstanceDoesNotGrow() {
        XCTAssertLessThanOrEqual(class_getInstanceSize(DynamicCounterTextView.self), class_getInstanceSize(ReferenceDynamicCounterTextView.self))
    }

    func testCounterConstructionBenchmark() throws {
        guard ProcessInfo.processInfo.environment["COUNTER_BENCHMARK"] != nil else { throw XCTSkip("Opt-in counter construction benchmark") }
        var report: [String: Any] = [:]
        let font = NSFont.systemFont(ofSize: 13)
        for (text, count, kerned) in [("12 participants", "12", false), ("00:59", "00:59", true), ("typing…", "", false)] {
            _ = DynamicCounterTextView.make(for: text, count: count, font: font, textColor: .black, width: 200, kerned: kerned)
            _ = ReferenceDynamicCounterTextView.make(for: text, count: count, font: font, textColor: .black, width: 200, kerned: kerned)
            var before: [Double] = [], after: [Double] = []
            var checksum: CGFloat = 0
            for batch in 0..<9 {
                for candidate in batch % 2 == 0 ? [false, true] : [true, false] {
                    let elapsed = autoreleasepool { () -> Double in
                        let start = CACurrentMediaTime()
                        for _ in 0..<1000 {
                            if candidate { checksum += DynamicCounterTextView.make(for: text, count: count, font: font, textColor: .black, width: 200, kerned: kerned).size.width }
                            else { checksum += ReferenceDynamicCounterTextView.make(for: text, count: count, font: font, textColor: .black, width: 200, kerned: kerned).size.width }
                        }
                        return (CACurrentMediaTime() - start) * 1000
                    }
                    if candidate { after.append(elapsed) } else { before.append(elapsed) }
                }
            }
            XCTAssertGreaterThan(checksum, 0)
            report[text] = ["original_ms_per_1000": before, "candidate_ms_per_1000": after]
        }
        var coldOriginal: [Double] = [], coldCandidate: [Double] = []
        var checksum: CGFloat = 0
        for batch in 0..<9 {
            for candidate in batch % 2 == 0 ? [false, true] : [true, false] {
                let start = CACurrentMediaTime()
                autoreleasepool {
                    for _ in 0..<1000 {
                        checksum += candidate ? DynamicCounterDigitWidthCache().width(for: font) : referenceWidth(font)
                    }
                }
                let elapsed = (CACurrentMediaTime() - start) * 1000
                if candidate { coldCandidate.append(elapsed) } else { coldOriginal.append(elapsed) }
            }
        }
        XCTAssertGreaterThan(checksum, 0)
        report["cold digit width"] = ["original_ms_per_1000": coldOriginal, "candidate_ms_per_1000": coldCandidate]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/counter-benchmark.json"))
    }
}
