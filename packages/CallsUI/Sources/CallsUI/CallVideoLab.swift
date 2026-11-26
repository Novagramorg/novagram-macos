#if DEBUG
import Cocoa
import CoreVideo
import Metal
import TGUIKit
import SwiftSignalKit
import CallVideoLayer
import PerfLab

public enum CallVideoLab {
    private static var session: AnyObject?
    private static var didStart = false

    @discardableResult
    public static func startIfRequested(outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "call-video" else {
            return false
        }
        self.didStart = true
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 4.0), {
            let session = CallVideoLabSession(configuration: configuration, completion: {
                CallVideoLab.session = nil
                if configuration.quitWhenDone {
                    NSApp.terminate(nil)
                }
            })
            CallVideoLab.session = session
            session.start()
        })
        return true
    }
}

private struct CallVideoLabScenario {
    let tileCount: Int
    let width: Int
    let height: Int
    let rotationAngle: Float
    let mirrored: Bool
    let fitsTiles: Bool
    let isStill: Bool

    init?(_ name: String) {
        let parts = Set(name.split(separator: "-").map(String.init))
        var tileCount = 1
        for part in parts where part.hasPrefix("g") {
            if let value = Int(part.dropFirst()) {
                tileCount = value
            }
        }
        let sizes: [String: (Int, Int)] = [
            "180p": (320, 180),
            "360p": (640, 360),
            "720p": (1280, 720),
            "1080p": (1920, 1080),
            "portrait": (540, 960),
            "screen": (1660, 1076)
        ]
        guard let size = parts.compactMap({ sizes[$0] }).first else {
            return nil
        }
        self.tileCount = max(1, tileCount)
        self.width = size.0
        self.height = size.1
        if parts.contains("rot90") {
            self.rotationAngle = Float.pi * 0.5
        } else if parts.contains("rot180") {
            self.rotationAngle = Float.pi
        } else if parts.contains("rot270") {
            self.rotationAngle = Float.pi * 3.0 / 2.0
        } else {
            self.rotationAngle = 0.0
        }
        self.mirrored = parts.contains("mirror")
        self.fitsTiles = parts.contains("fit")
        self.isStill = parts.contains("still")
    }

    var displayAspect: CGFloat {
        if self.rotationAngle == Float.pi * 0.5 || self.rotationAngle == Float.pi * 3.0 / 2.0 {
            return CGFloat(self.height) / CGFloat(self.width)
        }
        return CGFloat(self.width) / CGFloat(self.height)
    }
}

