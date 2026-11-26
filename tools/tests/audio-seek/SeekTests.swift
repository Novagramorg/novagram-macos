import Foundation
import Cocoa

__STATUS__
__STATE__

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        print(message)
        exit(1)
    }
}

final class Song {
    var status: MediaPlayerStatus
    var state: APState = .waiting
    init(duration: Double = 200, playback: MediaPlayerPlaybackStatus = .paused) {
        status = MediaPlayerStatus(generationTimestamp: 5, duration: duration, dimensions: CGSize(width: 40, height: 40), timestamp: 10, baseRate: 1.5, volume: 0.5, seekId: 3, status: playback)
    }
    __PROGRESS__
}

final class Player {
    var positions: [Double] = []
    func seek(timestamp: Double) { positions.append(timestamp) }
}

final class Controller {
    var mediaPlayer: Player? = Player()
    var song: Song? = Song()
    var notifications = 0
    var timerStops = 0
    var notifiedTimestamp: Double?
    func stopTimer() { timerStops += 1 }
    func notifyStateChanged(item: Song, animated: Bool) {
        notifications += 1
        notifiedTimestamp = item.status.timestamp
    }
    __SEEK__
}

func verify(_ controller: Controller, position: Double, progress: Double, playing: Bool = false) {
    check(controller.mediaPlayer?.positions.last == position, "wrong player seek position")
    check(controller.song?.status.timestamp == position, "elapsed time did not move to seek target")
    check(controller.notifiedTimestamp == position, "listeners received an outdated elapsed time")
    let expected: APState = playing ? .playing(current: position, duration: 200, progress: progress) : .paused(current: position, duration: 200, progress: progress)
    check(controller.song?.state == expected, "progress or playback state does not match seek target")
    check(controller.timerStops == controller.notifications, "old interpolation timer was not stopped for each seek")
}

let controller = Controller()
switch CommandLine.arguments[1] {
case "quarter":
    check(controller.set(seek: 50), "seek rejected")
    verify(controller, position: 50, progress: 0.25)
case "start":
    check(controller.set(seek: 0), "start seek rejected")
    verify(controller, position: 0, progress: 0)
case "bounds":
    check(controller.set(seek: -10), "negative seek rejected instead of clamped")
    verify(controller, position: 0, progress: 0)
    check(controller.set(seek: 1000), "end seek rejected instead of clamped")
    verify(controller, position: 200, progress: 1)
case "invalid-position":
    for position in [Double.nan, .infinity, -.infinity] {
        check(!controller.set(seek: position), "non-finite seek accepted")
    }
    check(controller.mediaPlayer!.positions.isEmpty && controller.notifications == 0 && controller.timerStops == 0, "invalid seek had side effects")
case "invalid-duration":
    for duration in [0, -1, Double.nan, .infinity, -.infinity] {
        controller.song = Song(duration: duration)
        check(!controller.set(seek: 10), "invalid duration accepted for timestamp seek")
        check(!controller.set(trackProgress: 0.5), "invalid duration accepted for fractional seek")
    }
    check(controller.mediaPlayer!.positions.isEmpty && controller.notifications == 0 && controller.timerStops == 0, "invalid duration had side effects")
case "unavailable":
    controller.song = nil
    check(!controller.set(seek: 10) && !controller.set(trackProgress: 0.5), "missing song accepted")
    check(controller.mediaPlayer!.positions.isEmpty, "player moved without song")
    controller.song = Song()
    controller.mediaPlayer = nil
    check(!controller.set(seek: 10) && !controller.set(trackProgress: 0.5), "missing player accepted")
    check(controller.notifications == 0 && controller.timerStops == 0, "unavailable seek had side effects")
case "fraction":
    check(controller.set(trackProgress: 0.75), "fractional seek rejected")
    verify(controller, position: 150, progress: 0.75)
case "fraction-bounds":
    check(controller.set(trackProgress: -2), "negative progress rejected instead of clamped")
    verify(controller, position: 0, progress: 0)
    check(controller.set(trackProgress: 3), "excess progress rejected instead of clamped")
    verify(controller, position: 200, progress: 1)
case "invalid-fraction":
    for progress in [Float.nan, .infinity, -.infinity] {
        check(!controller.set(trackProgress: progress), "non-finite fraction accepted")
    }
    check(controller.mediaPlayer!.positions.isEmpty && controller.notifications == 0 && controller.timerStops == 0, "invalid fraction had side effects")
case "item-validation":
    let song = Song()
    let original = song.status
    for progress in [Double.nan, .infinity, -.infinity] {
        song.setProgress(progress)
        check(song.state == .waiting && song.status == original, "invalid progress mutated item")
    }
    song.setProgress(2)
    check(song.state == .paused(current: 200, duration: 200, progress: 1), "item did not clamp high progress")
    song.setProgress(-1)
    check(song.state == .paused(current: 0, duration: 200, progress: 0), "item did not clamp low progress")
case "playing":
    controller.song = Song(playback: .playing)
    let original = controller.song!.status
    check(controller.set(seek: 50), "playing seek rejected")
    verify(controller, position: 50, progress: 0.25, playing: true)
    check(controller.song!.status == original.withUpdatedTimestamp(50), "seek changed unrelated playback metadata")
case "buffering":
    controller.song = Song(playback: .buffering(initial: false, whilePlaying: true))
    check(controller.set(seek: 100), "buffered seek rejected")
    check(controller.song!.status.timestamp == 100, "buffered seek did not update elapsed time")
    check(controller.song!.state == .waiting, "buffered seek invented playing state")
    check(controller.notifications == 1 && controller.timerStops == 1, "buffered seek did not update lifecycle")
default:
    fatalError("unknown test")
}
