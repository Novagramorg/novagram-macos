import Foundation
import XCTest
import SwiftSignalKit

var clockTime: Double = 100
func CACurrentMediaTime() -> Double { clockTime }
__STATUS__
__STATE__

final class ManualTimer {
    let fire: () -> Void
    var active = false
    init(timeout: Double, repeat: Bool, completion: @escaping () -> Void, queue: Queue) { fire = completion }
    func start() { active = true }
    func invalidate() { active = false }
    func tick() { if active { fire() } }
}
struct APResource { let complete: Bool; let progress: Float }
struct Resource { let size: Int64? = 100 }
enum ContentType { case audio }
struct Reference {}
final class MediaBox {
    func resourceRangesStatus(_ resource: Resource) -> Signal<Int, NoError> { .single(40) }
}
final class Postbox { let mediaBox = MediaBox() }
final class Account { let postbox = Postbox() }
var prefetches = 0
func fetchedMediaResource(mediaBox: MediaBox, userLocation: Int, userContentType: ContentType, reference: Reference, statsCategory: ContentType) -> Signal<Int, NoError> {
    Signal { _ in prefetches += 1; return EmptyDisposable }
}
final class APSongItem: Equatable {
    struct Entry { struct Index { let id: Int }; let index: Index }
    let entry: Entry
    init(_ id: Int = 0) { entry = Entry(index: Entry.Index(id: id)) }
    static func ==(lhs: APSongItem, rhs: APSongItem) -> Bool { lhs === rhs }
    let resource = Resource()
    let reference = Reference()
    let userLocation = 0
    let pipe = ValuePipe<APResource>()
    var resourceSubscriptions = 0
    var onState: (() -> Void)?
    var state: APState = .waiting { didSet { onState?() } }
    var status = makeStatus()
    var statusUpdates = 0
    func setStatus(_ status: MediaPlayerStatus, rate: Double) {
        statusUpdates += 1
        self.status = status
        self.state = .playing(current: status.timestamp, duration: status.duration, progress: 0)
    }
    func pullResource() -> Signal<APResource, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            self.resourceSubscriptions += 1
            let inner = self.pipe.signal().start(next: subscriber.putNext)
            return ActionDisposable { [weak self] in self?.resourceSubscriptions -= 1; inner.dispose() }
        }
    }
}
typealias APItem = APSongItem
func makeStatus(timestamp: Double = 10, duration: Double = 100, generation: Double = 100, rate: Double = 1, status: MediaPlayerPlaybackStatus = .playing) -> MediaPlayerStatus {
    MediaPlayerStatus(generationTimestamp: generation, duration: duration, dimensions: .zero, timestamp: timestamp, baseRate: rate, volume: 1, seekId: 0, status: status)
}
final class MediaPlayer {
    enum End { case stop, action(() -> Void) }
    static var instances: [MediaPlayer] = []
    static var initialStatus: MediaPlayerStatus?
    static var initialTimebase: Int?
    let statusPipe = ValuePipe<MediaPlayerStatus>()
    let timebasePipe = ValuePipe<Int?>()
    var statusSubscriptions = 0
    var timebaseSubscriptions = 0
    var pauses = 0
    var plays = 0
    var actionAtEnd: End = .stop
    var status: Signal<MediaPlayerStatus, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            self.statusSubscriptions += 1
            let inner = self.statusPipe.signal().start(next: subscriber.putNext)
            if let value = MediaPlayer.initialStatus { subscriber.putNext(value) }
            return ActionDisposable { [weak self] in self?.statusSubscriptions -= 1; inner.dispose() }
        }
    }
    var timebase: Signal<Int?, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            self.timebaseSubscriptions += 1
            let inner = self.timebasePipe.signal().start(next: subscriber.putNext)
            if let value = MediaPlayer.initialTimebase { subscriber.putNext(value) }
            return ActionDisposable { [weak self] in self?.timebaseSubscriptions -= 1; inner.dispose() }
        }
    }
    init(postbox: Postbox, userLocation: Int, userContentType: ContentType, reference: Reference, streamable: Bool, video: Bool, preferSoftwareDecoding: Bool, enableSound: Bool, baseRate: Double, volume: Float, fetchAutomatically: Bool) { Self.instances.append(self) }
    func play() { plays += 1 }
    func pause() { pauses += 1 }
    func seek(timestamp: Double) {}
    var completion: () -> Void { if case let .action(f) = actionAtEnd { return f }; return {} }
}
final class SessionControlCenter { var activations = 0; func activate() { activations += 1 } }
class APController {
    let controlCenter = SessionControlCenter()
    enum Status { case playing, paused, stopped }
    struct State { var status: Status = .stopped }
    var onState: (() -> Void)?
    var onBuffer: (() -> Void)?
    var state = State() { didSet { onState?() } }
    let account = Account()
    var streamable = false
    var baseRate = 1.0
    var volume: Float = 1
    var mediaPlayer: MediaPlayer?
    var playbackGeneration: UInt64 = 0
    var song: APSongItem?
    var currentSong: APSongItem? { song }
    var _timebase: Int?
    var timer: ManualTimer?
    var finishes = 0
    var timebaseEvents = 0
    var stopEvents = 0
    var ticks = 0
    var onTimebase: (() -> Void)?
    var onStop: (() -> Void)?
    let statusDisposable = MetaDisposable()
    let timebaseDisposable = MetaDisposable()
    let itemDisposable = MetaDisposable()
    var prevNextDisposable = DisposableSet()
    let items = Atomic<[APItem]>(value: [])
    var bufferingStatus: Signal<(Int, Int64)?, NoError> = .single(nil) { didSet { onBuffer?() } }
    func audioPlayerDidFinishPlaying() { finishes += 1 }
    func notifySongDidChangedTimebase(item: APSongItem, animated: Bool) { timebaseEvents += 1; onTimebase?() }
    func notifySongDidStopPlaying(item: APSongItem, animated: Bool) { stopEvents += 1; onStop?() }
    func updateUIAfterTick(_ status: MediaPlayerStatus) { ticks += 1 }
    func dequeueCurrent() { if let song { replace(song) } }
    func replace(_ item: APSongItem) { stop(); song = item; play(with: item) }
    deinit { timer?.invalidate(); statusDisposable.dispose(); timebaseDisposable.dispose(); itemDisposable.dispose(); prevNextDisposable.dispose() }
    __PLAY__
    __TOGGLE__
    __RESUME__
    __TIMEBASE__
    __STOP__
    __TIMER__
}

