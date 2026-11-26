import Foundation
import AVFoundation
import ImageIO
import CoreServices
import SwiftSignalKit

struct EditedAvatarVideoRange {
    let timeRange: CMTimeRange
    let thumbnailTime: CMTime
    let keyFrame: Double?

    init?(duration: Double, leftTrim: Double, rightTrim: Double, keyFrame: Double?) {
        guard duration.isFinite, duration > 0, leftTrim.isFinite, rightTrim.isFinite, leftTrim >= 0, rightTrim <= 1, leftTrim < rightTrim, keyFrame?.isFinite != false else { return nil }
        let start = CMTime(seconds: leftTrim * duration, preferredTimescale: 1000)
        let end = CMTime(seconds: rightTrim * duration, preferredTimescale: 1000)
        guard start.isNumeric, end.isNumeric, end > start else { return nil }
        self.timeRange = CMTimeRange(start: start, end: end)
        let thumbnail = min(max(start.seconds, (keyFrame ?? leftTrim) * duration), max(start.seconds, end.seconds - 0.05))
        guard thumbnail.isFinite else { return nil }
        let thumbnailTime = CMTime(seconds: thumbnail, preferredTimescale: 1000)
        self.thumbnailTime = thumbnailTime
        self.keyFrame = keyFrame.map { _ in max(0, thumbnailTime.seconds - start.seconds) }
    }
}

private final class EditedAvatarVideoFiles {
    let videoPath = NSTemporaryDirectory() + "avatar_\(UUID().uuidString).mp4"
    let thumbnailPath = NSTemporaryDirectory() + "avatar_\(UUID().uuidString).jpg"
    private let transferred = Atomic(value: false)

    func transfer() {
        _ = self.transferred.swap(true)
    }

    func removeUnclaimed() {
        guard !self.transferred.with({ $0 }) else { return }
        try? FileManager.default.removeItem(atPath: self.videoPath)
        try? FileManager.default.removeItem(atPath: self.thumbnailPath)
    }

    deinit {
        self.removeUnclaimed()
    }
}

private final class EditedAvatarVideoExport {
    static let queue = Queue(name: "org.telegram.edited-avatar-export")
    private let cancelled = Atomic(value: false)
    private let files = EditedAvatarVideoFiles()
    private let subscriber: Subscriber<VideoAvatarGeneratorState, NoError>
    private var exportSession: AVAssetExportSession?
    private var timer: SwiftSignalKit.Timer?
    private var started = false
    private var finished = false

    init(subscriber: Subscriber<VideoAvatarGeneratorState, NoError>) {
        self.subscriber = subscriber
    }

    deinit {
        self.timer?.invalidate()
        self.exportSession?.cancelExport()
        self.files.removeUnclaimed()
    }

    func start(asset: AVComposition, composition: AVVideoComposition, quality: String, range: EditedAvatarVideoRange) {
        guard !self.started, !self.finished else { return }
        self.started = true
        guard !self.cancelled.with({ $0 }), let exportSession = AVAssetExportSession(asset: asset, presetName: quality), exportSession.supportedFileTypes.contains(.mp4) else {
            self.finish(keyFrame: nil, succeeded: false)
            return
        }
        self.exportSession = exportSession
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.outputURL = URL(fileURLWithPath: self.files.videoPath)
        exportSession.videoComposition = composition
        exportSession.timeRange = range.timeRange
        if #available(OSX 10.14, *) {
            exportSession.fileLengthLimit = 2 * 1024 * 1024
        }
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.maximumSize = CGSize(width: 640, height: 640)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.videoComposition = composition
        guard let image = try? imageGenerator.copyCGImage(at: range.thumbnailTime, actualTime: nil), let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: self.files.thumbnailPath) as CFURL, kUTTypeJPEG, 1, nil) else {
            self.finish(keyFrame: nil, succeeded: false)
            return
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.3] as CFDictionary)
        guard CGImageDestinationFinalize(destination), !self.cancelled.with({ $0 }) else {
            self.finish(keyFrame: nil, succeeded: false)
            return
        }
        self.subscriber.putNext(.start(thumb: self.files.thumbnailPath))
        guard !self.cancelled.with({ $0 }) else {
            self.finish(keyFrame: nil, succeeded: false)
            return
        }
        let timer = SwiftSignalKit.Timer(timeout: 0.05, repeat: true, completion: { [weak self] in
            guard let self, !self.finished, !self.cancelled.with({ $0 }), let progress = self.exportSession?.progress, progress.isFinite else { return }
            self.subscriber.putNext(.progress(min(1, max(0, progress))))
        }, queue: Self.queue)
        self.timer = timer
        timer.start()
        let files = self.files
        exportSession.exportAsynchronously { [weak self, files] in
            Self.queue.async {
                guard let self else {
                    files.removeUnclaimed()
                    return
                }
                guard !self.finished else {
                    files.removeUnclaimed()
                    return
                }
                let succeeded = self.exportSession?.status == .completed && self.exportSession?.error == nil
                self.finish(keyFrame: range.keyFrame, succeeded: succeeded)
            }
        }
    }

    private func finish(keyFrame: Double?, succeeded: Bool) {
        guard !self.finished else { return }
        self.finished = true
        self.timer?.invalidate()
        self.timer = nil
        var completed = succeeded && !self.cancelled.with({ $0 })
        var keyFrame = keyFrame
        if completed {
            let asset = AVURLAsset(url: URL(fileURLWithPath: self.files.videoPath))
            let duration = asset.duration.seconds
            completed = duration.isFinite && duration > 0 && !asset.tracks(withMediaType: .video).isEmpty
            if let value = keyFrame {
                keyFrame = max(0, min(value, duration - 0.05))
            }
        }
        if completed && !self.cancelled.with({ $0 }) {
            self.exportSession = nil
            self.files.transfer()
            self.subscriber.putNext(.complete(thumb: self.files.thumbnailPath, video: self.files.videoPath, keyFrame: keyFrame))
            self.subscriber.putCompletion()
        } else {
            self.exportSession?.cancelExport()
            self.exportSession = nil
            self.files.removeUnclaimed()
            if !self.cancelled.with({ $0 }) {
                self.subscriber.putNext(.error)
                self.subscriber.putCompletion()
            }
        }
    }

    func cancel() {
        _ = self.cancelled.swap(true)
        Self.queue.async {
            self.finish(keyFrame: nil, succeeded: false)
        }
    }
}

func generateEditedAvatarVideo(_ asset: AVComposition, composition: AVVideoComposition, quality: String, leftTrim: Double, rightTrim: Double, keyFrame: Double?) -> Signal<VideoAvatarGeneratorState, NoError> {
    return Signal { subscriber in
        let operation = EditedAvatarVideoExport(subscriber: subscriber)
        EditedAvatarVideoExport.queue.justDispatch {
            guard let range = EditedAvatarVideoRange(duration: asset.duration.seconds, leftTrim: leftTrim, rightTrim: rightTrim, keyFrame: keyFrame) else {
                subscriber.putNext(.error)
                subscriber.putCompletion()
                return
            }
            operation.start(asset: asset, composition: composition, quality: quality, range: range)
        }
        return ActionDisposable {
            operation.cancel()
        }
    }
}
