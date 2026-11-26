import Foundation
import XCTest
@testable import DecodeReference
@testable import DecodeCandidate

struct DecodeRandom {
    var state: UInt64 = 0xabcdef
    mutating func next(_ limit: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 32) % UInt64(limit))
    }
}

final class DecodeTests: XCTestCase {
    func testEveryByteAndPair() {
        XCTAssertEqual(DecodeCandidate.decodeStickerThumbnailData(Data()), "Mz")
        for first in UInt8.min...UInt8.max {
            let data = Data([first])
            XCTAssertEqual(DecodeReference.decodeStickerThumbnailData(data), DecodeCandidate.decodeStickerThumbnailData(data))
            XCTAssertEqual(DecodeReference.decodeStickerThumbnailData(data), DecodeCandidate.decodeFallbackForLab(data))
            XCTAssertEqual(DecodeReference.decodeStickerThumbnailData(data).utf8.count, DecodeCandidate.decodeLengthForLab(data))
            for second in UInt8.min...UInt8.max {
                let data = Data([first, second])
                XCTAssertEqual(DecodeReference.decodeStickerThumbnailData(data), DecodeCandidate.decodeStickerThumbnailData(data))
                XCTAssertEqual(DecodeReference.decodeStickerThumbnailData(data), DecodeCandidate.decodeFallbackForLab(data))
                XCTAssertEqual(DecodeReference.decodeStickerThumbnailData(data).utf8.count, DecodeCandidate.decodeLengthForLab(data))
            }
        }
    }
    func testRandomPayloadsAndSlicedData() {
        var random = DecodeRandom()
        for iteration in 0..<5000 {
            let source = Data((0..<(1 + random.next(1024))).map { _ in UInt8(random.next(256)) })
            let lower = random.next(source.count), upper = lower + random.next(source.count - lower + 1)
            let data = iteration % 2 == 0 ? source : source[lower..<upper]
            XCTAssertEqual(DecodeReference.decodeStickerThumbnailData(data), DecodeCandidate.decodeStickerThumbnailData(data))
            XCTAssertEqual(DecodeReference.decodeStickerThumbnailData(data), DecodeCandidate.decodeFallbackForLab(data))
            XCTAssertEqual(DecodeReference.decodeStickerThumbnailData(data).utf8.count, DecodeCandidate.decodeLengthForLab(data))
        }
    }
    func testBridgedDataAndAllByteOrderings() {
        for count in [0, 1, 15, 16, 31, 32, 255, 256, 1024, 65536] {
            for mode in 0..<3 {
                let bytes = (0..<count).map { UInt8(mode == 0 ? $0 % 256 : mode == 1 ? 255 - $0 % 256 : 170) }
                let data = bytes.withUnsafeBytes { Data(referencing: NSData(bytes: $0.baseAddress, length: $0.count)) }
                XCTAssertEqual(DecodeReference.decodeStickerThumbnailData(data), DecodeCandidate.decodeStickerThumbnailData(data))
                XCTAssertEqual(DecodeReference.decodeStickerThumbnailData(data), DecodeCandidate.decodeFallbackForLab(data))
                XCTAssertEqual(DecodeReference.decodeStickerThumbnailData(data).utf8.count, DecodeCandidate.decodeLengthForLab(data))
            }
        }
    }
}
