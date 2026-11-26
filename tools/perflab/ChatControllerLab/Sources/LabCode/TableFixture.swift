import AppKit

struct RowGeometry: Equatable {
    let id: Int
    let y: CGFloat
    let height: CGFloat
}

func visibleGeometry(_ rows: [TableRowItem], anchor: Int, viewport: CGFloat, alignmentShift: CGFloat = 0) -> [RowGeometry] {
    let index = rows.firstIndex { $0.stableId == anchor }!
    let total = rows.reduce(0) { $0 + $1.height }
    let origin = rows.prefix(index).reduce(0) { $0 + $1.height }
    let offset = round(max(0, min(origin - floor((viewport - rows[index].height) / 2), total - viewport))) - alignmentShift
    var y: CGFloat = 0
    return rows.compactMap { row in
        defer { y += row.height }
        guard y + row.height > offset && y < offset + viewport else { return nil }
        return RowGeometry(id: row.stableId, y: y - offset, height: row.height)
    }
}

final class HistoryTable: NSTableView {
    override var isFlipped: Bool { false }
}

final class TableFixture: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let rows: [TableRowItem]
    let table = HistoryTable()
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 720))
    let window: NSWindow
    init(rows: [TableRowItem], anchor: Int, viewport: CGFloat) {
        self.rows = rows
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: viewport), styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        scroll.frame.size.height = viewport
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.15, alpha: 1)
        table.headerView = nil
        table.intercellSpacing = .zero
        table.backgroundColor = scroll.backgroundColor
        table.selectionHighlightStyle = .none
        table.usesAutomaticRowHeights = false
        let column = NSTableColumn(identifier: .init("message"))
        column.width = 480
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        window.contentView = scroll
        table.reloadData()
        table.layoutSubtreeIfNeeded()
        let index = rows.firstIndex { $0.stableId == anchor }!
        let rect = table.rect(ofRow: index)
        let offset = round(max(0, min(rect.minY - floor((viewport - rect.height) / 2), table.frame.height - viewport)))
        scroll.contentView.scroll(to: CGPoint(x: 0, y: offset))
        scroll.reflectScrolledClipView(scroll.contentView)
        scroll.layoutSubtreeIfNeeded()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rows[row].height }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: rows[row].height))
        let bubble = NSView(frame: NSRect(x: 20, y: 6, width: 420, height: max(0, rows[row].height - 12)))
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 12
        bubble.layer?.backgroundColor = NSColor(calibratedRed: 0.17, green: 0.25, blue: 0.35, alpha: 1).cgColor
        let label = NSTextField(wrappingLabelWithString: "Message \(rows[row].stableId)\n\(rows[row].text)")
        label.textColor = .white
        label.font = .systemFont(ofSize: 14)
        label.frame = NSRect(x: 12, y: 8, width: 396, height: max(0, bubble.frame.height - 16))
        bubble.addSubview(label)
        view.addSubview(bubble)
        return view
    }
    var visibleGeometry: [RowGeometry] {
        let rect = scroll.contentView.bounds
        return rows.indices.compactMap { index in
            let row = table.rect(ofRow: index)
            guard row.maxY > rect.minY && row.minY < rect.maxY else { return nil }
            return RowGeometry(id: rows[index].stableId, y: row.minY - rect.minY, height: row.height)
        }
    }
}
