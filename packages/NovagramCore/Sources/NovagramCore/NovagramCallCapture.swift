import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import NovagramCallRecordingCore

@available(macOS 14.0, *)
final class NovagramCallCapture: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    enum Failure: Error {
        case windowNotFound
    }

    private static let maxVideoWidth: CGFloat = 1280
    private static let framesPerSecond: Int32 = 30
    private static let sampleRate = 48_000
    private static let streamQueueDepth = 5

    var onStreamStop: (() -> Void)?

    private let windowNumber: Int
    private let micDeviceId: String?
    private let videoSize: CGSize
    private let queue = DispatchQueue(label: "uz.novagram.call-capture", qos: .userInitiated)

    private var session: CallRecordingSession?
    private var stream: SCStream?
    private var micSession: AVCaptureSession?
    private var forwardsVideo: Bool
    private var isStopped = false

    init(window: NSWindow, micDeviceId: String?, hasVideo: Bool) {
        self.windowNumber = window.windowNumber
        self.micDeviceId = NovagramCallCapture.availableMicId(micDeviceId)
        self.forwardsVideo = hasVideo
        let scale = window.backingScaleFactor
        let pixelWidth = max(window.frame.width * scale, 1)
        let pixelHeight = max(window.frame.height * scale, 1)
        let fit = min(1, NovagramCallCapture.maxVideoWidth / pixelWidth)
        let even: (CGFloat) -> CGFloat = { value in max(2, floor(value / 2) * 2) }
        self.videoSize = CGSize(width: even(pixelWidth * fit), height: even(pixelHeight * fit))
        super.init()
    }

    func enableVideo() {
        queue.async {
            self.forwardsVideo = true
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
                    let stream = try self.makeStream(window: window)
                    self.stream = stream
                    stream.startCapture { error in
                        self.queue.async {
                            if let error {
                                self.stopSources()
                                finish(error)
                                return
                            }
                            finish(nil)
                        }
                    }
                } catch {
                    self.stopSources()
                    finish(error)
                }
            }
        }
    }

    func attach(_ session: CallRecordingSession) {
        queue.async {
            guard !self.isStopped else {
                return
            }
            self.session = session
        }
    }

    func stop() {
        queue.async {
            guard !self.isStopped else {
                return
            }
            self.isStopped = true
            self.session = nil
            self.stopSources()
        }
    }

    private func stopSources() {
        if let stream {
            self.stream = nil
            stream.stopCapture { _ in }
        }
        if let session = micSession {
            micSession = nil
            DispatchQueue.global(qos: .utility).async {
                session.stopRunning()
            }
        }
    }

    private func makeStream(window: SCWindow) throws -> SCStream {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.sampleRate = NovagramCallCapture.sampleRate
        configuration.channelCount = 2
        configuration.showsCursor = false
        configuration.queueDepth = NovagramCallCapture.streamQueueDepth
        configuration.width = Int(videoSize.width)
        configuration.height = Int(videoSize.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: NovagramCallCapture.framesPerSecond)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
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

    private static func availableMicId(_ id: String?) -> String? {
        guard let id, let device = AVCaptureDevice(uniqueID: id), device.isConnected, !device.isSuspended else {
            return nil
        }
        return device.uniqueID
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let session, sampleBuffer.isValid else {
            return
        }
        switch type {
        case .audio:
            session.audioTap.appendSampleBuffer(sampleBuffer, source: .remote)
        case .microphone:
            session.audioTap.appendSampleBuffer(sampleBuffer, source: .microphone)
        case .screen:
            guard forwardsVideo, NovagramCallCapture.isCompleteFrame(sampleBuffer), let frame = CallRecordingVideoFrame(sampleBuffer: sampleBuffer) else {
                return
            }
            session.appendVideoFrame(frame, side: .remote)
        @unknown default:
            break
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let session, sampleBuffer.isValid else {
            return
        }
        session.audioTap.appendSampleBuffer(sampleBuffer, source: .microphone)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async {
            self.onStreamStop?()
        }
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
}
