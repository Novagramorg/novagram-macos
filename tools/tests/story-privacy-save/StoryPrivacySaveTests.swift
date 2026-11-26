import Foundation
import XCTest
import SwiftSignalKit

struct EngineStoryPrivacy: Equatable {
    let base: Int
    let additionallyIncludePeers: [Int]
}
struct StoryId: Hashable { let peerId: Int; let id: Int32 }
struct CodableEntry {
    let value: Any
    init?(_ value: Any) { self.value = value }
    func get<T>(_ type: T.Type) -> T? { value as? T }
}
enum Stories {
    enum StoredItem { case item(Item), deleted }
    struct Item: Equatable {
        struct Privacy: Equatable { let base: Int; let additionallyIncludePeers: [Int] }
        var id: Int32
        var timestamp = 1
        var expirationTimestamp = 2
        var media = 3
        var alternativeMediaList = [4]
        var mediaAreas = [5]
        var text = "original"
        var entities = [6]
        var views = 7
        var privacy: Privacy? = .init(base: 0, additionallyIncludePeers: [])
        var isPinned = true
        var isExpired = false
        var isPublic = true
        var isCloseFriends = false
        var isContacts = false
        var isSelectedContacts = false
        var isForwardingDisabled = true
        var isEdited = false
        var isMy = true
        var myReaction = 8
        var forwardInfo = 9
        var music = 10
        var authorId = 11
        var folderIds = [12]
        var isLiveStream: Bool { media == 99 }
    }
}
struct StoryItemsTableEntry {
    let value: CodableEntry
    let id: Int32
    let expirationTimestamp: Int
    let isCloseFriends: Bool
    let isLiveStream: Bool
}
enum Api {
    enum InputPeer: Equatable { case inputPeerSelf }
    struct InputPrivacyRule { let privacy: EngineStoryPrivacy }
    struct Updates { let id: Int }
    enum functions {
        enum stories {
            static func editStory(flags: Int32, peer: InputPeer, id: Int32, media: Int?, mediaAreas: [Int]?, caption: String?, entities: [Int]?, privacyRules: [InputPrivacyRule], music: Int?) -> Request {
                .init(flags: flags, peer: peer, id: id, privacy: privacyRules.first!.privacy)
            }
        }
    }
}
struct Request { let flags: Int32; let peer: Api.InputPeer; let id: Int32; let privacy: EngineStoryPrivacy }
struct MTRpcError: Error { let errorDescription: String }
final class Transaction {
    var canResolvePrivacy = true
    var stories: [StoryId: CodableEntry] = [:]
    var lists: [Int: [StoryItemsTableEntry]] = [:]
    func getStory(id: StoryId) -> CodableEntry? { stories[id] }
    func setStory(id: StoryId, value: CodableEntry) { stories[id] = value }
    func getStoryItems(peerId: Int) -> [StoryItemsTableEntry] { lists[peerId] ?? [] }
    func setStoryItems(peerId: Int, items: [StoryItemsTableEntry]) { lists[peerId] = items }
}
func apiInputPrivacyRules(privacy: EngineStoryPrivacy, transaction: Transaction) -> [Api.InputPrivacyRule]? { transaction.canResolvePrivacy ? [.init(privacy: privacy)] : nil }
final class Postbox {
    let storage = Transaction()
    var delayNext = false
    var finish: (() -> Void)?
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            let run = { subscriber.putNext(f(self.storage)); subscriber.putCompletion() }
            if self.delayNext {
                self.delayNext = false
                self.finish = run
                return ActionDisposable { self.finish = nil }
            }
            run()
            return EmptyDisposable
        }
    }
}
final class Pending {
    let request: Request
    var subscriber: Subscriber<Api.Updates, MTRpcError>?
    var cancelled = false
    init(_ request: Request) { self.request = request }
    func succeed() { subscriber?.putNext(.init(id: 1)); subscriber?.putCompletion() }
    func fail(_ reason: String = "PRIVACY_ERROR") { subscriber?.putError(.init(errorDescription: reason)) }
}
final class Network {
    var pending: [Pending] = []
    func request(_ request: Request) -> Signal<Api.Updates, MTRpcError> {
        Signal { subscriber in
            let pending = Pending(request)
            pending.subscriber = subscriber
            self.pending.append(pending)
            return ActionDisposable { pending.cancelled = true; pending.subscriber = nil }
        }
    }
}
final class StateManager {
    var updates: [Int] = []
    func addUpdates(_ updates: Api.Updates) { self.updates.append(updates.id) }
}
final class Account {
    let peerId = 10
    let postbox = Postbox()
    let network = Network()
    let stateManager = StateManager()
}
__SOURCE__

