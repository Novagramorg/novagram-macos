import AppKit
import XCTest

enum TableSavingSide { case upper, lower, aroundIndex(AnyHashable) }
enum NativeScrollState { case saveVisible(TableSavingSide, Bool), none }

private final class NativeRow {
    let stableId: AnyHashable
    var index: Int = 0
    var height: CGFloat
    let canBeAnchor = true
    init(_ id: Int, _ height: CGFloat) {
        self.stableId = id
        self.height = height
    }
}

private final class FocusRowView: NSTableCellView {
    var focusCount = 0
    var focusedInnerId: AnyHashable?
    var focusedText: String?
    var focusedRange: NSRange?
    let isInsertionAnimated = false
    var interactableView: NSView { self }
    func focusAnimation(_ innerId: AnyHashable?, text: String?, range: NSRange?) {
        focusCount += 1
        focusedInnerId = innerId
        focusedText = text
        focusedRange = range
    }
}

private struct NativeFocus {
    var focus: Bool
    var string: String? = nil
    var range: NSRange? = nil
    var action: ((NSView) -> Void)? = nil
}

private final class NativeClipView: NSClipView {
    func cancelScrolling() {}
    func updateBounds(to point: NSPoint, cancel: Bool) {
        scroll(to: point)
        setBoundsOrigin(point)
    }
}

private final class NativeTableView: NSTableView {
    override var isFlipped: Bool { false }
}

private final class GroupLookup {
    var groups: [AnyHashable: AnyHashable] = [:]
    func findGroupStableId(for id: AnyHashable) -> AnyHashable? { groups[id] }
}

private final class NativeHistoryTable: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let frame = NSRect(x: 0, y: 0, width: 400, height: 600)
    let clipView = NativeClipView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    let tableView = NativeTableView(frame: .zero)
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
    var delegate: GroupLookup? = GroupLookup()
    var rows: [NativeRow] = []

    override init() {
        super.init()
        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("message"))
        column.width = 400
        tableView.addTableColumn(column)
        tableView.dataSource = self
        tableView.delegate = self
        scrollView.contentView = clipView
        scrollView.documentView = tableView
        clipView.setFrameSize(NSSize(width: 400, height: 580))
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rows[row].height }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        FocusRowView(frame: NSRect(x: 0, y: 0, width: 400, height: rows[row].height))
    }
    func load(_ rows: [NativeRow]) {
        self.rows = rows
        for (index, row) in rows.enumerated() { row.index = index }
        tableView.reloadData()
        tableView.layoutSubtreeIfNeeded()
    }
    func item(stableId: AnyHashable) -> NativeRow? { rows.first { $0.stableId == stableId } }
    func rectOf(item: NativeRow) -> NSRect { tableView.rect(ofRow: item.index) }
    func viewNecessary(at index: Int, makeIfNecessary: Bool = false) -> FocusRowView? {
        tableView.view(atColumn: 0, row: index, makeIfNecessary: makeIfNecessary) as? FocusRowView
    }
    func screenTop(_ row: NativeRow) -> CGFloat {
        frame.height - (rectOf(item: row).maxY - clipView.bounds.minY)
    }
    func focusShortDocument(id: AnyHashable, focus: NativeFocus, innerId: AnyHashable? = nil, completion: (Bool) -> Void) {
        let documentHeight = clipView.documentRect.height
        let height = frame.height
        let targetStableId: AnyHashable? = id
        let item = item(stableId: id)
        let findItem: (AnyHashable) -> NativeRow? = { [weak self] id in
            self?.item(stableId: id) ?? self?.delegate?.findGroupStableId(for: id).flatMap { self?.item(stableId: $0) }
        }
__SHORT_DOCUMENT_BRANCH__
__STATIONARY_BRANCH__
    }

    func mergePreserving(_ id: AnyHashable, insertedRows: [NativeRow], updatedHeight: CGFloat) {
        let visibleItems = rows.filter { rectOf(item: $0).intersects(clipView.bounds) }.map { ($0, screenTop($0), CGFloat(0)) }
        let state = NativeScrollState.saveVisible(.aroundIndex(id), false)
        load(insertedRows)
__SAVE_VISIBLE_FUNCTION__
        switch state {
__SAVE_VISIBLE_CASE__
        case .none: break
        }
        let target = item(stableId: id) ?? delegate?.findGroupStableId(for: id).flatMap { item(stableId: $0) }
        if let target {
            target.height = updatedHeight
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: target.index))
            tableView.layoutSubtreeIfNeeded()
        }
__AFTER_UPDATES__
    }
}

