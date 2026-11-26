import XCTest
import SwiftSignalKit

final class WeakReference<T: AnyObject> { weak var value: T?; init(value: T) { self.value = value } }
func RangeSet() -> Int { 0 }
final class APSongItem { var stableId: Int { id }; let id: Int; init(_ id: Int) { self.id = id } }
final class TableView {}
final class Control { var isHidden = false }
final class Animator { func invalidate() {} }
final class Header { var contextObject: Any? }
class NavigationHeaderView: NSObject {
    let header: Header
    let ready = Promise<Bool>()
    init(_ header: Header) { self.header = header }
    func update(with contextObject: Any) { header.contextObject = contextObject }
}
final class APController: NSObject {
    var listeners: [WeakReference<NSObject>] = []
    var activeSubscriptions = 0
    var stops = 0
    var cleanups = 0
    var baseRate = 1.0
    var canMakeRepeat = true
    var currentSong: APSongItem? = APSongItem(1)
    let ready = Promise<Bool>(true)
    let pipe = ValuePipe<(Int, Int)?>()
    var bufferingStatus: Signal<(Int, Int)?, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            self.activeSubscriptions += 1
            let subscription = self.pipe.signal().start(next: subscriber.putNext)
            return ActionDisposable { [weak self] in
                self?.activeSubscriptions -= 1
                subscription.dispose()
            }
        }
    }
    __LISTENERS__
    func notifyGlobalStateChanged(animated: Bool) {}
    func stop() { stops += 1 }
    func cleanup() { cleanups += 1; listeners.removeAll(); stop() }
}
func effectivePlayingRate(for controller: APController) -> Double { 1 }
final class AudioPlayerUIHooks {
    static var shared = AudioPlayerUIHooks()
    var ended = 0
    var hiddenPip = 0
    var globalAdds = 0
    func makeInstantVideoPip(_ controller: APController) -> Int { 1 }
    func updateInstantVideoPip(_ pip: Int?, _ table: TableView, _ controller: APController) {}
    func hideInstantVideoPip(_ pip: Int?) { hiddenPip += 1 }
    func addGlobalAudioToVisible(_ table: TableView, _ controller: APController) { globalAdds += 1 }
    func endInlinePlayer(_ context: Int?, _ animated: Bool) { ended += 1 }
}
final class InlineAudioPlayerView: NavigationHeaderView {
    struct ContextObject {
        let controller: APController
        var tableView: TableView? = nil
        var supportTableView: TableView? = nil
    }
    var controller: APController? { (header.contextObject as? ContextObject)?.controller }
    var context: Int? { controller == nil ? nil : 1 }
    private weak var observedController: APController?
    let bufferingStatusDisposable = MetaDisposable()
    var windowDidResignKeyObserver: NSObjectProtocol?
    var expansionAnimator: Animator?
    let repeatControl = Control()
    var instantVideoPip: Int?
    var rendered: [Int] = []
    var buffering: [Int] = []
    var expansionResets = 0
    func resetExpansion() { expansionResets += 1 }
    func updateStatus(_ ranges: Int, _ size: Int) { if size == 0 { buffering.removeAll() } else { buffering.append(ranges) } }
    __UPDATE__
    __GUARD__
        rendered.append(song.id)
    }
    __DELEGATES__
    __STOP__
}

