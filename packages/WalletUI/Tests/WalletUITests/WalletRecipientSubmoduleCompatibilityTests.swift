import XCTest
import Cocoa
import WalletContext
import TelegramCore
import Postbox
@testable import WalletUI

private func submodulePeerSelectionIsEligiblePeer(_ peer: EnginePeer, accountPeerId: EnginePeer.Id) -> Bool {
    guard case let .user(user) = peer else {
        return false
    }
    return user.isGenericUser && !peer.isService && peer.id != accountPeerId
}

private func submodulePeerSelectionIsAddressQuery(_ query: String) -> Bool {
    if query.lowercased().hasPrefix("ton://") {
        return true
    }
    if let separator = query.firstIndex(of: ":"), Int(query[..<separator]) != nil {
        return true
    }
    guard !query.hasPrefix("@"), !query.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else {
        return false
    }
    return query.count == 48 || (query.count > 32 && ["EQ", "UQ", "kQ", "0Q", "Ef", "Uf", "kf", "0f"].contains(where: query.hasPrefix))
}

private struct SubmodulePeerSelectionSearch {
    var query = ""
    var localSearchQuery: String?
    var localSearchPeers: [EnginePeer] = []
    var remoteLocalSearchPeers: [EnginePeer] = []
    var globalSearchPeers: [EnginePeer] = []
    var isSearchingLocalPeers = false
    var isSearchingRemotePeers = false
    var isResolvingRecipient = false
    var recipient: WalletContext.ResolvedTransferRecipient?

    var isSearching: Bool {
        return self.isSearchingLocalPeers || self.isSearchingRemotePeers || self.isResolvingRecipient
    }

    mutating func resetQuery(keepPeerResults: Bool = false) {
        if !keepPeerResults {
            self.localSearchQuery = nil
            self.localSearchPeers = []
            self.remoteLocalSearchPeers = []
            self.globalSearchPeers = []
        }
        self.isSearchingLocalPeers = false
        self.isSearchingRemotePeers = false
        self.isResolvingRecipient = false
        self.query = ""
        self.recipient = nil
    }

    mutating func updateQuery(_ value: String) {
        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.query != query else {
            return
        }
        self.resetQuery(keepPeerResults: !self.query.isEmpty && !query.isEmpty)
        self.query = query
        self.isSearchingLocalPeers = !query.isEmpty
        self.isSearchingRemotePeers = !query.isEmpty
        self.isResolvingRecipient = !query.isEmpty
    }

    mutating func localSearchCompleted(_ peers: [EnginePeer], query: String) {
        guard self.query == query else {
            return
        }
        self.localSearchQuery = query
        self.localSearchPeers = peers
        self.isSearchingLocalPeers = false
    }

    mutating func remoteSearchCompleted(local: [EnginePeer], global: [EnginePeer], query: String) {
        guard self.query == query else {
            return
        }
        self.remoteLocalSearchPeers = local
        self.globalSearchPeers = global
        self.isSearchingRemotePeers = false
    }

    mutating func resolveCompleted(_ recipient: WalletContext.ResolvedTransferRecipient?, query: String) {
        guard self.query == query else {
            return
        }
        self.isResolvingRecipient = false
        self.recipient = recipient
    }

    func entries(peers: [EnginePeer]) -> [EnginePeer.Id] {
        var entries: [EnginePeer.Id] = []
        var peerIds = Set<EnginePeer.Id>()
        func appendPeer(_ peer: EnginePeer) {
            guard peerIds.insert(peer.id).inserted else {
                return
            }
            entries.append(peer.id)
        }
        if self.query.isEmpty {
            for peer in peers {
                appendPeer(peer)
            }
        } else {
            for peer in self.localSearchPeers {
                appendPeer(peer)
            }
            for peer in self.remoteLocalSearchPeers {
                appendPeer(peer)
            }
            for peer in self.globalSearchPeers {
                appendPeer(peer)
            }
        }
        return entries
    }

    func displaysNoResults(peers: [EnginePeer]) -> Bool {
        return !self.query.isEmpty && !self.isSearching && self.entries(peers: peers).isEmpty && self.recipient == nil
    }
}

