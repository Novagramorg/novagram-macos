#if DEBUG
import Cocoa
import AVFoundation
import CoreMedia
import ScreenCaptureKit
import TGUIKit
import SwiftSignalKit
import TgVoipWebrtc
import PerfLab

public enum ScreenCaptureLab {
    private static var session: AnyObject?
    private static var didStart = false

    @discardableResult
    public static func startIfRequested(outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "screen-capture" else {
            return false
        }
        self.didStart = true
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 4.0), {
            let session = ScreenCaptureLabSession(configuration: configuration, completion: {
                ScreenCaptureLab.session = nil
                if configuration.quitWhenDone {
                    NSApp.terminate(nil)
                }
            })
            ScreenCaptureLab.session = session
            session.start()
        })
        return true
    }
}

private protocol ScreenCaptureLabPipeline: AnyObject {
    var view: NSView { get }
    var frames: Int { get }
    func start()
    func stop()
}

private final class LegacyCapturePipeline: ScreenCaptureLabPipeline {
    let view: NSView
    private let manager: DesktopCaptureSourceManagerMac
    private let scope: DesktopCaptureSourceScopeMac

    init?(size: NSSize, fps: Double) {
        let manager = DesktopCaptureSourceManagerMac(_s: ())
        guard let source = manager.list().first else {
            return nil
        }
        self.manager = manager
        self.scope = DesktopCaptureSourceScopeMac(source: source, data: DesktopCaptureSourceDataMac(size: size, fps: fps, captureMouse: true))
        self.view = manager.create(forScope: self.scope)
    }

    var frames: Int {
        return -1
    }

    func start() {
        self.manager.start(self.scope)
    }

    func stop() {
        self.manager.stop(self.scope)
    }
}

@available(macOS 12.3, *)
private final class ScreenCaptureKitPipeline: NSObject, ScreenCaptureLabPipeline, SCStreamOutput {
    let view: NSView
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let size: NSSize
    private let fps: Double
    private let queue = DispatchQueue(label: "ScreenCaptureLab.sck")
    private var stream: SCStream?
    private let frameCounter = Atomic<Int>(value: 0)

    init(size: NSSize, fps: Double) {
        self.size = size
        self.fps = fps
        self.view = NSView(frame: NSMakeRect(0, 0, 100, 100))
        super.init()
        self.view.wantsLayer = true
        self.displayLayer.videoGravity = .resizeAspect
        self.displayLayer.frame = self.view.bounds
        self.displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.view.layer?.addSublayer(self.displayLayer)
    }

    var frames: Int {
        return self.frameCounter.with { $0 }
    }

    func start() {
        SCShareableContent.getWithCompletionHandler { [weak self] content, error in
            guard let self, let display = content?.displays.first else {
                NSLog("ScreenCaptureLab: no shareable content \(String(describing: error))")
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            let scale = min(1.0, min(self.size.width / CGFloat(display.width * 2), self.size.height / CGFloat(display.height * 2)))
            let width = Int(CGFloat(display.width * 2) * scale) & ~1
            let height = Int(CGFloat(display.height * 2) * scale) & ~1
            configuration.width = width
            configuration.height = height
            configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(self.fps))
            configuration.showsCursor = true
            configuration.queueDepth = 5
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.queue)
            } catch {
                NSLog("ScreenCaptureLab: addStreamOutput failed \(error)")
                return
            }
            self.stream = stream
            stream.startCapture { error in
                if let error {
                    NSLog("ScreenCaptureLab: startCapture failed \(error)")
                }
            }
        }
    }

    func stop() {
        self.stream?.stopCapture(completionHandler: { _ in })
        self.stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else {
            return
        }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]], let statusValue = attachments.first?[.status] as? Int, statusValue == SCFrameStatus.complete.rawValue else {
            return
        }
        _ = self.frameCounter.modify { $0 + 1 }
        self.displayLayer.enqueue(sampleBuffer)
    }
}

private final class ScreenCaptureLabSession {
    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private let processMonitor = PerfLabProcessMonitor()
    private var pending: [(scenario: String, run: Int)] = []
    private var window: Window?
    private var pipeline: ScreenCaptureLabPipeline?

