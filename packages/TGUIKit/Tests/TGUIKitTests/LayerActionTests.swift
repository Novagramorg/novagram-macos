import Cocoa
import XCTest
@testable import TGUIKit

final class LayerActionTests: XCTestCase {
    let keys: Set<String> = ["onOrderIn", "sublayers", "bounds", "frame", "background", "position", "contents", "backgroundColor", "border", "shadowOffset"]

    func testActionKeysAndSuppressionArePreserved() {
        let layer = CALayer()
        layer.disableActions()
        XCTAssertEqual(Set(layer.actions?.keys ?? Dictionary<String, CAAction>().keys), keys)
        for key in keys {
            XCTAssertTrue(layer.actions?[key] is NSNull, key)
            XCTAssertNil(layer.action(forKey: key), key)
        }
        XCTAssertNil(layer.actions?["opacity"])
        XCTAssertNil(layer.actions?["transform"])
    }

    func testRepeatedCallsCancelExplicitAnimationsAndRestoreOverrides() {
        let layer = CALayer()
        for _ in 0..<3 {
            layer.actions = ["opacity": CABasicAnimation(keyPath: "opacity")]
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: .zero)
            animation.toValue = NSValue(point: NSPoint(x: 10, y: 20))
            animation.duration = 20
            layer.add(animation, forKey: "move")
            XCTAssertNotNil(layer.animation(forKey: "move"))
            layer.disableActions()
            XCTAssertTrue(layer.animationKeys()?.isEmpty ?? true)
            XCTAssertNil(layer.actions?["opacity"])
            XCTAssertTrue(layer.actions?["position"] is NSNull)
        }
    }

    func testLayersShareImmutableStorageButOverridesRemainIndependent() throws {
        let first = CALayer(), second = CALayer()
        first.disableActions(); second.disableActions()
        let firstActions = try XCTUnwrap(first.value(forKey: "actions") as? NSDictionary)
        let secondActions = try XCTUnwrap(second.value(forKey: "actions") as? NSDictionary)
        XCTAssertTrue(firstActions === secondActions)
        first.actions?["position"] = CABasicAnimation(keyPath: "position")
        first.actions?["custom"] = CABasicAnimation(keyPath: "opacity")
        XCTAssertTrue(first.actions?["position"] is CABasicAnimation)
        XCTAssertTrue(second.actions?["position"] is NSNull)
        XCTAssertNil(second.actions?["custom"])
        let third = CALayer()
        third.disableActions()
        XCTAssertTrue(third.actions?["position"] is NSNull)
        XCTAssertNil(third.actions?["custom"])
        first.disableActions()
        XCTAssertTrue((first.value(forKey: "actions") as? NSDictionary) === secondActions)
    }

    func testExplicitAnimationsStillRunAfterDisablingImplicitActions() {
        let layer = CALayer()
        layer.disableActions()
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0; animation.toValue = 1; animation.duration = 20
        layer.add(animation, forKey: "fade")
        XCTAssertNotNil(layer.animation(forKey: "fade"))
        XCTAssertTrue(layer.actions?["contents"] is NSNull)
    }

    func testIndependentBackgroundLayersCanInitializeConcurrently() {
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            autoreleasepool {
                let layer = CALayer()
                layer.disableActions()
                XCTAssertEqual(layer.actions?.count, keys.count)
                XCTAssertTrue(layer.actions?["bounds"] is NSNull)
                layer.actions?["bounds"] = CABasicAnimation(keyPath: "bounds")
                layer.disableActions()
                XCTAssertTrue(layer.actions?["bounds"] is NSNull)
            }
        }
    }
}
