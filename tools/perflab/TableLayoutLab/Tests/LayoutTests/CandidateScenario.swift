import AppKit
import XCTest
import QuartzCore
@testable import class TGUIKit.TableView
@testable import class TGUIKit.TGFlipableTableView
import class TGUIKit.TableRowItem
import class TGUIKit.TableRowView
import class TGUIKit.TableStickItem

private final class CandidateItem: TableRowItem {
    var rowHeight: CGFloat
    init(id: Int, height: CGFloat) {
        rowHeight = height
        super.init(.zero, stableId: id)
    }
    override var height: CGFloat { rowHeight }
    override func viewClass() -> AnyClass { CandidateRow.self }
}

private final class CandidateRow: TableRowView {
    override func draw(_ dirtyRect: NSRect) {
        let id = item?.stableId.base as? Int ?? 0
        NSColor(calibratedRed: CGFloat(id % 7) / 7, green: 0.3, blue: 0.6, alpha: 1).setFill()
        bounds.fill()
        NSColor.white.setFill()
        NSRect(x: 10, y: 9, width: max(0, bounds.width - 30), height: min(7, bounds.height / 3)).fill()
    }
}

private final class CandidateHeader: TableStickItem {}

func runCandidateScenario(flipped: Bool, count: Int, inset: CGFloat, render: Bool) -> [LayoutSnapshot] {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let table = TGUIKit.TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240), isFlipped: flipped)
    table.hasVerticalScroller = false
    table.hasHorizontalScroller = false
    window.contentView!.addSubview(table)
    table.contentInsets = NSEdgeInsets(top: inset, left: 0, bottom: inset / 2, right: 0)
    var rowItems: [CandidateItem] = []
    for id in 0..<count {
        let item = CandidateItem(id: id, height: CGFloat(20 + id % 5 * 11))
        rowItems.append(item)
        _ = table.addItem(item: item)
    }
    var results: [LayoutSnapshot] = []
    func record(_ stage: String) {
        table.needsLayout = true
        table.layoutSubtreeIfNeeded()
        table.view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        var frames: [Int: NSRect] = [:]
        for index in 0..<table.count {
            if let row = table.view.rowView(atRow: index, makeIfNecessary: false) { frames[index] = row.frame }
        }
        var pixels = Data()
        if render, let bitmap = table.bitmapImageRepForCachingDisplay(in: table.bounds) {
            table.cacheDisplay(in: table.bounds, to: bitmap)
            pixels = Data(bytes: bitmap.bitmapData!, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
            XCTAssertTrue(pixels.contains { $0 != 0 })
        }
        results.append(LayoutSnapshot(stage: stage, frame: table.frame, documentRect: table.contentView.documentRect, bounds: table.contentView.bounds, visible: table.visibleRows(), rowRects: (0..<table.count).map { table.rectOf(index: $0) }, realizedFrames: frames, selected: table.selectedItem()?.stableId.base as? Int, pixels: pixels))
        XCTAssertEqual(table.view.numberOfRows, table.count)
    }
    record("initial")
    if count > 0 { table.selectAt(count / 2) }
    for iteration in 0..<3 { record("repeat_\(iteration)") }
    for y in [CGFloat(0), 35.5, 500, 0] {
        table.clipView.updateBounds(to: NSPoint(x: 0, y: y), cancel: true)
        record("scroll_\(y)")
    }
    for size in [NSSize(width: 410, height: 170), NSSize(width: 250.5, height: 300.5), NSSize(width: 320, height: 240)] {
        table.setFrameSize(size)
        record("resize_\(size)")
    }
    if count > 0 {
        rowItems[count / 2].rowHeight += 73
        table.noteHeightOfRow(count / 2, false)
        record("height_change")
    }
    _ = table.insert(item: CandidateItem(id: 1001, height: 33), at: 0)
    record("insert")
    table.remove(at: 0)
    record("remove")
    table.beginTableUpdates()
    _ = table.addItem(item: CandidateItem(id: 1002, height: 47))
    table.layout()
    table.endTableUpdates()
    record("nested_update")
    table.removeAll()
    record("empty")
    _ = table.addItem(item: CandidateItem(id: 1003, height: 1200))
    record("tall_row")
    table.clipView.updateBounds(to: NSPoint(x: 0, y: 400), cancel: true)
    record("tall_row_scrolled")
    table.removeAll()
    return results
}

