import Foundation
import SwiftSignalKit
import XCTest

typealias PeerId = Int
final class Peer { let id: Int; var displayTitle: String { "bot \(id)" }; init(_ id: Int) { self.id = id } }
struct EnginePeer { let peer: Peer; init(_ peer: Peer) { self.peer = peer } }
struct CachedUserData {
    struct Flags: OptionSet { let rawValue: Int; static let botCanManageEmojiStatus = Flags(rawValue: 1) }
    var flags: Flags = []
}
__PERMISSIONS__
enum Failure: Error { case generic }
final class Pending<T, E> {
    let subscriber: Subscriber<T, E>; var disposed = false; var onDispose: (() -> Void)?
    init(_ subscriber: Subscriber<T, E>) { self.subscriber = subscriber }
    func send(_ value: T) { subscriber.putNext(value) }
    func complete() { subscriber.putCompletion() }
    func fail(_ error: E) { subscriber.putError(error) }
    func dispose() { if !disposed { disposed = true; onDispose?() } }
}
final class Transaction {
    let box: Postbox; init(_ box: Postbox) { self.box = box }
    func getPeerCachedData(peerId: PeerId) -> Any? { box.allowed ? CachedUserData(flags: [.botCanManageEmojiStatus]) : nil }
    func getPeer(_ id: PeerId) -> Peer? { box.accountPeer }
}
final class Postbox {
    var allowed = false; var accountPeer: Peer? = Peer(1); var autoRead = true
    var reads: [Pending<(Bool, Peer?), NoError>] = []
    var values: [PeerId: WebAppPermissionsState] = [:]
    var writes: [(PeerId, (WebAppPermissionsState?) -> WebAppPermissionsState?, Pending<Never, NoError>)] = []
    var autoWrite = true
    func transaction(_ body: @escaping (Transaction) -> (Bool, Peer?)) -> Signal<(Bool, Peer?), NoError> {
        Signal { subscriber in
            let pending = Pending(subscriber); self.reads.append(pending)
            if self.autoRead { pending.send(body(Transaction(self))); pending.complete() }
            return ActionDisposable { pending.dispose() }
        }
    }
    func write(_ id: PeerId, _ update: @escaping (WebAppPermissionsState?) -> WebAppPermissionsState?) -> Signal<Never, NoError> {
        Signal { subscriber in
            let pending = Pending(subscriber); self.writes.append((id, update, pending))
            if self.autoWrite { self.values[id] = update(self.values[id]); pending.complete() }
            return ActionDisposable { pending.dispose() }
        }
    }
    func commit() { let (id, update, pending) = writes.last!; if !pending.disposed { values[id] = update(values[id]); pending.complete() } }
}
final class Account { let postbox = Postbox(); let peerId = 1 }
final class Peers {
    var requests: [(PeerId, Bool, Pending<Never, Failure>)] = []; var autoComplete = false; var onSubscribe: (() -> Void)?
    func toggleBotEmojiStatusAccess(peerId: PeerId, enabled: Bool) -> Signal<Never, Failure> {
        Signal { subscriber in
            let pending = Pending(subscriber); self.requests.append((peerId, enabled, pending)); self.onSubscribe?()
            if self.autoComplete { pending.complete() }
            return ActionDisposable { pending.dispose() }
        }
    }
}
final class Engine { let peers = Peers() }
protocol AccountContextProtocol: AnyObject { var account: Account { get }; var engine: Engine { get }; var myPeer: Peer? { get }; var isPremium: Bool { get } }
final class Context: AccountContextProtocol { let account = Account(); let engine = Engine(); var myPeer: Peer? = Peer(1); var isPremium = true }
func updateWebAppPermissionsStateInteractively(context: any AccountContextProtocol, peerId: PeerId, _ f: @escaping (WebAppPermissionsState?) -> WebAppPermissionsState?) -> Signal<Never, NoError> { context.account.postbox.write(peerId, f) }
func deliverOnMainQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { signal }
final class Queue {
    static let main = Queue(); var tasks: [() -> Void] = []
    static func mainQueue() -> Queue { main }
    func justDispatch(_ task: @escaping () -> Void) { tasks.append(task) }
    func drain() { while !tasks.isEmpty { let batch = tasks; tasks = []; batch.forEach { $0() } } }
}
struct TelegramPresentationTheme {}
let theme = TelegramPresentationTheme()
struct ModalAlertResult {}
struct ModalAlertData {
    enum Mode { case confirm(text: String, isThird: Bool) }
    struct Header { let id: String; let value: (Int, Int, TelegramPresentationTheme) -> BotEmojiStatusPermissionRowItem }
    init(title: String?, info: String, description: String?, ok: String, options: [Int], mode: Mode, header: Header) { _ = header.value(0, 0, theme) }
}
final class BotEmojiStatusPermissionRowItem { init(_ initialSize: Int, stableId: Int, peer: EnginePeer, context: any AccountContextProtocol) {} }
final class InputDataModalController {
    let completion: (ModalAlertResult) -> Void; let cancel: () -> Void; let onDeinit: (() -> Void)?; var closed = false
    init(completion: @escaping (ModalAlertResult) -> Void, cancel: @escaping () -> Void, onDeinit: (() -> Void)?) { self.completion = completion; self.cancel = cancel; self.onDeinit = onDeinit }
    func close() { if !closed { closed = true; onDeinit?() } }
    func choose(_ allowed: Bool) { close(); if allowed { completion(.init()) } else { cancel() } }
}
func ModalAlertController(data: ModalAlertData, completion: @escaping (ModalAlertResult) -> Void, cancel: @escaping () -> Void = {}, onDeinit: (() -> Void)?, presentation: TelegramPresentationTheme) -> InputDataModalController { .init(completion: completion, cancel: cancel, onDeinit: onDeinit) }
enum Animation { case scaleCenter }
final class Window {
    var prompts: [InputDataModalController] = []; var texts: [String] = []; var onToast: (() -> Void)?
    func removeObserver(for object: AnyObject) {}
}
func showModal(with controller: InputDataModalController, for window: Window, animationType: Animation) { window.prompts.append(controller) }
__ALERT__
func showModalAlert(for window: Window, data: ModalAlertData, completion: @escaping (ModalAlertResult) -> Void, cancel: @escaping () -> Void = {}, onDeinit: (() -> Void)? = nil) { showModal(with: ModalAlertController(data: data, completion: completion, cancel: cancel, onDeinit: onDeinit, presentation: theme), for: window, animationType: .scaleCenter) }
struct Strings {
    let webappEmojiStatusRequestedAllow = "allow", webappEmojiStatusRequestedDecline = "decline"
    func webappEmojiStatusRequested(_ a: String, _ b: String) -> String { a + b }
    func webappEmojiStatusAllowed(_ name: String) -> String { name }
}
func strings() -> Strings { .init() }
func showModalText(for window: Window, text: String) { window.texts.append(text); window.onToast?() }
final class BrowserHooks { static let shared = BrowserHooks(); var premiumCount = 0; func openPremiumBoarding(_ context: any AccountContextProtocol, _ window: Window) { premiumCount += 1 } }
struct JSON {
    let data: [String: Any]
    init?(dictionary: [String: Any]) { data = dictionary }
    var string: String? { (try? JSONSerialization.data(withJSONObject: data)).flatMap { String(data: $0, encoding: .utf8) } }
}
var testTimestamp: Double = 100
func CACurrentMediaTime() -> Double { testTimestamp }
__SOURCE__
class BaseController { func viewWillDisappear(_ animated: Bool) {}; func viewWillAppear(_ animated: Bool) {} }
final class Resettable { func reset() {} }
final class Controller: BaseController {
    var lastTouchTimestamp: Double? = 100
    let context = Context(); var bot: Peer? = Peer(10); var window: Window? = Window()
    let emojiPermissionAction = BrowserEmojiPermissionAction(); var acceptsLocationRequests = true
    let emojiStatusAction = Resettable()
    let locationAction = Resettable(); let preparedShareAction = Resettable(); let apperanceDisposable = MetaDisposable()
    var events: [(String, [String: Any]?)] = []
    func sendEvent(name: String, data: String?) { let object = data?.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }; events.append((name, object)) }
    func cancelPendingInvoices() {}
    __METHODS__
    var box: Postbox { context.account.postbox }
    var requests: [(PeerId, Bool, Pending<Never, Failure>)] { context.engine.peers.requests }
    var prompt: InputDataModalController? { window?.prompts.last }
    var status: String? { events.last?.1?["status"] as? String }
}

