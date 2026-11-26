import Foundation
import SwiftSignalKit
import XCTest

typealias PeerId = Int
struct Peer { let id: Int; var inputAvailable = true }
func apiInputUser(_ peer: Peer) -> Int? { peer.inputAvailable ? peer.id : nil }
struct CachedUserFlags: OptionSet, Equatable { let rawValue: Int; static let botCanManageEmojiStatus = Self(rawValue: 1); static let other = Self(rawValue: 2) }
class CachedPeerData {}
final class CachedUserData: CachedPeerData {
    let flags: CachedUserFlags; let about: String
    init(flags: CachedUserFlags = [], about: String = "") { self.flags = flags; self.about = about }
    func withUpdatedFlags(_ flags: CachedUserFlags) -> CachedUserData { .init(flags: flags, about: about) }
}
final class Transaction {
    unowned let postbox: Postbox
    init(_ postbox: Postbox) { self.postbox = postbox }
    func getPeer(_ id: Int) -> Peer? { postbox.peers[id] }
    func updatePeerCachedData(peerIds: Set<Int>, update: (Int, CachedPeerData?) -> CachedPeerData?) { for id in peerIds { postbox.cached[id] = update(id, postbox.cached[id]); postbox.writes += 1 } }
}
final class Postbox {
    var peers: [Int: Peer] = [10: .init(id: 10), 20: .init(id: 20)]
    var cached: [Int: CachedPeerData] = [10: CachedUserData(flags: [.botCanManageEmojiStatus, .other], about: "kept")]
    var tasks: [() -> Void] = []; var writes = 0
    func transaction<T>(_ body: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            self.tasks.append { let result = body(Transaction(self)); subscriber.putNext(result); subscriber.putCompletion() }
            return EmptyDisposable
        }
    }
    func drain() { while !tasks.isEmpty { tasks.removeFirst()() } }
}
enum Api {
    enum Bool { case boolTrue, boolFalse }
    struct Request { let bot: Int; let enabled: Bool }
    enum functions { enum bots { static func toggleUserEmojiStatusPermission(bot: Int, enabled: Bool) -> Request { .init(bot: bot, enabled: enabled) } } }
}
enum RpcError { case failure }
final class Pending {
    let request: Api.Request; let subscriber: Subscriber<Api.Bool, RpcError>; var cancelled = false
    init(_ request: Api.Request, _ subscriber: Subscriber<Api.Bool, RpcError>) { self.request = request; self.subscriber = subscriber }
    func respond(_ value: Api.Bool) { subscriber.putNext(value); subscriber.putCompletion() }
    func fail() { subscriber.putError(.failure) }
    func complete() { subscriber.putCompletion() }
}
final class Network {
    var pending: [Pending] = []
    var onStart: ((Pending) -> Void)?
    func request(_ request: Api.Request) -> Signal<Api.Bool, RpcError> {
        Signal { subscriber in
            let pending = Pending(request, subscriber); self.pending.append(pending); self.onStart?(pending)
            return ActionDisposable { pending.cancelled = true }
        }
    }
}
final class Account { let postbox = Postbox(); let network = Network() }
__CORE__
final class Window { func removeAllHandlers(for object: AnyObject) {}
    var errors: [String] = []; var progress: [MetaDisposable] = [] }
