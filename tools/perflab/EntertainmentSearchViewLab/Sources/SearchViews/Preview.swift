import AppKit
import TGUIKit

public func writeSearchPreviews(directory: String, duckFile: String) throws {
    initializeSearchViewLab()
    NSApp.setActivationPolicy(.accessory)
    System.updateScaleFactor(2)
    let pixels = try Data(contentsOf: URL(fileURLWithPath: duckFile))
    let provider = CGDataProvider(data: pixels as CFData)!
    let duck = CGImage(width: 240, height: 240, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 960, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    for dark in [true, false] {
        for loading in [false, true] {
            let background = dark ? NSColor(srgbRed: 0.09, green: 0.14, blue: 0.18, alpha: 1) : NSColor.white
            let text = dark ? NSColor.white : NSColor.black
            let secondary = dark ? NSColor(srgbRed: 0.64, green: 0.71, blue: 0.77, alpha: 1) : NSColor.gray
            let window = NSWindow(contentRect: NSMakeRect(0, 0, 350, 550), styleMask: [.borderless], backing: .buffered, defer: false)
            let root = View(frame: NSMakeRect(0, 0, 350, 550))
            root.backgroundColor = background
            window.contentView = root
            let header = TextView(frame: .zero)
            let headerLayout = TextViewLayout(.initialize(string: "⌕   peppafe", color: text, font: .normal(16)))
            headerLayout.measure(width: 306)
            header.update(headerLayout)
            header.frame.origin = NSPoint(x: 22, y: 17)
            root.addSubview(header)
            let footer = TextView(frame: .zero)
            let footerLayout = TextViewLayout(.initialize(string: "Emoji     Stickers     GIFs", color: text, font: .medium(14)))
            footerLayout.measure(width: 320)
            footer.update(footerLayout)
            root.addSubview(footer)
            footer.centerX(y: 515)
            let status = PanelSearchStatusView(frame: NSMakeRect(0, 46, 350, 448))
            root.addSubview(status)
            status.update(status: loading ? .loading : .empty, kind: .stickers, title: "No Results Found", detail: "There were no results for “peppafe”.\nTry a new search.", loadingLabel: "Loading", backgroundColor: background, textColor: text, detailColor: secondary, reduceMotion: false, makeAnimation: {
                let container = View(frame: NSMakeRect(0, 0, 120, 120))
                let image = ImageView(frame: container.bounds)
                image.image = duck
                container.addSubview(image)
                return container
            })
            window.orderFront(nil)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
            root.layoutSubtreeIfNeeded()
            status.layoutSubtreeIfNeeded()
            root.displayIfNeeded()
            let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
            root.cacheDisplay(in: root.bounds, to: bitmap)
            let file = "\(dark ? "dark" : "light")-\(loading ? "loading" : "empty").png"
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent(file))
            window.orderOut(nil)
            withExtendedLifetime(window) {}
        }
    }
}
