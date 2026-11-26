import XCTest
import AppKit
import CoreText
import Baseline
@testable import Candidate

final class TextLayoutLabTests: XCTestCase {
    let texts = ["", "Hello world", "office AVATAR ffi fi fl To Wa", "First line\nSecond line\r\nThird\n", "a\tb\tTabbed text   ", "مرحبا بالعالم العربية 123 mixed Latin", "שלום עולם hello 123", "हिन्दी नमस्ते दुनिया", "中文日本語 한국어 줄바꿈", "🙂👩🏽‍💻👨‍👩‍👧‍👦🇦🇪 text ✨", "e\u{301} café a\u{200d}b", "no\u{00a0}break soft\u{00ad}hyphen zero\u{200b}width", String(repeating: "A linked paragraph with several words and whitespace. ", count: 24)]

    func compare(_ text: String, style: Int, width: CGFloat, maximum: Int32, truncation: CTLineTruncationType = .end, cutout: Int = 0, alignment: NSTextAlignment = .left, bigEmoji: Bool = false, spacing: CGFloat? = nil, saveRTL: Bool = false, pixels: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        let oldCutout = cutout == 0 ? nil : Baseline.TextViewCutout(topLeft: cutout == 1 ? CGSize(width: 28, height: 45) : nil, topRight: cutout == 2 ? CGSize(width: 24, height: 30) : nil, bottomRight: cutout == 3 ? CGSize(width: 35, height: 20) : nil)
        let newCutout = cutout == 0 ? nil : Candidate.TextViewCutout(topLeft: cutout == 1 ? CGSize(width: 28, height: 45) : nil, topRight: cutout == 2 ? CGSize(width: 24, height: 30) : nil, bottomRight: cutout == 3 ? CGSize(width: 35, height: 20) : nil)
        let old = Baseline.TextViewLayout(Baseline.input(text, style: style), maximumNumberOfLines: maximum, truncationType: truncation, cutout: oldCutout, alignment: alignment, strokeLinks: true, disableTooltips: false)
        let new = Candidate.TextViewLayout(Candidate.input(text, style: style), maximumNumberOfLines: maximum, truncationType: truncation, cutout: newCutout, alignment: alignment, strokeLinks: true, disableTooltips: false)
        old.measure(width: width + 31, isBigEmoji: bigEmoji, lineSpacing: spacing, saveRTL: saveRTL)
        new.measure(width: width + 31, isBigEmoji: bigEmoji, lineSpacing: spacing, saveRTL: saveRTL)
        XCTAssertEqual(old.signature, new.signature, "initial measurement", file: file, line: line)
        old.measure(width: width, isBigEmoji: bigEmoji, lineSpacing: spacing, saveRTL: saveRTL)
        new.measure(width: width, isBigEmoji: bigEmoji, lineSpacing: spacing, saveRTL: saveRTL)
        XCTAssertEqual(old.signature, new.signature, "style=\(style) width=\(width) max=\(maximum) text=\(text.prefix(40))", file: file, line: line)
        if pixels { XCTAssertEqual(old.pixels(), new.pixels(), file: file, line: line) }
        for y in stride(from: CGFloat(-10), through: max(1,old.layoutSize.height)+10, by: 9) {
            XCTAssertEqual(old.findIndex(location: CGPoint(x: 12, y: y)), new.findIndex(location: CGPoint(x: 12, y: y)), file: file, line: line)
        }
    }

    func testUnicodeWrappingAndTruncation() {
        for text in texts {
            for width: CGFloat in [1, 35, 150, 400] {
                for maximum: Int32 in [0, 1, 3] {
                    for truncation in [CTLineTruncationType.start, .middle, .end] {
                        compare(text, style: 0, width: width, maximum: maximum, truncation: truncation)
                    }
                }
            }
        }
    }

    func testRichAttributesAndDecorations() {
        for style in 1 ... 6 {
            for text in [texts[1], texts[5], texts[9], texts.last!] {
                for width: CGFloat in [40, 180, 350] {
                    for maximum: Int32 in [0, 1, 3] {
                        compare(text, style: style, width: width, maximum: maximum)
                    }
                }
            }
        }
    }