final class StoryPrivacySaveTests: XCTestCase {
    func testUnresolvedPrivacyFailsWithoutSendingOrChangingCaches() {
        let account = Account(); install(account)
        account.postbox.storage.canResolvePrivacy = false
        var failed = false; var completed = false
        let operation = _internal_editStoryPrivacy(account: account, id: 1, privacy: privacy).start(error: { _ in failed = true }, completed: { completed = true })
        XCTAssertTrue(failed); XCTAssertFalse(completed)
        XCTAssertTrue(account.network.pending.isEmpty)
        XCTAssertEqual(stored(account)?.privacy?.base, 0)
        XCTAssertEqual(listed(account)?.privacy?.base, 0)
        XCTAssertTrue(account.stateManager.updates.isEmpty)
        operation.dispose()
    }
    let privacy = EngineStoryPrivacy(base: 3, additionallyIncludePeers: [42, 43])
    func install(_ account: Account, id: Int32 = 1, peerId: Int = 10, text: String = "original", listed: Bool = true) {
        let item = Stories.Item(id: id, text: text)
        let entry = CodableEntry(Stories.StoredItem.item(item))!
        account.postbox.storage.stories[.init(peerId: peerId, id: id)] = entry
        if listed { account.postbox.storage.lists[peerId, default: []].append(.init(value: entry, id: id, expirationTimestamp: item.expirationTimestamp, isCloseFriends: item.isCloseFriends, isLiveStream: item.isLiveStream)) }
    }
    func item(_ entry: CodableEntry?) -> Stories.Item? {
        guard let value = entry?.get(Stories.StoredItem.self), case let .item(item) = value else { return nil }
        return item
    }
    func stored(_ account: Account, id: Int32 = 1, peerId: Int = 10) -> Stories.Item? { item(account.postbox.storage.stories[.init(peerId: peerId, id: id)]) }
    func listed(_ account: Account, id: Int32 = 1, peerId: Int = 10) -> Stories.Item? { item(account.postbox.storage.lists[peerId]?.first(where: { $0.id == id })?.value) }
    func testNoMutationOrRequestBeforeSubscription() {
        let account = Account(); install(account)
        _ = _internal_editStoryPrivacy(account: account, id: 1, privacy: privacy)
        XCTAssertTrue(account.network.pending.isEmpty)
        XCTAssertEqual(stored(account)?.privacy?.base, 0)
    }
    func testCachesRemainUnchangedUntilAccepted() {
        let account = Account(); install(account)
        let operation = _internal_editStoryPrivacy(account: account, id: 1, privacy: privacy).start()
        XCTAssertEqual(stored(account)?.privacy?.base, 0)
        XCTAssertEqual(listed(account)?.privacy?.base, 0)
        XCTAssertEqual(account.network.pending[0].request.flags, 4)
        XCTAssertEqual(account.network.pending[0].request.privacy, privacy)
        operation.dispose()
    }
    func testFailureIsForwardedAndDoesNotChangeCaches() {
        let account = Account(); install(account)
        var failed = false; var completed = false
        let operation = _internal_editStoryPrivacy(account: account, id: 1, privacy: privacy).start(error: { _ in failed = true }, completed: { completed = true })
        account.network.pending[0].fail()
        XCTAssertTrue(failed); XCTAssertFalse(completed)
        XCTAssertEqual(stored(account)?.privacy?.base, 0)
        XCTAssertEqual(listed(account)?.privacy?.base, 0)
        XCTAssertTrue(account.stateManager.updates.isEmpty)
        operation.dispose()
    }
    func testSuccessCommitsBothCachesBeforeCompletion() {
        let account = Account(); install(account)
        let original = stored(account)!
        var completed = false
        let operation = _internal_editStoryPrivacy(account: account, id: 1, privacy: privacy).start(completed: {
            XCTAssertEqual(self.stored(account)?.privacy?.base, 3)
            XCTAssertEqual(self.listed(account)?.privacy?.additionallyIncludePeers, [42, 43])
            XCTAssertEqual(account.stateManager.updates, [1])
            completed = true
        })
        account.network.pending[0].succeed()
        var expected = original; expected.privacy = .init(base: 3, additionallyIncludePeers: [42, 43])
        XCTAssertEqual(stored(account), expected)
        XCTAssertEqual(listed(account), expected)
        XCTAssertTrue(completed)
        operation.dispose()
    }
    func testNotModifiedIsSuccessfulAndRepairsStaleLocalPrivacy() {
        let account = Account(); install(account)
        var completed = false; var failed = false
        let operation = _internal_editStoryPrivacy(account: account, id: 1, privacy: privacy).start(error: { _ in failed = true }, completed: { completed = true })
        account.network.pending[0].fail("STORY_NOT_MODIFIED")
        XCTAssertTrue(completed); XCTAssertFalse(failed)
        XCTAssertEqual(stored(account)?.privacy?.base, 3)
        XCTAssertTrue(account.stateManager.updates.isEmpty)
        operation.dispose()
    }
    func testCancelBeforeResponseDoesNotChangeCache() {
        let account = Account(); install(account)
        let operation = _internal_editStoryPrivacy(account: account, id: 1, privacy: privacy).start()
        operation.dispose(); account.network.pending[0].succeed()
        XCTAssertTrue(account.network.pending[0].cancelled)
        XCTAssertEqual(stored(account)?.privacy?.base, 0)
        XCTAssertEqual(listed(account)?.privacy?.base, 0)
    }
    func testCommitUsesLatestStoryFields() {
        let account = Account(); install(account)
        let operation = _internal_editStoryPrivacy(account: account, id: 1, privacy: privacy).start()
        account.postbox.storage.lists[10] = []
        install(account, text: "edited during request")
        account.network.pending[0].succeed()
        XCTAssertEqual(stored(account)?.text, "edited during request")
        XCTAssertEqual(listed(account)?.text, "edited during request")
        XCTAssertEqual(stored(account)?.privacy?.base, 3)
        XCTAssertEqual(listed(account)?.privacy?.base, 3)
        operation.dispose()
    }
    func testDeletedStoryIsNotResurrectedByCommit() {
        let account = Account(); install(account)
        let operation = _internal_editStoryPrivacy(account: account, id: 1, privacy: privacy).start()
        account.postbox.storage.stories = [:]; account.postbox.storage.lists = [:]
        account.network.pending[0].succeed()
        XCTAssertNil(stored(account)); XCTAssertNil(listed(account))
        XCTAssertEqual(account.stateManager.updates, [1])
        operation.dispose()
    }
    func testOnlyRequestedAccountStoryIsChanged() {
        let account = Account(); install(account); install(account, id: 2); install(account, peerId: 20)
        let operation = _internal_editStoryPrivacy(account: account, id: 1, privacy: privacy).start()
        account.network.pending[0].succeed()
        XCTAssertEqual(stored(account)?.privacy?.base, 3)
        XCTAssertEqual(stored(account, id: 2)?.privacy?.base, 0)
        XCTAssertEqual(stored(account, peerId: 20)?.privacy?.base, 0)
        XCTAssertEqual(listed(account, id: 2)?.privacy?.base, 0)
        operation.dispose()
    }
    func testDelayedCommitDefersCompletionAndCanBeCancelled() {
        let account = Account(); install(account)
        var completed = false
        let operation = _internal_editStoryPrivacy(account: account, id: 1, privacy: privacy).start(completed: { completed = true })
        account.postbox.delayNext = true
        account.network.pending[0].succeed()
        XCTAssertFalse(completed)
        XCTAssertNotNil(account.postbox.finish)
        XCTAssertEqual(stored(account)?.privacy?.base, 0)
        operation.dispose()
        XCTAssertNil(account.postbox.finish)
        XCTAssertTrue(account.stateManager.updates.isEmpty)
    }
}
