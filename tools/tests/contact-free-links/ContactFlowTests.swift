import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
typealias MessageId = Int
struct ChatInitialAction {}
struct User { let id: PeerId; var botInfo: Int? = nil }
struct Peer { let isChannel = false; let isSupergroup = false; let isBot = false; let compactDisplayTitle = "Recipient" }
enum EnginePeer {
    case user(User)
    var id: PeerId { switch self { case let .user(user): return user.id } }
    func _asPeer() -> Peer { Peer() }
}
enum ImportNoPaidMessagesTokenError: Error { case invalidToken; case generic }
final class Window {
    var alerts: [String] = []
    var messages: [String] = []
}
final class Messages {
    var contacts: [(String, Subscriber<EnginePeer?, NoError>)] = []
    var free: [(PeerId, String, Subscriber<EnginePeer, ImportNoPaidMessagesTokenError>)] = []
    func importContactToken(token: String) -> Signal<EnginePeer?, NoError> {
        Signal { subscriber in self.contacts.append((token, subscriber)); return EmptyDisposable }
    }
    func importNoPaidMessagesToken(peerId: PeerId, token: String) -> Signal<EnginePeer, ImportNoPaidMessagesTokenError> {
        Signal { subscriber in self.free.append((peerId, token, subscriber)); return EmptyDisposable }
    }
}
final class Engine { let peers = Messages() }
final class AccountContext { let engine = Engine(); let peerId = 1; let window = Window() }
func getWindow(_ context: AccountContext) -> Window { context.window }
func afterComplete(_ result: Bool) {}
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> { signal }
func showModalText(for window: Window, text: String) { window.messages.append(text) }
func alert(for window: Window, info: String) { window.alerts.append(info) }
struct TestStrings { let alertUserDoesntExists = "Missing contact"; let unknownError = "Unknown error" }
func strings() -> TestStrings { TestStrings() }

__PRODUCTION__

final class ContactFlowTests: XCTestCase {
    func drain() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }

    func testResolvesContactBeforeImportingFreeToken() {
        let context = AccountContext()
        var opened: [PeerId] = []
        openContact(token: "XXXX:YYYZZZ", freeToken: "AABBCC", context: context) { id, _, _, _ in opened.append(id) }
        XCTAssertEqual(context.engine.peers.contacts.map { $0.0 }, ["XXXX:YYYZZZ"])
        XCTAssertTrue(context.engine.peers.free.isEmpty)
        context.engine.peers.contacts[0].1.putNext(.user(User(id: 42)))
        drain()
        XCTAssertEqual(context.engine.peers.free[0].0, 42)
        XCTAssertEqual(context.engine.peers.free[0].1, "AABBCC")
        XCTAssertTrue(opened.isEmpty)
        context.engine.peers.free[0].2.putNext(.user(User(id: 42)))
        drain()
        XCTAssertEqual(opened, [42])
        XCTAssertEqual(context.window.messages, ["You can now message Recipient for free."])
    }

    func testMissingContactNeverImportsFreeToken() {
        let context = AccountContext()
        var opened: [PeerId] = []
        openContact(token: "expired", freeToken: "AABBCC", context: context) { id, _, _, _ in opened.append(id) }
        context.engine.peers.contacts[0].1.putNext(nil)
        drain()
        XCTAssertTrue(context.engine.peers.free.isEmpty)
        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(context.window.alerts, ["Missing contact"])
    }

    func testExpiredFreeTokenDoesNotClaimFreeMessaging() {
        let context = AccountContext()
        var opened: [PeerId] = []
        openContact(token: "XXXX:YYYZZZ", freeToken: "expired", context: context) { id, _, _, _ in opened.append(id) }
        context.engine.peers.contacts[0].1.putNext(.user(User(id: 42)))
        drain()
        context.engine.peers.free[0].2.putError(.invalidToken)
        drain()
        XCTAssertEqual(opened, [42])
        XCTAssertEqual(context.window.messages, ["This free message link is invalid or has expired."])
    }

    func testOrdinaryContactDoesNotImportFreeToken() {
        let context = AccountContext()
        var opened: [PeerId] = []
        openContact(token: "XXXX:YYYZZZ", freeToken: nil, context: context) { id, _, _, _ in opened.append(id) }
        context.engine.peers.contacts[0].1.putNext(.user(User(id: 42)))
        drain()
        XCTAssertEqual(opened, [42])
        XCTAssertTrue(context.engine.peers.free.isEmpty)
        XCTAssertTrue(context.window.messages.isEmpty)
    }
}
