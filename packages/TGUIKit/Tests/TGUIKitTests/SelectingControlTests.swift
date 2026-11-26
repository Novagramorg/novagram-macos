import XCTest
import AppKit
@testable import TGUIKit

final class SelectingControlTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        TGUIKitAccessibility.isEnabled = true
    }

    override func tearDown() {
        System.updateScaleFactor(2)
        TGUIKitAccessibility.isEnabled = true
        super.tearDown()
    }

    private func icon(_ size: CGSize, _ color: NSColor) -> CGImage {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 3, y: 3, width: size.width / 2, height: size.height / 4))
        return context.makeImage()!
    }

    private func icons() -> (CGImage, CGImage) {
        (icon(CGSize(width: 40, height: 32), .red), icon(CGSize(width: 30, height: 42), .blue))
    }

    private func imageLayers(_ view: SelectingControl) -> [CALayer] {
        (view.layer?.sublayers ?? []).filter { $0.contents != nil }
    }

    private func render(_ view: NSView, scale: CGFloat) -> PixelBuffer {
        let window = SnapshotWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        CATransaction.flush()
        let context = CGContext(data: nil, width: Int(ceil(view.bounds.width * scale)), height: Int(ceil(view.bounds.height * scale)), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        if view.layer!.isGeometryFlipped {
            context.translateBy(x: 0, y: view.bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        view.layer!.render(in: context)
        window.contentView = nil
        return PixelBuffer(context.makeImage()!)
    }

    func testBothStatesKeepOnlyTheInteractiveParentView() {
        let (normal, selected) = icons()
        let control = SelectingControl(unselectedImage: normal, selectedImage: selected)
        XCTAssertTrue(control.subviews.isEmpty)
        XCTAssertEqual(imageLayers(control).count, 1)
        control.set(selected: true)
        XCTAssertTrue(control.subviews.isEmpty)
        XCTAssertEqual(imageLayers(control).count, 2)
        control.set(selected: false)
        XCTAssertEqual(imageLayers(control).count, 1)
    }

    func testRenderingMatchesLegacyForStatesSizesAndScales() {
        for scale in [CGFloat(1), 2] {
            System.updateScaleFactor(scale)
            let (normal, selected) = icons()
            for isSelected in [false, true] {
                for size in [CGSize(width: 51, height: 55), CGSize(width: 22, height: 24), CGSize(width: 20.5, height: 21.5)] {
                    let control = SelectingControl(unselectedImage: normal, selectedImage: selected, selected: isSelected)
                    let legacy = LegacySelectingControl(unselectedImage: normal, selectedImage: selected, selected: isSelected)
                    control.setFrameSize(size)
                    legacy.setFrameSize(size)
                    control.layout()
                    legacy.layout()
                    let actual = render(control, scale: scale)
                    let expected = render(legacy, scale: scale)
                    XCTAssertEqual(actual.differingPixels(from: expected, tolerance: 0), 0, "scale=\(scale), selected=\(isSelected), size=\(size)")
                    XCTAssertGreaterThan(actual.bytes.enumerated().filter { $0.offset % 4 == 3 && $0.element > 0 }.count, 20)
                }
            }
        }
    }

    func testCenteredFramesMatchLegacyAfterResizing() {
        let (normal, selected) = icons()
        let control = SelectingControl(unselectedImage: normal, selectedImage: selected, selected: true)
        let legacy = LegacySelectingControl(unselectedImage: normal, selectedImage: selected, selected: true)
        for size in [CGSize(width: 31, height: 47), CGSize(width: 22, height: 24), CGSize(width: 18, height: 10)] {
            control.setFrameSize(size)
            legacy.setFrameSize(size)
            control.layout()
            legacy.layout()
            XCTAssertEqual(imageLayers(control).map(\.frame), legacy.subviews.map(\.frame))
        }
    }

    func testImageSizeAndThemeUpdateRefreshesBothLayers() {
        let (normal, selected) = icons()
        let control = SelectingControl(unselectedImage: normal, selectedImage: selected, selected: true)
        control.setFrameSize(CGSize(width: 60, height: 60))
        let replacementNormal = icon(CGSize(width: 60, height: 24), .green)
        let replacementSelected = icon(CGSize(width: 32, height: 54), .orange)
        control.update(unselectedImage: replacementNormal, selectedImage: replacementSelected, selected: true, animated: false)
        let layers = imageLayers(control)
        XCTAssertTrue(layers[0].contents as AnyObject? === replacementNormal)
        XCTAssertTrue(layers[1].contents as AnyObject? === replacementSelected)
        XCTAssertEqual(layers[0].frame, control.focus(replacementNormal.backingSize))
        XCTAssertEqual(layers[1].frame, control.focus(replacementSelected.backingSize))
        XCTAssertEqual(control.frame.size, CGSize(width: 60, height: 60))
    }

    func testUnselectedUpdateUsesLatestImageWhenSelectedLater() {
        let (normal, selected) = icons()
        let control = SelectingControl(unselectedImage: normal, selectedImage: selected)
        let replacement = icon(CGSize(width: 36, height: 36), .green)
        control.update(unselectedImage: normal, selectedImage: replacement, selected: false, animated: false)
        control.set(selected: true)
        XCTAssertTrue(imageLayers(control).last?.contents as AnyObject? === replacement)
    }

    func testRepeatedSelectionReusesLayerAndDoesNotRestartAnimations() {
        let (normal, selected) = icons()
        let control = SelectingControl(unselectedImage: normal, selectedImage: selected, selected: true)
        let layer = imageLayers(control).last!
        layer.removeAllAnimations()
        for _ in 0..<100 {
            control.set(selected: true, animated: true)
        }
        XCTAssertTrue(imageLayers(control).last === layer)
        XCTAssertTrue(layer.animationKeys()?.isEmpty ?? true)
    }

    func testSelectionAnimationsKeepTheirParameters() {
        let (normal, selected) = icons()
        let control = SelectingControl(unselectedImage: normal, selectedImage: selected)
        let legacy = LegacySelectingControl(unselectedImage: normal, selectedImage: selected)
        control.set(selected: true, animated: true)
        legacy.set(selected: true, animated: true)
        let actual = imageLayers(control).last!
        let expected = legacy.subviews.last!.layer!
        XCTAssertFalse(actual.animationKeys()?.isEmpty ?? true)
        XCTAssertEqual(Set(actual.animationKeys() ?? []), Set(expected.animationKeys() ?? []))
        for key in actual.animationKeys() ?? [] {
            let a = actual.animation(forKey: key) as! CABasicAnimation
            let b = expected.animation(forKey: key) as! CABasicAnimation
            XCTAssertEqual(a.keyPath, b.keyPath)
            XCTAssertEqual(a.duration, b.duration)
            XCTAssertEqual(a.fromValue as? NSNumber, b.fromValue as? NSNumber)
            XCTAssertEqual(a.toValue as? NSNumber, b.toValue as? NSNumber)
        }
    }

    func testInterruptedDeselectCompletionOnlyRemovesOutgoingLayer() {
        let (normal, selected) = icons()
        let control = SelectingControl(unselectedImage: normal, selectedImage: selected, selected: true)
        let outgoing = imageLayers(control).last!
        control.set(selected: false, animated: true)
        control.set(selected: true, animated: false)
        let incoming = imageLayers(control).last!
        XCTAssertFalse(outgoing === incoming)
        for key in outgoing.animationKeys() ?? [] {
            if let animation = outgoing.animation(forKey: key) {
                animation.delegate?.animationDidStop?(animation, finished: true)
            }
        }
        XCTAssertNil(outgoing.superlayer)
        XCTAssertTrue(incoming.superlayer === control.layer)
        XCTAssertEqual(imageLayers(control).count, 2)
        XCTAssertTrue(control.isSelected)
    }

    func testCheckboxAccessibilityAndClickForwardingMatchLegacy() {
        let (normal, selected) = icons()
        let control = SelectingControl(unselectedImage: normal, selectedImage: selected)
        let legacy = LegacySelectingControl(unselectedImage: normal, selectedImage: selected)
        let parent = Control(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let window = SnapshotWindow(contentRect: parent.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = parent
        defer { window.close() }
        parent.addSubview(control)
        control.setAccessibilityLabel("Select message")
        XCTAssertTrue(control.isAccessibilityElement())
        XCTAssertEqual(control.accessibilityRole(), .checkBox)
        XCTAssertEqual(control.accessibilityLabel(), "Select message")
        for selected in [false, true] {
            control.set(selected: selected)
            legacy.set(selected: selected)
            XCTAssertEqual(control.accessibilityValue() as? NSNumber, legacy.accessibilityValue() as? NSNumber)
        }
        XCTAssertEqual(control.userInteractionEnabled, legacy.userInteractionEnabled)
        legacy.setFrameOrigin(CGPoint(x: 40, y: 0))
        parent.addSubview(legacy)
        var parentEvents = 0
        var childEvents = 0
        parent.set(handler: { _ in parentEvents += 1 }, for: .Up)
        for child in [control as Control, legacy as Control] {
            child.set(handler: { _ in childEvents += 1 }, for: .Up)
            child.layoutSubtreeIfNeeded()
            let center = CGPoint(x: child.bounds.midX, y: child.bounds.midY)
            let point = child.convert(center, to: parent.superview)
            let target = parent.hitTest(point)
            XCTAssertNotNil(target)
            let event = NSEvent.mouseEvent(with: .leftMouseUp, location: child.convert(center, to: nil), modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
            target?.mouseUp(with: event)
        }
        XCTAssertEqual(parentEvents, 2)
        XCTAssertEqual(childEvents, 0)
        control.isHidden = true
        XCTAssertFalse(control.isAccessibilityElement())
        control.isHidden = false
        control.isAccessibilityDecorative = true
        XCTAssertFalse(control.isAccessibilityElement())
    }

    func testInteractiveCheckboxKeepsAccessibilityActionAndHitTarget() {
        let (normal, selected) = icons()
        let control = SelectingControl(unselectedImage: normal, selectedImage: selected)
        let parent = Control(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let window = SnapshotWindow(contentRect: parent.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = parent
        defer { window.close() }
        parent.addSubview(control)
        control.userInteractionEnabled = true
        control.set(handler: { control in
            let control = control as! SelectingControl
            control.set(selected: !control.isSelected)
        }, for: .Click)
        let point = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: parent.superview)
        XCTAssertTrue(parent.hitTest(point) === control)
        XCTAssertTrue(control.accessibilityPerformPress())
        XCTAssertTrue(control.isSelected)
        control.isEnabled = false
        XCTAssertFalse(control.accessibilityPerformPress())
        XCTAssertTrue(control.isSelected)
    }

    func testRepeatedToggleDoesNotRetainRemovedLayers() {
        let (normal, selected) = icons()
        weak var removedLayer: CALayer?
        weak var releasedControl: SelectingControl?
        autoreleasepool {
            CATransaction.begin()
            let control = SelectingControl(unselectedImage: normal, selectedImage: selected)
            releasedControl = control
            for _ in 0..<100 {
                control.set(selected: true)
                removedLayer = imageLayers(control).last
                control.set(selected: false)
                XCTAssertEqual(imageLayers(control).count, 1)
            }
            CATransaction.commit()
            CATransaction.flush()
        }
        XCTAssertNil(releasedControl)
        XCTAssertNil(removedLayer)
    }
}
