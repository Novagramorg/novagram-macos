import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramMedia
import ObjcUtils
import TGVideoCameraMovie
import AVFoundation
import MediaRecorderUI

public final class RecordingPreviewPlayer {
    private let player: MediaPlayer
    private let statusDisposable = MetaDisposable()
    private var status: MediaPlayerStatus?
    private var progressAnimator: ConstantDisplayLinkAnimator?
    private var trimRange: Range<Double>

    public private(set) var position: Double
    public private(set) var isPlaying: Bool = false

    public var onUpdate: (() -> Void)?

    public init(postbox: Postbox, preview: ChatRecordingPreviewData, trimRange: Range<Double>) {
        self.trimRange = trimRange
        self.position = trimRange.lowerBound

        let resource = LocalFileReferenceMediaResource(localFilePath: preview.path, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: false, size: fileSize(preview.path))
        self.player = MediaPlayer(postbox: postbox, userLocation: .other, userContentType: preview.waveform == nil ? .video : .audio, reference: .standalone(resource: resource), streamable: false, video: false, preferSoftwareDecoding: false, enableSound: true, fetchAutomatically: true)

        player.actionAtEnd = .action { [weak self] in
            Queue.mainQueue().async {
                self?.restartFromTrimStart()
            }
        }

        let animator = ConstantDisplayLinkAnimator(update: { [weak self] in
            self?.updateProgress()
        }, fps: 30)
        animator.isPaused = true
        self.progressAnimator = animator

        statusDisposable.set((player.status |> deliverOnMainQueue).start(next: { [weak self] status in
            self?.apply(status)
        }))
    }

    deinit {
        statusDisposable.dispose()
        progressAnimator?.isPaused = true
        player.pause()
    }

    public func toggle() {
        if isPlaying {
            player.pause()
        } else {
            if position >= trimRange.upperBound - 0.05 || position < trimRange.lowerBound {
                player.seek(timestamp: trimRange.lowerBound)
            }
            player.play()
        }
    }

    public func seek(to value: Double) {
        position = clampedToTrim(value)
        status = nil
        player.seek(timestamp: position)
        onUpdate?()
    }

    public func updateTrim(_ range: Range<Double>, updatedEnd: Bool, applied: Bool) {
        trimRange = range
        if applied {
            seek(to: updatedEnd ? max(range.lowerBound, range.upperBound - 1.0) : range.lowerBound)
        } else if position < range.lowerBound || position > range.upperBound {
            seek(to: range.lowerBound)
        } else {
            onUpdate?()
        }
    }

    private func clampedToTrim(_ value: Double) -> Double {
        return min(trimRange.upperBound, max(trimRange.lowerBound, value))
    }

    private func apply(_ status: MediaPlayerStatus) {
        self.status = status
        switch status.status {
        case .playing:
            isPlaying = true
        case let .buffering(_, whilePlaying):
            isPlaying = whilePlaying
        default:
            isPlaying = false
        }
        progressAnimator?.isPaused = !isPlaying
        updateProgress()
    }

    private func updateProgress() {
        var position = self.position
        if let status {
            if isPlaying, status.generationTimestamp > 0 {
                position = status.timestamp + max(0.0, CACurrentMediaTime() - status.generationTimestamp) * status.baseRate
            } else {
                position = status.timestamp
            }
        }
        if isPlaying, position >= trimRange.upperBound {
            restartFromTrimStart()
            return
        }
        self.position = clampedToTrim(position)
        onUpdate?()
    }

    private func restartFromTrimStart() {
        player.pause()
        status = nil
        player.seek(timestamp: trimRange.lowerBound)
        isPlaying = false
        progressAnimator?.isPaused = true
        position = trimRange.lowerBound
        onUpdate?()
    }
}
