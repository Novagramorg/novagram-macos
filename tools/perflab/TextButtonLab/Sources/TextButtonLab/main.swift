import AppKit
import Darwin
import TGUIKit

func image(_ selected: Bool) -> CGImage {
    let context = CGContext(data: nil, width: 44, height: 44, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor((selected ? NSColor.systemBlue : NSColor.lightGray).cgColor)
    context.fillEllipse(in: CGRect(x: 2, y: 2, width: 40, height: 40))
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 12, y: 14, width: selected ? 20 : 8, height: 8))
    return context.makeImage()!
}

func allocatedBytes() -> Int {
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(nil, &statistics)
    return Int(statistics.size_in_use)
}

func elapsed(_ operation: () -> Void) -> Double {
    let start = CFAbsoluteTimeGetCurrent()
    operation()
    return (CFAbsoluteTimeGetCurrent() - start) * 1000
}

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
System.updateScaleFactor(2)
System.liquidGlass = false
let namedImages = ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"].map { name in
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.black.setFill()
        rect.insetBy(dx: 4, dy: 4).fill()
        return true
    }
    _ = image.setName(name)
    return image
}

let icon = image(false)
let count = 400

func makeButton(subtitle: Bool, styled: Bool) -> TextButton {
    let button = TextButton(frame: CGRect(x: 0, y: 0, width: 180, height: 44))
    button.autoSizeToFit = false
    button.animates = false
    button.set(font: .systemFont(ofSize: 14), for: .Normal)
    button.set(color: .black, for: .Normal)
    button.set(text: "Send message 👋", for: .Normal)
    if subtitle { button.set(subtext: "Scheduled for tomorrow", for: .Normal) }
    if styled {
        button.set(color: .blue, for: .Hover)
        button.set(font: .boldSystemFont(ofSize: 15), for: .Hover)
        button.set(image: icon, for: .Normal)
    }
    _ = button.sizeToFit(.zero, NSSize(width: 180, height: 44), thatFit: true)
    return button
}

func measure(_ kind: String, subtitle: Bool = false, styled: Bool = false, update: (TextButton, Int) -> Void) -> [String: Any] {
    for _ in 0..<30 { autoreleasepool { _ = makeButton(subtitle: subtitle, styled: styled) } }
    var trials: [[String: Any]] = []
    for _ in 0..<7 {
        autoreleasepool {
            var buttons: [TextButton] = []
            buttons.reserveCapacity(count)
            let bytes = allocatedBytes()
            let createMs = elapsed {
                autoreleasepool {
                    for _ in 0..<count { buttons.append(makeButton(subtitle: subtitle, styled: styled)) }
                }
            }
            let retainedBytes = allocatedBytes() - bytes
            let updateMs = elapsed {
                for pass in 0..<10 {
                    for button in buttons { update(button, pass) }
                }
            }
            trials.append(["createMs": createMs, "updateMs": updateMs, "mallocBytes": retainedBytes])
            withExtendedLifetime(buttons) {}
        }
    }
    return ["kind": kind, "controls": count, "updatePasses": 10, "trials": trials]
}

func stateAndSize(_ button: TextButton, _ pass: Int) {
    button.controlState = pass % 2 == 0 ? .Hover : .Normal
    _ = button.sizeToFit(.zero, NSSize(width: 180 + pass, height: 44), thatFit: true)
}

if CommandLine.arguments.contains("--preview") {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = "TGUIKit text button lab"
    let scroll = NSScrollView(frame: window.contentView!.bounds)
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    let document = View(frame: CGRect(x: 0, y: 0, width: 500, height: 8000))
    for index in 0..<100 {
        let button = makeButton(subtitle: index % 2 == 0, styled: index % 3 == 0)
        button.frame.origin = CGPoint(x: 32, y: index * 80 + 12)
        button.set(handler: { control in
            let button = control as! TextButton
            button.isSelected.toggle()
            button.set(subtext: button.isSelected ? "Selected ✓" : nil, for: .Normal, animated: true)
        }, for: .Click)
        document.addSubview(button)
    }
    scroll.documentView = document
    window.contentView!.addSubview(scroll)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    NSApp.run()
} else {
    let results = [
        measure("titleStateAndSize", update: stateAndSize),
        measure("subtitleStateAndSize", subtitle: true, update: stateAndSize),
        measure("distinctStateStyles", subtitle: true, styled: true, update: stateAndSize),
        measure("changingContent", subtitle: true, update: { button, pass in
            button.set(text: "Send message \(pass) 👋", for: .Normal)
            button.set(subtext: "Scheduled for day \(pass)", for: .Normal)
            _ = button.sizeToFit(.zero, NSSize(width: 180, height: 44), thatFit: true)
        }),
        measure("widthOnly", subtitle: true, update: { button, pass in
            _ = button.sizeToFit(.zero, NSSize(width: 80 + pass * 20, height: 44), thatFit: true)
        }),
        measure("repeatedSetters", subtitle: true, update: { button, _ in
            button.set(text: "Send message 👋", for: .Normal)
            button.set(color: .black, for: .Normal)
            button.set(font: .systemFont(ofSize: 14), for: .Normal)
            button.set(subtext: "Scheduled for tomorrow", for: .Normal)
        })
    ]
    let data = try JSONSerialization.data(withJSONObject: ["os": ProcessInfo.processInfo.operatingSystemVersionString, "results": results], options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
