@testable import class TGUIKit.PathDataReader
@testable import class TGUIKit.PathSegment
@testable import func TGUIKit.renderPath
@testable import func TGUIKit.decodeStickerThumbnailData
@testable import class TGUIKitBaseline.PathDataReader
@testable import class TGUIKitBaseline.PathSegment
@testable import func TGUIKitBaseline.renderPath
@testable import func TGUIKitBaseline.decodeStickerThumbnailData
import Cocoa
import XCTest

struct SegmentSignature: Equatable {
    let type: String
    let values: [UInt64]
}
func signature(_ segments: [TGUIKitBaseline.PathSegment]) -> [SegmentSignature] {
    segments.map { SegmentSignature(type: String(describing: $0.type), values: $0.data.map(\.bitPattern)) }
}
func signature(_ segments: [TGUIKit.PathSegment]) -> [SegmentSignature] {
    segments.map { SegmentSignature(type: String(describing: $0.type), values: $0.data.map(\.bitPattern)) }
}
func pathPixels(scale: Int, variant: Int, draw: (CGContext) -> Void) -> [UInt8] {
    let width = 96 * scale, height = 96 * scale
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.setFillColor(CGColor(red: 0.13, green: 0.2, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        if variant == 1 { context.translateBy(x: 0.25, y: 0.75); context.scaleBy(x: 0.81, y: 1.03) }
        if variant == 2 { context.translateBy(x: 92, y: 92); context.scaleBy(x: -0.9, y: -0.9) }
        context.setFillColor(CGColor(red: 0.9, green: 0.4, blue: 0.15, alpha: variant == 0 ? 1 : 0.45))
        context.addRect(CGRect(x: 3, y: 3, width: 12, height: 11))
        draw(context)
    }
    return bytes
}
struct PathRandom {
    var value: UInt64 = 0x12345678
    mutating func next(_ limit: Int) -> Int {
        value = value &* 6364136223846793005 &+ 1442695040888963407
        return Int((value >> 32) % UInt64(limit))
    }
}

final class PathTests: XCTestCase {
    func testNumberConversionsAndRecoveryMatchBitForBit() {
        let values = ["0", "-0", "00", "-00", "1", "-1", "63", "-63", "999999999999999", "9007199254740991", "9007199254740993", "18446744073709551615", "000000000000000000001", ".5", "-.5", "1.", "-0.0", "1.234567890123456789", "-999999999999999.1", "1e-3", "1e300", "1e999", "-1e-999", "1e+3", "1E3", "1e-", "1e2e3", "-", ".", "-.", "--1", "1.2.3", "1-2", "1,2", "0x1", "nan", "∞", "١٢", "\u{00a0}1"]
        var count = 0
        for command in ["M", "m", "L", "l", "C", "c", "S", "s", "Q", "q", "T", "t", "A", "a", "H", "h", "V", "v"] {
            for value in values {
                for ending in ["", " L 2 3 z", " 1 0 1 12 24 M 1 2"] {
                    let input = "M 1 2 " + command + " " + value + " 4 5 6 7 8" + ending
                    XCTAssertTrue(signature(TGUIKitBaseline.PathDataReader(input: input).read()) == signature(TGUIKit.PathDataReader(input: input).read()), input)
                    count += 1
                }
            }
        }
        XCTAssertEqual(count, 2106)
    }

    func testRandomGrammarAndDecoderParity() {
        var random = PathRandom()
        let tokens = ["M", "m", "L", "l", "C", "c", "S", "s", "Q", "q", "A", "a", "H", "V", "z", "Z", " ", ",", "\n", "-", ".", "e", "E", "+", "0", "1", "2", "3", "4", "9"]
        for _ in 0..<10000 {
            var input = "M 0 0 "
            for _ in 0..<random.next(120) { input += tokens[random.next(tokens.count)] }
            input += " L 10 20 z"
            XCTAssertTrue(signature(TGUIKitBaseline.PathDataReader(input: input).read()) == signature(TGUIKit.PathDataReader(input: input).read()), input)
        }
        for _ in 0..<2000 {
            let data = Data((0..<random.next(200)).map { _ in UInt8(random.next(256)) })
            let a = TGUIKitBaseline.decodeStickerThumbnailData(data), b = TGUIKit.decodeStickerThumbnailData(data)
            XCTAssertEqual(a, b)
            XCTAssertTrue(signature(TGUIKitBaseline.PathDataReader(input: a).read()) == signature(TGUIKit.PathDataReader(input: b).read()))
        }
    }

    func testDrawingPixelsAndFillBoundariesMatch() {
        let paths = [
            "M 4 4 60 4 60 60 4 60 z",
            "m 4 4 60 0 0 60 -60 0 z",
            "M 2 2 L 70 2 70 70 2 70 z M 15 15 L 85 15 85 85 15 85 z",
            "M 10 10 C 20 0 40 80 50 50 60 20 80 60 90 10 S 80 70 50 80 10 60 5 5 z",
            "m 10 10 c 10 -10 30 70 40 40 s 20 20 40 -40 l -70 30 z",
            "M 5 5 H 90 V 80 h -60 v -70 z l 30 40 10 10 z",
            "M 5.25 6.75 L 80.125 5.5 85.5 80.75 3.25 82.125 z z",
            "M 12 12 L 20 20 S 40 80 80 20 z M 20 20 C 10 10 50 10 50 50 L 40 30 S 30 50 5 5 z",
            "M 1 1 z z M 10 10 C 30 30 40 40 50 50 z"
        ]
        var pairs = 0
        for input in paths {
            let a = TGUIKitBaseline.PathDataReader(input: input).read(), b = TGUIKit.PathDataReader(input: input).read()
            for scale in [1, 2, 3] {
                for variant in 0..<3 {
                    let old = pathPixels(scale: scale, variant: variant) { TGUIKitBaseline.renderPath(a, context: $0) }
                    let new = pathPixels(scale: scale, variant: variant) { TGUIKit.renderPath(b, context: $0) }
                    XCTAssertTrue(old == new, input)
                    pairs += 1
                }
            }
        }
        XCTAssertEqual(pairs, 81)
    }

    func testPackedSegmentArraysAndTrailingValuesMatch() {
        let a: [TGUIKitBaseline.PathSegment] = [
            .init(type: .M, data: [2, 2, 70, 2, 70, 70, 2, 70, 99]), .init(type: .z),
            .init(type: .m, data: [5, 5, 20, 0, 0, 20, -20, 0, 99]), .init(type: .z),
            .init(type: .M, data: [10, 10]), .init(type: .C, data: [30, 0, 50, 80, 60, 60, 70, 30, 80, 40, 90, 20, 1, 2]), .init(type: .S, data: [80, 90, 60, 90, 10, 20, 5, 5, 1]), .init(type: .z),
            .init(type: .m, data: [5, 5]), .init(type: .c, data: [10, -10, 20, 30, 40, 40, 10, 0, 20, -10, 30, -40, 1]), .init(type: .s, data: [-10, -10, -30, 30, -10, -10, -20, -20, 1]), .init(type: .l, data: [2, 4, 5, 8, 1]), .init(type: .L, data: [20, 20, 30, 40, 1]), .init(type: .z)
        ]
        let b: [TGUIKit.PathSegment] = a.map { source in
            let type: TGUIKit.PathSegment.SegmentType
            switch source.type {
            case .M: type = .M
            case .m: type = .m
            case .C: type = .C
            case .c: type = .c
            case .S: type = .S
            case .s: type = .s
            case .L: type = .L
            case .l: type = .l
            default: type = .z
            }
            return .init(type: type, data: source.data)
        }
        for scale in [1, 2, 3] {
            for variant in 0..<3 {
                XCTAssertTrue(pathPixels(scale: scale, variant: variant) { TGUIKitBaseline.renderPath(a, context: $0) } == pathPixels(scale: scale, variant: variant) { TGUIKit.renderPath(b, context: $0) })
            }
        }
    }

    func testReaderOwnsItsInputThroughTheIterator() {
        let source = (0..<1000).map { "L \($0) \($0 + 1)" }.joined(separator: " ")
        let reader: TGUIKit.PathDataReader = autoreleasepool { TGUIKit.PathDataReader(input: "M 0 0 " + source + " z") }
        XCTAssertEqual(reader.read().count, 1002)
        XCTAssertTrue(reader.read().isEmpty)
    }
}
