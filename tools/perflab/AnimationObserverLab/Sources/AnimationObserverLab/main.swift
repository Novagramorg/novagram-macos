import Cocoa
import TGUIKit

initializeLab()

final class CountingRow: TableRowView {
    var calls = 0
    var independentCalls = 0
    override func updateAnimatableContent() { calls += 1 }
    @objc func independent() { independentCalls += 1 }
}

let independentNotification = Notification.Name("AnimationObserverLab.independent")
let rowCount = 40
let iterations = 1000
var results: [[String: Any]] = []
for scenario in ["plain_unrelated_frame", "plain_unrelated_bounds", "plain_row_frame", "scroll_content_bounds", "scroll_document_frame"] {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 1600))
    var scroll: NSScrollView?
    if scenario.hasPrefix("scroll") {
        let view = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        view.documentView = root
        window.contentView = view
        scroll = view
    } else {
        window.contentView = root
    }
    let rows = (0..<rowCount).map { index -> CountingRow in
        let row = CountingRow(frame: NSRect(x: 0, y: index * 30, width: 300, height: 30))
        NotificationCenter.default.addObserver(row, selector: #selector(CountingRow.independent), name: independentNotification, object: nil)
        root.addSubview(row)
        return row
    }
    let unrelated = NSView()
    let name: Notification.Name
    let object: AnyObject
    switch scenario {
    case "plain_unrelated_frame": name = NSView.frameDidChangeNotification; object = unrelated
    case "plain_unrelated_bounds": name = NSView.boundsDidChangeNotification; object = unrelated
    case "plain_row_frame": name = NSView.frameDidChangeNotification; object = rows[0]
    case "scroll_content_bounds": name = NSView.boundsDidChangeNotification; object = scroll!.contentView
    default: name = NSView.frameDidChangeNotification; object = root
    }
    let center = NotificationCenter.default
    for _ in 0..<100 { center.post(name: name, object: object) }
    var trials: [Double] = []
    var counts: [Int] = []
    for _ in 0..<9 {
        rows.forEach { $0.calls = 0 }
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { center.post(name: name, object: object) }
        trials.append(Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations))
        counts.append(rows.reduce(0) { $0 + $1.calls })
    }
    rows.forEach { $0.independentCalls = 0 }
    center.post(name: independentNotification, object: nil)
    let independentCalls = rows.reduce(0) { $0 + $1.independentCalls }
    results.append(["scenario": scenario, "median_ns_per_post": trials.sorted()[4], "trials_ns": trials, "callbacks_per_batch": counts, "independent_callbacks": independentCalls])
    rows.forEach { $0.removeFromSuperview() }
    rows.forEach { $0.calls = 0 }
    center.post(name: name, object: object)
    precondition(rows.reduce(0) { $0 + $1.calls } == 0)
    window.contentView = nil
    window.close()
}
let path = CommandLine.arguments.last!
precondition(path.hasSuffix(".json"))
try JSONSerialization.data(withJSONObject: ["rows": rowCount, "posts_per_batch": iterations, "batches": 9, "results": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
print("Wrote observer measurements to \(path)")
