import Cocoa
import XCTest
import SwiftSignalKit
@testable import Playback

final class PlaybackTests: XCTestCase {
    private var windows: [KeyWindow] = []
    override func setUp() { initializeLab() }
    override func tearDown() {
        windows.forEach { $0.close() }
        windows.removeAll()
        super.tearDown()
    }
    private func window() -> KeyWindow {
        let window = KeyWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        return window
    }
    private func commands(_ view: ChatVideoAutoplayView?) -> [RecordingPlayer.Command] {
        (view!.mediaPlayer as! RecordingPlayer).commands
    }

    func testLivePhotoPlaysWithoutAnAutoplayVideoPlayer() {
        let old = ReferenceMediaView(), new = CurrentMediaView(), window = window()
        old.testWindow = window; new.testWindow = window
        old.livePhotoView = makePlayer(); new.livePhotoView = makePlayer()
        old.updatePlayerIfNeeded(); new.updatePlayerIfNeeded()
        XCTAssertEqual(commands(old.livePhotoView), [])
        XCTAssertEqual(commands(new.livePhotoView), [.seek(0, true)])
        for _ in 0..<1000 { new.updatePlayerIfNeeded() }
        XCTAssertEqual(commands(new.livePhotoView), [.seek(0, true)])
        XCTAssertTrue(new.livePhotoPlayed)
    }

    func testLivePhotoPausesForEachIneligibleStateAndRestartsOnce() {
        let view = CurrentMediaView(), window = window()
        view.testWindow = window
        view.livePhotoView = makePlayer()
        let disable: [(CurrentMediaView) -> Void] = [
            { $0.testWindow = nil },
            { _ in window.key = false },
            { $0.region = .zero },
            { $0.isDynamicContentLocked = true },
            { $0.lite = true; $0.pointerInside = false }
        ]
        for change in disable {
            view.testWindow = window; window.key = true; view.region = NSRect(x: 0, y: 0, width: 100, height: 100)
            view.isDynamicContentLocked = false; view.lite = false; view.pointerInside = true
            view.updatePlayerIfNeeded()
            XCTAssertEqual(commands(view.livePhotoView).last, .seek(0, true))
            change(view)
            view.updatePlayerIfNeeded()
            XCTAssertEqual(commands(view.livePhotoView).last, .pause)
            XCTAssertFalse(view.livePhotoPlayed)
            XCTAssertEqual(view.hides.last, false)
            let count = commands(view.livePhotoView).count
            for _ in 0..<100 { view.updatePlayerIfNeeded() }
            XCTAssertEqual(commands(view.livePhotoView).count, count)
        }
    }

    func testLivePhotoDoesNotStartWhileIneligible() {
        let view = CurrentMediaView(), window = window()
        view.livePhotoView = makePlayer()
        view.updatePlayerIfNeeded()
        view.testWindow = window; window.key = false
        view.updatePlayerIfNeeded()
        window.key = true; view.isDynamicContentLocked = true
        view.updatePlayerIfNeeded()
        view.isDynamicContentLocked = false; view.lite = true; view.pointerInside = false
        view.updatePlayerIfNeeded()
        XCTAssertTrue(commands(view.livePhotoView).isEmpty)
        view.pointerInside = true
        view.updatePlayerIfNeeded()
        XCTAssertEqual(commands(view.livePhotoView), [.seek(0, true)])
    }

    func testOrdinaryVideoPlaybackAndProgressMatchBaseline() {
        let old = ReferenceMediaView(), new = CurrentMediaView(), window = window()
        old.autoplayVideoView = makePlayer(); new.autoplayVideoView = makePlayer()
        for bits in 0..<64 {
            window.key = bits & 1 != 0
            for view in [old as MediaEnvironment, new] {
                view.testWindow = bits & 2 != 0 ? window : nil
                view.region = bits & 4 != 0 ? .zero : NSRect(x: 0, y: 0, width: 20, height: 20)
                view.lite = bits & 8 != 0
                view.pointerInside = bits & 16 != 0
                view.isDynamicContentLocked = bits & 32 != 0
                view.updatePlayerIfNeeded()
            }
            XCTAssertEqual(commands(old.autoplayVideoView), commands(new.autoplayVideoView))
            XCTAssertEqual(old.progressView?.isHidden, new.progressView?.isHidden)
        }
    }