func makeCallVideoLabFrames(width: Int, height: Int, seed: Int, count: Int) -> [CVPixelBuffer] {
    var result: [CVPixelBuffer] = []
    let attributes: [String: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as NSDictionary,
        kCVPixelBufferMetalCompatibilityKey as String: true
    ]
    for frame in 0 ..< count {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attributes as CFDictionary, &pixelBuffer)
        guard let pixelBuffer else {
            continue
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let shift = frame * 12 + seed * 37
        if let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
            let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let plane = base.assumingMemoryBound(to: UInt8.self)
            let bandStart = height / 3
            let bandEnd = bandStart + height / 8
            let barStart = shift % width
            let barEnd = barStart + width / 16
            for y in 0 ..< height {
                let row = plane + y * stride
                for x in 0 ..< width {
                    let value: Int
                    if y >= bandStart && y < bandEnd {
                        value = ((x / 2 + y / 2) & 1) == 0 ? 30 : 220
                    } else if x >= barStart && x < barEnd {
                        value = 235
                    } else {
                        value = 16 + (x * 3 + y * 2 + shift * 4) % 220
                    }
                    row[x] = UInt8(value)
                }
            }
        }
        if let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
            let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let plane = base.assumingMemoryBound(to: UInt8.self)
            let chromaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
            let chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
            for y in 0 ..< chromaHeight {
                let row = plane + y * stride
                for x in 0 ..< chromaWidth {
                    row[x * 2] = UInt8(x < chromaWidth / 2 ? 90 + seed * 7 % 40 : 170)
                    row[x * 2 + 1] = UInt8(y < chromaHeight / 2 ? 80 : 180 - seed * 5 % 40)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        result.append(pixelBuffer)
    }
    return result
}

final class CallVideoLabSource: VideoSource {
    private(set) var currentOutput: Output?
    private var listeners = Bag<() -> Void>()
    private let frames: [CVPixelBuffer]
    private let queue: DispatchQueue
    private let interval: Double
    private let phase: Double
    private let rotationAngle: Float
    private let mirrored: Bool
    private let isStill: Bool
    private var textureCache: CVMetalTextureCache?
    private var timer: DispatchSourceTimer?
    private var frameIndex = 0
    let deliveredFrames = Atomic<Int>(value: 0)

    init(frames: [CVPixelBuffer], device: MTLDevice, fps: Double, phase: Double, rotationAngle: Float, mirrored: Bool, isStill: Bool, index: Int) {
        self.frames = frames
        self.queue = DispatchQueue(label: "CallVideoLab.source.\(index)")
        self.interval = 1.0 / fps
        self.phase = phase
        self.rotationAngle = rotationAngle
        self.mirrored = mirrored
        self.isStill = isStill
        CVMetalTextureCacheCreate(nil, nil, device, nil, &self.textureCache)
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        timer.schedule(deadline: .now() + self.phase, repeating: self.interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.deliverFrame()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        self.timer?.cancel()
        self.timer = nil
    }

    private func deliverFrame() {
        guard let textureCache = self.textureCache, !self.frames.isEmpty else {
            return
        }
        let pixelBuffer = self.frames[self.isStill ? 0 : self.frameIndex % self.frames.count]
        self.frameIndex += 1
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvMetalTextureY: CVMetalTexture?
        var status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .r8Unorm, width, height, 0, &cvMetalTextureY)
        guard status == kCVReturnSuccess, let cvMetalTextureY, let yTexture = CVMetalTextureGetTexture(cvMetalTextureY) else {
            return
        }
        var cvMetalTextureUV: CVMetalTexture?
        status = CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pixelBuffer, nil, .rg8Unorm, CVPixelBufferGetWidthOfPlane(pixelBuffer, 1), CVPixelBufferGetHeightOfPlane(pixelBuffer, 1), 1, &cvMetalTextureUV)
        guard status == kCVReturnSuccess, let cvMetalTextureUV, let uvTexture = CVMetalTextureGetTexture(cvMetalTextureUV) else {
            return
        }
        let output = Output(
            resolution: CGSize(width: CGFloat(width), height: CGFloat(height)),
            textureLayout: .biPlanar(Output.BiPlanarTextureLayout(y: yTexture, uv: uvTexture)),
            dataBuffer: Output.NativeDataBuffer(pixelBuffer: pixelBuffer),
            rotationAngle: self.rotationAngle,
            followsDeviceOrientation: false,
            mirrorDirection: self.mirrored ? [.horizontal] : [],
            sourceId: 0,
            textureReferences: [cvMetalTextureY, cvMetalTextureUV]
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.currentOutput = output
            let _ = self.deliveredFrames.modify { $0 + 1 }
            for listener in self.listeners.copyItems() {
                listener()
            }
        }
    }

    func addOnUpdated(_ f: @escaping () -> Void) -> Disposable {
        let index = self.listeners.add(f)
        return ActionDisposable { [weak self] in
            DispatchQueue.main.async {
                self?.listeners.remove(index)
            }
        }
    }
}

