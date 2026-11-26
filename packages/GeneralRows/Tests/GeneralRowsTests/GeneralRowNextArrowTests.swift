import XCTest
import AppKit
import TGUIKit
import TelegramTheme
@testable import GeneralRows

final class GeneralRowNextArrowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private let width: CGFloat = 400

    private func makeRow(_ type: GeneralInteractedType, enabled: Bool = true, viewType: GeneralViewType = .singleItem) -> GeneralInteractedRowView {
        let item = GeneralInteractedRowItem(NSMakeSize(width, 50), stableId: 0, name: "Privacy and Security", type: type, viewType: viewType, enabled: enabled)
        _ = item.makeSize(width, oldWidth: 0)
        let row = GeneralInteractedRowView(frame: NSMakeRect(0, 0, width, item.height))
        row.set(item: item, animated: false)
        row.updateColors()
        row.layout()
        return row
    }

    private func hostInWindow(_ view: NSView) -> NSWindow {
        let window = SnapshotWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        return window
    }

    private func legacyArrow(for row: GeneralInteractedRowView) -> ImageView {
        let arrow = ImageView()
        if let contents = row.nextView.contents {
            arrow.image = (contents as! CGImage)
        }
        arrow.frame = row.nextView.frame
        arrow.isHidden = row.nextView.isHidden
        arrow.alphaValue = CGFloat(row.nextView.opacity)
        row.nextView.removeFromSuperlayer()
        row.containerView.addSubview(arrow, positioned: .below, relativeTo: row.containerView.subviews.first)
        return arrow
    }

    func testArrowIsALayerBetweenTheBorderAndTheRowContent() {
        let row = makeRow(.next)
        let window = hostInWindow(row)
        defer { window.contentView = nil }
        XCTAssertFalse(row.containerView.subviews.contains(where: { $0 is ImageView }))
        let sublayers = row.containerView.layer?.sublayers ?? []
        let border = sublayers.firstIndex(where: { $0 === row.borderView }) ?? -1
        let arrow = sublayers.firstIndex(where: { $0 === row.nextView }) ?? -1
        XCTAssertEqual(arrow, border + 1)
        for view in row.containerView.subviews {
            let index = sublayers.firstIndex(where: { $0 === view.layer }) ?? -1
            XCTAssertGreaterThan(index, arrow, String(describing: type(of: view)))
        }
        XCTAssertFalse(row.nextView.isHidden)
        XCTAssertNotNil(row.nextView.contents)
        XCTAssertTrue((row.nextView.action(forKey: "opacity") as AnyObject) === nullAction)
    }

    func testRowsRenderLikeTheArrowImageView() {
        let cases: [(String, GeneralInteractedType, Bool)] = [
            ("next", .next, true),
            ("nextContext", .nextContext("On"), true),
            ("switchable", .switchable(true), true),
            ("disabled", .next, false)
        ]
        for (name, type, enabled) in cases {
            let current = makeRow(type, enabled: enabled)
            let legacy = makeRow(type, enabled: enabled)
            _ = legacyArrow(for: legacy)
            let new = ViewSnapshot.render(current)
            let old = ViewSnapshot.render(legacy)
            let doubled = makeRow(type, enabled: enabled)
            let copy = SimpleLayer()
            copy.anchorPoint = .zero
            copy.contents = doubled.nextView.contents
            copy.frame = doubled.nextView.bounds
            doubled.nextView.insertSublayer(copy, at: 0)
            XCTAssertEqual(ViewSnapshot.render(doubled).differingPixels(from: old, tolerance: 0), 0, name)
            let arrowFrame = current.nextView.frame.offsetBy(dx: current.containerView.frame.minX, dy: current.containerView.frame.minY)
            let arrowRect = NSRect(x: arrowFrame.minX * 2, y: arrowFrame.minY * 2, width: arrowFrame.width * 2, height: arrowFrame.height * 2).insetBy(dx: -1, dy: -1)
            for y in 0 ..< new.height {
                for x in 0 ..< new.width where !arrowRect.contains(NSPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                    let index = (y * new.width + x) * 4
                    if (0 ..< 4).contains(where: { new.bytes[index + $0] != old.bytes[index + $0] }) {
                        XCTFail("\(name): pixel \(x),\(y) outside the arrow differs")
                        return
                    }
                }
            }
            let bare = makeRow(type, enabled: enabled)
            let arrowVisible = !bare.nextView.isHidden && bare.nextView.contents != nil
            bare.nextView.removeFromSuperlayer()
            let without = new.differingPixels(from: ViewSnapshot.render(bare), tolerance: 0)
            if arrowVisible {
                XCTAssertGreaterThan(without, 40, name)
            } else {
                XCTAssertEqual(without, 0, name)
            }
        }
    }

    func testArrowGeometryMatchesTheViewHelpers() {
        let row = makeRow(.next)
        let legacy = ImageView()
        legacy.image = (row.nextView.contents as! CGImage)
        legacy.sizeToFit()
        row.containerView.addSubview(legacy)
        legacy.centerY(x: row.nextView.frame.minX, addition: -1)
        XCTAssertEqual(row.nextView.frame.size, legacy.frame.size)
        XCTAssertEqual(row.nextView.frame.origin, legacy.frame.origin)
        XCTAssertEqual(row.nextView.opacity, 1.0)
        XCTAssertEqual(makeRow(.next, enabled: false).nextView.opacity, 0.7, accuracy: 0.0001)
    }
}