    func testCutoutsAlignmentSpacingAndEmoji() {
        for cutout in 0 ... 3 {
            for alignment in [NSTextAlignment.left, .center, .right] {
                for style in [0, 1, 3, 5] {
                    compare(texts.last!, style: style, width: 160, maximum: 0, cutout: cutout, alignment: alignment, bigEmoji: true, spacing: 5.5, saveRTL: true)
                }
            }
        }
    }

    func testCoreTextPixelsMatch() {
        for text in [texts[2], texts[5], texts[8], texts[9], texts[10], texts.last!] {
            for style in 0 ... 6 {
                compare(text, style: style, width: 220, maximum: 0, pixels: true)
                compare(text, style: style, width: 220, maximum: 2, pixels: true)
            }
        }
    }

    func testRandomizedLayouts() {
        var seed: UInt64 = 817236
        func next(_ upper: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1; return Int((seed >> 32) % UInt64(upper)) }
        let tokens = ["hello ", "🙂 ", "مرحبا ", "שלום ", "日本語 ", "\n", "e\u{301} ", "\t", "👩🏽‍💻", "AV fi "]
        for _ in 0 ..< 1000 {
            let text = (0 ..< next(45)).map { _ in tokens[next(tokens.count)] }.joined()
            compare(text, style: next(7), width: CGFloat(30+next(450)), maximum: [0,1,2,4][next(4)], truncation: [.start,.middle,.end][next(3)], cutout: next(4), alignment: [.left,.center,.right][next(3)], bigEmoji: next(2)==0, spacing: next(2)==0 ? nil : CGFloat(next(7)), saveRTL: next(2)==0)
        }
    }

    func testRepeatedMeasurementObservesMutableInput() {
        let oldInput = NSMutableAttributedString(attributedString: Baseline.input(texts.last!, style: 1))
        let newInput = NSMutableAttributedString(attributedString: Candidate.input(texts.last!, style: 1))
        let old = Baseline.TextViewLayout(oldInput, strokeLinks: true, disableTooltips: false)
        let new = Candidate.TextViewLayout(newInput, strokeLinks: true, disableTooltips: false)
        for width: CGFloat in [80, 230, 0, 130, 400, 80] {
            old.measure(width: width); new.measure(width: width)
            XCTAssertEqual(old.signature,new.signature)
            for value in [oldInput,newInput] {
                value.replaceCharacters(in: NSRange(location: 0, length: 5), with: "ABCDE")
                value.addAttribute(.font,value: NSFont.systemFont(ofSize: width == 80 ? 20 : 12),range: NSRange(location: 0,length: 20))
            }
        }
    }

    func testRangeIndexAgainstFullIntersection() {
        var seed: UInt64 = 27
        func next(_ upper: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1; return Int((seed >> 32) % UInt64(upper)) }
        for _ in 0 ..< 1000 {
            var position = 0
            let ranges: [NSRange] = (0 ..< next(100)).map { _ in
                let length = next(50)
                defer { position += length + next(3) }
                return NSRange(location: position, length: length)
            }
            let index = TextViewLineRangeIndex(ranges)
            for _ in 0 ..< 20 {
                let query = NSRange(location: next(max(1,position+20)), length: next(100))
                let expected = ranges.indices.filter { NSIntersectionRange(ranges[$0],query).length > 0 }
                let actual = index.candidates(intersecting: query).filter { NSIntersectionRange(ranges[$0],query).length > 0 }
                XCTAssertEqual(expected,actual)
            }
        }
    }

