import AppKit

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)

let bundle = Bundle(path: CommandLine.arguments[1])!
var images: [NSImage] = []
var bitmaps: [CGImage] = []
for _ in 0..<100 {
    let image = bundle.image(forResource: NSImage.Name("Icon_CopyCode"))!
    images.append(image)
    var rect = NSRect(origin: .zero, size: image.size)
    bitmaps.append(image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!)
}
let result: [String: Any] = ["asset_loader": "Xcode-generated Bundle.image(forResource:)", "loads": images.count, "nsimage_identities": Set(images.map(ObjectIdentifier.init)).count, "cgimage_identities": Set(bitmaps.map(ObjectIdentifier.init)).count, "image_width": images[0].size.width, "image_height": images[0].size.height, "bitmap_width": bitmaps[0].width, "bitmap_height": bitmaps[0].height, "bitmap_bytes_per_row": bitmaps[0].bytesPerRow]
print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8)!)
