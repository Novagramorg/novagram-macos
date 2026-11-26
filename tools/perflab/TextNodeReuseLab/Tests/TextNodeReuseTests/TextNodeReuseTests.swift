import Cocoa
import XCTest
import TGUIKit
import Darwin
import ObjectiveC.runtime

final class TextNodeReuseTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func text(_ string: String = "A selected row") -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black, .selectedColor: NSColor.red])
    }

    private func layout(_ value: NSAttributedString?, node: TextNode? = nil, selected: Bool = false, spacing: CGFloat? = nil) -> (TextNodeLayout, TextNode) {
        TextNode.layoutText(maybeNode: node, value, nil, 0, .end, NSSize(width: 170, height: 300), nil, selected, .left, spacing)
    }

    func testRepeatedSelectedTextReusesMeasuredLayout() {
        for value in [text(), NSAttributedString(string: ""), NSAttributedString(string: "plain")] {
            let first = layout(value, selected: true)
            let second = layout(value, node: first.1, selected: true)
            XCTAssertTrue(first.0 === second.0)
            XCTAssertTrue(first.1 === second.1)
        }
    }

    func testChangingLineSpacingMatchesFreshLayout() throws {
        let value = text("one two three four five six seven eight nine ten")
        let first = layout(value, spacing: 0)
        let updated = layout(value, node: first.1, spacing: 8)
        let fresh = layout(value, spacing: 8)
        XCTAssertEqual(updated.0.size, fresh.0.size)
        XCTAssertEqual(try render(updated), try render(fresh))
    }

    func testMutatedInputTextMatchesFreshLayout() throws {
        let value = NSMutableAttributedString(attributedString: text("first"))
        let first = layout(value)
        value.replaceCharacters(in: NSRange(location: 0, length: value.length), with: "very different longer text")
        let updated = layout(value, node: first.1)
        let fresh = layout(value)
        XCTAssertEqual(updated.0.size, fresh.0.size)
        XCTAssertEqual(try render(updated), try render(fresh))
    }

    func testMutatedInputColorMatchesFreshDrawing() throws {
        let value = NSMutableAttributedString(attributedString: text())
        let first = layout(value)
        value.addAttribute(.foregroundColor, value: NSColor.blue, range: NSRange(location: 0, length: value.length))
        let updated = layout(value, node: first.1)
        let fresh = layout(value)
        XCTAssertEqual(try render(updated), try render(fresh))
    }

    func testSelectionRoundTripMatchesFreshDrawing() throws {
        let value = text()
        var current = layout(value)
        for selected in [true, true, false, false, true] {
            current = layout(value, node: current.1, selected: selected)
            let fresh = layout(value, selected: selected)
            XCTAssertEqual(current.0.size, fresh.0.size)
            XCTAssertEqual(try render(current), try render(fresh))
        }
    }

    func testZeroAndNilSpacingReuseAndNilTextReuse() {
        for value: NSAttributedString? in [nil, text()] {
            for selected in [false, true] {
                let first = layout(value, selected: selected)
                let second = layout(value, node: first.1, selected: selected, spacing: 0)
                XCTAssertTrue(first.0 === second.0)
                XCTAssertEqual(second.0.selected, selected)
            }
        }
    }

    func testChangingPublicSelectionFlagCannotRelabelRenderedText() throws {
        let value = text()
        let first = layout(value, selected: true)
        first.0.selected = false
        let second = layout(value, node: first.1, selected: false)
        XCTAssertFalse(first.0 === second.0)
        XCTAssertEqual(try render(second), try render(layout(value)))
    }

    func testEqualIndependentStringsReuseAndChangedSelectedColorInvalidates() throws {
        let first = layout(text(), selected: true)
        let same = layout(text(), node: first.1, selected: true)
        XCTAssertTrue(first.0 === same.0)
        let changed = NSMutableAttributedString(attributedString: text())
        changed.addAttribute(.selectedColor, value: NSColor.blue, range: NSRange(location: 0, length: changed.length))
        let next = layout(changed, node: first.1, selected: true)
        XCTAssertFalse(next.0 === same.0)
        XCTAssertEqual(try render(next), try render(layout(changed, selected: true)))
    }

    func testFreshAndReusedRenderingMatchesOriginalAcrossLayoutModes() throws {
        var pairs = 0
        for string in ["ordinary text", "A much longer piece of text with several words", "שלום עולם", "🎉 hello 🚀", "first line\nsecond line"] {
            let value = text(string)
            for selected in [false, true] {
                for mode in 0..<3 {
                    let size = NSSize(width: mode == 0 ? 70 : 160, height: 180)
                    let lines = [1, 3, 0][mode]
                    let truncation: CTLineTruncationType = [.end, .middle, .start][mode]
                    let alignment: NSTextAlignment = mode == 1 ? .center : .left
                    let spacing: CGFloat? = mode == 2 ? 6 : nil
                    let cutout: TextNodeCutout? = mode == 0 ? nil : TextNodeCutout(position: mode == 1 ? .TopLeft : .TopRight, size: NSSize(width: 20, height: 25))
                    let originalCutout: ReferenceTextNodeCutout? = mode == 0 ? nil : ReferenceTextNodeCutout(position: mode == 1 ? .TopLeft : .TopRight, size: NSSize(width: 20, height: 25))
                    let first = TextNode.layoutText(value, nil, lines, truncation, size, cutout, selected, alignment, spacing)
                    let repeated = TextNode.layoutText(maybeNode: first.1, value, nil, lines, truncation, size, cutout, selected, alignment, spacing)
                    let original = ReferenceTextNode.layoutText(value, nil, lines, truncation, size, originalCutout, selected, alignment, spacing)
                    XCTAssertTrue(first.0 === repeated.0)
                    XCTAssertEqual(repeated.0.size, original.0.size)
                    XCTAssertEqual(repeated.0.numberOfLines, original.0.numberOfLines)
                    for scale: CGFloat in [1, 2] {
                        let actual = try bitmap(size: repeated.0.size, scale: scale) { rect, context in
                            repeated.1.draw(rect, in: context, backingScaleFactor: scale, backgroundColor: .white)
                        }
                        let expected = try bitmap(size: original.0.size, scale: scale) { rect, context in
                            original.1.draw(rect, in: context, backingScaleFactor: scale, backgroundColor: .white)
                        }
                        XCTAssertEqual(actual, expected)
                        pairs += 1
                    }
                }
            }
        }
        XCTAssertEqual(pairs, 60)
    }

    func testReplacingLayoutReleasesOldLayout() {
        let node = TextNode()
        weak var oldLayout: TextNodeLayout?
        autoreleasepool {
            let first = layout(text("first"), node: node, selected: true)
            oldLayout = first.0
        }
        XCTAssertNotNil(oldLayout)
        _ = layout(text("second"), node: node, selected: true)
        XCTAssertNil(oldLayout)
    }

    func testChangedGeometryDoesNotReuseOldLayout() throws {
        let value = text("one two three four five six seven eight nine ten")
        let size = NSSize(width: 110, height: 200)
        for change in 0..<6 {
            let first = TextNode.layoutText(value, nil, 3, .end, size, nil, false, .left)
            let newSize = NSSize(width: change == 0 ? 170 : size.width, height: change == 1 ? 100 : size.height)
            let lines = change == 2 ? 1 : 3
            let truncation: CTLineTruncationType = change == 3 ? .middle : .end
            let cutout = change == 4 ? TextNodeCutout(position: .TopLeft, size: NSSize(width: 30, height: 25)) : nil
            let alignment: NSTextAlignment = change == 5 ? .center : .left
            let updated = TextNode.layoutText(maybeNode: first.1, value, nil, lines, truncation, newSize, cutout, false, alignment)
            let fresh = TextNode.layoutText(value, nil, lines, truncation, newSize, cutout, false, alignment)
            XCTAssertFalse(updated.0 === first.0)
            XCTAssertEqual(updated.0.size, fresh.0.size)
            XCTAssertEqual(try render(updated), try render(fresh))
        }
    }

    func testLayoutReuseBenchmark() throws {
        guard ProcessInfo.processInfo.environment["TEXTNODE_BENCHMARK"] != nil else { throw XCTSkip("Opt-in text layout reuse benchmark") }
        var report: [String: Any] = [:]
        for input in ["same", "equal", "mutable"] {
            for selected in [false, true] {
                for reuse in [false, true] {
                    let value = text("A chat search result title that can be truncated")
                    let request: NSAttributedString = input == "same" ? value : input == "equal" ? text(value.string) : NSMutableAttributedString(attributedString: value)
                    let original = ReferenceTextNode.layoutText(value, nil, 1, .end, NSSize(width: 170, height: 30), nil, selected, .left)
                    let candidate = TextNode.layoutText(value, nil, 1, .end, NSSize(width: 170, height: 30), nil, selected, .left)
                    var before: [Double] = [], after: [Double] = []
                    var checksum: CGFloat = 0
                    for batch in 0..<9 {
                        for current in batch % 2 == 0 ? [false, true] : [true, false] {
                            let elapsed = autoreleasepool { () -> Double in
                                let start = CACurrentMediaTime()
                                for _ in 0..<1000 {
                                    if current {
                                        let next = TextNode.layoutText(maybeNode: reuse ? candidate.1 : nil, request, nil, 1, .end, NSSize(width: 170, height: 30), nil, selected, .left)
                                        checksum += next.0.size.width
                                    } else {
                                        let next = ReferenceTextNode.layoutText(maybeNode: reuse ? original.1 : nil, request, nil, 1, .end, NSSize(width: 170, height: 30), nil, selected, .left)
                                        checksum += next.0.size.width
                                    }
                                }
                                return (CACurrentMediaTime() - start) * 1000
                            }
                            if current { after.append(elapsed) } else { before.append(elapsed) }
                        }
                    }
                    report["input=\(input),selected=\(selected),reuse=\(reuse)"] = ["original_ms_per_1000": before, "candidate_ms_per_1000": after]
                    XCTAssertGreaterThan(checksum, 0)
                }
            }
        }
        report["layout_instance_bytes"] = ["original": class_getInstanceSize(ReferenceTextNodeLayout.self), "candidate": class_getInstanceSize(TextNodeLayout.self)]
        let original = ReferenceTextNode.layoutText(text(), nil, 1, .end, NSSize(width: 170, height: 30), nil, true, .left)
        let candidate = layout(text(), selected: true)
        report["layout_allocation_bytes"] = ["original": malloc_size(Unmanaged.passUnretained(original.0).toOpaque()), "candidate": malloc_size(Unmanaged.passUnretained(candidate.0).toOpaque())]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/textnode-reuse-benchmark.json"))
    }

    private func bitmap(size: NSSize, scale: CGFloat, draw: (NSRect, CGContext) -> Void) throws -> Data {
        let width = Int(ceil(max(size.width, 1) * scale)), height = Int(ceil(max(size.height, 1) * scale))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        draw(NSRect(origin: .zero, size: size), context)
        let data = Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
        XCTAssertTrue(data.contains { $0 != 0 })
        return data
    }

    private func render(_ pair: (TextNodeLayout, TextNode)) throws -> Data {
        let width = 400, height = 600
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 2, y: 2)
        pair.1.draw(NSRect(origin: .zero, size: pair.0.size), in: context, backingScaleFactor: 2, backgroundColor: .white)
        let data = Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
        XCTAssertTrue(data.contains { $0 != 0 })
        return data
    }
}