    init(configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        self.configuration = configuration
        self.completion = completion
        self.report = PerfLabReport(configuration: configuration)
    }

    func start() {
        for scenario in self.configuration.scenarios {
            for run in 0 ..< self.configuration.runs {
                self.pending.append((scenario, run))
            }
        }
        self.next()
    }

    private func next() {
        guard !self.pending.isEmpty else {
            let url = self.report.write()
            NSLog("PerfLab report written to %@", url?.path ?? "nil")
            self.completion()
            return
        }
        let (scenario, run) = self.pending.removeFirst()
        self.runScenario(scenario, completion: { [weak self] metrics, notes in
            guard let self else {
                return
            }
            self.report.add(scenario: scenario, run: run, metrics: metrics, notes: notes)
            self.pipeline?.stop()
            self.pipeline = nil
            self.window?.orderOut(nil)
            self.window = nil
            Queue.mainQueue().after(2.0, { [weak self] in
                self?.next()
            })
        })
    }

    private func makePipeline(_ kind: String) -> ScreenCaptureLabPipeline? {
        let size = NSMakeSize(self.configuration.double("-PerfLabCaptureWidth", 1920), self.configuration.double("-PerfLabCaptureHeight", 1080))
        let fps = self.configuration.double("-PerfLabCaptureFps", 25)
        if kind == "sck" {
            if #available(macOS 12.3, *) {
                return ScreenCaptureKitPipeline(size: size, fps: fps)
            }
            return nil
        }
        return LegacyCapturePipeline(size: size, fps: fps)
    }

    private func runScenario(_ scenario: String, completion: @escaping ([String: Double], [String: String]) -> Void) {
        let parts = scenario.split(separator: "-").map(String.init)
        let kind = parts.first ?? "legacy"
        let showsPreview = !parts.contains("static")
        guard let pipeline = self.makePipeline(kind) else {
            completion([:], ["error": "pipeline \(kind) unavailable"])
            return
        }
        self.pipeline = pipeline
        let frame = NSMakeRect(200, 200, 720, 450)
        let window = Window(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Screen Capture Lab"
        window.isReleasedWhenClosed = false
        pipeline.view.frame = window.contentView?.bounds ?? frame.size.bounds
        pipeline.view.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(pipeline.view)
        if showsPreview {
            window.makeKeyAndOrderFront(nil)
        }
        self.window = window
        pipeline.start()
        var permission = "unknown"
        if #available(macOS 10.15, *) {
            permission = CGPreflightScreenCaptureAccess() ? "granted" : "missing"
        }
        let notes = ["permission": permission, "preview": showsPreview ? "visible" : "hidden"]
        Queue.mainQueue().after(self.configuration.double("-PerfLabWarmupSeconds", 3.0), { [weak self] in
            guard let self else {
                return
            }
            let clock = PerfLabFrameClock(view: self.window?.contentView ?? pipeline.view)
            let start = self.processMonitor.snapshot()
            let startUnixTime = Date().timeIntervalSince1970
            let framesStart = pipeline.frames
            clock.start()
            Queue.mainQueue().after(self.configuration.double("-PerfLabSeconds", 15.0), { [weak self] in
                clock.stop()
                guard let self else {
                    return
                }
                let end = self.processMonitor.snapshot()
                let duration = end.time - start.time
                var metrics: [String: Double] = [
                    "duration": duration,
                    "cpuCores": duration > 0 ? (end.cpuTime - start.cpuTime) / duration : 0,
                    "mainThreadBusyPercent": duration > 0 ? (end.mainThreadCpuTime - start.mainThreadCpuTime) / duration * 100 : 0,
                    "footprintMB": Double(end.footprint) / 1048576.0,
                    "hitches": Double(clock.stats.hitches),
                    "worstGapMs": clock.stats.worstGap * 1000,
                    "startUnixTime": startUnixTime,
                    "endUnixTime": Date().timeIntervalSince1970
                ]
                if framesStart >= 0 {
                    metrics["capturedFps"] = Double(pipeline.frames - framesStart) / max(duration, 0.001)
                }
                completion(metrics, notes)
            })
        })
    }
}
#endif