private final class CallVideoLabSession {
    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private let processMonitor = PerfLabProcessMonitor()
    private var pending: [(scenario: String, run: Int)] = []
    private var window: Window?
    private var sources: [CallVideoLabSource] = []
    private let device = MTLCreateSystemDefaultDevice()

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
            for source in self.sources {
                source.stop()
            }
            self.sources.removeAll()
            self.window?.orderOut(nil)
            self.window = nil
            Queue.mainQueue().after(2.0, { [weak self] in
                self?.next()
            })
        })
    }

    private func runScenario(_ name: String, completion: @escaping ([String: Double], [String: String]) -> Void) {
        guard let scenario = CallVideoLabScenario(name), let device = self.device else {
            completion([:], ["error": "unknown scenario \(name)"])
            return
        }
        let fps = self.configuration.double("-PerfLabFps", 30.0)
        Queue.concurrentDefaultQueue().async {
            let frameSets = (0 ..< scenario.tileCount).map { index in
                makeCallVideoLabFrames(width: scenario.width, height: scenario.height, seed: index, count: scenario.isStill ? 1 : 6)
            }
            Queue.mainQueue().async {
                self.present(scenario: scenario, name: name, frameSets: frameSets, device: device, fps: fps, completion: completion)
            }
        }
    }

    private func present(scenario: CallVideoLabScenario, name: String, frameSets: [[CVPixelBuffer]], device: MTLDevice, fps: Double, completion: @escaping ([String: Double], [String: String]) -> Void) {
        let columns = Int(ceil(sqrt(Double(scenario.tileCount))))
        let rows = Int(ceil(Double(scenario.tileCount) / Double(columns)))
        let gap: CGFloat = 4.0
        let windowWidth = CGFloat(self.configuration.double("-PerfLabWindowWidth", 1440))
        let tileWidth = floor((windowWidth - gap * CGFloat(columns + 1)) / CGFloat(columns))
        let tileHeight: CGFloat
        if scenario.fitsTiles {
            tileHeight = floor(tileWidth / scenario.displayAspect)
        } else {
            tileHeight = floor((windowWidth * 0.625 - gap * CGFloat(rows + 1)) / CGFloat(rows))
        }
        let windowHeight = tileHeight * CGFloat(rows) + gap * CGFloat(rows + 1)
        let window = Window(contentRect: NSMakeRect(60, 60, windowWidth, windowHeight), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Call Video Lab"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        guard let contentView = window.contentView else {
            completion([:], ["error": "no content view"])
            return
        }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor
        var sources: [CallVideoLabSource] = []
        for index in 0 ..< scenario.tileCount {
            let column = index % columns
            let row = index / columns
            let frame = NSMakeRect(gap + CGFloat(column) * (tileWidth + gap), gap + CGFloat(row) * (tileHeight + gap), tileWidth, tileHeight)
            let source = CallVideoLabSource(frames: frameSets[index], device: device, fps: fps, phase: Double(index) / Double(scenario.tileCount) / fps, rotationAngle: scenario.rotationAngle, mirrored: scenario.mirrored, isStill: scenario.isStill, index: index)
            let view = MetalCallVideoView(frame: frame)
            contentView.addSubview(view)
            view.video = source
            sources.append(source)
        }
        self.sources = sources
        self.window = window
        window.orderFrontRegardless()
        for source in sources {
            source.start()
        }
        let notes = ["tiles": "\(scenario.tileCount)", "stream": "\(scenario.width)x\(scenario.height)", "tile": "\(Int(tileWidth))x\(Int(tileHeight))"]
        Queue.mainQueue().after(self.configuration.double("-PerfLabWarmupSeconds", 3.0), { [weak self] in
            guard let self else {
                return
            }
            if scenario.isStill {
                self.captureWindow(window, name: name)
            }
            let clock = PerfLabFrameClock(view: contentView)
            let start = self.processMonitor.snapshot()
            let startUnixTime = Date().timeIntervalSince1970
            let deliveredStart = sources.reduce(0) { $0 + $1.deliveredFrames.with { $0 } }
            clock.start()
            Queue.mainQueue().after(self.configuration.double("-PerfLabSeconds", 15.0), {
                clock.stop()
                let end = self.processMonitor.snapshot()
                let duration = end.time - start.time
                let delivered = sources.reduce(0) { $0 + $1.deliveredFrames.with { $0 } } - deliveredStart
                let metrics: [String: Double] = [
                    "duration": duration,
                    "cpuCores": duration > 0 ? (end.cpuTime - start.cpuTime) / duration : 0,
                    "mainThreadBusyPercent": duration > 0 ? (end.mainThreadCpuTime - start.mainThreadCpuTime) / duration * 100 : 0,
                    "footprintMB": Double(end.footprint) / 1048576.0,
                    "deliveredFps": duration > 0 ? Double(delivered) / duration : 0,
                    "hitches": Double(clock.stats.hitches),
                    "worstGapMs": clock.stats.worstGap * 1000,
                    "startUnixTime": startUnixTime,
                    "endUnixTime": Date().timeIntervalSince1970
                ]
                completion(metrics, notes)
            })
        })
    }

    private func captureWindow(_ window: Window, name: String) {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) else {
            NSLog("CallVideoLab: window capture failed")
            return
        }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return
        }
        try? FileManager.default.createDirectory(at: self.configuration.outputDirectory, withIntermediateDirectories: true)
        let url = self.configuration.outputDirectory.appendingPathComponent("call-video-\(self.configuration.label)-\(name)-\(width)x\(height).rgba")
        try? Data(bytes).write(to: url)
        NSLog("CallVideoLab: captured %@", url.path)
    }
}
#endif
