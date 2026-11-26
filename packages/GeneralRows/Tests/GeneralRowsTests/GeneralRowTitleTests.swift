import XCTest
import AppKit
import TGUIKit
import TelegramTheme
@testable import GeneralRows

final class GeneralRowTitleTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private let width: CGFloat = 400

    private func makeRow(_ type: GeneralInteractedType, enabled: Bool = true) -> (GeneralInteractedRowView, GeneralInteractedRowItem) {
        let item = GeneralInteractedRowItem(NSMakeSize(width, 50), stableId: 0, name: "Notifications and Sounds", type: type, viewType: .singleItem, enabled: enabled)
        _ = item.makeSize(width, oldWidth: 0)
        let row = GeneralInteractedRowView(frame: NSMakeRect(0, 0, width, item.height))
        row.set(item: item, animated: false)
        row.updateColors()
        row.layout()
        return (row, item)
    }

    func testTitleIsASingleTextViewInTheContainer() {
        let (row, _) = makeRow(.next)
        XCTAssertTrue(row.nameView.superview === row.containerView)
        XCTAssertFalse(row.containerView.subviews.contains(where: { $0 is InteractiveTextView }))
        XCTAssertTrue(row.nameView.subviews.isEmpty)
        XCTAssertFalse(row.nameView.userInteractionEnabled)
        XCTAssertFalse(row.nameView.isSelectable)
        XCTAssertNotNil(row.nameView.textLayout)
    }

    func testTitlesRenderLikeTheInteractiveTextView() {
        for (name, type, enabled) in [("next", GeneralInteractedType.next, true), ("context", .context("On"), true), ("disabled", .next, false)] {
            let (current, _) = makeRow(type, enabled: enabled)
            let (legacy, item) = makeRow(type, enabled: enabled)
            let origin = legacy.nameView.frame.origin
            legacy.nameView.removeFromSuperview()
            let wrapper = InteractiveTextView()
            wrapper.userInteractionEnabled = false
            wrapper.textView.isSelectable = false
            wrapper.set(text: item.nameLayout, context: nil)
            wrapper.setFrameOrigin(origin)
            legacy.containerView.addSubview(wrapper)
            XCTAssertEqual(wrapper.frame, current.nameView.frame, name)
            let new = ViewSnapshot.render(current)
            XCTAssertEqual(new.differingPixels(from: ViewSnapshot.render(legacy), tolerance: 0), 0, name)
            let (bare, _) = makeRow(type, enabled: enabled)
            bare.nameView.removeFromSuperview()
            XCTAssertGreaterThan(new.differingPixels(from: ViewSnapshot.render(bare), tolerance: 0), 500, name)
        }
    }
}
