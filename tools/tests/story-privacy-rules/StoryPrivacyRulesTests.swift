import XCTest

struct PeerId: Hashable {
    struct Id: Hashable {
        let value: Int64
        func _internalGetInt64Value() -> Int64 { value }
        static func _internalFromInt64Value(_ value: Int64) -> Id { .init(value: value) }
    }
    let namespace: Int
    let id: Id
}
enum Namespaces {
    enum Peer {
        static let CloudUser = 0
        static let CloudGroup = 1
        static let CloudChannel = 2
    }
}
enum EnginePeer { typealias Id = PeerId }
enum Stories {
    enum Item {
        struct Privacy: Equatable {
            enum Base: CaseIterable { case everyone, contacts, closeFriends, nobody }
            let base: Base
            let additionallyIncludePeers: [PeerId]
        }
    }
}
typealias EngineStoryPrivacy = Stories.Item.Privacy
protocol Peer { var id: PeerId { get } }
struct Hash { let value: Int64 }
struct TelegramUser: Peer { let id: PeerId; let accessHash: Hash? }
struct TelegramGroup: Peer { let id: PeerId }
struct TelegramChannel: Peer {
    enum Info { case group, broadcast }
    let id: PeerId
    let info: Info
}
struct UnsupportedPeer: Peer { let id: PeerId }
final class Transaction {
    var peers: [PeerId: Peer] = [:]
    var lookups: [PeerId] = []
    func getPeer(_ id: PeerId) -> Peer? { lookups.append(id); return peers[id] }
}
enum Api {
    struct InputUserData: Equatable { let userId: Int64; let accessHash: Int64 }
    enum InputUser: Equatable { case inputUserSelf, inputUser(InputUserData) }
    struct InputUsers: Equatable { let users: [InputUser] }
    struct Chats: Equatable { let chats: [Int64] }
    struct Users: Equatable { let users: [Int64] }
    enum InputPrivacyRule: Equatable {
        case inputPrivacyValueAllowAll, inputPrivacyValueAllowContacts, inputPrivacyValueAllowCloseFriends
        case inputPrivacyValueAllowUsers(InputUsers), inputPrivacyValueDisallowUsers(InputUsers)
        case inputPrivacyValueAllowChatParticipants(Chats), inputPrivacyValueDisallowChatParticipants(Chats)
    }
    enum PrivacyRule {
        case privacyValueAllowAll, privacyValueAllowContacts, privacyValueAllowCloseFriends
        case privacyValueAllowPremium, privacyValueDisallowAll, other
        case privacyValueAllowUsers(Users), privacyValueDisallowUsers(Users)
        case privacyValueAllowChatParticipants(Chats), privacyValueDisallowChatParticipants(Chats)
    }
}
__SOURCE__

