import Cocoa
import XCTest
import SwiftSignalKit
import ObjectiveC
import Darwin
@testable import TGUIKit

private final class CountingSpinnerColor: NSColor {
    var alphaCalls = 0
    override func withAlphaComponent(_ alpha: CGFloat) -> NSColor {
        alphaCalls += 1
        return NSColor.systemBlue.withAlphaComponent(alpha)
    }
}

final class SpinnerLifecycleTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func field<T>(_ object: Any, _ name: String, as: T.Type = T.self) -> T? {
        var mirror: Mirror? = Mirror(reflecting: object)
        while let value = mirror {
            if let child = value.children.first(where: { $0.label == name }) { return child.value as? T }
            mirror = value.superclassMirror
        }
        return nil
    }

    private func timer(_ view: Any) throws -> SwiftSignalKit.Timer {
        try XCTUnwrap(field(view, "animationTimer"))
    }

    private func tick(_ view: Any) throws {
        let timer = try timer(view)
        let callback: (SwiftSignalKit.Timer) -> Void = try XCTUnwrap(field(timer, "completion"))
        callback(timer)
    }

    private func waitForTimer(_ seconds: Double) {
        let done = expectation(description: "Timer deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 3)
    }

    func testRepeatedStartsKeepTimerAndPhase() throws {
        let view = SpinningProgressView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        view.startAnimation()
        for _ in 0..<5 { try tick(view) }
        let original = try timer(view)
        let phase: Int = try XCTUnwrap(field(view, "currentPosition"))
        for _ in 0..<50 { view.startAnimation() }
        XCTAssertTrue(try timer(view) === original)
        XCTAssertEqual(field(view, "currentPosition", as: Int.self), phase)
    }

    func testSteadyTicksReuseTheTwelveFinColors() throws {
        let view = SpinningProgressView(frame: .zero), color = CountingSpinnerColor()
        view.color = color
        view.startAnimation()
        XCTAssertEqual(color.alphaCalls, 12)
        for _ in 0..<120 { try tick(view) }
        XCTAssertEqual(color.alphaCalls, 12)
    }

    func testRepeatedStopsKeepOriginalFadeDeadline() throws {
        let view = SpinningProgressView(frame: .zero)
        view.startAnimation()
        view.stopAnimation()
        let deadline: Date = try XCTUnwrap(field(view, "fadeOutStartTime"))
        for _ in 0..<50 { view.stopAnimation() }
        XCTAssertEqual(field(view, "fadeOutStartTime", as: Date.self), deadline)
        waitForTimer(0.9)
        XCTAssertFalse(view.isAnimating)
        XCTAssertNil(field(view, "animationTimer", as: SwiftSignalKit.Timer.self))
    }

    func testAlwaysAnimateUpdatesDetachedIndicatorImmediately() {
        let view = ProgressIndicator(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        view.alwaysAnimate = true
        XCTAssertTrue(view.isSpinning)
        view.alwaysAnimate = false
        waitForTimer(0.9)
        XCTAssertFalse(view.isSpinning)
    }

    func testResizeDoesNotResetMountedSpinner() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let progress = ProgressIndicator(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        window.contentView!.addSubview(progress)
        let indicator: SpinningProgressView = try XCTUnwrap(field(progress, "indicator"))
        let original = try timer(indicator)
        for _ in 0..<5 { try tick(indicator) }
        let phase: Int = try XCTUnwrap(field(indicator, "currentPosition"))
        for size: CGFloat in [21, 22, 23, 24] { progress.setFrameSize(NSSize(width: size, height: size)) }
        XCTAssertTrue(try timer(indicator) === original)
        XCTAssertEqual(field(indicator, "currentPosition", as: Int.self), phase)
    }

    func testCycleAndColorChangesRenderLikeReference() throws {
        let reference = ReferenceSpinningProgressView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        let current = SpinningProgressView(frame: reference.frame)
        reference.startAnimation(); current.startAnimation()
        for scale in [1, 2] {
            for phase in 0..<36 {
                if phase == 8 { reference.color = .systemRed; current.color = .systemRed }
                if phase == 17 { reference.setColor(.systemGreen); current.setColor(.systemGreen) }
                XCTAssertEqual(try render(current, scale: scale), try render(reference, scale: scale), "scale=\(scale), phase=\(phase)")
                try tick(reference); try tick(current)
            }
        }
    }

    func testDynamicColorsStayCorrectAcrossAppearanceChanges() throws {
        guard #available(macOS 11.0, *) else { return }
        let color = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .systemRed : .systemBlue
        }
        let reference = ReferenceSpinningProgressView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        let current = SpinningProgressView(frame: reference.frame)
        reference.color = color; current.color = color
        reference.startAnimation(); current.startAnimation()
        var first: Data?
        for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
            var captured: Data?
            var failure: Error?
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                do {
                    for _ in 0..<12 { try self.tick(reference); try self.tick(current) }
                    let baseline = try self.render(reference, scale: 2)
                    captured = try self.render(current, scale: 2)
                    XCTAssertEqual(captured, baseline)
                } catch { failure = error }
            }
            if let failure { throw failure }
            if let first, name == .darkAqua { XCTAssertNotEqual(first, captured) }
            if first == nil { first = captured }
        }
    }

    func testFadingAndRestartRebuildColorsThenResumeReuse() throws {
        let view = SpinningProgressView(frame: .zero), color = CountingSpinnerColor()
        view.color = color; view.startAnimation()
        view.stopAnimation()
        try tick(view); try tick(view)
        XCTAssertEqual(color.alphaCalls, 36)
        view.startAnimation()
        XCTAssertEqual(color.alphaCalls, 48)
        for _ in 0..<20 { try tick(view) }
        XCTAssertEqual(color.alphaCalls, 48)
        XCTAssertTrue(view.isAnimating)
        XCTAssertFalse(try XCTUnwrap(field(view, "isFadingOut", as: Bool.self)))
    }

    func testDirectColorAssignmentInvalidatesCachedCycle() throws {
        let view = SpinningProgressView(frame: .zero), first = CountingSpinnerColor(), next = CountingSpinnerColor()
        view.color = first; view.startAnimation()
        for _ in 0..<5 { try tick(view) }
        view.color = next
        try tick(view)
        XCTAssertEqual(next.alphaCalls, 12)
        for _ in 0..<24 { try tick(view) }
        XCTAssertEqual(next.alphaCalls, 12)
    }

    func testPhaseRemainsBoundedAfterManyCycles() throws {
        let view = SpinningProgressView(frame: .zero)
        view.startAnimation()
        for _ in 0..<1000 { try tick(view) }
        XCTAssertEqual(field(view, "currentPosition", as: Int.self), 1001 % 12)
    }

    func testIdleStopDoesNotStartFadeAndDestructionReleasesTimer() throws {
        weak var released: SpinningProgressView?
        weak var releasedTimer: SwiftSignalKit.Timer?
        autoreleasepool {
            let view = SpinningProgressView(frame: .zero)
            view.stopAnimation()
            XCTAssertFalse(field(view, "isFadingOut", as: Bool.self) ?? true)
            view.startAnimation()
            released = view
            releasedTimer = try? timer(view)
            XCTAssertNotNil(releasedTimer)
        }
        XCTAssertNil(released)
        XCTAssertNil(releasedTimer)
    }

    func testTickAndRepeatedStartBenchmark() throws {
        guard ProcessInfo.processInfo.environment["SPINNER_BENCHMARK"] != nil else { throw XCTSkip("Opt-in spinner benchmark") }
        let current = SpinningProgressView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        let reference = ReferenceSpinningProgressView(frame: current.frame)
        current.color = .systemBlue; reference.color = .systemBlue
        current.startAnimation(); reference.startAnimation()
        let currentTimer = try timer(current), referenceTimer = try timer(reference)
        let currentTick: (SwiftSignalKit.Timer) -> Void = try XCTUnwrap(field(currentTimer, "completion"))
        let referenceTick: (SwiftSignalKit.Timer) -> Void = try XCTUnwrap(field(referenceTimer, "completion"))
        for _ in 0..<1000 { currentTick(currentTimer); referenceTick(referenceTimer) }
        var reports: [String: Any] = [:]
        for starts in [false, true] {
            var before: [Double] = [], after: [Double] = []
            let iterations = starts ? 500 : 10000
            for batch in 0..<9 {
                for candidate in batch % 2 == 0 ? [false, true] : [true, false] {
                    let elapsed = autoreleasepool { () -> Double in
                        let start = CACurrentMediaTime()
                        for _ in 0..<iterations {
                            if starts {
                                if candidate { current.startAnimation() } else { reference.startAnimation() }
                            } else {
                                if candidate { currentTick(currentTimer) } else { referenceTick(referenceTimer) }
                            }
                        }
                        return (CACurrentMediaTime() - start) * 1e6 / Double(iterations)
                    }
                    if candidate { after.append(elapsed) } else { before.append(elapsed) }
                }
            }
            reports[starts ? "repeated_start" : "steady_tick"] = ["baseline_us": before, "candidate_us": after]
        }
        reports["allocation"] = ["baseline_view_bytes": malloc_size(Unmanaged.passUnretained(reference).toOpaque()), "candidate_view_bytes": malloc_size(Unmanaged.passUnretained(current).toOpaque()), "baseline_instance_bytes": class_getInstanceSize(ReferenceSpinningProgressView.self), "candidate_instance_bytes": class_getInstanceSize(SpinningProgressView.self)]
        try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/spinner-benchmark.json"))
    }

    private func render(_ view: View, scale: Int) throws -> Data {
        let size = 22 * scale
        let context = try XCTUnwrap(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        view.draw(try XCTUnwrap(view.layer), in: context)
        let data = Data(bytes: try XCTUnwrap(context.data), count: size * size * 4)
        XCTAssertTrue(data.contains { $0 != 0 })
        return data
    }
}