    func testRangeIndexFallsBackForTruncatedOrUnorderedRanges() {
        for ranges in [[NSRange(location: 0,length: 10),NSRange(location: 10,length: 10),NSRange(location: 0,length: 100)], [NSRange(location: 40,length: 10),NSRange(location: 0,length: 20)]] {
            let index = TextViewLineRangeIndex(ranges)
            for location in 0 ... 100 {
                let query = NSRange(location: location,length: 3)
                XCTAssertEqual(index.candidates(intersecting: query).filter { NSIntersectionRange(query,ranges[$0]).length>0 },ranges.indices.filter { NSIntersectionRange(query,ranges[$0]).length>0 })
            }
        }
        XCTAssertEqual(TextViewLineRangeIndex([NSRange(location: Int.max,length: 1)]).candidates(intersecting: NSRange(location: 0,length: 1)),0 ..< 1)
    }
    func testMutableParagraphStylesAndUnknownAttributesDoNotGoStale() {
        let oldStyle = NSMutableParagraphStyle(), newStyle = NSMutableParagraphStyle()
        let text = String(repeating: "Mutable attributed text with tabs\tand wrapping. ", count: 8)
        let oldInput = NSMutableAttributedString(attributedString: Baseline.input(text))
        let newInput = NSMutableAttributedString(attributedString: Candidate.input(text))
        oldInput.addAttribute(.paragraphStyle, value: oldStyle, range: NSRange(location: 0, length: oldInput.length))
        newInput.addAttribute(.paragraphStyle, value: newStyle, range: NSRange(location: 0, length: newInput.length))
        let old = Baseline.TextViewLayout(oldInput), new = Candidate.TextViewLayout(newInput)
        for indent: CGFloat in [0, 10, 40, 5, 0] {
            oldStyle.firstLineHeadIndent = indent; newStyle.firstLineHeadIndent = indent
            oldInput.addAttribute(.paragraphStyle,value:oldStyle,range:NSRange(location:0,length:oldInput.length))
            newInput.addAttribute(.paragraphStyle,value:newStyle,range:NSRange(location:0,length:newInput.length))
            old.measure(width: 230); new.measure(width: 230)
            XCTAssertEqual(old.signature, new.signature)
        }
    }

    func testPreparedTextOnlyReusesImmutableAttributeValues() {
        func cache(_ value: Any) -> TextViewPreparedText {
            let source = NSAttributedString(string: String(repeating: "x",count: 100),attributes: [.font: NSFont.systemFont(ofSize: 13),NSAttributedString.Key("test"):value])
            return TextViewPreparedText(source: source, attributedString: source, typesetter: CTTypesetterCreateWithAttributedString(source), needsRunDecorations: false)
        }
        for value: Any in [NSFont.systemFont(ofSize: 13), NSColor.red, NSNumber(value: 4), "constant", NSParagraphStyle.default] {
            let prepared = cache(value)
            XCTAssertTrue(prepared.matches(prepared.source))
        }
        for value: Any in [NSMutableString(string: "mutable"), NSObject(), NSColor.labelColor] {
            let prepared = cache(value)
            XCTAssertFalse(prepared.matches(prepared.source), "value=\(type(of: value)) stored=\(type(of: prepared.source.attribute(NSAttributedString.Key("test"),at:0,effectiveRange:nil)!))")
        }
    }

    func testRepeatedMeasureRecomputesAllGeometryOptions() {
        let old = Baseline.TextViewLayout(Baseline.input(texts.last!,style: 1), strokeLinks: true, disableTooltips: false)
        let new = Candidate.TextViewLayout(Candidate.input(texts.last!,style: 1), strokeLinks: true, disableTooltips: false)
        for index in 0 ..< 10 {
            old.maximumNumberOfLines = Int32(index % 4); new.maximumNumberOfLines = Int32(index % 4)
            old.penFlush = CGFloat(index % 3)/2; new.penFlush = CGFloat(index % 3)/2
            old.cutout = .init(topLeft: CGSize(width: index*3,height: 40))
            new.cutout = .init(topLeft: CGSize(width: index*3,height: 40))
            old.dropLayoutSize(); new.dropLayoutSize()
            old.lines.removeAll(); new.lines.removeAll()
            old.measure(width: 250, isBigEmoji: index%2==0,lineSpacing: CGFloat(index),saveRTL:index%2==0)
            new.measure(width: 250, isBigEmoji: index%2==0,lineSpacing: CGFloat(index),saveRTL:index%2==0)
            XCTAssertEqual(old.signature,new.signature)
        }
    }