final class LifecycleTests: XCTestCase {
    override func setUp() { AudioPlayerUIHooks.shared = AudioPlayerUIHooks() }
    func install(_ controller: APController, on view: InlineAudioPlayerView, table: Bool = false) {
        let context = InlineAudioPlayerView.ContextObject(controller: controller, tableView: table ? TableView() : nil)
        view.header.contextObject = context
        view.update(with: context)
    }
    func testReplacementDetachesPreviousControllerEvenWhenHeaderAlreadyChanged() {
        let view = InlineAudioPlayerView(Header())
        let old = APController(), current = APController()
        install(old, on: view)
        install(current, on: view)
        XCTAssertEqual(old.listeners.count, 0)
        XCTAssertEqual(old.activeSubscriptions, 0)
        XCTAssertEqual(current.listeners.count, 1)
        XCTAssertEqual(current.activeSubscriptions, 1)
        XCTAssertEqual(old.stops, 0)
    }
    func testRepeatedUpdateKeepsOneListenerAndSubscription() {
        let view = InlineAudioPlayerView(Header())
        let controller = APController()
        for _ in 0..<3 { install(controller, on: view) }
        XCTAssertEqual(controller.listeners.count, 1)
        XCTAssertEqual(controller.activeSubscriptions, 1)
        XCTAssertEqual(controller.stops, 0)
    }
    func testOldCompletionCannotStopNewPlayer() {
        let view = InlineAudioPlayerView(Header())
        let old = APController(), current = APController()
        install(old, on: view)
        install(current, on: view)
        view.audioDidCompleteQueue(for: old, animated: true)
        XCTAssertEqual(current.stops, 0)
        XCTAssertEqual(current.cleanups, 0)
        XCTAssertEqual(AudioPlayerUIHooks.shared.ended, 0)
    }
    func testOldSongEventsCannotReplaceCurrentSong() {
        let view = InlineAudioPlayerView(Header())
        let old = APController(), current = APController()
        install(old, on: view)
        install(current, on: view)
        view.rendered.removeAll()
        let song = APSongItem(99)
        view.songDidChanged(song: song, for: old, animated: true)
        view.songDidChangedState(song: song, for: old, animated: true)
        view.songDidStartPlaying(song: song, for: old, animated: true)
        view.songDidStopPlaying(song: song, for: old, animated: true)
        view.playerDidChangedTimebase(song: song, for: old, animated: true)
        XCTAssertEqual(view.rendered, [])
        current.currentSong = song
        view.songDidChanged(song: song, for: current, animated: true)
        XCTAssertEqual(view.rendered, [99])
    }
    func testPreviousSongEventsOnSameControllerAreIgnored() {
        let view = InlineAudioPlayerView(Header())
        let controller = APController()
        install(controller, on: view)
        let old = controller.currentSong!
        controller.currentSong = APSongItem(2)
        view.rendered.removeAll()
        view.songDidChanged(song: old, for: controller, animated: false)
        view.songDidChangedState(song: old, for: controller, animated: false)
        view.songDidStartPlaying(song: old, for: controller, animated: false)
        view.songDidStopPlaying(song: old, for: controller, animated: false)
        view.playerDidChangedTimebase(song: old, for: controller, animated: false)
        XCTAssertEqual(view.rendered, [])
        view.songDidChanged(song: controller.currentSong!, for: controller, animated: false)
        XCTAssertEqual(view.rendered, [2])
    }
    func testNilBufferStatusClearsVisibleValue() {
        let view = InlineAudioPlayerView(Header())
        let controller = APController()
        install(controller, on: view)
        controller.pipe.putNext((40, 100))
        XCTAssertEqual(view.buffering, [40])
        controller.pipe.putNext(nil)
        XCTAssertEqual(view.buffering, [])
    }
    func testNewBindingClearsBufferBeforeFirstEmission() {
        let view = InlineAudioPlayerView(Header())
        let controller = APController()
        install(controller, on: view)
        controller.pipe.putNext((40, 100))
        install(APController(), on: view)
        XCTAssertEqual(view.buffering, [])
    }
    func testHiddenHeaderIgnoresAllControllerEvents() {
        let view = InlineAudioPlayerView(Header())
        let controller = APController()
        install(controller, on: view)
        view.rendered.removeAll()
        view.header.contextObject = nil
        controller.pipe.putNext((10, 100))
        view.songDidChanged(song: APSongItem(99), for: controller, animated: true)
        view.audioDidCompleteQueue(for: controller, animated: true)
        XCTAssertEqual(view.rendered, [])
        XCTAssertEqual(view.buffering, [])
        XCTAssertEqual(AudioPlayerUIHooks.shared.ended, 0)
    }
    func testStopCancelsBufferingAndCannotRunTwice() {
        let view = InlineAudioPlayerView(Header())
        let controller = APController()
        install(controller, on: view)
        view.stopAndHide(true)
        XCTAssertEqual(controller.activeSubscriptions, 0)
        XCTAssertEqual(controller.listeners.count, 0)
        view.stopAndHide(true)
        view.audioDidCompleteQueue(for: controller, animated: true)
        controller.pipe.putNext((10, 100))
        XCTAssertEqual(controller.cleanups, 1)
        XCTAssertEqual(AudioPlayerUIHooks.shared.ended, 1)
        XCTAssertEqual(view.buffering, [])
    }
    func testDeinitRemovesListenerAndReleasesSubscription() {
        let controller = APController()
        var view: InlineAudioPlayerView? = InlineAudioPlayerView(Header())
        weak var weakView = view
        install(controller, on: view!)
        view = nil
        XCTAssertNil(weakView)
        XCTAssertEqual(controller.listeners.count, 0)
        XCTAssertEqual(controller.activeSubscriptions, 0)
    }
    func testReplacedControllerCanDeallocate() {
        let view = InlineAudioPlayerView(Header())
        var controller: APController? = APController()
        weak var weakController = controller
        install(controller!, on: view)
        install(APController(), on: view)
        controller = nil
        XCTAssertNil(weakController)
    }
    func testListenerRemovalPreservesOtherLiveListeners() {
        let controller = APController()
        let kept = NSObject(), removed = NSObject()
        controller.add(listener: kept)
        controller.add(listener: removed)
        autoreleasepool {
            controller.add(listener: NSObject())
        }
        controller.remove(listener: removed)
        XCTAssertEqual(controller.listeners.count, 1)
        XCTAssertTrue(controller.listeners.first?.value === kept)
    }
    func testCurrentCompletionStopsAndHidesOnce() {
        let view = InlineAudioPlayerView(Header())
        let controller = APController()
        install(controller, on: view, table: true)
        XCTAssertEqual(AudioPlayerUIHooks.shared.globalAdds, 1)
        XCTAssertNotNil(view.instantVideoPip)
        view.audioDidCompleteQueue(for: controller, animated: true)
        XCTAssertEqual(controller.cleanups, 1)
        XCTAssertEqual(AudioPlayerUIHooks.shared.ended, 1)
        XCTAssertNil(view.instantVideoPip)
        XCTAssertEqual(controller.activeSubscriptions, 0)
    }
    func testQueuedOldBufferingCannotAffectReplacement() {
        let view = InlineAudioPlayerView(Header())
        let old = APController(), current = APController()
        install(old, on: view)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { old.pipe.putNext((10, 100)); group.leave() }
        group.wait()
        install(current, on: view)
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        current.pipe.putNext((20, 100))
        XCTAssertEqual(view.buffering, [20])
    }
}
