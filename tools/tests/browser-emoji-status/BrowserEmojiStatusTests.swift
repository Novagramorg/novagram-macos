import Foundation
import CoreFoundation
import SwiftSignalKit
import XCTest

typealias PeerId = Int
class Peer { let id: Int; init(_ id: Int) { self.id = id } }
struct EnginePeer { let peer: Peer; init(_ peer: Peer) { self.peer = peer } }
struct MediaId: Equatable { let id: Int64 }
final class TelegramMediaFile { let fileId: MediaId; var isCustomEmoji = true; init(_ id: Int64) { fileId = .init(id: id) } }
struct PeerEmojiStatus: Equatable { enum Content: Equatable { case emoji(fileId: Int64) }; let content: Content; let expirationDate: Int32? }
final class TelegramUser: Peer {
    let name: String; let status: PeerEmojiStatus?
    init(_ id: Int, name: String = "current", status: PeerEmojiStatus? = nil) { self.name = name; self.status = status; super.init(id) }
    func withUpdatedEmojiStatus(_ status: PeerEmojiStatus?) -> TelegramUser { .init(id, name: name, status: status) }
}
struct RecentMediaItem { let file: TelegramMediaFile; init(_ file: TelegramMediaFile) { self.file = file } }
struct RecentMediaItemId { let rawValue: Int64; init(_ id: MediaId) { rawValue = id.id } }
struct CodableEntry { let value: RecentMediaItem; init?(_ value: RecentMediaItem) { self.value = value } }
struct OrderedItemListEntry { let id: Int64; let contents: CodableEntry }
enum Namespaces { enum OrderedItemList { static let CloudRecentStatusEmoji = 1 } }
struct Settings { var focusIntentStatusEnabled = true; var focusIntentStatusFallback: Int? = 123; var other = 456 }
final class Transaction {
    unowned let postbox: Postbox; init(_ postbox: Postbox) { self.postbox = postbox }
    func getPeer(_ id: Int) -> Peer? { postbox.peers[id] }
    func storeMediaIfNotPresent(media: TelegramMediaFile) { if postbox.media[media.fileId.id] == nil { postbox.media[media.fileId.id] = media } }
    func addOrMoveToFirstPositionOrderedItemListItem(collectionId: Int, item: OrderedItemListEntry, removeTailIfCountExceeds: Int) { postbox.recent.removeAll { $0 == item.id }; postbox.recent.insert(item.id, at: 0); postbox.recent = Array(postbox.recent.prefix(removeTailIfCountExceeds)) }
}
func updatePeersCustom(transaction: Transaction, peers: [TelegramUser], update: (TelegramUser?, TelegramUser) -> TelegramUser) { for peer in peers { transaction.postbox.peers[peer.id] = update(transaction.postbox.peers[peer.id] as? TelegramUser, peer) } }
final class Postbox {
    var peers: [Int: Peer] = [1: TelegramUser(1)]; var media: [Int64: TelegramMediaFile] = [:]; var recent: [Int64] = []; var settings = Settings()
    var autoCommit = true; var tasks: [() -> Void] = []
    func transaction<T>(_ body: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            let run = { let result = body(Transaction(self)); subscriber.putNext(result); subscriber.putCompletion() }
            if self.autoCommit { run() } else { self.tasks.append(run) }
            return EmptyDisposable
        }
    }
    func drain() { while !tasks.isEmpty { tasks.removeFirst()() } }
}
enum Api {
    enum Bool { case boolTrue, boolFalse }
    struct Status { let flags: Int32; let documentId: Int64; let until: Int32? }
    enum EmojiStatus { case emojiStatus(Status), emojiStatusEmpty }
    enum functions { enum account { static func updateEmojiStatus(emojiStatus: EmojiStatus) -> EmojiStatus { emojiStatus } } }
}
enum RpcError { case generic }
final class Pending<T, E> {
    let subscriber: Subscriber<T, E>; var disposed = false; var onDispose: (() -> Void)?
    init(_ subscriber: Subscriber<T, E>) { self.subscriber = subscriber }
    func send(_ value: T) { subscriber.putNext(value) }
    func respond(_ value: T) { subscriber.putNext(value); subscriber.putCompletion() }
    func complete() { subscriber.putCompletion() }
    func fail(_ error: E) { subscriber.putError(error) }
    func dispose() { if !disposed { disposed = true; onDispose?() } }
}
protocol NetworkRequestDependencyTag { func shouldDependOn(other: NetworkRequestDependencyTag) -> Bool }
final class Network {
    var requests: [(Api.EmojiStatus, Pending<Api.Bool, RpcError>)] = []; var onSubscribe: (() -> Void)?
    func request(_ request: Api.EmojiStatus, tag: NetworkRequestDependencyTag? = nil) -> Signal<Api.Bool, RpcError> {
        Signal { subscriber in
            let pending = Pending(subscriber); self.requests.append((request, pending)); self.onSubscribe?()
            return ActionDisposable { pending.dispose() }
        }
    }
}
final class Account { let peerId = 1; let postbox = Postbox(); let network = Network() }
enum SetEmojiStatusError { case generic }
__CORE_SUPPORT__
final class AccountData {
    let account: Account; init(_ account: Account) { self.account = account }
    __CORE__
}
final class Engine { let accountData: AccountData; init(_ account: Account) { accountData = AccountData(account) } }
final class InlinePacks {
    var pending: [Pending<TelegramMediaFile?, NoError>] = []; var ids: [Int64] = []; var synchronous: TelegramMediaFile?
    func load(fileId: Int64) -> Signal<TelegramMediaFile?, NoError> {
        Signal { subscriber in
            let pending = Pending(subscriber); self.pending.append(pending); self.ids.append(fileId)
            if let file = self.synchronous { pending.send(file) }
            return ActionDisposable { pending.dispose() }
        }
    }
}
protocol AccountContextProtocol: AnyObject { var account: Account { get }; var engine: Engine { get }; var inlinePacksContext: InlinePacks { get }; var timestamp: Int32 { get }; var isPremium: Bool { get } }
final class Context: AccountContextProtocol {
    let account = Account(); lazy var engine = Engine(account); let inlinePacksContext = InlinePacks(); var timestamp: Int32 = 1_700_000_000; var isPremium = true
}
func updateSomeSettingsInteractively(postbox: Postbox, _ update: @escaping (Settings) -> Settings) -> Signal<Void, NoError> { postbox.transaction { _ in postbox.settings = update(postbox.settings) } }
func deliverOnMainQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { signal }
func deliverOnPrepareQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { signal }
final class Queue { static let main = Queue(); var tasks: [() -> Void] = []; static func mainQueue() -> Queue { main }; func justDispatch(_ body: @escaping () -> Void) { tasks.append(body) }; func drain() { while !tasks.isEmpty { tasks.removeFirst()() } } }
struct State: Equatable { let peer: EnginePeer; let file: TelegramMediaFile; static func == (lhs: Self, rhs: Self) -> Bool { lhs.file === rhs.file } }
struct Arguments { let context: any AccountContextProtocol; let close: () -> Void }
func entries(_ state: State, arguments: Arguments) -> [Int] { [] }
struct InputDataSignalValue { let entries: [Int] }
enum Validation { case none }
enum Screen { case botMiniAppEmojiStatusRequest }
struct ModalHeaderData { let image: Int; let handler: () -> Void }
struct ModalTheme { let listBackground: Int }
struct Theme { struct Colors { let background = 0 }; struct Icons { let modalClose = 1 }; let colors = Colors(); let icons = Icons() }
let theme = Theme()
struct ModalInteractions { init(acceptTitle: String, accept: @escaping () -> Void, singleButton: Bool, customTheme: @escaping () -> ModalTheme) {} }
final class InputDataController {
    var onDeinit: (() -> Void)?; var validateData: ((Int) -> Validation)?; var analyticsScreen: Screen?; var leftModalHeader: ModalHeaderData?
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) {}
    func returnKeyAction() -> Validation { validateData?(0) ?? .none }
    deinit { onDeinit?() }
}
final class InputDataModalController {
    let controller: InputDataController; var closed = false; var modal: InputDataModalController? { self }
    init(_ controller: InputDataController, modalInteractions: ModalInteractions?) { self.controller = controller }
    func close() { if !closed { closed = true; controller.onDeinit?() } }
    func accept() { _ = controller.returnKeyAction() }
}
__MODAL__
final class Window { var prompts: [InputDataModalController] = []; var progress: [MetaDisposable] = []; var texts: [String] = []; var onToast: (() -> Void)?; func removeObserver(for object: AnyObject) {} }
func showModal(with modal: InputDataModalController, for window: Window) { window.prompts.append(modal) }
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> {
    Signal { subscriber in
        let pending = MetaDisposable(); window.progress.append(pending)
        pending.set(signal.start(next: subscriber.putNext, error: subscriber.putError, completed: subscriber.putCompletion))
        return pending
    }
}
struct Strings { let emojiContextSetStatusSuccess = "success", webappEmojiStatusNotExists = "invalid" }
func strings() -> Strings { .init() }
func showModalText(for window: Window, text: String) { window.texts.append(text); window.onToast?() }
final class BrowserHooks { static let shared = BrowserHooks(); var premium = 0; func openPremiumBoarding(_ context: any AccountContextProtocol, _ window: Window) { premium += 1 } }
struct JSON { let data: [String: Any]; init?(dictionary: [String: Any]) { data = dictionary }; var string: String? { (try? JSONSerialization.data(withJSONObject: data)).flatMap { String(data: $0, encoding: .utf8) } } }
var testTimestamp: Double = 100
func CACurrentMediaTime() -> Double { testTimestamp }
__ACTION__
class BaseController { func viewWillDisappear(_ animated: Bool) {}; func viewWillAppear(_ animated: Bool) {} }
final class Resettable { func reset() {} }
final class Controller: BaseController {
    var lastTouchTimestamp: Double? = 100; var acceptsLocationRequests = true
    let context = Context(); var bot: Peer? = Peer(10); var window: Window? = Window()
    let emojiStatusAction = BrowserEmojiStatusAction(); let emojiPermissionAction = Resettable(); let locationAction = Resettable(); let preparedShareAction = Resettable(); let apperanceDisposable = MetaDisposable()
    var events: [(String, [String: Any]?)] = []
    func sendEvent(name: String, data: String?) { let object = data?.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }; events.append((name, object)) }
    func cancelPendingInvoices() {}
    __METHODS__
    func request(_ duration: Any? = nil) { var data: [String: Any] = ["custom_emoji_id": "10"]; data["duration"] = duration; setEmojiStatus(data) }
    func resolve(_ file: TelegramMediaFile? = TelegramMediaFile(10)) { context.inlinePacksContext.pending.last?.send(file) }
    var prompt: InputDataModalController? { window?.prompts.last }
    var rpc: Pending<Api.Bool, RpcError>? { context.account.network.requests.last?.1 }
    var error: String? { events.last?.1?["error"] as? String }
    var box: Postbox { context.account.postbox }
    var user: TelegramUser? { box.peers[1] as? TelegramUser }
}

