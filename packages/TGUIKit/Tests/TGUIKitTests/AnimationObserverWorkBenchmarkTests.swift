import AppKit
import XCTest
import Darwin
@testable import TGUIKit

final class AnimationObserverWorkBenchmarkTests: XCTestCase {
    func testConstructionAndBindingCosts() throws {
        guard ProcessInfo.processInfo.environment["OBSERVER_WORK_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in animation observer benchmark") }
        TGUIKitTestBootstrap.install()
        let fixture = AnimationObserverWorkTests()
        defer { fixture.tearDown() }
        var results: [String: [[Double]]] = [:]
        for depth in [0, 4, 16] {
            let attached = NSView(), detached = NSView(), detachedRoot = NSView()
            _ = fixture.attach(attached, depth: depth)
            let contentView = attached.enclosingScrollView!.contentView
            let documentView = attached.enclosingScrollView!.documentView
            var parent = detachedRoot
            for _ in 0..<depth {
                let child = NSView()
                parent.addSubview(child)
                parent = child
            }
            parent.addSubview(detached)
            let target = ObserverWorkTarget()
            let selector = #selector(ObserverWorkTarget.receive(_:))
            let baseline = BaselineCompactObserver(), candidate = AnimatableContentObserver()
            let oldToken = BaselineCompactTokenObserver(), newToken = AnimatableContentTokenObserver()
            let handler: (Notification) -> Void = { _ in }
            for scenario in depth == 0 ? ["construct", "detached_update", "attached_selector_update", "explicit_selector_update", "attached_token_update"] : ["detached_update", "attached_selector_update", "attached_token_update"] {
                var retained: [AnyObject] = []
                retained.reserveCapacity(10000)
                let operations: [() -> Void] = [
                    {
                        switch scenario {
                        case "construct": retained.append(BaselineCompactObserver())
                        case "detached_update": baseline.update(for: detached, target: target, selector: selector)
                        case "attached_selector_update": baseline.update(for: attached, target: target, selector: selector)
                        case "explicit_selector_update": baseline.update(for: attached, target: target, selector: selector, contentView: contentView, documentView: documentView, options: [.contentBounds, .documentFrame])
                        default: oldToken.update(for: attached, handler: handler)
                        }
                    },
                    {
                        switch scenario {
                        case "construct": retained.append(AnimatableContentObserver())
                        case "detached_update": candidate.update(for: detached, target: target, selector: selector)
                        case "attached_selector_update": candidate.update(for: attached, target: target, selector: selector)
                        case "explicit_selector_update": candidate.update(for: attached, target: target, selector: selector, contentView: contentView, documentView: documentView, options: [.contentBounds, .documentFrame])
                        default: newToken.update(for: attached, handler: handler)
                        }
                    }
                ]
                autoreleasepool { for _ in 0..<100 { operations[0](); operations[1]() }; retained.removeAll(keepingCapacity: true) }
                var samples = [[Double](), [Double]()]
                for batch in 0..<9 {
                    for variant in batch % 2 == 0 ? [0, 1] : [1, 0] {
                        let start = CACurrentMediaTime()
                        autoreleasepool {
                            for _ in 0..<10000 { operations[variant]() }
                            retained.removeAll(keepingCapacity: true)
                        }
                        samples[variant].append((CACurrentMediaTime() - start) * 1e6 / 10000)
                    }
                }
                results["\(scenario)_depth\(depth)"] = samples
            }
            withExtendedLifetime(detachedRoot) {}
        }
        let oldIdle = BaselineCompactObserver(), newIdle = AnimatableContentObserver()
        let receiver = try XCTUnwrap(fixture.storedReceiver(oldIdle))
        XCTAssertNil(fixture.storedReceiver(newIdle))
        let allocations = ["baseline_observer_bytes": malloc_size(Unmanaged.passUnretained(oldIdle).toOpaque()), "candidate_observer_bytes": malloc_size(Unmanaged.passUnretained(newIdle).toOpaque()), "baseline_receiver_bytes": malloc_size(Unmanaged.passUnretained(receiver).toOpaque())]
        XCTAssertEqual(allocations["baseline_observer_bytes"], allocations["candidate_observer_bytes"])
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_baseline_then_candidate": results, "allocations": allocations], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/observer-work-benchmark.json"))
    }
}
