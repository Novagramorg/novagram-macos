import XCTest
import AppKit
import TGUIKit
import TelegramTheme
@testable import GeneralRows

final class GeneralRowBorderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private let width: CGFloat = 400

    private func makeItem(_ viewType: GeneralViewType, name: String = "Notifications and Sounds") -> GeneralInteractedRowItem {
        let item = GeneralInteractedRowItem(NSMakeSize(width, 50), stableId: 0, name: name, type: .next, viewType: viewType)
        _ = item.makeSize(width, oldWidth: 0)
        return item
    }

    private func makeRow(_ item: GeneralInteractedRowItem) -> GeneralInteractedRowView {
        let row = GeneralInteractedRowView(frame: NSMakeRect(0, 0, width, item.height))
        row.set(item: item, animated: false)
        row.updateColors()
        row.layout()
        return row
    }

    private func attachLegacyBorder(to row: GeneralInteractedRowView, item: GeneralInteractedRowItem) -> View {
        let legacy = View(frame: row.borderView.frame)
        legacy.backgroundColor = theme.colors.border
        legacy.isHidden = !item.hasBorder
        row.borderView.isHidden = true
        row.containerView.addSubview(legacy, positioned: .below, relativeTo: row.containerView.subviews.first)
        return legacy
    }

    private func hostInWindow(_ view: NSView) -> NSWindow {
        let window = SnapshotWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        return window
    }

    func testBorderIsABottomLayerOfTheContainerInsteadOfAView() {
        let row = GeneralContainableRowView(frame: NSMakeRect(0, 0, width, 50))
        let window = hostInWindow(row)
        defer { window.contentView = nil }
        XCTAssertEqual(row.subviews.count, 1)
        XCTAssertTrue(row.subviews.first === row.containerView)
        XCTAssertTrue(row.containerView.subviews.isEmpty)
        XCTAssertTrue(row.containerView.layer?.sublayers?.first === row.borderView)
        XCTAssertEqual(row.borderView.anchorPoint, .zero)
        XCTAssertFalse(row.borderView.action(forKey: "position") is CAAnimation)
        XCTAssertFalse(row.borderView.action(forKey: "backgroundColor") is CAAnimation)
        XCTAssertTrue((row.borderView.action(forKey: "position") as AnyObject) === nullAction)
    }

    func testContentAddedToTheRowStaysAboveTheBorder() {
        let row = GeneralContainableRowView(frame: NSMakeRect(0, 0, width, 50))
        let first = View(frame: NSMakeRect(0, 0, width, 50))
        let second = View(frame: NSMakeRect(0, 0, width, 50))
        let third = View(frame: NSMakeRect(0, 0, width, 50))
        row.addSubview(first)
        row.addSubview(second, positioned: .below, relativeTo: first)
        row.addSubview(third, positioned: .above, relativeTo: first)
        let window = hostInWindow(row)
        defer { window.contentView = nil }
        let sublayers = row.containerView.layer?.sublayers ?? []
        let border = sublayers.firstIndex(where: { $0 === row.borderView })
        XCTAssertEqual(border, 0)
        for view in [first, second, third] {
            let index = sublayers.firstIndex(where: { $0 === view.layer })
            XCTAssertNotNil(index)
            XCTAssertGreaterThan(index ?? -1, border ?? Int.max)
        }
    }

    func testBorderCanSitAboveABottomBackground() {
        let row = GeneralContainableRowView(frame: NSMakeRect(0, 0, width, 50))
        let content = View(frame: NSMakeRect(0, 0, width, 50))
        row.addSubview(content)
        let background = View(frame: NSMakeRect(0, 0, width, 50))
        row.containerView.addSubview(background, positioned: .below, relativeTo: nil)
        let window = hostInWindow(row)
        defer { window.contentView = nil }
        row.containerView.layer?.insertSublayer(row.borderView, above: background.layer!)
        let sublayers = row.containerView.layer?.sublayers ?? []
        let backgroundIndex = sublayers.firstIndex(where: { $0 === background.layer }) ?? -1
        let borderIndex = sublayers.firstIndex(where: { $0 === row.borderView }) ?? -1
        let contentIndex = sublayers.firstIndex(where: { $0 === content.layer }) ?? -1
        XCTAssertLessThan(backgroundIndex, borderIndex)
        XCTAssertLessThan(borderIndex, contentIndex)
    }

    func testBorderGeometryAndVisibilityFollowTheItem() {
        let item = makeItem(.firstItem)
        let row = makeRow(item)
        let window = hostInWindow(row)
        defer { window.contentView = nil }
        XCTAssertFalse(row.borderView.isHidden)
        let container = row.containerView.frame
        let expected = NSMakeRect(item.viewType.innerInset.left, container.height - .borderSize, container.width - item.viewType.innerInset.left - item.viewType.innerInset.right, .borderSize)
        XCTAssertEqual(row.borderView.frame, expected)
        let (plain, _) = makePlain(.firstItem)
        let plainWindow = hostInWindow(plain)
        defer { plainWindow.contentView = nil }
        XCTAssertEqual(plain.borderView.backgroundColor, theme.colors.border.cgColor)
        XCTAssertTrue(makeRow(makeItem(.lastItem)).borderView.isHidden)
        XCTAssertTrue(makeRow(makeItem(.singleItem)).borderView.isHidden)
    }

    private final class PlainRow: GeneralContainableRowView {
    }

    private func makePlain(_ viewType: GeneralViewType) -> (PlainRow, GeneralRowItem) {
        let item = GeneralRowItem(NSMakeSize(width, 50), height: 50, stableId: 0, viewType: viewType)
        _ = item.makeSize(width, oldWidth: 0)
        let row = PlainRow(frame: NSMakeRect(0, 0, width, item.height))
        row.set(item: item, animated: false)
        row.updateColors()
        row.layout()
        return (row, item)
    }

    func testPlainRowsWhoseOnlySeparatorIsTheBorderRenderTheSame() {
        for viewType in [GeneralViewType.firstItem, .innerItem, .lastItem, .singleItem] {
            let (current, currentItem) = makePlain(viewType)
            let (legacyRow, legacyItem) = makePlain(viewType)
            let legacy = View(frame: legacyRow.borderView.frame)
            legacy.backgroundColor = theme.colors.border
            legacy.isHidden = !legacyItem.hasBorder
            legacyRow.borderView.removeFromSuperlayer()
            legacyRow.containerView.addSubview(legacy)
            let new = ViewSnapshot.render(current)
            let old = ViewSnapshot.render(legacyRow)
            XCTAssertEqual(new.differingPixels(from: old, tolerance: 0), 0, "\(viewType)")
            let (bare, _) = makePlain(viewType)
            bare.borderView.removeFromSuperlayer()
            let without = ViewSnapshot.render(bare)
            if currentItem.hasBorder {
                XCTAssertGreaterThan(new.differingPixels(from: without, tolerance: 0), 300, "\(viewType)")
            } else {
                XCTAssertEqual(new.differingPixels(from: without, tolerance: 0), 0, "\(viewType)")
            }
        }
    }

    func testRowsRenderLikeTheBorderView() {
        for viewType in [GeneralViewType.firstItem, .innerItem, .lastItem, .singleItem] {
            let currentItem = makeItem(viewType)
            let current = makeRow(currentItem)
            let legacyItem = makeItem(viewType)
            let legacy = makeRow(legacyItem)
            _ = attachLegacyBorder(to: legacy, item: legacyItem)
            let new = ViewSnapshot.render(current)
            let old = ViewSnapshot.render(legacy)
            XCTAssertEqual(new.differingPixels(from: old, tolerance: 0), 0, "\(viewType)")
        }
    }

    func testAnimatedRelayoutMovesTheBorderLikeTheView() {
        let item = makeItem(.firstItem)
        let current = makeRow(item)
        let legacyItem = makeItem(.firstItem)
        let legacyRow = makeRow(legacyItem)
        let legacy = attachLegacyBorder(to: legacyRow, item: legacyItem)
        let size = NSMakeSize(width - 60, item.height + 20)
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)
        current.setFrameSize(size)
        current.updateLayout(size: size, transition: transition)
        legacyRow.setFrameSize(size)
        legacyRow.updateLayout(size: size, transition: .immediate)
        transition.updateFrame(view: legacy, frame: current.borderView.frame)
        XCTAssertEqual(current.borderView.frame, legacy.frame)
        for key in ["position", "bounds"] {
            let new = current.borderView.animation(forKey: key) as? CABasicAnimation
            let old = legacy.layer?.animation(forKey: key) as? CABasicAnimation
            XCTAssertEqual(new == nil, old == nil, key)
            if let new = new, let old = old {
                XCTAssertEqual(new.duration, old.duration, key)
                XCTAssertEqual(new.timingFunction, old.timingFunction, key)
                XCTAssertEqual(new.fromValue as? NSValue, old.fromValue as? NSValue, key)
                XCTAssertEqual(new.toValue as? NSValue, old.toValue as? NSValue, key)
            }
        }
    }

    func testRowsNoLongerCarryAnEmptyBorderView() {
        let row = makeRow(makeItem(.firstItem))
        let emptyPlainViews = row.containerView.subviews.filter { type(of: $0) == View.self && $0.subviews.isEmpty }
        XCTAssertTrue(emptyPlainViews.isEmpty)
    }
}
