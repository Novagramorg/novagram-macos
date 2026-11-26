import Cocoa
import QuartzCore
import XCTest
import TGUIKit
@testable import ReactionHarness

private final class ReactionTestWindow: Window {
    var testScale: CGFloat = 2
    override var backingScaleFactor: CGFloat { testScale }
}

final class PassiveReactionTests: XCTestCase {
    private static var images: [NSImage] = []
    private var windows: [NSWindow] = []
    private var accessibilityWasEnabled = false
    private var diagnosticCount = 0

    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        System.liquidGlass = false
        accessibilityWasEnabled = TGUIKitAccessibility.isEnabled
        TGUIKitAccessibility.isEnabled = true
        if Self.images.isEmpty {
            for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
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
        TGUIKitAccessibility.isEnabled = accessibilityWasEnabled
        System.updateScaleFactor(2)
    }

    func attach(_ views: [NSView]) -> Window {
        let window = ReactionTestWindow(contentRect: CGRect(x: 50, y: 60, width: 400, height: 180), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = View(frame: CGRect(x: 0, y: 0, width: 400, height: 180))
        for view in views { window.contentView?.addSubview(view) }
        windows.append(window)
        return window
    }

    func pair(tag: Bool, width: CGFloat = 180) -> (ReactionFixture, ReactionFixture) {
        let frame = CGRect(x: 17, y: 21, width: width, height: 32)
        return tag ? (OriginalTag(frame: frame), CurrentTag(frame: frame)) : (OriginalFull(frame: frame), CurrentFull(frame: frame))
    }

    func reaction(_ string: String?, selected: Bool = false, color: NSColor = .black, custom: Bool = false) -> LabReaction {
        let text = string.map { text -> TextViewLayout in
            let layout = TextViewLayout(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color]))
            layout.measure(width: 260)
            return layout
        }
        var result = LabReaction(text: text, value: .init(isSelected: selected, value: custom ? .custom : .builtin))
        result.presentation.tagBackground = Self.tagBackground
        return result
    }

    private static let tagBackground: NSImage = {
        let size = CGSize(width: 40, height: 22), scale: CGFloat = 2
        let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let rect = CGRect(origin: .zero, size: size)
        NSColor.red.withAlphaComponent(0.4).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        NSColor.blue.setFill()
        CGRect(x: 31, y: 8, width: 3, height: 3).fill()
        NSGraphicsContext.restoreGraphicsState()
        return NSImage(cgImage: context.makeImage()!, size: size)
    }()

    func render(_ view: ReactionFixture, scale: CGFloat) throws -> Data {
        (view.window as? ReactionTestWindow)?.testScale = scale
        System.updateScaleFactor(scale)
        view.layoutSubtreeIfNeeded()
        view.layout()
        view.window?.displayIfNeeded()
        let layer = try XCTUnwrap(view.layer)
        func display(_ layer: CALayer) {
            layer.contentsScale = scale
            layer.setNeedsDisplay()
            layer.displayIfNeeded()
            layer.sublayers?.forEach(display)
        }
        display(layer)
        let width = Int(ceil(view.bounds.width * scale)), height = Int(ceil(view.bounds.height * scale))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        return Data(bytes: context.data!, count: width * height * 4)
    }

    static func resampledDifference(_ expected: Data, _ actual: Data) -> (maximum: Int, large: Int, pixels: Int) {
        precondition(expected.count == actual.count)
        var maximum = 0, large = 0
        expected.withUnsafeBytes { a in
            actual.withUnsafeBytes { b in
                var index = 0
                while index < a.count {
                    var delta = 0
                    for channel in 0 ..< 4 { delta = max(delta, abs(Int(a[index + channel]) - Int(b[index + channel]))) }
                    maximum = max(maximum, delta)
                    if delta > 3 { large += 1 }
                    index += 4
                }
            }
        }
        return (maximum, large, expected.count / 4)
    }

    static func acceptsResampledTagBackground(_ expected: Data, _ actual: Data) -> Bool {
        let difference = resampledDifference(expected, actual)
        return difference.maximum <= 32 && difference.large <= max(32, difference.pixels / 200)
    }

    func assertPixelsMatch(_ original: ReactionFixture, _ current: ReactionFixture, scale: CGFloat, label: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = try render(original, scale: scale), actual = try render(current, scale: scale)
        let resampledTag = original is OriginalTag && original.reaction?.value.isSelected == true
        let matches = resampledTag ? Self.acceptsResampledTagBackground(expected, actual) : expected == actual
        if !matches, let directory = ProcessInfo.processInfo.environment["REACTION_PASSIVE_DIAGNOSTICS"], diagnosticCount < 12 {
            diagnosticCount += 1
            let folder = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let prefix = String(format: "%02d", diagnosticCount)
            var metadata = ["case": label, "scale": String(describing: scale)]
            func describe(_ layer: CALayer, depth: Int = 0) -> String {
                let row = String(repeating: "  ", count: depth) + "\(type(of: layer)) frame=\(layer.frame) bounds=\(layer.bounds) anchor=\(layer.anchorPoint) flip=\(layer.isGeometryFlipped) z=\(layer.zPosition) opacity=\(layer.opacity) scale=\(layer.contentsScale) bg=\(String(describing: layer.backgroundColor)) delegate=\(String(describing: layer.delegate))\n"
                return row + (layer.sublayers ?? []).map { describe($0, depth: depth + 1) }.joined()
            }
            for (name, view, data) in [("native", original, expected), ("layers", current, actual)] {
                let width = Int(ceil(view.bounds.width * scale)), height = Int(ceil(view.bounds.height * scale))
                let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
                let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
                let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                try png.write(to: folder.appendingPathComponent("\(prefix)-\(name).png"))
                metadata[name] = view.layer.map { describe($0) } ?? "Missing layer"
            }
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("\(prefix).json"))
        }
        if resampledTag {
            let difference = Self.resampledDifference(expected, actual)
            XCTAssertTrue(matches, "\(label) max=\(difference.maximum) large=\(difference.large) of \(difference.pixels)", file: file, line: line)
        } else {
            XCTAssertEqual(expected, actual, label, file: file, line: line)
        }
    }

    func waitForRemovals() {
        CATransaction.flush()
        let done = expectation(description: "Passive removal animations complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { done.fulfill() }
        wait(for: [done], timeout: 3)
    }

    func testNativeAndLayerPixelsMatchAcrossTextsColorsScalesAndSelection() throws {
        var comparisons = 0
        for tag in [false, true] {
            let (original, current) = pair(tag: tag)
            _ = attach([original, current])
            for string in ["1", "12.5K", "Saved tag", "مرحبا", "🦆 Ducks", "Wide overlapping label 123456789"] {
                for selected in [false, true] {
                    for color in [NSColor.black, NSColor.systemBlue] {
                        for width: CGFloat in [85, 180] {
                            for view in [original, current] {
                                view.setFrameSize(CGSize(width: width, height: 32))
                                view.bind(reaction(string, selected: selected, color: color, custom: selected), animated: false)
                            }
                            XCTAssertEqual(original.textFrame, current.textFrame)
                            XCTAssertEqual(original.countLayer?.masksToBounds, current.countLayer?.masksToBounds)
                            for scale: CGFloat in [1, 2, 3] {
                                try assertPixelsMatch(original, current, scale: scale, label: "tag=\(tag) text=\(string) selected=\(selected) width=\(width) scale=\(scale) color=\(color)")
                                comparisons += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 288)
    }

    func testPixelOracleRejectsMissingTextAndWrongTint() throws {
        let (original, current) = pair(tag: false)
        _ = attach([original, current])
        original.bind(reaction("888"), animated: false)
        current.bind(reaction(nil), animated: false)
        XCTAssertNotEqual(try render(original, scale: 2), try render(current, scale: 2))
        current.bind(reaction("888", color: .red), animated: false)
        XCTAssertNotEqual(try render(original, scale: 2), try render(current, scale: 2))
        current.bind(reaction("888"), animated: false)
        try assertPixelsMatch(original, current, scale: 2, label: "Negative control restored")
    }

    func testResampledTagOracleRejectsFlippedMissingAndRecoloredBackgrounds() throws {
        let (original, current) = pair(tag: true)
        _ = attach([original, current])
        for view in [original, current] { view.bind(reaction("12", selected: true), animated: false) }
        for scale: CGFloat in [1, 2, 3] {
            let expected = try render(original, scale: scale)
            XCTAssertTrue(Self.acceptsResampledTagBackground(expected, try render(current, scale: scale)), "Baseline scale=\(scale)")
            let background = try XCTUnwrap(current.selectionLayer)
            background.isGeometryFlipped.toggle()
            XCTAssertFalse(Self.acceptsResampledTagBackground(expected, try render(current, scale: scale)), "Flipped scale=\(scale)")
            background.isGeometryFlipped.toggle()
            background.isHidden = true
            XCTAssertFalse(Self.acceptsResampledTagBackground(expected, try render(current, scale: scale)), "Missing scale=\(scale)")
            background.isHidden = false
            background.opacity = 0.6
            XCTAssertFalse(Self.acceptsResampledTagBackground(expected, try render(current, scale: scale)), "Faded scale=\(scale)")
            background.opacity = 1
            XCTAssertTrue(Self.acceptsResampledTagBackground(expected, try render(current, scale: scale)), "Restored scale=\(scale)")
        }
    }

    func testSelectedBackgroundPixelsWithoutText() throws {
        for tag in [false, true] {
            let (original, current) = pair(tag: tag)
            _ = attach([original, current])
            for custom in [false, true] {
                for view in [original, current] { view.bind(reaction(nil, selected: true, custom: custom), animated: false) }
                for scale: CGFloat in [1, 2, 3] {
                    try assertPixelsMatch(original, current, scale: scale, label: "No text tag=\(tag) custom=\(custom) scale=\(scale)")
                }
            }
        }
    }

    func testCountsReuseLayersAndRemovedCompletionsCannotRemoveReplacement() throws {
        for tag in [false, true] {
            let (original, current) = pair(tag: tag)
            _ = attach([original, current])
            for view in [original, current] { view.bind(reaction("1", selected: true), animated: false) }
            let previous = try XCTUnwrap(current.textObject)
            for view in [original, current] { view.bind(reaction("999", selected: true, color: .blue), animated: false) }
            XCTAssertTrue(current.textObject === previous)
            try assertPixelsMatch(original, current, scale: 2, label: "Count reuse tag=\(tag)")
            let retiredLayer = try XCTUnwrap(current.countLayer)
            for view in [original, current] { view.bind(reaction(nil), animated: true) }
            XCTAssertNil(current.textObject)
            XCTAssertNil(current.countAccessibility)
            XCTAssertNotNil(retiredLayer.superlayer)
            for view in [original, current] { view.bind(reaction("New", selected: true), animated: true) }
            let replacement = try XCTUnwrap(current.textObject)
            XCTAssertFalse(replacement === previous)
            waitForRemovals()
            XCTAssertTrue(current.textObject === replacement)
            XCTAssertNil(retiredLayer.superlayer)
            try assertPixelsMatch(original, current, scale: 2, label: "Count replacement tag=\(tag)")
        }
    }

    func testSelectedBackgroundGeometryAnimationsAndEffectStackMatch() throws {
        let (original, current) = pair(tag: false)
        _ = attach([original, current])
        for view in [original, current] { view.bind(reaction("12", selected: true), animated: true) }
        let a = try XCTUnwrap(original.selectionLayer), b = try XCTUnwrap(current.selectionLayer)
        XCTAssertEqual(a.frame, b.frame)
        XCTAssertEqual(a.anchorPoint, b.anchorPoint)
        XCTAssertEqual(a.isGeometryFlipped, b.isGeometryFlipped)
        XCTAssertEqual(a.cornerRadius, b.cornerRadius)
        XCTAssertEqual(a.cornerCurve, b.cornerCurve)
        XCTAssertEqual(Set(a.animationKeys() ?? []), Set(b.animationKeys() ?? []))
        for key in a.animationKeys() ?? [] {
            let expected = try XCTUnwrap(a.animation(forKey: key) as? CABasicAnimation)
            let actual = try XCTUnwrap(b.animation(forKey: key) as? CABasicAnimation)
            XCTAssertEqual(expected.keyPath, actual.keyPath)
            XCTAssertEqual(expected.duration, actual.duration)
            XCTAssertEqual(expected.fromValue as? NSObject, actual.fromValue as? NSObject)
            XCTAssertEqual(expected.toValue as? NSObject, actual.toValue as? NSObject)
        }
        for view in [original, current] {
            view.selectionLayer?.removeAllAnimations()
            let effect = View(frame: CGRect(x: 24, y: 4, width: 70, height: 25))
            effect.backgroundColor = .purple
            view.addSubview(effect)
        }
        try assertPixelsMatch(original, current, scale: 2, label: "Selected effect stack")
        for view in [original, current] { view.bind(reaction("12", selected: false), animated: true) }
        XCTAssertNil(current.selectionLayer)
        waitForRemovals()
        XCTAssertNil(b.superlayer)
    }

    func testLazyAvatarHostPreservesPositionAndExistingHostOnReuse() throws {
        let (original, current) = pair(tag: false)
        XCTAssertNotNil(original.avatarHost)
        XCTAssertNil(current.avatarHost)
        current.ensureAvatars([])
        XCTAssertNil(current.avatarHost)
        for view in [original, current] { view.bind(reaction(nil, custom: true), animated: false) }
        current.ensureAvatars([0])
        let host = try XCTUnwrap(current.avatarHost)
        XCTAssertTrue(host.isEventLess)
        current.updateLayout(size: current.frame.size, transition: .immediate)
        XCTAssertEqual(host.frame, original.avatarHost?.frame)
        current.ensureAvatars([0, 1])
        current.ensureAvatars([])
        XCTAssertTrue(current.avatarHost === host)
        XCTAssertEqual(current.subviews.count, original.subviews.count)
        let (_, fresh) = pair(tag: false)
        fresh.bind(reaction("1", selected: true), animated: false)
        XCTAssertEqual(fresh.subviews.count, 1)
        XCTAssertEqual(original.subviews.count, 2)
    }

    func testDeselectionReplacesEntranceTransformAndUsesPresentationOpacity() throws {
        let (original, current) = pair(tag: false)
        let window = attach([original, current])
        window.orderFront(nil)
        for view in [original, current] { view.bind(reaction("12", selected: true), animated: true) }
        let a = try XCTUnwrap(original.selectionLayer), b = try XCTUnwrap(current.selectionLayer)
        for layer in [a, b] {
            layer.speed = 0
            layer.timeOffset = 26
            let alpha = CABasicAnimation(keyPath: "opacity")
            alpha.fromValue = 0.2
            alpha.toValue = 1.0
            alpha.beginTime = 1
            alpha.duration = 100
            alpha.fillMode = .both
            alpha.isRemovedOnCompletion = false
            layer.add(alpha, forKey: "opacity")
        }
        CATransaction.flush()
        let displayed = expectation(description: "Paused selected background presented")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { displayed.fulfill() }
        wait(for: [displayed], timeout: 3)
        let originalOpacity = try XCTUnwrap(a.presentation()?.opacity)
        let currentOpacity = try XCTUnwrap(b.presentation()?.opacity)
        XCTAssertLessThan(originalOpacity, 0.95)
        XCTAssertLessThan(currentOpacity, 0.95)
        for view in [original, current] { view.bind(reaction("12", selected: false), animated: true) }
        XCTAssertEqual(Set(a.animationKeys() ?? []), Set(b.animationKeys() ?? []))
        XCTAssertNil(b.animation(forKey: "transform.scale"))
        for key in a.animationKeys() ?? [] {
            let expected = try XCTUnwrap(a.animation(forKey: key) as? CABasicAnimation)
            let actual = try XCTUnwrap(b.animation(forKey: key) as? CABasicAnimation)
            XCTAssertEqual(expected.keyPath, actual.keyPath)
            XCTAssertEqual(expected.duration, actual.duration)
            XCTAssertEqual(expected.toValue as? NSObject, actual.toValue as? NSObject)
            if key == "opacity" {
                XCTAssertEqual((expected.fromValue as? NSNumber)?.floatValue ?? -1, originalOpacity, accuracy: 0.001)
                XCTAssertEqual((actual.fromValue as? NSNumber)?.floatValue ?? -1, currentOpacity, accuracy: 0.001)
            } else {
                XCTAssertEqual(expected.fromValue as? NSObject, actual.fromValue as? NSObject)
            }
        }
        for layer in [a, b] { layer.removeAllAnimations(); layer.removeFromSuperlayer() }
    }

    func testAccessibilityCountValueFrameHitAndControlPressRemainAvailable() throws {
        for tag in [false, true] {
            let (original, current) = pair(tag: tag)
            _ = attach([original, current])
            for view in [original, current] {
                view.toolTip = "Reaction from Alex"
                view.bind(reaction("15K"), animated: false)
            }
            let native = try XCTUnwrap(original.nativeText)
            let accessible = try XCTUnwrap(current.countAccessibility)
            XCTAssertEqual(native.accessibilityRole(), accessible.accessibilityRole())
            XCTAssertEqual(native.accessibilityValue() as? String, accessible.accessibilityValue() as? String)
            XCTAssertEqual(native.accessibilityFrame(), accessible.accessibilityFrame())
            XCTAssertTrue((accessible.accessibilityParent() as AnyObject?) === current)
            let rect = accessible.accessibilityFrame()
            XCTAssertTrue((current.accessibilityHitTest(CGPoint(x: rect.midX, y: rect.midY)) as AnyObject?) === accessible)
            XCTAssertTrue((current.accessibilityChildren() ?? []).contains { ($0 as AnyObject) === accessible })
            XCTAssertEqual(original.accessibilityLabel(), current.accessibilityLabel())
            XCTAssertEqual(original.accessibilityRole(), current.accessibilityRole())
            XCTAssertTrue(original.accessibilityPerformPress())
            XCTAssertTrue(current.accessibilityPerformPress())
            XCTAssertEqual(original.presses, current.presses)
            XCTAssertEqual(current.presses, 1)
            for view in [original, current] {
                view.setFrameOrigin(CGPoint(x: 43, y: 37))
                view.setFrameSize(CGSize(width: 210, height: 42))
                view.bind(reaction("Updated tag 2026"), animated: false)
            }
            XCTAssertTrue(current.countAccessibility === accessible)
            XCTAssertEqual(accessible.accessibilityValue() as? String, "Updated tag 2026")
            XCTAssertEqual(original.nativeText?.accessibilityFrame(), accessible.accessibilityFrame())
            XCTAssertNotEqual(rect, accessible.accessibilityFrame())
            current.isHidden = true
            XCTAssertNil(current.countAccessibility)
            current.isHidden = false
            TGUIKitAccessibility.isEnabled = false
            XCTAssertNil(current.countAccessibility)
            TGUIKitAccessibility.isEnabled = true
            current.bind(reaction(nil), animated: true)
            XCTAssertFalse(accessible.isAccessibilityElement())
            XCTAssertNil(accessible.accessibilityParent())
            current.bind(reaction("Restored"), animated: false)
            XCTAssertFalse(current.countAccessibility === accessible)
            XCTAssertFalse(accessible.isAccessibilityElement())
            XCTAssertNil(accessible.accessibilityParent())
        }
    }

    func testDetachedLayersAndAccessibilityElementsDoNotRetainControl() throws {
        weak var host: CurrentFull?
        weak var text: CALayer?
        var accessible: NSAccessibilityElement?
        autoreleasepool {
            let current = CurrentFull(frame: CGRect(x: 0, y: 0, width: 100, height: 32))
            current.bind(reaction("5", selected: true), animated: false)
            host = current
            text = current.countLayer
            accessible = current.countAccessibility
            current.bind(reaction(nil), animated: true)
        }
        waitForRemovals()
        XCTAssertNil(host)
        XCTAssertNil(text)
        XCTAssertNil(accessible?.accessibilityParent())
        XCTAssertFalse(accessible?.isAccessibilityElement() ?? true)
    }
}