func runCandidateStickyScenario() -> [[NSRect]] {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let table = TGUIKit.TableView(frame: window.contentView!.bounds)
    window.contentView!.addSubview(table)
    for id in 0..<100 {
        if id % 10 == 0 { _ = table.addItem(item: CandidateHeader(.zero)) }
        else { _ = table.addItem(item: CandidateItem(id: id, height: 40)) }
    }
    table.set(stickClass: CandidateHeader.self, handler: { _ in })
    var result: [[NSRect]] = []
    for y in [CGFloat(0), 20, 340, 600, 1800, 0] {
        table.clipView.updateBounds(to: NSPoint(x: 0, y: y), cancel: true)
        table.layout()
        table.layoutSubtreeIfNeeded()
        table.updateStickAfterScroll(false)
        result.append(table.layoutLabStickyFrames)
    }
    table.remove(at: 0)
    table.layout()
    table.updateStickAfterScroll(false)
    result.append(table.layoutLabStickyFrames)
    return result
}

private final class CandidateSecondaryHeader: TableStickItem {}

private final class CandidateEndTable: TGFlipableTableView {
    var completed: (() -> Void)?
    override func endUpdates() {
        super.endUpdates()
        let callback = completed
        completed = nil
        callback?()
    }
}

func runCandidateReentrantCacheScenario(mode: Int) -> Bool {
    let table = TGUIKit.TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
    let spy = CandidateEndTable(frame: table.bounds)
    table.tableView = spy
    table.updateAfterInitialize()
    for id in 0..<20 {
        if id % 5 == 0 { _ = table.addItem(item: CandidateHeader(.zero)) }
        else if id % 7 == 0 { _ = table.addItem(item: CandidateSecondaryHeader(.zero)) }
        else { _ = table.addItem(item: CandidateItem(id: id, height: 40)) }
    }
    table.set(stickClass: CandidateHeader.self, handler: { _ in })
    table.setSecondary(stickClass: CandidateSecondaryHeader.self, handler: { _ in })
    table.updateStickAfterScroll(false)
    XCTAssertTrue(table.layoutLabStickyCacheCounts.allSatisfy { $0 >= 0 })
    var invoked = false
    spy.completed = {
        invoked = true
        switch mode {
        case 0:
            _ = table.insert(item: CandidateHeader(.zero), at: 0)
        case 1:
            table.set(stickClass: CandidateSecondaryHeader.self, handler: { _ in })
        case 2:
            table.setSecondary(stickClass: CandidateHeader.self, handler: { _ in })
        case 3:
            table.remove(at: 0)
            _ = table.insert(item: CandidateItem(id: 100, height: 40), at: 0)
        default:
            table.removeAll()
        }
    }
    table.layout()
    XCTAssertTrue(invoked)
    table.updateStickAfterScroll(false)
    XCTAssertTrue(table.layoutLabStickyCacheCounts.allSatisfy { $0 >= 0 })
    return table.layoutLabCachesMatchRows
}

func runCandidateCacheRetentionScenario() -> [[Int]] {
    let table = TGUIKit.TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
    for id in 0..<40 {
        if id % 10 == 0 { _ = table.addItem(item: CandidateHeader(.zero)) }
        else { _ = table.addItem(item: CandidateSecondaryHeader(.zero)) }
    }
    table.set(stickClass: CandidateHeader.self, handler: { _ in })
    table.setSecondary(stickClass: CandidateSecondaryHeader.self, handler: { _ in })
    table.updateStickAfterScroll(false)
    var values = [table.layoutLabStickyCacheCounts]
    for _ in 0..<3 { table.layout(); values.append(table.layoutLabStickyCacheCounts) }
    _ = table.insert(item: CandidateHeader(.zero), at: 0)
    values.append(table.layoutLabStickyCacheCounts)
    table.updateStickAfterScroll(false)
    values.append(table.layoutLabStickyCacheCounts)
    XCTAssertTrue(table.layoutLabCachesMatchRows)
    return values
}
