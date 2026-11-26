import Cocoa
import QuartzCore
import XCTest
import TGUIKit
@testable import CommentsHarness

private final class CommentsTestWindow: Window {
    var testScale: CGFloat = 2
    var active = true
    override var backingScaleFactor: CGFloat { testScale }
    override var isKeyWindow: Bool { active }
}

struct CommentsFixture {
    var title: [(String, ChannelCommentsRenderData.Text.Animation, Int)]
    var peers: Int
    var unread: Bool
    var border: Bool
    var loading: Bool
    var bubble: Bool

    static func count(_ value: Int) -> [(String, ChannelCommentsRenderData.Text.Animation, Int)] {
        let pretty = NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
        var result: [(String, ChannelCommentsRenderData.Text.Animation, Int)] = []
        for (index, symbol) in pretty.enumerated() {
            result.append((String(symbol), .numeric, index + 1))
        }
        result.append((" comments", .crossFade, pretty.count + 1))
        return result
    }

    static let leave: [(String, ChannelCommentsRenderData.Text.Animation, Int)] = [("Leave a comment", .crossFade, 0)]
}

final class CommentsTests: XCTestCase {
    private var windows: [NSWindow] = []
    private let context = LabContext()
    private let peers: [LabPeer] = [LabPeer(id: 1, color: .systemRed), LabPeer(id: 2, color: .systemGreen), LabPeer(id: 3, color: .systemBlue)]
    private var diagnosticCount = 0

