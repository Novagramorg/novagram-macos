import Cocoa
import XCTest
import SwiftSignalKit
import RangeSet

__HELPER__

final class WeakReference<T: AnyObject> { weak var value: T?; init(value: T) { self.value = value } }
final class APSongItem {
    let stableId: Int
    enum State { case playing, stoped }
    var state: State = .playing
    init(_ id: Int) { stableId = id }
}
final class Progress {
    var ranges: [Range<CGFloat>] = []
    func set(fetchingProgress: CGFloat, animated: Bool) { ranges = fetchingProgress > 0 ? [0 ..< fetchingProgress] : [] }
    func set(fetchingProgressRanges: [Range<CGFloat>], animated: Bool) { ranges = fetchingProgressRanges }
}
final class Controls {
    let progress = Progress()
    var isHidden = false
    var rendered: [Int] = []
    var animations: [Bool] = []
    func update(_ song: APSongItem, controller: APController, animated: Bool) {
        rendered.append(song.stableId)
        animations.append(animated)
    }
}
final class StubPlayer {
    enum End { case stop }
    var actionAtEnd = End.stop
    func pause() {}
}
final class APController: NSObject {
    var playbackGeneration: UInt64 = 0
    let statusDisposable = MetaDisposable()
    let timebaseDisposable = MetaDisposable()
    let itemDisposable = MetaDisposable()
    var prevNextDisposable = DisposableSet()
    var _timebase: Int?
    var listeners: [WeakReference<NSObject>] = []
    var currentSong: APSongItem? = APSongItem(1)
    var song: APSongItem? { currentSong }
    var mediaPlayer: StubPlayer? = StubPlayer()
    var timerStops = 0
    __CORE_BUFFER__
    func notifySongDidStopPlaying(item: APSongItem, animated: Bool) {}
    func stopTimer() { timerStops += 1 }
    __LISTENERS__
    __STOP__
}
final class PlayerListView: NSObject {
    let controls = Controls()
    let bufferingStatusDisposable = MetaDisposable()
    private var ranges: (RangeSet<Int64>, Int64)?
    __LIST_BINDING__
    __LIST_SET__
    __LIST_DELEGATES__
}
final class InlineAudioPlayerView {
    let progressView = Progress()
    private var ranges: (RangeSet<Int64>, Int64)?
    __INLINE_STATUS__
}

