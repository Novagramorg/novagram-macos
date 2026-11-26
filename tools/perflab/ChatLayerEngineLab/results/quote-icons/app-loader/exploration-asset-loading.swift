import AppKit
import QuartzCore
import CryptoKit

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
let bundle = Bundle(path: CommandLine.arguments[1])!
func loadResource() -> NSImage { bundle.image(forResource: NSImage.Name("Icon_CopyCode"))! }
let template = loadResource()
var proposed = NSRect(origin: .zero, size: template.size)
let raw = template.cgImage(forProposedRect: &proposed, context: nil, hints: nil)!
func bitmapWidth(_ image: NSImage) -> Int {
    var rect = NSRect(origin: .zero, size: image.size)
    return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!.width
}
let operations: [(String, () -> Int)] = [
    ("resource_only", { Int(loadResource().size.width) }),
    ("copy_only", { Int((template.copy() as! NSImage).size.width) }),
    ("resource_bitmap", { bitmapWidth(loadResource()) }),
    ("copy_bitmap", { bitmapWidth(template.copy() as! NSImage) }),
    ("retained_bitmap", { bitmapWidth(template) }),
    ("raw_wrapper_bitmap", { bitmapWidth(NSImage(cgImage: raw, size: template.size)) })
]
var timings = [String: [Double]](), sink = 0
if ProcessInfo.processInfo.environment["ASSET_PROBE_FUNCTIONAL_ONLY"] != "1" {
for (_, op) in operations { for _ in 0..<100 { sink += op() } }
for batch in 0..<9 {
    for i in batch % 2 == 0 ? Array(operations.indices) : Array(operations.indices.reversed()) {
        let (name, op) = operations[i]
        let start = CACurrentMediaTime()
        for _ in 0..<5000 { autoreleasepool { sink += op() } }
        timings[name, default: []].append((CACurrentMediaTime() - start) * 1e6 / 5000)
    }
}
}
func pixelDigest(_ image: NSImage, scale: CGFloat) -> String {
    let width = Int(ceil(image.size.width * scale)), height = Int(ceil(image.size.height * scale))
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()
    return SHA256.hash(data: Data(bytes: ctx.data!, count: width * height * 4)).map { String(format: "%02x", $0) }.joined()
}
var comparisons = [[String: Any]]()
for scale: CGFloat in [1, 2, 3] {
    let fresh = loadResource(), copied = template.copy() as! NSImage
    comparisons.append(["scale": scale, "equal": pixelDigest(fresh, scale: scale) == pixelDigest(copied, scale: scale)])
}
var mutations = [[String: Any]]()
for mode in ["resource", "copy"] {
    func make() -> NSImage { mode == "resource" ? loadResource() : template.copy() as! NSImage }
    for mutation in ["size", "template", "remove_rep", "rep_size"] {
        let a = make(), b = make()
        let before = pixelDigest(b, scale: 2)
        let repShared = a.representations.first === b.representations.first
        let oldSize = a.size, oldTemplate = a.isTemplate
        let reps = a.representations, repSize = reps.first?.size
        switch mutation {
        case "size": a.size = NSSize(width: 25, height: 27)
        case "template": a.isTemplate = !a.isTemplate
        case "remove_rep": if let rep = a.representations.first { a.removeRepresentation(rep) }
        case "rep_size": a.representations.first?.size = NSSize(width: 29, height: 31)
        default: break
        }
        mutations.append(["mode": mode, "mutation": mutation, "rep_shared_before": repShared, "peer_pixels_unchanged": before == pixelDigest(b, scale: 2), "peer_width": b.size.width, "peer_template": b.isTemplate, "peer_rep_width": b.representations.first?.size.width ?? -1])
        a.size = oldSize; a.isTemplate = oldTemplate
        if let size = repSize { reps.first?.size = size }
        if mutation == "remove_rep" { reps.forEach { a.addRepresentation($0) } }
    }
}
let result: [String: Any] = ["unit": "microseconds_per_operation", "batches": timings, "pixels": comparisons, "mutations": mutations, "sink": sink, "source_representation_class": String(describing: type(of: template.representations[0]))]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
