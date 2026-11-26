import XCTest
import Cocoa
@testable import TGUIKit

final class TextHitTestingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func layout(_ text: String, width: CGFloat = 180, alignment: NSTextAlignment = .left, cutout: TextViewCutout? = nil) -> TextViewLayout {
        let layout = TextViewLayout(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black]), alignment: alignment)
        layout.cutout = cutout
        layout.measure(width: width)
        return layout
    }

    func testMeasuredTextMatchesLegacyAtLineEdgesAndOutsideText() {
        for text in ["Short", "First line\nSecond line\n\nFourth line", String(repeating: "Wrapping text 👨‍👩‍👧‍👦 café 中文 שלום مرحبا ", count: 12)] {
            for alignment in [NSTextAlignment.left, .center, .right] {
                for cutout in [TextViewCutout?.none, TextViewCutout(topLeft: NSSize(width: 40, height: 40)), TextViewCutout(topRight: NSSize(width: 30, height: 65))] {
                    let value = layout(text, alignment: alignment, cutout: cutout)
                    for line in value.lines {
                        let rect = line.frame
                        for x in [-100, rect.minX, rect.midX, rect.maxX, rect.maxX + 100] {
                            for y in [rect.minY - 5 - 0.01, rect.minY - 5, rect.minY - 5 + 0.01, rect.midY, rect.maxY, rect.maxY + 100, 0, CGFloat.greatestFiniteMagnitude] {
                                let point = NSPoint(x: x, y: y)
                                XCTAssertEqual(value.findIndex(location: point), value.legacyFindIndex(location: point))
                            }
                        }
                    }
                }
            }
        }
    }

    func testMutableOverlappingAndUnorderedLineFramesMatchLegacy() {
        let value = layout(String(repeating: "line\n", count: 128))
        let allLines = value.lines
        var seed: UInt64 = 0xAD98
        func random(_ limit: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(limit))
        }
        for _ in 0..<500 {
            value.lines = Array(allLines.prefix(1 + random(120)))
            for (index, line) in value.lines.enumerated() {
                if index > 0 && random(5) == 0 {
                    line.frame = value.lines[index - 1].frame
                } else {
                    line.frame = NSRect(x: Double(random(300) - 100) / 2, y: Double(random(1000) - 200) / 2, width: Double(random(300)), height: Double(random(50)))
                }
            }
            for _ in 0..<100 {
                let point = NSPoint(x: Double(random(600) - 200), y: Double(random(1500) - 500))
                XCTAssertEqual(value.findIndex(location: point), value.legacyFindIndex(location: point))
            }
        }
    }

    func testNonfiniteCoordinatesPreserveLegacyFallbacks() {
        let value = layout("first\nsecond\nthird\nfourth")
        for frame in [CGRect.zero, .null, .infinite, CGRect(x: CGFloat.nan, y: 20, width: 10, height: 10), CGRect(x: 20, y: CGFloat.nan, width: 10, height: 10)] {
            value.lines[1].frame = frame
            for point in [NSPoint(x: 5, y: 20), NSPoint(x: -1, y: CGFloat.infinity), NSPoint(x: CGFloat.nan, y: 15), NSPoint(x: 10, y: CGFloat.nan)] {
                XCTAssertEqual(value.findIndex(location: point), value.legacyFindIndex(location: point))
            }
        }
    }

    func testEmptyAndUnmeasuredTextHasNoHit() {
        for value in [layout(""), TextViewLayout(NSAttributedString(string: "Not measured yet"))] {
            XCTAssertTrue(value.lines.isEmpty)
            for point in [NSPoint.zero, NSPoint(x: 20, y: 20), NSPoint(x: 0, y: CGFloat.greatestFiniteMagnitude)] {
                XCTAssertEqual(value.findIndex(location: point), -1)
                XCTAssertEqual(value.findCharacterIndex(at: point), -1)
                XCTAssertNil(value.link(at: point))
                XCTAssertNil(value.formattedDate(at: point))
                XCTAssertNil(value.block(at: point))
                value.selectWord(at: point)
                value.selectAll(at: point)
                XCTAssertEqual(value.selectedRange.range.location, NSNotFound)
            }
        }
    }

    func testLinksAndDragSelectionStillResolveTheSameLines() {
        let text = NSMutableAttributedString(string: "First link\nSecond link\nThird link", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        text.addAttribute(.link, value: "first", range: NSRange(location: 0, length: 10))
        text.addAttribute(.link, value: "second", range: NSRange(location: 11, length: 11))
        let value = TextViewLayout(text)
        value.measure(width: 250)
        XCTAssertEqual(value.lines.count, 3)
        for (index, expected) in ["first", "second"].enumerated() {
            let point = NSPoint(x: 3, y: value.lines[index].frame.minY - 5)
            XCTAssertEqual(value.findIndex(location: point), index)
            XCTAssertEqual(value.link(at: point)?.0 as? String, expected)
        }
        let start = NSPoint(x: 0, y: value.lines[0].frame.minY - 5)
        let end = NSPoint(x: 240, y: value.lines[2].frame.minY - 5)
        XCTAssertEqual(value.selectedRange(startPoint: start, currentPoint: end), text.range)
        XCTAssertEqual(value.selectedRange(startPoint: end, currentPoint: start), text.range)
    }

    func testLinksFollowRenderedOffsetsForQuotesAlignmentAndCutouts() throws {
        var comparisons = 0
        for prefix in ["let", "אבג", "مرح"] {
            for alignment in [NSTextAlignment.left, .center, .right] {
                for cutout in [TextViewCutout?.none, TextViewCutout(topLeft: NSSize(width: 40, height: 40)), TextViewCutout(topRight: NSSize(width: 30, height: 65))] {
                    for quoted in [false, true] {
                        let source = NSMutableAttributedString(string: prefix + " other text\nA considerably longer second line to establish alignment space.", attributes: [.font: NSFont.systemFont(ofSize: 14)])
                        source.addAttribute(.link, value: "target", range: NSRange(location: 0, length: (prefix as NSString).length))
                        if quoted {
                            source.addAttribute(TextInputAttributes.quote, value: TextViewBlockQuoteData(id: 0, colors: .init(main: .blue)), range: NSRange(location: 0, length: source.length))
                        }
                        let value = TextViewLayout(source, cutout: cutout, alignment: alignment)
                        value.measure(width: 400)
                        let line = try XCTUnwrap(value.lines.first)
                        var origin = CGFloat(CTLineGetPenOffsetForFlush(line.line, line.penFlush, Double(value.layoutSize.width))) + line.frame.minX
                        if value.penFlush == 0.5, line.penFlush != 0.5 { origin = line.frame.minX }
                        if line.penFlush == 1, let size = cutout?.topRight, line.frame.maxY <= size.height { origin -= size.width }
                        if quoted && line.isRTL { origin -= 20 + 4 * 2 }
                        let start = CTLineGetOffsetForStringIndex(line.line, 0, nil)
                        let end = CTLineGetOffsetForStringIndex(line.line, (prefix as NSString).length, nil)
                        let point = NSPoint(x: origin + (start + end) / 2, y: line.frame.minY - 5)
                        XCTAssertEqual(value.link(at: point)?.0 as? String, "target", "prefix=\(prefix), alignment=\(alignment), quote=\(quoted), cutout=\(String(describing: cutout))")
                        XCTAssertNil(value.link(at: NSPoint(x: origin - 1, y: point.y)))
                        comparisons += 1
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 54)
    }

    func testEmptyTextMouseDownPassesToParentAndSelectionDrawingIsSafe() {
        final class Parent: NSView {
            var mouseDownCount = 0
            override func mouseDown(with event: NSEvent) { mouseDownCount += 1 }
        }
        let parent = Parent(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        let view = TextView(frame: parent.bounds)
        let value = layout("")
        view.update(value)
        parent.addSubview(view)
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        view.mouseDown(with: event)
        XCTAssertEqual(parent.mouseDownCount, 1)
        value.selectedRange.range = NSRange(location: 0, length: 0)
        let context = CGContext(data: nil, width: 200, height: 80, bitsPerComponent: 8, bytesPerRow: 800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        view.draw(view.drawingLayer, in: context)
        XCTAssertFalse(Data(bytes: context.data!, count: 64000).contains { $0 != 0 })
    }
}