private func submoduleApplyResolvedRecipient(initialAddress: String, recipient: WalletUserAddress) -> (address: String, publicKey: Data?) {
    let address = WalletContext.transferRecipient(from: initialAddress)?.address ?? recipient.address
    let accountAddress = WalletContext.transferAddress(from: address)
    let publicKey = accountAddress != nil && accountAddress == WalletContext.transferAddress(from: recipient.address)
        ? recipient.publicKey : nil
    return (address, publicKey)
}

private func submoduleRecipientDisplaysPlaceholder(address: String, hasPeer: Bool, isLoading: Bool) -> Bool {
    return hasPeer && (isLoading || address.isEmpty)
}

private struct SubmoduleRecipientAddressScramble {
    enum AddressPhase {
        case loading
        case revealing
        case ready
    }

    struct Component {
        let peerId: EnginePeer.Id?
        let address: String
        let isLoading: Bool
    }

    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    static let flipDuration = 0.14
    static let sweepDuration = 0.4
    static let settleDuration = 0.546

    var component: Component?
    var addressPhase: AddressPhase = .ready
    var animationElapsed: Double = 0
    var revealElapsed: Double = 0
    var openingTime: Double?

    mutating func advance(by delta: Double) {
        self.animationElapsed += delta
        if self.addressPhase == .revealing && self.openingTime == nil {
            self.revealElapsed += delta
            if self.revealElapsed >= Self.settleDuration {
                self.addressPhase = .ready
            }
        }
    }

    mutating func update(_ component: Component) {
        let hasPeer = component.peerId != nil
        let displaysPlaceholder = hasPeer && (component.isLoading || component.address.isEmpty)
        if self.component?.peerId != component.peerId || self.component?.address != component.address || self.component?.isLoading != component.isLoading {
            let continuesLoading = self.component?.peerId == component.peerId
                && self.addressPhase == .loading
            if !continuesLoading {
                self.animationElapsed = 0
            }
            self.revealElapsed = 0
            if displaysPlaceholder {
                self.addressPhase = .loading
            } else if hasPeer && continuesLoading && self.openingTime == nil {
                self.addressPhase = .revealing
            } else {
                self.addressPhase = .ready
            }
        }
        self.component = component
    }

    static func addressLines(_ address: String, groupsPerLine: Int) -> [String] {
        var lines: [String] = []
        var groups: [String] = []
        var index = address.startIndex
        while index < address.endIndex {
            let endIndex = address.index(index, offsetBy: 4, limitedBy: address.endIndex) ?? address.endIndex
            groups.append(String(address[index ..< endIndex]))
            index = endIndex
            if groups.count == groupsPerLine {
                lines.append(groups.joined(separator: " "))
                groups.removeAll(keepingCapacity: true)
            }
        }
        if !groups.isEmpty {
            lines.append(groups.joined(separator: " "))
        }
        return lines
    }

    func formattedAddressLines(groupsPerLine: Int) -> [String] {
        guard let component = self.component else {
            return []
        }
        let displaysPlaceholder = component.peerId != nil && (component.isLoading || component.address.isEmpty)
        let addressText = displaysPlaceholder ? String(repeating: "0", count: 48) : (component.address.isEmpty ? "—" : component.address)
        return Self.addressLines(addressText, groupsPerLine: groupsPerLine)
    }

    func renderStep(groupsPerLine: Int) -> (tick: Int, revealStep: Int) {
        let total = self.formattedAddressLines(groupsPerLine: groupsPerLine).reduce(0) { $0 + $1.count }
        let tick = self.addressPhase == .ready ? -1 : Int(self.animationElapsed / Self.flipDuration)
        let revealStep = self.addressPhase == .revealing ? Int(self.revealElapsed / Self.sweepDuration * Double(max(total - 1, 1))) : -1
        return (tick, revealStep)
    }

