import XCTest
import Postbox
import SwiftSignalKit
import TelegramCore
@testable import ChatUI

final class ThrottledProcessingManagerTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(1))

    private func ids(_ values: [Int32]) -> [MessageId] {
        return values.map { MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: $0) }
    }

    private func run(for seconds: Double) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func makeManager(_ batches: Atomic<[Set<MessageId>]>) -> ChatMessageThrottledProcessingManager {
        let manager = ChatMessageThrottledProcessingManager(delay: 0.05, submitInterval: 0.1)
        manager.process = { ids in
            let _ = batches.modify { $0 + [ids] }
        }
        return manager
    }

    func testRepollsOnlyTheLatestVisibleBatch() {
        let batches = Atomic<[Set<MessageId>]>(value: [])
        let manager = self.makeManager(batches)

        manager.add(self.ids([1, 2]))
        self.run(for: 0.1)
        manager.add(self.ids([3]))
        self.run(for: 0.1)
        let _ = batches.swap([])
        self.run(for: 0.6)

        let repolled = batches.with { $0 }
        XCTAssertGreaterThanOrEqual(repolled.count, 2)
        for batch in repolled {
            XCTAssertEqual(batch, Set(self.ids([3])))
        }
    }

    func testInactiveManagerStopsPolling() {
        let batches = Atomic<[Set<MessageId>]>(value: [])
        let manager = self.makeManager(batches)

        manager.add(self.ids([1, 2]))
        self.run(for: 0.3)
        XCTAssertFalse(batches.with { $0 }.isEmpty)

        manager.setActive(false)
        self.run(for: 0.2)
        let _ = batches.swap([])
        self.run(for: 0.6)
        XCTAssertTrue(batches.with { $0 }.isEmpty)

        manager.setActive(true)
        self.run(for: 0.3)
        let resumed = batches.with { $0 }
        XCTAssertFalse(resumed.isEmpty)
        XCTAssertEqual(resumed.first, Set(self.ids([1, 2])))
    }

    func testManagerWithoutSubmitIntervalProcessesOnce() {
        let batches = Atomic<[Set<MessageId>]>(value: [])
        let manager = ChatMessageThrottledProcessingManager(delay: 0.05)
        manager.process = { ids in
            let _ = batches.modify { $0 + [ids] }
        }
        manager.add(self.ids([1, 2]))
        manager.add(self.ids([1, 2]))
        self.run(for: 0.5)
        XCTAssertEqual(batches.with { $0 }, [Set(self.ids([1, 2]))])
    }
}
