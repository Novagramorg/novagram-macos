import AppKit
import XCTest
@testable import TGUIKit

final class TableFocusCompletionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func withTable(_ body: (TableView) throws -> Void) rethrows {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let table = TableView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(table)
        for id in 0..<60 {
            _ = table.addItem(item: TableRowItem(.zero, stableId: id))
        }
        table.layoutSubtreeIfNeeded()
        try body(table)
    }

    func testInterruptedScrollDoesNotCommitFocusAction() throws {
        try withTable { table in
            var focused = 0
            table.scroll(to: .center(id: 30, innerId: nil, animated: true, focus: .init(focus: true, action: { _ in focused += 1 }), inset: 0))
            let completion = try XCTUnwrap(table.clipView.scrollCompletion)
            XCTAssertNotNil(table.viewNecessary(at: 30, makeIfNecessary: true))
            completion(false)
            XCTAssertEqual(focused, 0)
            table.clipView.updateBounds(to: table.clipView.bounds.origin, cancel: true)
        }
    }

    func testCompletedScrollCommitsFocusAction() throws {
        try withTable { table in
            var focused = 0
            table.scroll(to: .center(id: 30, innerId: nil, animated: true, focus: .init(focus: true, action: { _ in focused += 1 }), inset: 0))
            let completion = try XCTUnwrap(table.clipView.scrollCompletion)
            XCTAssertNotNil(table.viewNecessary(at: 30, makeIfNecessary: true))
            completion(true)
            XCTAssertEqual(focused, 1)
            table.clipView.updateBounds(to: table.clipView.bounds.origin, cancel: true)
        }
    }

    func testCompletedScrollNotifiesVisibleMessageObservers() throws {
        try withTable { table in
            var updates = 0
            table.addScroll(listener: TableScrollListener { _ in updates += 1 })
            table.scroll(to: .center(id: 30, innerId: nil, animated: true, focus: .init(focus: false), inset: 0))
            let completion = try XCTUnwrap(table.clipView.scrollCompletion)
            let beforeCompletion = updates
            completion(true)
            XCTAssertGreaterThan(updates, beforeCompletion)
            table.clipView.updateBounds(to: table.clipView.bounds.origin, cancel: true)
        }
    }

    func testCancelAtCurrentOriginClearsDestination() {
        withTable { table in
            let clip = table.clipView
            clip.scroll(to: NSPoint(x: 0, y: 40), animated: true)
            clip.updateBounds(to: clip.bounds.origin, cancel: true)
            XCTAssertNil(clip.destination)
            XCTAssertFalse(clip.isAnimateScrolling)
            XCTAssertEqual(clip.documentOffset, clip.bounds.origin)
        }
    }
}
