@testable import func TGUIKit.decodeFallbackForLab
@testable import func TGUIKit.decodeStickerThumbnailData
@testable import func TGUIKitBaseline.decodeStickerThumbnailData
import Foundation
import XCTest
import Darwin

private func allocatedDecodeBytes() -> Int {
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(nil, &statistics)
    return Int(statistics.size_in_use)
}

final class DecodeMemoryTests: XCTestCase {
    func testRetainedStringStorage() throws {
        guard ProcessInfo.processInfo.environment["STICKER_DECODE_MEMORY"] == "1" else { throw XCTSkip("Opt-in allocator observations") }
        var results: [String: [[[Int]]]] = [:]
        var sink = 0
        for length in [1, 16, 64, 256, 1024] {
            let input = Data((0..<length).map { UInt8(($0 * 17) % 256) })
            for _ in 0..<100 {
                sink += TGUIKitBaseline.decodeStickerThumbnailData(input).utf8.count
                sink += TGUIKit.decodeStickerThumbnailData(input).utf8.count
            }
            var variants = [[[Int]](), [[Int]](), [[Int]]()]
            for batch in 0..<5 {
                for variant in batch % 2 == 0 ? [0, 1, 2] : [2, 1, 0] {
                    autoreleasepool {
                        var strings = [String](); strings.reserveCapacity(2000)
                        let before = allocatedDecodeBytes()
                        for _ in 0..<2000 {
                            strings.append(variant == 0 ? TGUIKitBaseline.decodeStickerThumbnailData(input) : variant == 1 ? TGUIKit.decodeStickerThumbnailData(input) : TGUIKit.decodeFallbackForLab(input))
                        }
                        let retained = withExtendedLifetime(strings) { allocatedDecodeBytes() }
                        sink += strings.reduce(0) { $0 + $1.utf8.count }
                        strings.removeAll(keepingCapacity: true)
                        let released = allocatedDecodeBytes()
                        variants[variant].append([retained - before, released - before])
                    }
                }
            }
            results[String(length)] = variants
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["variants": ["original", "native", "fallback"], "retained_count": 2000, "delta_bytes": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/sticker-decode-memory.json"))
    }
}
