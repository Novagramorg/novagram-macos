@testable import func TGUIKit.decodeFallbackForLab
@testable import func TGUIKit.decodeStickerThumbnailData
@testable import func TGUIKitBaseline.decodeStickerThumbnailData
import Foundation
import QuartzCore
import XCTest
import Darwin

final class DecodeBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["STICKER_DECODE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in decoder timings") }
        let reverse = ProcessInfo.processInfo.environment["STICKER_DECODE_REVERSE"] == "1"
        var results: [String: [[Double]]] = [:]
        var sink = 0
        let cases: [(String, Data)] = [("empty", Data()), ("one", Data([10])), ("short", Data([0, 128, 203, 50, 128, 203, 50, 178, 203, 0, 178])), ("mixed_64", Data((0..<64).map { UInt8(($0 * 17) % 256) })), ("mixed_256", Data((0..<256).map { UInt8(($0 * 17) % 256) })), ("mixed_1024", Data((0..<1024).map { UInt8(($0 * 17) % 256) })), ("commands", Data((0..<256).map { UInt8(192 + $0 % 64) })), ("numbers", Data((0..<256).map { UInt8($0 % 192) }))]
        for (name, input) in cases {
            var batches = [[Double](), [Double](), [Double]()]
            for batch in 0..<9 {
                for variant in ((batch % 2 == 0) != reverse ? [0, 1, 2] : [2, 1, 0]) {
                    autoreleasepool {
                        let start = CACurrentMediaTime()
                        for _ in 0..<1000 {
                            let result = variant == 0 ? TGUIKitBaseline.decodeStickerThumbnailData(input) : variant == 1 ? TGUIKit.decodeStickerThumbnailData(input) : TGUIKit.decodeFallbackForLab(input)
                            sink += result.utf8.count
                        }
                        batches[variant].append((CACurrentMediaTime() - start) * 1e6 / 1000)
                    }
                }
            }
            results[name] = batches
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["variants": ["original", "native", "fallback"], "unit": "microseconds_per_decode", "reverse": reverse, "batches": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/sticker-decode-benchmark.json"))
    }
}
