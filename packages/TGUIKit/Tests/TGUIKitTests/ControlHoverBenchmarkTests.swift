import Cocoa
import XCTest
import SwiftSignalKit
import Darwin
@testable import TGUIKit

private final class CurrentHoverBenchmarkControl: Control {
    override func mouseInside() -> Bool { true }
}

private final class LegacyHoverBenchmarkControl: LegacyHoverControl {
    override func mouseInside() -> Bool { true }
}

final class ControlHoverBenchmarkTests: XCTestCase {
    func testHoverAllocationAndLifecycleCosts() throws {
        guard ProcessInfo.processInfo.environment["CONTROL_HOVER_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in control hover allocation benchmark") }
        TGUIKitTestBootstrap.install()
        let entered = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        let moved = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        let exited = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        var results: [String: [[Double]]] = [:]
        for scenario in ["construct", "movement_without_handler", "schedule_cancel"] {
            let baseline = LegacyHoverBenchmarkControl(), candidate = CurrentHoverBenchmarkControl()
            baseline.canHighlight = false; candidate.canHighlight = false
            var notifications = [0, 0]
            if scenario == "schedule_cancel" {
                baseline.set(handler: { _ in notifications[0] += 1 }, for: .LongOver)
                candidate.set(handler: { _ in notifications[1] += 1 }, for: .LongOver)
            }
            let operations: [(Int) -> Void] = [
                { _ in
                    switch scenario {
                    case "construct": withExtendedLifetime(LegacyHoverControl()) {}
                    case "movement_without_handler": baseline.mouseMoved(with: moved)
                    default: baseline.mouseEntered(with: entered); baseline.mouseExited(with: exited)
                    }
                },
                { _ in
                    switch scenario {
                    case "construct": withExtendedLifetime(Control()) {}
                    case "movement_without_handler": candidate.mouseMoved(with: moved)
                    default: candidate.mouseEntered(with: entered); candidate.mouseExited(with: exited)
                    }
                }
            ]
            for i in 0..<100 { operations[0](i); operations[1](i) }
            var samples = [[Double](), [Double]()]
            let iterations = scenario == "construct" ? 2000 : scenario == "schedule_cancel" ? 5000 : 20000
            for batch in 0..<9 {
                for variant in batch % 2 == 0 ? [0, 1] : [1, 0] {
                    let start = CFAbsoluteTimeGetCurrent()
                    autoreleasepool { for i in 0..<iterations { operations[variant](i) } }
                    samples[variant].append((CFAbsoluteTimeGetCurrent() - start) * 1_000_000 / Double(iterations))
                }
            }
            XCTAssertEqual(notifications, [0, 0])
            results[scenario] = samples
        }
        let baseline = LegacyHoverControl(), candidate = Control()
        let holder = try XCTUnwrap(Mirror(reflecting: baseline).children.first { $0.label == "longOverHandleDisposable" }?.value as? MetaDisposable)
        let baselineBytes = malloc_size(Unmanaged.passUnretained(baseline).toOpaque())
        let candidateBytes = malloc_size(Unmanaged.passUnretained(candidate).toOpaque())
        let holderBytes = malloc_size(Unmanaged.passUnretained(holder).toOpaque())
        XCTAssertGreaterThan(baselineBytes, 0)
        XCTAssertGreaterThan(candidateBytes, 0)
        XCTAssertGreaterThan(holderBytes, 0)
        XCTAssertGreaterThan(baselineBytes + holderBytes, candidateBytes)
        let memory = ["baseline_view_bytes": baselineBytes, "candidate_view_bytes": candidateBytes, "baseline_hover_holder_bytes": holderBytes, "saved_object_bytes_per_idle_control": baselineBytes + holderBytes - candidateBytes]
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_baseline_then_candidate": results, "object_allocations": memory], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/control-hover-benchmark.json"))
    }
}