    func testStringReplacementAndCacheLengthBoundaries() {
        let old = Baseline.TextViewLayout(Baseline.input("initial")), new = Candidate.TextViewLayout(Candidate.input("initial"))
        for length in [0,63,64,100,4096,4097,64] {
            let text = String(repeating:"word ",count:length/5)+String(repeating:"x",count:length%5)
            old.setAttributedString(Baseline.input(text)); new.setAttributedString(Candidate.input(text))
            for width: CGFloat in [180,300,180] {
                old.measure(width: width); new.measure(width: width)
                XCTAssertEqual(old.signature,new.signature)
            }
        }
    }

    func testIndependentLayoutsCanMeasureConcurrently() {
        let lock = NSLock()
        var mismatches = 0
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let text = String(repeating: "Parallel Unicode مرحبا 👩🏽‍💻 text ", count: 10)
            let old = Baseline.TextViewLayout(Baseline.input(text,style:index%3)), new = Candidate.TextViewLayout(Candidate.input(text,style:index%3))
            for width: CGFloat in [120,230,180] {
                old.measure(width: width); new.measure(width: width)
                if old.signature != new.signature { lock.lock(); mismatches += 1; lock.unlock() }
            }
        }
        XCTAssertEqual(mismatches,0)
    }

    func testPixelsAndHitTestingAfterTypesetterReuse() {
        for text in [String(repeating: texts[5]+" ",count:8), String(repeating:texts[9]+" ",count:8), String(repeating:texts[10]+" ",count:10), texts.last!] {
            for style in 0 ... 6 {
                let old = Baseline.TextViewLayout(Baseline.input(text,style:style),strokeLinks:true,disableTooltips:false)
                let new = Candidate.TextViewLayout(Candidate.input(text,style:style),strokeLinks:true,disableTooltips:false)
                for width: CGFloat in [180,230,180] {
                    old.measure(width:width);new.measure(width:width)
                    XCTAssertEqual(old.signature,new.signature)
                    XCTAssertEqual(old.pixels(),new.pixels())
                }
            }
        }
    }

    func testSequentialMeasurementAcrossQueues() {
        let text = String(repeating:"Queue migration مرحبا 👩🏽‍💻 text ",count:20)
        let old = Baseline.TextViewLayout(Baseline.input(text)), new = Candidate.TextViewLayout(Candidate.input(text))
        let queues = [DispatchQueue(label:"layout.first"),DispatchQueue(label:"layout.second")]
        for index in 0 ..< 20 {
            queues[index%2].sync {
                old.measure(width:CGFloat(100+index*10)); new.measure(width:CGFloat(100+index*10))
                XCTAssertEqual(old.signature,new.signature)
            }
        }
    }

    func testParagraphStylesWithMutableChildrenAreNotReused() {
        let style = NSMutableParagraphStyle()
        style.textBlocks = [NSTextBlock()]
        let source = NSAttributedString(string:String(repeating:"paragraph ",count:20),attributes:[.font:NSFont.systemFont(ofSize:13),.paragraphStyle:style])
        let prepared = TextViewPreparedText(source:source,attributedString:source,typesetter:CTTypesetterCreateWithAttributedString(source),needsRunDecorations:false)
        XCTAssertFalse(prepared.matches(source))
    }

    func testFontsKerningLigaturesAndParagraphTabs() {
        let text = String(repeating:"AVATAR office ffi fi To Wa café مرحبا\twords ",count:8)
        let fonts = [NSFont.systemFont(ofSize:11), NSFont.systemFont(ofSize:18,weight:.bold), NSFont(name:"Menlo",size:14)!, NSFont(name:"TimesNewRomanPSMT",size:16)!]
        for font in fonts {
            for kern in [-0.5,0.0,1.5] {
                let paragraph = NSMutableParagraphStyle()
                paragraph.firstLineHeadIndent = 12
                paragraph.defaultTabInterval = 40
                let attributes: [NSAttributedString.Key:Any] = [.font:font,.kern:kern,.ligature:1,.paragraphStyle:paragraph]
                let input = NSAttributedString(string:text,attributes:attributes)
                let old = Baseline.TextViewLayout(input), new = Candidate.TextViewLayout(input)
                for width: CGFloat in [160,220,340] {
                    old.measure(width:width);new.measure(width:width)
                    XCTAssertEqual(old.signature,new.signature)
                    XCTAssertEqual(old.pixels(),new.pixels())
                }
            }
        }
    }

}
