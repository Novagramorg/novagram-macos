import XCTest
import AppKit
import QuartzCore
@testable import TGUIKit

final class AppMenuBubbleAnimationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func makeMenuView(_ size: NSSize = NSMakeSize(220, 300)) -> MenuView {
        let view = MenuView(frame: NSMakeRect(0, 0, size.width, size.height))
        view.setFrameSize(size)
        return view
    }

    private func roundedLayers(_ view: MenuView) -> [CALayer] {
        var layers: [CALayer] = []
        if let layer = view.layer {
            layers.append(layer)
        }
        for subview in view.subviews {
            if let layer = subview.layer {
                layers.append(layer)
            }
        }
        return layers
    }

    func testAppearanceAddsSampledScaleAndFade() {
        let view = makeMenuView()
        view.animateBubbleAppearance(anchor: NSMakePoint(20, 280))
        XCTAssertTrue(view.layer?.animation(forKey: "bubbleScale") is CAKeyframeAnimation)
        XCTAssertTrue(view.layer?.animation(forKey: "bubbleAlpha") is CAKeyframeAnimation)
    }

    func testScaleIsSampledAndLandsOnIdentity() {
        let view = makeMenuView()
        view.animateBubbleAppearance(anchor: NSMakePoint(20, 280))
        guard let scale = view.layer?.animation(forKey: "bubbleScale") as? CAKeyframeAnimation, let values = scale.values as? [NSValue] else {
            return XCTFail("missing sampled scale")
        }
        XCTAssertGreaterThan(values.count, 10, "a sampled spring should have many frames, not a single step")
        XCTAssertTrue(CATransform3DIsIdentity(values.last!.caTransform3DValue), "must settle exactly at the resting size")
    }

    func testCornerMorphsFromPillToRestingAndMonotonically() {
        let view = makeMenuView(NSMakeSize(220, 300))
        let resting = view.layer?.cornerRadius ?? 0
        view.animateBubbleAppearance(anchor: NSMakePoint(20, 280))
        guard let corner = view.layer?.animation(forKey: "bubbleCorner") as? CAKeyframeAnimation, let values = corner.values as? [NSNumber] else {
            return XCTFail("missing corner morph")
        }
        XCTAssertEqual(CGFloat(values.first!.doubleValue), floor(min(220, 300) / 2), "starts as a pill")
        XCTAssertEqual(CGFloat(values.last!.doubleValue), resting, "settles exactly on the resting radius")
        let radii = values.map { $0.doubleValue }
        XCTAssertGreaterThanOrEqual(radii.min()!, Double(resting) - 1.5, "the gentle spring may undershoot the resting radius, but only slightly")
        XCTAssertLessThanOrEqual(radii.max()!, Double(floor(min(220, 300) / 2)), "never rounder than the initial pill")
        XCTAssertEqual(view.layer?.cornerRadius, resting)
    }

    func testEveryRoundedLayerMorphsTogether() {
        let view = makeMenuView()
        view.animateBubbleAppearance(anchor: NSMakePoint(20, 280))
        let morphing = roundedLayers(view).filter { $0.animation(forKey: "bubbleCorner") != nil }
        XCTAssertGreaterThanOrEqual(morphing.count, 3, "shadow layer plus the inner rounded layers must morph")
    }

    func testInnerLayersClipDuringTheMorph() {
        let view = makeMenuView()
        view.animateBubbleAppearance(anchor: NSMakePoint(20, 280))
        for subview in view.subviews {
            if subview.layer?.animation(forKey: "bubbleCorner") != nil {
                XCTAssertTrue(subview.layer?.masksToBounds ?? false, "a morphing inner layer must clip so the pill shape shows")
            }
        }
    }

    func testTinyMenuSkipsTheCornerMorph() {
        let view = makeMenuView(NSMakeSize(20, 20))
        view.animateBubbleAppearance(anchor: NSMakePoint(5, 15))
        XCTAssertNil(view.layer?.animation(forKey: "bubbleCorner"), "no morph when the pill radius is not larger than the resting radius")
        XCTAssertNotNil(view.layer?.animation(forKey: "bubbleScale"), "the scale still plays")
    }
}
