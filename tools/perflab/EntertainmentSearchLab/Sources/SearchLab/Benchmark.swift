import Foundation

public func runSearchBenchmark(queryCount: Int = 100) -> String {
    let queries = (0..<queryCount).map { String(UnicodeScalar(0x1f600 + $0)!) }
    let items = (0..<10_000).map { String(UnicodeScalar(0x1f600 + ($0 % 300))!) }
    let iterations = 20
    func measure(_ body: () -> Int) -> (Double, Int) {
        var timings: [Double] = []
        var count = 0
        for _ in 0..<9 {
            let start = ProcessInfo.processInfo.systemUptime
            count = body()
            timings.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        return (timings.sorted()[timings.count / 2], count)
    }
    let baseline = measure {
        var count = 0
        for _ in 0..<iterations {
            for item in items where queries.contains(item) { count += 1 }
        }
        return count
    }
    let candidate = measure {
        var count = 0
        for _ in 0..<iterations {
            let index = PanelEmojiSearchIndex(queries)
            for item in items where index.contains(item) { count += 1 }
        }
        return count
    }
    precondition(baseline.1 == candidate.1)
    let result: [String: Any] = [
        "workload": "\(queryCount) emoji keys, 10000 installed items, 20 renders, median of 9 runs",
        "baseline_ms": baseline.0,
        "candidate_ms": candidate.0,
        "speedup": baseline.0 / candidate.0,
        "matching_items": candidate.1,
        "os": ProcessInfo.processInfo.operatingSystemVersionString
    ]
    return String(data: try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!
}
