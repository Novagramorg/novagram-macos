import AppKit
import XCTest

struct LayoutSnapshot: Equatable {
    let stage: String
    let frame: NSRect
    let documentRect: NSRect
    let bounds: NSRect
    let visible: NSRange
    let rowRects: [NSRect]
    let realizedFrames: [Int: NSRect]
    let selected: Int?
    let pixels: Data
}

final class LayoutTests: XCTestCase {
    func testNativeLayoutPreservesGeometryPixelsAndRowLifetime() {
        LayoutBootstrap.install()
        for flipped in [false, true] {
            for count in [0, 1, 4, 80] {
                for inset in [CGFloat(0), 20] {
                    let old = runBaselineScenario(flipped: flipped, count: count, inset: inset, render: true)
                    let new = runCandidateScenario(flipped: flipped, count: count, inset: inset, render: true)
                    XCTAssertEqual(old.count, new.count)
                    for (a, b) in zip(old, new) {
                        let context = "\(flipped) \(count) \(inset) \(a.stage)"
                        XCTAssertEqual(a.frame, b.frame, context)
                        XCTAssertEqual(a.documentRect, b.documentRect, context)
                        XCTAssertEqual(a.bounds, b.bounds, context)
                        XCTAssertEqual(a.visible, b.visible, context)
                        XCTAssertEqual(a.rowRects, b.rowRects, context)
                        XCTAssertEqual(a.realizedFrames, b.realizedFrames, context)
                        XCTAssertEqual(a.selected, b.selected, context)
                        XCTAssertEqual(a.pixels, b.pixels, context)
                    }
                }
            }
        }
    }

    func testStableLayoutPreservesBothHeaderCaches() {
        LayoutBootstrap.install()
        let old = runBaselineCacheRetentionScenario()
        let new = runCandidateCacheRetentionScenario()
        XCTAssertEqual(old.first, [4, 36])
        XCTAssertEqual(new.first, [4, 36])
        for index in 1...3 {
            XCTAssertEqual(old[index], [-1, -1])
            XCTAssertEqual(new[index], [4, 36])
        }
        XCTAssertEqual(new[4], [-1, -1])
        XCTAssertEqual(new[5], [5, 36])
    }

    func testReentrantMutationsDoNotRestoreStaleIndexes() {
        LayoutBootstrap.install()
        for mode in 0..<5 {
            XCTAssertTrue(runBaselineReentrantCacheScenario(mode: mode), "baseline \(mode)")
            XCTAssertTrue(runCandidateReentrantCacheScenario(mode: mode), "candidate \(mode)")
        }
    }

    func testBaselineControl() {
        LayoutBootstrap.install()
        for flipped in [false, true] {
            for inset in [CGFloat(0), 20] {
                let first = runBaselineScenario(flipped: flipped, count: 80, inset: inset, render: true)
                let second = runBaselineScenario(flipped: flipped, count: 80, inset: inset, render: true)
                for (a, b) in zip(first, second) {
                    XCTAssertEqual(a.realizedFrames, b.realizedFrames, "\(flipped) \(inset) \(a.stage)")
                    XCTAssertEqual(a.pixels, b.pixels, a.stage)
                    XCTAssertEqual(a.bounds, b.bounds, a.stage)
                }
            }
        }
    }

    func testStickyHeadersMatchAfterLayoutScrollAndRemoval() {
        LayoutBootstrap.install()
        XCTAssertEqual(runBaselineStickyScenario(), runCandidateStickyScenario())
    }
}
