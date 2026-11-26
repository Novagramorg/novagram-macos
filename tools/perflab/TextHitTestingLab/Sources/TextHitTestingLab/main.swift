import Cocoa
import TGUIKit

initializeLab()
var results: [[String: Any]] = []
var checksum = 0
let iterations = 20000
for lineCount in [1, 4, 20, 100, 500] {
    let text = NSAttributedString(string: Array(repeating: "A message with a link", count: lineCount).joined(separator: "\n"), attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
    let layout = TextViewLayout(text)
    layout.measure(width: 350)
    precondition(layout.lines.count == lineCount)
    for scenario in ["first_line", "middle_line", "outside_x", "below_text"] {
        let y = layout.lines[scenario == "first_line" ? 0 : lineCount / 2].frame.minY - 4
        let point = NSPoint(x: scenario == "outside_x" ? -100 : 20, y: scenario == "below_text" ? layout.layoutSize.height + 100 : y)
        precondition(layout.findIndex(location: point) == layout.legacyFindIndex(location: point))
        func measure(_ body: () -> Int) -> Double {
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<iterations { checksum &+= body() }
            return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations)
        }
        var baseline: [Double] = [], candidate: [Double] = []
        for i in 0..<9 {
            if i % 2 == 0 {
                baseline.append(measure { layout.legacyFindIndex(location: point) })
                candidate.append(measure { layout.findIndex(location: point) })
            } else {
                candidate.append(measure { layout.findIndex(location: point) })
                baseline.append(measure { layout.legacyFindIndex(location: point) })
            }
        }
        results.append(["lines": lineCount, "scenario": scenario, "baseline_ns": baseline.sorted()[4], "candidate_ns": candidate.sorted()[4], "speedup": baseline.sorted()[4] / candidate.sorted()[4], "eliminated_rectangle_array_bytes": lineCount * MemoryLayout<CGRect>.stride])
    }
}
precondition(checksum > 0)
let output: [String: Any] = ["iterations_per_batch": iterations, "batches": 9, "checksum": checksum, "results": results]
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
if let path = ProcessInfo.processInfo.environment["TEXT_HIT_RESULTS"] {
    try data.write(to: URL(fileURLWithPath: path))
}
print(String(data: data, encoding: .utf8)!)
