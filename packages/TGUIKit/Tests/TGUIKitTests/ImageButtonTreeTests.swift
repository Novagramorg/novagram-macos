import XCTest
import AppKit
@testable import TGUIKit

final class ImageButtonTreeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func makeButton() -> ImageButton {
        let button = ImageButton()
        button.set(image: testImage(CGSize(width: 40, height: 40)), for: .Normal)
        _ = button.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
        return button
    }

    func testGlassTextButtonReceivesClicksAcrossItsSurface() {
        let parent = View(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        let window = SnapshotWindow(contentRect: parent.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = parent
        defer { window.contentView = nil }
        let button = TextButton(frame: NSRect(x: 20, y: 20, width: 300, height: 40))
        button.autoSizeToFit = false
        button.set(text: "Start Crafting", for: .Normal)
        button.setGlassEffect(tintColor: .systemBlue)
        parent.addSubview(button)
        button.layoutSubtreeIfNeeded()
        for point in [NSPoint(x: 15, y: 20), NSPoint(x: 150, y: 20), NSPoint(x: 285, y: 20)] {
            let target = parent.hitTest(button.convert(point, to: parent.superview))
            XCTAssertTrue(target === button, "Hit \(String(describing: target)) in button \(button.frame)")
        }
        button.isHidden = true
        XCTAssertFalse(parent.hitTest(NSPoint(x: 170, y: 40)) === button)
    }

    func testPlainButtonHoldsOnlyItsImage() {
        let button = makeButton()
        XCTAssertEqual(button.subviews.count, 1)
        XCTAssertTrue(button.subviews.first === button.imageView)
        XCTAssertNil(button.additionBackgroundView)
    }

    func testClearBackgroundKeepsThePlateDetached() {
        let button = makeButton()
        button.set(additionBackgroundColor: .clear, for: .Normal)
        XCTAssertEqual(button.subviews.count, 1)
        XCTAssertNil(button.additionBackgroundView?.superview)
        XCTAssertNil(button.additionBackgroundView)
    }

    func testColoredBackgroundAttachesThePlateBelowTheImage() {
        let button = makeButton()
        button.set(additionBackgroundColor: .red, for: .Normal)
        XCTAssertEqual(button.subviews.count, 2)
        XCTAssertTrue(button.subviews.first === button.additionBackgroundView)
        XCTAssertTrue(button.subviews.last === button.imageView)
        XCTAssertEqual(button.additionBackgroundView?.frame, button.bounds)
    }

    func testPlateAttachesBelowTheGlass() {
        let button = makeButton()
        button.setGlassEffect(size: NSMakeSize(40, 40))
        button.set(additionBackgroundColor: .red, for: .Normal)
        XCTAssertEqual(viewClassNames(button.subviews), ["View", "LiquidGlassView", "ImageView"])
        XCTAssertTrue(button.subviews.first === button.additionBackgroundView)
    }

    func testPlateAttachesAboveTheBlurBackground() {
        let button = makeButton()
        button.blurBackground = .white
        button.set(additionBackgroundColor: .red, for: .Normal)
        XCTAssertEqual(viewClassNames(button.subviews), ["VisualEffect", "View", "ImageView"])
    }

    func testHoverOnlyBackgroundAttachesOnHover() {
        let button = makeButton()
        button.set(additionBackgroundColor: .red, for: .Hover)
        XCTAssertNil(button.additionBackgroundView?.superview)
        button.apply(state: .Hover)
        XCTAssertTrue(button.subviews.first === button.additionBackgroundView)
    }

    func testTextButtonHoldsNoPlate() {
        let button = TextButton()
        button.set(text: "Done", for: .Normal)
        XCTAssertEqual(viewClassNames(button.subviews), ["ImageView", "TextView"])
        XCTAssertNil(button.additionBackgroundView)
    }

    func testPlainButtonStateAndLayoutUpdatesNeverAllocateAPlate() {
        let button = makeButton()
        for state in [ControlState.Normal, .Hover, .Highlight, .Other] {
            button.controlState = state
            button.isEnabled = false
            button.isEnabled = true
            button.isSelected = true
            button.isSelected = false
            button.updateLayout(size: NSSize(width: 51, height: 43), transition: .immediate)
        }
        XCTAssertNil(button.additionBackgroundView)
    }

    func testApplyingStateRestoresImageOpacityWhenItChanged() {
        let button = makeButton()
        button.imageView.alphaValue = 0.3
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            button.apply(state: .Hover)
        }
        XCTAssertEqual(button.imageView.alphaValue, 1)
        XCTAssertNil(button.additionBackgroundView)
    }

    func testLatePlateUsesCurrentSizeMultiplierAndRadius() {
        let button = makeButton()
        button.setFrameSize(NSSize(width: 60, height: 40))
        button.set(additionBackgroundMultiplier: 0.5, for: .Hover)
        button.set(cornerRadius: .half, for: .Hover)
        button.set(additionBackgroundColor: .blue, for: .Hover)
        XCTAssertNil(button.additionBackgroundView)
        button.controlState = .Hover
        XCTAssertEqual(button.additionBackgroundView?.frame, CGRect(x: 15, y: 10, width: 30, height: 20))
        XCTAssertEqual(button.additionBackgroundView?.layer?.cornerRadius, 15)
        XCTAssertEqual(button.additionBackgroundView?.layer?.backgroundColor, NSColor.blue.cgColor)
    }

    func testPlateSurvivesTransparentStateAndIsReused() {
        let button = makeButton()
        button.set(additionBackgroundColor: .red, for: .Hover)
        button.controlState = .Hover
        let plate = button.additionBackgroundView
        button.controlState = .Normal
        XCTAssertEqual(plate?.layer?.backgroundColor, NSColor.clear.cgColor)
        button.controlState = .Hover
        XCTAssertTrue(button.additionBackgroundView === plate)
        XCTAssertEqual(button.subviews.count, 2)
    }

    func testRadiusConfiguredBeforeColorIsPreservedInAnotherState() {
        let button = makeButton()
        button.set(cornerRadius: .half, for: .Normal)
        XCTAssertEqual(button.additionBackgroundView?.layer?.cornerRadius, 20)
        button.set(additionBackgroundColor: .blue, for: .Hover)
        button.controlState = .Hover
        XCTAssertEqual(button.additionBackgroundView?.layer?.cornerRadius, 20)
        XCTAssertEqual(button.additionBackgroundView?.frame, button.bounds)
    }

    func testHoverAnimationCanStartWhenPlateIsCreated() {
        let button = makeButton()
        button.set(hoverAdditionPolicy: .enlarge(value: 1.2), for: .Hover)
        button.set(additionBackgroundColor: .blue, for: .Hover)
        button.controlState = .Hover
        let layer = button.additionBackgroundView?.layer
        XCTAssertFalse(layer?.animationKeys()?.isEmpty ?? true)
        XCTAssertNotNil(button.additionBackgroundView?.superview)
    }

    func testGlassWithoutAdditionBackgroundDoesNotAllocatePlate() {
        let button = makeButton()
        button.setGlassEffect(size: NSSize(width: 40, height: 40))
        button.controlState = .Hover
        button.updateLayout()
        XCTAssertNil(button.additionBackgroundView)
        XCTAssertEqual(viewClassNames(button.subviews), ["LiquidGlassView", "ImageView"])
    }
}

func viewClassNames(_ views: [NSView]) -> [String] {
    return views.map { String(describing: type(of: $0)) }
}
