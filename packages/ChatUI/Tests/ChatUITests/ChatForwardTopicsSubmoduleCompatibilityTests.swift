import XCTest
import Cocoa
import Postbox
import TelegramCore
@testable import ChatUI

private struct Topic {
    let threadId: Int64
    let timestamp: Int32
    var pinnedIndex: Int? = nil
    var isHidden: Bool = false
    var isClosed: Bool = false
}

private let forumPeerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(1))

private func makeItem(_ topic: Topic) -> EngineChatList.Item {
    let peer = TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2)), accessHash: nil, firstName: "Author", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    let threadData = MessageHistoryThreadData(
        creationDate: 0,
        isOwnedByMe: false,
        author: peer.id,
        info: EngineMessageHistoryThread.Info(title: "Topic \(topic.threadId)", icon: nil, iconColor: 0),
        incomingUnreadCount: 0,
        isMarkedUnread: false,
        maxIncomingReadId: 0,
        maxKnownMessageId: 0,
        maxOutgoingReadId: 0,
        isClosed: topic.isClosed,
        isHidden: topic.isHidden,
        notificationSettings: TelegramPeerNotificationSettings.defaultSettings,
        isMessageFeeRemoved: false
    )
    let pinnedIndex: EngineChatList.Item.PinnedIndex = topic.pinnedIndex.map { .index($0) } ?? .none
    return EngineChatList.Item(
        id: .forum(topic.threadId),
        index: .forum(pinnedIndex: pinnedIndex, timestamp: topic.timestamp, threadId: topic.threadId, namespace: Namespaces.Message.Cloud, id: topic.timestamp),
        messages: [],
        readCounters: nil,
        isMuted: false,
        draft: nil,
        threadData: threadData,
        renderedPeer: EngineRenderedPeer(peer: .user(peer)),
        presence: nil,
        hasUnseenMentions: false,
        hasUnseenReactions: false,
        hasUnseenPollVotes: false,
        forumTopicData: nil,
        topForumTopicItems: [],
        hasFailed: false,
        isContact: false,
        autoremoveTimeout: nil,
        storyStats: nil,
        displayAsTopicList: false,
        isPremiumRequiredToMessage: false,
        mediaDraftContentType: nil
    )
}

private func submoduleThreadIndexOrder(_ topics: [Topic]) -> [Topic] {
    return topics.sorted(by: { lhs, rhs in
        if let lhsPinnedIndex = lhs.pinnedIndex, let rhsPinnedIndex = rhs.pinnedIndex {
            return lhsPinnedIndex < rhsPinnedIndex
        } else if (lhs.pinnedIndex == nil) != (rhs.pinnedIndex == nil) {
            if lhs.pinnedIndex != nil {
                return true
            } else {
                return false
            }
        }
        return lhs.timestamp > rhs.timestamp
    })
}

private func forumChatListItems(_ topics: [Topic]) -> [EngineChatList.Item] {
    return submoduleThreadIndexOrder(topics).map(makeItem).reversed()
}

private func threadIds(_ items: [EngineChatList.Item]) -> [Int64] {
    return items.map { item in
        if case let .forum(threadId) = item.id {
            return threadId
        } else {
            return -1
        }
    }
}

