import AppKit

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "nosuper"

final class Row: NSTableRowView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        backgroundColor = .clear
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {}
    override var wantsUpdateLayer: Bool { mode != "draw" }
    override func updateLayer() {
        if mode == "super" { super.updateLayer() }
    }
    func applyColor() { layer?.backgroundColor = NSColor.black.cgColor }
    override var backgroundColor: NSColor {
        get { super.backgroundColor }
        set { super.backgroundColor = CommandLine.arguments.contains("pin") ? .clear : newValue }
    }
}

final class Delegate: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { 2000 }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("row"), owner: nil) as? Row) ?? { let r = Row(frame: .zero); r.identifier = NSUserInterfaceItemIdentifier("row"); return r }()
        view.applyColor()
        return view
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { nil }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { CGFloat(30 + (row % 5) * 10) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
let scroll = NSScrollView(frame: window.contentView!.bounds)
let table = NSTableView(frame: scroll.bounds)
table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c")))
table.headerView = nil
table.backgroundColor = .white
table.usesAlternatingRowBackgroundColors = CommandLine.arguments.contains("alt")
table.selectionHighlightStyle = .none
let delegate = Delegate()
table.dataSource = delegate
table.delegate = delegate
scroll.documentView = table
scroll.wantsLayer = true
window.contentView = scroll
window.makeKeyAndOrderFront(nil)
table.reloadData()

var step = 0
var captures = 0, whiteFrames = 0, maxWhite = 0, sublayerHits = 0, contentsHits = 0
typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
let createImage = unsafeBitCast(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage")!, to: CreateImage.self)
func capture() {
    table.enumerateAvailableRowViews { rowView, _ in
        if (rowView.layer?.sublayers?.count ?? 0) > 0 { sublayerHits += 1 }
        if rowView.layer?.contents != nil { contentsHits += 1 }
    }
    guard let image = createImage(.null, CGWindowListOption.optionIncludingWindow.rawValue, UInt32(window.windowNumber), CGWindowImageOption.boundsIgnoreFraming.rawValue | CGWindowImageOption.nominalResolution.rawValue)?.takeRetainedValue() else { return }
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var white = 0
    for y in stride(from: 40, to: h, by: 2) {
        for x in stride(from: 0, to: w, by: 2) {
            let i = (y * w + x) * 4
            if data[i] > 200 && data[i + 1] > 200 && data[i + 2] > 200 { white += 1 }
        }
    }
    captures += 1
    if white > 0 { whiteFrames += 1 }
    maxWhite = max(maxWhite, white)
}
var whiteHits = 0
var checks = 0
var rowBgWhite = 0
func check() {
    table.enumerateAvailableRowViews { rowView, _ in
        checks += 1
        if let bg = rowView.layer?.backgroundColor, let c = NSColor(cgColor: bg)?.usingColorSpace(.deviceRGB), c.redComponent > 0.5 {
            whiteHits += 1
        }
        if let c = rowView.backgroundColor.usingColorSpace(.deviceRGB), c.alphaComponent > 0, c.redComponent > 0.5 {
            rowBgWhite += 1
        }
    }
}
Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { timer in
    step += 1
    let y = CGFloat((step * 160) % 60000)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
    scroll.reflectScrolledClipView(scroll.contentView)
    if step % 7 == 0 {
        table.enumerateAvailableRowViews { rowView, _ in rowView.needsDisplay = true }
    }
    window.displayIfNeeded()
    CATransaction.flush()
    check()
    if step % 10 == 0 { capture() }
    if step == 600 {
        print("mode=\(mode) alt=\(table.usesAlternatingRowBackgroundColors) checks=\(checks) layerBgWhite=\(whiteHits) rowPropertyWhite=\(rowBgWhite) captures=\(captures) whitePixelFrames=\(whiteFrames) maxWhitePixels=\(maxWhite) sublayers=\(sublayerHits) contents=\(contentsHits)")
        exit(0)
    }
}
app.run()
