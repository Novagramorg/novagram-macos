import Foundation
import SwiftSignalKit
import Postbox
import CoreMedia
import TelegramCore
import TelegramMediaPlayer
import QuartzCore

public enum MediaPlayerSeek {
    case none
    case start
    case automatic
    case timecode(Double)
}

private struct MediaPlayerSeekState {
    let duration: Double
}

public enum ChunkMediaPlayerActionAtEnd {
    case loop((() -> Void)?)
    case action(() -> Void)
    case loopDisablingSound(() -> Void)
    case stop
}





public protocol ChunkMediaPlayer: AnyObject {
    var status: Signal<MediaPlayerStatus, NoError> { get }
    var audioLevelEvents: Signal<Float, NoError> { get }
    var actionAtEnd: ChunkMediaPlayerActionAtEnd { get set }
    
    func play()
    func playOnceWithSound(playAndRecord: Bool, seek: MediaPlayerSeek)
    func setSoundMuted(soundMuted: Bool)
    func continueWithOverridingAmbientMode(isAmbient: Bool)
    func continuePlayingWithoutSound(seek: MediaPlayerSeek)
    func setContinuePlayingWithoutSoundOnLostAudioSession(_ value: Bool)
    func setForceAudioToSpeaker(_ value: Bool)
    func setKeepAudioSessionWhilePaused(_ value: Bool)
    func pause()
    func togglePlayPause(faded: Bool)
    func seek(timestamp: Double, play: Bool?)
    func setBaseRate(_ baseRate: Double)
    func setVolume(volume: Float)
}