private func canSend(_ item: EngineChatList.Item) -> Bool {
    return item.threadData?.isClosed != true
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

final class ChatForwardTopicsSubmoduleCompatibilityTests: XCTestCase {

    func testTopicsFollowTheForumListOrder() {
        let topics = [
            Topic(threadId: 1, timestamp: 300),
            Topic(threadId: 2, timestamp: 500),
            Topic(threadId: 3, timestamp: 100, pinnedIndex: 1),
            Topic(threadId: 4, timestamp: 50, pinnedIndex: 0),
            Topic(threadId: 5, timestamp: 400)
        ]
        let result = forwardMenuTopicItems(forumChatListItems(topics), canSend: canSend)
        XCTAssertEqual(threadIds(result), [4, 3, 2, 5, 1])
    }

    func testShowsEveryTopicOfALargeForum() {
        let topics = [Topic(threadId: 1, timestamp: 5)] + (2 ... 120).map { Topic(threadId: Int64($0), timestamp: Int32($0) * 10) }
        let result = forwardMenuTopicItems(forumChatListItems(topics), canSend: canSend)
        XCTAssertEqual(threadIds(result), (2 ... 120).reversed().map(Int64.init) + [1])
    }

    func testRecentlyActiveGeneralKeepsItsPlace() {
        let topics = (2 ... 60).map { Topic(threadId: Int64($0), timestamp: Int32($0) * 10) } + [Topic(threadId: 1, timestamp: 1000)]
        let result = forwardMenuTopicItems(forumChatListItems(topics), canSend: canSend)
        XCTAssertEqual(threadIds(result), [1] + (2 ... 60).reversed().map(Int64.init))
    }

    func testHiddenGeneralComesFirst() {
        let topics = [Topic(threadId: 1, timestamp: 5, isHidden: true)] + (2 ... 30).map { Topic(threadId: Int64($0), timestamp: Int32($0) * 10) }
        let result = forwardMenuTopicItems(forumChatListItems(topics), canSend: canSend)
        XCTAssertEqual(threadIds(result), [1] + (2 ... 30).reversed().map(Int64.init))
    }

    func testTopicsThatCannotBeSentToAreSkipped() {
        let closed = (2 ... 6).map { Topic(threadId: Int64($0), timestamp: 1000 + Int32($0), isClosed: true) }
        let open = (7 ... 30).map { Topic(threadId: Int64($0), timestamp: Int32($0) * 10) }
        let result = forwardMenuTopicItems(forumChatListItems([Topic(threadId: 1, timestamp: 900)] + closed + open), canSend: canSend)
        XCTAssertEqual(threadIds(result), [1] + (7 ... 30).reversed().map(Int64.init))
    }

    func testClosedGeneralIsSkipped() {
        let topics = [Topic(threadId: 1, timestamp: 5, isClosed: true)] + (2 ... 30).map { Topic(threadId: Int64($0), timestamp: Int32($0) * 10) }
        let result = forwardMenuTopicItems(forumChatListItems(topics), canSend: canSend)
        XCTAssertEqual(threadIds(result), (2 ... 30).reversed().map(Int64.init))
    }

    func testSmallForumShowsEverySendableTopic() {
        let topics = [
            Topic(threadId: 1, timestamp: 10),
            Topic(threadId: 2, timestamp: 20, isClosed: true),
            Topic(threadId: 3, timestamp: 30)
        ]
        let result = forwardMenuTopicItems(forumChatListItems(topics), canSend: canSend)
        XCTAssertEqual(threadIds(result), [3, 1])
    }

    func testInputOrderAssumptionsStillHold() throws {
        let threadIndexView = try String(contentsOf: repositoryRoot.appendingPathComponent("submodules/telegram-ios/submodules/Postbox/Sources/MessageHistoryThreadIndexView.swift"), encoding: .utf8)
        XCTAssertTrue(threadIndexView.contains("return lhsPinnedIndex < rhsPinnedIndex"))
        XCTAssertTrue(threadIndexView.contains("return lhs.index > rhs.index"))

        let predicate = try String(contentsOf: repositoryRoot.appendingPathComponent("packages/TelegramUtils/Sources/TelegramUtils/ChatListFilterPredicate.swift"), encoding: .utf8)
        let forumBranch = try XCTUnwrap(predicate.components(separatedBy: "case let .forum(peerId):").dropFirst().first)
        let forumList = try XCTUnwrap(forumBranch.components(separatedBy: "let list = EngineChatList(").dropFirst().first)
        XCTAssertTrue(forumList.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("items: items.reversed(),"))
    }
}
