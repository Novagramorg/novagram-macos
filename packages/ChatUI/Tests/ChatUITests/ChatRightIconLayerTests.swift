import XCTest
import AppKit
import TGUIKit
@testable import ChatUI

final class ChatRightIconLayerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func icon(_ size: CGSize) -> CGImage {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemGreen.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        return context.makeImage()!
    }

    private let rects: [NSRect] = [NSMakeRect(12, 3, 20, 20), NSMakeRect(0, 0, 14, 10), NSMakeRect(40.5, 2, 9, 9)]

    func testIconLayerKeepsTheImageViewFrame() {
        for rect in rects {
            let image = icon(CGSize(width: 28, height: 20))
            let view = ImageView(frame: rect)
            view.image = image
            view.sizeToFit()
            let layer = ChatRightView.makeIconLayer(rect)
            layer.image = image
            layer.sizeToFit()
            XCTAssertEqual(layer.frame, view.frame, "\(rect)")
            XCTAssertTrue((layer.contents as AnyObject?) === image)
            XCTAssertEqual(layer.masksToBounds, view.layer?.masksToBounds)
            XCTAssertEqual(layer.contentsGravity, view.layer?.contentsGravity)
        }
    }

    func testIconLayerFollowsFrameUpdatesLikeTheView() {
        for rect in rects {
            let view = ImageView(frame: rect)
            let layer = ChatRightView.makeIconLayer(rect)
            let target = rect.offsetBy(dx: 7, dy: -2).insetBy(dx: -1, dy: 1)
            ContainedViewLayoutTransition.immediate.updateFrame(view: view, frame: target)
            ContainedViewLayoutTransition.immediate.updateFrame(layer: layer, frame: target)
            XCTAssertEqual(layer.frame, view.frame, "\(rect)")
            XCTAssertEqual(layer.position, view.frame.origin, "\(rect)")
        }
    }

    func testIconLayerRendersAboveViewSiblings() {
        let layer = ChatRightView.makeIconLayer(rects[0])
        XCTAssertGreaterThan(layer.zPosition, 0)
        XCTAssertEqual(layer.anchorPoint, .zero)
    }

    func testAnimatedRemovalMatchesSubviewRemoval() {
        for rect in rects {
            let host = View(frame: NSMakeRect(0, 0, 100, 40))
            let view = ImageView(frame: rect)
            host.addSubview(view)
            let layer = ChatRightView.makeIconLayer(rect)
            host.layer?.addSublayer(layer)

            performSubviewRemoval(view, animated: true, scale: true)
            ChatRightView.removeIcon(layer, animated: true)

            let legacyKeys = Set(view.layer?.animationKeys() ?? [])
            let currentKeys = Set(layer.animationKeys() ?? [])
            XCTAssertEqual(legacyKeys, currentKeys, "\(rect)")
            for key in legacyKeys {
                guard let legacy = view.layer?.animation(forKey: key) as? CABasicAnimation, let current = layer.animation(forKey: key) as? CABasicAnimation else {
                    XCTFail("missing \(key)")
                    continue
                }
                XCTAssertEqual(legacy.duration, current.duration, key)
                XCTAssertEqual(legacy.timingFunction, current.timingFunction, key)
                XCTAssertEqual(legacy.isRemovedOnCompletion, current.isRemovedOnCompletion, key)
                XCTAssertEqual(legacy.fromValue as? NSValue, current.fromValue as? NSValue, key)
                XCTAssertEqual(legacy.toValue as? NSValue, current.toValue as? NSValue, key)
            }
        }
    }

    func testImmediateRemovalDetachesTheLayer() {
        let host = View(frame: NSMakeRect(0, 0, 100, 40))
        let layer = ChatRightView.makeIconLayer(rects[0])
        host.layer?.addSublayer(layer)
        ChatRightView.removeIcon(layer, animated: false)
        XCTAssertNil(layer.superlayer)
    }
}
