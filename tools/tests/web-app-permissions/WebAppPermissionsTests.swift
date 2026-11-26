import Foundation
import SwiftSignalKit
import XCTest

struct PeerId: Hashable { let raw: Int64; var id: PeerId { self }; func _internalGetInt64Value() -> Int64 { raw } }
enum EnginePeer { typealias Id = PeerId }
final class ValueBoxKey: Hashable {
    let length: Int; var value: Int64 = 0
    init(length: Int) { self.length = length }
    func setInt64(_ offset: Int, value: Int64) { precondition(offset == 0 && length == 8); self.value = value }
    static func == (a: ValueBoxKey, b: ValueBoxKey) -> Bool { a.length == b.length && a.value == b.value }
    func hash(into h: inout Hasher) { h.combine(length); h.combine(value) }
}
typealias EngineDataBuffer = ValueBoxKey
struct ItemCacheEntryId: Hashable { let collectionId: Int8; let key: ValueBoxKey }
enum ApplicationSpecificItemCacheCollectionId { static let webAppPermissionsState: Int8 = 12 }
struct CodableEntry {
    let data: Data
    init?<T: Encodable>(_ value: T) { guard let data = try? JSONEncoder().encode(value) else { return nil }; self.data = data }
    init(data: Data) { self.data = data }
    func get<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(type, from: data) }
}
final class Transaction {
    unowned let box: Postbox
    init(_ box: Postbox) { self.box = box }
    func retrieveItemCacheEntry(id: ItemCacheEntryId) -> CodableEntry? { box.entries[id] }
    func putItemCacheEntry(id: ItemCacheEntryId, entry: CodableEntry) { box.entries[id] = entry; box.writes += 1 }
    func removeItemCacheEntry(id: ItemCacheEntryId) { box.entries.removeValue(forKey: id); box.removals += 1 }
}
final class Postbox {
    var entries: [ItemCacheEntryId: CodableEntry] = [:]
    var queue: [() -> Void] = []
    var executed = 0; var writes = 0; var removals = 0
    var observers: [UUID: (ItemCacheEntryId, Subscriber<CodableEntry?, NoError>)] = [:]
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            self.queue.append {
                self.executed += 1
                let result = f(Transaction(self))
                for (id, observer) in Array(self.observers.values) { observer.putNext(self.entries[id]) }
                subscriber.putNext(result); subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }
    func runOne() { if !queue.isEmpty { queue.removeFirst()() } }
    func drain() { while !queue.isEmpty { runOne() } }
    func observe(_ id: ItemCacheEntryId) -> Signal<CodableEntry?, NoError> {
        Signal { subscriber in
            let token = UUID(); self.observers[token] = (id, subscriber); subscriber.putNext(self.entries[id])
            return ActionDisposable { self.observers.removeValue(forKey: token) }
        }
    }
}
final class Account { let postbox = Postbox() }
protocol AccountContextProtocol: AnyObject { var account: Account { get }; var engine: Engine { get } }
final class Context: AccountContextProtocol { let account = Account(); lazy var engine = Engine(account) }
enum TelegramEngine { enum EngineData { enum Item { enum ItemCache { struct Item { let collectionId: Int8; let id: EngineDataBuffer } } } } }
final class Engine {
    final class DataAPI {
        let box: Postbox; init(_ box: Postbox) { self.box = box }
        func get(_ item: TelegramEngine.EngineData.Item.ItemCache.Item) -> Signal<CodableEntry?, NoError> { box.transaction { $0.retrieveItemCacheEntry(id: .init(collectionId: item.collectionId, key: item.id)) } }
        func subscribe(_ item: TelegramEngine.EngineData.Item.ItemCache.Item) -> Signal<CodableEntry?, NoError> { box.observe(.init(collectionId: item.collectionId, key: item.id)) }
    }
    final class ItemCache {
        let box: Postbox; init(_ box: Postbox) { self.box = box }
        func put<T: Codable>(collectionId: Int8, id: EngineDataBuffer, item: T) -> Signal<Never, NoError> { box.transaction { tx in if let entry = CodableEntry(item) { tx.putItemCacheEntry(id: .init(collectionId: collectionId, key: id), entry: entry) } } |> ignoreValues }
        func remove(collectionId: Int8, id: EngineDataBuffer) -> Signal<Never, NoError> { box.transaction { $0.removeItemCacheEntry(id: .init(collectionId: collectionId, key: id)) } |> ignoreValues }
    }
    let data: DataAPI; let itemCache: ItemCache
    init(_ account: Account) { data = .init(account.postbox); itemCache = .init(account.postbox) }
}
__SOURCE__
final class Profile {
    let context: Context; let peerId: PeerId
    init(_ context: Context, _ id: PeerId) { self.context = context; peerId = id }
    __PROFILE__
}

