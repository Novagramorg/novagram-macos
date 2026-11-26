import AppKit
import QuartzCore
import Metal
import XCTest
import TGUIKit
@testable import ActivityPlaybackCore

private final class FocusWindow: NSWindow {
    var focused = true
    override var isKeyWindow: Bool { focused }
    override var canBecomeKey: Bool { true }
}
private final class Document: NSView { override var isFlipped: Bool { true } }

private final class Scene {
    let window = FocusWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 120), styleMask: [.titled], backing: .buffered, defer: true)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
    let document = Document(frame: NSRect(x: 0, y: 0, width: 240, height: 1200))
    init() {
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.documentView = document
        scroll.contentView.scroll(to: .zero)
    }
    func attach(_ view: NSView, y: CGFloat = 10) {
        view.frame = CGRect(x: 10, y: y, width: 120, height: 20)
        document.addSubview(view)
    }
    func scroll(to y: CGFloat) {
        scroll.contentView.scroll(to: CGPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    func focus(_ value: Bool) {
        window.focused = value
        NotificationCenter.default.post(name: value ? NSWindow.didBecomeKeyNotification : NSWindow.didResignKeyNotification, object: window)
    }
}

final class ActivityTests: XCTestCase {
    private let theme = ActivitiesTheme(textColor: .blue, backgroundColor: .white)
    private static var images: [NSImage] = []
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        if Self.images.isEmpty {
            for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
                let image = NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in NSColor.black.setFill(); rect.fill(); return true }
                image.setName(name); Self.images.append(image)
            }
        }
    }

    func testStopAndSameConfigurationRestartPreserveAnimationLayers() {
        let scene = Scene(), view = CurrentChatActivitiesView()
        scene.attach(view)
        view.startAnimation(.text, theme: theme)
        XCTAssertTrue(view.isIndicatorPlaying)
        let shapes = view.indicatorLayer.sublayers!
        view.stopAnimation()
        XCTAssertFalse(view.isIndicatorPlaying)
        let pausedTime = view.indicatorLayer.timeOffset
        for _ in 0..<100 { view.stopAnimation() }
        XCTAssertEqual(view.indicatorLayer.timeOffset, pausedTime)
        view.startAnimation(.text, theme: theme)
        XCTAssertTrue(view.isIndicatorPlaying)
        XCTAssertEqual(view.indicatorLayer.convertTime(CACurrentMediaTime(), from: nil), pausedTime, accuracy: 0.05)
        XCTAssertTrue(zip(shapes, view.indicatorLayer.sublayers!).allSatisfy { $0 === $1 })
        view.layout(with: (.none, nil), width: 120, theme: theme)
        XCTAssertFalse(view.isIndicatorPlaying)
        view.startAnimation(.text, theme: theme)
        XCTAssertTrue(view.isIndicatorPlaying)
        view.startAnimation(.none, theme: theme)
        XCTAssertFalse(view.isIndicatorPlaying)
    }

    func testOriginalKeepsStoppedAndOffscreenIndicatorsPlaying() {
        let scene = Scene(), view = ReferenceChatActivitiesView()
        scene.attach(view)
        view.startAnimation(.text, theme: theme)
        view.stopAnimation()
        XCTAssertTrue(view.isIndicatorPlaying)
        scene.scroll(to: 300)
        XCTAssertTrue(view.visibleRect.isEmpty)
        XCTAssertTrue(view.isIndicatorPlaying)
    }

    func testScrollingFreezesAndResumesVisibleActivityWithoutRebuilding() {
        let scene = Scene(), view = CurrentChatActivitiesView()
        scene.attach(view)
        view.startAnimation(.recording, theme: theme)
        let shapes = view.indicatorLayer.sublayers!
        XCTAssertTrue(view.isIndicatorPlaying)
        scene.scroll(to: 300)
        XCTAssertTrue(view.visibleRect.isEmpty)
        XCTAssertFalse(view.isIndicatorPlaying)
        let paused = view.indicatorLayer.timeOffset
        scene.scroll(to: 500)
        XCTAssertEqual(view.indicatorLayer.timeOffset, paused)
        scene.scroll(to: 0)
        XCTAssertTrue(view.isIndicatorPlaying)
        XCTAssertTrue(zip(shapes, view.indicatorLayer.sublayers!).allSatisfy { $0 === $1 })
        view.stopAnimation()
        scene.scroll(to: 300); scene.scroll(to: 0)
        XCTAssertFalse(view.isIndicatorPlaying)
    }

    func testOwnAndAncestorVisibilityAndZeroSizeGatePlayback() {
        let scene = Scene(), parent = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 80)), view = CurrentChatActivitiesView()
        scene.document.addSubview(parent)
        view.frame = CGRect(x: 10, y: 10, width: 120, height: 20)
        parent.addSubview(view)
        view.startAnimation(.choosingSticker, theme: theme)
        XCTAssertTrue(view.isIndicatorPlaying)
        view.isHidden = true
        XCTAssertFalse(view.isIndicatorPlaying)
        view.isHidden = false
        XCTAssertTrue(view.isIndicatorPlaying)
        parent.isHidden = true
        XCTAssertFalse(view.isIndicatorPlaying)
        parent.isHidden = false
        XCTAssertTrue(view.isIndicatorPlaying)
        view.setFrameSize(.zero)
        XCTAssertFalse(view.isIndicatorPlaying)
        view.setFrameSize(CGSize(width: 120, height: 20))
        XCTAssertTrue(view.isIndicatorPlaying)
    }

    func testFocusDetachReattachAndReparentTrackCurrentScrollView() {
        let first = Scene(), second = Scene(), view = CurrentChatActivitiesView()
        first.attach(view)
        view.startAnimation(.uploading, theme: theme)
        first.focus(false)
        XCTAssertFalse(view.isIndicatorPlaying)
        first.focus(true)
        XCTAssertTrue(view.isIndicatorPlaying)
        view.removeFromSuperview()
        XCTAssertFalse(view.isIndicatorPlaying)
        second.attach(view)
        XCTAssertTrue(view.isIndicatorPlaying)
        first.focus(false); first.scroll(to: 300)
        XCTAssertTrue(view.isIndicatorPlaying)
        second.scroll(to: 300)
        XCTAssertFalse(view.isIndicatorPlaying)
        second.scroll(to: 0)
        XCTAssertTrue(view.isIndicatorPlaying)
        view.stopAnimation()
        view.removeFromSuperview(); first.attach(view)
        first.focus(true)
        XCTAssertFalse(view.isIndicatorPlaying)
    }

    func testDetachedStartAndSameWindowReparentFollowVisibility() {
        let view = CurrentChatActivitiesView()
        view.startAnimation(.text, theme: theme)
        XCTAssertFalse(view.isIndicatorPlaying)
        let scene = Scene()
        scene.attach(view)
        XCTAssertTrue(view.isIndicatorPlaying)
        let otherScroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let otherDocument = Document(frame: CGRect(x: 0, y: 0, width: 200, height: 1000))
        otherScroll.contentView.postsBoundsChangedNotifications = true
        scene.document.addSubview(otherScroll)
        otherScroll.documentView = otherDocument
        otherDocument.addSubview(view)
        XCTAssertTrue(view.isIndicatorPlaying)
        otherScroll.contentView.scroll(to: CGPoint(x: 0, y: 300))
        XCTAssertFalse(view.isIndicatorPlaying)
        otherScroll.contentView.scroll(to: .zero)
        XCTAssertTrue(view.isIndicatorPlaying)
    }

    func testChangedTypeAndThemeWhilePausedResumeCorrectConfiguration() {
        let scene = Scene(), view = CurrentChatActivitiesView()
        scene.attach(view)
        view.startAnimation(.text, theme: theme)
        scene.focus(false)
        let previous = view.indicatorLayer.sublayers!.first!
        view.startAnimation(.choosingSticker, theme: ActivitiesTheme(textColor: .red, backgroundColor: .black))
        XCTAssertFalse(view.isIndicatorPlaying)
        XCTAssertFalse(view.indicatorLayer.sublayers!.first! === previous)
        XCTAssertEqual(view.indicatorLayer.frameCount, 120)
        scene.focus(true)
        XCTAssertTrue(view.isIndicatorPlaying)
    }

    func testObserverAndLayerAreReleasedAfterRemoval() {
        let scene = Scene()
        weak var weakView: CurrentChatActivitiesView?
        weak var weakLayer: CALayer?
        autoreleasepool {
            let view = CurrentChatActivitiesView()
            weakView = view
            weakLayer = view.indicatorLayer
            scene.attach(view)
            view.startAnimation(.text, theme: theme)
            view.removeFromSuperview()
            CATransaction.flush()
        }
        XCTAssertNil(weakView)
        XCTAssertNil(weakLayer)
        scene.scroll(to: 100); scene.focus(false)
    }

    func testIndicatorModelFramesMatchReferenceAtEverySample() {
        func pixels(_ layer: CALayer, scale: CGFloat) -> Data {
            let width = Int(layer.bounds.width * scale), height = Int(layer.bounds.height * scale)
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            layer.render(in: context)
            return Data(bytes: context.data!, count: width * height * 4)
        }
        let pairs: [(ReferenceChatActivityAnimation, CurrentChatActivityAnimation)] = [(.text, .text), (.recording, .recording), (.uploading, .uploading), (.choosingSticker, .choosingSticker)]
        for pair in pairs {
            let old = ReferenceChatActivitiesView(), new = CurrentChatActivitiesView()
            old.startAnimation(pair.0, theme: theme); new.startAnimation(pair.1, theme: theme)
            XCTAssertEqual(old.indicatorLayer.frameCount, new.indicatorLayer.frameCount)
            for scale in [CGFloat(1), 2, 3] {
                for sample in 0..<old.indicatorLayer.frameCount {
                    old.indicatorLayer.show(sample: sample); new.indicatorLayer.show(sample: sample)
                    let expected = pixels(old.indicatorLayer, scale: scale), actual = pixels(new.indicatorLayer, scale: scale)
                    XCTAssertEqual(actual, expected)
                    XCTAssertTrue(actual.contains { $0 != 0 })
                }
            }
        }
    }

    func testOnlyVisibleIndicatorsRunAcrossLargeListScrollPositions() {
        let scene = Scene()
        scene.document.setFrameSize(CGSize(width: 240, height: 3000))
        let views = (0..<100).map { index -> CurrentChatActivitiesView in
            let view = CurrentChatActivitiesView()
            scene.attach(view, y: CGFloat(index * 26))
            view.startAnimation(.text, theme: theme)
            return view
        }
        for y in [CGFloat(0), 260, 1300, 2500, 0] {
            scene.scroll(to: y)
            for view in views { XCTAssertEqual(view.isIndicatorPlaying, !view.visibleRect.isEmpty) }
            XCTAssertLessThanOrEqual(views.filter { $0.isIndicatorPlaying }.count, 6)
        }
    }

    func testProductionScrollViewDeliversVisibilityChangesWithoutCustomSetup() {
        let window = FocusWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 120), styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let scroll = ScrollView(frame: CGRect(x: 0, y: 0, width: 240, height: 120))
        let document = Document(frame: CGRect(x: 0, y: 0, width: 240, height: 1200))
        window.contentView = scroll
        scroll.documentView = document
        scroll.contentView.scroll(to: .zero)
        let view = CurrentChatActivitiesView()
        view.frame = CGRect(x: 10, y: 10, width: 120, height: 20)
        document.addSubview(view)
        view.startAnimation(.text, theme: theme)
        XCTAssertTrue(view.isIndicatorPlaying)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 300))
        XCTAssertTrue(view.visibleRect.isEmpty)
        XCTAssertFalse(view.isIndicatorPlaying)
        scroll.contentView.scroll(to: .zero)
        XCTAssertTrue(view.isIndicatorPlaying)
        view.removeFromSuperview()
    }

    func testPlaybackBenchmark() throws {
        guard ProcessInfo.processInfo.environment["ACTIVITY_PLAYBACK_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw XCTSkip("Metal unavailable") }
        var renderResults: [[String: Any]] = []
        for pass in 0..<3 {
            for baseline in pass % 2 == 0 ? [true, false] : [false, true] {
                let scene = Scene(), root = CALayer()
                root.frame = CGRect(x: 0, y: 0, width: 160, height: 280)
                root.backgroundColor = NSColor.white.cgColor
                var views: [NSView] = []
                for index in 0..<8 {
                    let indicator: CALayer
                    if baseline {
                        let view = ReferenceChatActivitiesView()
                        scene.attach(view)
                        view.startAnimation(.text, theme: theme)
                        view.stopAnimation()
                        XCTAssertTrue(view.isIndicatorPlaying)
                        views.append(view); indicator = view.indicatorLayer
                    } else {
                        let view = CurrentChatActivitiesView()
                        scene.attach(view)
                        view.startAnimation(.text, theme: theme)
                        view.stopAnimation()
                        XCTAssertFalse(view.isIndicatorPlaying)
                        views.append(view); indicator = view.indicatorLayer
                    }
                    indicator.removeFromSuperlayer()
                    root.addSublayer(indicator)
                    indicator.frame.origin = CGPoint(x: 20, y: 20 + index * 30)
                }
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 160, height: 280, mipmapped: false)
                descriptor.usage = [.renderTarget, .shaderRead]; descriptor.storageMode = .private
                let texture = device.makeTexture(descriptor: descriptor)!
                let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue as String: queue])
                renderer.layer = root; renderer.bounds = root.bounds
                CATransaction.flush()
                var time = CACurrentMediaTime()
                for _ in 0..<60 {
                    renderer.beginFrame(atTime: time, timeStamp: nil)
                    renderer.addUpdate(root.bounds); renderer.render(); renderer.endFrame()
                    time += 1.0 / 120
                }
                let frames = 360
                var dirty = 0, total: Double = 0
                for _ in 0..<frames {
                    let start = DispatchTime.now().uptimeNanoseconds
                    renderer.beginFrame(atTime: time, timeStamp: nil)
                    let bounds = renderer.updateBounds()
                    if !bounds.isEmpty && !bounds.isNull {
                        dirty += 1; renderer.addUpdate(bounds); renderer.render()
                    }
                    renderer.endFrame()
                    let fence = queue.makeCommandBuffer()!
                    fence.commit(); fence.waitUntilCompleted()
                    total += Double(DispatchTime.now().uptimeNanoseconds - start) / 1000
                    time += 1.0 / 120
                }
                renderResults.append(["pass": pass, "baseline": baseline, "frames": frames, "dirty_frames": dirty, "mean_us_per_frame": total / Double(frames)])
                XCTAssertEqual(dirty, baseline ? frames : 0)
                withExtendedLifetime((views, scene)) {}
            }
        }
        var scrollResults: [[String: Any]] = []
        for stopped in [false, true] {
            let a = Scene(), b = Scene()
            a.document.setFrameSize(CGSize(width: 240, height: 3000))
            b.document.setFrameSize(CGSize(width: 240, height: 3000))
            var old: [ReferenceChatActivitiesView] = [], new: [CurrentChatActivitiesView] = []
            for index in 0..<100 {
                let x = ReferenceChatActivitiesView(), y = CurrentChatActivitiesView()
                a.attach(x, y: CGFloat(index * 26)); b.attach(y, y: CGFloat(index * 26))
                x.startAnimation(.text, theme: theme); y.startAnimation(.text, theme: theme)
                if stopped { x.stopAnimation(); y.stopAnimation() }
                old.append(x); new.append(y)
            }
            var before: [Double] = [], after: [Double] = []
            let iterations = 200
            func measure(_ scene: Scene) -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                for index in 0..<iterations { scene.scroll(to: CGFloat((index % 2) * 250)) }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations) / 1000
            }
            _ = measure(a); _ = measure(b)
            for batch in 0..<9 {
                if batch % 2 == 0 { before.append(measure(a)); after.append(measure(b)) }
                else { after.append(measure(b)); before.append(measure(a)) }
            }
            scrollResults.append(["stopped": stopped, "rows": 100, "iterations_per_batch": iterations, "baseline_us": before.sorted()[4], "candidate_us": after.sorted()[4], "baseline_trials_us": before, "candidate_trials_us": after, "baseline_running": old.filter { $0.isIndicatorPlaying }.count, "candidate_running": new.filter { $0.isIndicatorPlaying }.count, "visible": new.filter { !$0.visibleRect.isEmpty }.count])
        }
        let data = try JSONSerialization.data(withJSONObject: ["rendering": renderResults, "scrolling": scrollResults], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/activity-playback-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
