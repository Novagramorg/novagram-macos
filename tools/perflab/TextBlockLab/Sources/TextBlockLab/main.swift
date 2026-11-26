import Cocoa
import CryptoKit
import TGUIKit

initializeLab()
NSApp.setActivationPolicy(.accessory)
let snapshotMode = CommandLine.arguments.contains("--snapshots")
let outputPath = CommandLine.arguments.last!
precondition(outputPath.hasSuffix(".json"))
let kinds = ["empty", "newline", "short", "wrapped", "styled", "many_lines", "rtl", "emoji"]

func makeLayout(_ kind: String, alignment: NSTextAlignment = .left) -> TextViewLayout {
    let text: String
    switch kind {
    case "empty": text = ""
    case "newline": text = "\n\n\n"
    case "short": text = "A short poll question"
    case "wrapped": text = String(repeating: "A quoted paragraph with text that wraps around to the next line. ", count: 12)
    case "styled": text = String(repeating: "Styled text has many attributes. ", count: 32)
    case "many_lines": text = Array(repeating: "Text line\n\nAnother line", count: 32).joined(separator: "\n")
    case "rtl": text = String(repeating: "مرحبا שלום English\n", count: 8)
    default: text = String(repeating: "👩🏽‍🚀 🇺🇦 café 中\n", count: 8)
    }
    let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
    if kind == "styled" {
        for index in stride(from: 0, to: value.length, by: 2) {
            value.addAttribute(.foregroundColor, value: index % 4 == 0 ? NSColor.red : NSColor.blue, range: NSRange(location: index, length: min(2, value.length - index)))
        }
    }
    let layout = TextViewLayout(value, alignment: alignment)
    layout.measure(width: 280)
    return layout
}

func hashImage(_ image: CGImage?) -> String {
    guard let image else { return "nil" }
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    context.clear(rect)
    context.draw(image, in: rect)
    let data = Data(bytes: context.data!, count: image.width * image.height * 4)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

var results: [[String: Any]] = []
var checksum = 0
let iterations = 300
for scale in snapshotMode ? [CGFloat(1), 2, 3] : [CGFloat(2)] {
    System.updateScaleFactor(scale)
    for kind in kinds {
        for alignment in snapshotMode ? [NSTextAlignment.left, .center, .right] : [NSTextAlignment.left] {
            let layout = makeLayout(kind, alignment: alignment)
            for mode in ["whole", "range"] {
                func draw() -> (CGPoint, CGImage?) {
                    if mode == "whole" { return layout.generateBlock(backgroundColor: NSColor.black.withAlphaComponent(0.4)) }
                    let length = layout.attributedString.length
                    let start = length / 4
                    return layout.generateBlock(for: NSRange(location: start, length: length / 2), backgroundColor: NSColor.black.withAlphaComponent(0.4))
                }
                let sample = draw()
                var result: [String: Any] = ["kind": kind, "mode": mode, "scale": scale, "alignment": alignment.rawValue, "lines": layout.lines.count, "image_sha256": hashImage(sample.1), "width": sample.1?.width ?? 0, "height": sample.1?.height ?? 0, "x": sample.0.x, "y": sample.0.y]
                if !snapshotMode {
                    func measure() -> Double {
                        let start = DispatchTime.now().uptimeNanoseconds
                        for _ in 0..<iterations {
                            autoreleasepool {
                                let output = draw()
                                checksum &+= output.1?.width ?? 1
                            }
                        }
                        return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations) / 1000
                    }
                    _ = measure()
                    let trials = (0..<9).map { _ in measure() }
                    result["trials_us"] = trials
                    result["median_us"] = trials.sorted()[4]
                }
                results.append(result)
            }
        }
    }
}
let output: [String: Any] = ["iterations_per_batch": iterations, "batches": 9, "checksum": checksum, "snapshot_mode": snapshotMode, "results": results]
let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: outputPath))
print("Saved \(results.count) results to \(outputPath)")