    func addressCharacters(groupsPerLine: Int) -> [(character: Character, isSettled: Bool)] {
        let formattedAddressLines = self.formattedAddressLines(groupsPerLine: groupsPerLine)
        let total = formattedAddressLines.reduce(0) { $0 + $1.count }
        let tick = Int(self.animationElapsed / Self.flipDuration)
        var result: [(character: Character, isSettled: Bool)] = []
        var place = 0
        for (row, line) in formattedAddressLines.enumerated() {
            if row != 0 {
                result.append(("\n", true))
            }
            for (column, group) in line.split(separator: " ").enumerated() {
                if column != 0 {
                    result.append((" ", true))
                    place += 1
                }
                for character in group {
                    let settled = self.addressPhase == .ready || (self.addressPhase == .revealing
                        && self.revealElapsed >= Self.sweepDuration * Double(place) / Double(max(total - 1, 1)))
                    let displayedCharacter: Character
                    if settled {
                        displayedCharacter = character
                    } else {
                        let hash = (place &* 2_654_435_761) ^ (tick &* 40_503)
                        displayedCharacter = Self.alphabet[(hash & 0x7fff_ffff) % Self.alphabet.count]
                    }
                    result.append((displayedCharacter, settled))
                    place += 1
                }
            }
        }
        return result
    }
}