    func testPlayingStatusReusesOneTimerAndPreservesImmediateUpdates() {
        let old = ReferenceMediaView(), new = CurrentMediaView()
        old.autoplayVideoView = makePlayer(); new.autoplayVideoView = makePlayer()
        for index in 0..<1000 { old.updateMediaStatus(.init(status: .playing, timestamp: index), animated: index % 2 == 0) }
        XCTAssertEqual(LabTimer.records.count, 1000)
        XCTAssertEqual(LabTimer.records.filter(\.active).count, 1)
        let before = LabTimer.records.count
        for index in 0..<1000 { new.updateMediaStatus(.init(status: .playing, timestamp: index), animated: index % 2 == 0) }
        XCTAssertEqual(LabTimer.records.count - before, 1)
        XCTAssertEqual(new.autoplayVideoView!.playTimer!.record.schedules, 1000)
        XCTAssertEqual(old.accessories, new.accessories)
    }

    func testTimerUsesLatestMediaStatusAndAnimationFlag() {
        let view = CurrentMediaView()
        view.autoplayVideoView = makePlayer()
        view.updateMediaStatus(.init(status: .playing, timestamp: 1), animated: false)
        let timer = view.autoplayVideoView!.playTimer!
        view.media = TelegramMediaFile(99)
        let status = MediaPlayerStatus(status: .playing, timestamp: 800)
        view.updateMediaStatus(status, animated: true)
        XCTAssertTrue(view.autoplayVideoView!.playTimer === timer)
        timer.fire()
        XCTAssertEqual(view.accessories.last, .init(file: 99, status: status, animated: true))
    }

    func testPauseBufferingAndVisibilityStopTimerAndResumeCreatesOne() {
        let view = CurrentMediaView(), window = window()
        view.testWindow = window
        view.autoplayVideoView = makePlayer()
        for state: MediaPlayerStatus.State in [.paused, .buffering] {
            view.updateMediaStatus(.init(status: .playing))
            let timer = view.autoplayVideoView!.playTimer!
            view.updateMediaStatus(.init(status: state))
            XCTAssertNil(view.autoplayVideoView!.playTimer)
            XCTAssertFalse(timer.record.active)
            let count = view.accessories.count
            timer.fire()
            XCTAssertEqual(view.accessories.count, count)
            view.updateMediaStatus(.init(status: .playing))
            XCTAssertFalse(view.autoplayVideoView!.playTimer === timer)
        }
        window.key = false
        view.updatePlayerIfNeeded()
        XCTAssertNil(view.autoplayVideoView!.playTimer)
        view.updateMediaStatus(.init(status: .playing))
        XCTAssertEqual(LabTimer.records.filter(\.active).count, 1)
    }

    func testReplacedPlayerTimerCannotUpdateNewPlayer() {
        let view = CurrentMediaView()
        view.autoplayVideoView = makePlayer()
        let oldPlayer = view.autoplayVideoView!
        view.updateMediaStatus(.init(status: .playing))
        let timer = oldPlayer.playTimer!
        view.autoplayVideoView = makePlayer()
        view.media = TelegramMediaFile(2)
        view.updateMediaStatus(.init(status: .playing))
        let count = view.accessories.count
        timer.fire()
        XCTAssertEqual(view.accessories.count, count)
        XCTAssertNil(oldPlayer.playTimer)
        XCTAssertFalse(timer.record.active)
        XCTAssertEqual(LabTimer.records.filter(\.active).count, 1)
    }

    func testTimersDoNotRetainOwnerOrPlayer() {
        weak var releasedView: CurrentMediaView?
        weak var releasedPlayer: ChatVideoAutoplayView?
        autoreleasepool {
            let view = CurrentMediaView()
            view.autoplayVideoView = makePlayer()
            view.updateMediaStatus(.init(status: .playing))
            releasedView = view; releasedPlayer = view.autoplayVideoView
        }
        XCTAssertNil(releasedView); XCTAssertNil(releasedPlayer)
        XCTAssertEqual(LabTimer.records.filter(\.active).count, 0)
    }

    func testTimerDoesNotRetainReplacedMediaAndStopsWithoutMedia() {
        let old = ReferenceMediaView(), new = CurrentMediaView()
        old.autoplayVideoView = makePlayer(); new.autoplayVideoView = makePlayer()
        weak var oldFile: TelegramMediaFile?
        weak var newFile: TelegramMediaFile?
        autoreleasepool {
            let first = TelegramMediaFile(7), second = TelegramMediaFile(7)
            old.media = first; new.media = second
            old.updateMediaStatus(.init(status: .playing))
            new.updateMediaStatus(.init(status: .playing))
            oldFile = first; newFile = second
            old.media = nil; new.media = nil
        }
        XCTAssertNotNil(oldFile)
        XCTAssertNil(newFile)
        let count = new.accessories.count
        new.autoplayVideoView!.playTimer!.fire()
        XCTAssertEqual(new.accessories.count, count)
        XCTAssertNil(new.autoplayVideoView!.playTimer)
        old.autoplayVideoView!.stopPlayTimer()
    }