func alert(for window: Window, info: String) { window.errors.append(info) }
func deliverOnMainQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { signal }
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> {
    Signal { subscriber in
        let pending = MetaDisposable(); window.progress.append(pending)
        pending.set(signal.start(next: subscriber.putNext, error: subscriber.putError, completed: subscriber.putCompletion))
        return pending
    }
}
final class Queue {
    static let main = Queue(); var tasks: [() -> Void] = []
    static func mainQueue() -> Queue { main }
    func async(_ f: @escaping () -> Void) { tasks.append(f) }
    func drain() { while !tasks.isEmpty { tasks.removeFirst()() } }
}
struct Strings { let unknownError = "error"; let peerInfoBotPermissionsStatus = "status" }
func strings() -> Strings { .init() }
final class Context {
    final class Peers {
        let account: Account; init(_ account: Account) { self.account = account }
        func toggleBotEmojiStatusAccess(peerId: Int, enabled: Bool) -> Signal<Never, ToggleBotEmojiStatusAccessError> { _internal_toggleBotEmojiStatusAccess(account: account, peerId: peerId, enabled: enabled) }
    }
    final class Engine { let peers: Peers; init(_ account: Account) { peers = .init(account) } }
    let account = Account(); let window = Window(); lazy var engine = Engine(account)
}
final class Profile {
    let context: Context; let peerId: Int
    let botEmojiStatusDisposable = MetaDisposable(); var botEmojiStatusOperationId: UUID?
    var acceptsEmojiPermissionRequests = true
    init(_ context: Context = Context(), peerId: Int = 10) { self.context = context; self.peerId = peerId }
    __PROFILE__
    deinit { __DISPOSE__ }
}
class BaseController {
    var onDisappear: (() -> Void)?
    func viewWillDisappear(_ animated: Bool) { onDisappear?() }
    func viewWillAppear(_ animated: Bool) {}
}
struct PeerInfoNavigationHooks {
    static let shared = Self()
    func prefetchQrStudio(_ context: Context, _ peer: Int) {}
}
final class ProfileController: BaseController {
    let context: Context; var _userArguments: Profile?; let peer = 10
    var window: Window? { context.window }
    enum State { case Edit, normal }
    let initialState = State.normal
    func update(with state: State) {}
    init(_ context: Context = Context()) { self.context = context; self._userArguments = Profile(context) }
    __LIFECYCLE__
}
struct TelegramThemeHooks {
    static let shared = Self(); enum Image { case iconPeerInfoBotStatus }
    func image(_ image: Image) -> Int { 0 }
}
extension Int { func precomposed(flipVertical: Bool) -> Int { self } }
struct GeneralInteractedRowItem {
    enum Kind { case switchable(Bool) }
    let action: () -> Void; let autoswitch: Bool
    init(_ size: Int, stableId: Int, name: String, icon: Int, type: Kind, viewType: Int, action: @escaping () -> Void, autoswitch: Bool = true) { self.action = action; self.autoswitch = autoswitch }
}
func row(_ arguments: Profile, value: Bool) -> GeneralInteractedRowItem {
    let initialSize = 0, stableId = 0, viewType = 0
    __ROW__
}
final class Outcome {
    var errors = 0; var completions = 0
    func start(_ account: Account, peer: Int = 10, enabled: Bool = false) -> Disposable { _internal_toggleBotEmojiStatusAccess(account: account, peerId: peer, enabled: enabled).start(error: { _ in self.errors += 1 }, completed: { self.completions += 1 }) }
}

