import Cocoa
import CryptoKit
import TGUIKit

initializeLab()
let snapshotMode = CommandLine.arguments.contains("--snapshots")
let outputPath = CommandLine.arguments.last!
precondition(outputPath.hasSuffix(".json"))

func attributedText(_ kind: String) -> NSAttributedString {
    let text: String
    switch kind {
    case "short": text = "12:34"
    case "emoji": text = "👨‍👩‍👧‍👦 👩🏽‍💻 🦆 🇦🇪 🙂"
    case "rtl": text = "مرحبا بالعالم English שלום"
    case "cjk": text = "中文 日本語 한글 café ffi"
    case "empty": text = ""
    case "many-runs": text = String(repeating: "abc ", count: 32)
    default: text = "Hello with styled text and a second line\nMore text 👩🏽‍💻"
    }
    let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black, .selectedColor: NSColor.white])
    if value.length > 0 {
        let range = NSRange(location: 0, length: min(10, value.length))
        switch kind {
        case "underline": value.addAttribute(.underlineStyle, value: 1, range: range)
        case "strike": value.addAttribute(.strikethroughStyle, value: 1, range: range)
        case "colored": value.addAttributes([.foregroundColor: NSColor.red, .font: NSFont.boldSystemFont(ofSize: 18)], range: range)
        case "spoiler": value.addAttribute(TextInputAttributes.spoiler, value: true, range: range)
        case "embedded": value.addAttribute(TextInputAttributes.embedded, value: "emoji", range: range)
        case "many-runs":
            for index in stride(from: 0, to: value.length, by: 4) {
                value.addAttribute(.foregroundColor, value: index % 8 == 0 ? NSColor.blue : NSColor.red, range: NSRange(location: index, length: 4))
            }
        default: break
        }
    }
    return value
}

func context(scale: CGFloat) -> CGContext {
    let result = CGContext(data: nil, width: 1200, height: 480, bitsPerComponent: 8, bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    result.scaleBy(x: scale, y: scale)
    result.translateBy(x: 5, y: 5)
    return result
}

func digest(_ context: CGContext, nonemptyExpected: Bool) -> String {
    let data = Data(bytes: context.data!, count: 2304000)
    if nonemptyExpected { precondition(data.contains { $0 != 0 }) }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

let kinds = ["short", "plain", "emoji", "rtl", "cjk", "colored", "underline", "strike", "spoiler", "embedded", "many-runs", "empty"]
var snapshots: [String: String] = [:]
var results: [[String: Any]] = []
for kind in kinds {
    let text = attributedText(kind)
    let layout = TextViewLayout(text, maximumNumberOfLines: 4, cutout: TextViewCutout(topLeft: NSSize(width: 20, height: 20)), alignment: kind == "rtl" ? .right : .left)
    layout.measure(width: 340)
    if kind == "colored" { layout.selectedRange = TextSelectedRange(range: NSRange(location: 0, length: 6)) }
    let view = TextView()
    view.update(layout)
    view.layoutSubtreeIfNeeded()
    if snapshotMode {
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for limit in [Int?.none, 0, 1, 4, 100000] {
                layout.maxGlyphDrawCount = limit
                let ctx = context(scale: scale)
                view.draw(view.drawingLayer, in: ctx)
                snapshots["view-\(kind)-\(scale)-\(limit.map(String.init) ?? "all")"] = digest(ctx, nonemptyExpected: limit == nil && text.length > 0)
            }
            for selected in [false, true] {
                let pair = TextNode.layoutText(text, nil, 4, .end, NSSize(width: 340, height: 150), nil, selected, .left)
                let ctx = context(scale: scale)
                pair.1.draw(NSRect(origin: .zero, size: pair.0.size), in: ctx, backingScaleFactor: scale, backgroundColor: .clear)
                snapshots["node-\(kind)-\(scale)-\(selected)"] = digest(ctx, nonemptyExpected: text.length > 0)
            }
        }
    } else if kind != "empty" {
        System.updateScaleFactor(2)
        let ctx = context(scale: 2)
        let pair = TextNode.layoutText(text, nil, 4, .end, NSSize(width: 340, height: 150), nil, false, .left)
        for target in ["view", "node"] {
            func draw() {
                if target == "view" { view.draw(view.drawingLayer, in: ctx) }
                else { pair.1.draw(NSRect(origin: .zero, size: pair.0.size), in: ctx, backingScaleFactor: 2, backgroundColor: .clear) }
            }
            for _ in 0..<100 { draw() }
            var trials: [Double] = []
            for _ in 0..<9 {
                let start = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<2000 { draw() }
                trials.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 2000)
            }
            results.append(["kind": kind, "target": target, "median_ns": trials.sorted()[4], "trials_ns": trials])
        }
    }
}
let output: [String: Any] = snapshotMode ? ["snapshots": snapshots] : ["results": results, "iterations_per_batch": 2000, "batches": 9]
try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(snapshotMode ? snapshots.count : results.count) results to \(outputPath)")
