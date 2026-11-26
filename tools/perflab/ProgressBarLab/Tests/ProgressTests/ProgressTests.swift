import Cocoa
import XCTest
import TGUIKit
import ProgressReference

protocol ProgressBar: Control {
    var progressHeight: CGFloat { get set }
    var roundCorners: Bool { get set }
    var cornerRadius: CGFloat { get set }
    var insets: NSEdgeInsets { get set }
    var hasMinumimVisibility: Bool { get set }
    var previewColor: NSColor { get set }
    var previewProgress: CGFloat? { get set }
    var containerBackground: NSColor { get set }
    var fetchingColor: NSColor { get set }
    var scrubberImage: CGImage? { get set }
    var onUserChanged: ((Float) -> Void)? { get set }
    var onLiveScrobbling: ((Float?) -> Void)? { get set }
    var startScrobbling: (() -> Void)? { get set }
    var endScrobbling: (() -> Void)? { get set }
    var liveScrobbling: Bool { get set }
    var hasTemporaryState: Bool { get }
    var currentValue: CGFloat { get }
    func set(progress: CGFloat, animated: Bool, duration: Double, timingFunction: CAMediaTimingFunctionName, bounce: Bool)
    func set(fetchingProgress: CGFloat, animated: Bool, duration: Double)
    func set(fetchingProgressRanges: [Range<CGFloat>], animated: Bool)
    func set(progress: CGFloat, animated: Bool, duration: Double, beginTime: Double?, offset: Double, speed: Float, seekId: Int?, repeatForever: Bool)
}
extension LinearProgressControl: ProgressBar {}
extension LegacyProgressControl: ProgressBar {}
extension ProgressBar {
    func progress(_ value: CGFloat, animated: Bool = false) { set(progress: value, animated: animated, duration: 0.2, timingFunction: .linear, bounce: false) }
    func fetching(_ value: CGFloat, animated: Bool = false) { set(fetchingProgress: value, animated: animated, duration: 0.2) }
    func align(_ value: Int) {
        if let current = self as? LinearProgressControl { current.alignment = value == 0 ? .top : value == 1 ? .center : .bottom }
        if let old = self as? LegacyProgressControl { old.alignment = value == 0 ? .top : value == 1 ? .center : .bottom }
    }
    var track: NSView { subviews[0] }
    var bars: [CALayer] { track.layer!.sublayers ?? [] }
}

