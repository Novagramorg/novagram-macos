import XCTest
import Cocoa
import TGUIKit
import ColorPalette
import Postbox
import TelegramCore
@testable import AvatarUI

final class AvatarStoryRingLayerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        System.updateScaleFactor(2)
    }

    private let availableSize = NSMakeSize(36, 36)

    private func peer() -> Peer {
        return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(1)), accessHash: nil, title: "Channel", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(.init(flags: [])), flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func component(unseen: Int32, total: Int32, rounded: Bool = false) -> AvatarStoryIndicatorComponent {
        let image = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let presentation = PresentationTheme(colors: whitePalette, search: SearchTheme(.clear, image, image, { "" }, .black, .gray), inputTheme: .init(quote: .init(foreground: .init(main: .blue), icon: NSImage(), collapse: NSImage(), expand: NSImage()), indicatorColor: .blue, backgroundColor: .white, selectingColor: .blue, textColor: .black, accentColor: .blue, grayTextColor: .gray, fontSize: 13))
        let story = EngineStorySubscriptions.Item(peer: EnginePeer(peer()), hasUnseen: unseen > 0, hasUnseenCloseFriends: false, hasLiveItems: false, hasPending: false, storyCount: Int(total), unseenCount: Int(unseen), lastTimestamp: 0)
        return AvatarStoryIndicatorComponent(story: story, presentation: presentation, active: false, isRoundedRect: rounded)
    }

    private func makeIndicator(_ component: AvatarStoryIndicatorComponent, displayProgress: Bool = false) -> AvatarStoryIndicatorComponent.IndicatorView {
        let view = AvatarStoryIndicatorComponent.IndicatorView(frame: NSMakeRect(0, 0, availableSize.width + 6, availableSize.height + 6))
        view.update(component: component, availableSize: availableSize, transition: .immediate, displayProgress: displayProgress)
        return view
    }

    private func legacy(from view: AvatarStoryIndicatorComponent.IndicatorView) -> LayerBackedView {
        let drawer = LayerBackedView(frame: view.indicatorView.frame)
        drawer.layer?.masksToBounds = false
        drawer.layer?.contentsScale = view.indicatorView.contentsScale
        drawer.layer?.contents = view.indicatorView.contents
        drawer.layer?.opacity = view.indicatorView.opacity
        view.indicatorView.removeFromSuperlayer()
        view.addSubview(drawer, positioned: .below, relativeTo: nil)
        return drawer
    }

    private func emulateSnapshotOverlay(_ view: AvatarStoryIndicatorComponent.IndicatorView) {
        let copy = SimpleLayer()
        copy.contents = view.indicatorView.contents
        copy.frame = view.indicatorView.bounds
        copy.contentsScale = view.indicatorView.contentsScale
        view.indicatorView.insertSublayer(copy, at: 0)
    }

    private var cases: [(String, AvatarStoryIndicatorComponent, Bool)] {
        return [
            ("segmented", component(unseen: 2, total: 5), false),
            ("seen", component(unseen: 0, total: 1), false),
            ("unseen", component(unseen: 1, total: 1), false),
            ("rounded", component(unseen: 1, total: 1, rounded: true), false),
            ("loading", component(unseen: 1, total: 1), true)
        ]
    }

    func testRingIsALayerAtTheBottomOfTheIndicator() {
        let view = makeIndicator(component(unseen: 2, total: 5))
        XCTAssertTrue(view.subviews.isEmpty)
        XCTAssertTrue(view.layer?.sublayers?.first === view.indicatorView)
        XCTAssertEqual(view.indicatorView.anchorPoint, .zero)
        XCTAssertEqual(view.indicatorView.frame, NSMakeRect(0, 0, availableSize.width + 6, availableSize.height + 6))
        XCTAssertNotNil(view.indicatorView.contents)
        XCTAssertTrue((view.indicatorView.action(forKey: "opacity") as AnyObject) === nullAction)
    }

    func testRingsRenderLikeTheDrawerView() {
        for (name, component, displayProgress) in cases {
            let current = makeIndicator(component, displayProgress: displayProgress)
            emulateSnapshotOverlay(current)
            let old = makeIndicator(component, displayProgress: displayProgress)
            _ = legacy(from: old)
            let new = ViewSnapshot.render(current)
            XCTAssertEqual(new.differingPixels(from: ViewSnapshot.render(old), tolerance: 0), 0, name)
            let bare = makeIndicator(component, displayProgress: displayProgress)
            bare.indicatorView.removeFromSuperlayer()
            let rendered = ViewSnapshot.render(bare)
            if displayProgress {
                XCTAssertEqual(new.differingPixels(from: rendered, tolerance: 0), 0, name)
            } else {
                XCTAssertGreaterThan(new.differingPixels(from: rendered, tolerance: 0), 300, name)
            }
        }
    }

    func testIndicatorLayerRendersLikeTheView() {
        for (name, component, displayProgress) in cases {
            let view = makeIndicator(component, displayProgress: displayProgress)
            let host = LayerBackedView(frame: view.frame)
            host.layer?.masksToBounds = false
            let layer = AvatarStoryIndicatorComponent.IndicatorLayer()
            layer.anchorPoint = .zero
            layer.frame = host.bounds
            layer.update(component: component, availableSize: availableSize, transition: .immediate, displayProgress: displayProgress)
            host.layer?.addSublayer(layer)
            XCTAssertEqual(ViewSnapshot.render(host).differingPixels(from: ViewSnapshot.render(view), tolerance: 0), 0, name)
            XCTAssertTrue(layer.sublayers?.first is SimpleLayer, name)
        }
    }

    func testRingAnimationsMatchTheViewHelpers() {
        for transition in [ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut), .animated(duration: 0.3, curve: .spring)] {
            let view = makeIndicator(component(unseen: 2, total: 5))
            let drawer = LayerBackedView(frame: view.indicatorView.frame)
            let bigger = NSMakeSize(44, 44)
            view.update(component: component(unseen: 2, total: 5), availableSize: bigger, transition: transition, displayProgress: true)
            transition.updateFrame(view: drawer, frame: NSMakeRect(0, 0, bigger.width + 6, bigger.height + 6))
            transition.updateAlpha(view: drawer, alpha: 0.0)
            XCTAssertNotNil(view.indicatorView.animation(forKey: "bounds"), "\(transition)")
            XCTAssertNotNil(view.indicatorView.animation(forKey: "opacity"), "\(transition)")
            XCTAssertEqual(view.indicatorView.frame, drawer.frame)
            XCTAssertEqual(view.indicatorView.opacity, drawer.layer?.opacity)
            for key in ["position", "bounds", "opacity"] {
                let new = view.indicatorView.animation(forKey: key) as? CABasicAnimation
                let old = drawer.layer?.animation(forKey: key) as? CABasicAnimation
                XCTAssertEqual(new == nil, old == nil, "\(key) \(transition)")
                if let new = new, let old = old {
                    XCTAssertEqual(new.duration, old.duration, key)
                    XCTAssertEqual(new.timingFunction, old.timingFunction, key)
                    XCTAssertEqual(new.fromValue as? NSValue, old.fromValue as? NSValue, key)
                    XCTAssertEqual(new.toValue as? NSValue, old.toValue as? NSValue, key)
                    XCTAssertEqual(new.fromValue as? NSNumber, old.fromValue as? NSNumber, key)
                    XCTAssertEqual(new.toValue as? NSNumber, old.toValue as? NSNumber, key)
                }
            }
        }
    }
}