final class BotEmojiPermissionTests: XCTestCase {
    override func setUp() { Queue.main.drain() }
    override func tearDown() { Queue.main.drain() }
    func flags(_ a: Account, _ id: Int = 10) -> CachedUserFlags? { (a.postbox.cached[id] as? CachedUserData)?.flags }
    func testDisappearCancelsBeforeReentrantError() {
        let c = ProfileController(); c._userArguments?.togglePermissionsStatus(); c.context.account.postbox.drain(); let pending = c.context.account.network.pending[0]
        c.onDisappear = { pending.fail() }; c.viewWillDisappear(false)
        XCTAssertTrue(pending.cancelled); XCTAssertTrue(c.context.window.errors.isEmpty)
    }
    func testHiddenProfileRejectsRequestsAndReappearanceEnablesThem() {
        let c = ProfileController(); c.viewWillDisappear(false); c._userArguments?.togglePermissionsStatus(); c.context.account.postbox.drain(); XCTAssertTrue(c.context.account.network.pending.isEmpty)
        c.viewWillAppear(false); c._userArguments?.togglePermissionsStatus(); c.context.account.postbox.drain(); XCTAssertEqual(c.context.account.network.pending.count, 1); c.context.account.network.pending.last?.fail()
    }
    func testAcknowledgedRevokeSurvivesProfileDisappearance() {
        let c = ProfileController(); c._userArguments?.togglePermissionsStatus(); c.context.account.postbox.drain(); c.context.account.network.pending[0].respond(.boolTrue)
        c.viewWillDisappear(false); c.context.account.postbox.drain(); XCTAssertEqual(flags(c.context.account), [.other]); XCTAssertTrue(c.context.window.errors.isEmpty)
    }
    func testFalseResponseIsFailureWithoutCacheWrite() { let a = Account(), o = Outcome(); let d = o.start(a); a.postbox.drain(); a.network.pending[0].respond(.boolFalse); a.postbox.drain(); XCTAssertEqual(o.errors, 1); XCTAssertEqual(o.completions, 0); XCTAssertEqual(a.postbox.writes, 0); XCTAssertEqual(flags(a), [.botCanManageEmojiStatus, .other]); d.dispose() }
    func testEmptyResponseIsFailureWithoutCacheWrite() { let a = Account(), o = Outcome(); let d = o.start(a); a.postbox.drain(); a.network.pending[0].complete(); a.postbox.drain(); XCTAssertEqual(o.errors, 1); XCTAssertEqual(o.completions, 0); XCTAssertEqual(a.postbox.writes, 0); d.dispose() }
    func testNetworkErrorDoesNotChangePermission() { let a = Account(), o = Outcome(); let d = o.start(a); a.postbox.drain(); a.network.pending[0].fail(); a.postbox.drain(); XCTAssertEqual(o.errors, 1); XCTAssertEqual(o.completions, 0); XCTAssertEqual(flags(a), [.botCanManageEmojiStatus, .other]); d.dispose() }
    func testTrueResponseRevokesOnlyTargetFlagBeforeCompletion() { let a = Account(), o = Outcome(); let d = o.start(a); a.postbox.drain(); a.network.pending[0].respond(.boolTrue); XCTAssertEqual(o.completions, 0); a.postbox.drain(); XCTAssertEqual(flags(a), [.other]); XCTAssertEqual((a.postbox.cached[10] as? CachedUserData)?.about, "kept"); XCTAssertEqual(o.completions, 1); XCTAssertEqual(o.errors, 0); d.dispose() }
    func testGrantCreatesMissingCachedUserData() { let a = Account(), o = Outcome(); let d = o.start(a, peer: 20, enabled: true); a.postbox.drain(); a.network.pending[0].respond(.boolTrue); a.postbox.drain(); XCTAssertEqual(flags(a, 20), [.botCanManageEmojiStatus]); XCTAssertEqual(o.completions, 1); d.dispose() }
    func testCommitUsesLatestOtherFlagsAndFields() { let a = Account(), o = Outcome(); let d = o.start(a, enabled: true); a.postbox.drain(); a.network.pending[0].respond(.boolTrue); a.postbox.cached[10] = CachedUserData(flags: [.other], about: "updated"); a.postbox.drain(); XCTAssertEqual(flags(a), [.botCanManageEmojiStatus, .other]); XCTAssertEqual((a.postbox.cached[10] as? CachedUserData)?.about, "updated"); d.dispose() }
    func testMissingPeerFailsWithoutRPC() { let a = Account(), o = Outcome(); a.postbox.peers[10] = nil; let d = o.start(a); a.postbox.drain(); XCTAssertEqual(o.errors, 1); XCTAssertTrue(a.network.pending.isEmpty); d.dispose() }
    func testUnusablePeerFailsWithoutRPC() { let a = Account(), o = Outcome(); a.postbox.peers[10] = .init(id: 10, inputAvailable: false); let d = o.start(a); a.postbox.drain(); XCTAssertEqual(o.errors, 1); XCTAssertTrue(a.network.pending.isEmpty); d.dispose() }
    func testCancelledLookupDoesNotStartRPC() { let a = Account(), o = Outcome(); let d = o.start(a); d.dispose(); a.postbox.drain(); XCTAssertTrue(a.network.pending.isEmpty); XCTAssertEqual(o.completions + o.errors, 0) }
    func testCancelledNetworkDoesNotPublishLateResponse() { let a = Account(), o = Outcome(); let d = o.start(a); a.postbox.drain(); let p = a.network.pending[0]; d.dispose(); XCTAssertTrue(p.cancelled); p.respond(.boolTrue); a.postbox.drain(); XCTAssertEqual(a.postbox.writes, 0); XCTAssertEqual(o.completions + o.errors, 0) }
    func testAcknowledgedPermissionStillCommitsAfterObserverCancels() { let a = Account(), o = Outcome(); let d = o.start(a); a.postbox.drain(); a.network.pending[0].respond(.boolTrue); d.dispose(); a.postbox.drain(); XCTAssertEqual(flags(a), [.other]); XCTAssertEqual(o.completions + o.errors, 0) }
    func testSynchronousResponseAndCompletionOnlyCommitOnce() { let a = Account(), o = Outcome(); a.network.onStart = { $0.respond(.boolTrue) }; let d = o.start(a); a.postbox.drain(); XCTAssertEqual(o.completions, 1); XCTAssertEqual(o.errors, 0); XCTAssertEqual(a.postbox.writes, 1); d.dispose() }
    func testForeignCachedTypeIsNotOverwritten() { let a = Account(), o = Outcome(); let cached = CachedPeerData(); a.postbox.cached[10] = cached; let d = o.start(a); a.postbox.drain(); a.network.pending[0].respond(.boolTrue); a.postbox.drain(); XCTAssertTrue(a.postbox.cached[10] === cached); d.dispose() }
    func testSignalDoesNotRetainAccount() { var a: Account? = Account(); weak var weakAccount = a; let box = a!.postbox, network = a!.network; let signal = _internal_toggleBotEmojiStatusAccess(account: a!, peerId: 10, enabled: false); a = nil; XCTAssertNil(weakAccount); let d = signal.start(); box.drain(); network.pending[0].fail(); d.dispose() }
    func testProfileSwitchDoesNotFlipBeforeConfirmation() { let p = Profile(); XCTAssertFalse(row(p, value: true).autoswitch) }
    func testProfileSuppressesRepeatedClicksDuringRequest() { let p = Profile(); p.togglePermissionsStatus(); p.togglePermissionsStatus(); p.context.account.postbox.drain(); XCTAssertEqual(p.context.account.network.pending.count, 1); p.context.account.network.pending[0].fail() }
    func testProfileErrorShowsFailureAndAllowsRetry() { let p = Profile(); p.togglePermissionsStatus(); p.context.account.postbox.drain(); p.context.account.network.pending[0].fail(); XCTAssertEqual(p.context.window.errors, ["error"]); p.togglePermissionsStatus(); p.context.account.postbox.drain(); XCTAssertEqual(p.context.account.network.pending.count, 2); p.context.account.network.pending[1].fail() }
    func testProfileFalseResponseShowsFailure() { let p = Profile(); p.togglePermissionsStatus(); p.context.account.postbox.drain(); p.context.account.network.pending[0].respond(.boolFalse); p.context.account.postbox.drain(); XCTAssertEqual(p.context.window.errors, ["error"]); XCTAssertEqual(flags(p.context.account), [.botCanManageEmojiStatus, .other]) }
    func testProfileSuccessReleasesBusyStateAfterCommit() { let p = Profile(); p.togglePermissionsStatus(); p.context.account.postbox.drain(); p.context.account.network.pending[0].respond(.boolTrue); XCTAssertNotNil(p.botEmojiStatusOperationId); p.context.account.postbox.drain(); XCTAssertNil(p.botEmojiStatusOperationId); XCTAssertTrue(p.context.window.errors.isEmpty) }
    func testProgressCancellationAllowsRetryWithoutError() { let p = Profile(); p.togglePermissionsStatus(); p.context.account.postbox.drain(); p.context.window.progress.first?.dispose(); Queue.main.drain(); p.togglePermissionsStatus(); p.context.account.postbox.drain(); XCTAssertEqual(p.context.account.network.pending.count, 2); XCTAssertTrue(p.context.window.errors.isEmpty); p.context.account.network.pending.last?.fail() }
    func testOldQueuedCleanupCannotClearNewRequest() { let p = Profile(); p.togglePermissionsStatus(); p.context.account.postbox.drain(); p.context.account.network.pending[0].fail(); p.togglePermissionsStatus(); let id = p.botEmojiStatusOperationId; Queue.main.drain(); XCTAssertEqual(p.botEmojiStatusOperationId, id); p.togglePermissionsStatus(); p.context.account.postbox.drain(); XCTAssertEqual(p.context.account.network.pending.count, 2); p.context.account.network.pending.last?.fail() }
    func testProfileDeinitCancelsPendingNetwork() { let c = Context(); var p: Profile? = Profile(c); weak var weakProfile = p; p!.togglePermissionsStatus(); c.account.postbox.drain(); p = nil; XCTAssertNil(weakProfile); XCTAssertTrue(c.account.network.pending[0].cancelled) }
    func testProfileCapturesOriginalPeer() { let c = Context(); let p = Profile(c, peerId: 20); p.togglePermissionsStatus(); c.account.postbox.drain(); XCTAssertEqual(c.account.network.pending.first?.request.bot, 20); c.account.network.pending[0].respond(.boolTrue); c.account.postbox.drain(); XCTAssertEqual(flags(c.account), [.botCanManageEmojiStatus, .other]); XCTAssertEqual(flags(c.account, 20), []) }
}
