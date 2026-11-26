import Cocoa
import XCTest
@testable import TGUIKit

private final class BlockCountingString: NSAttributedString {
    let value: NSAttributedString
    var substringCount = 0
    override var string: String { value.string }
    override var length: Int { value.length }
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        value.attributes(at: location, effectiveRange: range)
    }
    override func attributedSubstring(from range: NSRange) -> NSAttributedString {
        substringCount += 1
        return value.attributedSubstring(from: range)
    }
    init(_ value: NSAttributedString) { self.value = value; super.init() }
    required init?(coder: NSCoder) { fatalError() }
    required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) { fatalError() }
}

final class TextBlockTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    override func tearDown() {
        System.updateScaleFactor(2)
        super.tearDown()
    }

    private func pixels(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: image.width * image.height * 4)
    }

    private func assertEqual(_ a: (CGPoint, CGImage?), _ b: (CGPoint, CGImage?), file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.0, b.0, file: file, line: line)
        XCTAssertEqual(a.1 == nil, b.1 == nil, file: file, line: line)
        if let a = a.1, let b = b.1 {
            XCTAssertEqual(a.width, b.width, file: file, line: line)
            XCTAssertEqual(a.height, b.height, file: file, line: line)
            XCTAssertEqual(pixels(a), pixels(b), file: file, line: line)
        }
    }

    private func fixture(_ text: String, width: CGFloat = 180, alignment: NSTextAlignment = .left, maximumLines: Int32 = .max, cutout: TextViewCutout? = nil) -> TextViewLayout {
        let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        for index in stride(from: 0, to: value.length, by: 3) {
            value.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: index, length: min(2, value.length - index)))
        }
        let layout = TextViewLayout(value, maximumNumberOfLines: maximumLines, cutout: cutout, alignment: alignment)
        layout.measure(width: width)
        return layout
    }

    func testWholeBlockPixelsAcrossScriptsAlignmentScalesAndWrapping() {
        let samples = ["", "\n", "\n\n", "\r\n", "\nhello\n\nworld\n", "Message background with several wrapped lines and uneven lengths", "👩🏽‍🚀 🇺🇦 e\u{0301}\n中 文\n", "مرحبا بالعالم שלום English", "\u{2028}one\u{2029}two\u{0085}three"]
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for text in samples {
                for alignment in [NSTextAlignment.left, .center, .right] {
                    for width in [CGFloat(60), 240] {
                        let layout = fixture(text, width: width, alignment: alignment)
                        for color in [NSColor.black.withAlphaComponent(0.4), .clear] {
                            assertEqual(layout.legacyGenerateBlock(backgroundColor: color), layout.generateBlock(backgroundColor: color))
                        }
                    }
                }
            }
        }
        XCTAssertNotNil(fixture("Visible background").generateBlock(backgroundColor: .black).1)
        XCTAssertNil(fixture("\n").generateBlock(backgroundColor: .black).1)
    }

    func testRangeBlockPixelsAtEveryUnicodeBoundary() {
        let text = "a👩🏽‍🚀e\u{0301}\nשלום\nline"
        for alignment in [NSTextAlignment.left, .center, .right] {
            let layout = fixture(text, width: 65, alignment: alignment)
            for start in 0...text.utf16.count {
                for end in start...text.utf16.count {
                    let range = NSRange(location: start, length: end - start)
                    assertEqual(layout.legacyGenerateBlock(for: range, backgroundColor: .blue), layout.generateBlock(for: range, backgroundColor: .blue))
                }
            }
        }
    }

    func testSeededGeometryTruncationCutoutsAndRemeasurement() {
        var seed: UInt64 = 0xB10C261016
        func random(_ limit: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(limit))
        }
        let words = ["abc", "\n", "\r\n", "👩🏽‍💻", "שלום", "مرحبا", "中", "e\u{0301}"]
        for iteration in 0..<200 {
            let text = (0..<1 + random(60)).map { _ in words[random(words.count)] }.joined(separator: " ")
            let layout = fixture(text, width: CGFloat(30 + random(300)), alignment: [.left, .center, .right][random(3)], maximumLines: iteration % 3 == 0 ? 3 : .max, cutout: iteration % 2 == 0 ? TextViewCutout(topLeft: NSSize(width: 12, height: 30)) : nil)
            assertEqual(layout.legacyGenerateBlock(backgroundColor: .red), layout.generateBlock(backgroundColor: .red))
            for (index, line) in layout.lines.enumerated() {
                line.frame.origin.x += CGFloat(index % 3) * 0.5
                line.penFlush = [0, 0.5, 1][index % 3]
            }
            layout.lines.reverse()
            assertEqual(layout.legacyGenerateBlock(backgroundColor: .red), layout.generateBlock(backgroundColor: .red))
            layout.measure(width: 80)
            assertEqual(layout.legacyGenerateBlock(backgroundColor: .red), layout.generateBlock(backgroundColor: .red))
            layout.setAttributedString(NSAttributedString(string: "new\ntext", attributes: [.font: NSFont.systemFont(ofSize: 13)]))
            layout.measure(width: 100)
            assertEqual(layout.legacyGenerateBlock(backgroundColor: .red), layout.generateBlock(backgroundColor: .red))
        }
    }

    func testWholeBlockDoesNotCreateTemporaryAttributedSubstrings() {
        let text = BlockCountingString(NSAttributedString(string: "one\n\ntwo\nthree", attributes: [.font: NSFont.systemFont(ofSize: 14)]))
        let layout = TextViewLayout(text)
        layout.measure(width: 120)
        text.substringCount = 0
        let before = layout.legacyGenerateBlock(backgroundColor: .black)
        XCTAssertEqual(text.substringCount, layout.lines.count)
        text.substringCount = 0
        let after = layout.generateBlock(backgroundColor: .black)
        XCTAssertEqual(text.substringCount, 0)
        assertEqual(before, after)
    }
}