final class ConsumptionMessages {
    var started: [Int] = []
    var pending: [Int: Int] = [:]
    var onStart: ((Int) -> Void)?
    var onDispose: ((Int) -> Void)?
    func markMessageContentAsConsumedInteractively(messageId: Int) -> Signal<Void, NoError> {
        Signal { subscriber in
            self.started.append(messageId)
            self.pending[messageId, default: 0] += 1
            self.onStart?(messageId)
            return ActionDisposable {
                self.pending[messageId, default: 0] -= 1
                self.onDispose?(messageId)
            }
        }
    }
}
final class ConsumptionEngine { let messages = ConsumptionMessages() }
final class ConsumptionContext { let engine = ConsumptionEngine() }
final class APChatVoiceController: APController {
    let context = ConsumptionContext()
    let markAsConsumedDisposable = MetaDisposable()
    __VOICE__
}

final class PlaybackTests: XCTestCase {
    override func setUp() {
        MediaPlayer.instances.removeAll()
        MediaPlayer.initialStatus = nil
        MediaPlayer.initialTimebase = nil
        clockTime = 100
        prefetches = 0
    }
    func start() -> (APController, APSongItem, MediaPlayer) {
        let controller = APController(), item = APSongItem()
        controller.replace(item)
        return (controller, item, controller.mediaPlayer!)
    }
    func drain() {
        let done = expectation(description: "main queue drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }
    func enqueue(_ body: @escaping () -> Void) {
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { body(); group.leave() }
        group.wait()
    }
    func testVoiceMarksActiveMessageAndReleasesOnDeinit() {
        var controller: APChatVoiceController? = APChatVoiceController()
        let messages = controller!.context.engine.messages
        controller!.replace(APSongItem(1))
        XCTAssertEqual(messages.started, [1])
        XCTAssertEqual(messages.pending[1], 1)
        weak var weakController = controller
        controller = nil
        XCTAssertNil(weakController)
        XCTAssertEqual(messages.pending[1], 0)
    }
    func testVoiceDoesNotMarkMessageSupersededByStateObserver() {
        let controller = APChatVoiceController()
        let messages = controller.context.engine.messages
        controller.onState = {
            controller.onState = nil
            controller.replace(APSongItem(2))
        }
        controller.replace(APSongItem(1))
        XCTAssertEqual(controller.song?.entry.index.id, 2)
        XCTAssertEqual(messages.started, [2])
        XCTAssertEqual(messages.pending[2], 1)
    }
    func testVoiceDoesNotMarkMessageStoppedDuringStart() {
        let controller = APChatVoiceController()
        controller.onState = { controller.onState = nil; controller.stop() }
        controller.replace(APSongItem(1))
        XCTAssertTrue(controller.context.engine.messages.started.isEmpty)
    }
    func testVoiceSameItemRestartMarksOnlyLatestRequest() {
        let controller = APChatVoiceController(), item = APSongItem(1)
        controller.onState = {
            controller.onState = nil
            controller.replace(item)
        }
        controller.replace(item)
        XCTAssertEqual(controller.context.engine.messages.started, [1])
        XCTAssertEqual(controller.context.engine.messages.pending[1], 1)
    }
    func testVoiceDecoderStatusReplacementKeepsNewConsumptionRequest() {
        let controller = APChatVoiceController(), item = APSongItem(1)
        MediaPlayer.initialStatus = makeStatus()
        item.onState = {
            item.onState = nil
            controller.replace(APSongItem(2))
        }
        controller.replace(item)
        XCTAssertEqual(controller.song?.entry.index.id, 2)
        XCTAssertEqual(controller.context.engine.messages.started, [2])
        XCTAssertEqual(controller.context.engine.messages.pending[2], 1)
    }
    func testVoiceDoesNotMarkMessageReplacedByBufferObserver() {
        let controller = APChatVoiceController()
        var calls = 0
        controller.onBuffer = {
            calls += 1
            if calls == 2 {
                controller.onBuffer = nil
                controller.replace(APSongItem(2))
            }
        }
        controller.replace(APSongItem(1))
        XCTAssertEqual(controller.context.engine.messages.started, [2])
    }
    func testVoiceDoesNotReplaceNewerConsumptionDuringSynchronousStart() {
        let controller = APChatVoiceController()
        let messages = controller.context.engine.messages
        messages.onStart = { id in
            if id == 1 { messages.onStart = nil; controller.replace(APSongItem(2)) }
        }
        controller.replace(APSongItem(1))
        XCTAssertEqual(messages.started, [1, 2])
        XCTAssertEqual(messages.pending[1], 0)
        XCTAssertEqual(messages.pending[2], 1)
    }
    func testVoiceReplacementWhileDisposingOldMarkDoesNotStartObsoleteMark() {
        let controller = APChatVoiceController()
        let messages = controller.context.engine.messages
        controller.replace(APSongItem(1))
        messages.onDispose = { id in
            if id == 1 { messages.onDispose = nil; controller.replace(APSongItem(3)) }
        }
        controller.replace(APSongItem(2))
        XCTAssertEqual(messages.started, [1, 3])
        XCTAssertEqual(messages.pending[3], 1)
        XCTAssertEqual(controller.song?.entry.index.id, 3)
    }
    func testStartingAndResumingActivateSystemControls() {
        let (controller, _, player) = start()
        XCTAssertEqual(controller.controlCenter.activations, 1)
        controller.state.status = .paused
        XCTAssertTrue(controller.play())
        XCTAssertEqual(controller.controlCenter.activations, 2)
        XCTAssertEqual(player.plays, 2)
    }
    func testToggleResumeActivatesSystemControls() {
        let (controller, _, player) = start()
        controller.state.status = .paused
        XCTAssertTrue(controller.playOrPause())
        XCTAssertEqual(controller.controlCenter.activations, 2)
        XCTAssertEqual(player.plays, 2)
    }
    func testStopCancelsDecoderTimebaseResourceAndPrefetch() {
        let (controller, item, player) = start()
        var cancelled = false
        controller.prevNextDisposable.add(ActionDisposable { cancelled = true })
        player.timebasePipe.putNext(7)
        player.statusPipe.putNext(makeStatus())
        let timer = controller.timer
        controller.stop()
        XCTAssertEqual(player.statusSubscriptions, 0)
        XCTAssertEqual(player.timebaseSubscriptions, 0)
        XCTAssertEqual(item.resourceSubscriptions, 0)
        XCTAssertTrue(cancelled)
        XCTAssertEqual(player.pauses, 1)
        XCTAssertNil(controller._timebase)
        XCTAssertNil(controller.timer)
        XCTAssertFalse(timer?.active ?? true)
    }
    func testDecoderEventsAfterStopDoNotRevivePlayback() {
        let (controller, item, player) = start()
        controller.stop()
        let statusUpdates = item.statusUpdates
        player.statusPipe.putNext(makeStatus())
        player.timebasePipe.putNext(9)
        item.pipe.putNext(APResource(complete: false, progress: 0.8))
        XCTAssertEqual(item.statusUpdates, statusUpdates)
        XCTAssertEqual(item.state, .stoped)
        XCTAssertNil(controller.timer)
        XCTAssertNil(controller._timebase)
    }
    func testQueuedDecoderEventsAreCancelledAtStop() {
        let (controller, item, player) = start()
        enqueue { player.statusPipe.putNext(makeStatus()); player.timebasePipe.putNext(9) }
        controller.stop()
        drain()
        XCTAssertEqual(item.statusUpdates, 0)
        XCTAssertEqual(item.state, .stoped)
        XCTAssertNil(controller._timebase)
        XCTAssertNil(controller.timer)
    }
    func testOldCompletionDoesNotFinishNewTrack() {
        let (controller, _, player) = start()
        let oldCompletion = player.completion
        enqueue(oldCompletion)
        controller.replace(APSongItem())
        drain()
        XCTAssertEqual(controller.finishes, 0)
        controller.mediaPlayer?.completion()
        XCTAssertEqual(controller.finishes, 1)
    }
    func testCompletionAfterStopIsIgnored() {
        let (controller, _, player) = start()
        let completion = player.completion
        controller.stop()
        completion()
        XCTAssertEqual(controller.finishes, 0)
    }
    func testLegacyTimebaseCallbackRejectsPreviousPlayer() {
        let (controller, _, player) = start()
        controller.replace(APSongItem())
        controller.audioPlayerDidChangedTimebase(player)
        XCTAssertEqual(controller.timebaseEvents, 0)
        controller.audioPlayerDidChangedTimebase(controller.mediaPlayer!)
        XCTAssertEqual(controller.timebaseEvents, 1)
    }
    func testImmediateStatusReentryKeepsNewestSubscriptions() {
        let controller = APController(), first = APSongItem(), next = APSongItem()
        MediaPlayer.initialStatus = makeStatus()
        first.onState = {
            first.onState = nil
            controller.replace(next)
        }
        controller.replace(first)
        let old = MediaPlayer.instances[0], current = controller.mediaPlayer!
        XCTAssertTrue(controller.song === next)
        XCTAssertEqual(old.statusSubscriptions, 0)
        XCTAssertEqual(first.resourceSubscriptions, 0)
        XCTAssertEqual(current.statusSubscriptions, 1)
        XCTAssertEqual(next.resourceSubscriptions, 1)
        let before = next.statusUpdates
        current.statusPipe.putNext(makeStatus(timestamp: 30, status: .paused))
        XCTAssertEqual(next.statusUpdates, before + 1)
        XCTAssertNil(controller.timer)
    }
    func testImmediateTimebaseReentryKeepsNewestSubscriptions() {
        let controller = APController(), first = APSongItem(), next = APSongItem()
        MediaPlayer.initialTimebase = 7
        controller.onTimebase = {
            controller.onTimebase = nil
            MediaPlayer.initialTimebase = nil
            controller.replace(next)
        }
        controller.replace(first)
        let old = MediaPlayer.instances[0], current = controller.mediaPlayer!
        XCTAssertEqual(old.timebaseSubscriptions, 0)
        XCTAssertEqual(old.statusSubscriptions, 0)
        XCTAssertEqual(first.resourceSubscriptions, 0)
        XCTAssertEqual(current.timebaseSubscriptions, 1)
        current.timebasePipe.putNext(42)
        XCTAssertEqual(controller._timebase, 42)
    }
    func testPlayingStateReentryCannotReinstallPreviousPlayer() {
        let controller = APController(), first = APSongItem(), next = APSongItem()
        controller.onState = {
            controller.onState = nil
            controller.replace(next)
        }
        controller.replace(first)
        let old = MediaPlayer.instances[0], current = MediaPlayer.instances[1]
        XCTAssertTrue(controller.mediaPlayer === current)
        XCTAssertEqual(old.statusSubscriptions, 0)
        XCTAssertEqual(old.timebaseSubscriptions, 0)
        XCTAssertEqual(first.resourceSubscriptions, 0)
        XCTAssertEqual(current.statusSubscriptions, 1)
    }
    func testBufferPublicationReentryCannotReplaceCurrentSubscriptions() {
        let controller = APController(), first = APSongItem(), next = APSongItem()
        controller.onBuffer = {
            guard controller.mediaPlayer != nil else { return }
            controller.onBuffer = nil
            controller.replace(next)
        }
        controller.replace(first)
        let old = MediaPlayer.instances[0], current = MediaPlayer.instances[1]
        XCTAssertTrue(controller.mediaPlayer === current)
        XCTAssertEqual(old.statusSubscriptions, 0)
        XCTAssertEqual(old.timebaseSubscriptions, 0)
        XCTAssertEqual(first.resourceSubscriptions, 0)
        XCTAssertEqual(current.statusSubscriptions, 1)
        XCTAssertEqual(current.timebaseSubscriptions, 1)
    }
    func testStoppedStateReentryCannotStopNewTimer() {
        let (controller, first, player) = start()
        let next = APSongItem()
        MediaPlayer.initialStatus = makeStatus()
        player.statusPipe.putNext(makeStatus())
        first.onState = {
            first.onState = nil
            controller.replace(next)
        }
        controller.stop()
        XCTAssertTrue(controller.song === next)
        XCTAssertTrue(controller.timer?.active == true)
        XCTAssertTrue(controller.mediaPlayer != nil)
    }
    func current(_ item: APSongItem) -> Double {
        if case let .playing(current, _, _) = item.state { return current }
        XCTFail("Expected playing state")
        return -1
    }
    func testDelayedTicksUseElapsedTimeAndPlaybackRate() {
        let (controller, item, player) = start()
        player.statusPipe.putNext(makeStatus(timestamp: 10, rate: 2))
        clockTime = 103
        controller.timer?.tick()
        XCTAssertEqual(current(item), 16, accuracy: 0.0001)
        clockTime = 104
        controller.timer?.tick()
        XCTAssertEqual(current(item), 18, accuracy: 0.0001)
    }
    func testProgressStopsAtDuration() {
        let (controller, item, player) = start()
        player.statusPipe.putNext(makeStatus(timestamp: 99))
        clockTime = 110
        controller.timer?.tick()
        XCTAssertEqual(current(item), 100)
        if case let .playing(_, _, progress) = item.state { XCTAssertEqual(progress, 1) }
    }
    func testUnknownGenerationDoesNotInventElapsedTime() {
        let (controller, item, player) = start()
        player.statusPipe.putNext(makeStatus(timestamp: 10, generation: 0))
        clockTime = 1000
        controller.timer?.tick()
        XCTAssertEqual(current(item), 10)
    }
    func testInvalidStatusDoesNotStartInterpolationTimer() {
        let (controller, _, player) = start()
        for status in [makeStatus(duration: 0), makeStatus(duration: .nan), makeStatus(timestamp: .infinity), makeStatus(generation: .nan), makeStatus(rate: .infinity), makeStatus(rate: -1)] {
            player.statusPipe.putNext(status)
            XCTAssertNil(controller.timer)
        }
    }
    func testRetiredTimerCannotMutateNextSong() {
        let (controller, _, player) = start()
        player.statusPipe.putNext(makeStatus())
        let oldTimer = controller.timer!
        let next = APSongItem()
        controller.replace(next)
        oldTimer.fire()
        XCTAssertEqual(next.state, .waiting)
    }
    func testReplacementTimerInvalidatesPriorTimer() {
        let (controller, _, player) = start()
        player.statusPipe.putNext(makeStatus())
        let oldTimer = controller.timer!
        player.statusPipe.putNext(makeStatus(timestamp: 20))
        XCTAssertFalse(oldTimer.active)
        XCTAssertTrue(controller.timer?.active == true)
    }
    func testControllerCanDeallocateWhileOldPlayerIsRetained() {
        var controller: APController? = APController()
        weak var weakController = controller
        controller?.replace(APSongItem())
        let player = controller!.mediaPlayer!
        controller = nil
        XCTAssertNil(weakController)
        player.completion()
        XCTAssertEqual(player.statusSubscriptions, 0)
        XCTAssertEqual(player.timebaseSubscriptions, 0)
    }
}
