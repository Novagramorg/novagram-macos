import XCTest
import AppKit
@testable import TGUIKit

private final class BackgroundAnimationLayer: SimpleLayer {
    var backgroundAnimations = 0

    override func add(_ animation: CAAnimation, forKey key: String?) {
        if key == "backgroundColor" {
            backgroundAnimations += 1
        }
        super.add(animation, forKey: key)
    }
}

private final class BackgroundAnimationControl: Control {
    override func makeBackingLayer() -> CALayer {
        return BackgroundAnimationLayer()
    }
}

final class ControlStateApplyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testUnchangedStateDoesNotRestartTheBackgroundAnimation() {
        let control = BackgroundAnimationControl(frame: NSMakeRect(0, 0, 40, 40))
        control.animates = true
        control.set(background: .red, for: .Normal)
        control.set(background: .blue, for: .Hover)
        control.layer?.removeAllAnimations()
        let layer = control.layer as! BackgroundAnimationLayer
        layer.backgroundAnimations = 0

        control.controlState = .Normal
        control.controlState = .Normal
        XCTAssertEqual(layer.backgroundAnimations, 0)

        control.controlState = .Hover
        XCTAssertEqual(layer.backgroundAnimations, 1)
        XCTAssertEqual(control.layer?.backgroundColor, NSColor.blue.cgColor)

        control.layer?.removeAllAnimations()
        for _ in 0 ..< 10 {
            control.controlState = .Hover
        }
        XCTAssertEqual(layer.backgroundAnimations, 1)
        XCTAssertEqual(control.layer?.backgroundColor, NSColor.blue.cgColor)
    }
}
