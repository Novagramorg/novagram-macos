import Foundation
import AVFoundation

struct AvatarVideoFrameSequence {
    let startFrame: Int32
    let endFrame: Int32
    let sourceFps: Int32
    let outputFps: Int32
    private(set) var index: Int64 = 0

    init?(startFrame: Int32, endFrame: Int32, fps: Int) {
        guard startFrame >= 0, endFrame > startFrame, fps > 0, fps <= Int(Int32.max) else { return nil }
        self.startFrame = startFrame
        self.endFrame = endFrame
        self.sourceFps = Int32(fps)
        self.outputFps = Int32(min(30, fps))
    }

    var duration: CMTime {
        CMTime(value: Int64(self.endFrame) - Int64(self.startFrame), timescale: self.sourceFps)
    }

    mutating func next() -> (frame: Int32, time: CMTime, progress: Float)? {
        let offset = self.index * Int64(self.sourceFps) / Int64(self.outputFps)
        let count = Int64(self.endFrame) - Int64(self.startFrame)
        guard offset < count else { return nil }
        let time = CMTime(value: self.index, timescale: self.outputFps)
        self.index += 1
        let progress = min(1, Double(self.index) * Double(self.sourceFps) / (Double(self.outputFps) * Double(count)))
        return (Int32(Int64(self.startFrame) + offset), time, Float(progress))
    }
}

final class AvatarVideoExport {
    enum Frame {
        case frame(CVPixelBuffer, CMTime)
        case finished(CMTime)
        case failed
    }

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let path: String
    private var observation: NSKeyValueObservation?
    private var completion: ((String?) -> Void)?
    private var started = false
    private var finishing = false
    private var finished = false
    private var succeeded = false

    init(codec: String) throws {
        self.path = NSTemporaryDirectory() + "tgs_\(UUID().uuidString).mp4"
        self.writer = try AVAssetWriter(url: URL(fileURLWithPath: self.path), fileType: .mp4)
        var settings: [String: Any] = [AVVideoWidthKey: 640, AVVideoHeightKey: 640, AVVideoCodecKey: codec]
        if codec == AVVideoCodecType.h264.rawValue {
            settings[AVVideoCompressionPropertiesKey] = [AVVideoAverageBitRateKey: 1500000, AVVideoMaxKeyFrameIntervalKey: 3]
        }
        guard self.writer.canApply(outputSettings: settings, forMediaType: .video) else {
            throw NSError(domain: "AvatarVideoExport", code: 1)
        }
        self.input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        self.adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.input, sourcePixelBufferAttributes: nil)
        guard self.writer.canAdd(self.input) else {
            throw NSError(domain: "AvatarVideoExport", code: 1)
        }
        self.writer.add(self.input)
    }

    func start(queue: DispatchQueue, isCancelled: @escaping () -> Bool, next: @escaping () -> Frame, completed: @escaping (String?) -> Void) {
        guard !self.started, !self.finished else { return }
        self.started = true
        self.completion = completed
        guard !isCancelled(), !self.finished, self.writer.startWriting(), self.writer.status == .writing else {
            self.resolve(success: false)
            return
        }
        self.writer.startSession(atSourceTime: .zero)
        self.observation = self.writer.observe(\.status, options: [.new]) { [weak self] _, _ in
            queue.async { [weak self] in
                guard let self else { return }
                if self.writer.status == .failed || self.writer.status == .cancelled {
                    self.resolve(success: false)
                }
            }
        }
        guard self.writer.status == .writing else {
            self.resolve(success: false)
            return
        }
        self.input.requestMediaDataWhenReady(on: queue) { [weak self] in
            guard let self, !self.finishing, !self.finished else { return }
            while self.input.isReadyForMoreMediaData {
                guard !isCancelled(), self.writer.status == .writing else {
                    self.resolve(success: false)
                    return
                }
                let frame = autoreleasepool { next() }
                guard !self.finished, !isCancelled() else {
                    self.resolve(success: false)
                    return
                }
                switch frame {
                case let .frame(buffer, time):
                    guard self.adaptor.append(buffer, withPresentationTime: time) else {
                        self.resolve(success: false)
                        return
                    }
                case let .finished(time):
                    self.finishing = true
                    self.input.markAsFinished()
                    self.writer.endSession(atSourceTime: time)
                    self.writer.finishWriting { [weak self] in
                        queue.async { [weak self] in
                            guard let self else { return }
                            self.resolve(success: !isCancelled() && self.writer.status == .completed && self.writer.error == nil)
                        }
                    }
                    return
                case .failed:
                    self.resolve(success: false)
                    return
                }
            }
            if isCancelled() || self.writer.status == .failed || self.writer.status == .cancelled {
                self.resolve(success: false)
            }
        }
    }

    func cancel() {
        self.resolve(success: false)
    }

    private func resolve(success: Bool) {
        guard !self.finished else { return }
        self.finished = true
        self.succeeded = success
        self.observation = nil
        let completion = self.completion
        self.completion = nil
        if !success {
            if self.writer.status == .writing {
                self.writer.cancelWriting()
            }
            try? FileManager.default.removeItem(atPath: self.path)
        }
        completion?(success ? self.path : nil)
    }

    deinit {
        if self.writer.status == .writing {
            self.writer.cancelWriting()
        }
        if !self.succeeded {
            try? FileManager.default.removeItem(atPath: self.path)
        }
    }
}
