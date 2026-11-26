import Cocoa
import XCTest
import SwiftSignalKit

typealias MessageId = Int
typealias MediaResourceId = String
final class CMTimebase { let value: Int; init(_ value: Int) { self.value = value } }
struct ImageDataTransformation {}
protocol APDelegate {}
final class WeakReference<T: AnyObject> { weak var value: T?; init(value: T) { self.value = value } }
class MediaResource { let id: String; init(_ id: String) { self.id = id } }
final class LocalFileReferenceMediaResource: MediaResource { var localFilePath: String { id } }
final class TelegramMediaFile {
    let resource: MediaResource
    var isInstantVideo = true
    init(_ id: Int) { resource = MediaResource(String(id)) }
}
struct Message: Hashable {
    let id: Int
    var file: TelegramMediaFile
    var anyMedia: Any { file }
    var chatStableId: AnyHashable { id }
    init(_ id: Int) { self.id = id; file = TelegramMediaFile(id) }
    static func == (lhs: Message, rhs: Message) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
struct MessageReference { let message: Message; init(_ message: Message) { self.message = message } }
enum FileMediaReference {
    case message(message: MessageReference, media: TelegramMediaFile)
    var media: TelegramMediaFile { switch self { case let .message(_, media): return media } }
}
struct ResourceData { let complete: Bool; let path: String }
struct AVGifData { let path: String; static func dataFrom(_ path: String) -> AVGifData? { AVGifData(path: path) } }
final class MediaBox {
    var requests = 0
    var active = 0
    var pipes: [String: ValuePipe<ResourceData>] = [:]
    func resourceData(_ resource: MediaResource) -> Signal<ResourceData, NoError> {
        requests += 1
        let pipe = pipes[resource.id] ?? ValuePipe<ResourceData>()
        pipes[resource.id] = pipe
        return Signal { [weak self] subscriber in
            self?.active += 1
            let disposable = pipe.signal().start(next: subscriber.putNext)
            return ActionDisposable { [weak self] in self?.active -= 1; disposable.dispose() }
        }
    }
    func emit(_ id: Int) { pipes[String(id)]?.putNext(ResourceData(complete: true, path: String(id))) }
}
final class Postbox { let mediaBox = MediaBox() }
final class Account { let postbox = Postbox() }
protocol AccountContextProtocol: AnyObject { var account: Account { get }; var bindings: Bindings { get }; var window: Window { get } }
final class Context: AccountContextProtocol {
    let account = Account()
    let bindings = Bindings()
    let window = Window()
    var mediaBox: MediaBox { account.postbox.mediaBox }
}
final class Bindings { let navigation = Navigation(); func rootNavigation() -> Navigation { navigation } }
final class Navigation {
    var listeners: [WeakReference<ViewController>] = []
    var controller: ViewController? = nil
    func add(listener: WeakReference<ViewController>) { listeners.append(listener) }
    func remove(listener: WeakReference<ViewController>) { listeners.removeAll { $0.value == nil || $0.value === listener.value } }
}
class Layer { var opacity: Float = 1; var cornerRadius: CGFloat = 0; var borderWidth: CGFloat = 0; var borderColor: CGColor? }
class MockView: NSObject {
    var frame = CGRect(x: 0, y: 0, width: 200, height: 200)
    var visibleRect: CGRect { frame }
    var layer: Layer? = Layer()
    weak var superview: MockView?
    var children: [MockView] = []
    var autoresizingMask: NSView.AutoresizingMask = []
    var backingScaleFactor: CGFloat { 2 }
    var completions: [(Bool) -> Void] = []
    var positions: [CGPoint] = []
    func addSubview(_ view: MockView) { view.removeFromSuperview(); children.append(view); view.superview = self }
    func removeFromSuperview() { superview?.children.removeAll { $0 === self }; superview = nil }
    func setFrameOrigin(_ point: CGPoint) { frame.origin = point }
    func _change(pos: CGPoint, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        frame.origin = pos
        positions.append(pos)
        if let completion { if animated { completions.append(completion) } else { completion(true) } }
    }
    func _change(opacity: CGFloat) { layer?.opacity = Float(opacity) }
    func _mouseInside() -> Bool { true }
    func finishAnimations() { let pending = completions; completions.removeAll(); pending.forEach { $0(true) } }
}
enum ProgressState: Equatable { case None, ImpossibleFetching(progress: Float, force: Bool) }
final class Progress { var state: ProgressState = .None }
final class InstantVideoPIPView: MockView {
    let playingProgressView = Progress()
    var animatesAlphaOnFirstTransition = false
    var dataPath: String?
    var dataSets: [String?] = []
    var timebase: CMTimebase?
    var thumbnailRequests = 0
    var clears = 0
    var resets = 0
    func set(data: AVGifData?, timebase: CMTimebase? = nil) { dataPath = data?.path; dataSets.append(data?.path); self.timebase = timebase }
    func reset(with timebase: CMTimebase?) { self.timebase = timebase; resets += 1 }
    func clear() { clears += 1 }
    func setSignal(_ signal: Signal<ImageDataTransformation, NoError>) { thumbnailRequests += 1 }
}
enum KeyHandlerResult { case invoked, rejected }
enum MouseEvent { case leftMouseUp, leftMouseDown, leftMouseDragged }
enum Priority { case high }
final class Window {
    var contentView: MockView? = MockView()
    var mouseLocationOutsideOfEventStream = CGPoint(x: 50, y: 50)
    var handlers: [MouseEvent: (Int) -> KeyHandlerResult] = [:]
    var installations = 0
    init() { contentView?.frame.size = CGSize(width: 900, height: 700) }
    func set(mouseHandler: @escaping (Int) -> KeyHandlerResult, with owner: AnyObject, for event: MouseEvent, priority: Priority) { handlers[event] = mouseHandler; installations += 1 }
    func removeAllHandlers(for owner: AnyObject) { handlers.removeAll() }
}
class ViewController: NSObject {
    var window: Window? { nil }
    func viewDidLoad() {}
    func navigationWillChangeController() {}
}
class GenericViewController<T: InstantVideoPIPView>: ViewController {
    let genericView = InstantVideoPIPView()
    var view: MockView { genericView }
    var loaded = false
    func loadViewIfNeeded() { loaded = true }
    func isLoaded() -> Bool { loaded }
}
final class ChatControllerKind: ViewController { let genericView = ChatContent() }
final class ChatContent { let tableView = TableView() }
enum ChatHistoryEntryId: Hashable { case message(Message), other }
enum TranscribeState { case collapsed, expanded }
struct Additional { var transribeState: TranscribeState? = nil }
struct Entry { var additionalData = Additional() }
final class ChatRowItem { var stableId: AnyHashable; var entry = Entry(); init(_ message: Message) { stableId = ChatHistoryEntryId.message(message) } }
final class ChatRowView: MockView { var item: Any? }
final class ClipView { var isAnimateScrolling = false }
final class TableScrollListener { let callback: (Int) -> Void; init(_ callback: @escaping (Int) -> Void) { self.callback = callback } }
struct Focus { let focus: Bool }
enum ScrollTarget { case center(id: AnyHashable, innerId: Int?, animated: Bool, focus: Focus, inset: Int) }
final class TableView {
    let clipView = ClipView()
    var listeners: [TableScrollListener] = []
    var visible: [MockView] = []
    var scrolls = 0
    func addScroll(listener: TableScrollListener) { listeners.append(listener) }
    func removeScroll(listener: TableScrollListener) { listeners.removeAll { $0 === listener } }
    func enumerateVisibleViews(with body: (MockView) -> Void) { visible.forEach(body) }
    func item(stableId: AnyHashable) -> ChatRowItem? { nil }
    func scroll(to: ScrollTarget) { scrolls += 1 }
    func scroll() { listeners.forEach { $0.callback(0) } }
}
enum APState: Equatable { case playing(Double, Double, Double), paused(Double, Double, Double), waiting, stoped, fetching(Float) }
enum SongEntry { case song(Message), other }
final class APSongItem {
    var entry: SongEntry
    var state: APState = .playing(1, 10, 0.1)
    var stableId: AnyHashable { if case let .song(message) = entry { return message.chatStableId }; return -1 }
    init(_ id: Int) { entry = .song(Message(id)) }
}
final class APController: NSObject {
    var currentSong: APSongItem? = APSongItem(1)
    var timebase: CMTimebase? = CMTimebase(1)
    var listeners: [WeakReference<NSObject>] = []
    var cleanups = 0
    var toggles = 0
    var onComplete: (() -> Void)?
    func add(listener: NSObject) { listeners.append(WeakReference(value: listener)) }
    func remove(listener: NSObject) { listeners.removeAll { $0.value == nil || $0.value === listener } }
    func playOrPause() -> Bool { toggles += 1; return true }
    func notifyCompleteQueue(animated: Bool) { onComplete?() }
    func cleanup() { cleanups += 1; currentSong?.state = .stoped }
}
final class ChatUIHooks { static let shared = ChatUIHooks(); var player: APController?; func getAudioPlayer(_ context: any AccountContextProtocol) -> APController? { player } }
func chatMessageVideo(account: Account, fileReference: FileMediaReference, scale: CGFloat) -> Signal<ImageDataTransformation, NoError> { .single(ImageDataTransformation()) }

__ALIGNMENT__
__CONTROLLER__

final class PipTests: XCTestCase {
    func create(_ context: Context, _ player: APController, table: TableView? = nil) -> InstantVideoPIP {
        let pip = InstantVideoPIP(player, context: context, window: context.window)
        pip.updateTableView(table, context: context, controller: player)
        if let song = player.currentSong { pip.songDidChanged(song: song, for: player, animated: false) }
        return pip
    }
    func testReplacementDetachesOldPlayerAndUsesNewSong() {
        let context = Context(), old = APController(), next = APController()
        next.currentSong = APSongItem(2)
        let pip = create(context, old)
        pip.updateTableView(nil, context: context, controller: next)
        XCTAssertEqual(old.listeners.count, 0)
        XCTAssertEqual(next.listeners.count, 1)
        XCTAssertEqual(pip.currentMessage?.id, 2)
        context.mediaBox.emit(1)
        context.mediaBox.emit(2)
        XCTAssertEqual(pip.genericView.dataPath, "2")
        XCTAssertEqual(context.mediaBox.active, 1)
    }
    func testStalePlayerCallbacksCannotChangeCurrentPresentation() {
        let context = Context(), old = APController(), next = APController()
        next.currentSong = APSongItem(2)
        next.timebase = CMTimebase(2)
        let pip = create(context, old)
        pip.updateTableView(nil, context: context, controller: next)
        pip.songDidChanged(song: next.currentSong!, for: next, animated: false)
        pip.playerDidChangedTimebase(song: next.currentSong!, for: next, animated: false)
        let before = pip.genericView.playingProgressView.state
        old.currentSong!.state = .paused(5, 10, 0.5)
        pip.songDidChangedState(song: old.currentSong!, for: old, animated: false)
        pip.songDidChanged(song: old.currentSong!, for: old, animated: false)
        pip.playerDidChangedTimebase(song: old.currentSong!, for: old, animated: false)
        pip.audioDidCompleteQueue(for: old, animated: false)
        XCTAssertEqual(pip.currentMessage?.id, 2)
        XCTAssertTrue(pip.isShown)
        XCTAssertEqual(pip.timebase?.value, 2)
        XCTAssertEqual(pip.genericView.playingProgressView.state, before)
    }
    func testRepeatedScrollDoesNotRestartMediaOrMouseHandlers() {
        let context = Context(), player = APController(), table = TableView()
        let pip = create(context, player, table: table)
        let requests = context.mediaBox.requests
        let thumbnails = pip.genericView.thumbnailRequests
        let handlers = context.window.installations
        for _ in 0..<10 { table.scroll() }
        XCTAssertEqual(context.mediaBox.requests, requests)
        XCTAssertEqual(pip.genericView.thumbnailRequests, thumbnails)
        XCTAssertEqual(context.window.installations, handlers)
    }
    func testHideCancelsResourceUpdatesAndClearsDecoderAfterAnimation() {
        let context = Context(), player = APController()
        let pip = create(context, player)
        context.mediaBox.emit(1)
        pip.hide()
        XCTAssertEqual(context.mediaBox.active, 0)
        let updates = pip.genericView.dataSets.count
        context.mediaBox.emit(1)
        XCTAssertEqual(pip.genericView.dataSets.count, updates)
        XCTAssertNotNil(pip.genericView.superview)
        pip.genericView.finishAnimations()
        XCTAssertNil(pip.genericView.superview)
        XCTAssertNil(pip.genericView.dataPath)
        XCTAssertTrue(context.window.handlers.isEmpty)
    }
    func testReopenBeforeHideCompletionKeepsViewAndData() {
        let context = Context(), player = APController()
        let pip = create(context, player)
        pip.hide()
        pip.showIfNeeded(animated: false)
        context.mediaBox.emit(1)
        let reopenedPosition = pip.genericView.frame.origin
        pip.genericView.finishAnimations()
        XCTAssertTrue(pip.isShown)
        XCTAssertNotNil(pip.genericView.superview)
        XCTAssertEqual(pip.genericView.dataPath, "1")
        XCTAssertEqual(reopenedPosition.x, 680)
    }
    func testCompletionCannotReappearOnScrollOrTableUpdate() {
        let context = Context(), player = APController(), table = TableView()
        let pip = create(context, player, table: table)
        pip.audioDidCompleteQueue(for: player, animated: false)
        player.currentSong?.state = .stoped
        table.scroll()
        pip.updateTableView(table, context: context, controller: player)
        XCTAssertNil(pip.currentMessage)
        XCTAssertFalse(pip.isShown)
        XCTAssertNil(pip.genericView.superview)
    }
    func testContextMigrationMovesWindowNavigationAndResourceOwnership() {
        let old = Context(), next = Context(), player = APController(), nextPlayer = APController()
        let oldTable = TableView(), nextTable = TableView()
        let pip = create(old, player, table: oldTable)
        pip.updateTableView(nextTable, context: next, controller: nextPlayer)
        XCTAssertTrue(pip.window === next.window)
        XCTAssertTrue(old.window.handlers.isEmpty)
        XCTAssertEqual(old.mediaBox.active, 0)
        XCTAssertEqual(old.bindings.navigation.listeners.count, 0)
        XCTAssertEqual(next.bindings.navigation.listeners.count, 1)
        XCTAssertEqual(oldTable.listeners.count, 0)
        XCTAssertEqual(nextTable.listeners.count, 1)
        XCTAssertTrue(pip.genericView.superview === next.window.contentView)
    }
    func testDeinitRemovesViewHandlersListenersAndResourceSubscription() {
        let context = Context(), player = APController(), table = TableView()
        var pip: InstantVideoPIP? = create(context, player, table: table)
        weak var weakPip = pip
        let view = pip!.genericView
        context.mediaBox.emit(1)
        pip = nil
        XCTAssertNil(weakPip)
        XCTAssertEqual(context.mediaBox.active, 0)
        XCTAssertEqual(player.listeners.count, 0)
        XCTAssertEqual(table.listeners.count, 0)
        XCTAssertEqual(context.bindings.navigation.listeners.count, 0)
        XCTAssertNil(view.superview)
        XCTAssertNil(view.dataPath)
        XCTAssertTrue(context.window.handlers.isEmpty)
    }
    func testDismissalDoesNotCleanUpPlayerStartedByCompletion() {
        let context = Context(), player = APController(), next = APController()
        let pip = create(context, player)
        ChatUIHooks.shared.player = player
        player.onComplete = { ChatUIHooks.shared.player = next }
        _ = context.window.handlers[.leftMouseDown]?(0)
        pip.genericView.frame.origin.x += 5
        pip.genericView.layer?.opacity = 0.2
        _ = context.window.handlers[.leftMouseUp]?(0)
        XCTAssertEqual(player.cleanups, 1)
        XCTAssertEqual(next.cleanups, 0)
        ChatUIHooks.shared.player = nil
    }
    func testNoMessageDoesNotLoadOrPresentView() {
        let context = Context(), player = APController()
        player.currentSong = nil
        let pip = InstantVideoPIP(player, context: context, window: context.window)
        pip.hide(false)
        pip.showIfNeeded()
        XCTAssertFalse(pip.isLoaded())
        XCTAssertFalse(pip.isShown)
        XCTAssertTrue(context.window.handlers.isEmpty)
        XCTAssertEqual(context.mediaBox.requests, 0)
    }
    func testVisibleMessageHidesPipUntilItScrollsAway() {
        let context = Context(), player = APController(), table = TableView()
        let row = ChatRowView()
        row.item = ChatRowItem(Message(1))
        table.visible = [row]
        let pip = create(context, player, table: table)
        XCTAssertFalse(pip.isShown)
        table.visible = []
        table.scroll()
        XCTAssertTrue(pip.isShown)
        table.visible = [row]
        table.scroll()
        XCTAssertFalse(pip.isShown)
    }
    func testNewMessageOnSamePlayerReplacesResourceWithoutReinstallingHandlers() {
        let context = Context(), player = APController()
        let pip = create(context, player)
        let requests = context.mediaBox.requests
        let handlers = context.window.installations
        player.currentSong = APSongItem(2)
        pip.songDidChanged(song: player.currentSong!, for: player, animated: false)
        context.mediaBox.emit(2)
        context.mediaBox.emit(1)
        XCTAssertEqual(context.mediaBox.requests, requests + 1)
        XCTAssertEqual(context.mediaBox.active, 1)
        XCTAssertEqual(pip.genericView.dataPath, "2")
        XCTAssertEqual(context.window.installations, handlers)
    }
    func testRepeatedTableUpdatesKeepSingleListeners() {
        let context = Context(), player = APController(), table = TableView()
        let pip = create(context, player, table: table)
        let requests = context.mediaBox.requests
        let resets = pip.genericView.resets
        for _ in 0..<3 { pip.updateTableView(table, context: context, controller: player) }
        XCTAssertEqual(table.listeners.count, 1)
        XCTAssertEqual(player.listeners.count, 1)
        XCTAssertEqual(context.bindings.navigation.listeners.count, 1)
        XCTAssertEqual(context.mediaBox.requests, requests)
        XCTAssertEqual(pip.genericView.resets, resets)
    }
    func testClickControlsBoundPlayerWhenGlobalPlayerDiffers() {
        let context = Context(), player = APController(), other = APController()
        let pip = create(context, player)
        ChatUIHooks.shared.player = other
        _ = context.window.handlers[.leftMouseDown]?(0)
        _ = context.window.handlers[.leftMouseUp]?(0)
        XCTAssertEqual(player.toggles, 1)
        XCTAssertEqual(other.toggles, 0)
        XCTAssertTrue(pip.isShown)
        ChatUIHooks.shared.player = nil
    }
    func testLateAnimationAfterOwnerDeinitDoesNotKeepViewAlive() {
        let context = Context(), player = APController()
        var pip: InstantVideoPIP? = create(context, player)
        weak var weakPip = pip
        let view = pip!.genericView
        pip!.hide()
        pip = nil
        XCTAssertNil(weakPip)
        XCTAssertNil(view.superview)
        view.finishAnimations()
        XCTAssertNil(view.superview)
        XCTAssertEqual(context.mediaBox.active, 0)
    }
    func testQueuedResourceFromOldMessageCannotReplaceNewData() {
        let context = Context(), player = APController()
        let pip = create(context, player)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { context.mediaBox.emit(1); group.leave() }
        group.wait()
        player.currentSong = APSongItem(2)
        pip.songDidChanged(song: player.currentSong!, for: player, animated: false)
        context.mediaBox.emit(2)
        let drained = expectation(description: "queued resource drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(pip.genericView.dataPath, "2")
    }
    func testOldSongEventsOnSamePlayerCannotReplaceNewMessage() {
        let context = Context(), player = APController()
        let pip = create(context, player)
        let previous = player.currentSong!
        player.currentSong = APSongItem(2)
        pip.songDidChanged(song: player.currentSong!, for: player, animated: false)
        pip.songDidChangedState(song: player.currentSong!, for: player, animated: false)
        let progress = pip.genericView.playingProgressView.state
        previous.state = .paused(5, 10, 0.5)
        pip.songDidChanged(song: previous, for: player, animated: false)
        pip.songDidChangedState(song: previous, for: player, animated: false)
        XCTAssertEqual(pip.currentMessage?.id, 2)
        XCTAssertEqual(pip.genericView.playingProgressView.state, progress)
    }
    func testResourceChangeWithSameMessageIdRefreshesMedia() {
        let context = Context(), player = APController()
        let pip = create(context, player)
        let requests = context.mediaBox.requests
        var edited = Message(1)
        edited.file = TelegramMediaFile(2)
        player.currentSong!.entry = .song(edited)
        pip.songDidChanged(song: player.currentSong!, for: player, animated: false)
        context.mediaBox.emit(2)
        context.mediaBox.emit(1)
        XCTAssertEqual(pip.currentMessage?.id, 1)
        XCTAssertEqual(context.mediaBox.requests, requests + 1)
        XCTAssertEqual(context.mediaBox.active, 1)
        XCTAssertEqual(pip.genericView.dataPath, "2")
    }
}
