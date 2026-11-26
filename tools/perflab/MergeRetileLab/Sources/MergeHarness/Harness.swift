import Cocoa
import TGUIKit

public final class MergeItem: TableRowItem {
    public let id: Int
    public init(_ id: Int, width: CGFloat) {
        self.id = id
        super.init(NSSize(width: width, height: 0), stableId: AnyHashable(id))
    }
    public override var height: CGFloat { CGFloat(36 + (id * 37) % 90) }
    public override func viewClass() -> AnyClass { MergeRow.self }
}

public final class MergeStick: TableStickItem {
    public private(set) var id: Int = 0
    public convenience init(id: Int, width: CGFloat) {
        self.init(NSSize(width: width, height: 0))
        self.id = id
    }
    public required init(_ initialSize: NSSize) {
        super.init(initialSize)
    }
    public override var stableId: AnyHashable { AnyHashable(id) }
    public override var height: CGFloat { 30 }
    public override func viewClass() -> AnyClass { MergeStickView.self }
}

public final class MergeStickView: TableStickView {
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? MergeStick else { return }
        MergeRow.binds += 1
        MergeRow.boundIds.append(item.id)
        layer?.backgroundColor = NSColor(white: CGFloat(item.id % 7) / 10 + 0.2, alpha: 1).cgColor
    }
}

public func makeMergeItem(_ id: Int, width: CGFloat, sticky: Bool) -> TableRowItem {
    if sticky, id % 15 == 0 {
        return MergeStick(id: id, width: width)
    }
    return MergeItem(id, width: width)
}

public final class MergeRow: TableRowView {
    public static var binds = 0
    public static var boundIds: [Int] = []
    private let bar = SimpleLayer()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.addSublayer(bar)
    }
    public required init?(coder: NSCoder) { fatalError() }
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? MergeItem else { return }
        MergeRow.binds += 1
        MergeRow.boundIds.append(item.id)
        let hue = CGFloat((item.id * 47) % 360) / 360
        layer?.backgroundColor = NSColor(hue: hue, saturation: 0.35, brightness: 0.95, alpha: 1).cgColor
        bar.backgroundColor = NSColor(hue: 1 - hue, saturation: 0.8, brightness: 0.5, alpha: 1).cgColor
        bar.frame = CGRect(x: CGFloat((item.id * 13) % 300), y: 6, width: 24, height: 12)
    }
}

public func drain(_ seconds: Double = 0.05) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        RunLoop.current.run(mode: .default, before: min(end, Date().addingTimeInterval(0.002)))
    }
}

public final class MergeScene {
    public let window: NSWindow
    public let table: TableView
    public init(ids: [Int], size: NSSize = NSSize(width: 360, height: 500), flipped: Bool = false, sticky: Bool = false) {
        window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 60, y: 60), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        table = TableView(frame: NSRect(origin: .zero, size: size), isFlipped: flipped)
        window.contentView = table
        table.hasVerticalScroller = false
        window.orderFrontRegardless()
        table.beginTableUpdates()
        for id in ids {
            _ = table.addItem(item: makeMergeItem(id, width: size.width, sticky: sticky))
        }
        table.endTableUpdates()
        if sticky {
            table.set(stickClass: MergeStick.self, handler: { _ in })
        }
        table.layoutSubtreeIfNeeded()
        drain(0.2)
    }

    public func scroll(toRow row: Int) {
        let rect = table.rectOf(index: row)
        table.clipView.scroll(to: NSPoint(x: 0, y: rect.minY))
        table.reflectScrolledClipView(table.clipView)
        drain(0.2)
    }

    public struct Placement: Equatable, CustomStringConvertible {
        public let id: Int
        public let y: CGFloat
        public var description: String { "\(id)@\(y)" }
    }

    public func placements() -> [Placement] {
        let range = table.visibleRows()
        guard range.location != NSNotFound else { return [] }
        var result: [Placement] = []
        for row in range.location ..< range.location + range.length {
            let item = table.item(at: row)
            let id = (item as? MergeItem)?.id ?? (item as? MergeStick)?.id ?? -1
            let rect = table.rectOf(index: row)
            let inWindow = table.documentView!.convert(rect, to: nil)
            result.append(Placement(id: id, y: inWindow.minY))
        }
        return result
    }

    public func capture() -> [UInt8]? {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) else { return nil }
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    public func close() {
        window.orderOut(nil)
        window.close()
    }
}