private var icons: [NSImage] = []
final class ProgressTests: XCTestCase {
    var window: NSWindow!
    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        if icons.isEmpty {
            for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
                let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                    NSColor.black.setFill()
                    rect.fill()
                    return true
                }
                image.setName(name)
                icons.append(image)
            }
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
    }
    override func tearDown() { window.close(); window = nil }

    func pair(_ height: CGFloat = 4) -> (LegacyProgressControl, LinearProgressControl) {
        let old = LegacyProgressControl(progressHeight: height), new = LinearProgressControl(progressHeight: height)
        for control: any ProgressBar in [old, new] {
            control.frame = NSRect(x: 0, y: 0, width: 320, height: 30)
            control.style = ControlStyle(font: .systemFont(ofSize: 13), foregroundColor: .systemBlue, backgroundColor: .clear)
            control.containerBackground = NSColor.gray.withAlphaComponent(0.2)
            control.fetchingColor = NSColor.gray.withAlphaComponent(0.5)
            control.previewColor = NSColor.red.withAlphaComponent(0.5)
            window.contentView!.addSubview(control)
        }
        window.displayIfNeeded()
        return (old, new)
    }
    func pixels(_ control: any ProgressBar, scale: CGFloat) -> Data {
        control.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        let width = Int(ceil(control.frame.width * scale)), height = Int(ceil(control.frame.height * scale))
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        control.layer!.render(in: ctx)
        return Data(bytes: ctx.data!, count: width * height * 4)
    }
    func equal(_ old: any ProgressBar, _ new: any ProgressBar, render: Bool = true, scale: CGFloat = 2, file: StaticString = #filePath, line: UInt = #line) {
        old.layoutSubtreeIfNeeded(); new.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        XCTAssertEqual(old.track.frame, new.track.frame, file: file, line: line)
        XCTAssertEqual(old.bars.count, new.bars.count, file: file, line: line)
        for (a, b) in zip(old.bars, new.bars) {
            for (x, y) in zip([a.frame.minX, a.frame.minY, a.frame.width, a.frame.height], [b.frame.minX, b.frame.minY, b.frame.width, b.frame.height]) {
                XCTAssertEqual(x, y, accuracy: 0.00000001, file: file, line: line)
            }
            XCTAssertEqual(a.anchorPoint, b.anchorPoint, file: file, line: line)
            XCTAssertEqual(a.cornerRadius, b.cornerRadius, file: file, line: line)
            XCTAssertEqual(a.isHidden, b.isHidden, file: file, line: line)
            XCTAssertEqual(a.masksToBounds, b.masksToBounds, file: file, line: line)
            XCTAssertEqual(a.backgroundColor, b.backgroundColor, file: file, line: line)
        }
        if render {
            let a = pixels(old, scale: scale), b = pixels(new, scale: scale)
            XCTAssertTrue(a.contains { $0 != 0 }, file: file, line: line)
            XCTAssertEqual(a, b, file: file, line: line)
        }
    }
    func testGeometryAndPixels() {
        let (old, new) = pair()
        for i in 0..<300 {
            for control: any ProgressBar in [old, new] {
                control.progressHeight = [CGFloat(1), 3.5, 4, 8, 16][i % 5]
                control.align(i % 3)
                control.insets = NSEdgeInsets(top: 0, left: CGFloat(i % 13), bottom: 0, right: CGFloat(i % 17))
                control.frame = NSRect(x: 0, y: 0, width: CGFloat(40 + i % 300) + 0.5, height: 30)
                control.hasMinumimVisibility = i % 2 == 0
                control.roundCorners = i % 3 != 0
                control.progress(CGFloat(i % 11) / 10)
                control.fetching(CGFloat(i % 9) / 8)
                control.previewProgress = i % 7 == 0 ? nil : CGFloat(i % 5) / 4
                control.set(fetchingProgressRanges: i % 2 == 0 ? [0..<0.5, 0.2..<0.9, 0.3..<1] : [], animated: false)
                control.layout()
            }
            equal(old, new, scale: CGFloat(i % 3 + 1))
        }
    }

    func icon(_ width: Int = 10) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: 10, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: width, height: 10))
        return ctx.makeImage()!
    }

    func testScrubberColorsCornersAndRangeTransitions() {
        let (old, new) = pair()
        let image = icon()
        for i in 0..<100 {
            for bar: any ProgressBar in [old, new] {
                bar.scrubberImage = i % 3 == 0 ? nil : image
                bar.cornerRadius = CGFloat(i % 6)
                bar.roundCorners = i % 2 == 0
                bar.fetchingColor = i % 2 == 0 ? .blue : .green
                bar.previewColor = i % 3 == 0 ? .yellow : .orange
                bar.containerBackground = i % 2 == 0 ? .darkGray : .lightGray
                bar.style = ControlStyle(font: .systemFont(ofSize: 13), foregroundColor: i % 2 == 0 ? .red : .purple, backgroundColor: .clear)
                bar.previewProgress = 0.9
                bar.progress(CGFloat(i % 11) / 10)
                bar.set(fetchingProgressRanges: Array(repeating: 0.1..<0.9, count: i % 5), animated: false)
                bar.layout()
            }
            equal(old, new)
            XCTAssertEqual(old.subviews.last!.frame, new.subviews.last!.frame)
        }
    }

    func testOutOfRangeAndNaNMatchExistingBehavior() {
        let (old, new) = pair()
        for progress in [CGFloat(-1), 0, 0.5, 1, 1.5, .nan] {
            for fetching in [CGFloat(-1), 0, 0.5, 1.5, .nan] {
                for bar: any ProgressBar in [old, new] {
                    bar.progress(progress)
                    bar.fetching(fetching)
                    bar.previewProgress = progress
                }
                equal(old, new)
            }
        }
    }

    func testViewCountAndRemovedRangeRelease() {
        let (old, new) = pair()
        for bar: any ProgressBar in [old, new] {
            bar.progress(0.5)
            bar.set(fetchingProgressRanges: [0..<1, 0.1..<0.9, 0.2..<0.8], animated: false)
            bar.layout()
        }
        equal(old, new)
        XCTAssertEqual(old.track.subviews.count, 6)
        XCTAssertEqual(new.track.subviews.count, 0)
        XCTAssertEqual(new.bars.count, 6)
        weak var removed: CALayer?
        autoreleasepool {
            new.set(fetchingProgressRanges: [0..<1, 0.1..<0.9, 0.2..<0.8, 0.3..<0.7], animated: false)
            removed = new.bars[4]
            new.set(fetchingProgressRanges: [], animated: false)
            window.displayIfNeeded()
            CATransaction.flush()
        }
        XCTAssertNil(removed)
        XCTAssertEqual(new.bars.count, 3)
    }

    func event(_ type: NSEvent.EventType, bar: any ProgressBar, fraction: CGFloat) -> NSEvent {
        let point = bar.track.convert(NSPoint(x: bar.track.frame.width * fraction, y: 2), to: nil)
        return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    func testScrubbingAndDisabledCallbacksMatch() {
        for live in [true, false] {
            for enabled in [true, false] {
                let (old, new) = pair()
                var values: [[Float]] = [], liveValues: [[Float?]] = [], temporary: [[Bool]] = [], starts: [Int] = [], ends: [Int] = []
                for bar: any ProgressBar in [old, new] {
                    window.contentView!.subviews.forEach { $0.removeFromSuperview() }
                    window.contentView!.addSubview(bar)
                    var changed: [Float] = [], updates: [Float?] = [], states: [Bool] = []
                    var start = 0, end = 0
                    bar.insets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 15)
                    bar.layout()
                    bar.liveScrobbling = live
                    bar.isEnabled = enabled
                    bar.onUserChanged = { changed.append($0) }
                    bar.onLiveScrobbling = { updates.append($0) }
                    bar.startScrobbling = { start += 1 }
                    bar.endScrobbling = { end += 1 }
                    bar.mouseDown(with: event(.leftMouseDown, bar: bar, fraction: 0.2))
                    states.append(bar.hasTemporaryState)
                    for fraction in [CGFloat(-0.1), 0.3, 0.7, 1.1] {
                        bar.mouseDragged(with: event(.leftMouseDragged, bar: bar, fraction: fraction))
                        states.append(bar.hasTemporaryState)
                    }
                    bar.mouseUp(with: event(.leftMouseUp, bar: bar, fraction: 0.75))
                    states.append(bar.hasTemporaryState)
                    values.append(changed); liveValues.append(updates); temporary.append(states); starts.append(start); ends.append(end)
                }
                XCTAssertEqual(values[0], values[1])
                XCTAssertEqual(liveValues[0], liveValues[1])
                XCTAssertEqual(temporary[0], temporary[1])
                XCTAssertEqual(starts, [1, 1]); XCTAssertEqual(ends, [1, 1])
                if enabled { XCTAssertEqual(values[1].last, 0.75) } else { XCTAssertTrue(values[1].isEmpty) }
                window.contentView!.addSubview(old)
                window.contentView!.addSubview(new)
                old.layout(); new.layout()
                equal(old, new)
                old.removeFromSuperview(); new.removeFromSuperview()
            }
        }
    }

    func testHitTestingRemainsOnInteractiveControl() {
        let (old, new) = pair()
        let image = icon()
        for interactive in [false, true] {
            for scrubber in [false, true] {
                for bar: any ProgressBar in [old, new] {
                    bar.userInteractionEnabled = interactive
                    bar.scrubberImage = scrubber ? image : nil
                    bar.progress(0.5)
                    bar.set(fetchingProgressRanges: [0..<1], animated: false)
                    bar.layout()
                }
                for x in stride(from: CGFloat(-10), through: 330, by: 5) {
                    for y in stride(from: CGFloat(-5), through: 35, by: 5) {
                        let a = old.hitTest(NSPoint(x: x, y: y)), b = new.hitTest(NSPoint(x: x, y: y))
                        XCTAssertEqual(a == nil, b == nil)
                        XCTAssertEqual(a === old, b === new)
                        if let a, let b, a !== old { XCTAssertEqual(a.className, b.className) }
                    }
                }
            }
        }
    }

    func testAccessibilityAdjustments() {
        let (old, new) = pair()
        TGUIKitAccessibility.isEnabled = true
        defer { TGUIKitAccessibility.isEnabled = true }
        var values: [[Float]] = []
        for bar: any ProgressBar in [old, new] {
            var updates: [Float] = []
            bar.onUserChanged = { updates.append($0) }
            bar.progress(0.5)
            XCTAssertEqual(bar.accessibilityRole(), .slider)
            XCTAssertEqual(bar.accessibilityValue() as? String, "50%")
            XCTAssertTrue(bar.accessibilityPerformIncrement())
            XCTAssertTrue(bar.accessibilityPerformDecrement())
            bar.isEnabled = false
            XCTAssertFalse(bar.accessibilityPerformIncrement())
            values.append(updates)
        }
        XCTAssertEqual(values[0], values[1])
        TGUIKitAccessibility.isEnabled = false
        XCTAssertFalse(new.accessibilityPerformIncrement())
    }

    func testAnimationParametersPauseSeekAndResize() {
        let (old, new) = pair()
        let image = icon()
        for bar: any ProgressBar in [old, new] { bar.scrubberImage = image; bar.layout(); bar.progress(0.2) }
        func check() {
            for (a, b) in zip(old.bars, new.bars) {
                XCTAssertEqual(a.animationKeys(), b.animationKeys())
                for key in a.animationKeys() ?? [] {
                    let x = a.animation(forKey: key) as! CABasicAnimation, y = b.animation(forKey: key) as! CABasicAnimation
                    XCTAssertEqual(x.keyPath, y.keyPath)
                    XCTAssertEqual(x.fromValue as? NSNumber, y.fromValue as? NSNumber)
                    XCTAssertEqual(x.toValue as? NSNumber, y.toValue as? NSNumber)
                    XCTAssertEqual(x.duration, y.duration)
                    XCTAssertEqual(x.beginTime, y.beginTime)
                    XCTAssertEqual(x.timeOffset, y.timeOffset)
                    XCTAssertEqual(x.speed, y.speed)
                    XCTAssertEqual(x.fillMode, y.fillMode)
                }
            }
        }
        let start = CACurrentMediaTime() + 100
        for offset in [Double(0), 1, 1.05, 2, 30] {
            for bar: any ProgressBar in [old, new] {
                bar.set(progress: 0.2, animated: true, duration: 100, beginTime: start, offset: offset, speed: 1, seekId: Int(offset), repeatForever: false)
            }
            check()
        }
        for bar: any ProgressBar in [old, new] {
            bar.set(progress: 0.4, animated: false, duration: 100, beginTime: start, offset: 40, speed: 0, seekId: 30, repeatForever: false)
        }
        check()
        XCTAssertNil(new.bars.last!.animation(forKey: "trackWidth"))
        for bar: any ProgressBar in [old, new] {
            bar.set(progress: 0.4, animated: true, duration: 100, beginTime: start, offset: 40, speed: 2, seekId: 31, repeatForever: false)
            bar.frame.size.width += 20
        }
        check()
        XCTAssertNil(new.bars.last!.animation(forKey: "trackWidth"))
        equal(old, new)
    }
}
