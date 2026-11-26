enum TerminateSessionError: Error {
    case generic
}

enum UpdateSessionError: Error {
    case generic
}

enum UpadteAuthorizationTTLError: Error {
    case generic
}

final class PendingRequest<E> {
    private var subscriber: Subscriber<Void, E>?

    var signal: Signal<Void, E> {
        return Signal { subscriber in
            self.subscriber = subscriber
            return ActionDisposable {
                self.subscriber = nil
            }
        }
    }

    func succeed() {
        let subscriber = self.subscriber
        subscriber?.putNext(())
        subscriber?.putCompletion()
    }

    func fail(_ error: E) {
        subscriber?.putError(error)
    }
}

final class TestStateManager {
    let authorizationListUpdates: Signal<Void, NoError> = .never()
}

final class Account {
    let stateManager = TestStateManager()
    var serverSessions: [RecentAccountSession] = []
    let secretRequest = PendingRequest<UpdateSessionError>()
    let callsRequest = PendingRequest<UpdateSessionError>()
    let removeRequest = PendingRequest<TerminateSessionError>()
    var ttlRequests: [PendingRequest<UpadteAuthorizationTTLError>] = []
}

func requestRecentAccountSessions(account: Account) -> Signal<([RecentAccountSession], Int32), NoError> {
    return .single((account.serverSessions, 90))
}

func terminateAccountSession(account: Account, hash: Int64) -> Signal<Void, TerminateSessionError> {
    return account.removeRequest.signal
}

func terminateOtherAccountSessions(account: Account) -> Signal<Void, TerminateSessionError> {
    return account.removeRequest.signal
}

func updateAccountSessionAcceptsSecretChats(account: Account, hash: Int64, accepts: Bool) -> Signal<Void, UpdateSessionError> {
    return account.secretRequest.signal
}

func updateAccountSessionAcceptsIncomingCalls(account: Account, hash: Int64, accepts: Bool) -> Signal<Void, UpdateSessionError> {
    return account.callsRequest.signal
}

func setAuthorizationTTL(account: Account, ttl: Int32) -> Signal<Void, UpadteAuthorizationTTLError> {
    let request = PendingRequest<UpadteAuthorizationTTLError>()
    account.ttlRequests.append(request)
    return request.signal
}

final class ActiveSessionsRegressionTests: XCTestCase {
    private func session(_ hash: Int64) -> RecentAccountSession {
        return RecentAccountSession(hash: hash, deviceModel: "Test", platform: "macOS", systemVersion: "1", apiId: 1, appName: "Test", appVersion: "1", creationDate: 0, activityDate: 0, ip: "", country: "", region: "", flags: [])
    }

    func testSettingsCompletionDoesNotRestoreTerminatedSession() throws {
        let account = Account()
        account.serverSessions = [session(1), session(2)]
        let context = ActiveSessionsContextImpl(account: account)
        var latest: ActiveSessionsContextState?
        let observer = context.state.start(next: { latest = $0 })
        let update = context.updateSessionAcceptsSecretChats(session(1), accepts: true).start()
        let remove = context.remove(hash: 2).start()
        defer { observer.dispose(); update.dispose(); remove.dispose() }

        account.removeRequest.succeed()
        XCTAssertEqual(try XCTUnwrap(latest).sessions.map(\.hash), [1])
        account.secretRequest.succeed()
        XCTAssertEqual(try XCTUnwrap(latest).sessions.map(\.hash), [1])
    }

    func testIndependentSettingsSurviveReversedResponses() throws {
        let account = Account()
        account.serverSessions = [session(1)]
        let context = ActiveSessionsContextImpl(account: account)
        var latest: ActiveSessionsContextState?
        let observer = context.state.start(next: { latest = $0 })
        let secret = context.updateSessionAcceptsSecretChats(session(1), accepts: true).start()
        let calls = context.updateSessionAcceptsIncomingCalls(session(1), accepts: true).start()
        defer { observer.dispose(); secret.dispose(); calls.dispose() }

        account.callsRequest.succeed()
        account.secretRequest.succeed()
        let flags = try XCTUnwrap(latest?.sessions.first).flags
        XCTAssertTrue(flags.contains(.acceptsSecretChats))
        XCTAssertTrue(flags.contains(.acceptsIncomingCalls))
    }

    func testSettingsCompletionPreservesNewSession() throws {
        let account = Account()
        account.serverSessions = [session(1)]
        let context = ActiveSessionsContextImpl(account: account)
        var latest: ActiveSessionsContextState?
        let observer = context.state.start(next: { latest = $0 })
        let update = context.updateSessionAcceptsIncomingCalls(session(1), accepts: true).start()
        defer { observer.dispose(); update.dispose() }

        context.addSession(session(2))
        account.callsRequest.succeed()
        XCTAssertEqual(try XCTUnwrap(latest).sessions.map(\.hash), [2, 1])
    }

    func testOlderTTLResponseDoesNotReplaceLatestSelection() throws {
        let account = Account()
        account.serverSessions = [session(1)]
        let context = ActiveSessionsContextImpl(account: account)
        var latest: ActiveSessionsContextState?
        let observer = context.state.start(next: { latest = $0 })
        let first = context.updateAuthorizationTTL(days: 30).start()
        let second = context.updateAuthorizationTTL(days: 180).start()
        defer { observer.dispose(); first.dispose(); second.dispose() }

        account.ttlRequests[1].succeed()
        account.ttlRequests[0].succeed()
        XCTAssertEqual(try XCTUnwrap(latest).ttlDays, 180)
    }

    func testSettingsRequestsKeepCompletionAndErrorDelivery() {
        let account = Account()
        account.serverSessions = [session(1)]
        let context = ActiveSessionsContextImpl(account: account)
        var completed = false
        var failed = false
        let secret = context.updateSessionAcceptsSecretChats(session(1), accepts: true).start(completed: { completed = true })
        let calls = context.updateSessionAcceptsIncomingCalls(session(1), accepts: true).start(error: { _ in failed = true })
        defer { secret.dispose(); calls.dispose() }

        account.secretRequest.succeed()
        account.callsRequest.fail(.generic)
        XCTAssertTrue(completed)
        XCTAssertTrue(failed)
    }
}
