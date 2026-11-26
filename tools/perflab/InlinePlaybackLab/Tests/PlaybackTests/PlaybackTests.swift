import Cocoa
import XCTest
import TGUIKit
@testable import Playback

final class PlaybackTests: XCTestCase {
    func testSharedParentGeometryIsReadOnce() {
        let fixture = Fixture(count: 200)
        fixture.text.reads = 0
        fixture.window.reads = 0
        fixture.update(true)
        let expected = fixture.states
        XCTAssertEqual(fixture.text.reads, 200)
        fixture.text.reads = 0
        fixture.window.reads = 0
        fixture.update(false)
        XCTAssertEqual(fixture.states, expected)
        XCTAssertEqual(fixture.text.reads, 1)
        XCTAssertEqual(fixture.window.reads, 1)
    }

    func testInactiveAndLiteUpdatesDoNotReadGeometry() {
        let fixture = Fixture(count: 200)
        for state in 0..<3 {
            fixture.window.key = state != 0
            fixture.update(true, lite: state == 1, detached: state == 2)
            let expected = fixture.states
            XCTAssertEqual(fixture.text.reads > 0, true)
            fixture.text.reads = 0
            fixture.update(false, lite: state == 1, detached: state == 2)
            XCTAssertEqual(fixture.states, expected)
            XCTAssertEqual(fixture.text.reads, 0)
            XCTAssertTrue(fixture.states.values.allSatisfy { !$0 })
        }
    }

    func testEmptyCollectionDoesNotReadWindowState() {
        let fixture = Fixture(count: 0)
        fixture.window.reads = 0
        fixture.text.reads = 0
        fixture.update(false)
        XCTAssertEqual(fixture.window.reads, 0)
        XCTAssertEqual(fixture.text.reads, 0)
    }

    func testScrollResizeAndFrameChangesMatchReference() {
        let fixture = Fixture(count: 240)
        var random: UInt64 = 0x261016
        func next(_ bound: Int) -> Int {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            return Int((random >> 32) % UInt64(bound))
        }
        for _ in 0..<1000 {
            fixture.window.key = next(3) != 0
            let lite = next(5) == 0
            fixture.scroll.frame.size = NSSize(width: 80 + next(300), height: 50 + next(400))
            fixture.scroll.contentView.scroll(to: NSPoint(x: next(30), y: next(1500)))
            fixture.text.frame.origin = NSPoint(x: next(30) - 15, y: next(300) - 150)
            let layer = fixture.layers[next(240)]!
            layer.frame = NSRect(x: next(400) - 50, y: next(1800) - 50, width: next(80), height: next(80))
            fixture.update(true, lite: lite)
            let expected = fixture.states
            fixture.update(false, lite: lite)
            XCTAssertEqual(fixture.states, expected)
        }
    }

    func testInterleavedParentsAndOtherLayersMatchReference() {
        let fixture = Fixture(count: 40)
        let second = TextHost(frame: NSRect(x: 50, y: 150, width: 100, height: 600))
        fixture.document.addSubview(second)
        var sequence: [SimpleLayer] = []
        for index in 0..<40 {
            let layer = fixture.layers[index] as! InlineStickerItemLayer
            if index % 2 == 0 { layer.superview = second }
            sequence.append(layer)
            sequence.append(SimpleLayer())
        }
        for y in stride(from: 0, to: 900, by: 30) {
            fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            fixture.update(true)
            let expected = fixture.states
            updateInlineStickerPlayback(sequence, window: fixture.window, isLite: false)
            XCTAssertEqual(fixture.states, expected)
        }
    }

    func testDetachedLayersStopAndReparentedLayersResume() {
        let fixture = Fixture(count: 1)
        let layer = fixture.layers[0] as! InlineStickerItemLayer
        fixture.update(true)
        XCTAssertEqual(layer.isPlayable, true)
        layer.superview = nil
        fixture.update(true)
        XCTAssertEqual(layer.isPlayable, true)
        fixture.update(false)
        XCTAssertEqual(layer.isPlayable, false)
        layer.superview = fixture.text
        fixture.update(false)
        XCTAssertEqual(layer.isPlayable, true)
    }

    func testVisibilityIsNotRetainedAcrossUpdates() {
        let fixture = Fixture(count: 1)
        let layer = fixture.layers[0] as! InlineStickerItemLayer
        weak var released: NSView?
        autoreleasepool {
            let temporary = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
            fixture.document.addSubview(temporary)
            layer.superview = temporary
            released = temporary
            fixture.update(false)
            XCTAssertEqual(layer.isPlayable, true)
            temporary.removeFromSuperview()
        }
        XCTAssertNil(released)
        fixture.update(false)
        XCTAssertEqual(layer.isPlayable, false)
    }

    func testClippingEdgesKeepAppKitIntersectionSemantics() {
        let fixture = Fixture(count: 1)
        let layer = fixture.layers[0] as! InlineStickerItemLayer
        let rect = fixture.text.visibleRect
        for frame in [rect, .zero, NSRect(x: rect.maxX, y: rect.minY, width: 10, height: 10), NSRect(x: rect.maxX - 0.25, y: rect.minY, width: 10, height: 10), NSRect(x: 0, y: rect.maxY, width: 10, height: 10), NSRect(x: 10, y: 10, width: -1, height: 10)] {
            layer.frame = frame
            fixture.update(true)
            let expected = layer.isPlayable
            fixture.update(false)
            XCTAssertEqual(layer.isPlayable, expected)
        }
    }

    func testPlaybackBenchmark() throws {
        guard ProcessInfo.processInfo.environment["INLINE_PLAYBACK_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        let count = 3000
        var results: [[String: Any]] = []
        for (layers, mode) in [(0, "active"), (1, "active"), (4, "active"), (16, "active"), (64, "active"), (256, "active"), (64, "scrolling"), (64, "inactive"), (64, "lite")] {
            let fixture = Fixture(count: layers)
            fixture.window.key = mode != "inactive"
            var oldTrials: [Double] = [], newTrials: [Double] = []
            func measure(_ baseline: Bool) -> Double {
                let start = DispatchTime.now().uptimeNanoseconds
                for index in 0..<count {
                    if mode == "scrolling" { fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: index % 1000)) }
                    fixture.update(baseline, lite: mode == "lite")
                }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(count) / 1000
            }
            _ = measure(true); _ = measure(false)
            for batch in 0..<9 {
                if batch % 2 == 0 { oldTrials.append(measure(true)); newTrials.append(measure(false)) }
                else { newTrials.append(measure(false)); oldTrials.append(measure(true)) }
            }
            fixture.update(true, lite: mode == "lite")
            let expected = fixture.states
            fixture.update(false, lite: mode == "lite")
            XCTAssertEqual(fixture.states, expected)
            results.append(["layers": layers, "mode": mode, "baseline_us": oldTrials.sorted()[4], "candidate_us": newTrials.sorted()[4], "baseline_trials_us": oldTrials, "candidate_trials_us": newTrials])
        }
        let data = try JSONSerialization.data(withJSONObject: ["batches": 9, "iterations_per_batch": count, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/inline-playback-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
