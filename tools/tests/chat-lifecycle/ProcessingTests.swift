import Foundation
import XCTest
import SwiftSignalKit

private enum ProcessingCase {
    typealias MessageId = Int
    static let messagesViewQueue = Queue()
    static func delaySignal(_ seconds: Double) -> Signal<Never, NoError> { .complete() |> delay(seconds, queue: messagesViewQueue) }
__PROCESSING_MANAGER__
}

final class ProcessingTests: XCTestCase {
    private func drain(_ duration: Double = 0.08) { RunLoop.main.run(until: Date().addingTimeInterval(duration)) }
    func testPauseCancelsPendingBatch() {
        let manager = ProcessingCase.ChatMessageThrottledProcessingManager(delay: 0.02, submitInterval: 1)
        var batches: [Set<Int>] = []
        manager.process = { batches.append($0) }
        manager.add([1])
        manager.setActive(false)
        drain()
        XCTAssertTrue(batches.isEmpty)
    }
    func testInactiveAddWaitsUntilResume() {
        let manager = ProcessingCase.ChatMessageThrottledProcessingManager(delay: 0.01, submitInterval: 1)
        var batches: [Set<Int>] = []
        manager.process = { batches.append($0) }
        manager.setActive(false)
        manager.add([1])
        drain()
        XCTAssertTrue(batches.isEmpty)
        manager.setActive(true)
        drain()
        XCTAssertEqual(batches, [[1]])
        manager.setActive(false)
    }
    func testQueuedDeliveryDoesNotRetainManagerAfterOwnerReleasesIt() {
        var manager: ProcessingCase.ChatMessageThrottledProcessingManager? = .init(delay: 0.01)
        weak var reference = manager
        var calls = 0
        manager?.process = { _ in calls += 1 }
        manager?.add([1])
        Thread.sleep(forTimeInterval: 0.05)
        manager = nil
        XCTAssertNil(reference)
        drain()
        XCTAssertEqual(calls, 0)
    }
    func testPauseDropsAlreadyQueuedMainThreadDelivery() {
        let manager = ProcessingCase.ChatMessageThrottledProcessingManager(delay: 0.01)
        var calls = 0
        manager.process = { _ in calls += 1 }
        manager.add([1])
        Thread.sleep(forTimeInterval: 0.05)
        manager.setActive(false)
        drain()
        XCTAssertEqual(calls, 0)
    }
    func testPauseResumeDoesNotDeliverOldQueuedBatch() {
        let manager = ProcessingCase.ChatMessageThrottledProcessingManager(delay: 0.01, submitInterval: 1)
        var batches: [Set<Int>] = []
        manager.process = { if !$0.isEmpty { batches.append($0) } }
        manager.add([1])
        Thread.sleep(forTimeInterval: 0.05)
        manager.setActive(false)
        manager.add([2])
        manager.setActive(true)
        drain()
        XCTAssertEqual(batches, [[2]])
        manager.setActive(false)
    }
    func testPeriodicRefreshStillRepeatsAndStopsOnPause() {
        let manager = ProcessingCase.ChatMessageThrottledProcessingManager(delay: 0.01, submitInterval: 0.02)
        var calls = 0
        manager.process = { ids in if !ids.isEmpty { calls += 1 } }
        manager.add([1])
        drain(0.12)
        XCTAssertGreaterThanOrEqual(calls, 2)
        manager.setActive(false)
        let before = calls
        drain()
        XCTAssertEqual(calls, before)
    }
}
