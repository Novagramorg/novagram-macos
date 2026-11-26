import XCTest
import AppKit
import TGUIKit
import TelegramCore
@testable import InlineMediaGrid

final class StoryBadgeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private let size = NSMakeSize(118, 20)

    private func emulateImageViewDoubleDraw(_ layer: CALayer) {
        guard layer.contents != nil else {
            return
        }
        let copy = CALayer()
        copy.frame = layer.bounds
        copy.contentsScale = 2
        copy.contentsGravity = layer.contentsGravity
        copy.contents = layer.contents
        layer.insertSublayer(copy, at: 0)
    }

    private func imageView(_ view: NSView) -> NSView {
        return view.subviews.first(where: { $0 is ImageView })!
    }

    func testViewsBadgeKeepsOnlyItsText() {
        let view = StoryViewsView(frame: size.bounds)
        view.update(42, animated: false)
        view.layout()
        XCTAssertEqual(viewClassNames(view.subviews), ["TextView"])
        XCTAssertTrue(view.iconLayer.superlayer === view.layer)
        XCTAssertTrue((view.iconLayer.action(forKey: "position") as AnyObject) === nullAction)
    }

    func testViewsBadgeRendersLikeTheOldBadge() {
        for count in [7, 1234, 1_500_000] {
            let current = StoryViewsView(frame: size.bounds)
            let legacy = LegacyStoryViewsView(frame: size.bounds)
            current.update(count, animated: false)
            legacy.update(count, animated: false)
            current.layout()
            legacy.layout()
            XCTAssertEqual(current.iconLayer.frame, imageView(legacy).frame, "\(count)")
            XCTAssertEqual(current.subviews[0].frame, legacy.subviews[1].frame, "\(count)")
            emulateImageViewDoubleDraw(current.iconLayer)
            let new = ViewSnapshot.render(current)
            XCTAssertEqual(new.differingPixels(from: ViewSnapshot.render(legacy), tolerance: 0), 0, "\(count)")
            let bare = StoryViewsView(frame: size.bounds)
            bare.update(count, animated: false)
            bare.iconLayer.contents = nil
            XCTAssertGreaterThan(new.differingPixels(from: ViewSnapshot.render(bare), tolerance: 0), 50, "\(count)")
        }
    }

    func testPrivacyBadgeHasNoSubviews() {
        let view = StoryPrivacyView(frame: size.bounds)
        view.update(EngineStoryPrivacy(base: .contacts, additionallyIncludePeers: []), isPinned: false, animated: false)
        XCTAssertTrue(view.subviews.isEmpty)
        XCTAssertTrue(view.iconLayer.superlayer === view.layer)
    }

    func testPrivacyBadgeRendersLikeTheOldBadgeAcrossReuse() {
        let steps: [(Stories.Item.Privacy.Base, Bool)] = [(.closeFriends, false), (.contacts, false), (.nobody, false), (.everyone, true), (.everyone, false), (.closeFriends, false)]
        let current = StoryPrivacyView(frame: size.bounds)
        let legacy = LegacyStoryPrivacyView(frame: size.bounds)
        for (base, pinned) in steps {
            let privacy = EngineStoryPrivacy(base: base, additionallyIncludePeers: [])
            current.update(privacy, isPinned: pinned, animated: false)
            legacy.update(privacy, isPinned: pinned, animated: false)
            current.layout()
            legacy.layout()
            XCTAssertEqual(current.iconLayer.frame, imageView(legacy).frame, "\(base) \(pinned)")
            let shown = current.iconLayer.contents != nil
            emulateImageViewDoubleDraw(current.iconLayer)
            let new = ViewSnapshot.render(current)
            current.iconLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            XCTAssertEqual(new.differingPixels(from: ViewSnapshot.render(legacy), tolerance: 0), 0, "\(base) \(pinned)")
            let bare = LegacyStoryPrivacyView(frame: size.bounds)
            bare.update(EngineStoryPrivacy(base: .everyone, additionallyIncludePeers: []), isPinned: false, animated: false)
            let difference = new.differingPixels(from: ViewSnapshot.render(bare), tolerance: 0)
            if shown {
                XCTAssertGreaterThan(difference, 50, "\(base) \(pinned)")
            } else {
                XCTAssertEqual(difference, 0, "\(base) \(pinned)")
            }
        }
    }
}
