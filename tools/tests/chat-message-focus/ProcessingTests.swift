import Foundation
import XCTest
import SwiftSignalKit

private enum ProcessingCase {
    typealias MessageId = Int
    static let messagesViewQueue = Queue()
    static func delaySignal(_ seconds: Double) -> Signal<Never, NoError> { .complete() |> delay(seconds, queue: messagesViewQueue) }
__PROCESSING_MANAGER__
    static func makeReactionManager() -> ChatMessageThrottledProcessingManager { __REACTIONS_MANAGER_INIT__ }
}

final class ProcessingTests: XCTestCase {
    func testNewReactionOnPreviouslySeenMessageIsProcessedAgain() {
        let manager = ProcessingCase.makeReactionManager()
        var batches: [Set<Int>] = []
        manager.process = { batches.append($0) }
        manager.add([1])
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        manager.add([1])
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(batches.filter { $0 == [1] }.count, 2)
    }
    func testZeroIntervalAllowsExplicitResubmissionWithoutIdlePolling() {
        let manager = ProcessingCase.ChatMessageThrottledProcessingManager(delay: 0.01, submitInterval: 0)
        var batches: [Set<Int>] = []
        manager.process = { batches.append($0) }
        manager.add([1])
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        XCTAssertEqual(batches, [[1]])
        manager.add([1])
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        XCTAssertEqual(batches, [[1], [1]])
    }
    func testDefaultManagerStillDeduplicatesMessages() {
        let manager = ProcessingCase.ChatMessageThrottledProcessingManager(delay: 0.01)
        var batches: [Set<Int>] = []
        manager.process = { if !$0.isEmpty { batches.append($0) } }
        manager.add([1])
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        manager.add([1])
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        XCTAssertEqual(batches, [[1]])
    }
}
