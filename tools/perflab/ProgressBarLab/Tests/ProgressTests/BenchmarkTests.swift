import Cocoa
import XCTest
import TGUIKit
import ProgressReference

extension ProgressTests {
    func testBenchmark() throws {
        guard ProcessInfo.processInfo.environment["PROGRESS_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        let count = 2000
        var checksum: CGFloat = 0
        var results: [[String: Any]] = []
        for scenario in ["cold", "progress", "ranges_unchanged", "ranges_churn", "layout", "playback"] {
            let (old, new) = pair()
            let begin = CACurrentMediaTime() + 100
            func run(_ candidate: Bool) -> Double {
                let start = CACurrentMediaTime()
                for i in 0..<count {
                    let bar: any ProgressBar
                    if scenario == "cold" {
                        if candidate { bar = LinearProgressControl(progressHeight: 4) }
                        else { bar = LegacyProgressControl(progressHeight: 4) }
                    } else {
                        if candidate { bar = new } else { bar = old }
                    }
                    switch scenario {
                    case "cold":
                        bar.frame = NSRect(x: 0, y: 0, width: 320, height: 30)
                        bar.progress(0.5)
                    case "progress":
                        bar.progress(CGFloat(i % 100) / 100)
                    case "ranges_unchanged", "ranges_churn":
                        bar.progress(scenario == "ranges_churn" && i % 2 == 0 ? 1 : 0.5)
                        bar.set(fetchingProgressRanges: [0..<1, 0.2..<0.8, 0.3..<0.9], animated: false)
                    case "layout":
                        bar.frame.size.width = CGFloat(200 + i % 200)
                    default:
                        bar.set(progress: 0.5, animated: true, duration: 100, beginTime: begin, offset: 50, speed: 1, seekId: 1, repeatForever: false)
                    }
                    checksum += bar.currentValue
                }
                return (CACurrentMediaTime() - start) * 1_000_000 / Double(count)
            }
            _ = run(false); _ = run(true)
            var before: [Double] = [], after: [Double] = []
            for batch in 0..<9 {
                if batch % 2 == 0 { before.append(run(false)); after.append(run(true)) }
                else { after.append(run(true)); before.append(run(false)) }
            }
            old.removeFromSuperview(); new.removeFromSuperview()
            results.append(["scenario": scenario, "baseline_us": before.sorted()[4], "candidate_us": after.sorted()[4], "baseline_trials_us": before, "candidate_trials_us": after])
        }
        XCTAssertGreaterThan(checksum, 0)
        let data = try JSONSerialization.data(withJSONObject: ["batches": 9, "iterations_per_batch": count, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/progress-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
