import Foundation
import XCTest
import SwiftSignalKit

private enum ThreadCase {
    typealias PeerId = Int
    enum Namespaces { enum Message { static let Cloud = 0 } }
    enum Message { static let newTopicThreadId: Int64 = -1 }
    struct MessageId { let peerId: Int; let namespace: Int; let id: Int32 }
    struct MessageIndex { static func absoluteLowerBound() -> Self { Self() } }
    enum Anchor { case automatic }
    enum FetchChannelReplyThreadMessageError: Error { case generic }
    struct ChatReplyThreadMessage {
        let peerId: Int
        let threadId: Int64
        init(peerId: Int, threadId: Int64, channelMessageId: Int? = nil, isChannelPost: Bool = false, isForumPost: Bool = false, isMonoforumPost: Bool = false, maxMessage: Int? = nil, maxReadIncomingMessageId: Int? = nil, maxReadOutgoingMessageId: Int? = nil, unreadCount: Int = 0, initialFilledHoles: [Int] = [], initialAnchor: Anchor = .automatic, isNotAvailable: Bool = false) {
            self.peerId = peerId; self.threadId = threadId
        }
    }
    enum ChatLocation {
        case peer(Int)
        case thread(ChatReplyThreadMessage)
        var threadId: Int64? {
            if case let .thread(message) = self { return message.threadId }
            return nil
        }
        static func makeSaved(_ peerId: Int, threadId: Int64, isMonoforum: Bool) -> Self {
            .thread(.init(peerId: peerId, threadId: threadId))
        }
    }
    struct Presentation {
        var chatLocation = ChatLocation.peer(1)
        func withUpdatedChatLocation(_ location: ChatLocation) -> Self {
            var state = self; state.chatLocation = location; return state
        }
    }
    final class Interaction {
        var presentation = Presentation()
        var isMonoforum = false
        var updateChatLocationThread: (Int64?) -> Void = { _ in }
        func update(_ f: (Presentation) -> Presentation) { presentation = f(presentation) }
    }
    final class Messages {
        var subscribers: [Int64: [Subscriber<ChatReplyThreadMessage, FetchChannelReplyThreadMessageError>]] = [:]
        var canceled: [Int64] = []
        func fetchChannelReplyThreadMessage(messageId: MessageId, atMessageId: MessageId?) -> Signal<ChatReplyThreadMessage, FetchChannelReplyThreadMessageError> {
            Signal { subscriber in
                let id = Int64(messageId.id)
                self.subscribers[id, default: []].append(subscriber)
                return ActionDisposable { self.canceled.append(id) }
            }
        }
        func complete(_ id: Int64) {
            subscribers[id]?.last?.putNext(.init(peerId: 1, threadId: id))
            subscribers[id]?.last?.putCompletion()
        }
        func fail(_ id: Int64) { subscribers[id]?.last?.putError(.generic) }
    }
    final class Engine { let messages = Messages() }
    final class Context { let engine = Engine() }
    final class Harness {
        let context = Context()
        let chatInteraction = Interaction()
        var chatLocation: ChatLocation { chatInteraction.presentation.chatLocation }
        let updateChatLocationThreadDisposable = MetaDisposable()
        let editCurrentMessagePhotoDisposable = MetaDisposable()
        let updateMediaDisposable = MetaDisposable()
        let loadSelectionMessagesDisposable = MetaDisposable()
        var scrolled = 0
        func cancelMessageFocus() {}
        func scrollup() { scrolled += 1 }
        func updateMaxVisibleReadIncomingMessageIndex(_ index: MessageIndex) {}
        init(threadId: Int64? = nil) {
            if let threadId { chatInteraction.presentation.chatLocation = .thread(.init(peerId: 1, threadId: threadId)) }
            let context = self.context
            let chatInteraction = self.chatInteraction
            let peerId = 1
            var didSetReadIndex = true
            let previousMaxIncomingMessageIdByNamespace = Atomic<[Int: Int]>(value: [:])
            let chatLocationContextHolder = Atomic<Int?>(value: nil)
__THREAD_SETUP__
        }
        func cleanup() {
__CLEANUP__
        }
        deinit { cleanup() }
    }
}

final class ThreadTests: XCTestCase {
    func testLatestTopicSelectionWinsWhenResponsesArriveOutOfOrder() {
        let h = ThreadCase.Harness()
        h.chatInteraction.updateChatLocationThread(10)
        h.chatInteraction.updateChatLocationThread(20)
        h.context.engine.messages.complete(20)
        h.context.engine.messages.complete(10)
        XCTAssertEqual(h.chatLocation.threadId, 20)
    }
    func testSelectingCurrentTopicCancelsPendingSwitch() {
        let h = ThreadCase.Harness(threadId: 10)
        h.chatInteraction.updateChatLocationThread(20)
        h.chatInteraction.updateChatLocationThread(10)
        h.context.engine.messages.complete(20)
        XCTAssertEqual(h.chatLocation.threadId, 10)
        XCTAssertEqual(h.scrolled, 1)
    }
    func testSelectingAllMessagesCancelsPendingSwitch() {
        let h = ThreadCase.Harness(threadId: 10)
        h.chatInteraction.updateChatLocationThread(20)
        h.chatInteraction.updateChatLocationThread(nil)
        h.context.engine.messages.complete(20)
        XCTAssertNil(h.chatLocation.threadId)
    }
    func testSelectingNewTopicCancelsPendingSwitch() {
        let h = ThreadCase.Harness()
        h.chatInteraction.updateChatLocationThread(20)
        h.chatInteraction.updateChatLocationThread(ThreadCase.Message.newTopicThreadId)
        h.context.engine.messages.complete(20)
        XCTAssertEqual(h.chatLocation.threadId, ThreadCase.Message.newTopicThreadId)
    }
    func testFailedTopicRequestCanBeRetried() {
        let h = ThreadCase.Harness()
        h.chatInteraction.updateChatLocationThread(20)
        h.context.engine.messages.fail(20)
        h.chatInteraction.updateChatLocationThread(20)
        h.context.engine.messages.complete(20)
        XCTAssertEqual(h.chatLocation.threadId, 20)
    }
    func testMonoforumSelectionRemainsImmediate() {
        let h = ThreadCase.Harness()
        h.chatInteraction.isMonoforum = true
        h.chatInteraction.updateChatLocationThread(20)
        XCTAssertEqual(h.chatLocation.threadId, 20)
        XCTAssertTrue(h.context.engine.messages.subscribers.isEmpty)
    }
    func testCleanupCancelsPendingTopicRequest() {
        let h = ThreadCase.Harness()
        h.chatInteraction.updateChatLocationThread(20)
        h.cleanup()
        h.context.engine.messages.complete(20)
        XCTAssertNil(h.chatLocation.threadId)
        XCTAssertEqual(h.context.engine.messages.canceled, [20])
    }
}
