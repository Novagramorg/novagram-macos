import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext

public struct NovagramForeignPeerHit: Equatable {
    public let accountId: AccountRecordId
    public let account: Account
    public let accountPeer: Peer
    public let peer: Peer

    public static func == (lhs: NovagramForeignPeerHit, rhs: NovagramForeignPeerHit) -> Bool {
        return lhs.accountId == rhs.accountId
            && lhs.account === rhs.account
            && lhs.peer.isEqual(rhs.peer)
            && lhs.accountPeer.isEqual(rhs.accountPeer)
    }
}

private final class NovagramCrossAccountLastHits {
    private let lock = NSLock()
    private var hitsByAccount: [AccountRecordId: [NovagramForeignPeerHit]] = [:]

    func get(_ accountId: AccountRecordId) -> [NovagramForeignPeerHit] {
        lock.lock()
        defer { lock.unlock() }
        return hitsByAccount[accountId] ?? []
    }

    func set(_ hits: [NovagramForeignPeerHit], for accountId: AccountRecordId) {
        lock.lock()
        defer { lock.unlock() }
        hitsByAccount[accountId] = hits
    }
}

public enum NovagramCrossAccountSearch {
    public static let defaultsKey = "novagram_search_all_accounts"
    public static let minQueryLength = 2

    private static let suiteName = "pro_messager"
    private static let debounceSeconds: Double = 0.25
    private static let maxAccounts = 30
    private static let maxHitsPerAccount = 3
    private static let maxHits = 15
    private static let lastHits = NovagramCrossAccountLastHits()

    public static var isEnabled: Bool {
        get {
            return UserDefaults(suiteName: suiteName)?.object(forKey: defaultsKey) as? Bool ?? true
        }
        set {
            UserDefaults(suiteName: suiteName)?.set(newValue, forKey: defaultsKey)
        }
    }

    public static func peers(
        sharedContext: any SharedAccountContextProtocol,
        currentAccountId: AccountRecordId,
        query: String
    ) -> Signal<[NovagramForeignPeerHit], NoError> {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, query.count >= minQueryLength else {
            return empty(currentAccountId: currentAccountId)
        }
        let search: Signal<[NovagramForeignPeerHit], NoError> = sharedContext.activeAccountsWithInfo
            |> take(1)
            |> mapToSignal { _, accounts -> Signal<[NovagramForeignPeerHit], NoError> in
                let others = Array(accounts.filter { $0.account.id != currentAccountId }.prefix(maxAccounts))
                if others.isEmpty {
                    return .single([])
                }
                return combineLatest(others.map { hits(in: $0, query: query) }) |> map(merged)
            }
        let debounced: Signal<[NovagramForeignPeerHit], NoError> = Signal<Void, NoError>.single(Void())
            |> delay(debounceSeconds, queue: .concurrentDefaultQueue())
            |> mapToSignal { _ in search }
            |> beforeNext { hits in lastHits.set(hits, for: currentAccountId) }
        return .single(lastHits.get(currentAccountId)) |> then(debounced)
    }

    public static func empty(currentAccountId: AccountRecordId) -> Signal<[NovagramForeignPeerHit], NoError> {
        lastHits.set([], for: currentAccountId)
        return .single([])
    }

    private static func hits(in info: AccountWithInfo, query: String) -> Signal<[NovagramForeignPeerHit], NoError> {
        let account = info.account
        let accountPeer = info.peer
        return TelegramEngine(account: account).contacts.searchLocalPeers(query: query)
            |> take(1)
            |> map { rendered -> [NovagramForeignPeerHit] in
                let privacy = NovagramSearchPrivacyPass()
                var result: [NovagramForeignPeerHit] = []
                for item in rendered where result.count < maxHitsPerAccount {
                    let allowed = isAllowed(item.peerId, account: account, privacy: privacy)
                    guard let peer = item.peer?._asPeer(), allowed else {
                        continue
                    }
                    if let main = item.chatMainPeer, main.id != item.peerId, isPrivate(main.id, privacy: privacy) {
                        continue
                    }
                    result.append(NovagramForeignPeerHit(
                        accountId: account.id,
                        account: account,
                        accountPeer: accountPeer,
                        peer: peer
                    ))
                }
                return result
            }
    }

    private static func isPrivate(_ peerId: PeerId, privacy: NovagramSearchPrivacyPass) -> Bool {
        if NovagramHiddenChatsManager.shared.isPeerHiddenInStorage(peerId) {
            return true
        }
        return privacy.isLocked(peerId)
    }

    private static func isAllowed(_ peerId: PeerId, account: Account, privacy: NovagramSearchPrivacyPass) -> Bool {
        if peerId == account.peerId || peerId.namespace == Namespaces.Peer.SecretChat {
            return false
        }
        return !isPrivate(peerId, privacy: privacy)
    }

    private static func merged(_ perAccount: [[NovagramForeignPeerHit]]) -> [NovagramForeignPeerHit] {
        var seen = Set<PeerId>()
        var result: [NovagramForeignPeerHit] = []
        for hit in perAccount.joined() where result.count < maxHits {
            if seen.insert(hit.peer.id).inserted {
                result.append(hit)
            }
        }
        return result
    }
}
