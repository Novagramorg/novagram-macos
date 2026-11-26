public typealias PeerId = Int64

public struct Peer: Equatable {
    let id: PeerId
}

public struct EnginePeer: Equatable {
    public typealias Id = PeerId
    let peer: Peer

    init(_ peer: Peer) {
        self.peer = peer
    }
}

enum Api {
    enum Bool {
        case boolTrue
        case boolFalse
    }

    enum Request: Hashable {
        case reset(Int64)
        case resetAll
    }

    enum functions {
        enum account {
            static func resetWebAuthorization(hash: Int64) -> Request {
                return .reset(hash)
            }

            static func resetWebAuthorizations() -> Request {
                return .resetAll
            }
        }
    }
}

final class Network {
    var sessions: [WebAuthorization] = []
    var peers: [PeerId: Peer] = [:]
    private(set) var requested: Api.Request?
    private var subscribers: [Api.Request: Subscriber<Api.Bool, NoError>] = [:]

    func request(_ request: Api.Request) -> Signal<Api.Bool, NoError> {
        requested = request
        return Signal { subscriber in
            self.subscribers[request] = subscriber
            return ActionDisposable {
                self.subscribers[request] = nil
            }
        }
    }

    func respond(_ result: Api.Bool, to request: Api.Request? = nil) {
        guard let request = request ?? requested else {
            return
        }
        let subscriber = self.subscribers[request]
        subscriber?.putNext(result)
        subscriber?.putCompletion()
    }
}

final class Account {
    let network = Network()
}

func retryRequest<T>(signal: Signal<T, NoError>) -> Signal<T, NoError> {
    return signal
}

func webSessions(network: Network) -> Signal<([WebAuthorization], [PeerId: Peer]), NoError> {
    return .single((network.sessions, network.peers))
}

final class WebSessionsRegressionTests: XCTestCase {
    private func session(_ hash: Int64) -> WebAuthorization {
        return WebAuthorization(hash: hash, botId: hash, domain: "example.test", browser: "Test", platform: "macOS", dateCreated: 0, dateActive: 0, ip: "", region: "")
    }

    private func account() -> Account {
        let account = Account()
        account.network.sessions = [session(1), session(2)]
        account.network.peers = [1: Peer(id: 1), 2: Peer(id: 2)]
        return account
    }

    private func verifyRemoval(all: Bool, accepted: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
        let account = account()
        let context = WebSessionsContext(account: account)
        var latest: WebSessionsContextState?
        let observer = context.state.start(next: { latest = $0 })
        var values: [Any] = []
        var completed = false
        let operation = all ? context.removeAll() : context.remove(hash: 1)
        let removal = operation.start(next: { values.append($0 as Any) }, completed: { completed = true })
        defer { observer.dispose(); removal.dispose() }

        XCTAssertEqual(account.network.requested, all ? .resetAll : .reset(1), file: file, line: line)
        XCTAssertEqual(try XCTUnwrap(latest).sessions.map(\.hash), [1, 2], file: file, line: line)
        XCTAssertFalse(completed, file: file, line: line)
        XCTAssertTrue(values.isEmpty, file: file, line: line)

        account.network.respond(accepted ? .boolTrue : .boolFalse)

        XCTAssertEqual(try XCTUnwrap(latest).sessions.map(\.hash), accepted ? (all ? [] : [2]) : [1, 2], file: file, line: line)
        XCTAssertEqual(try XCTUnwrap(latest).peers.count, accepted && all ? 0 : 2, file: file, line: line)
        XCTAssertEqual(values.count, 1, file: file, line: line)
        XCTAssertEqual(values.first as? Bool, accepted, file: file, line: line)
        XCTAssertTrue(completed, file: file, line: line)
    }

    func testConfirmedSingleRemovalKeepsOtherSessions() throws {
        try verifyRemoval(all: false, accepted: true)
    }

    func testRejectedSingleRemovalPreservesSessions() throws {
        try verifyRemoval(all: false, accepted: false)
    }

    func testConfirmedRemoveAllClearsSessionsAndPeers() throws {
        try verifyRemoval(all: true, accepted: true)
    }

    func testRejectedRemoveAllPreservesSessionsAndPeers() throws {
        try verifyRemoval(all: true, accepted: false)
    }

    func testCancelledRemovalPreservesSessions() throws {
        let account = account()
        let context = WebSessionsContext(account: account)
        var latest: WebSessionsContextState?
        let observer = context.state.start(next: { latest = $0 })
        defer { observer.dispose() }
        let removal = context.remove(hash: 1).start()
        removal.dispose()
        account.network.respond(.boolTrue)

        XCTAssertEqual(try XCTUnwrap(latest).sessions.map(\.hash), [1, 2])
    }

    func testIndependentRemovalsCompleteInReverseOrder() throws {
        let account = account()
        let context = WebSessionsContext(account: account)
        var latest: WebSessionsContextState?
        let observer = context.state.start(next: { latest = $0 })
        let first = context.remove(hash: 1).start()
        let second = context.remove(hash: 2).start()
        defer { observer.dispose(); second.dispose(); first.dispose() }
        account.network.respond(.boolTrue, to: .reset(2))
        XCTAssertEqual(try XCTUnwrap(latest).sessions.map(\.hash), [1])
        account.network.respond(.boolTrue, to: .reset(1))

        XCTAssertEqual(try XCTUnwrap(latest).sessions, [])
    }
}
