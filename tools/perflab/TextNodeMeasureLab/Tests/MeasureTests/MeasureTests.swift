import AppKit
import CoreText
import XCTest
import class TGUIKit.TextNode
import class TGUIKit.TextNodeLayout
import struct TGUIKit.TextNodeCutout
import class TGUIKitBaseline.TextNode
import class TGUIKitBaseline.TextNodeLayout
import struct TGUIKitBaseline.TextNodeCutout

final class MeasureTests: XCTestCase {
    override func setUp() { super.setUp(); MeasureBootstrap.install() }

    func testOriginalMinimumLineLimitRegression() throws {
        guard ProcessInfo.processInfo.environment["TEXTNODE_BASELINE_CRASH"] == "1" else { throw XCTSkip("Isolated original line-limit crash reproduction") }
        _ = TGUIKitBaseline.TextNode.layoutText(text("a label", mode: 0), nil, Int.min, .end, CGSize(width: 90, height: 50), nil, false, .left)
    }

    private func text(_ string: String, mode: Int) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = mode == 2 ? 12 : 0
        paragraph.headIndent = mode == 2 ? 5 : 0
        paragraph.lineBreakMode = mode == 2 ? .byCharWrapping : .byWordWrapping
        paragraph.baseWritingDirection = mode == 3 ? .rightToLeft : .natural
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 40, options: [:])]
        let value = NSMutableAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: mode == 1 ? 19 : 14), .foregroundColor: NSColor.black, .paragraphStyle: paragraph, NSAttributedString.Key("KSelectedColorAttributeName"): NSColor.red])
        if mode == 1, value.length > 1 {
            value.addAttributes([.font: NSFont.boldSystemFont(ofSize: 17), .foregroundColor: NSColor.blue, .kern: 0.4], range: NSRange(location: 1, length: value.length - 1))
        }
        return value
    }

    private func pixels(size: CGSize, scale: CGFloat, draw: (CGRect, CGContext) -> Void) throws -> Data {
        let size = CGSize(width: min(420, max(2, size.width + 12)), height: min(360, max(2, size.height + 12)))
        let width = Int(ceil(size.width * scale)), height = Int(ceil(size.height * scale))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        draw(CGRect(origin: CGPoint(x: 3, y: 4), size: CGSize(width: min(400, size.width - 12), height: size.height - 12)), context)
        return Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
    }

    func testExactGeometryGlyphsAndPixelsAcrossLayoutModes() throws {
        let strings = ["", "A", "ordinary short label", "long filename with spaces and a final extension.tar.gz", "שלום עולם mixed 123", "مرحبا بالعالم", "中文日本語 한국어", "👨‍👩‍👧‍👦 🏳️‍🌈 e\u{301} fi", "first\nsecond\r\nthird", "\n", "   \t  ", "\u{0}a\u{200b}\u{200d}\u{2028}b", String(repeating: "word ", count: 30)]
        var pairs = 0
        var nonblankPairs = 0
        for (stringIndex, string) in strings.enumerated() {
            for mode in 0..<4 {
                let value = text(string, mode: mode)
                for width: CGFloat in [-100, -1, 0, 0.25, 1, 17.5, 90, 320, .greatestFiniteMagnitude] {
                    for limit in [0, 1, 2, 3] {
                        for truncation: CTLineTruncationType in [.start, .middle, .end] {
                            let size = CGSize(width: width, height: 400)
                            let selected = mode % 2 == 1
                            let spacing: CGFloat? = mode == 2 ? 4.5 : nil
                            let alignment: NSTextAlignment = mode == 3 ? .center : .left
                            let cutout = mode == 2 ? TGUIKit.TextNodeCutout(position: .TopLeft, size: CGSize(width: 30, height: 35)) : nil
                            let oldCutout = mode == 2 ? TGUIKitBaseline.TextNodeCutout(position: .TopLeft, size: CGSize(width: 30, height: 35)) : nil
                            let a = TGUIKitBaseline.TextNode.layoutText(value, nil, limit, truncation, size, oldCutout, selected, alignment, spacing)
                            let b = TGUIKit.TextNode.layoutText(value, nil, limit, truncation, size, cutout, selected, alignment, spacing)
                            XCTAssertEqual(a.0.measurementSnapshot(), b.0.measurementSnapshot(), "string=\(stringIndex), mode=\(mode), width=\(width), limit=\(limit), truncation=\(truncation)")
                            if width == 90 || width == 320 {
                                for scale: CGFloat in [1, 2] {
                                    let old = try pixels(size: a.0.size, scale: scale) { a.1.draw($0, in: $1, backingScaleFactor: scale, backgroundColor: .white) }
                                    let new = try pixels(size: b.0.size, scale: scale) { b.1.draw($0, in: $1, backingScaleFactor: scale, backgroundColor: .white) }
                                    XCTAssertTrue(old == new, "Pixel mismatch: string=\(stringIndex), mode=\(mode), width=\(width), limit=\(limit), scale=\(scale)")
                                    if stringIndex == 2 && mode == 0 && width == 90 && limit == 1 {
                                        XCTAssertTrue(old.contains { $0 != 255 })
                                        XCTAssertTrue(new.contains { $0 != 255 })
                                        nonblankPairs += 1
                                    }
                                    pairs += 1
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(pairs, 2496)
        XCTAssertEqual(nonblankPairs, 6)
    }
    func testNonemptyTerminalLinesMatchForControlsAndComplexClusters() {
        let strings = ["\u{200d}", "\u{200b}", "\u{fe0f}", "\u{2066}\u{2069}", "\r", "\u{2028}", "\u{2029}", "\u{0000}", "\u{00ad}", "\u{0301}", "\u{200d}a", "\u{2067}שלום\u{2069}"]
        for string in strings {
            for width: CGFloat in [0.0001, 1, 10, 100, .greatestFiniteMagnitude] {
                for limit in [1, 2, 3] {
                    let value = text(string, mode: 3)
                    let size = CGSize(width: width, height: 100)
                    let a = TGUIKitBaseline.TextNode.layoutText(value, nil, limit, .end, size, nil, false, .left)
                    let b = TGUIKit.TextNode.layoutText(value, nil, limit, .end, size, nil, false, .left)
                    XCTAssertEqual(a.0.measurementSnapshot(), b.0.measurementSnapshot())
                }
            }
        }
    }

    func testDeterministicMixedScriptParagraphsMatchOriginal() {
        var state: UInt64 = 0x87a56b0291
        func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 32) % UInt64(bound))
        }
        let clusters = ["a", "fi", " ", "\t", "\n", "\r\n", "é", "e\u{301}", "ש", "م", "中", "👩🏽‍💻", "🇦🇪", "\u{200b}", "\u{2028}", "\u{00ad}"]
        for index in 0..<512 {
            let string = (0..<next(40)).map { _ in clusters[next(clusters.count)] }.joined()
            let value = text(string, mode: next(4))
            let width: CGFloat = [0.1, 3, 35.5, 90, 160, 300][next(6)]
            let size = CGSize(width: width, height: 400)
            let limit = [1, 2, 3, 0][next(4)]
            let truncation: CTLineTruncationType = [.start, .middle, .end][next(3)]
            let selected = next(2) == 1
            let alignment: NSTextAlignment = next(2) == 1 ? .center : .left
            let a = TGUIKitBaseline.TextNode.layoutText(value, nil, limit, truncation, size, .init(position: .TopRight, size: CGSize(width: 22, height: 30)), selected, alignment)
            let b = TGUIKit.TextNode.layoutText(value, nil, limit, truncation, size, .init(position: .TopRight, size: CGSize(width: 22, height: 30)), selected, alignment)
            XCTAssertEqual(a.0.measurementSnapshot(), b.0.measurementSnapshot(), "Randomized case \(index)")
        }
    }

    func testReusedLayoutsTrackSelectionWidthAndMutableText() throws {
        let value = NSMutableAttributedString(attributedString: text("initial title", mode: 0))
        let oldNode = TGUIKitBaseline.TextNode(), newNode = TGUIKit.TextNode()
        for iteration in 0..<24 {
            let string = ["Alice Parker", "a longer filename.mov", "שלום עולם 👩🏽‍💻"][iteration / 8]
            value.replaceCharacters(in: NSRange(location: 0, length: value.length), with: string)
            let width: CGFloat = iteration % 4 < 2 ? 80 : 240
            let selected = iteration % 2 == 1
            let size = CGSize(width: width, height: 50)
            let a = TGUIKitBaseline.TextNode.layoutText(maybeNode: oldNode, value, nil, 1, .middle, size, nil, selected, .left)
            let b = TGUIKit.TextNode.layoutText(maybeNode: newNode, value, nil, 1, .middle, size, nil, selected, .left)
            XCTAssertEqual(a.0.measurementSnapshot(), b.0.measurementSnapshot())
            XCTAssertTrue(b.1 === newNode)
            let repeatLayout = TGUIKit.TextNode.layoutText(maybeNode: newNode, value, nil, 1, .middle, size, nil, selected, .left)
            XCTAssertTrue(repeatLayout.0 === b.0)
            let old = try pixels(size: a.0.size, scale: 2) { a.1.draw($0, in: $1, backingScaleFactor: 2, backgroundColor: .white) }
            let new = try pixels(size: b.0.size, scale: 2) { b.1.draw($0, in: $1, backingScaleFactor: 2, backgroundColor: .white) }
            XCTAssertTrue(old == new)
        }
        let normal = TGUIKit.TextNode.layoutText(value, nil, 1, .end, CGSize(width: 240, height: 50), nil, false, .left)
        let selected = TGUIKit.TextNode.layoutText(value, nil, 1, .end, CGSize(width: 240, height: 50), nil, true, .left)
        let normalPixels = try pixels(size: normal.0.size, scale: 2) { normal.1.draw($0, in: $1, backingScaleFactor: 2, backgroundColor: .white) }
        let selectedPixels = try pixels(size: selected.0.size, scale: 2) { selected.1.draw($0, in: $1, backingScaleFactor: 2, backgroundColor: .white) }
        XCTAssertNotEqual(normalPixels, selectedPixels)
    }

    func testExtremeCutoutArithmeticAndNegativeLimits() {
        let value = text("words and another line\nsecond paragraph", mode: 0)
        for width: CGFloat in [90, .greatestFiniteMagnitude] {
            for cutoutWidth: CGFloat in [-CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude] {
                let size = CGSize(width: width, height: 100)
                let cutout = CGSize(width: cutoutWidth, height: 50)
                let a = TGUIKitBaseline.TextNode.layoutText(value, nil, 1, .end, size, .init(position: .TopRight, size: cutout), false, .left)
                let b = TGUIKit.TextNode.layoutText(value, nil, 1, .end, size, .init(position: .TopRight, size: cutout), false, .left)
                XCTAssertEqual(a.0.measurementSnapshot(), b.0.measurementSnapshot())
            }
        }
        for value: NSAttributedString? in [nil, text("", mode: 0), value] {
            for limit in [Int.min, -1, 0] {
                let size = CGSize(width: 100, height: 100)
                let a = TGUIKitBaseline.TextNode.layoutText(value, nil, 0, .end, size, nil, false, .left)
                let b = TGUIKit.TextNode.layoutText(value, nil, limit, .end, size, nil, false, .left)
                XCTAssertEqual(a.0.measurementSnapshot(), b.0.measurementSnapshot())
            }
        }
    }

    func testConcurrentIndependentMeasurementsMatchOriginal() {
        let values = ["Alice Parker", "long filename with extension.mov", "👩🏽‍💻 mixed emoji 🇦🇪", "مرحبا بالعالم שלום", "one\ntwo\nthree"].map {
            NSAttributedString(string: $0, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        }
        let expected = values.map { TGUIKitBaseline.TextNode.layoutText($0, nil, 1, .middle, CGSize(width: 90, height: 50), nil, false, .left).0.measurementSnapshot() }
        let lock = NSLock()
        var mismatches: [Int] = []
        DispatchQueue.concurrentPerform(iterations: 600) { iteration in
            autoreleasepool {
                let index = iteration % values.count
                let actual = TGUIKit.TextNode.layoutText(values[index], nil, 1, .middle, CGSize(width: 90, height: 50), nil, false, .left).0.measurementSnapshot()
                if actual != expected[index] {
                    lock.lock()
                    mismatches.append(iteration)
                    lock.unlock()
                }
            }
        }
        XCTAssertTrue(mismatches.isEmpty)
    }

}
