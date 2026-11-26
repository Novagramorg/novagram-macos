import AppKit
import XCTest
@testable import class TGUIKit.ScrollView
@testable import class TGUIKit.TGClipView
@testable import class TGUIKit.TableView
@testable import class TGUIKit.TableRowItem
@testable import struct TGUIKit.ScrollPosition
@testable import enum TGUIKit.ScrollDirection

private final class PositionDocumentCandidate: NSView {
    var documentIsFlipped = false
    override var isFlipped: Bool { documentIsFlipped }
}

private final class PositionClipCandidate: TGClipView {
    var documentReads = 0
    override var documentRect: NSRect {
        documentReads += 1
        return super.documentRect
    }
}

final class ScrollPositionCandidateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PositionBootstrap.install()
    }

    func testHistoryMatchesOriginalGeometryAcrossMutations() {
        for flipped in [false, true] {
            let scroll = ScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
            let document = PositionDocumentCandidate(frame: NSRect(x: 0, y: 0, width: 700, height: 2400))
            document.documentIsFlipped = flipped
            scroll.documentView = document
            var previous = ScrollPosition()
            for height in [CGFloat(2400), 80, 3200.25] {
                document.setFrameSize(NSSize(width: 700.25, height: height))
                for viewport in [NSSize(width: 320, height: 240), NSSize(width: 450.5, height: 170.25)] {
                    scroll.setFrameSize(viewport)
                    for inset in [CGFloat(0), 23.5] {
                        scroll.contentInsets = NSEdgeInsets(top: inset, left: 7, bottom: 13, right: 3)
                        for offset in [CGFloat(0), 1.5, 700, 700, 25, -12] {
                            scroll.contentView.setBoundsOrigin(NSPoint(x: 9.25, y: offset))
                            let range = NSRange(location: Int(abs(offset)), length: 7)
                            let rect = NSRect(x: scroll.contentView.bounds.minX, y: scroll.contentView.bounds.maxY, width: scroll.contentView.documentRect.width, height: scroll.contentView.documentRect.height)
                            var direction = previous.direction
                            if previous.rect.minY > rect.minY { direction = .top }
                            else if previous.rect.minY < rect.minY { direction = .bottom }
                            let expected = ScrollPosition(rect, direction, range)
                            let actual = scroll.scrollPosition(range)
                            XCTAssertEqual(actual.previous, previous)
                            XCTAssertEqual(actual.current, expected)
                            previous = expected
                        }
                    }
                }
            }
        }
    }

    func testResetUsesLatestGeometryAndClearsDirection() {
        let scroll = ScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 3000))
        _ = scroll.scrollPosition()
        scroll.contentView.setBoundsOrigin(NSPoint(x: 3, y: 300))
        _ = scroll.scrollPosition()
        scroll.documentView!.setFrameSize(NSSize(width: 640, height: 4100))
        scroll.contentView.setBoundsOrigin(NSPoint(x: 12, y: 110))
        let range = NSRange(location: 4, length: 8)
        scroll.resetScroll(range)
        let result = scroll.scrollPosition(range)
        XCTAssertEqual(result.current, result.previous)
        XCTAssertEqual(result.current.direction, .none)
        XCTAssertEqual(result.current.rect, NSRect(x: 12, y: scroll.contentView.bounds.maxY, width: scroll.contentView.documentRect.width, height: scroll.contentView.documentRect.height))
        scroll.documentView = nil
        scroll.resetScroll()
        XCTAssertEqual(scroll.scrollPosition().current, scroll.scrollPosition().previous)
    }

    func testPositionReadsDocumentOnceAndDoesNotCacheAcrossCalls() {
        let scroll = ScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let clip = PositionClipCandidate(frame: scroll.contentView.frame)
        scroll.contentView = clip
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 3000))
        clip.documentReads = 0
        let first = scroll.scrollPosition()
        XCTAssertEqual(clip.documentReads, 1)
        scroll.documentView!.setFrameSize(NSSize(width: 800, height: 4000))
        clip.documentReads = 0
        let second = scroll.scrollPosition()
        XCTAssertEqual(clip.documentReads, 1)
        XCTAssertNotEqual(first.current.rect.size, second.current.rect.size)
        clip.documentReads = 0
        scroll.resetScroll()
        XCTAssertEqual(clip.documentReads, 1)
    }

    func testUnobservedTablePreservesPointCallbackWithoutReadingDocument() {
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let clip = PositionClipCandidate(frame: table.contentView.frame)
        table.contentView = clip
        var calls = 0
        table.updateScrollPoint = { point in calls += 1; return point }
        clip.documentReads = 0
        table.scrollDidChangedBounds()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(clip.documentReads, 0)
    }

    func testPointCallbackCanInstallObserverAndResizeDocument() {
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        defer { table.updateScrollPoint = nil; table.scrollDidUpdate = nil; table._scrollDidLiveScrolling = nil }
        for index in 0..<20 { _ = table.addItem(item: TableRowItem(.zero, stableId: index)) }
        var events: [String] = []
        var received: ScrollPosition?
        table._scrollDidLiveScrolling = { events.append("live") }
        table.updateScrollPoint = { point in
            events.append("point")
            table.documentView!.setFrameSize(NSSize(width: 700, height: 4000))
            table.scrollDidUpdate = { position in events.append("observer"); received = position }
            return NSPoint(x: point.x + 13, y: point.y + 29)
        }
        let origin = table.contentView.bounds.origin
        table.scrollDidChangedBounds()
        XCTAssertEqual(events, ["live", "point", "observer"])
        XCTAssertEqual(received?.rect, NSRect(origin: NSPoint(x: origin.x + 13, y: origin.y + 29), size: table.contentView.documentRect.size))
        XCTAssertEqual(received?.visibleRows, NSRange(location: 0, length: 0))
        XCTAssertEqual(received?.direction, ScrollDirection.none)
    }

    func testPointCallbackCanRemoveObserver() {
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        defer { table.updateScrollPoint = nil; table.scrollDidUpdate = nil; table._scrollDidLiveScrolling = nil }
        var count = 0
        table.scrollDidUpdate = { _ in count += 1 }
        table.updateScrollPoint = { point in table.scrollDidUpdate = nil; return point }
        table.scrollDidChangedBounds()
        XCTAssertEqual(count, 0)
    }

    func testObserverCanReenterAndMutateRows() {
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        defer { table.updateScrollPoint = nil; table.scrollDidUpdate = nil; table._scrollDidLiveScrolling = nil }
        for index in 0..<20 { _ = table.addItem(item: TableRowItem(.zero, stableId: index)) }
        var positions: [ScrollPosition] = []
        table.scrollDidUpdate = { position in
            positions.append(position)
            if positions.count == 1 {
                table.removeAll()
                table.scrollDidChangedBounds()
            }
        }
        table.scrollDidChangedBounds()
        XCTAssertEqual(positions.count, 2)
        XCTAssertEqual(table.count, 0)
        XCTAssertEqual(positions.last?.rect.size, table.contentView.documentRect.size)
    }
}