final class WalletRecipientSubmoduleCompatibilityTests: XCTestCase {
    private let accountPeerId = EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))

    private func userId(_ value: Int64) -> EnginePeer.Id {
        return EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(value))
    }

    private func user(_ id: Int64, firstName: String? = "User", lastName: String? = nil, isBot: Bool = false) -> EnginePeer {
        return .user(TelegramUser(id: self.userId(id), accessHash: nil, firstName: firstName, lastName: lastName, username: nil, phone: nil, photo: [], botInfo: isBot ? BotUserInfo(flags: [], inlinePlaceholder: nil) : nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil))
    }

    private func group(_ id: Int64) -> EnginePeer {
        return .legacyGroup(TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(id)), title: "Group", photo: [], participantCount: 1, role: .creator(rank: nil), membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0))
    }

    private func friendlyAddress(hashByte: UInt8, bounceable: Bool, testnet: Bool = false) -> String {
        var bytes: [UInt8] = [(bounceable ? 0x11 : 0x51) | (testnet ? 0x80 : 0x00), 0x00]
        bytes += Array(repeating: hashByte, count: 32)
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0 ..< 8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        bytes += [UInt8(crc >> 8), UInt8(crc & 0xff)]
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }

    private func rawAddress(hashByte: UInt8) -> String {
        return "0:" + String(repeating: String(format: "%02x", hashByte), count: 32)
    }

    func testFriendlyAddressFixtureMatchesAKnownAddress() {
        XCTAssertEqual(self.friendlyAddress(hashByte: 0x11, bounceable: false), "UQAREREREREREREREREREREREREREREREREREREREREREbvW")
        XCTAssertEqual(WalletContext.transferAddress(from: self.friendlyAddress(hashByte: 0x11, bounceable: true)), "UQAREREREREREREREREREREREREREREREREREREREREREbvW")
    }

    func testEligibleRecipientsMatchSubmodule() {
        let peers: [EnginePeer] = [
            self.user(100),
            self.user(101, firstName: nil, lastName: "Last"),
            self.user(1),
            self.user(102, isBot: true),
            self.user(103, firstName: nil, lastName: nil),
            self.user(777000),
            self.user(333000),
            self.user(708513),
            self.user(1271266957),
            self.user(489000),
            self.group(5)
        ]
        for peer in peers {
            XCTAssertEqual(walletRecipientIsEligiblePeer(peer, accountPeerId: self.accountPeerId), submodulePeerSelectionIsEligiblePeer(peer, accountPeerId: self.accountPeerId), "\(peer.id)")
        }
        XCTAssertTrue(walletRecipientIsEligiblePeer(self.user(100), accountPeerId: self.accountPeerId))
    }

    func testAddressQueryDetectionMatchesSubmodule() {
        let friendly = self.friendlyAddress(hashByte: 0x22, bounceable: true)
        let filler20 = String(repeating: "x", count: 20)
        let filler31 = String(repeating: "x", count: 31)
        let filler40 = String(repeating: "x", count: 40)
        var queries: [String] = ["", "alice", "@alice", "Alice Example", "alice.ton"]
        queries += [friendly, "@" + friendly, String(friendly.dropLast()), friendly + "A"]
        queries += [String(friendly.prefix(33)), String(friendly.prefix(32))]
        queries += ["UQ" + filler31, "kQ" + filler40, "0f" + filler40, "Zz" + filler40]
        queries += [String(repeating: "a", count: 48), "EQ" + filler20 + " " + filler20]
        queries += [self.rawAddress(hashByte: 0x33), "-1:abc", "0:", "12x:abc", "abc:def"]
        queries += ["ton://transfer/" + friendly, "TON://transfer/x", "ton:/x"]
        for query in queries {
            XCTAssertEqual(walletRecipientQueryLooksLikeAddress(query), submodulePeerSelectionIsAddressQuery(query), query)
        }
    }

    func testRecipientSearchSessionMatchesSubmodule() {
        let alice = self.user(10, firstName: "Alice")
        let bob = self.user(11, firstName: "Bob")
        let carol = self.user(12, firstName: "Carol")
        let dave = self.user(13, firstName: "Dave")
        let chats = [bob, alice]

        enum Step {
            case type(String)
            case local([EnginePeer])
            case remote(local: [EnginePeer], global: [EnginePeer])
            case resolved(WalletContext.ResolvedTransferRecipient?)
        }
        let steps: [Step] = [
            .type("al"),
            .local([alice, bob]),
            .resolved(nil),
            .remote(local: [bob, carol], global: [dave, alice]),
            .type("ali"),
            .local([alice]),
            .resolved(nil),
            .remote(local: [], global: []),
            .type("alic"),
            .remote(local: [carol], global: []),
            .local([]),
            .resolved(nil),
            .type("zzz"),
            .local([]),
            .remote(local: [], global: []),
            .resolved(nil),
            .type(""),
            .type("dave"),
            .resolved(nil),
            .local([]),
            .remote(local: [], global: [dave]),
            .type(String(self.friendlyAddress(hashByte: 0x44, bounceable: false).dropLast())),
            .local([]),
            .remote(local: [], global: []),
            .resolved(nil)
        ]

        var submodule = SubmodulePeerSelectionSearch()
        var actual = WalletRecipientState()
        actual.recentPeers = chats
        for (index, step) in steps.enumerated() {
            switch step {
            case let .type(query):
                submodule.updateQuery(query)
                _ = actual.beginSearch(query)
                actual.address = query
                actual.resolved = nil
                actual.resolveFailed = false
                actual.isResolving = !query.isEmpty
            case let .local(peers):
                submodule.localSearchCompleted(peers, query: submodule.query)
                actual.finishLocalSearch(peers)
            case let .remote(local, global):
                submodule.remoteSearchCompleted(local: local, global: global, query: submodule.query)
                actual.finishRemoteSearch(local + global)
            case let .resolved(recipient):
                submodule.resolveCompleted(recipient, query: submodule.query)
                actual.isResolving = false
                actual.resolved = recipient
                actual.resolveFailed = recipient == nil
            }
            XCTAssertEqual(walletMatchingPeers(actual).map(\.id), submodule.entries(peers: chats), "step \(index)")
            XCTAssertEqual(walletShowsNoRecipientResults(actual), submodule.displaysNoResults(peers: chats), "step \(index)")
            if walletShowsNoRecipientResults(actual) {
                XCTAssertEqual(walletRecipientQueryLooksLikeAddress(actual.address), submodulePeerSelectionIsAddressQuery(submodule.query), "step \(index)")
            }
        }
    }

    func testEnteredAddressesKeepTheirFormLikeSubmodule() {
        let bounceable = self.friendlyAddress(hashByte: 0x55, bounceable: true)
        let nonBounceable = self.friendlyAddress(hashByte: 0x55, bounceable: false)
        let testnet = self.friendlyAddress(hashByte: 0x55, bounceable: true, testnet: true)
        let inputs = [
            bounceable, nonBounceable, " \(bounceable)\n", self.rawAddress(hashByte: 0x55),
            "ton://transfer/\(bounceable)?amount=10", "ton://transfer/\(nonBounceable)", testnet, "alice.ton", "garbage", ""
        ]
        for input in inputs {
            let actual = walletSendRecipientAddress(walletParseRecipient(input).address)
            let submodule = WalletContext.transferRecipient(from: input)?.address
            XCTAssertEqual(actual, submodule, input)
        }
        XCTAssertEqual(walletSendRecipientAddress(bounceable), bounceable)
        XCTAssertNotEqual(walletSendRecipientAddress(bounceable), WalletContext.transferAddress(from: bounceable))
    }

    func testSendAgainAddressMatchesSubmodule() {
        let bounceable = self.friendlyAddress(hashByte: 0x66, bounceable: true)
        let nonBounceable = self.friendlyAddress(hashByte: 0x66, bounceable: false)
        for counterparty in [bounceable, nonBounceable, self.rawAddress(hashByte: 0x66)] {
            let actual = walletSendRecipientAddress(counterparty) ?? counterparty
            let submodule = WalletContext.transferAddress(from: counterparty, preserveBounce: true) ?? counterparty
            XCTAssertEqual(actual, submodule, counterparty)
            XCTAssertEqual(walletSendRecipientAddress(walletParseRecipient(actual).address), WalletContext.transferRecipient(from: submodule)?.address, counterparty)
        }
    }

    func testResolvedPeerAddressAndKeyMatchSubmodule() {
        let peerId = self.userId(20)
        let key = Data([1, 2, 3])
        let userBounceable = self.friendlyAddress(hashByte: 0x77, bounceable: true)
        let userNonBounceable = self.friendlyAddress(hashByte: 0x77, bounceable: false)
        let otherAccount = self.friendlyAddress(hashByte: 0x78, bounceable: true)
        let registered = [
            WalletUserAddress(userId: peerId, address: userNonBounceable, publicKey: key),
            WalletUserAddress(userId: peerId, address: userBounceable, publicKey: key),
            WalletUserAddress(userId: peerId, address: userNonBounceable, publicKey: Data())
        ]
        for recipient in registered {
            for initial in ["", userBounceable, userNonBounceable, otherAccount, "ton://transfer/\(otherAccount)?amount=5", "garbage"] {
                let submodule = submoduleApplyResolvedRecipient(initialAddress: initial, recipient: recipient)
                let target = WalletPeerSendTarget(address: recipient.address, publicKey: recipient.publicKey.isEmpty ? nil : recipient.publicKey)
                let actualAddress: String?
                let actualKey: Data?
                if !initial.isEmpty, let address = walletSendRecipientAddress(walletParseRecipient(initial).address) {
                    actualAddress = address
                    actualKey = walletSendPeerPublicKey(address: address, peerAddress: target.address, publicKey: target.publicKey)
                } else {
                    actualAddress = walletSendRecipientAddress(target.address)
                    actualKey = target.publicKey
                }
                XCTAssertEqual(actualAddress.flatMap { WalletContext.transferAddress(from: $0, preserveBounce: true) }, WalletContext.transferAddress(from: submodule.address, preserveBounce: true), "\(initial) \(recipient.address)")
                XCTAssertEqual(actualKey, submodule.publicKey.flatMap { $0.isEmpty ? nil : $0 }, "\(initial) \(recipient.address)")
            }
        }
    }

    func testRecipientPlaceholderMatchesSubmodule() {
        let address = self.friendlyAddress(hashByte: 0x88, bounceable: false)
        for hasPeer in [false, true] {
            for value in ["", address] {
                for isLoading in [false, true] {
                    let submodule = submoduleRecipientDisplaysPlaceholder(address: value, hasPeer: hasPeer, isLoading: isLoading)
                    let actualAddress: String? = value.isEmpty ? nil : value
                    XCTAssertEqual(walletRecipientDisplaysPlaceholder(address: actualAddress, hasPeer: hasPeer, isLoading: isLoading), submodule)
                    let submoduleText = submodule ? String(repeating: "0", count: 48) : (value.isEmpty ? "—" : value)
                    XCTAssertEqual(walletRecipientAddressText(address: actualAddress, hasPeer: hasPeer, isLoading: isLoading), submoduleText)
                }
            }
        }
    }

    private func gridText(_ text: String, groupsPerLine: Int) -> String {
        var result = ""
        for (position, group) in walletAddressGroups(text).enumerated() {
            if position > 0 {
                result += position % groupsPerLine == 0 ? "\n" : " "
            }
            result += group
        }
        return result
    }

    func testAddressScrambleMatchesSubmodule() {
        let peer = self.userId(30)
        let otherPeer = self.userId(31)
        let address = self.friendlyAddress(hashByte: 0x99, bounceable: false)
        enum Step {
            case update(EnginePeer.Id?, String, Bool)
            case ticks(Int)
        }
        let steps: [Step] = [
            .update(peer, "", true),
            .ticks(12),
            .update(peer, "", false),
            .ticks(5),
            .update(peer, address, false),
            .ticks(20),
            .update(peer, address, false),
            .ticks(2),
            .update(otherPeer, "", true),
            .ticks(3),
            .update(otherPeer, address, false),
            .ticks(3),
            .update(otherPeer, address, true),
            .ticks(2),
            .update(nil, address, false),
            .ticks(2),
            .update(nil, "", false),
            .update(peer, address, false),
            .ticks(2)
        ]
        for groupsPerLine in [3, 4, 6] {
            var submodule = SubmoduleRecipientAddressScramble()
            var actual = WalletRecipientAddressScramble()
            var lastComponent: SubmoduleRecipientAddressScramble.Component?
            var checks = 0
            func compare(_ label: String) {
                guard let component = lastComponent else {
                    return
                }
                let actualAddress: String? = component.address.isEmpty ? nil : component.address
                let text = self.gridText(walletRecipientAddressText(address: actualAddress, hasPeer: component.peerId != nil, isLoading: component.isLoading), groupsPerLine: groupsPerLine)
                XCTAssertEqual(text, submodule.formattedAddressLines(groupsPerLine: groupsPerLine).joined(separator: "\n"), label)
                let actualCharacters = actual.displayedCharacters(text)
                let submoduleCharacters = submodule.addressCharacters(groupsPerLine: groupsPerLine)
                XCTAssertEqual(actualCharacters.map { String($0.character) }.joined(), submoduleCharacters.map { String($0.character) }.joined(), label)
                XCTAssertEqual(actualCharacters.map(\.isSettled), submoduleCharacters.map(\.isSettled), label)
                XCTAssertEqual(String(describing: actual.phase), String(describing: submodule.addressPhase), label)
                let renderStep = submodule.renderStep(groupsPerLine: groupsPerLine)
                XCTAssertEqual(actual.renderStep(text), WalletRecipientAddressRenderStep(tick: renderStep.tick, revealStep: renderStep.revealStep), label)
                checks += 1
            }
            for (index, step) in steps.enumerated() {
                switch step {
                case let .update(peerId, address, isLoading):
                    let component = SubmoduleRecipientAddressScramble.Component(peerId: peerId, address: address, isLoading: isLoading)
                    submodule.update(component)
                    actual.update(peerId: peerId, address: address.isEmpty ? nil : address, isLoading: isLoading)
                    lastComponent = component
                    compare("groups \(groupsPerLine) step \(index)")
                case let .ticks(count):
                    for tick in 0 ..< count {
                        submodule.advance(by: 0.035)
                        actual.advance(by: 0.035)
                        compare("groups \(groupsPerLine) step \(index) tick \(tick)")
                    }
                }
            }
            XCTAssertGreaterThan(checks, 60)
        }
    }

    func testAddressScrambleDuringOpeningMatchesSubmodule() {
        let peer = self.userId(32)
        let address = self.friendlyAddress(hashByte: 0x9A, bounceable: false)
        enum Step {
            case update(EnginePeer.Id?, String, Bool)
            case opening(Bool)
            case ticks(Int)
        }
        let scenarios: [[Step]] = [
            [.opening(true), .update(peer, "", true), .ticks(10), .update(peer, address, false), .ticks(10), .opening(false), .ticks(5)],
            [.opening(true), .update(peer, "", true), .ticks(10), .opening(false), .ticks(3), .update(peer, address, false), .ticks(20)],
            [.update(peer, "", true), .ticks(4), .update(peer, address, false), .ticks(3), .opening(true), .ticks(20), .opening(false), .ticks(20)],
            [.opening(true), .update(peer, address, false), .ticks(8), .opening(false), .ticks(8)]
        ]
        for (scenarioIndex, steps) in scenarios.enumerated() {
            var submodule = SubmoduleRecipientAddressScramble()
            var actual = WalletRecipientAddressScramble()
            var isOpening = false
            var lastComponent: SubmoduleRecipientAddressScramble.Component?
            var sawRevealing = false
            func compare(_ label: String) {
                guard let component = lastComponent else {
                    return
                }
                let actualAddress: String? = component.address.isEmpty ? nil : component.address
                let text = self.gridText(walletRecipientAddressText(address: actualAddress, hasPeer: component.peerId != nil, isLoading: component.isLoading), groupsPerLine: 6)
                let actualCharacters = actual.displayedCharacters(text)
                let submoduleCharacters = submodule.addressCharacters(groupsPerLine: 6)
                XCTAssertEqual(actualCharacters.map { String($0.character) }.joined(), submoduleCharacters.map { String($0.character) }.joined(), label)
                XCTAssertEqual(actualCharacters.map(\.isSettled), submoduleCharacters.map(\.isSettled), label)
                XCTAssertEqual(String(describing: actual.phase), String(describing: submodule.addressPhase), label)
                let renderStep = submodule.renderStep(groupsPerLine: 6)
                XCTAssertEqual(actual.renderStep(text), WalletRecipientAddressRenderStep(tick: renderStep.tick, revealStep: renderStep.revealStep), label)
                sawRevealing = sawRevealing || actual.phase == .revealing
            }
            for (index, step) in steps.enumerated() {
                let label = "scenario \(scenarioIndex) step \(index)"
                switch step {
                case let .update(peerId, address, isLoading):
                    let component = SubmoduleRecipientAddressScramble.Component(peerId: peerId, address: address, isLoading: isLoading)
                    submodule.update(component)
                    actual.update(peerId: peerId, address: address.isEmpty ? nil : address, isLoading: isLoading, isOpening: isOpening)
                    lastComponent = component
                    compare(label)
                case let .opening(value):
                    isOpening = value
                    submodule.openingTime = value ? 0.0 : nil
                    compare(label)
                case let .ticks(count):
                    for tick in 0 ..< count {
                        submodule.advance(by: 0.035)
                        actual.advance(by: 0.035, isOpening: isOpening)
                        compare("\(label) tick \(tick)")
                    }
                }
            }
            XCTAssertEqual(sawRevealing, scenarioIndex == 1 || scenarioIndex == 2, "scenario \(scenarioIndex)")
        }
    }

    func testAddressScrambleRevealsOnlyAfterLoadingLikeSubmodule() {
        let peer = self.userId(40)
        let address = self.friendlyAddress(hashByte: 0xAA, bounceable: false)
        var actual = WalletRecipientAddressScramble()
        actual.update(peerId: peer, address: nil, isLoading: true)
        XCTAssertEqual(actual.phase, .loading)
        actual.advance(by: 0.3)
        actual.update(peerId: peer, address: address, isLoading: false)
        XCTAssertEqual(actual.phase, .revealing)
        XCTAssertEqual(actual.animationElapsed, 0.3, accuracy: 0.0001)
        actual.advance(by: 0.545)
        XCTAssertEqual(actual.phase, .revealing)
        actual.advance(by: 0.002)
        XCTAssertEqual(actual.phase, .ready)

        var fresh = WalletRecipientAddressScramble()
        fresh.update(peerId: peer, address: address, isLoading: false)
        XCTAssertEqual(fresh.phase, .ready)

        var reduced = WalletRecipientAddressScramble()
        reduced.update(peerId: peer, address: nil, isLoading: true)
        reduced.update(peerId: peer, address: address, isLoading: false)
        reduced.skipReveal()
        XCTAssertEqual(reduced.phase, .ready)
    }
}
