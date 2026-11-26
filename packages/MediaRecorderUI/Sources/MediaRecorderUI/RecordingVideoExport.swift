import Foundation
import AVFoundation
import SwiftSignalKit

final class RecordingVideoExportResult {
    let path: String
    let duration: Double
    private let owned = Atomic(value: true)

    init(path: String, duration: Double) {
        self.path = path
        self.duration = duration
    }

    func takePath() -> String? {
        guard owned.swap(false) else { return nil }
        return path
    }

    func discard() {
        guard owned.swap(false) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    deinit {
        discard()
    }
}

private final class RecordingVideoExportStorage {
    let path = NSTemporaryDirectory() + "recording_\(UUID().uuidString).mp4"
    private let transferred = Atomic(value: false)

    func transfer(duration: Double) -> RecordingVideoExportResult {
        _ = transferred.swap(true)
        return RecordingVideoExportResult(path: path, duration: duration)
    }

    func removeUnclaimed() {
        guard !transferred.with({ $0 }) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    deinit {
        removeUnclaimed()
    }
}

private final class RecordingVideoExportOperation {
    static let queue = Queue(name: "org.telegram.recording-video-export")
    private let cancelled = Atomic(value: false)
    private let storage = RecordingVideoExportStorage()
    private let subscriber: Subscriber<RecordingVideoExportResult?, NoError>
    private var session: AVAssetExportSession?
    private var finished = false

    init(subscriber: Subscriber<RecordingVideoExportResult?, NoError>) {
        self.subscriber = subscriber
    }

    func start(asset: AVAsset, trimRange: Range<Double>?) {
        guard !finished else { return }
        guard !cancelled.with({ $0 }), let duration = recordingVideoDuration(asset) else {
            finish(succeeded: false)
            return
        }
        var timeRange: CMTimeRange?
        if let trimRange {
            guard trimRange.lowerBound.isFinite, trimRange.upperBound.isFinite,
                trimRange.lowerBound >= 0, trimRange.lowerBound < trimRange.upperBound,
                trimRange.upperBound <= duration else {
                finish(succeeded: false)
                return
            }
            let scale = max(60000, asset.duration.timescale)
            let start = CMTime(seconds: trimRange.lowerBound, preferredTimescale: scale)
            let end = min(CMTime(seconds: trimRange.upperBound, preferredTimescale: scale), asset.duration)
            guard start.isNumeric, end.isNumeric, end > start else {
                finish(succeeded: false)
                return
            }
            timeRange = CMTimeRange(start: start, end: end)
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough), session.supportedFileTypes.contains(.mp4) else {
            finish(succeeded: false)
            return
        }
        self.session = session
        session.outputURL = URL(fileURLWithPath: storage.path)
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        if let timeRange {
            session.timeRange = timeRange
        }
        let storage = self.storage
        session.exportAsynchronously { [weak self, storage] in
            Self.queue.justDispatch {
                guard let self else {
                    storage.removeUnclaimed()
                    return
                }
                self.finish(succeeded: self.session?.status == .completed && self.session?.error == nil)
            }
        }
    }

    private func finish(succeeded: Bool) {
        guard !finished else {
            storage.removeUnclaimed()
            return
        }
        finished = true
        let duration = succeeded && !cancelled.with({ $0 }) ? recordingVideoDuration(AVURLAsset(url: URL(fileURLWithPath: storage.path))) : nil
        if let duration, !cancelled.with({ $0 }) {
            let result = storage.transfer(duration: duration)
            session = nil
            subscriber.putNext(result)
            subscriber.putCompletion()
        } else {
            session?.cancelExport()
            session = nil
            storage.removeUnclaimed()
            if !cancelled.with({ $0 }) {
                subscriber.putNext(nil)
                subscriber.putCompletion()
            }
        }
    }

    func cancel() {
        _ = cancelled.swap(true)
        Self.queue.async {
            self.finish(succeeded: false)
        }
    }

    deinit {
        session?.cancelExport()
        storage.removeUnclaimed()
    }
}

func passthroughExport(asset: AVAsset, name: String) -> Signal<RecordingVideoExportResult?, NoError> {
    return Signal { subscriber in
        let operation = RecordingVideoExportOperation(subscriber: subscriber)
        RecordingVideoExportOperation.queue.justDispatch {
            operation.start(asset: asset, trimRange: nil)
        }
        return ActionDisposable {
            operation.cancel()
        }
    }
}

func exportTrimmedVideo(path: String, range: Range<Double>) -> Signal<RecordingVideoExportResult?, NoError> {
    return Signal { subscriber in
        let operation = RecordingVideoExportOperation(subscriber: subscriber)
        RecordingVideoExportOperation.queue.justDispatch {
            operation.start(asset: AVURLAsset(url: URL(fileURLWithPath: path)), trimRange: range)
        }
        return ActionDisposable {
            operation.cancel()
        }
    }
}