final class WebAppPermissionsTests: XCTestCase {
    let id = PeerId(raw: 10)
    func key(_ id: PeerId) -> ItemCacheEntryId { let key = ValueBoxKey(length: 8); key.setInt64(0, value: id.raw); return .init(collectionId: ApplicationSpecificItemCacheCollectionId.webAppPermissionsState, key: key) }
    func state(_ c: Context, _ id: PeerId? = nil) -> WebAppPermissionsState? { c.account.postbox.entries[key(id ?? self.id)]?.get(WebAppPermissionsState.self) }
    func seed(_ c: Context, location: Bool? = nil, emoji: Bool? = nil) { c.account.postbox.entries[key(id)] = CodableEntry(WebAppPermissionsState(location: location.map { .init(isRequested: true, isAllowed: $0) }, emojiStatus: emoji.map { .init(isRequested: $0) })) }
    func location(_ c: Context, allowed: Bool, id: PeerId? = nil) -> Disposable { updateWebAppPermissionsStateInteractively(context: c, peerId: id ?? self.id) { .init(location: .init(isRequested: true, isAllowed: allowed), emojiStatus: $0?.emojiStatus) }.start() }
    func emoji(_ c: Context, requested: Bool) -> Disposable { updateWebAppPermissionsStateInteractively(context: c, peerId: id) { .init(location: $0?.location, emojiStatus: .init(isRequested: requested)) }.start() }
    func testConcurrentIndependentFieldsArePreservedInBothOrders() {
        for reverse in [false, true] {
            let c = Context(); let a: Disposable; let b: Disposable
            if reverse { a = emoji(c, requested: true); b = location(c, allowed: true) } else { a = location(c, allowed: true); b = emoji(c, requested: true) }
            c.account.postbox.drain(); XCTAssertEqual(state(c)?.location?.isAllowed, true); XCTAssertEqual(state(c)?.emojiStatus?.isRequested, true); a.dispose(); b.dispose()
        }
    }
    func testTwoRapidProfileTogglesUseLatestValue() { let c = Context(); seed(c, location: false, emoji: true); let p = Profile(c, id); p.togglePermissionsGeo(); p.togglePermissionsGeo(); c.account.postbox.drain(); XCTAssertEqual(state(c)?.location?.isAllowed, false); XCTAssertEqual(state(c)?.emojiStatus?.isRequested, true) }
    func testProfileTogglePreservesEmojiState() { let c = Context(); seed(c, location: false, emoji: true); Profile(c, id).togglePermissionsGeo(); c.account.postbox.drain(); XCTAssertEqual(state(c)?.location?.isAllowed, true); XCTAssertEqual(state(c)?.emojiStatus?.isRequested, true) }
    func testProfileToggleInitialPermissionRequestsAndAllows() { let c = Context(); Profile(c, id).togglePermissionsGeo(); c.account.postbox.drain(); XCTAssertEqual(state(c)?.location?.isRequested, true); XCTAssertEqual(state(c)?.location?.isAllowed, true) }
    func testProfileToggleAndGrantRemainOrdered() { let c = Context(); seed(c, location: false); let d = location(c, allowed: true); Profile(c, id).togglePermissionsGeo(); c.account.postbox.drain(); XCTAssertEqual(state(c)?.location?.isAllowed, false); d.dispose() }
    func testDeletionBeforeUnrelatedUpdateDoesNotResurrectLocation() { let c = Context(); seed(c, location: true); let a = updateWebAppPermissionsStateInteractively(context: c, peerId: id) { _ in nil }.start(); let b = emoji(c, requested: true); c.account.postbox.drain(); XCTAssertNil(state(c)?.location); XCTAssertEqual(state(c)?.emojiStatus?.isRequested, true); a.dispose(); b.dispose() }
    func testDeletionAfterUpdateRemovesEntry() { let c = Context(); let a = location(c, allowed: true); let b = updateWebAppPermissionsStateInteractively(context: c, peerId: id) { _ in nil }.start(); c.account.postbox.drain(); XCTAssertNil(state(c)); a.dispose(); b.dispose() }
    func testSeparateBotKeysDoNotInterfere() { let c = Context(); let other = PeerId(raw: 20); let a = location(c, allowed: true); let b = location(c, allowed: false, id: other); c.account.postbox.drain(); XCTAssertEqual(state(c)?.location?.isAllowed, true); XCTAssertEqual(state(c, other)?.location?.isAllowed, false); a.dispose(); b.dispose() }
    func testSeparateAccountsDoNotInterfere() { let a = Context(), b = Context(); let x = location(a, allowed: true); let y = location(b, allowed: false); a.account.postbox.drain(); b.account.postbox.drain(); XCTAssertEqual(state(a)?.location?.isAllowed, true); XCTAssertEqual(state(b)?.location?.isAllowed, false); x.dispose(); y.dispose() }
    func testCancelledQueuedUpdateDoesNotRunTransform() { let c = Context(); var calls = 0; let d = updateWebAppPermissionsStateInteractively(context: c, peerId: id) { _ in calls += 1; return .init(location: nil, emojiStatus: nil) }.start(); d.dispose(); c.account.postbox.drain(); XCTAssertEqual(c.account.postbox.executed, 1); XCTAssertEqual(calls, 0); XCTAssertEqual(c.account.postbox.writes, 0) }
    func testCancellationDuringTransformPreventsWrite() { let c = Context(); var d: Disposable?; d = updateWebAppPermissionsStateInteractively(context: c, peerId: id) { _ in d?.dispose(); return .init(location: .init(isRequested: true, isAllowed: true), emojiStatus: nil) }.start(); c.account.postbox.drain(); XCTAssertNil(state(c)); XCTAssertEqual(c.account.postbox.writes, 0) }
    func testCancellationAfterCommitDoesNotRollbackAcceptedChoice() { let c = Context(); let d = location(c, allowed: true); c.account.postbox.drain(); d.dispose(); XCTAssertEqual(state(c)?.location?.isAllowed, true) }
    func testCancelledSiblingDoesNotDiscardOtherUpdate() { let c = Context(); let a = location(c, allowed: true); let b = emoji(c, requested: true); a.dispose(); c.account.postbox.drain(); XCTAssertNil(state(c)?.location); XCTAssertEqual(state(c)?.emojiStatus?.isRequested, true); b.dispose() }
    func testCancellationCannotApplyAStillQueuedWrite() {
        let c = Context(); seed(c, location: false); let d = location(c, allowed: true)
        c.account.postbox.runOne(); let committedBeforeCancel = state(c)?.location?.isAllowed
        d.dispose(); c.account.postbox.drain(); XCTAssertEqual(state(c)?.location?.isAllowed, committedBeforeCancel)
    }
    func testCancellationCannotApplyAStillQueuedDeletion() {
        let c = Context(); seed(c, location: true)
        let d = updateWebAppPermissionsStateInteractively(context: c, peerId: id) { _ in nil }.start()
        c.account.postbox.runOne(); let committedBeforeCancel = state(c)?.location?.isAllowed
        d.dispose(); c.account.postbox.drain(); XCTAssertEqual(state(c)?.location?.isAllowed, committedBeforeCancel)
    }
    func testColdSignalDoesNotTouchStore() { let c = Context(); var calls = 0; let signal = updateWebAppPermissionsStateInteractively(context: c, peerId: id) { _ in calls += 1; return nil }; XCTAssertTrue(c.account.postbox.queue.isEmpty); XCTAssertEqual(calls, 0); withExtendedLifetime(signal) {} }
    func testResubscribingCancelledSignalUsesIndependentCancellation() { let c = Context(); let signal = updateWebAppPermissionsStateInteractively(context: c, peerId: id) { .init(location: .init(isRequested: true, isAllowed: !($0?.location?.isAllowed ?? false)), emojiStatus: $0?.emojiStatus) }; let a = signal.start(); a.dispose(); let b = signal.start(); c.account.postbox.drain(); XCTAssertEqual(state(c)?.location?.isAllowed, true); b.dispose() }
    func testSameSignalSubscriptionsReadLatestState() { let c = Context(); let signal = updateWebAppPermissionsStateInteractively(context: c, peerId: id) { .init(location: .init(isRequested: true, isAllowed: !($0?.location?.isAllowed ?? false)), emojiStatus: $0?.emojiStatus) }; let a = signal.start(), b = signal.start(); c.account.postbox.drain(); XCTAssertEqual(state(c)?.location?.isAllowed, false); a.dispose(); b.dispose() }
    func testCompletionOnlyAfterMutationWithNoValues() { let c = Context(); var completed = 0; let d = updateWebAppPermissionsStateInteractively(context: c, peerId: id) { _ in .init(location: .init(isRequested: true, isAllowed: true), emojiStatus: nil) }.start(completed: { completed += 1; XCTAssertEqual(self.state(c)?.location?.isAllowed, true) }); XCTAssertEqual(completed, 0); c.account.postbox.drain(); XCTAssertEqual(completed, 1); d.dispose() }
    func testCancelledUpdateDoesNotCompleteObserver() { let c = Context(); var completed = 0; let d = updateWebAppPermissionsStateInteractively(context: c, peerId: id) { _ in nil }.start(completed: { completed += 1 }); d.dispose(); c.account.postbox.drain(); XCTAssertEqual(completed, 0) }
    func testCompletionCanStartAnotherMutation() { let c = Context(); var next: Disposable?; let d = updateWebAppPermissionsStateInteractively(context: c, peerId: id) { _ in .init(location: .init(isRequested: true, isAllowed: true), emojiStatus: nil) }.start(completed: { next = self.emoji(c, requested: true) }); c.account.postbox.drain(); XCTAssertEqual(state(c)?.location?.isAllowed, true); XCTAssertEqual(state(c)?.emojiStatus?.isRequested, true); d.dispose(); next?.dispose() }
    func testObserverSeesBothFieldsAtTransactionBoundary() { let c = Context(); var observed: [WebAppPermissionsState?] = []; let reader = webAppPermissionsState(context: c, peerId: id).start(next: { observed.append($0) }); let d = updateWebAppPermissionsStateInteractively(context: c, peerId: id) { _ in .init(location: .init(isRequested: true, isAllowed: true), emojiStatus: .init(isRequested: true)) }.start(); c.account.postbox.drain(); XCTAssertEqual(observed.last??.location?.isAllowed, true); XCTAssertEqual(observed.last??.emojiStatus?.isRequested, true); reader.dispose(); d.dispose(); XCTAssertTrue(c.account.postbox.observers.isEmpty) }
    func testCorruptEntryCanBeReplacedWithoutCrashing() { let c = Context(); c.account.postbox.entries[key(id)] = .init(data: Data("invalid".utf8)); let d = location(c, allowed: true); c.account.postbox.drain(); XCTAssertEqual(state(c)?.location?.isAllowed, true); d.dispose() }
    func testLegacyKeyAndOptionalPayloadRemainReadable() { let c = Context(); let big = PeerId(raw: 9_000_000_000); c.account.postbox.entries[key(big)] = .init(data: Data("{\"location\":{\"isRequested\":true,\"isAllowed\":false}}".utf8)); var observed: WebAppPermissionsState?; let r = webAppPermissionsState(context: c, peerId: big).start(next: { observed = $0 }); XCTAssertEqual(observed?.location?.isAllowed, false); let d = location(c, allowed: true, id: big); c.account.postbox.drain(); XCTAssertEqual(observed?.location?.isAllowed, true); XCTAssertNil(observed?.emojiStatus); XCTAssertEqual(c.account.postbox.entries.count, 1); r.dispose(); d.dispose() }
    func testSignalDoesNotRetainAccountContext() { var c: Context? = Context(); weak var weakContext = c; let box = c!.account.postbox; let signal = updateWebAppPermissionsStateInteractively(context: c!, peerId: id) { _ in nil }; c = nil; XCTAssertNil(weakContext); let d = signal.start(); box.drain(); d.dispose() }
    func testQueuedUpdateDoesNotRetainAccountContext() { var c: Context? = Context(); weak var weakContext = c; let box = c!.account.postbox; let d = location(c!, allowed: true); c = nil; XCTAssertNil(weakContext); box.drain(); d.dispose() }
}