final class TableFocusRegressionTests: XCTestCase {
    func testShortCachedMessageHighlightsOnNextMainQueueTurn() {
        let table = NativeHistoryTable()
        table.load([NativeRow(50, 180)])
        var actions = 0
        var completed: Bool?
        let range = NSRange(location: 1, length: 3)
        table.focusShortDocument(id: 50, focus: NativeFocus(focus: true, string: "quote", range: range, action: { _ in actions += 1 }), innerId: 51, completion: { completed = $0 })
        let done = expectation(description: "Immediate focus")
        DispatchQueue.main.async {
            XCTAssertEqual(table.viewNecessary(at: 0, makeIfNecessary: true)?.focusCount, 1)
            XCTAssertEqual(table.viewNecessary(at: 0, makeIfNecessary: true)?.focusedInnerId, AnyHashable(51))
            XCTAssertEqual(table.viewNecessary(at: 0, makeIfNecessary: true)?.focusedText, "quote")
            XCTAssertEqual(table.viewNecessary(at: 0, makeIfNecessary: true)?.focusedRange, range)
            XCTAssertEqual(actions, 1)
            XCTAssertEqual(completed, true)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testStationaryTargetHighlightsWhenDocumentFillsViewport() {
        let table = NativeHistoryTable()
        table.load([NativeRow(50, 600)])
        table.focusShortDocument(id: 50, focus: NativeFocus(focus: true), completion: { _ in })
        let done = expectation(description: "Stationary focus")
        DispatchQueue.main.async {
            XCTAssertEqual(table.viewNecessary(at: 0, makeIfNecessary: true)?.focusCount, 1)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testDeletedTargetDoesNotHighlightReplacementRow() {
        let table = NativeHistoryTable()
        table.load([NativeRow(50, 180)])
        table.focusShortDocument(id: 50, focus: NativeFocus(focus: true), completion: { _ in })
        table.load([NativeRow(60, 180)])
        let done = expectation(description: "No stale focus")
        DispatchQueue.main.async {
            XCTAssertEqual(table.viewNecessary(at: 0, makeIfNecessary: true)?.focusCount, 0)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testUnfocusedShortMessageDoesNotAnimate() {
        let table = NativeHistoryTable()
        table.load([NativeRow(50, 180)])
        table.focusShortDocument(id: 50, focus: NativeFocus(focus: false), completion: { _ in })
        let done = expectation(description: "No focus requested")
        DispatchQueue.main.async {
            XCTAssertEqual(table.viewNecessary(at: 0, makeIfNecessary: true)?.focusCount, 0)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testSurroundingHistoryPreservesShortAnchorAfterHeightChanges() {
        let table = NativeHistoryTable()
        let anchor = NativeRow(50, 180)
        table.load([anchor])
        let oldTop = table.screenTop(anchor)
        table.mergePreserving(50, insertedRows: [NativeRow(40, 700), anchor, NativeRow(60, 700)], updatedHeight: 260)
        XCTAssertEqual(table.screenTop(anchor), oldTop, accuracy: 0.5)
    }

    func testSurroundingHistoryPreservesOversizedAnchorAfterHeightChanges() {
        let table = NativeHistoryTable()
        let anchor = NativeRow(50, 900)
        table.load([anchor])
        table.clipView.updateBounds(to: NSPoint(x: 0, y: 300), cancel: true)
        let oldTop = table.screenTop(anchor)
        table.mergePreserving(50, insertedRows: [NativeRow(40, 700), anchor, NativeRow(60, 700)], updatedHeight: 960)
        XCTAssertEqual(table.screenTop(anchor), oldTop, accuracy: 0.5)
    }

    func testStandaloneMessageBecomingAlbumKeepsItsPosition() {
        let table = NativeHistoryTable()
        let anchor = NativeRow(50, 180)
        table.load([anchor])
        let oldTop = table.screenTop(anchor)
        let album = NativeRow(500, 180)
        table.delegate?.groups[50] = 500
        table.mergePreserving(50, insertedRows: [NativeRow(40, 700), album, NativeRow(60, 700)], updatedHeight: 320)
        XCTAssertEqual(table.screenTop(album), oldTop, accuracy: 0.5)
    }
}

private struct WrappedHistoryEntry {
    struct Entry { let messages: [Message] }
    let stableId: AnyHashable
    let entry: Entry
}
private struct HistorySnapshot { let filteredEntries: [WrappedHistoryEntry] }
private enum AnchorPosition { case keepInPlace(MessageId) }
private func resolveAnchor(fromView: HistorySnapshot?, messageId: MessageId) -> NativeScrollState? {
    let scrollPosition = AnchorPosition.keepInPlace(messageId)
    var scrollToItem: NativeScrollState?
    switch scrollPosition {
__KEEP_IN_PLACE_CASE__
    }
    return scrollToItem
}

final class AnchorResolutionTests: XCTestCase {
    func testKeepsOldAlbumRowIdForTappedInnerMessage() {
        let history = HistorySnapshot(filteredEntries: [WrappedHistoryEntry(stableId: 500, entry: .init(messages: [Message(id: 49), Message(id: 50)]))])
        guard case let .saveVisible(.aroundIndex(id), animated)? = resolveAnchor(fromView: history, messageId: 50) else { return XCTFail("Expected exact album anchor") }
        XCTAssertEqual(id, AnyHashable(500))
        XCTAssertFalse(animated)
    }

    func testKeepsOldStandaloneRowId() {
        let history = HistorySnapshot(filteredEntries: [WrappedHistoryEntry(stableId: 50, entry: .init(messages: [Message(id: 50)]))])
        guard case let .saveVisible(.aroundIndex(id), _)? = resolveAnchor(fromView: history, messageId: 50) else { return XCTFail("Expected exact message anchor") }
        XCTAssertEqual(id, AnyHashable(50))
    }

    func testMissingOldTargetFallsBackWithoutFocusingNeighbor() {
        guard case .saveVisible(.upper, false)? = resolveAnchor(fromView: HistorySnapshot(filteredEntries: []), messageId: 50) else { return XCTFail("Expected viewport preservation") }
    }
}
