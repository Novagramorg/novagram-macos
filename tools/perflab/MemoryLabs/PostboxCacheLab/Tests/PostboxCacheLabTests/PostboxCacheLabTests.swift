import XCTest
import Foundation
import SwiftSignalKit
@testable import Postbox

final class LabPeer: Peer {
    static let register: Void = {
        declareEncodable(LabPeer.self, f: { LabPeer(decoder: $0) })
        declareEncodable(LabCachedData.self, f: { LabCachedData(decoder: $0) })
    }()
    let id: PeerId
    let firstName: String
    let lastName: String
    let username: String
    let photo: [String]
    init(id: PeerId, firstName: String, lastName: String, username: String, photo: [String]) {
        self.id = id; self.firstName = firstName; self.lastName = lastName; self.username = username; self.photo = photo
    }
    init(decoder: PostboxDecoder) {
        self.id = PeerId(decoder.decodeInt64ForKey("i", orElse: 0))
        self.firstName = decoder.decodeStringForKey("f", orElse: "")
        self.lastName = decoder.decodeStringForKey("l", orElse: "")
        self.username = decoder.decodeStringForKey("u", orElse: "")
        self.photo = decoder.decodeStringArrayForKey("p")
    }
    func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.id.toInt64(), forKey: "i")
        encoder.encodeString(self.firstName, forKey: "f")
        encoder.encodeString(self.lastName, forKey: "l")
        encoder.encodeString(self.username, forKey: "u")
        encoder.encodeStringArray(self.photo, forKey: "p")
    }
    var indexName: PeerIndexNameRepresentation { return .personName(first: firstName, last: lastName, addressNames: [username], phoneNumber: nil) }
    var notificationSettingsPeerId: PeerId? { return nil }
    var associatedMediaIds: [MediaId]? { return nil }
    var timeoutAttribute: UInt32? { return nil }
    var associatedPeerId: PeerId? { return nil }
    var associatedPeerOverridesIdentity: Bool { return false }
    func isEqual(_ other: Peer) -> Bool { return (other as? LabPeer)?.id == self.id && (other as? LabPeer)?.username == self.username }
}

final class LabCachedData: CachedPeerData {
    let about: String
    let peerIds: Set<PeerId> = []
    let messageIds: Set<MessageId> = []
    let associatedHistoryMessageId: MessageId? = nil
    init(about: String) { self.about = about }
    init(decoder: PostboxDecoder) { self.about = decoder.decodeStringForKey("a", orElse: "") }
    func encode(_ encoder: PostboxEncoder) { encoder.encodeString(self.about, forKey: "a") }
    func isEqual(to other: CachedPeerData) -> Bool { return (other as? LabCachedData)?.about == self.about }
}

private func seed() -> SeedConfiguration {
    return SeedConfiguration(globalMessageIdsPeerIdNamespaces: [], initializeChatListWithHole: (topLevel: nil, groups: nil), messageHoles: [:], upgradedMessageHoles: [:], messageThreadHoles: { _, _ in nil }, existingMessageTags: [], messageTagsWithSummary: [], messageTagsWithThreadSummary: [], existingGlobalMessageTags: [], peerNamespacesRequiringMessageTextIndex: [], peerSummaryCounterTags: { _, _ in PeerSummaryCounterTags() }, peerSummaryIsThreadBased: { _, _ in (false, false) }, additionalChatListIndexNamespace: nil, messageNamespacesRequiringGroupStatsValidation: [], defaultMessageNamespaceReadStates: [:], chatMessagesNamespaces: [0], getGlobalNotificationSettings: { _ in nil }, defaultGlobalNotificationSettings: PostboxGlobalNotificationSettings(defaultIncludePeer: { _ in true }), mergeMessageAttributes: { _, _ in }, decodeMessageThreadInfo: { _ in nil }, decodeAutoremoveTimeout: { _ in nil }, decodeDisplayPeerAsRegularChat: { _ in false }, isPeerUpgradeMessage: { _ in false }, automaticThreadIndexInfo: { _, _ in nil }, customTagsFromAttributes: { _ in [] }, displaySavedMessagesAsTopicListPreferencesKey: ValueBoxKey(length: 0))
}

