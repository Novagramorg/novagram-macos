import Cocoa
import XCTest
import ObjectiveC
import Darwin
@testable import PathReference
@testable import PathCandidate

final class PathBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["STICKER_PATH_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in path timings") }
        let reverse = ProcessInfo.processInfo.environment["STICKER_PATH_REVERSE"] == "1"
        let cases: [(String, String)] = [
            ("integer_lines", "M 0 0 " + (0..<60).map { "L \(($0 * 17) % 80) \(($0 * 31) % 80)" }.joined(separator: " ") + " z"),
            ("integer_curves", "M 0 0 " + (0..<40).map { "c 12 -9 30 8 \($0 % 63) 20" }.joined(separator: " ") + " z"),
            ("fractional_curves", "M 0 0 " + (0..<40).map { "c 12.125 -9.5 30.25 8.75 \($0 % 63).125 20.6" }.joined(separator: " ") + " z"),
            ("long_numeric", "M 0 0 " + Array(repeating: "L 99999999999999.125 -9007199254740993", count: 40).joined(separator: " ") + " z"),
            ("exponents", "M 0 0 " + Array(repeating: "C 1e-3 2e2 3.5e1 4e-1 3e1 5e1", count: 40).joined(separator: " ") + " z"),
            ("short", "M 0 0 L 30 0 30 30 0 30 z")
        ]
        var results: [String: [[Double]]] = [:]
        var sink = 0
        for (name, input) in cases {
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                for variant in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                    autoreleasepool {
                        let start = CACurrentMediaTime()
                        for _ in 0..<300 {
                            if variant == 0 { sink += PathReference.PathDataReader(input: input).read().count }
                            else { sink += PathCandidate.PathDataReader(input: input).read().count }
                        }
                        batches[variant].append((CACurrentMediaTime() - start) * 1e6 / 300)
                    }
                }
            }
            results["parse_" + name] = batches
        }
        let a = PathReference.PathDataReader(input: "M 0 0"), b = PathCandidate.PathDataReader(input: "M 0 0")
        let sizes = ["runtime": [class_getInstanceSize(object_getClass(a)!), class_getInstanceSize(object_getClass(b)!)], "allocator": [malloc_size(Unmanaged.passUnretained(a).toOpaque()), malloc_size(Unmanaged.passUnretained(b).toOpaque())]]
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_parse", "reverse": reverse, "batches": results, "reader_bytes": sizes], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/sticker-path-benchmark.json"))
    }
}
