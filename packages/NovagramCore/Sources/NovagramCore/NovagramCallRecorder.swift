import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

// Records one call window with ScreenCaptureKit: the window picture (video calls), the app's audio (the other
// side) and the microphone (macOS 15+: SCK, macOS 14: AVCaptureSession), mixed into one AAC track.
@available(macOS 14.0, *)
final class NovagramCallRecorder: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    enum Failure: Error {
        case windowNotFound
        case writerFailed
        case nothingRecorded
    }

    private static let maxVideoWidth: CGFloat = 1280
    private static let framesPerSecond: Int32 = 30
    private static let keyFrameInterval = 60
    private static let videoBitRate = 4_000_000
    private static let audioBitRate = 128_000
    private static let audioOnlyFrameSide = 2
    private static let mixLatency: Double = 0.4
    private static let streamQueueDepth = 5

    let outputURL: URL
    let hasVideo: Bool
    var onStreamStop: (() -> Void)?

    private let windowNumber: Int
    private let micDeviceId: String?
    private let videoSize: CGSize
    private let queue = DispatchQueue(label: "uz.novagram.call-recorder", qos: .userInitiated)
    private let mixer = NovagramCallAudioMixer()

    private var stream: SCStream?
    private var micSession: AVCaptureSession?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var startSeconds: Double?
    private var videoClockOffset: Double?
    private var lastVideoTime: CMTime = .invalid
    private var wroteSamples = false
    private var isStopping = false
    private var micMuted = false

    init(outputURL: URL, hasVideo: Bool, window: NSWindow, micDeviceId: String?) {
        self.outputURL = outputURL
        self.hasVideo = hasVideo
        self.micDeviceId = NovagramCallRecorder.availableMicId(micDeviceId)
        self.windowNumber = window.windowNumber
        let scale = window.backingScaleFactor
        let pixelWidth = max(window.frame.width * scale, 1)
        let pixelHeight = max(window.frame.height * scale, 1)
        let fit = min(1, NovagramCallRecorder.maxVideoWidth / pixelWidth)
        let even: (CGFloat) -> CGFloat = { value in max(2, floor(value / 2) * 2) }
        self.videoSize = CGSize(width: even(pixelWidth * fit), height: even(pixelHeight * fit))
        super.init()
    }

    func setMicMuted(_ muted: Bool) {
        queue.async {
            self.micMuted = muted
        }
    }

    func start(completion: @escaping (Error?) -> Void) {
        let finish: (Error?) -> Void = { error in
            DispatchQueue.main.async {
                completion(error)
            }
        }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            if let error {
                finish(error)
                return
            }
            guard let window = content?.windows.first(where: { Int($0.windowID) == self.windowNumber }) else {
                finish(Failure.windowNotFound)
                return
            }
            self.queue.async {
                do {
                    try self.makeWriter()
                    let stream = try self.makeStream(window: window)
                    self.stream = stream
                    stream.startCapture { error in
                        self.queue.async {
                            if let error {
                                self.abortStart()
                                finish(error)
                                return
                            }
                            self.beginSession()
                            finish(nil)
                        }
                    }
                } catch {
                    self.abortStart()
                    finish(error)
                }
            }
        }
    }

    func stop(completion: @escaping (Result<URL, Error>) -> Void) {
        stopCapture { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func stopAndWait(timeout: TimeInterval) -> URL? {
        let done = DispatchSemaphore(value: 0)
        var url: URL?
        stopCapture { result in
            url = try? result.get()
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            return nil
        }
        return url
    }

    private func stopCapture(_ finish: @escaping (Result<URL, Error>) -> Void) {
        queue.async {
            guard !self.isStopping else {
                return
            }
            self.isStopping = true
            let stream = self.stream
            self.stream = nil
            if let session = self.micSession {
                self.micSession = nil
                DispatchQueue.global(qos: .utility).async {
                    session.stopRunning()
                }
            }
            guard let stream else {
                self.finishWriting(finish)
                return
            }
            stream.stopCapture { _ in
                self.queue.async {
                    self.finishWriting(finish)
                }
            }
        }
    }

    private func abortStart() {
        stream = nil
        if let session = micSession {
            micSession = nil
            DispatchQueue.global(qos: .utility).async {
                session.stopRunning()
            }
        }
        if writer?.status == .writing {
            writer?.cancelWriting()
        }
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func makeWriter() throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: hasVideo ? .mp4 : .m4a)
        if hasVideo {
            let compression: [String: Any] = [
                AVVideoAverageBitRateKey: NovagramCallRecorder.videoBitRate,
                AVVideoExpectedSourceFrameRateKey: NovagramCallRecorder.framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: NovagramCallRecorder.keyFrameInterval,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(videoSize.width),
                AVVideoHeightKey: Int(videoSize.height),
                AVVideoCompressionPropertiesKey: compression
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw Failure.writerFailed
            }
            writer.add(input)
            videoInput = input
        }
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: NovagramCallAudioMixer.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: NovagramCallRecorder.audioBitRate
        ]
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings, sourceFormatHint: mixer.formatDescription)
        audio.expectsMediaDataInRealTime = true
        guard writer.canAdd(audio) else {
            throw Failure.writerFailed
        }
        writer.add(audio)
        audioInput = audio
        guard writer.startWriting() else {
            throw writer.error ?? Failure.writerFailed
        }
        self.writer = writer
    }

    private func makeStream(window: SCWindow) throws -> SCStream {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.sampleRate = Int(NovagramCallAudioMixer.sampleRate)
        configuration.channelCount = 2
        configuration.showsCursor = false
        configuration.queueDepth = NovagramCallRecorder.streamQueueDepth
        if hasVideo {
            configuration.width = Int(videoSize.width)
            configuration.height = Int(videoSize.height)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: NovagramCallRecorder.framesPerSecond)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.scalesToFit = true
            configuration.preservesAspectRatio = true
        } else {
            configuration.width = NovagramCallRecorder.audioOnlyFrameSide
            configuration.height = NovagramCallRecorder.audioOnlyFrameSide
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        }
        if #available(macOS 15.0, *) {
            configuration.captureMicrophone = true
            if let micDeviceId {
                configuration.microphoneCaptureDeviceID = micDeviceId
            }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        if #available(macOS 15.0, *) {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        } else {
            startMicrophoneSession()
        }
        return stream
    }

    private func startMicrophoneSession() {
        guard let device = micDeviceId.flatMap(AVCaptureDevice.init(uniqueID:)) ?? AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: NovagramCallAudioMixer.sampleRate,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVLinearPCMIsBigEndianKey: false
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            return
        }
        session.addInput(input)
        session.addOutput(output)
        micSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func beginSession() {
        let now = NovagramCallRecorder.hostSeconds()
        startSeconds = now
        writer?.startSession(atSourceTime: CMTime(seconds: now, preferredTimescale: CMTimeScale(NovagramCallAudioMixer.sampleRate)))
    }

    private static func availableMicId(_ id: String?) -> String? {
        guard let id, let device = AVCaptureDevice(uniqueID: id), device.isConnected, !device.isSuspended else {
            return nil
        }
        return device.uniqueID
    }

    private static func hostSeconds() -> Double {
        return CMClockGetTime(CMClockGetHostTimeClock()).seconds
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let start = startSeconds, !isStopping, sampleBuffer.isValid else {
            return
        }
        if type == .screen {
            appendVideo(sampleBuffer, start: start)
        } else if type == .audio {
            mixer.add(sampleBuffer, source: .app, start: start, now: NovagramCallRecorder.hostSeconds())
        } else if #available(macOS 15.0, *), type == .microphone, !micMuted {
            mixer.add(sampleBuffer, source: .microphone, start: start, now: NovagramCallRecorder.hostSeconds())
        }
        flushAudio(final: false)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let start = startSeconds, !isStopping, sampleBuffer.isValid else {
            return
        }
        if !micMuted {
            mixer.add(sampleBuffer, source: .microphone, start: start, now: NovagramCallRecorder.hostSeconds())
        }
        flushAudio(final: false)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.onStreamStop?()
        }
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer, start: Double) {
        guard hasVideo, let videoInput, NovagramCallRecorder.isCompleteFrame(sampleBuffer) else {
            return
        }
        let original = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard original.isValid else {
            return
        }
        let offset = videoOffset(for: original.seconds)
        let time = CMTime(seconds: original.seconds + offset, preferredTimescale: original.timescale)
        guard time.seconds >= start, !lastVideoTime.isValid || time > lastVideoTime, videoInput.isReadyForMoreMediaData else {
            return
        }
        guard let retimed = offset == 0 ? sampleBuffer : NovagramCallRecorder.retime(sampleBuffer, to: time) else {
            return
        }
        if videoInput.append(retimed) {
            lastVideoTime = time
            wroteSamples = true
        }
    }

    private func videoOffset(for pts: Double) -> Double {
        if let videoClockOffset {
            return videoClockOffset
        }
        let delta = NovagramCallRecorder.hostSeconds() - pts
        let offset = abs(delta) > 1 ? delta : 0
        videoClockOffset = offset
        return offset
    }

    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else {
            return false
        }
        return status == .complete
    }

    private static func retime(_ sampleBuffer: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(sampleBuffer), presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var result: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &result) == noErr else {
            return nil
        }
        return result
    }

    private func flushAudio(final: Bool) {
        guard let start = startSeconds, let audioInput, writer?.status == .writing else {
            return
        }
        let limit: Int64
        if final {
            limit = mixer.pendingEndFrame
        } else {
            limit = Int64((NovagramCallRecorder.hostSeconds() - NovagramCallRecorder.mixLatency - start) * NovagramCallAudioMixer.sampleRate)
        }
        guard let chunk = mixer.takeSampleBuffer(upTo: limit, start: start) else {
            return
        }
        if audioInput.isReadyForMoreMediaData, audioInput.append(chunk) {
            wroteSamples = true
        }
    }

    private func finishWriting(_ completion: @escaping (Result<URL, Error>) -> Void) {
        guard let writer, writer.status == .writing, startSeconds != nil else {
            if self.writer?.status == .writing {
                self.writer?.cancelWriting()
            }
            try? FileManager.default.removeItem(at: outputURL)
            completion(.failure(self.writer?.error ?? Failure.writerFailed))
            return
        }
        flushAudio(final: true)
        guard wroteSamples else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            completion(.failure(Failure.nothingRecorded))
            return
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        let url = outputURL
        writer.finishWriting {
            if writer.status == .completed {
                completion(.success(url))
            } else {
                try? FileManager.default.removeItem(at: url)
                completion(.failure(writer.error ?? Failure.writerFailed))
            }
        }
    }
}