final class BrowserEmojiStatusTests: XCTestCase {
    override func setUp() { Queue.main.tasks = []; testTimestamp = 100; BrowserHooks.shared.premium = 0 }
    override func tearDown() { Queue.main.drain() }
    func testNumericDurationSetsOneAbsoluteTimestamp() { let c = Controller(); c.request(60); c.resolve(); c.prompt!.accept(); guard case let .emojiStatus(status)? = c.context.account.network.requests.last?.0 else { return XCTFail() }; XCTAssertEqual(status.until, 1_700_000_060); XCTAssertEqual(status.documentId, 10); XCTAssertEqual(status.flags, 1) }
    func testLegacyStringDurationIsSupported() { let c = Controller(); c.request("60"); c.resolve(); c.prompt!.accept(); guard case let .emojiStatus(status)? = c.context.account.network.requests.last?.0 else { return XCTFail() }; XCTAssertEqual(status.until, 1_700_000_060) }
    func testMissingAndZeroDurationsNeverExpire() { for duration in [nil, 0 as Any?, "0" as Any?] { let c = Controller(); c.request(duration); c.resolve(); c.prompt!.accept(); guard case let .emojiStatus(status)? = c.context.account.network.requests.last?.0 else { return XCTFail() }; XCTAssertNil(status.until); XCTAssertEqual(status.flags, 0) } }
    func testInvalidDurationsRejectWithoutLoading() { for duration: Any in [-1, 0.5, true, NSNull(), "abc", "1.5", Double.infinity, Double.nan, Int64.max, Int64(Int32.max)] { let c = Controller(); c.request(duration); XCTAssertEqual(c.error, "DURATION_INVALID", "\(duration)"); XCTAssertTrue(c.context.inlinePacksContext.pending.isEmpty) } }
    func testDurationOverflowAfterSlowConfirmationIsRejected() { let c = Controller(); c.context.timestamp = Int32.max - 60; c.request(60); c.resolve(); c.context.timestamp += 1; c.prompt!.accept(); XCTAssertEqual(c.error, "DURATION_INVALID"); XCTAssertNil(c.rpc) }
    func testDurationStartsWhenConfirmed() { let c = Controller(); c.request(60); c.resolve(); c.context.timestamp += 30; c.prompt!.accept(); guard case let .emojiStatus(status)? = c.context.account.network.requests.last?.0 else { return XCTFail() }; XCTAssertEqual(status.until, 1_700_000_090) }
    func testInvalidIdentifierReturnsProtocolError() { for value: Any in ["0", "abc", "9223372036854775808", 10, true, NSNull()] { let c = Controller(); c.setEmojiStatus(["custom_emoji_id": value]); XCTAssertEqual(c.error, "SUGGESTED_EMOJI_INVALID"); XCTAssertTrue(c.context.inlinePacksContext.pending.isEmpty) } }
    func testMissingPayloadReturnsProtocolError() { let c = Controller(); c.setEmojiStatus(nil); XCTAssertEqual(c.error, "SUGGESTED_EMOJI_INVALID") }
    func testRequiresRecentUserInteraction() { let c = Controller(); for time: Double? in [nil, 89, 101] { c.lastTouchTimestamp = time; c.request() }; XCTAssertTrue(c.context.inlinePacksContext.pending.isEmpty); XCTAssertTrue(c.events.isEmpty) }
    func testHiddenPageAndOldGestureAreIgnored() { let c = Controller(); c.viewWillDisappear(false); c.lastTouchTimestamp = 100; c.request(); XCTAssertTrue(c.context.inlinePacksContext.pending.isEmpty); c.viewWillDisappear(false); c.viewWillAppear(false); c.request(); XCTAssertTrue(c.context.inlinePacksContext.pending.isEmpty) }
    func testDuplicatesIgnoredIncludingMalformedRequestWhileBusy() { let c = Controller(); c.request(); c.setEmojiStatus(nil); c.request(); XCTAssertEqual(c.context.inlinePacksContext.pending.count, 1); XCTAssertTrue(c.events.isEmpty); c.resolve(); c.prompt!.accept(); c.request(); XCTAssertEqual(c.window!.prompts.count, 1) }
    func testNilFileReturnsInvalidEmoji() { let c = Controller(); c.request(); c.resolve(nil); XCTAssertEqual(c.error, "SUGGESTED_EMOJI_INVALID"); XCTAssertNil(c.prompt) }
    func testWrongFileOrNonEmojiRejected() { for file in [TelegramMediaFile(20), TelegramMediaFile(10)] { if file.fileId.id == 10 { file.isCustomEmoji = false }; let c = Controller(); c.request(); c.resolve(file); XCTAssertEqual(c.error, "SUGGESTED_EMOJI_INVALID"); XCTAssertNil(c.prompt) } }
    func testEmptyLoadReturnsInvalidEmoji() { let c = Controller(); c.request(); c.context.inlinePacksContext.pending.last!.complete(); XCTAssertEqual(c.error, "SUGGESTED_EMOJI_INVALID") }
    func testProgressCancellationCompletesAndAllowsRetry() { let c = Controller(); c.request(); c.window!.progress.last!.dispose(); Queue.main.drain(); XCTAssertEqual(c.error, "USER_DECLINED"); c.request(); XCTAssertEqual(c.context.inlinePacksContext.pending.count, 2) }
    func testResetCancelsLoadAndSuppressesResult() { let c = Controller(); c.request(); let load = c.context.inlinePacksContext.pending.last!; c.cancelPendingPageActions(); XCTAssertTrue(load.disposed); load.send(TelegramMediaFile(10)); Queue.main.drain(); XCTAssertNil(c.prompt); XCTAssertTrue(c.events.isEmpty) }
    func testResetClosesPromptWithoutSettingStatus() { let c = Controller(); c.request(); c.resolve(); let p = c.prompt!; c.cancelPendingPageActions(); XCTAssertTrue(p.closed); p.accept(); XCTAssertNil(c.rpc); XCTAssertTrue(c.events.isEmpty) }
    func testDismissalHasOneDeclinedEvent() { let c = Controller(); c.request(); c.resolve(); let p = c.prompt!; p.close(); p.close(); p.accept(); Queue.main.drain(); XCTAssertEqual(c.events.count, 1); XCTAssertEqual(c.error, "USER_DECLINED"); XCTAssertNil(c.rpc) }
    func testNonPremiumConfirmationOpensPremiumWithoutMutation() { let c = Controller(); c.context.isPremium = false; c.request(); c.resolve(); c.prompt!.accept(); XCTAssertEqual(c.error, "USER_DECLINED"); XCTAssertEqual(BrowserHooks.shared.premium, 1); XCTAssertNil(c.rpc) }
    func testSameEmojiIsSetInsteadOfToggledOff() { let c = Controller(); c.box.peers[1] = TelegramUser(1, status: .init(content: .emoji(fileId: 10), expirationDate: nil)); c.request(60); c.resolve(); c.prompt!.accept(); guard case let .emojiStatus(status)? = c.context.account.network.requests.last?.0 else { return XCTFail() }; XCTAssertEqual(status.documentId, 10) }
    func testNoOptimisticSuccessOrLocalMutation() { let c = Controller(); c.request(); c.resolve(); c.prompt!.accept(); Queue.main.drain(); XCTAssertNil(c.user?.status); XCTAssertTrue(c.box.recent.isEmpty); XCTAssertTrue(c.events.isEmpty); XCTAssertTrue(c.window!.texts.isEmpty); XCTAssertTrue(c.box.settings.focusIntentStatusEnabled) }
    func testServerFalseDoesNotMutateAndReturnsError() { let c = Controller(); c.request(); c.resolve(); c.prompt!.accept(); c.rpc!.respond(.boolFalse); XCTAssertEqual(c.error, "SERVER_ERROR"); XCTAssertNil(c.user?.status); XCTAssertTrue(c.box.recent.isEmpty); XCTAssertTrue(c.window!.texts.isEmpty); XCTAssertTrue(c.box.settings.focusIntentStatusEnabled) }
    func testNetworkFailureReturnsServerError() { let c = Controller(); c.request(); c.resolve(); c.prompt!.accept(); c.rpc!.fail(.generic); XCTAssertEqual(c.error, "SERVER_ERROR"); XCTAssertNil(c.user?.status) }
    func testEmptyServerCompletionReturnsServerError() { let c = Controller(); c.request(); c.resolve(); c.prompt!.accept(); c.rpc!.complete(); XCTAssertEqual(c.error, "SERVER_ERROR"); XCTAssertNil(c.user?.status) }
    func testAcceptedStatusCommitsBeforeReportingSuccess() { let c = Controller(); c.request(); c.resolve(); c.prompt!.accept(); c.box.autoCommit = false; c.rpc!.respond(.boolTrue); XCTAssertTrue(c.events.isEmpty); XCTAssertNil(c.user?.status); c.box.drain(); XCTAssertEqual(c.events.last?.0, "emoji_status_set"); XCTAssertEqual(c.user?.status?.content, .emoji(fileId: 10)); XCTAssertEqual(c.box.recent, [10]); XCTAssertEqual(c.window!.texts, ["success"]); XCTAssertFalse(c.box.settings.focusIntentStatusEnabled); XCTAssertNil(c.box.settings.focusIntentStatusFallback); XCTAssertEqual(c.box.settings.other, 456) }
    func testAcceptedCacheCommitSurvivesObserverCancellation() { let c = Controller(); c.request(); c.resolve(); c.prompt!.accept(); c.box.autoCommit = false; c.rpc!.respond(.boolTrue); c.cancelPendingPageActions(); c.box.drain(); XCTAssertEqual(c.user?.status?.content, .emoji(fileId: 10)); XCTAssertTrue(c.events.isEmpty) }
    func testCommitPreservesCurrentUnrelatedUserFields() { let c = Controller(); c.request(); c.resolve(); c.prompt!.accept(); c.box.peers[1] = TelegramUser(1, name: "edited"); c.rpc!.respond(.boolTrue); XCTAssertEqual(c.user?.name, "edited") }
    func testResetDuringRpcSuppressesLateSuccess() { let c = Controller(); c.request(); c.resolve(); c.prompt!.accept(); let rpc = c.rpc!; c.cancelPendingPageActions(); XCTAssertTrue(rpc.disposed); rpc.respond(.boolTrue); XCTAssertTrue(c.events.isEmpty); XCTAssertNil(c.user?.status) }
    func testRepeatedConfirmStartsOneRequest() { let c = Controller(); c.request(); c.resolve(); c.prompt!.accept(); c.prompt!.accept(); XCTAssertEqual(c.context.account.network.requests.count, 1) }
    func testDifferentBotOrWindowCannotConfirmOldPrompt() { for changeBot in [true, false] { let c = Controller(); c.request(); c.resolve(); let window = c.window!; if changeBot { c.bot = Peer(20) } else { c.window = Window() }; window.prompts[0].accept(); XCTAssertNil(c.rpc); XCTAssertTrue(c.events.isEmpty) } }
    func testMissingBotOrWindowReturnsUnknownError() { let c = Controller(); c.bot = nil; c.request(); XCTAssertEqual(c.error, "UNKNOWN_ERROR"); c.bot = Peer(10); c.window = nil; c.request(); XCTAssertEqual(c.events.count, 2) }
    func testControllerReleasesWithLoadPending() { var c: Controller? = Controller(); c!.request(); let load = c!.context.inlinePacksContext.pending.last!; weak var weakController = c; c = nil; XCTAssertNil(weakController); XCTAssertTrue(load.disposed) }
    func testControllerReleasesWithPromptRetained() { var c: Controller? = Controller(); c!.request(); c!.resolve(); let prompt = c!.prompt!; weak var weakController = c; c = nil; XCTAssertNil(weakController); XCTAssertTrue(prompt.closed); prompt.accept() }
    func testControllerReleasesDuringRpc() { var c: Controller? = Controller(); c!.request(); c!.resolve(); c!.prompt!.accept(); let rpc = c!.rpc!; weak var weakController = c; c = nil; XCTAssertNil(weakController); XCTAssertTrue(rpc.disposed) }
    func testSynchronousLoadDoesNotCancelPrompt() { let c = Controller(); c.context.inlinePacksContext.synchronous = TelegramMediaFile(10); c.request(); Queue.main.drain(); XCTAssertNotNil(c.prompt); XCTAssertTrue(c.events.isEmpty); c.prompt!.accept(); XCTAssertNotNil(c.rpc) }
    func testCancellationDuringRpcSubscriptionOwnsReturnedDisposable() { let c = Controller(); c.context.account.network.onSubscribe = { c.cancelPendingPageActions() }; c.request(); c.resolve(); c.prompt!.accept(); XCTAssertTrue(c.rpc!.disposed); XCTAssertTrue(c.events.isEmpty); c.context.account.network.onSubscribe = nil }
    func testResetDuringSuccessToastSuppressesEvent() { let c = Controller(); c.request(); c.resolve(); c.prompt!.accept(); c.window!.onToast = { c.cancelPendingPageActions() }; c.rpc!.respond(.boolTrue); XCTAssertTrue(c.events.isEmpty); c.window!.onToast = nil }
    func testOldLoaderDisposalCannotCancelNewOperation() { let c = Controller(); c.request(); c.cancelPendingPageActions(); c.lastTouchTimestamp = 100; c.request(); Queue.main.drain(); XCTAssertTrue(c.events.isEmpty); c.resolve(); XCTAssertNotNil(c.prompt) }
    func testCoreSignalDoesNotRetainAccount() { var account: Account? = Account(); weak var weakAccount = account; let network = account!.network; let signal = AccountData(account!).setEmojiStatusWithResult(file: TelegramMediaFile(10), expirationDate: nil); account = nil; XCTAssertNil(weakAccount); let disposable = signal.start(); XCTAssertEqual(network.requests.count, 1); disposable.dispose(); XCTAssertTrue(network.requests[0].1.disposed) }
    func testTrueThenFalseResponseCommitsOnlyFirstResult() { let c = Controller(); c.request(); c.resolve(); c.prompt!.accept(); c.rpc!.respond(.boolTrue); c.rpc!.respond(.boolFalse); c.rpc!.complete(); XCTAssertEqual(c.events.count, 1); XCTAssertEqual(c.events.first?.0, "emoji_status_set"); XCTAssertEqual(c.box.recent, [10]) }
    func testFailureLeavesActionReusable() { let c = Controller(); c.request(); c.resolve(); c.prompt!.accept(); c.rpc!.fail(.generic); c.request(); c.resolve(); c.prompt!.accept(); c.rpc!.respond(.boolTrue); XCTAssertEqual(c.events.count, 2); XCTAssertEqual(c.events.last?.0, "emoji_status_set") }
    func testCoreRemovalUsesEmptyStatusAndCommitsOnTrue() { let c = Controller(); c.box.peers[1] = TelegramUser(1, status: .init(content: .emoji(fileId: 10), expirationDate: nil)); var completed = false; let disposable = c.context.engine.accountData.setEmojiStatusWithResult(file: nil, expirationDate: nil).start(completed: { completed = true }); guard case .emojiStatusEmpty? = c.context.account.network.requests.last?.0 else { return XCTFail() }; XCTAssertNotNil(c.user?.status); c.rpc!.respond(.boolTrue); XCTAssertNil(c.user?.status); XCTAssertTrue(completed); disposable.dispose() }
}