final class BrowserEmojiPermissionTests: XCTestCase {
    override func setUp() { Queue.main.tasks = []; testTimestamp = 100; BrowserHooks.shared.premiumCount = 0 }
    override func tearDown() { Queue.main.drain() }
    func testRequiresRecentUserClick() { let c = Controller(); c.lastTouchTimestamp = nil; c.requestEmojiStatusAccess(); c.lastTouchTimestamp = 89; c.requestEmojiStatusAccess(); c.lastTouchTimestamp = 101; c.requestEmojiStatusAccess(); XCTAssertTrue(c.window!.prompts.isEmpty); XCTAssertTrue(c.events.isEmpty) }
    func testTenSecondBoundaryIsAllowed() { let c = Controller(); c.lastTouchTimestamp = 90; c.requestEmojiStatusAccess(); XCTAssertEqual(c.window!.prompts.count, 1) }
    func testAlreadyGrantedDoesNotPromptOrCallServer() { let c = Controller(); c.box.allowed = true; c.requestEmojiStatusAccess(); XCTAssertEqual(c.status, "allowed"); XCTAssertTrue(c.window!.prompts.isEmpty); XCTAssertTrue(c.requests.isEmpty); XCTAssertTrue(c.window!.texts.isEmpty) }
    func testAlreadyGrantedDoesNotRequireAccountPeerOrPremium() { let c = Controller(); c.box.allowed = true; c.context.myPeer = nil; c.box.accountPeer = nil; c.context.isPremium = false; c.requestEmojiStatusAccess(); XCTAssertEqual(c.status, "allowed") }
    func testMissingAccountPeerReturnsCancelled() { let c = Controller(); c.context.myPeer = nil; c.box.accountPeer = nil; c.requestEmojiStatusAccess(); XCTAssertEqual(c.status, "cancelled"); XCTAssertTrue(c.window!.prompts.isEmpty) }
    func testReadsAccountPeerWhenContextHasNotLoadedIt() { let c = Controller(); c.context.myPeer = nil; c.requestEmojiStatusAccess(); XCTAssertEqual(c.window!.prompts.count, 1) }
    func testEmptyPermissionReadReturnsCancelled() { let c = Controller(); c.box.autoRead = false; c.requestEmojiStatusAccess(); c.box.reads.last!.complete(); XCTAssertEqual(c.status, "cancelled") }
    func testReadCancellationSuppressesPrompt() { let c = Controller(); c.box.autoRead = false; c.requestEmojiStatusAccess(); let read = c.box.reads.last!; c.cancelPendingPageActions(); XCTAssertTrue(read.disposed); read.send((false, Peer(1))); XCTAssertTrue(c.window!.prompts.isEmpty); XCTAssertTrue(c.events.isEmpty) }
    func testDuplicateRequestsSharePendingPrompt() { let c = Controller(); c.requestEmojiStatusAccess(); c.requestEmojiStatusAccess(); XCTAssertEqual(c.window!.prompts.count, 1) }
    func testDuplicateRequestsWhileGrantPendingAreIgnored() { let c = Controller(); c.requestEmojiStatusAccess(); c.prompt!.choose(true); c.requestEmojiStatusAccess(); XCTAssertEqual(c.window!.prompts.count, 1); XCTAssertEqual(c.requests.count, 1) }
    func testNoSuccessBeforeServerAcknowledgement() { let c = Controller(); c.requestEmojiStatusAccess(); c.prompt!.choose(true); Queue.main.drain(); XCTAssertTrue(c.events.isEmpty); XCTAssertTrue(c.window!.texts.isEmpty); c.requests.last!.2.complete(); XCTAssertEqual(c.status, "allowed"); XCTAssertEqual(c.events.count, 1); XCTAssertEqual(c.window!.texts, ["bot 10"]) }
    func testServerFailureReportsCancelledWithoutSuccessToast() { let c = Controller(); c.requestEmojiStatusAccess(); c.prompt!.choose(true); c.requests.last!.2.fail(.generic); Queue.main.drain(); XCTAssertEqual(c.status, "cancelled"); XCTAssertEqual(c.events.count, 1); XCTAssertTrue(c.window!.texts.isEmpty) }
    func testDeclineReportsCancelledAndPreservesLocation() { let c = Controller(); c.box.values[10] = .init(location: .init(isRequested: true, isAllowed: true), emojiStatus: nil); c.requestEmojiStatusAccess(); c.prompt!.choose(false); Queue.main.drain(); XCTAssertEqual(c.status, "cancelled"); XCTAssertTrue(c.requests.isEmpty); XCTAssertEqual(c.box.values[10]?.location?.isAllowed, true); XCTAssertEqual(c.box.values[10]?.emojiStatus?.isRequested, true) }
    func testDismissReportsCancelledWithoutSavingChoice() { let c = Controller(); c.requestEmojiStatusAccess(); c.prompt!.close(); Queue.main.drain(); XCTAssertEqual(c.status, "cancelled"); XCTAssertEqual(c.events.count, 1); XCTAssertTrue(c.box.writes.isEmpty); XCTAssertTrue(c.requests.isEmpty) }
    func testPromptDeinitBeforeConfirmationDoesNotCancelAcceptedChoice() { let c = Controller(); c.requestEmojiStatusAccess(); c.prompt!.choose(true); Queue.main.drain(); XCTAssertTrue(c.events.isEmpty); c.requests.last!.2.complete(); XCTAssertEqual(c.status, "allowed") }
    func testNonPremiumChoiceOpensPremiumAndReportsCancelled() { let c = Controller(); c.context.isPremium = false; c.requestEmojiStatusAccess(); c.prompt!.choose(true); Queue.main.drain(); XCTAssertEqual(BrowserHooks.shared.premiumCount, 1); XCTAssertEqual(c.status, "cancelled"); XCTAssertTrue(c.requests.isEmpty) }
    func testExplicitChoiceWaitsForPersistenceBeforeGrant() { let c = Controller(); c.box.autoWrite = false; c.requestEmojiStatusAccess(); c.prompt!.choose(true); Queue.main.drain(); XCTAssertTrue(c.requests.isEmpty); c.box.commit(); XCTAssertEqual(c.requests.count, 1) }
    func testResetDuringPersistenceSuppressesGrant() { let c = Controller(); c.box.autoWrite = false; c.requestEmojiStatusAccess(); c.prompt!.choose(true); c.cancelPendingPageActions(); c.box.commit(); XCTAssertTrue(c.requests.isEmpty); XCTAssertTrue(c.events.isEmpty); XCTAssertNil(c.box.values[10]) }
    func testResetDismissesPromptAndIgnoresLateChoice() { let c = Controller(); c.requestEmojiStatusAccess(); let p = c.prompt!; c.cancelPendingPageActions(); XCTAssertTrue(p.closed); p.choose(true); Queue.main.drain(); XCTAssertTrue(c.requests.isEmpty); XCTAssertTrue(c.events.isEmpty) }
    func testResetCancelsGrantAndSuppressesLateResult() { let c = Controller(); c.requestEmojiStatusAccess(); c.prompt!.choose(true); let rpc = c.requests.last!.2; c.cancelPendingPageActions(); XCTAssertTrue(rpc.disposed); rpc.complete(); Queue.main.drain(); XCTAssertTrue(c.events.isEmpty); XCTAssertTrue(c.window!.texts.isEmpty) }
    func testDisappearCancelsPromptAndClearsGesture() { let c = Controller(); c.requestEmojiStatusAccess(); let p = c.prompt!; c.viewWillDisappear(false); XCTAssertTrue(p.closed); XCTAssertNil(c.lastTouchTimestamp); p.choose(true); XCTAssertTrue(c.requests.isEmpty); c.viewWillAppear(false); c.requestEmojiStatusAccess(); XCTAssertEqual(c.window!.prompts.count, 1) }
    func testHiddenPageCannotOpenPrompt() { let c = Controller(); c.viewWillDisappear(false); c.lastTouchTimestamp = 100; c.requestEmojiStatusAccess(); XCTAssertTrue(c.window!.prompts.isEmpty) }
    func testChangedBotCannotGrantOldBotPermission() { let c = Controller(); c.requestEmojiStatusAccess(); let p = c.prompt!; c.bot = Peer(20); p.choose(true); Queue.main.drain(); XCTAssertTrue(c.requests.isEmpty); XCTAssertTrue(c.events.isEmpty) }
    func testChangedWindowCannotGrantOldPermission() { let c = Controller(); c.requestEmojiStatusAccess(); let oldWindow = c.window!; c.window = Window(); oldWindow.prompts[0].choose(true); XCTAssertTrue(c.requests.isEmpty); XCTAssertTrue(c.events.isEmpty) }
    func testMissingBotOrWindowReturnsCancelled() { let c = Controller(); c.bot = nil; c.requestEmojiStatusAccess(); XCTAssertEqual(c.status, "cancelled"); c.bot = Peer(10); c.window = nil; c.requestEmojiStatusAccess(); XCTAssertEqual(c.events.count, 2) }
    func testRepeatedChoiceOnlyStartsOneGrant() { let c = Controller(); c.requestEmojiStatusAccess(); let p = c.prompt!; p.choose(true); p.choose(true); p.choose(false); Queue.main.drain(); XCTAssertEqual(c.requests.count, 1); XCTAssertTrue(c.events.isEmpty) }
    func testSynchronousCompletionLeavesActionReusable() { let c = Controller(); c.context.engine.peers.autoComplete = true; c.requestEmojiStatusAccess(); c.prompt!.choose(true); c.requestEmojiStatusAccess(); c.prompt!.choose(true); Queue.main.drain(); XCTAssertEqual(c.events.count, 2); XCTAssertEqual(c.window!.texts.count, 2) }
    func testOldDismissalCannotCancelNewPrompt() { let c = Controller(); c.requestEmojiStatusAccess(); c.prompt!.choose(false); c.requestEmojiStatusAccess(); let p = c.prompt!; Queue.main.drain(); XCTAssertFalse(p.closed); p.choose(true); c.requests.last!.2.complete(); XCTAssertEqual(c.events.count, 2); XCTAssertEqual(c.status, "allowed") }
    func testControllerReleasedWithPromptRetained() { var c: Controller? = Controller(); c!.requestEmojiStatusAccess(); let p = c!.prompt!; weak var weakController = c; c = nil; XCTAssertNil(weakController); XCTAssertTrue(p.closed); p.choose(true) }
    func testControllerReleasedDuringNetworkRequest() { var c: Controller? = Controller(); c!.requestEmojiStatusAccess(); c!.prompt!.choose(true); let rpc = c!.requests.last!.2; weak var weakController = c; c = nil; XCTAssertNil(weakController); XCTAssertTrue(rpc.disposed) }
    func testCancellationDuringSubscriptionOwnsReturnedDisposable() { let c = Controller(); c.context.engine.peers.onSubscribe = { c.cancelPendingPageActions() }; c.requestEmojiStatusAccess(); c.prompt!.choose(true); XCTAssertTrue(c.requests.last!.2.disposed); XCTAssertTrue(c.events.isEmpty); c.context.engine.peers.onSubscribe = nil }
    func testResetReenteredDuringCompletionDisposalSuppressesSuccess() { let c = Controller(); c.requestEmojiStatusAccess(); c.prompt!.choose(true); let rpc = c.requests.last!.2; rpc.onDispose = { c.cancelPendingPageActions() }; rpc.complete(); XCTAssertTrue(c.events.isEmpty); XCTAssertTrue(c.window!.texts.isEmpty); rpc.onDispose = nil }
    func testResetDuringToastSuppressesEvent() { let c = Controller(); c.requestEmojiStatusAccess(); c.prompt!.choose(true); c.window!.onToast = { c.cancelPendingPageActions() }; c.requests.last!.2.complete(); XCTAssertTrue(c.events.isEmpty); c.window!.onToast = nil }
    func testOldCompletionCannotClearReentrantNewRequest() { let c = Controller(); c.requestEmojiStatusAccess(); c.prompt!.choose(true); let rpc = c.requests.last!.2; rpc.onDispose = { c.cancelPendingPageActions(); c.lastTouchTimestamp = 100; c.requestEmojiStatusAccess() }; rpc.complete(); rpc.onDispose = nil; let p = c.prompt!; XCTAssertFalse(p.closed); p.choose(true); XCTAssertEqual(c.requests.count, 2); c.requests.last!.2.complete(); XCTAssertEqual(c.events.count, 1) }
}
