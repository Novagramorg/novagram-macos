private struct PeerId: Hashable {
    struct Namespace: Hashable {
        let value: Int32
        func _internalGetInt32Value() -> Int32 { value }
    }
    struct Id: Hashable {
        let value: Int64
        func _internalGetInt64Value() -> Int64 { value }
    }
    let namespace: Namespace
    let id: Id
    init(namespace: Int32 = 0, id: Int64) {
        self.namespace = Namespace(value: namespace)
        self.id = Id(value: id)
    }
}

private class Peer {
    let id: PeerId
    init(_ id: PeerId) { self.id = id }
}

private final class TelegramFilterCategory: Peer {
    init(category: ChatListFilterPeerCategories) {
        super.init(PeerId(namespace: ChatListFilterPeerCategories.Namespace, id: Int64(category.rawValue)))
    }
}

private final class TelegramChannel: Peer {
    enum Info { case group, broadcast }
    let info: Info
    init(_ id: PeerId, info: Info) { self.info = info; super.init(id) }
}

private struct CachedChannelData {
    struct Summary { let memberCount: Int32? }
    let participantsSummary: Summary
}

private struct SelectivePrivacyPeer {
    let peer: Peer
    let participantCount: Int32?
    init(peer: Peer, participantCount: Int32? = nil) {
        self.peer = peer
        self.participantCount = participantCount
    }
}

private struct PrivacyState {
    var enableForPremium = false
    var enableForBots = false
    var enableFor: [PeerId: SelectivePrivacyPeer] = [:]
    var disableFor: [PeerId: SelectivePrivacyPeer] = [:]
}

private final class Transaction {
    var peers: [PeerId: Peer] = [:]
    var cached: [PeerId: CachedChannelData] = [:]
    func getPeer(_ id: PeerId) -> Peer? { peers[id] }
    func getPeerCachedData(peerId: PeerId) -> Any? { cached[peerId] }
}

final class PrivacyExceptionsRegressionTests: XCTestCase {
    private func category(_ value: ChatListFilterPeerCategories) -> SelectivePrivacyPeer {
        SelectivePrivacyPeer(peer: TelegramFilterCategory(category: value))
    }

    func testPremiumCategoryDoesNotEnableBots() {
        let premium = category(.premiumUsers)
        var state = PrivacyState()
        applySettings([premium.peer.id: premium], current: &state)
        XCTAssertTrue(state.enableForPremium)
        XCTAssertFalse(state.enableForBots)
        XCTAssertTrue(state.enableFor.isEmpty)
    }

    func testBotsCategoryDoesNotEnablePremium() {
        let bots = category(.miniApps)
        var state = PrivacyState()
        applySettings([bots.peer.id: bots], current: &state)
        XCTAssertFalse(state.enableForPremium)
        XCTAssertTrue(state.enableForBots)
        XCTAssertTrue(state.enableFor.isEmpty)
    }

    func testOtherCategoriesDoNotEnableEitherException() {
        let other = category(.groups)
        var state = PrivacyState()
        applySettings([other.peer.id: other], current: &state)
        XCTAssertFalse(state.enableForPremium)
        XCTAssertFalse(state.enableForBots)
        XCTAssertTrue(state.enableFor.isEmpty)
    }

    func testRealPeersClearCategoriesAndResolveConflictingExceptions() {
        let peer = SelectivePrivacyPeer(peer: Peer(PeerId(id: 42)))
        let other = SelectivePrivacyPeer(peer: Peer(PeerId(id: 43)))
        var state = PrivacyState(enableForPremium: true, enableForBots: true, disableFor: [peer.peer.id: peer, other.peer.id: other])
        applySettings([peer.peer.id: peer], current: &state)
        XCTAssertFalse(state.enableForPremium)
        XCTAssertFalse(state.enableForBots)
        XCTAssertEqual(Set(state.enableFor.keys), [peer.peer.id])
        XCTAssertEqual(Set(state.disableFor.keys), [other.peer.id])
    }

    func testPickerDeselectsPeersAndPreservesSelectedExistingData() {
        let first = SelectivePrivacyPeer(peer: Peer(PeerId(id: 1)), participantCount: 20)
        let second = SelectivePrivacyPeer(peer: Peer(PeerId(id: 2)))
        let result = applyPeers([first.peer.id], peers: [first, second], transaction: Transaction())
        XCTAssertEqual(result.map { $0.peer.id }, [first.peer.id])
        XCTAssertEqual(result.first?.participantCount, 20)
    }

    func testPickerKeepsExistingCategoryExactlyOnce() {
        let premium = category(.premiumUsers)
        let result = applyPeers([premium.peer.id], peers: [premium], transaction: Transaction())
        XCTAssertEqual(result.map { $0.peer.id }, [premium.peer.id])
    }

    func testPickerCanRemoveAllExceptions() {
        let premium = category(.premiumUsers)
        let peer = SelectivePrivacyPeer(peer: Peer(PeerId(id: 1)))
        let result = applyPeers([], peers: [premium, peer], transaction: Transaction())
        XCTAssertTrue(result.isEmpty)
    }

    func testPickerAddsUniqueGroupsWithCachedMemberCounts() {
        let group = TelegramChannel(PeerId(namespace: 2, id: 10), info: .group)
        let bots = category(.miniApps)
        let transaction = Transaction()
        transaction.peers[group.id] = group
        transaction.cached[group.id] = CachedChannelData(participantsSummary: .init(memberCount: 100))
        let result = applyPeers([group.id, group.id, bots.peer.id, bots.peer.id], peers: [], transaction: transaction)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map { $0.peer.id }), [group.id, bots.peer.id])
        XCTAssertEqual(result.first(where: { $0.peer.id == group.id })?.participantCount, 100)
    }
}
