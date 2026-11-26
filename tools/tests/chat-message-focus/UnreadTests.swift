import Foundation
import XCTest
import SwiftSignalKit

private typealias MessageId = UnreadCase.MessageId
private enum Namespaces { enum Message { static let Cloud = 0 } }
private enum UnreadCase {
    struct MessageId: Hashable { var namespace = 0; let id: Int }
    struct Message { let id: MessageId }
    class View { var visibleRect = CGRect(x: 0, y: 0, width: 300, height: 50) }
    class ChatRowItem { var messages: [Message]; var view: View? = View(); init(_ id: Int) { messages = [.init(id: .init(id: id))] } }
    class Clip { var isAnimateScrolling = false }
    class Table {
        let clipView = Clip()
        var items: [ChatRowItem] = []
        func enumerateVisibleItems(with f: (Any) -> Bool) { for item in items { if !f(item) { break } } }
    }
    class Generic { let tableView = Table() }
    class Window { var isKeyWindow = true }
    class Tracker {
        var mentions: [Set<MessageId>] = []
        var reactions: [Set<MessageId>] = []
        func updateMarkMentionsSeenForMessageIds(messageIds: Set<MessageId>) { mentions.append(messageIds) }
        func updateMarkReactionsAndVotesSeenForMessageIds(messageIds: Set<MessageId>) { reactions.append(messageIds) }
    }
    class Account { let viewTracker = Tracker() }
    class Context { let account = Account(); let window = Window() }
    enum ChatUIHooks {
        static let shared = ChatUIHooksState()
    }
    class ChatUIHooksState {
        var locked = false
        func appIsLockedValue() -> Bool? { locked }
    }
    class Manager { var process: ((Set<MessageId>) -> Void)? }
    class Harness {
        let genericView = Generic()
        let context = Context()
        var interactiveReadEnabled = true
        let messageMentionProcessingManager = Manager()
        let messageReactionsMentionProcessingManager = Manager()
        var effects: [Set<MessageId>] = []
        func playUnseenReactions(_ ids: Set<MessageId>, checkUnseen: Bool) { effects.append(ids) }
        init() {
            let context = self.context
__UNREAD_PROCESSING__
        }
__VISIBLE_READ_IDS__
        func process() {
            messageMentionProcessingManager.process?([.init(id: 1)])
            messageReactionsMentionProcessingManager.process?([.init(id: 1)])
        }
    }
}

final class UnreadTests: XCTestCase {
    override func setUp() { UnreadCase.ChatUIHooks.shared.locked = false }
    func testHiddenChatDoesNotReadMentionsOrReactions() {
        let h = UnreadCase.Harness()
        h.genericView.tableView.items = [.init(1)]
        h.interactiveReadEnabled = false
        h.process()
        XCTAssertTrue(h.context.account.viewTracker.mentions.isEmpty)
        XCTAssertTrue(h.context.account.viewTracker.reactions.isEmpty)
    }
    func testLockDuringReadDelayDoesNotConsumeUnreadState() {
        let h = UnreadCase.Harness()
        h.genericView.tableView.items = [.init(1)]
        UnreadCase.ChatUIHooks.shared.locked = true
        h.process()
        XCTAssertTrue(h.context.account.viewTracker.mentions.isEmpty)
        XCTAssertTrue(h.context.account.viewTracker.reactions.isEmpty)
    }
    func testMessagesPassedDuringJumpAreNotMarkedRead() {
        let h = UnreadCase.Harness()
        h.genericView.tableView.items = [.init(1)]
        h.genericView.tableView.clipView.isAnimateScrolling = true
        h.process()
        XCTAssertTrue(h.context.account.viewTracker.mentions.isEmpty)
        XCTAssertTrue(h.context.account.viewTracker.reactions.isEmpty)
    }
    func testDelayedBatchDoesNotReadMessagesNoLongerVisible() {
        let h = UnreadCase.Harness()
        h.genericView.tableView.items = [.init(2)]
        h.process()
        XCTAssertTrue(h.context.account.viewTracker.mentions.isEmpty)
        XCTAssertTrue(h.context.account.viewTracker.reactions.isEmpty)
        XCTAssertTrue(h.effects.isEmpty)
    }
    func testSettledVisibleMessageIsRead() {
        let h = UnreadCase.Harness()
        h.genericView.tableView.items = [.init(1)]
        h.process()
        XCTAssertEqual(h.context.account.viewTracker.mentions, [[.init(id: 1)]])
        XCTAssertEqual(h.context.account.viewTracker.reactions, [[.init(id: 1)]])
        XCTAssertEqual(h.effects, [[.init(id: 1)]])
    }
    func testReturningToChatCanReadPreviouslyDeferredBatch() {
        let h = UnreadCase.Harness()
        h.genericView.tableView.items = [.init(1)]
        h.interactiveReadEnabled = false
        h.process()
        h.interactiveReadEnabled = true
        h.process()
        XCTAssertEqual(h.context.account.viewTracker.mentions.count, 1)
        XCTAssertEqual(h.context.account.viewTracker.reactions.count, 1)
    }
}
