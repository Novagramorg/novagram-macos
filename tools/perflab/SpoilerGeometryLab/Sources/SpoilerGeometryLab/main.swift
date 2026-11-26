import Cocoa
import CryptoKit
import TGUIKit

initializeLab()
let kinds = ["plain", "one", "sparse", "dense", "wrapped", "rtl", "emoji", "empty"]

func makeLayout(_ kind: String, revealed: Bool) -> TextViewLayout {
    let text: String
    switch kind {
    case "empty": text = ""
    case "sparse": text = String(repeating: "hidden visible ", count: 32)
    case "dense": text = String(repeating: "hidden visible ", count: 16)
    case "rtl": text = String(repeating: "مرحبا שלום English ", count: 6)
    case "emoji": text = String(repeating: "👨‍👩‍👧‍👦 👩🏽‍💻 🦆 🇦🇪 🙂 visible ", count: 3)
    case "wrapped": text = String(repeating: "A long hidden paragraph with words ", count: 8)
    default: text = "Hello with styled text and a second line\nMore text 👩🏽‍💻"
    }
    let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
    var ranges: [NSRange] = []
    switch kind {
    case "one": ranges = [NSRange(location: 0, length: 10)]
    case "sparse": ranges = [NSRange(location: value.length - 15, length: 6)]
    case "dense": ranges = stride(from: 0, to: value.length, by: 15).map { NSRange(location: $0, length: 6) }
    case "wrapped": ranges = [NSRange(location: 10, length: value.length - 20)]
    case "rtl", "emoji": ranges = [NSRange(location: 0, length: value.length / 2)]
    default: break
    }
    for range in ranges { value.addAttribute(TextInputAttributes.spoiler, value: true, range: range) }
    let layout = TextViewLayout(value, cutout: TextViewCutout(topLeft: NSSize(width: 20, height: 20)), alignment: kind == "rtl" ? .right : .left, isSpoilerRevealed: revealed)
    layout.measure(width: 340)
    return layout
}

if CommandLine.arguments.contains("--preview") {
    final class Document: NSView { override var isFlipped: Bool { true } }
    final class PreviewDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    }
    NSApp.setActivationPolicy(.regular)
    let delegate = PreviewDelegate()
    NSApp.delegate = delegate
    let window = Window(contentRect: NSRect(x: 0, y: 0, width: 410, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    window.backgroundColor = .white
    window.title = "Spoiler geometry: select text and click to reveal"
    let scroll = NSScrollView(frame: window.contentView!.bounds)
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    let document = Document(frame: .zero)
    var y: CGFloat = 20
    for kind in kinds where kind != "empty" {
        let view = TextView()
        let layout = makeLayout(kind, revealed: false)
        view.update(layout, origin: NSPoint(x: 20, y: y))
        document.addSubview(view)
        y += layout.layoutSize.height + 35
    }
    document.frame.size = NSSize(width: 390, height: y)
    scroll.documentView = document
    window.contentView?.addSubview(scroll)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    withExtendedLifetime((window, delegate)) { NSApp.run() }
    exit(0)
}
let snapshotMode = CommandLine.arguments.contains("--snapshots")
let outputPath = CommandLine.arguments.last!
precondition(outputPath.hasSuffix(".json"))
func context(scale: CGFloat) -> CGContext {
    let result = CGContext(data: nil, width: 1200, height: 1200, bitsPerComponent: 8, bytesPerRow: 4800, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    result.scaleBy(x: scale, y: scale)
    result.translateBy(x: 5, y: 5)
    return result
}
var snapshots: [String: String] = [:]
var results: [[String: Any]] = []
for kind in kinds {
    for revealed in [false, true] {
        let layout = makeLayout(kind, revealed: revealed)
        let view = TextView()
        view.update(layout)
        view.layoutSubtreeIfNeeded()
        if snapshotMode {
            let length = layout.attributedString.length
            let ranges = [NSRange(location: NSNotFound, length: 0), NSRange(location: 0, length: 0), NSRange(location: min(3, length), length: min(8, max(0, length - 3))), NSRange(location: 0, length: length)]
            for scale in [CGFloat(1), 2, 3] {
                System.updateScaleFactor(scale)
                for (index, range) in ranges.enumerated() {
                    layout.selectedRange = TextSelectedRange(range: range)
                    let ctx = context(scale: scale)
                    view.draw(view.drawingLayer, in: ctx)
                    let data = Data(bytes: ctx.data!, count: 5760000)
                    if revealed && length > 0 { precondition(data.contains { $0 != 0 }) }
                    snapshots["\(kind)-\(revealed)-\(scale)-\(index)"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                }
            }
        } else if kind != "empty" {
            System.updateScaleFactor(2)
            let ctx = context(scale: 2)
            for _ in 0..<100 { view.draw(view.drawingLayer, in: ctx) }
            var trials: [Double] = []
            for _ in 0..<9 {
                let start = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<500 { view.draw(view.drawingLayer, in: ctx) }
                trials.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 500)
            }
            results.append(["kind": kind, "revealed": revealed, "median_ns": trials.sorted()[4], "trials_ns": trials])
        }
    }
}
let output: [String: Any] = snapshotMode ? ["snapshots": snapshots] : ["results": results, "iterations_per_batch": 500, "batches": 9]
try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(snapshotMode ? snapshots.count : results.count) results to \(outputPath)")