    func testLivePhotoRemovalCancelsFetchAndStatusSubscriptions() {
        let old = ReferenceMediaView(), new = CurrentMediaView()
        var oldFetch = 0, newFetch = 0, subscriptions = 0
        old.livePhotoFetchDisposable.set(ActionDisposable { oldFetch += 1 })
        new.livePhotoFetchDisposable.set(ActionDisposable { newFetch += 1 })
        new.livePhotoStatusDisposable.set(ActionDisposable { subscriptions += 1 })
        new.livePhotoPlayerStatusDisposable.set(ActionDisposable { subscriptions += 1 })
        new.livePhotoView = makePlayer(); new.livePhotoFile = TelegramMediaFile(9); new.livePhotoPlayed = true
        weak var player = new.livePhotoView
        old.removeLivePhotoPlayer(); new.removeLivePhotoPlayer()
        XCTAssertEqual(oldFetch, 0); XCTAssertEqual(newFetch, 1)
        XCTAssertEqual(subscriptions, 2)
        XCTAssertNil(player); XCTAssertNil(new.livePhotoFile); XCTAssertFalse(new.livePhotoPlayed)
        new.removeLivePhotoPlayer()
        XCTAssertEqual(newFetch, 1)
    }

    func testRealHalfSecondTimerPreservesQuietPeriodAndRepeatTiming() {
        let old = ReferenceMediaView(), new = CurrentMediaView()
        old.autoplayVideoView = makePlayer(); new.autoplayVideoView = makePlayer()
        var oldRecords: [TimerRecord] = []
        for index in 0..<8 {
            old.updateMediaStatus(.init(status: .playing, timestamp: index))
            oldRecords.append(old.autoplayVideoView!.playTimer!.record)
            new.updateMediaStatus(.init(status: .playing, timestamp: index))
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(oldRecords.reduce(0) { $0 + $1.fires }, 0)
        XCTAssertEqual(new.autoplayVideoView!.playTimer!.record.fires, 0)
        XCTAssertEqual(old.accessories.count, 8)
        XCTAssertEqual(new.accessories.count, 8)
        RunLoop.main.run(until: Date().addingTimeInterval(0.55))
        XCTAssertEqual(old.autoplayVideoView!.playTimer!.record.fires, 1)
        XCTAssertEqual(new.autoplayVideoView!.playTimer!.record.fires, 1)
        XCTAssertEqual(old.accessories, new.accessories)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(old.autoplayVideoView!.playTimer!.record.fires, 2)
        XCTAssertEqual(new.autoplayVideoView!.playTimer!.record.fires, 2)
    }

    func testStatusTimerBenchmark() throws {
        guard ProcessInfo.processInfo.environment["MEDIA_PLAYBACK_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        let count = 3000
        var results: [[String: Any]] = []
        for scenario in ["playing", "paused", "transitions", "new_player"] {
            let old = ReferenceMediaView(), new = CurrentMediaView()
            old.autoplayVideoView = makePlayer(); new.autoplayVideoView = makePlayer()
            var oldTrials: [Double] = [], newTrials: [Double] = []
            func measure(_ baseline: Bool) -> Double {
                let view: MediaEnvironment = baseline ? old : new
                view.accessories.removeAll(keepingCapacity: true)
                LabTimer.records.removeAll(keepingCapacity: true)
                let start = DispatchTime.now().uptimeNanoseconds
                for index in 0..<count {
                    if scenario == "new_player" { view.autoplayVideoView = makePlayer() }
                    let paused = scenario == "paused" || (scenario == "transitions" && index % 2 == 0)
                    view.updateMediaStatus(.init(status: paused ? .paused : .playing, timestamp: index), animated: false)
                }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(count) / 1000
            }
            _ = measure(true); _ = measure(false)
            for batch in 0..<9 {
                if batch % 2 == 0 { oldTrials.append(measure(true)); newTrials.append(measure(false)) }
                else { newTrials.append(measure(false)); oldTrials.append(measure(true)) }
            }
            XCTAssertEqual(old.accessories, new.accessories)
            results.append(["scenario": scenario, "baseline_us": oldTrials.sorted()[4], "candidate_us": newTrials.sorted()[4], "baseline_trials_us": oldTrials, "candidate_trials_us": newTrials])
        }
        let data = try JSONSerialization.data(withJSONObject: ["batches": 9, "iterations_per_batch": count, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/media-playback-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
