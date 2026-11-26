import Cocoa
import QuartzCore
import XCTest
import TGUIKit
@testable import CommentsHarness

final class CommentsBenchmarkTests: XCTestCase {
    func testConstructionAndUpdateCosts() throws {
        guard ProcessInfo.processInfo.environment["COMMENTS_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in benchmark") }
        _ = NSApplication.shared
        System.updateScaleFactor(2)
        let helper = CommentsTests()
        helper.setUp()
        let fixtures = [CommentsFixture(title: CommentsFixture.count(123), peers: 2, unread: true, border: true, loading: false, bubble: true),
                        CommentsFixture(title: CommentsFixture.count(124), peers: 2, unread: true, border: true, loading: false, bubble: true)]
        let legacyData = fixtures.map(helper.legacyData)
        let currentData = fixtures.map { helper.currentData($0) }
        let size = NSMakeSize(260, 42)
        let host = View(frame: NSMakeRect(0, 0, 400, 400))
        func time(_ iterations: Int, _ body: () -> Void) -> Double {
            let start = CACurrentMediaTime()
            for _ in 0 ..< iterations { body() }
            return (CACurrentMediaTime() - start) * 1_000_000 / Double(iterations)
        }
        var results: [String: [[Double]]] = ["construct": [[], []], "update_changed": [[], []], "update_same": [[], []]]
        let legacy = LegacyChannelCommentsBubbleControl(frame: NSMakeRect(0, 0, 260, 42))
        let current = ChannelCommentsBubbleControl(frame: NSMakeRect(0, 50, 260, 42))
        host.addSubview(legacy); host.addSubview(current)
        legacy.update(data: legacyData[0], size: size, animated: false)
        current.update(data: currentData[0], size: size, animated: false)
        for batch in 0 ..< 9 {
            for variant in (batch % 2 == 0 ? [0, 1] : [1, 0]) {
                autoreleasepool {
                    CATransaction.begin()
                    let construct = time(300) {
                        if variant == 0 {
                            let view = LegacyChannelCommentsBubbleControl(frame: NSMakeRect(0, 0, 260, 42))
                            host.addSubview(view)
                            view.update(data: legacyData[0], size: size, animated: false)
                            view.removeFromSuperview()
                        } else {
                            let view = ChannelCommentsBubbleControl(frame: NSMakeRect(0, 0, 260, 42))
                            host.addSubview(view)
                            view.update(data: currentData[0], size: size, animated: false)
                            view.removeFromSuperview()
                        }
                    }
                    var flip = 0
                    let changed = time(2000) {
                        flip ^= 1
                        if variant == 0 { legacy.update(data: legacyData[flip], size: size, animated: false) } else { current.update(data: currentData[flip], size: size, animated: false) }
                    }
                    let same = time(2000) {
                        if variant == 0 { legacy.update(data: legacyData[flip], size: size, animated: false) } else { current.update(data: currentData[flip], size: size, animated: false) }
                    }
                    CATransaction.commit()
                    CATransaction.flush()
                    results["construct"]![variant].append(construct)
                    results["update_changed"]![variant].append(changed)
                    results["update_same"]![variant].append(same)
                }
            }
        }
        for (name, values) in results.sorted(by: { $0.key < $1.key }) {
            let legacyMedian = values[0].sorted()[4], currentMedian = values[1].sorted()[4]
            print(String(format: "COMMENTS_BENCHMARK %@ legacy=%.3fus current=%.3fus change=%+.1f%%", name, legacyMedian, currentMedian, (currentMedian - legacyMedian) / legacyMedian * 100))
        }
        func count(_ view: NSView) -> Int { view.subviews.reduce(1) { $0 + count($1) } }
        print("COMMENTS_BENCHMARK views legacy=\(count(legacy)) current=\(count(current))")
    }
}