final class BufferingTests: XCTestCase {
    func testEmptyRangeClearsPreviousBufferInBothViews() {
        let list = PlayerListView(), inline = InlineAudioPlayerView()
        list.updateStatus(RangeSet(0 ..< 40), 100)
        inline.updateStatus(RangeSet(0 ..< 40), 100)
        list.updateStatus(RangeSet(), 100)
        inline.updateStatus(RangeSet(), 100)
        XCTAssertEqual(list.controls.progress.ranges, [])
        XCTAssertEqual(inline.progressView.ranges, [])
    }
    func testUnknownSizeClearsPreviousBuffer() {
        let list = PlayerListView(), inline = InlineAudioPlayerView()
        for size: Int64 in [0, -1] {
            list.updateStatus(RangeSet(0 ..< 40), 100)
            inline.updateStatus(RangeSet(0 ..< 40), 100)
            list.updateStatus(RangeSet(0 ..< 40), size)
            inline.updateStatus(RangeSet(0 ..< 40), size)
            XCTAssertEqual(list.controls.progress.ranges, [])
            XCTAssertEqual(inline.progressView.ranges, [])
        }
    }
    func testFragmentedBufferPreservesOffsets() {
        var ranges = RangeSet<Int64>()
        ranges.insert(contentsOf: 0 ..< 20)
        ranges.insert(contentsOf: 60 ..< 80)
        let list = PlayerListView(), inline = InlineAudioPlayerView()
        list.updateStatus(ranges, 100)
        inline.updateStatus(ranges, 100)
        XCTAssertEqual(list.controls.progress.ranges, [0 ..< 0.2, 0.6 ..< 0.8])
        XCTAssertEqual(inline.progressView.ranges, [0 ..< 0.2, 0.6 ..< 0.8])
    }
    func testOutOfBoundsRangesAreClippedWithoutOverflow() {
        XCTAssertEqual(audioPlayerBufferingRanges(RangeSet(Int64.min ..< 40), size: 100), [0 ..< 0.4])
        XCTAssertEqual(audioPlayerBufferingRanges(RangeSet(60 ..< Int64.max), size: 100), [0.6 ..< 1])
        XCTAssertEqual(audioPlayerBufferingRanges(RangeSet(Int64.min ..< Int64.max), size: 100), [])
        XCTAssertEqual(audioPlayerBufferingRanges(RangeSet(101 ..< Int64.max), size: 100), [])
    }
    func testFullResourceHasNoBufferOverlay() {
        let list = PlayerListView(), inline = InlineAudioPlayerView()
        list.updateStatus(RangeSet(0 ..< 100), 100)
        inline.updateStatus(RangeSet(0 ..< 100), 100)
        XCTAssertEqual(list.controls.progress.ranges, [])
        XCTAssertEqual(inline.progressView.ranges, [])
    }
    func testNilEmissionClearsBuffer() {
        let view = PlayerListView(), controller = APController()
        view.setController(controller)
        controller.bufferingStatus = .single((RangeSet(0 ..< 40), 100))
        XCTAssertFalse(view.controls.progress.ranges.isEmpty)
        controller.bufferingStatus = .single(nil)
        XCTAssertEqual(view.controls.progress.ranges, [])
    }
    func testReplacementClearsBufferBeforeNewControllerEmits() {
        let view = PlayerListView(), old = APController(), next = APController()
        view.setController(old)
        old.bufferingStatus = .single((RangeSet(0 ..< 40), 100))
        view.setController(next)
        XCTAssertEqual(view.controls.progress.ranges, [])
        XCTAssertEqual(old.listeners.count, 0)
        XCTAssertEqual(next.listeners.count, 1)
    }
    func testNilControllerHidesControlsAndPublishesNilSong() {
        let view = PlayerListView(), controller = APController()
        var updates: [Int?] = []
        view.playerDidUpdate = { updates.append($0?.stableId) }
        view.setController(controller)
        controller.bufferingStatus = .single((RangeSet(0 ..< 40), 100))
        view.setController(nil)
        XCTAssertEqual(updates.count, 2)
        XCTAssertNil(updates.last.flatMap { $0 })
        XCTAssertTrue(view.controls.isHidden)
        XCTAssertEqual(view.controls.progress.ranges, [])
        XCTAssertEqual(controller.listeners.count, 0)
    }
    func testControllerWithoutSongHidesOldControls() {
        let view = PlayerListView(), controller = APController()
        view.setController(controller)
        controller.currentSong = nil
        view.setController(controller)
        XCTAssertTrue(view.controls.isHidden)
    }
    func testControllerSwitchPublishesCurrentSong() {
        let view = PlayerListView(), controller = APController()
        controller.currentSong = APSongItem(2)
        var updates: [Int?] = []
        view.playerDidUpdate = { updates.append($0?.stableId) }
        view.setController(controller)
        XCTAssertEqual(updates, [2])
        XCTAssertEqual(view.controls.rendered, [2])
    }
    func sendAll(_ song: APSongItem, from controller: APController, to view: PlayerListView) {
        view.songDidChanged(song: song, for: controller, animated: false)
        view.songDidChangedState(song: song, for: controller, animated: false)
        view.songDidStartPlaying(song: song, for: controller, animated: false)
        view.songDidStopPlaying(song: song, for: controller, animated: false)
        view.playerDidChangedTimebase(song: song, for: controller, animated: false)
    }
    func testOldControllerEventsAreIgnored() {
        let view = PlayerListView(), old = APController(), current = APController()
        view.setController(old)
        view.setController(current)
        view.controls.rendered.removeAll()
        var updates = 0
        view.playerDidUpdate = { _ in updates += 1 }
        sendAll(old.currentSong!, from: old, to: view)
        view.audioDidCompleteQueue(for: old, animated: false)
        XCTAssertEqual(view.controls.rendered, [])
        XCTAssertEqual(updates, 0)
        XCTAssertFalse(view.controls.isHidden)
    }
    func testPreviousSongEventsOnCurrentControllerAreIgnored() {
        let view = PlayerListView(), controller = APController()
        view.setController(controller)
        let old = controller.currentSong!
        controller.currentSong = APSongItem(2)
        view.controls.rendered.removeAll()
        var updates = 0
        view.playerDidUpdate = { _ in updates += 1 }
        sendAll(old, from: controller, to: view)
        XCTAssertEqual(view.controls.rendered, [])
        XCTAssertEqual(updates, 0)
    }
    func testCurrentEventsRespectAnimationAndPublishSong() {
        let view = PlayerListView(), controller = APController()
        view.setController(controller)
        view.controls.animations.removeAll()
        var updates: [Int?] = []
        view.playerDidUpdate = { updates.append($0?.stableId) }
        sendAll(controller.currentSong!, from: controller, to: view)
        XCTAssertEqual(updates, [1, 1, 1, 1, 1])
        XCTAssertEqual(view.controls.animations, [false, false, false, false, false])
    }
    func testCompletionClearsVisiblePlaybackState() {
        let view = PlayerListView(), controller = APController()
        view.setController(controller)
        controller.bufferingStatus = .single((RangeSet(0 ..< 40), 100))
        var completed = false
        view.playerDidUpdate = { completed = $0 == nil }
        view.audioDidCompleteQueue(for: controller, animated: false)
        XCTAssertTrue(completed)
        XCTAssertTrue(view.controls.isHidden)
        XCTAssertEqual(view.controls.progress.ranges, [])
    }
    func testDeinitDetachesListenerAndSubscription() {
        let controller = APController()
        var view: PlayerListView? = PlayerListView()
        weak var weakView = view
        view?.setController(controller)
        view = nil
        XCTAssertNil(weakView)
        XCTAssertEqual(controller.listeners.count, 0)
    }
    func testStopPublishesNilAndDetachesResourceSignal() {
        let controller = APController(), view = PlayerListView()
        let pipe = ValuePipe<(RangeSet<Int64>, Int64)?>()
        var disposed = false
        controller.bufferingStatus = Signal { subscriber in
            let inner = pipe.signal().start(next: subscriber.putNext)
            return ActionDisposable { disposed = true; inner.dispose() }
        }
        view.setController(controller)
        pipe.putNext((RangeSet(0 ..< 40), 100))
        controller.stop()
        XCTAssertTrue(disposed)
        XCTAssertEqual(view.controls.progress.ranges, [])
        pipe.putNext((RangeSet(0 ..< 80), 100))
        XCTAssertEqual(view.controls.progress.ranges, [])
        XCTAssertNil(controller.mediaPlayer)
        XCTAssertEqual(controller.timerStops, 1)
    }
    func testQueuedBufferCannotReappearAfterStop() {
        let view = PlayerListView(), controller = APController()
        let pipe = ValuePipe<(RangeSet<Int64>, Int64)?>()
        controller.bufferingStatus = pipe.signal()
        view.setController(controller)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { pipe.putNext((RangeSet(0 ..< 40), 100)); group.leave() }
        group.wait()
        controller.stop()
        let drained = expectation(description: "drain")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(view.controls.progress.ranges, [])
    }
    func testQueuedPreviousResourceCannotReplaceCurrentBuffer() {
        let view = PlayerListView(), controller = APController()
        let pipe = ValuePipe<(RangeSet<Int64>, Int64)?>()
        controller.bufferingStatus = pipe.signal()
        view.setController(controller)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { pipe.putNext((RangeSet(0 ..< 40), 100)); group.leave() }
        group.wait()
        controller.stop()
        controller.currentSong = APSongItem(2)
        controller.bufferingStatus = .single((RangeSet(60 ..< 80), 100))
        let drained = expectation(description: "drain")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(view.controls.progress.ranges, [0.6 ..< 0.8])
    }
    func testQueuedOldBufferCannotOverwriteNewBinding() {
        let view = PlayerListView(), old = APController(), next = APController()
        view.setController(old)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { old.bufferingStatus = .single((RangeSet(0 ..< 40), 100)); group.leave() }
        group.wait()
        view.setController(next)
        next.bufferingStatus = .single((RangeSet(60 ..< 80), 100))
        let drained = expectation(description: "drain")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(view.controls.progress.ranges, [0.6 ..< 0.8])
    }
}
