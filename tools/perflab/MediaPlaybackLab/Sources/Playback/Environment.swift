import Cocoa
import SwiftSignalKit

struct MediaPlayerStatus: Equatable {
    enum State: Equatable { case playing, paused, buffering }
    var status: State
    var timestamp: Int = 0
}
enum MediaPlayerActionAtEnd { case loop((() -> Void)?), stop }
final class MediaPlayerView: NSView {}
final class TelegramMediaFile {
    var id: Int
    init(_ id: Int) { self.id = id }
}
enum MediaResourceStatus { case Local }

final class RecordingPlayer: ChatVideoAutoplayPlayer {
    enum Command: Equatable { case play, pause, seek(Double, Bool?) }
    var commands: [Command] = []
    var status: Signal<MediaPlayerStatus, NoError> { .single(.init(status: .paused)) }
    func play() { commands.append(.play) }
    func pause() { commands.append(.pause) }
    func seek(timestamp: Double) { commands.append(.seek(timestamp, nil)) }
    func seek(timestamp: Double, play: Bool?) { commands.append(.seek(timestamp, play)) }
    func setVolume(_ volume: Float) {}
    func getVolume(_ completion: @escaping (Float) -> Void) { completion(0) }
    func attachPlayerView(_ node: MediaPlayerView) {}
    func setActionAtEnd(_ value: MediaPlayerActionAtEnd) {}
}

final class TimerRecord {
    var active = false
    var starts = 0
    var fires = 0
    var cancellations = 0
    var schedules = 0
}
protocol LabPlaybackTimer: AnyObject {
    var record: TimerRecord { get }
    func start()
    func restart()
    func invalidate()
    func fire()
}

final class LabDispatchTimer {
    let record = TimerRecord()
    private let underlying: DispatchSourceTimer
    private var handler: (() -> Void)?
    private init(queue: DispatchQueue) {
        underlying = DispatchSource.makeTimerSource(queue: queue)
        LabTimer.records.append(record)
    }
    static func makeTimerSource(queue: DispatchQueue) -> LabDispatchTimer { LabDispatchTimer(queue: queue) }
    func setEventHandler(handler: @escaping () -> Void) {
        self.handler = handler
        let record = self.record
        underlying.setEventHandler {
            record.fires += 1
            handler()
        }
    }
    func schedule(deadline: DispatchTime, repeating: Double) {
        record.schedules += 1
        underlying.schedule(deadline: deadline, repeating: repeating)
    }
    func resume() {
        record.active = true
        record.starts += 1
        underlying.resume()
    }
    func cancel() {
        if record.active { record.cancellations += 1 }
        record.active = false
        underlying.cancel()
    }
    func fire() {
        if record.active { record.fires += 1; handler?() }
    }
}

final class LabTimer: LabPlaybackTimer {
    static var records: [TimerRecord] = []
    let record = TimerRecord()
    private let underlying: SwiftSignalKit.Timer
    private let completion: () -> Void
    init(timeout: Double, repeat repeats: Bool, completion: @escaping () -> Void, queue: Queue) {
        self.completion = completion
        let record = self.record
        underlying = SwiftSignalKit.Timer(timeout: timeout, repeat: repeats, completion: {
            record.fires += 1
            completion()
        }, queue: queue)
        LabTimer.records.append(record)
    }
    func start() {
        record.active = true
        record.starts += 1
        underlying.start()
    }
    func restart() { fatalError("Legacy timer has no reschedule API") }
    func invalidate() {
        if record.active { record.cancellations += 1 }
        record.active = false
        underlying.invalidate()
    }
    func fire() {
        if record.active {
            record.fires += 1
            completion()
        }
    }
    deinit { invalidate() }
}

final class KeyWindow: NSWindow {
    var key = true
    override var isKeyWindow: Bool { key }
}

class MediaEnvironment: NSView {
    var testWindow: NSWindow?
    var region = NSRect(x: 0, y: 0, width: 200, height: 200)
    var visibleReads = 0
    override var window: NSWindow? { testWindow }
    override var visibleRect: NSRect { visibleReads += 1; return region }
    var isDynamicContentLocked = false
    var lite = false
    var pointerInside = true
    func mouseInside() -> Bool { pointerInside }
    var autoplayVideoView: ChatVideoAutoplayView?
    var livePhotoView: ChatVideoAutoplayView?
    var livePhotoPlayed = false
    var media: Any? = TelegramMediaFile(1)
    var livePhotoFile: TelegramMediaFile?
    var progressView: NSView? = NSView()
    let livePhotoStatusDisposable = MetaDisposable()
    let livePhotoFetchDisposable = MetaDisposable()
    let livePhotoPlayerStatusDisposable = MetaDisposable()
    struct Accessory: Equatable { let file: Int; let status: MediaPlayerStatus; let animated: Bool }
    var accessories: [Accessory] = []
    var hides: [Bool] = []
    func updateVideoAccessory(_ resource: MediaResourceStatus, file: TelegramMediaFile, mediaPlayerStatus: MediaPlayerStatus, animated: Bool) {
        accessories.append(Accessory(file: file.id, status: mediaPlayerStatus, animated: animated))
    }
    func hideLivePhotoVideo(animated: Bool) { hides.append(animated) }
    func updateMediaStatus(_ status: MediaPlayerStatus, animated: Bool = false) {}
    func updatePlayerIfNeeded() {}
    func removeLivePhotoPlayer() {}
    deinit {
        livePhotoStatusDisposable.dispose()
        livePhotoFetchDisposable.dispose()
        livePhotoPlayerStatusDisposable.dispose()
    }
}

func makePlayer() -> ChatVideoAutoplayView {
    ChatVideoAutoplayView(mediaPlayer: RecordingPlayer(), view: MediaPlayerView())
}

func initializeLab() {
    _ = NSApplication.shared
    LabTimer.records = []
}
