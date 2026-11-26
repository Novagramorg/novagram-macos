import XCTest
import AppKit
import TGUIKit
import TelegramTheme
@testable import ShortPeerRow

final class ShortPeerRowSeparatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private let rowFrame = NSMakeRect(0, 0, 400, 50)
    private let separatorFrame = NSMakeRect(64, 49, 322, .borderSize)
    private let rightFrame = NSMakeRect(399, 0, .borderSize, 50)

    private func makeRow() -> ShortPeerRowView {
        let row = ShortPeerRowView(frame: rowFrame)
        row.containerView.frame = row.bounds
        row.containerView.setCorners([], frame: row.bounds)
        row.containerView.backgroundColor = theme.colors.background
        row.container.backgroundColor = theme.colors.background
        row.container.frame = NSMakeRect(10, 5, 380, 40)
        row.separator.frame = separatorFrame
        row.separator.backgroundColor = theme.colors.border.cgColor
        row.rightSeparatorView.frame = rightFrame
        row.rightSeparatorView.backgroundColor = theme.colors.border.cgColor
        return row
    }

    private func hostInWindow(_ view: NSView) -> NSWindow {
        let window = SnapshotWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.layout()
        CATransaction.flush()
        return window
    }

    private func index(of layer: CALayer?, in host: CALayer?) -> Int {
        return host?.sublayers?.firstIndex(where: { $0 === layer }) ?? -1
    }

    func testSeparatorsAreLayersDrawnAboveTheContentContainer() {
        let row = makeRow()
        let window = hostInWindow(row)
        defer { window.contentView = nil }
        let host = row.containerView.layer
        XCTAssertFalse(row.containerView.subviews.contains(where: { type(of: $0) == View.self }))
        XCTAssertTrue(row.separator.superlayer === host)
        XCTAssertTrue(row.rightSeparatorView.superlayer === host)
        XCTAssertGreaterThanOrEqual(index(of: row.container.layer, in: host), 0)
        XCTAssertGreaterThan(row.separator.zPosition, row.container.layer?.zPosition ?? 0)
        XCTAssertGreaterThan(row.rightSeparatorView.zPosition, row.container.layer?.zPosition ?? 0)
        XCTAssertEqual(row.separator.anchorPoint, .zero)
        XCTAssertTrue((row.separator.action(forKey: "position") as AnyObject) === nullAction)
    }

    func testControlsAddedLaterDoNotTouchTheSeparatorLines() {
        let row = makeRow()
        let window = hostInWindow(row)
        defer { window.contentView = nil }
        let control = View(frame: NSMakeRect(300, 10, 60, 30))
        control.backgroundColor = .systemRed
        row.containerView.addSubview(control)
        CATransaction.flush()
        XCTAssertFalse(control.frame.intersects(row.separator.frame))
        XCTAssertFalse(control.frame.intersects(row.rightSeparatorView.frame))
    }

    func testSeparatorsRenderLikeTheOldViews() {
        let current = makeRow()
        let legacy = makeRow()
        legacy.separator.removeFromSuperlayer()
        legacy.rightSeparatorView.removeFromSuperlayer()
        let right = View(frame: rightFrame)
        right.backgroundColor = theme.colors.border
        let bottom = View(frame: separatorFrame)
        bottom.backgroundColor = theme.colors.border
        legacy.containerView.addSubview(right, positioned: .above, relativeTo: legacy.container)
        legacy.containerView.addSubview(bottom, positioned: .above, relativeTo: right)
        let new = ViewSnapshot.render(current)
        let old = ViewSnapshot.render(legacy)
        XCTAssertEqual(new.differingPixels(from: old, tolerance: 0), 0)
        let bare = makeRow()
        bare.separator.removeFromSuperlayer()
        bare.rightSeparatorView.removeFromSuperlayer()
        XCTAssertGreaterThan(new.differingPixels(from: ViewSnapshot.render(bare), tolerance: 0), 600)
    }

    func testAnimatedSeparatorChangeMatchesTheViewHelpers() {
        let row = makeRow()
        let legacy = View(frame: separatorFrame)
        let target = NSMakeRect(86, 69, 290, .borderSize)
        row.changeSeparator(frame: target, animated: true)
        legacy.change(size: target.size, animated: true)
        legacy.change(pos: target.origin, animated: true)
        XCTAssertEqual(row.separator.frame, legacy.frame)
        for key in ["position", "bounds"] {
            let new = row.separator.animation(forKey: key) as? CABasicAnimation
            let old = legacy.layer?.animation(forKey: key) as? CABasicAnimation
            XCTAssertNotNil(new, key)
            XCTAssertEqual(new == nil, old == nil, key)
            if let new = new, let old = old {
                XCTAssertEqual(new.duration, old.duration, key)
                XCTAssertEqual(new.timingFunction, old.timingFunction, key)
                XCTAssertEqual(new.fromValue as? NSValue, old.fromValue as? NSValue, key)
                XCTAssertEqual(new.toValue as? NSValue, old.toValue as? NSValue, key)
            }
        }
        row.changeSeparator(frame: separatorFrame, animated: false)
        XCTAssertEqual(row.separator.frame, separatorFrame)
        XCTAssertNil(row.separator.animation(forKey: "position"))
        XCTAssertNil(row.separator.animation(forKey: "bounds"))
    }

    func testAvatarSitsDirectlyInTheContentContainer() {
        let row = makeRow()
        XCTAssertTrue(row.image.superview === row.container)
        XCTAssertTrue(row.container.subviews.first === row.image)
        let wrappers = row.container.subviews.filter { type(of: $0) == Control.self && $0.subviews.count == 1 && $0.subviews.first === row.image }
        XCTAssertTrue(wrappers.isEmpty)
    }

    func testAvatarOpensTheStoryAndScalesOnClick() {
        let row = makeRow()
        XCTAssertTrue(row.image.hasHandlers)
        XCTAssertTrue(row.image.scaleOnClick)
        XCTAssertFalse(row.image.userInteractionEnabled)
    }
}