    private static var images: [NSImage] = []

    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        System.liquidGlass = false
        if Self.images.isEmpty {
            for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode", "Icon_MessageFile", "Icon_NavigationBack"] {
                let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                    NSColor.black.setFill()
                    rect.insetBy(dx: 4, dy: 4).fill()
                    return true
                }
                _ = image.setName(name)
                Self.images.append(image)
            }
        }
    }

    override func tearDown() {
        for window in windows { window.contentView = nil; window.close() }
        windows.removeAll()
        System.updateScaleFactor(2)
    }

    private func attach(_ views: [NSView]) -> CommentsTestWindow {
        let window = CommentsTestWindow(contentRect: CGRect(x: 40, y: 60, width: 420, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = View(frame: CGRect(x: 0, y: 0, width: 420, height: 200))
        for view in views { window.contentView?.addSubview(view) }
        windows.append(window)
        return window
    }

    private func attributed(_ string: String) -> NSAttributedString {
        return NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.systemBlue])
    }

    func legacyData(_ fixture: CommentsFixture) -> LegacyChannelCommentsRenderData {
        let texts = fixture.title.map { LegacyChannelCommentsRenderData.Text(text: attributed($0.0), animation: $0.1 == .numeric ? .numeric : .crossFade, index: $0.2) }
        let data = LegacyChannelCommentsRenderData(context: context, message: Message(), hasUnread: fixture.unread, title: texts, peers: Array(peers.prefix(fixture.peers)), drawBorder: fixture.border, isLoading: fixture.loading, bubbleMode: fixture.bubble)
        data.makeSize()
        return data
    }

    func currentData(_ fixture: CommentsFixture, handler: @escaping () -> Void = {}) -> ChannelCommentsRenderData {
        let texts = fixture.title.map { ChannelCommentsRenderData.Text(text: attributed($0.0), animation: $0.1, index: $0.2) }
        let data = ChannelCommentsRenderData(context: context, message: Message(), hasUnread: fixture.unread, title: texts, peers: Array(peers.prefix(fixture.peers)), drawBorder: fixture.border, isLoading: fixture.loading, bubbleMode: fixture.bubble, handler: handler)
        data.makeSize()
        return data
    }

    func render(_ view: NSView, scale: CGFloat) throws -> Data {
        (view.window as? CommentsTestWindow)?.testScale = scale
        System.updateScaleFactor(scale)
        view.viewDidChangeBackingProperties()
        view.layoutSubtreeIfNeeded()
        view.layout()
        view.window?.displayIfNeeded()
        let layer = try XCTUnwrap(view.layer)
        func display(_ layer: CALayer) {
            let assignedImage = layer.contents.map { CFGetTypeID($0 as CFTypeRef) == CGImage.typeID } ?? false
            if !assignedImage {
                layer.contentsScale = scale
                layer.setNeedsDisplay()
                layer.displayIfNeeded()
            }
            layer.sublayers?.forEach(display)
        }
        display(layer)
        let width = Int(ceil(view.bounds.width * scale)), height = Int(ceil(view.bounds.height * scale))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        return Data(bytes: context.data!, count: width * height * 4)
    }

    func assertPixelsMatch(_ legacy: NSView, _ current: NSView, scale: CGFloat, label: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = try render(legacy, scale: scale), actual = try render(current, scale: scale)
        if expected != actual, let directory = ProcessInfo.processInfo.environment["COMMENTS_DIAGNOSTICS"], diagnosticCount < 12 {
            diagnosticCount += 1
            let folder = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, view, data) in [("legacy", legacy, expected), ("current", current, actual)] {
                let width = Int(ceil(view.bounds.width * scale)), height = Int(ceil(view.bounds.height * scale))
                let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
                let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
                try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(String(format: "%02d-%@.png", diagnosticCount, name)))
            }
            try label.write(to: folder.appendingPathComponent(String(format: "%02d.txt", diagnosticCount)), atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(expected, actual, label, file: file, line: line)
    }

    private func nonBlank(_ data: Data) -> Int {
        var count = 0
        data.withUnsafeBytes { bytes in
            var index = 3
            while index < bytes.count {
                if bytes[index] != 0 { count += 1 }
                index += 4
            }
        }
        return count
    }

    func fixtures() -> [CommentsFixture] {
        var result: [CommentsFixture] = []
        for title in [CommentsFixture.leave, CommentsFixture.count(7), CommentsFixture.count(123), CommentsFixture.count(1234)] {
            for peers in [0, 1, 3] {
                for unread in [false, true] {
                    for bubble in [true, false] {
                        result.append(CommentsFixture(title: title, peers: peers, unread: unread, border: peers != 1, loading: false, bubble: bubble))
                    }
                }
            }
        }
        result.append(CommentsFixture(title: CommentsFixture.count(42), peers: 2, unread: true, border: true, loading: true, bubble: true))
        return result
    }

    func testBubbleControlPixelsMatchLegacyAcrossTitlesPeersUnreadModesAndScales() throws {
        var comparisons = 0
        for fixture in fixtures() {
            let legacyValue = legacyData(fixture), currentValue = currentData(fixture)
            let size = currentValue.size(fixture.bubble)
            XCTAssertEqual(size, legacyValue.size(fixture.bubble))
            let width = max(size.width, 220)
            let legacy = LegacyChannelCommentsBubbleControl(frame: NSMakeRect(10, 10, width, ChatRowItem.channelCommentsBubbleHeight))
            let current = ChannelCommentsBubbleControl(frame: NSMakeRect(10, 70, width, ChatRowItem.channelCommentsBubbleHeight))
            _ = attach([legacy, current])
            legacy.update(data: legacyValue, size: NSMakeSize(width, ChatRowItem.channelCommentsBubbleHeight), animated: false)
            current.update(data: currentValue, size: NSMakeSize(width, ChatRowItem.channelCommentsBubbleHeight), animated: false)
            for scale: CGFloat in [1, 2, 3] {
                let label = "title=\(fixture.title.map { $0.0 }.joined()) peers=\(fixture.peers) unread=\(fixture.unread) bubble=\(fixture.bubble) loading=\(fixture.loading) scale=\(scale)"
                if !fixture.loading {
                    XCTAssertGreaterThan(nonBlank(try render(current, scale: scale)), 50, label)
                }
                try assertPixelsMatch(legacy, current, scale: scale, label: label)
                comparisons += 1
            }
            XCTAssertLessThan(subviewCount(current), subviewCount(legacy), "Fewer native views")
        }
        XCTAssertEqual(comparisons, fixtures().count * 3)
    }

    func testSmallControlPixelsMatchLegacyAcrossWallpaperLoadingAndScales() throws {
        var comparisons = 0
        for wallpaper in [false, true] {
            theme.backgroundMode.hasWallpaper = wallpaper
            defer { theme.backgroundMode.hasWallpaper = false }
            for title in [[], CommentsFixture.count(5), CommentsFixture.count(48)] as [[(String, ChannelCommentsRenderData.Text.Animation, Int)]] {
                for loading in [false, true] {
                    let fixture = CommentsFixture(title: title, peers: 0, unread: false, border: false, loading: loading, bubble: false)
                    let legacyValue = legacyData(fixture), currentValue = currentData(fixture)
                    let size = currentValue.size(false, true)
                    XCTAssertEqual(size, legacyValue.size(false, true))
                    let legacy = LegacyChannelCommentsSmallControl(frame: CGRect(origin: NSMakePoint(10, 10), size: size))
                    let current = ChannelCommentsSmallControl(frame: CGRect(origin: NSMakePoint(80, 10), size: size))
                    for control in [legacy, current] as [Control] { control.set(background: .systemYellow, for: .Normal) }
                    _ = attach([legacy, current])
                    legacy.update(data: legacyValue, size: size, animated: false)
                    current.update(data: currentValue, size: size, animated: false)
                    for scale: CGFloat in [1, 2, 3] {
                        try assertPixelsMatch(legacy, current, scale: scale, label: "small wallpaper=\(wallpaper) title=\(title.map { $0.0 }.joined()) loading=\(loading) scale=\(scale)")
                        comparisons += 1
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 36)
    }

    func testPixelOracleRejectsMissingArrowDotAndText() throws {
        let fixture = CommentsFixture(title: CommentsFixture.count(123), peers: 0, unread: true, border: true, loading: false, bubble: true)
        let legacy = LegacyChannelCommentsBubbleControl(frame: NSMakeRect(10, 10, 240, 42))
        let current = ChannelCommentsBubbleControl(frame: NSMakeRect(10, 70, 240, 42))
        _ = attach([legacy, current])
        legacy.update(data: legacyData(fixture), size: NSMakeSize(240, 42), animated: false)
        current.update(data: currentData(fixture), size: NSMakeSize(240, 42), animated: false)
        let expected = try render(legacy, scale: 2)
        XCTAssertEqual(expected, try render(current, scale: 2))
        let sublayers = try XCTUnwrap(current.layer?.sublayers)
        let texts = sublayers.filter { $0 is ChatReactionTextLayer }
        let arrowSize = theme.icons.channel_comments_bubble_next.backingSize
        let arrow = try XCTUnwrap(sublayers.first { $0 is SimpleLayer && !($0 is ChatReactionTextLayer) && $0.contents != nil && $0.frame.size == arrowSize })
        let dot = try XCTUnwrap(sublayers.first { $0.backgroundColor != nil && $0.cornerRadius == 3 })
        XCTAssertEqual(texts.count, 4)
        for layer in texts + [arrow, dot] {
            layer.isHidden = true
            XCTAssertNotEqual(expected, try render(current, scale: 2), "Hidden \(type(of: layer)) must change pixels")
            layer.isHidden = false
        }
        XCTAssertEqual(expected, try render(current, scale: 2))
    }

    struct AnimationRecord: Equatable {
        let key: String
        let keyPath: String?
        let from: String
        let to: String
        let duration: Double
        let additive: Bool
        let removedOnCompletion: Bool
    }

    private func records(_ layer: CALayer) -> [AnimationRecord] {
        return (layer.animationKeys() ?? []).sorted().compactMap { key in
            guard let animation = layer.animation(forKey: key) else { return nil }
            if let spring = animation as? CASpringAnimation {
                return AnimationRecord(key: key, keyPath: spring.keyPath, from: String(describing: spring.fromValue), to: String(describing: spring.toValue), duration: spring.duration, additive: spring.isAdditive, removedOnCompletion: spring.isRemovedOnCompletion)
            }
            if let basic = animation as? CABasicAnimation {
                return AnimationRecord(key: key, keyPath: basic.keyPath, from: String(describing: basic.fromValue), to: String(describing: basic.toValue), duration: basic.duration, additive: basic.isAdditive, removedOnCompletion: basic.isRemovedOnCompletion)
            }
            if let keyframe = animation as? CAKeyframeAnimation {
                return AnimationRecord(key: key, keyPath: keyframe.keyPath, from: String(describing: keyframe.values?.first), to: String(describing: keyframe.values?.last), duration: keyframe.duration, additive: keyframe.isAdditive, removedOnCompletion: keyframe.isRemovedOnCompletion)
            }
            return AnimationRecord(key: key, keyPath: nil, from: "", to: "", duration: animation.duration, additive: false, removedOnCompletion: animation.isRemovedOnCompletion)
        }
    }

    private func legacyTextLayers(_ control: NSView) -> [CALayer] {
        return control.subviews.compactMap { $0 as? TextView }.compactMap { $0.layer }
    }

    private func currentTextLayers(_ control: NSView) -> [CALayer] {
        return (control.layer?.sublayers ?? []).filter { $0 is ChatReactionTextLayer }
    }

    private func sortedByPosition(_ layers: [CALayer]) -> [CALayer] {
        return layers.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    func testAnimatedCountChangesReproduceLegacyAnimations() throws {
        let transitions: [(CommentsFixture, CommentsFixture)] = [
            (CommentsFixture(title: CommentsFixture.count(123), peers: 1, unread: false, border: true, loading: false, bubble: true), CommentsFixture(title: CommentsFixture.count(124), peers: 2, unread: true, border: true, loading: false, bubble: true)),
            (CommentsFixture(title: CommentsFixture.count(124), peers: 2, unread: true, border: true, loading: false, bubble: true), CommentsFixture(title: CommentsFixture.count(119), peers: 0, unread: false, border: true, loading: false, bubble: true)),
            (CommentsFixture(title: CommentsFixture.leave, peers: 0, unread: false, border: true, loading: false, bubble: true), CommentsFixture(title: CommentsFixture.count(1), peers: 1, unread: true, border: true, loading: false, bubble: true)),
            (CommentsFixture(title: CommentsFixture.count(99), peers: 3, unread: false, border: true, loading: false, bubble: true), CommentsFixture(title: CommentsFixture.count(100), peers: 3, unread: false, border: true, loading: true, bubble: true))
        ]
        for (from, to) in transitions {
            let legacy = LegacyChannelCommentsBubbleControl(frame: NSMakeRect(10, 10, 260, 42))
            let current = ChannelCommentsBubbleControl(frame: NSMakeRect(10, 70, 260, 42))
            _ = attach([legacy, current])
            legacy.update(data: legacyData(from), size: NSMakeSize(260, 42), animated: false)
            current.update(data: currentData(from), size: NSMakeSize(260, 42), animated: false)
            legacy.layoutSubtreeIfNeeded(); current.layoutSubtreeIfNeeded()
            CATransaction.begin()
            legacy.update(data: legacyData(to), size: NSMakeSize(260, 42), animated: true)
            current.update(data: currentData(to), size: NSMakeSize(260, 42), animated: true)
            let legacyTexts = sortedByPosition(legacyTextLayers(legacy)), currentTexts = sortedByPosition(currentTextLayers(current))
            XCTAssertEqual(legacyTexts.count, currentTexts.count, "Text segment count incl. outgoing")
            for (old, new) in zip(legacyTexts, currentTexts) {
                XCTAssertEqual(old.frame, new.frame, "Segment frame")
                XCTAssertEqual(records(old), records(new), "Segment animations \(from.title.map { $0.0 }.joined()) -> \(to.title.map { $0.0 }.joined())")
                XCTAssertEqual(old.opacity, new.opacity)
            }
            let legacyArrow = try XCTUnwrap(legacy.subviews.compactMap { $0 as? ImageView }.first?.layer)
            let currentArrow = try XCTUnwrap((current.layer?.sublayers ?? []).first { $0 is SimpleLayer && !($0 is ChatReactionTextLayer) && $0.contents != nil && $0.frame.size == theme.icons.channel_comments_bubble_next.backingSize })
            XCTAssertEqual(records(legacyArrow), records(currentArrow), "Arrow animations")
            XCTAssertEqual(legacyArrow.isHidden, currentArrow.isHidden)
            let legacyDot = legacy.subviews.first { type(of: $0) == View.self }?.layer
            let currentDot = (current.layer?.sublayers ?? []).first { $0.backgroundColor != nil && $0.cornerRadius == 3 }
            XCTAssertEqual(legacyDot == nil, currentDot == nil, "Dot presence")
            if let legacyDot, let currentDot {
                XCTAssertEqual(legacyDot.frame, currentDot.frame)
                XCTAssertEqual(records(legacyDot), records(currentDot), "Dot animations")
            }
            CATransaction.commit()
        }
    }

    func testRemovedSegmentsAndDotLeaveTheHierarchyAfterAnimations() throws {
        let current = ChannelCommentsBubbleControl(frame: NSMakeRect(10, 70, 260, 42))
        _ = attach([current])
        current.update(data: currentData(CommentsFixture(title: CommentsFixture.count(123), peers: 0, unread: true, border: true, loading: false, bubble: true)), size: NSMakeSize(260, 42), animated: false)
        XCTAssertEqual(currentTextLayers(current).count, 4)
        current.update(data: currentData(CommentsFixture(title: CommentsFixture.count(9), peers: 0, unread: false, border: true, loading: false, bubble: true)), size: NSMakeSize(260, 42), animated: true)
        CATransaction.flush()
        let done = expectation(description: "removal animations")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { done.fulfill() }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(currentTextLayers(current).count, 2)
        XCTAssertNil((current.layer?.sublayers ?? []).first { $0.backgroundColor != nil && $0.cornerRadius == 3 })
        current.update(data: currentData(CommentsFixture(title: CommentsFixture.count(9), peers: 0, unread: false, border: true, loading: false, bubble: true)), size: NSMakeSize(260, 42), animated: false)
        XCTAssertEqual(currentTextLayers(current).count, 2)
    }

    func testClicksAndAccessibilityReachTheButton() throws {
        var presses = 0
        let current = ChannelCommentsBubbleControl(frame: NSMakeRect(10, 70, 260, 42))
        let window = attach([current])
        current.update(data: currentData(CommentsFixture(title: CommentsFixture.count(123), peers: 1, unread: true, border: true, loading: false, bubble: true), handler: { presses += 1 }), size: NSMakeSize(260, 42), animated: false)
        current.layoutSubtreeIfNeeded()
        for layer in currentTextLayers(current) {
            let point = current.convert(NSPoint(x: layer.frame.midX, y: layer.frame.midY), to: window.contentView!.superview)
            XCTAssertTrue(window.contentView?.hitTest(point) === current, "Text area hits the button")
        }
        XCTAssertTrue(current.subviews.isEmpty, "No native subviews at rest")
        let previous = TGUIKitAccessibility.isEnabled
        TGUIKitAccessibility.isEnabled = true
        defer { TGUIKitAccessibility.isEnabled = previous }
        XCTAssertTrue(current.isAccessibilityElement())
        XCTAssertEqual(current.accessibilityRole(), .button)
        XCTAssertEqual(current.accessibilityLabel(), "123 comments")
        XCTAssertTrue(current.accessibilityPerformPress())
        XCTAssertEqual(presses, 1)
    }

    func testBackingScaleChangesRedrawText() throws {
        let current = ChannelCommentsBubbleControl(frame: NSMakeRect(10, 70, 260, 42))
        let window = attach([current])
        current.update(data: currentData(CommentsFixture(title: CommentsFixture.count(5), peers: 0, unread: false, border: false, loading: false, bubble: true)), size: NSMakeSize(260, 42), animated: false)
        for scale: CGFloat in [1, 3, 2] {
            window.testScale = scale
            current.viewDidChangeBackingProperties()
            for layer in currentTextLayers(current) {
                XCTAssertEqual(layer.sublayers?.first?.contentsScale, scale)
            }
        }
    }

    func subviewCount(_ view: NSView) -> Int {
        return view.subviews.reduce(0) { $0 + 1 + subviewCount($1) }
    }
}