final class PostboxCacheLabTests: XCTestCase {
    private func heapInUse() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return stats.size_in_use
    }

    func testClearCachesFreesPeerCacheAndKeepsData() {
        let _ = LabPeer.register
        let queue = Queue(name: "lab")
        let basePath = NSTemporaryDirectory() + "postbox-lab-" + UUID().uuidString
        var valueBox: SqliteValueBox?
        queue.sync {
            valueBox = SqliteValueBox(basePath: basePath + "/db", queue: queue, isTemporary: true, isReadOnly: false, useCaches: true, removeDatabaseOnError: true, encryptionParameters: nil, upgradeProgress: { _ in }, inMemory: false)
        }
        var postbox: Postbox? = Postbox(queue: queue, basePath: basePath, seedConfiguration: seed(), valueBox: valueBox!, timestampForAbsoluteTimeBasedOperations: Int32(Date().timeIntervalSince1970), isMainProcess: true, isTemporary: true, tempDir: nil, useCaches: true)

        func run<T>(_ f: @escaping (Transaction) -> T) -> T {
            let semaphore = DispatchSemaphore(value: 0)
            var result: T!
            let disposable = postbox!.transaction(f).start(next: { result = $0; semaphore.signal() })
            _ = semaphore.wait(timeout: .now() + 120)
            disposable.dispose()
            return result
        }

        let count = 20000
        let ids = (1 ... count).map { PeerId(namespace: PeerId.Namespace._internalFromInt32Value(0), id: PeerId.Id._internalFromInt64Value(Int64($0))) }
        run { transaction -> Void in
            transaction.updatePeersInternal(ids.map { id in
                let n = id.id._internalGetInt64Value()
                return LabPeer(id: id, firstName: "First\(n) Name", lastName: "Last\(n) Surname", username: "user_\(n)_name", photo: ["photo-small-\(n)-a1b2c3d4e5f6", "photo-big-\(n)-a1b2c3d4e5f6", "stripped-\(n)"])
            }, update: { _, updated in updated })
            transaction.updatePeerCachedData(peerIds: Set(ids.prefix(2000)), update: { id, _ in LabCachedData(about: String(repeating: "about \(id.id._internalGetInt64Value()) ", count: 20)) })
        }
        postbox!.clearCaches()
        _ = run { _ in 0 }

        let empty = heapInUse()
        var t = CFAbsoluteTimeGetCurrent()
        let firstRead = run { transaction -> Int in
            var found = 0
            for id in ids where transaction.getPeer(id) != nil { found += 1 }
            for id in ids.prefix(2000) where transaction.getPeerCachedData(peerId: id) != nil { found += 1 }
            return found
        }
        let coldMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
        let filled = heapInUse()

        t = CFAbsoluteTimeGetCurrent()
        _ = run { transaction -> Int in
            var found = 0
            for id in ids where transaction.getPeer(id) != nil { found += 1 }
            return found
        }
        let warmMs = (CFAbsoluteTimeGetCurrent() - t) * 1000

        postbox!.clearCaches()
        _ = run { _ in 0 }
        let cleared = heapInUse()
        let afterClear = run { transaction -> (Int, String?) in
            var found = 0
            for id in ids where transaction.getPeer(id) != nil { found += 1 }
            return (found, (transaction.getPeer(ids[123]) as? LabPeer)?.username)
        }

        print("postbox cache lab: \(count) peers + 2000 cached datas hold \((filled - empty) / 1024) KB (\((filled - empty) / (count + 2000)) B each); clearCaches freed \((filled - cleared) / 1024) KB; cold read \(Int(coldMs)) ms (\(String(format: "%.1f", coldMs * 1000 / Double(count + 2000))) us each), warm read \(Int(warmMs)) ms")
        XCTAssertEqual(firstRead, count + 2000)
        XCTAssertEqual(afterClear.0, count)
        XCTAssertEqual(afterClear.1, "user_124_name")
        XCTAssertGreaterThan(filled - cleared, (filled - empty) * 8 / 10)

        postbox = nil
        queue.sync { valueBox = nil }
        try? FileManager.default.removeItem(atPath: basePath)
    }
}
