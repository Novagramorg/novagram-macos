import Foundation
import XCTest

private enum ClipCase {
    enum CAMediaTimingFunctionName { case spring }
    struct CAMediaTimingFunction { init(controlPoints: Float, _ b: Float, _ c: Float, _ d: Float) {} }
    enum CATransaction { static func begin() {}; static func commit() {} }
    final class NSAnimationContext {
        static let current = NSAnimationContext()
        static var completions: [() -> Void] = []
        var duration: Double = 0
        var timingFunction: CAMediaTimingFunction?
        static func beginGrouping() {}
        static func endGrouping() {}
        static func runAnimationGroup(_ changes: (NSAnimationContext) -> Void, completionHandler: @escaping () -> Void) {
            changes(current)
            completions.append(completionHandler)
        }
    }
    final class Layer {
        var bounds = CGRect.zero
        func presentation() -> Layer? { nil }
    }
    final class Document { var isFlipped = false; var needsLayout = false }
    struct Insets { var top: CGFloat = 0 }
    struct ScrollView { var contentInsets = Insets() }
    final class Harness {
        var destinationOrigin: NSPoint?
        var point: NSPoint?
        var animatingContentRect: NSRect?
        var scrollAnimationId = 0
        var scrollCompletion: ((Bool) -> Void)?
        var scrollDidComplete: ((Bool) -> Void)?
        var bounds = NSRect(x: 0, y: 0, width: 300, height: 100)
        var frame: NSRect { bounds }
        let documentView: Document? = Document()
        let enclosingScrollView: ScrollView? = ScrollView()
        let layer: Layer? = Layer()
        var shortCompletions: [(Bool) -> Void] = []
        func animator() -> Harness { self }
        func scroll(to point: NSPoint) { bounds.origin = point }
        func setBoundsOrigin(_ point: NSPoint) { bounds.origin = point }
        func _changeBounds(from: NSRect, to: NSRect, animated: Bool, duration: Double, timingFunction: CAMediaTimingFunctionName, completion: @escaping (Bool) -> Void) {
            shortCompletions.append(completion)
        }
__CLIP_UPDATE__
__CLIP_SCROLL__
    }
}

final class ClipTests: XCTestCase {
    override func setUp() { ClipCase.NSAnimationContext.completions = [] }
    func testInterruptedAnimationClearsScrollingStateAndReportsFailure() {
        let h = ClipCase.Harness()
        var results: [Bool] = []
        h.scroll(to: NSPoint(x: 0, y: 40), animated: true, completion: { results.append($0) })
        h.bounds.origin.y = 40
        h.shortCompletions[0](false)
        XCTAssertNil(h.destinationOrigin)
        XCTAssertNil(h.point)
        XCTAssertEqual(results, [false])
    }
    func testOlderShortAnimationCannotRestoreItsDestination() {
        let h = ClipCase.Harness()
        h.scroll(to: NSPoint(x: 0, y: 40), animated: true)
        h.scroll(to: NSPoint(x: 0, y: 80), animated: true)
        h.shortCompletions[1](true)
        h.shortCompletions[0](true)
        XCTAssertEqual(h.bounds.minY, 80)
    }
    func testOlderAnimationDoesNotCompleteNewRequest() {
        let h = ClipCase.Harness()
        var results: [Bool] = []
        h.scroll(to: NSPoint(x: 0, y: 40), animated: true)
        h.scroll(to: NSPoint(x: 0, y: 80), animated: true, completion: { results.append($0) })
        h.shortCompletions[0](false)
        XCTAssertTrue(results.isEmpty)
        h.shortCompletions[1](true)
        XCTAssertEqual(results, [true])
    }
    func testOlderLongAnimationCannotRestoreItsDestination() {
        let h = ClipCase.Harness()
        h.scroll(to: NSPoint(x: 0, y: 1000), animated: true)
        h.scroll(to: NSPoint(x: 0, y: 2000), animated: true)
        ClipCase.NSAnimationContext.completions[1]()
        ClipCase.NSAnimationContext.completions[0]()
        XCTAssertEqual(h.bounds.minY, 2000)
    }
    func testDirectPositionUpdateInvalidatesAnimation() {
        let h = ClipCase.Harness()
        var results: [Bool] = []
        h.scroll(to: NSPoint(x: 0, y: 40), animated: true, completion: { results.append($0) })
        h.updateBounds(to: NSPoint(x: 0, y: 20))
        h.shortCompletions[0](true)
        XCTAssertEqual(h.bounds.minY, 20)
        XCTAssertEqual(results, [false])
        XCTAssertNil(h.scrollCompletion)
    }
    func testNonanimatedJumpSupersedesOldAnimation() {
        let h = ClipCase.Harness()
        var count = 0
        h.scroll(to: NSPoint(x: 0, y: 40), animated: true)
        h.scroll(to: NSPoint(x: 0, y: 20), animated: false, completion: { _ in count += 1 })
        h.shortCompletions[0](true)
        XCTAssertEqual(h.bounds.minY, 20)
        XCTAssertEqual(count, 1)
    }
    func testNonanimatedJumpToPendingDestinationCompletesImmediately() {
        let h = ClipCase.Harness()
        var results: [Bool] = []
        h.scroll(to: NSPoint(x: 0, y: 40), animated: true)
        h.scroll(to: NSPoint(x: 0, y: 40), animated: false, completion: { results.append($0) })
        XCTAssertEqual(h.bounds.minY, 40)
        XCTAssertEqual(results, [true])
        XCTAssertNil(h.destinationOrigin)
        h.shortCompletions[0](true)
        XCTAssertEqual(results, [true])
    }
    func testSameDestinationUsesLatestCompletionWithoutRestartingAnimation() {
        let h = ClipCase.Harness()
        var firstCount = 0
        var secondCount = 0
        h.scroll(to: NSPoint(x: 0, y: 40), animated: true, completion: { _ in firstCount += 1 })
        h.scroll(to: NSPoint(x: 0, y: 40), animated: true, completion: { _ in secondCount += 1 })
        XCTAssertEqual(h.shortCompletions.count, 1)
        h.shortCompletions[0](true)
        XCTAssertEqual(firstCount, 0)
        XCTAssertEqual(secondCount, 1)
    }
    func testUninterruptedShortScrollKeepsCompletionAndPosition() {
        let h = ClipCase.Harness()
        var results: [Bool] = []
        h.scroll(to: NSPoint(x: 0, y: 40), animated: true, completion: { results.append($0) })
        h.shortCompletions[0](true)
        XCTAssertEqual(h.bounds.minY, 40)
        XCTAssertEqual(results, [true])
        XCTAssertNil(h.destinationOrigin)
    }
    func testUninterruptedLongScrollKeepsCompletionAndPosition() {
        let h = ClipCase.Harness()
        var results: [Bool] = []
        h.scroll(to: NSPoint(x: 0, y: 1000), animated: true, completion: { results.append($0) })
        ClipCase.NSAnimationContext.completions[0]()
        XCTAssertEqual(h.bounds.minY, 1000)
        XCTAssertEqual(results, [true])
    }
}
