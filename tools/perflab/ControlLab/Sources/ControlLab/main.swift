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

func viewCount(_ view: NSView) -> Int {
    1 + view.subviews.reduce(0) { $0 + viewCount($1) }
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
let normal = image(false)
let selected = image(true)
let count = 2_000

func makeButton(_ decorated: Bool) -> ImageButton {
    let button = ImageButton(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
    button.animates = false
    button.set(image: normal, for: .Normal)
    if decorated {
        button.set(additionBackgroundColor: .systemRed, for: .Normal)
        button.set(cornerRadius: .half, for: .Normal)
    }
    return button
}

func makeSelection(_ isSelected: Bool) -> SelectingControl {
    SelectingControl(unselectedImage: normal, selectedImage: selected, selected: isSelected)
}

func measure(_ kind: String, make: () -> NSView, update: (NSView, Int) -> Void) -> [String: Any] {
    for _ in 0..<50 { autoreleasepool { _ = make() } }
    var trials: [[String: Any]] = []
    for _ in 0..<7 {
        autoreleasepool {
            var controls: [NSView] = []
            controls.reserveCapacity(count)
            let bytes = allocatedBytes()
            let createMs = elapsed {
                for _ in 0..<count { controls.append(make()) }
            }
            let retainedBytes = allocatedBytes() - bytes
            let updateMs = elapsed {
                for pass in 0..<10 {
                    for control in controls { update(control, pass) }
                }
            }
            trials.append(["createMs": createMs, "updateMs": updateMs, "mallocBytes": retainedBytes,
                           "viewCount": controls.reduce(0) { $0 + viewCount($1) }])
            withExtendedLifetime(controls) {}
        }
    }
    return ["kind": kind, "controls": count, "updatePasses": 10, "trials": trials]
}

func makeDocument() -> View {
    let document = View(frame: CGRect(x: 0, y: 0, width: 480, height: 10_000))
    for row in 0..<200 {
        let button = makeButton(row % 3 == 0)
        button.frame.origin = CGPoint(x: 18, y: row * 50 + 8)
        document.addSubview(button)
        let selection = makeSelection(row % 2 == 0)
        selection.frame.origin = CGPoint(x: 65, y: row * 50 + 12)
        document.addSubview(selection)
        button.set(handler: { _ in selection.set(selected: !selection.isSelected, animated: true) }, for: .Click)
        let label = NSTextField(labelWithString: "Chat row \(row + 1) — click the icon to select")
        label.frame = CGRect(x: 110, y: row * 50 + 14, width: 350, height: 24)
        document.addSubview(label)
    }
    return document
}

func measureRows() -> [String: Any] {
    var trials: [[String: Any]] = []
    for _ in 0..<7 {
        autoreleasepool {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: window.contentView!.bounds)
            window.contentView = scroll
            let bytes = allocatedBytes()
            let createMs = elapsed {
                scroll.documentView = makeDocument()
                scroll.layoutSubtreeIfNeeded()
                CATransaction.flush()
            }
            let retainedBytes = allocatedBytes() - bytes
            let scrollMs = elapsed {
                for step in 0..<300 {
                    scroll.contentView.scroll(to: CGPoint(x: 0, y: (step * 47) % 9400))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    scroll.layoutSubtreeIfNeeded()
                    CATransaction.flush()
                }
            }
            trials.append(["createMs": createMs, "scrollLayoutMs": scrollMs, "mallocBytes": retainedBytes,
                           "viewCount": viewCount(scroll.documentView!)])
            window.close()
        }
    }
    return ["kind": "chatRowFixture", "controls": 400, "rows": 200, "scrollSteps": 300, "trials": trials]
}

if CommandLine.arguments.contains("--preview") {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 600), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.title = "TGUIKit control performance lab"
    let scroll = NSScrollView(frame: window.contentView!.bounds)
    scroll.autoresizingMask = [.width, .height]
    scroll.hasVerticalScroller = true
    scroll.documentView = makeDocument()
    window.contentView!.addSubview(scroll)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    NSApp.run()
} else {
    let results = [
        measure("plainButtons", make: { makeButton(false) }, update: { view, pass in
            let button = view as! ImageButton
            button.controlState = pass % 2 == 0 ? .Hover : .Normal
            button.updateLayout(size: CGSize(width: 32 + pass % 2, height: 32), transition: .immediate)
        }),
        measure("decoratedButtons", make: { makeButton(true) }, update: { view, pass in
            let button = view as! ImageButton
            button.controlState = pass % 2 == 0 ? .Hover : .Normal
            button.updateLayout(size: CGSize(width: 32 + pass % 2, height: 32), transition: .immediate)
        }),
        measure("unselectedControls", make: { makeSelection(false) }, update: { view, pass in
            let control = view as! SelectingControl
            control.set(selected: pass % 2 == 0)
            control.layout()
        }),
        measure("selectedControls", make: { makeSelection(true) }, update: { view, pass in
            let control = view as! SelectingControl
            control.set(selected: true)
            control.setFrameSize(CGSize(width: 32 + pass % 2, height: 32))
            control.layout()
        }),
        measureRows()
    ]
    let output: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString,
        "architecture": "arm64", "processors": ProcessInfo.processInfo.processorCount,
        "scale": System.backingScale, "results": results]
    let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
