import Cocoa
import SwiftSignalKit

var backgroundMutations = 0
let MPMediaItemPropertyTitle = "title"
let MPMediaItemPropertyArtist = "artist"
let MPMediaItemPropertyPlaybackDuration = "duration"
let MPNowPlayingInfoPropertyElapsedPlaybackTime = "elapsed"
let MPNowPlayingInfoPropertyPlaybackRate = "rate"
let MPMediaItemPropertyArtwork = "artwork"
typealias MediaResourceId = String
struct Resource { let id: MediaResourceId }
struct MediaResourceData { let complete: Bool; let path: String }
final class MediaBox {
    var pipes: [String: ValuePipe<MediaResourceData>] = [:]
    var initial: [String: MediaResourceData] = [:]
    var observers = 0
    var subscriptions = 0
    func pipe(_ id: String) -> ValuePipe<MediaResourceData> {
        if let pipe = pipes[id] { return pipe }
        let pipe = ValuePipe<MediaResourceData>()
        pipes[id] = pipe
        return pipe
    }
    func resourcePath(_ resource: Resource) -> String { initial[resource.id]?.path ?? "" }
    func resourceData(_ resource: Resource) -> Signal<MediaResourceData, NoError> {
        Signal { subscriber in
            self.observers += 1
            self.subscriptions += 1
            let disposable = self.pipe(resource.id).signal().start(next: subscriber.putNext)
            if let data = self.initial[resource.id] { subscriber.putNext(data) }
            return ActionDisposable { self.observers -= 1; disposable.dispose() }
        }
    }
}
final class Postbox { let mediaBox = MediaBox() }
final class Account { let postbox = Postbox() }
func copyToTemp(path: String?, ext: String) -> String? { path }
var imageLoads = 0
var backgroundImageLoads = 0
func loadArtwork(contentsOfFile path: String) -> NSImage? {
    imageLoads += 1
    if !Thread.isMainThread { backgroundImageLoads += 1 }
    return NSImage(contentsOfFile: path)
}
final class MPMediaItemArtwork {
    let image: NSImage
    init(boundsSize: CGSize, requestHandler: (CGSize) -> NSImage) { image = requestHandler(boundsSize) }
}
__STATUS__
func makeStatus(timestamp: Double = 25, duration: Double = 100, rate: Double = 1, status: MediaPlayerPlaybackStatus = .playing) -> MediaPlayerStatus {
    MediaPlayerStatus(generationTimestamp: 10, duration: duration, dimensions: .zero, timestamp: timestamp, baseRate: rate, volume: 1, seekId: 0, status: status)
}
final class APSongItem {
    var onState: ((APState) -> Void)?
    var state: APState = .playing(current: 25, duration: 100, progress: 0.25) { didSet { onState?(state) } }
    var status = makeStatus()
    let songName: String
    let performerName = "Artist"
    var coverResource: Resource?
    init(_ name: String) { songName = name }
    __PUBLISH__
}
final class MPNowPlayingInfoCenter {
    enum State { case playing, paused, stopped }
    static let instance = MPNowPlayingInfoCenter()
    static func `default`() -> MPNowPlayingInfoCenter { instance }
    var nowPlayingInfo: [String: Any]? { didSet { if !Thread.isMainThread { backgroundMutations += 1 } } }
    var playbackState = State.stopped { didSet { if !Thread.isMainThread { backgroundMutations += 1 } } }
}
enum MPRemoteCommandHandlerStatus { case success, commandFailed }
class MPRemoteCommandEvent {}
final class MPChangePlaybackPositionCommandEvent: MPRemoteCommandEvent {
    let positionTime: Double
    init(_ position: Double) { positionTime = position }
}
final class Token { let id = UUID() }
final class Command {
    var isEnabled = true
    var handlers: [UUID: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus] = [:]
    var nilRemovals = 0
    func addTarget(handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) -> Any {
        let token = Token()
        handlers[token.id] = handler
        return token
    }
    func removeTarget(_ target: Any?) {
        if !Thread.isMainThread { backgroundMutations += 1 }
        guard let token = target as? Token else { nilRemovals += 1; handlers.removeAll(); return }
        handlers.removeValue(forKey: token.id)
    }
    func fire(_ event: MPRemoteCommandEvent = MPRemoteCommandEvent()) -> [MPRemoteCommandHandlerStatus] {
        Array(handlers.values).map { $0(event) }
    }
    var first: (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus { handlers.values.first ?? { _ in .commandFailed } }
}
final class MPRemoteCommandCenter {
    static let instance = MPRemoteCommandCenter()
    static func shared() -> MPRemoteCommandCenter { instance }
    let playCommand = Command(), pauseCommand = Command(), nextTrackCommand = Command(), previousTrackCommand = Command(), togglePlayPauseCommand = Command(), changePlaybackPositionCommand = Command()
    var commands: [Command] { [playCommand, pauseCommand, nextTrackCommand, previousTrackCommand, togglePlayPauseCommand, changePlaybackPositionCommand] }
}
__CONTROL__

final class PlayerOwner {
    let controlCenter: ControlCenter
    init() {
        self.controlCenter = ControlCenter(account: Account())
__BINDINGS__
    func play() -> Bool { true }
    func pause() -> Bool { true }
    func next() -> Bool { true }
    func prev() -> Bool { true }
    func playOrPause() -> Bool { true }
    func set(seek: TimeInterval) -> Bool { true }
}
var failures: [String] = []
func check(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { failures.append(message) } }
let commands = MPRemoteCommandCenter.shared()
let info = MPNowPlayingInfoCenter.default()
func activated(_ name: String) -> ControlCenter {
    let value = ControlCenter(account: Account())
    value.activate()
    value.setupNowPlaying(APSongItem(name))
    return value
}
func title() -> String? { info.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String }
func flush() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
func currentArtwork() -> MPMediaItemArtwork? { info.nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork }
func testArtwork(_ name: String) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("cover").path
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.setColor(.red, atX: 0, y: 0)
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    var owner: ControlCenter? = ControlCenter(account: Account())
    let box = owner!.account.postbox.mediaBox
    var song: APSongItem? = APSongItem("first")
    song!.coverResource = Resource(id: "first")
    let complete = MediaResourceData(complete: true, path: path)
    if ["artwork-reuse", "artwork-change", "artwork-clear", "artwork-reactivate", "artwork-background-release"].contains(name) { box.initial["first"] = complete }
    if name == "artwork-corrupt" {
        try! Data("not an image".utf8).write(to: URL(fileURLWithPath: path))
        box.initial["first"] = complete
    }
    owner!.activate()
    owner!.setupNowPlaying(song!)
    flush()
    switch name {
    case "artwork-reuse":
        let first = currentArtwork()
        check(first != nil, "Complete image was not loaded")
        for current in 1...100 {
            song!.state = .playing(current: Double(current), duration: 100, progress: Double(current) / 100)
            owner!.setupNowPlaying(song!)
        }
        check(imageLoads == 1 && currentArtwork() === first, "Progress updates reload cached artwork")
        check(box.subscriptions == 1 && box.observers == 0, "Complete resource observer was not released")
    case "artwork-late":
        check(currentArtwork() == nil && box.observers == 1, "Missing resource not observed")
        box.pipe("first").putNext(MediaResourceData(complete: false, path: path))
        flush()
        check(imageLoads == 0, "Partial image was opened")
        song!.state = .playing(current: 75, duration: 100, progress: 0.75)
        owner!.setupNowPlaying(song!)
        box.pipe("first").putNext(complete)
        flush()
        check(currentArtwork() != nil && imageLoads == 1, "Late cover not published")
        check((info.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue == 75, "Late cover restored an old timestamp")
        check(box.observers == 0, "Complete observer leaked")
    case "artwork-change":
        weak var oldImage = currentArtwork()?.image
        let next = APSongItem("second")
        next.coverResource = Resource(id: "second")
        owner!.setupNowPlaying(next)
        flush()
        check(title() == "second" && currentArtwork() == nil, "Old cover survives song replacement")
        check(oldImage == nil, "Previous cover image retained")
        box.pipe("second").putNext(complete)
        flush()
        check(currentArtwork() != nil && imageLoads == 2, "Replacement cover not loaded")
        next.coverResource = nil
        owner!.setupNowPlaying(next)
        check(currentArtwork() == nil && box.observers == 0, "Nil resource left artwork state")
    case "artwork-clear":
        weak var oldImage = currentArtwork()?.image
        owner!.clearNowPlaying()
        flush()
        check(currentArtwork() == nil && oldImage == nil && box.observers == 0, "Cleanup retained artwork")
    case "artwork-takeover":
        let current = activated("second")
        check(box.observers == 0, "Inactive player retained cover observer")
        box.pipe("first").putNext(complete)
        flush()
        check(title() == "second" && currentArtwork() == nil && imageLoads == 0, "Inactive cover overwrote new owner")
        withExtendedLifetime(current) {}
    case "artwork-deinit":
        weak var weakOwner = owner
        owner = nil
        check(weakOwner == nil && box.observers == 0, "Deinit leaked owner or cover observer")
    case "artwork-queued":
        let done = DispatchSemaphore(value: 0)
        let pipe = box.pipe("first")
        DispatchQueue.global().async { pipe.putNext(complete); done.signal() }
        check(done.wait(timeout: .now() + 2) == .success, "Resource delivery blocked")
        let next = APSongItem("second")
        owner!.setupNowPlaying(next)
        flush()
        check(title() == "second" && currentArtwork() == nil && imageLoads == 0, "Queued old cover decoded or published")
    case "artwork-reactivate":
        owner!.clearNowPlaying()
        owner!.activate()
        owner!.setupNowPlaying(song!)
        flush()
        check(currentArtwork() != nil && imageLoads == 2 && box.subscriptions == 2, "Reactivation failed to reload cover")
    case "artwork-corrupt":
        check(currentArtwork() == nil, "Corrupt image accepted")
        for _ in 0..<100 { owner!.setupNowPlaying(song!) }
        check(imageLoads == 1 && box.observers == 0, "Corrupt cover retried on each tick")
        try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        owner!.clearNowPlaying()
        owner!.activate()
        owner!.setupNowPlaying(song!)
        flush()
        check(currentArtwork() != nil && imageLoads == 2, "New playback session cannot retry corrected image")
    case "artwork-no-song-retention":
        weak var weakSong = song
        song = nil
        check(weakSong == nil, "Cover observer retained song")
        check(box.observers == 1, "Pending cover is not observed independently of the song")
        owner!.clearNowPlaying()
        check(box.observers == 0, "Pending cover observer survived clear")
    case "artwork-background-delivery":
        let done = DispatchSemaphore(value: 0)
        let pipe = box.pipe("first")
        DispatchQueue.global().async { pipe.putNext(complete); done.signal() }
        check(done.wait(timeout: .now() + 2) == .success, "Background resource completion blocked")
        flush()
        check(currentArtwork() != nil && imageLoads == 1 && box.observers == 0, "Background image did not reach active metadata")
    case "artwork-same-resource-song":
        let next = APSongItem("second")
        next.coverResource = Resource(id: "first")
        next.state = .paused(current: 60, duration: 200, progress: 0.3)
        owner!.setupNowPlaying(next)
        box.pipe("first").putNext(complete)
        flush()
        check(title() == "second" && currentArtwork() != nil, "Shared cover replaced the new song metadata")
        check((info.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? NSNumber)?.doubleValue == 60 && info.playbackState == .paused, "Shared cover replaced paused timing")
        let artwork = currentArtwork()
        owner!.setupNowPlaying(next)
        check(box.subscriptions == 1 && imageLoads == 1 && currentArtwork() === artwork, "Shared cover was not reused")
    case "artwork-background-release":
        final class OwnerBox { var value: ControlCenter? }
        let holder = OwnerBox()
        holder.value = owner
        owner = nil
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { holder.value = nil; done.signal() }
        check(done.wait(timeout: .now() + 2) == .success, "Artwork owner disposal blocked main")
        flush()
        check(title() == nil && currentArtwork() == nil && box.observers == 0, "Background artwork release left presentation")
    default: fatalError("Unknown artwork case")
    }
    check(backgroundImageLoads == 0 && backgroundMutations == 0, "Artwork decoded or published off main")
    withExtendedLifetime(owner) {}
}
switch CommandLine.arguments[1] {
case let name where name.hasPrefix("artwork-"):
    testArtwork(name)
case "inactive-init":
    let first = activated("first")
    let next = ControlCenter(account: Account())
    check(commands.commands.allSatisfy { $0.handlers.count == 1 }, "Inactive controller registered handlers")
    check(title() == "first", "Inactive controller replaced metadata")
    withExtendedLifetime((first, next)) {}
case "publish":
    let owner = activated("song")
    check(title() == "song", "Title missing")
    check(info.playbackState == .playing, "Playing state missing")
    owner.clearNowPlaying()
    check(title() == nil && info.playbackState == .stopped, "Active cleanup failed")
case "old-clear":
    let old = activated("old"), current = activated("current")
    old.clearNowPlaying()
    check(title() == "current", "Old controller erased current metadata")
    check(commands.commands.allSatisfy { $0.handlers.count == 1 }, "Current handlers were removed")
    withExtendedLifetime(current) {}
case "old-deinit":
    var old: ControlCenter? = activated("old")
    weak var weakOld = old
    let current = activated("current")
    old = nil
    check(weakOld == nil, "Old owner retained")
    check(title() == "current", "Old deinit erased current metadata")
    withExtendedLifetime(current) {}
case "active-deinit":
    var owner: ControlCenter? = activated("song")
    weak var weakOwner = owner
    owner = nil
    check(weakOwner == nil, "Owner retained")
    check(title() == nil && info.playbackState == .stopped, "Active deinit did not clear metadata")
    check(commands.commands.allSatisfy { $0.handlers.isEmpty }, "Active deinit left handlers")
case "ownership-takeover":
    let old = activated("old"), current = activated("current")
    var oldCalls = 0, currentCalls = 0
    old.play = { oldCalls += 1; return true }
    current.play = { currentCalls += 1; return true }
    let results = commands.playCommand.fire()
    check(results == [.success] && currentCalls == 1 && oldCalls == 0, "Remote command reached multiple players")
case "stale-publish":
    let old = activated("old"), current = activated("current")
    old.setupNowPlaying(APSongItem("stale"))
    check(title() == "current", "Old status update reclaimed metadata")
    withExtendedLifetime(current) {}
case "idempotent-setup":
    let owner = activated("song")
    owner.setupRemoteTransportControls()
    owner.activate()
    owner.setupRemoteTransportControls()
    check(commands.commands.allSatisfy { $0.handlers.count == 1 }, "Duplicate registrations")
    owner.clearNowPlaying()
    check(commands.commands.allSatisfy { $0.handlers.isEmpty }, "Duplicate targets survived cleanup")
case "repeated-clear":
    let owner = activated("song")
    _ = commands.playCommand.addTarget { _ in .success }
    owner.clearNowPlaying()
    owner.clearNowPlaying()
    check(commands.playCommand.handlers.count == 1, "Cleanup removed unrelated handler")
    check(commands.commands.allSatisfy { $0.nilRemovals == 0 }, "Cleanup called removeTarget(nil)")
case "reactivation":
    let owner = activated("song")
    owner.play = { true }
    owner.clearNowPlaying()
    owner.activate()
    owner.setupNowPlaying(APSongItem("again"))
    check(commands.playCommand.fire() == [.success], "Reactivation did not register controls")
    check(title() == "again", "Reactivation did not publish")
case "expired-command":
    let owner = activated("song")
    var calls = 0
    owner.play = { calls += 1; return true }
    let old = commands.playCommand.first
    owner.clearNowPlaying()
    owner.activate()
    check(old(MPRemoteCommandEvent()) == .commandFailed && calls == 0, "Expired handler affected reactivated session")
case "late-command":
    var owner: ControlCenter? = activated("song")
    owner?.play = { true }
    let saved = commands.playCommand.first
    owner = nil
    check(saved(MPRemoteCommandEvent()) == .commandFailed, "Handler used released controller")
case "released-player":
    var owner: PlayerOwner? = PlayerOwner()
    let bridge = owner!.controlCenter
    owner = nil
    check(!bridge.play() && !bridge.pause() && !bridge.nextTrack() && !bridge.prevTrack() && !bridge.togglePlayPause() && !bridge.seek(10), "Bridge called released player")
case "availability":
    let owner = activated("song")
    for next in [false, true] {
        for previous in [false, true] {
            owner.updateControlsAvaiability(nextEnabled: next, prevEnabled: previous)
            check(commands.nextTrackCommand.isEnabled == next, "Next availability follows Previous")
            check(commands.previousTrackCommand.isEnabled == previous, "Previous availability incorrect")
        }
    }
case "stale-availability":
    let old = activated("old"), current = activated("current")
    current.updateControlsAvaiability(nextEnabled: true, prevEnabled: false)
    old.updateControlsAvaiability(nextEnabled: false, prevEnabled: true)
    check(commands.nextTrackCommand.isEnabled && !commands.previousTrackCommand.isEnabled, "Inactive owner changed availability")
case "command-routing":
    let owner = activated("song")
    var counts = Array(repeating: 0, count: 6)
    owner.play = { counts[0] += 1; return true }
    owner.pause = { counts[1] += 1; return false }
    owner.nextTrack = { counts[2] += 1; return true }
    owner.prevTrack = { counts[3] += 1; return true }
    owner.togglePlayPause = { counts[4] += 1; return true }
    owner.seek = { value in counts[5] += 1; return value == 12 }
    for i in 0..<6 {
        let result = commands.commands[i].fire(i == 5 ? MPChangePlaybackPositionCommandEvent(12) : MPRemoteCommandEvent())
        check(result == [i == 1 ? .commandFailed : .success], "Wrong command result")
    }
    check(counts == [1, 1, 1, 1, 1, 1], "Wrong command dispatch")
case "seek-validation":
    let owner = activated("song")
    var calls = 0
    owner.seek = { _ in calls += 1; return true }
    for event in [MPRemoteCommandEvent(), MPChangePlaybackPositionCommandEvent(.nan), MPChangePlaybackPositionCommandEvent(.infinity)] {
        check(commands.changePlaybackPositionCommand.fire(event) == [.commandFailed], "Invalid seek accepted")
    }
    check(calls == 0, "Invalid seek reached player")
case "background-command":
    let owner = activated("song")
    var onMain = false
    owner.play = { onMain = Thread.isMainThread; return true }
    let callback = commands.playCommand.first
    let done = DispatchSemaphore(value: 0)
    var result = MPRemoteCommandHandlerStatus.commandFailed
    DispatchQueue.global().async { result = callback(MPRemoteCommandEvent()); done.signal() }
    while done.wait(timeout: .now()) == .timedOut { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    check(onMain && result == .success, "Remote command did not execute on main")
    withExtendedLifetime(owner) {}
case "background-deinit", "background-deinit-takeover":
    final class OwnerBox { var value: ControlCenter?; init(_ value: ControlCenter) { self.value = value } }
    let box = OwnerBox(activated("old"))
    weak var weakOwner = box.value
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { box.value = nil; done.signal() }
    check(done.wait(timeout: .now() + 2) == .success, "Background release blocked main")
    var current: ControlCenter?
    if CommandLine.arguments[1] == "background-deinit-takeover" { current = activated("current") }
    RunLoop.current.run(until: Date().addingTimeInterval(0.03))
    check(weakOwner == nil, "Background-released controller retained")
    check(backgroundMutations == 0, "Background deinit mutated system controls off main")
    if let current {
        check(title() == "current", "Queued old release erased current metadata")
        check(commands.commands.allSatisfy { $0.handlers.count == 1 }, "Queued old release removed current handlers")
        withExtendedLifetime(current) {}
    } else {
        check(title() == nil, "Background deinit did not clear metadata")
        check(commands.commands.allSatisfy { $0.handlers.isEmpty }, "Background deinit left handlers")
    }
case "paused-metadata":
    let owner = activated("song"), song = APSongItem("song")
    song.status = makeStatus(rate: 2)
    song.state = .paused(current: 32, duration: 100, progress: 0.32)
    owner.setupNowPlaying(song)
    check(info.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0, "Paused metadata advances playback")
    check(info.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 32, "Paused elapsed time is stale")
    check(info.playbackState == .paused, "Paused state incorrect")
case "interpolated-metadata":
    let owner = activated("song"), song = APSongItem("song")
    song.status = makeStatus(timestamp: 25, rate: 1.5)
    song.state = .playing(current: 28, duration: 100, progress: 0.28)
    owner.setupNowPlaying(song)
    check(info.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 28, "Progress tick republishes old decoder time")
    check(info.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.5, "Playback rate incorrect")
case "inactive-metadata":
    let owner = activated("song"), song = APSongItem("song")
    for state: APState in [.waiting, .fetching(0.2), .stoped] {
        song.state = state
        owner.setupNowPlaying(song)
        check(info.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0, "Inactive metadata advances playback")
    }
    check(info.playbackState == .stopped, "Stopped song advertised as paused")
case "invalid-metadata":
    let owner = activated("song"), song = APSongItem("song")
    song.status = makeStatus(timestamp: .infinity, duration: .nan, rate: .infinity)
    song.state = .playing(current: .infinity, duration: .nan, progress: 0)
    owner.setupNowPlaying(song)
    for key in [MPMediaItemPropertyPlaybackDuration, MPNowPlayingInfoPropertyElapsedPlaybackTime, MPNowPlayingInfoPropertyPlaybackRate] {
        check((info.nowPlayingInfo?[key] as? NSNumber)?.doubleValue == 0, "Invalid numeric metadata reached OS for \(key)")
    }
case "bounded-metadata":
    let owner = activated("song"), song = APSongItem("song")
    song.status = makeStatus(rate: -1)
    for current in [-10.0, 110.0] {
        song.state = .playing(current: current, duration: 100, progress: 0)
        owner.setupNowPlaying(song)
        check(info.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == max(0, min(100, current)), "Elapsed time not clamped")
        check(info.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0, "Negative rate not bounded")
    }
case "publication-order":
    let song = APSongItem("song")
    var observed: MediaPlayerStatus?
    song.onState = { _ in observed = song.status }
    song.setStatus(makeStatus(timestamp: 40, duration: 200, rate: 2), rate: 2)
    check(observed?.timestamp == 40 && observed?.duration == 200 && observed?.baseRate == 2, "Observer read old status")
    song.onState = nil
case "publication-reentry":
    let song = APSongItem("song")
    song.onState = { _ in
        song.onState = nil
        song.setStatus(makeStatus(timestamp: 70, duration: 200, rate: 2, status: .paused), rate: 2)
    }
    song.setStatus(makeStatus(timestamp: 40, duration: 150), rate: 1)
    check(song.status.timestamp == 70 && song.status.duration == 200 && song.status.baseRate == 2, "Outer publication overwrote newer status")
    if case let .paused(current, _, _) = song.state { check(current == 70, "State diverged from current status") } else { check(false, "New paused state lost") }
case "buffering-publication":
    let owner = activated("song"), song = APSongItem("song")
    song.onState = { _ in owner.setupNowPlaying(song) }
    song.setStatus(makeStatus(timestamp: 50, duration: 80, rate: 2, status: .buffering(initial: false, whilePlaying: true)), rate: 2)
    check(info.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 50, "Buffering timestamp stale")
    check(info.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0, "Buffering metadata advances")
    check(song.status.duration == 100, "Known duration was discarded")
    song.onState = nil
default: fatalError("Unknown case")
}
for failure in failures { print(failure) }
exit(failures.isEmpty ? 0 : 1)
