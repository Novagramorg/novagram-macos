import XCTest
import AppKit
import TGUIKit
import GeneralRows
import TelegramTheme
@testable import InputDataUI

final class InputDataRowSeparatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private let width: CGFloat = 400

    private func makeRow(_ viewType: GeneralViewType, mode: InputDataInputMode = .plain, text: String = "Telegram") -> (InputDataRowView, InputDataRowItem) {
        let item = InputDataRowItem(NSMakeSize(width, 50), stableId: 0, mode: mode, error: nil, viewType: viewType, currentText: text, placeholder: nil, inputPlaceholder: "Name", filter: { $0 }, updated: { _ in }, limit: 64)
        _ = item.makeSize(width, oldWidth: 0)
        let row = InputDataRowView(frame: NSMakeRect(0, 0, width, item.height))
        row.set(item: item, animated: false)
        row.updateColors()
        row.layout()
        return (row, item)
    }

    func testSeparatorIsALayerAboveTheInputs() {
        let (row, _) = makeRow(.firstItem)
        XCTAssertTrue(row.separator.superlayer === row.containerView.layer)
        XCTAssertFalse(row.containerView.subviews.contains(where: { type(of: $0) == View.self && $0.subviews.isEmpty }))
        XCTAssertEqual(row.separator.anchorPoint, .zero)
        XCTAssertEqual(row.separator.zPosition, 1)
        XCTAssertTrue((row.separator.action(forKey: "position") as AnyObject) === nullAction)
        XCTAssertFalse(row.separator.isHidden)
        XCTAssertEqual(row.separator.frame.maxY, row.containerView.frame.height)
        XCTAssertTrue(makeRow(.lastItem).0.separator.isHidden)
    }

    func testSeparatorOutranksEverySiblingOnScreen() {
        let (row, _) = makeRow(.firstItem, mode: .secure)
        let window = SnapshotWindow(contentRect: row.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = row
        row.layoutSubtreeIfNeeded()
        CATransaction.flush()
        defer { window.contentView = nil }
        for layer in row.containerView.layer?.sublayers ?? [] where layer !== row.separator {
            XCTAssertLessThan(layer.zPosition, row.separator.zPosition)
        }
    }

    func testSeparatorRendersLikeTheOldView() {
        for (name, viewType, mode) in [("first", GeneralViewType.firstItem, InputDataInputMode.plain), ("inner", .innerItem, .plain), ("secure", .firstItem, .secure), ("last", .lastItem, .plain)] {
            let (current, _) = makeRow(viewType, mode: mode)
            let (legacy, _) = makeRow(viewType, mode: mode)
            let view = View(frame: legacy.separator.frame)
            view.backgroundColor = theme.colors.border
            view.isHidden = legacy.separator.isHidden
            legacy.separator.removeFromSuperlayer()
            legacy.containerView.addSubview(view)
            let new = ViewSnapshot.render(current, prepare: { _ in current.containerView.layer?.addSublayer(current.separator) })
            XCTAssertEqual(new.differingPixels(from: ViewSnapshot.render(legacy), tolerance: 0), 0, name)
            let (bare, _) = makeRow(viewType, mode: mode)
            let visible = !bare.separator.isHidden
            bare.separator.removeFromSuperlayer()
            let without = new.differingPixels(from: ViewSnapshot.render(bare), tolerance: 0)
            if visible {
                XCTAssertGreaterThan(without, 300, name)
            } else {
                XCTAssertEqual(without, 0, name)
            }
        }
    }

    func testAnimatedSeparatorChangeMatchesTheViewHelpers() {
        let (row, _) = makeRow(.firstItem)
        let legacy = View(frame: row.separator.frame)
        let target = NSMakeRect(row.separator.frame.minX + 20, row.separator.frame.minY + 10, row.separator.frame.width - 40, .borderSize)
        row.changeSeparator(frame: target, animated: true)
        legacy.change(size: target.size, animated: true)
        legacy.change(pos: target.origin, animated: true)
        XCTAssertEqual(row.separator.frame, legacy.frame)
        for key in ["position", "bounds"] {
            let new = row.separator.animation(forKey: key) as? CABasicAnimation
            let old = legacy.layer?.animation(forKey: key) as? CABasicAnimation
            XCTAssertNotNil(new, key)
            if let new = new, let old = old {
                XCTAssertEqual(new.duration, old.duration, key)
                XCTAssertEqual(new.timingFunction, old.timingFunction, key)
                XCTAssertEqual(new.fromValue as? NSValue, old.fromValue as? NSValue, key)
                XCTAssertEqual(new.toValue as? NSValue, old.toValue as? NSValue, key)
            } else {
                XCTFail("missing \(key) animation on the view")
            }
        }
    }

    func testShakeMovesTheSeparatorLikeTheViewShake() {
        let (row, _) = makeRow(.firstItem)
        let legacy = View(frame: row.separator.frame)
        row.shakeView()
        legacy.shake(beep: false)
        let new = row.separator.animations().first
        let old = legacy.layer?.animations().first
        XCTAssertNotNil(new)
        XCTAssertEqual(new?.keyPath, old?.keyPath)
        XCTAssertEqual(new?.duration, old?.duration)
        XCTAssertEqual(new?.repeatCount, old?.repeatCount)
        XCTAssertEqual(new?.autoreverses, old?.autoreverses)
        XCTAssertEqual(new?.fromValue as? NSValue, old?.fromValue as? NSValue)
        XCTAssertEqual(new?.toValue as? NSValue, old?.toValue as? NSValue)
    }
}

private extension CALayer {
    func animations() -> [CABasicAnimation] {
        return (self.animationKeys() ?? []).compactMap { self.animation(forKey: $0) as? CABasicAnimation }
    }
}