final class StoryPrivacyRulesTests: XCTestCase {
    func id(_ value: Int64, _ namespace: Int = Namespaces.Peer.CloudUser) -> PeerId { .init(namespace: namespace, id: .init(value: value)) }
    func transaction() -> Transaction {
        let result = Transaction()
        result.peers[id(1)] = TelegramUser(id: id(1), accessHash: .init(value: 101))
        result.peers[id(2)] = TelegramUser(id: id(2), accessHash: .init(value: 102))
        result.peers[id(3, 1)] = TelegramGroup(id: id(3, 1))
        result.peers[id(4, 2)] = TelegramChannel(id: id(4, 2), info: .group)
        return result
    }
    func user(_ value: Int64) -> Api.InputUser { .inputUser(.init(userId: value, accessHash: value + 100)) }
    func rules(_ base: Stories.Item.Privacy.Base, _ peers: [PeerId], _ transaction: Transaction? = nil) -> [Api.InputPrivacyRule]? {
        apiInputPrivacyRules(privacy: .init(base: base, additionallyIncludePeers: peers), transaction: transaction ?? self.transaction())
    }
    func testEveryoneExceptionsPrecedeBase() {
        XCTAssertEqual(rules(.everyone, [id(1), id(2)]), [.inputPrivacyValueDisallowUsers(.init(users: [user(1), user(2)])), .inputPrivacyValueAllowAll])
    }
    func testContactExceptionsPrecedeBase() {
        XCTAssertEqual(rules(.contacts, [id(2)]), [.inputPrivacyValueDisallowUsers(.init(users: [user(2)])), .inputPrivacyValueAllowContacts])
    }
    func testEveryoneExcludesBothGroupKinds() {
        XCTAssertEqual(rules(.everyone, [id(3, 1), id(4, 2)]), [.inputPrivacyValueDisallowChatParticipants(.init(chats: [3, 4])), .inputPrivacyValueAllowAll])
    }
    func testContactsExcludeUsersAndGroups() {
        XCTAssertEqual(rules(.contacts, [id(4, 2), id(1)]), [.inputPrivacyValueDisallowUsers(.init(users: [user(1)])), .inputPrivacyValueDisallowChatParticipants(.init(chats: [4])), .inputPrivacyValueAllowContacts])
    }
    func testSelectedAudienceIncludesUsersAndGroups() {
        XCTAssertEqual(rules(.nobody, [id(1), id(3, 1), id(4, 2)]), [.inputPrivacyValueAllowUsers(.init(users: [user(1)])), .inputPrivacyValueAllowChatParticipants(.init(chats: [3, 4]))])
    }
    func testEmptySelectedAudienceKeepsSelfOnly() {
        XCTAssertEqual(rules(.nobody, []), [.inputPrivacyValueAllowUsers(.init(users: [.inputUserSelf]))])
    }
    func testEmptyBases() {
        XCTAssertEqual(rules(.everyone, []), [.inputPrivacyValueAllowAll])
        XCTAssertEqual(rules(.contacts, []), [.inputPrivacyValueAllowContacts])
        XCTAssertEqual(rules(.closeFriends, []), [.inputPrivacyValueAllowCloseFriends])
    }
    func testExistingCloseFriendAdditionsRemainAllowed() {
        XCTAssertEqual(rules(.closeFriends, [id(1), id(4, 2)]), [.inputPrivacyValueAllowUsers(.init(users: [user(1)])), .inputPrivacyValueAllowChatParticipants(.init(chats: [4])), .inputPrivacyValueAllowCloseFriends])
    }
    func testDuplicateIdsPreserveFirstOccurrenceOrder() {
        let transaction = transaction()
        XCTAssertEqual(rules(.nobody, [id(2), id(4, 2), id(1), id(2), id(3, 1), id(4, 2)], transaction), [.inputPrivacyValueAllowUsers(.init(users: [user(2), user(1)])), .inputPrivacyValueAllowChatParticipants(.init(chats: [4, 3]))])
        XCTAssertEqual(transaction.lookups, [id(2), id(4, 2), id(1), id(3, 1)])
    }
    func testMissingPeerRejectsEntireAudienceForEveryBase() {
        for base in Stories.Item.Privacy.Base.allCases {
            XCTAssertNil(rules(base, [id(1), id(99)]))
        }
    }
    func testMissingAccessHashRejectsEntireAudienceForEveryBase() {
        let transaction = transaction()
        transaction.peers[id(2)] = TelegramUser(id: id(2), accessHash: nil)
        for base in Stories.Item.Privacy.Base.allCases {
            XCTAssertNil(rules(base, [id(1), id(2)], transaction))
        }
    }
    func testUnsupportedPeerRejectsEntireAudience() {
        let transaction = transaction()
        transaction.peers[id(5, 3)] = UnsupportedPeer(id: id(5, 3))
        XCTAssertNil(rules(.everyone, [id(1), id(5, 3)], transaction))
        XCTAssertNil(rules(.nobody, [id(5, 3)], transaction))
    }
    func testBroadcastChannelCannotBecomeGroupRule() {
        let transaction = transaction()
        transaction.peers[id(4, 2)] = TelegramChannel(id: id(4, 2), info: .broadcast)
        XCTAssertNil(rules(.contacts, [id(1), id(4, 2)], transaction))
        XCTAssertNil(rules(.nobody, [id(4, 2)], transaction))
    }
    func testServerGroupExclusionsRoundTripEveryone() {
        let transaction = transaction()
        let parsed = parsePrivacy([.privacyValueDisallowUsers(.init(users: [1])), .privacyValueDisallowChatParticipants(.init(chats: [3, 4])), .privacyValueAllowAll], transaction: transaction)
        XCTAssertEqual(parsed, .init(base: .everyone, additionallyIncludePeers: [id(1), id(3, 1), id(4, 2)]))
        XCTAssertEqual(parsed.flatMap { apiInputPrivacyRules(privacy: $0, transaction: transaction) }, [.inputPrivacyValueDisallowUsers(.init(users: [user(1)])), .inputPrivacyValueDisallowChatParticipants(.init(chats: [3, 4])), .inputPrivacyValueAllowAll])
    }
    func testServerGroupExclusionsRoundTripContacts() {
        let transaction = transaction()
        let parsed = parsePrivacy([.privacyValueDisallowChatParticipants(.init(chats: [4])), .privacyValueAllowContacts], transaction: transaction)
        XCTAssertEqual(parsed, .init(base: .contacts, additionallyIncludePeers: [id(4, 2)]))
        XCTAssertEqual(parsed.flatMap { apiInputPrivacyRules(privacy: $0, transaction: transaction) }, [.inputPrivacyValueDisallowChatParticipants(.init(chats: [4])), .inputPrivacyValueAllowContacts])
    }
    func testServerGroupInclusionsRoundTripSelectedAudience() {
        let transaction = transaction()
        let parsed = parsePrivacy([.privacyValueAllowUsers(.init(users: [2])), .privacyValueAllowChatParticipants(.init(chats: [3, 4]))], transaction: transaction)
        XCTAssertEqual(parsed, .init(base: .nobody, additionallyIncludePeers: [id(2), id(3, 1), id(4, 2)]))
        XCTAssertEqual(parsed.flatMap { apiInputPrivacyRules(privacy: $0, transaction: transaction) }, [.inputPrivacyValueAllowUsers(.init(users: [user(2)])), .inputPrivacyValueAllowChatParticipants(.init(chats: [3, 4]))])
    }
    func testAbsentServerPrivacyRemainsAbsent() {
        XCTAssertNil(parsePrivacy(nil, transaction: transaction()))
    }
}
