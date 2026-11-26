import Cocoa
import XCTest
import TGUIKit
@testable import SwipeLab

final class SwipeTests: XCTestCase {
    override func setUp() {
        TGUIKitTestBootstrap.install()
    }

    func item(_ id: Int = 0) -> ChatListRowItem { ChatListRowItem(.zero, stableId: id) }

    func testProgressDoesNotRebindContentOrRedrawBadges() {
        let row = CandidateRow(frame: NSRect(x: 0, y: 0, width: 320, height: 70)), item = item()
        var progress: CGFloat? = nil
        item.getHideProgress = { progress }
        row.set(item: item)
        let bindings = row.bindings, displays = item.ctxShortBadgeNode!.displays
        for step in 0..<121 {
            progress = CGFloat(step) / 120
            row.updateHideProgress(animated: false)
            XCTAssertEqual(row.contentView.layer!.opacity, Float(progress!), accuracy: 0.000001)
            XCTAssertEqual(row.badgeShortView!.layer!.opacity, Float(1 - progress!), accuracy: 0.000001)
        }
        XCTAssertEqual(row.bindings, bindings)
        XCTAssertEqual(item.ctxShortBadgeNode!.displays, displays)
    }

    func testExistingContentMatchesReferenceThroughCancelAndFinish() {
        for hidden in [false, true] {
            for badge in [false, true] {
                for live in [false, true] {
                    let current = CandidateRow(frame: .zero), reference = ReferenceRow(frame: .zero)
                    let item = item()
                    item.hideContent = hidden; item.hasLiveItems = live
                    if !badge { item.ctxShortBadgeNode = nil }
                    var progress: CGFloat? = nil
                    item.getHideProgress = { progress }
                    current.set(item: item); reference.set(item: item)
                    for value: CGFloat? in [0, 0.1, 0.5, 1, 0.75, 0, nil, 0.4, 1, nil] {
                        progress = value
                        current.updateHideProgress(animated: value == nil)
                        reference.updateHideProgress(animated: value == nil)
                        XCTAssertEqual(current.contentView.layer?.opacity, reference.contentView.layer?.opacity)
                        XCTAssertEqual(current.badgeShortView?.layer?.opacity, reference.badgeShortView?.layer?.opacity)
                        XCTAssertEqual(current.badgeShortView?.frame, reference.badgeShortView?.frame)
                    }
                }
            }
        }
    }

    func testNewBadgeStartsAtCurrentGestureProgress() {
        for animated in [false, true] {
            let current = CandidateRow(frame: .zero), item = item()
            item.getHideProgress = { 0.6 }
            current.set(item: item, animated: animated)
            XCTAssertEqual(current.badgeShortView!.layer!.opacity, 0.4, accuracy: 0.000001)
        }
    }

    func testSplitLayoutChangeKeepsFullRebinding() {
        let row = CandidateRow(frame: .zero), item = item()
        item.hideContent = false
        row.set(item: item)
        XCTAssertNil(row.badgeShortView)
        item.context.layout = .minimisize
        row.updateHideProgress(animated: false)
        XCTAssertEqual(row.bindings, 2)
        XCTAssertNotNil(row.badgeShortView)
        XCTAssertEqual(row.contentView.layer?.opacity, 0)
    }

    func testReboundItemKeepsItsContentAndBadgeState() {
        let row = CandidateRow(frame: .zero), first = item(), next = item(1)
        first.getHideProgress = { 0.9 }
        row.set(item: first)
        next.getHideProgress = { 0.2 }
        row.set(item: next)
        row.updateHideProgress(animated: false)
        XCTAssertEqual(row.bindings, 2)
        XCTAssertEqual(row.contentView.layer!.opacity, 0.2, accuracy: 0.000001)
        XCTAssertEqual(row.badgeShortView!.layer!.opacity, 0.8, accuracy: 0.000001)
    }

    func testProgressCallbackCannotOverwriteNewBinding() {
        let row = CandidateRow(frame: .zero), first = item(), next = item(1)
        next.getHideProgress = { 0.25 }
        row.set(item: first)
        first.getHideProgress = { row.set(item: next); return 0.9 }
        row.updateHideProgress(animated: false)
        XCTAssertTrue(row.item === next)
        XCTAssertEqual(row.contentView.layer!.opacity, 0.25, accuracy: 0.000001)
        XCTAssertEqual(row.badgeShortView!.layer!.opacity, 0.75, accuracy: 0.000001)
    }

    func testMissingOrNonChatItemDoesNothing() {
        let row = CandidateRow(frame: .zero)
        row.updateHideProgress(animated: false)
        XCTAssertEqual(row.bindings, 0)
        row.set(item: TableRowItem(.zero, stableId: 0))
        row.updateHideProgress(animated: true)
        XCTAssertEqual(row.bindings, 1)
    }

    func testVisibilityUpdatesDoNotInvalidateLayout() {
        let row = CandidateRow(frame: .zero), item = item()
        item.getHideProgress = { 0.5 }
        row.set(item: item)
        row.layoutRequests = 0; row.contentView.layoutRequests = 0
        row.updateHideProgress(animated: false)
        XCTAssertEqual(row.layoutRequests, 0)
        XCTAssertEqual(row.contentView.layoutRequests, 0)
    }
    func testLayerPixelsMatchReferenceAcrossGestureStates() throws {
        let reference = ReferenceRow(frame: NSRect(x: 0, y: 0, width: 320, height: 70))
        let current = CandidateRow(frame: reference.frame)
        let item = item()
        var progress: CGFloat? = nil
        item.getHideProgress = { progress }
        reference.set(item: item); current.set(item: item)
        for scale in [1, 2] {
            for value: CGFloat? in [nil, 0, 0.1, 0.25, 0.5, 0.75, 1, nil] {
                progress = value
                reference.updateHideProgress(animated: false)
                current.updateHideProgress(animated: false)
                let before = try render(reference, scale: scale)
                let after = try render(current, scale: scale)
                XCTAssertEqual(before, after, "scale=\(scale), progress=\(String(describing: value))")
                XCTAssertTrue(after.contains { $0 != 0 })
            }
        }
    }

    private func render(_ row: RowEnvironment, scale: Int) throws -> Data {
        let window = NSWindow(contentRect: row.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = row
        defer { window.contentView = nil; window.close() }
        row.layoutSubtreeIfNeeded()
        CATransaction.flush()
        let width = 320 * scale, height = 70 * scale
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        row.containerView.layer!.render(in: context)
        return Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
    }

    func testAnimatedNewBadgeTargetsGestureOpacity() throws {
        let row = CandidateRow(frame: NSRect(x: 0, y: 0, width: 320, height: 70)), item = item()
        item.getHideProgress = { 0.75 }
        row.set(item: item, animated: true)
        let animation = try XCTUnwrap(row.badgeShortView?.layer?.animation(forKey: "opacity") as? CABasicAnimation)
        XCTAssertEqual((animation.toValue as? NSNumber)?.doubleValue, 0.25)
        XCTAssertEqual(row.badgeShortView?.layer?.opacity, 0.25)
    }

}
