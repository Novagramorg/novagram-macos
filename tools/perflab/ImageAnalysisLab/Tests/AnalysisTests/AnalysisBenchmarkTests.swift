import AppKit
import QuartzCore
import XCTest
import func TGUIKit.imageRequiresInversion
@testable import func TGUIKit.imageHasTransparency
import func TGUIKitBaseline.imageRequiresInversion
@testable import func TGUIKitBaseline.imageHasTransparency

final class AnalysisBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["IMAGE_ANALYSIS_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in image analysis timing") }
        let reverse = ProcessInfo.processInfo.environment["IMAGE_ANALYSIS_REVERSE"] == "1"
        let cases: [(String, Int, Int, Int)] = [("small_dark_logo", 32, 32, 0), ("dark_logo", 128, 128, 0), ("large_dark_logo", 512, 512, 0), ("wide_dark_logo", 2048, 32, 0), ("opaque_black", 128, 128, 1), ("opaque_white", 128, 128, 2), ("empty", 128, 128, 3), ("white_logo", 128, 128, 4), ("colorful_logo", 128, 128, 5)]
        var output: [String: [[Double]]] = [:]
        var decisions: [String: [Bool]] = [:]
        var sink = 0
        for (name, width, height, mode) in cases {
            let image = try fixture(width: width, height: height) { x, y in
                if mode == 1 { return .black }
                if mode == 2 { return .white }
                if mode == 3 { return .clear }
                if x < width / 4 || x >= width * 3 / 4 || y < height / 4 || y >= height * 3 / 4 { return .clear }
                return mode == 4 ? .white : mode == 5 ? Pixel(0, 160, 255) : .black
            }
            for transparencyOnly in [false, true] {
                let key = name + (transparencyOnly ? "_alpha" : "_inversion")
                let old: () -> Bool = { transparencyOnly ? TGUIKitBaseline.imageHasTransparency(image) : TGUIKitBaseline.imageRequiresInversion(image) }
                let new: () -> Bool = { transparencyOnly ? TGUIKit.imageHasTransparency(image) : TGUIKit.imageRequiresInversion(image) }
                decisions[key] = [old(), new()]
                for _ in 0..<5 { sink += old() ? 1 : 0; sink += new() ? 1 : 0 }
                let iterations = width > 512 ? 32 : 128
                var batches = [[Double](), [Double]()]
                for batch in 0..<9 {
                    for variant in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                        autoreleasepool {
                            let start = CACurrentMediaTime()
                            if variant == 0 { for _ in 0..<iterations { sink += old() ? 1 : 0 } }
                            else { for _ in 0..<iterations { sink += new() ? 1 : 0 } }
                            batches[variant].append((CACurrentMediaTime() - start) * 1e6 / Double(iterations))
                        }
                    }
                }
                output[key] = batches
            }
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "reverse": reverse, "batches": output, "decisions": decisions], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/image-analysis-benchmark.json"))
    }
}
