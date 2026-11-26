import AppKit
import Darwin
import TGUIKit

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

func elapsed(_ body: () -> Void) -> Double {
    let start = CFAbsoluteTimeGetCurrent()
    body()
    return (CFAbsoluteTimeGetCurrent() - start) * 1000
}

func drain() {
    var done = false
    DispatchQueue.main.async { done = true }
    while !done { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001)) }
}

func makeLayout(_ index: Int, kind: String) -> TextViewLayout {
    let string = NSMutableAttributedString(string: "Message \(index) — 中文 العربية 👩🏽‍💻 with a link and hidden text", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
    if kind == "links" { string.addAttribute(.link, value: "https://example.com", range: NSRange(location: 0, length: 7)) }
    if kind == "spoilers" { string.addAttribute(TextInputAttributes.spoiler, value: true, range: NSRange(location: 8, length: 18)) }
    let layout = TextViewLayout(string, maximumNumberOfLines: 3, disableTooltips: kind != "links")
    layout.interactions.resolveLink = { $0 as? String }
    layout.measure(width: 250 + CGFloat(index % 3) * 15)
    return layout
}

func measureText(_ kind: String, mounted: Bool) -> [String: Any] {
    let window = NSWindow(contentRect: NSMakeRect(0, 0, 360, 150), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let layouts = (0..<12).map { makeLayout($0, kind: kind) }
    let view = TextView()
    if mounted { window.contentView!.addSubview(view) }
    view.update(layouts[0])
    for _ in 0..<100 { view.update(layouts[0]); view.layoutSubtreeIfNeeded() }
    var trials: [Double] = []
    for _ in 0..<7 {
        trials.append(autoreleasepool {
            elapsed {
                for index in 0..<10_000 {
                    view.update(layouts[kind == "unchanged" ? 0 : index % layouts.count])
                    view.layoutSubtreeIfNeeded()
                }
            }
        })
    }
    return ["kind": "\(mounted ? "mounted" : "detached")-\(kind)", "operations": 10_000, "trialsMs": trials]
}

final class LabTextItem: TableRowItem {
    let textLayout: TextViewLayout
    init(_ index: Int) {
        textLayout = makeLayout(index, kind: index % 4 == 0 ? "links" : "plain")
        super.init(NSSize(width: 360, height: 60), stableId: index)
    }
    override func viewClass() -> AnyClass { LabTextRow.self }
}

final class LabTextRow: TableRowView {
    private let label = TextView()
    required init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        if let item = item as? LabTextItem {
            label.update(item.textLayout, origin: NSPoint(x: 12, y: 2))
        }
    }
}

final class LabHeader: TableStickItem {}
final class LabSecondaryHeader: TableStickItem {}

func makeTable(_ headers: Int, flipped: Bool = true) -> (NSWindow, TableView) {
    let window = NSWindow(contentRect: NSMakeRect(0, 0, 360, 500), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let table = TableView(frame: window.contentView!.bounds, isFlipped: flipped)
    table.autoresizingMask = [.width, .height]
    window.contentView!.addSubview(table)
    table.beginTableUpdates()
    for index in 0..<300 {
        let item: TableRowItem
        if headers > 0 && index % 20 == 0 { item = LabHeader(NSSize(width: 360, height: 30)) }
        else if headers > 1 && index % 20 == 1 { item = LabSecondaryHeader(NSSize(width: 360, height: 30)) }
        else { item = LabTextItem(index) }
        _ = table.addItem(item: item)
    }
    table.endTableUpdates()
    if headers > 0 { table.set(stickClass: LabHeader.self, handler: { _ in }) }
    if headers > 1 { table.setSecondary(stickClass: LabSecondaryHeader.self, handler: { _ in }) }
    table.layoutSubtreeIfNeeded()
    drain()
    return (window, table)
}

func measureTable(_ headers: Int, scroll: Bool) -> [String: Any] {
    let (window, table) = makeTable(headers)
    defer { window.close() }
    let operations = scroll ? 250 : 10_000
    var trials: [Double] = []
    var cpuTrials: [Double] = []
    for _ in 0..<7 {
        let startCPU = clock()
        trials.append(autoreleasepool {
            elapsed {
                for index in 0..<operations {
                    if scroll {
                        table.contentView.scroll(to: NSPoint(x: 0, y: (index * 31) % 8000))
                        table.reflectScrolledClipView(table.contentView)
                        drain()
                        table.layoutSubtreeIfNeeded()
                    } else {
                        table.updateStickAfterScroll(false)
                        _ = table.visibleRows()
                    }
                }
            }
        })
        cpuTrials.append(Double(clock() - startCPU) * 1000 / Double(CLOCKS_PER_SEC))
    }
    return ["kind": "\(scroll ? "scroll" : "scrollGeometry")-\(headers)Headers", "operations": operations, "trialsMs": trials, "cpuTrialsMs": cpuTrials]
}

if let index = CommandLine.arguments.firstIndex(of: "--snapshots") {
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for scale in [CGFloat(1), 2] {
        System.updateScaleFactor(scale)
        for kind in ["plain", "links", "selected"] {
            let view = TextView()
            let layout = makeLayout(0, kind: kind)
            if kind == "selected" { layout.selectedRange = TextSelectedRange(range: NSRange(location: 0, length: 7)) }
            for _ in 0..<3 { view.update(layout) }
            let pixels = ViewSnapshot.render(view, scale: scale)
            try Data(pixels.bytes).write(to: directory.appendingPathComponent("\(kind)-\(Int(scale)).rgba"))
            pixels.write(to: directory.appendingPathComponent("\(kind)-\(Int(scale)).png").path)
        }
    }
    var geometry: [[String: Any]] = []
    for flipped in [false, true] {
        for headers in 0...2 {
            let (window, table) = makeTable(headers, flipped: flipped)
            for position in [0, 1, 29, 500, 1180, 3600, 0] {
                table.contentView.scroll(to: NSPoint(x: 0, y: position))
                table.reflectScrolledClipView(table.contentView)
                drain()
                table.layoutSubtreeIfNeeded()
                table.updateStickAfterScroll(false)
                let sticky = table.subviews.compactMap { $0 as? TableStickView }.map { ["frame": NSStringFromRect($0.frame), "hidden": $0.isHidden, "header": $0.header, "index": $0.item?.index ?? -1] as [String: Any] }
                geometry.append(["flipped": flipped, "headers": headers, "position": position, "visible": NSStringFromRange(table.visibleRows()), "sticky": sticky])
            }
            window.close()
        }
    }
    try JSONSerialization.data(withJSONObject: geometry, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("table-geometry.json"))
} else if CommandLine.arguments.contains("--preview") {
    let (window, _) = makeTable(2)
    window.title = "Text updates and table scrolling"
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    NSApp.run()
} else {
    let results = [false, true].flatMap { mounted in ["unchanged", "changing", "links", "spoilers"].map { measureText($0, mounted: mounted) } } + (0...2).map { measureTable($0, scroll: false) } + (0...2).map { measureTable($0, scroll: true) }
    print(String(decoding: try JSONSerialization.data(withJSONObject: ["os": ProcessInfo.processInfo.operatingSystemVersionString, "results": results], options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
}
