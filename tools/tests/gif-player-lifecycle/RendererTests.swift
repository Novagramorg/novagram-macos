import XCTest
import Cocoa
import AVFoundation
import SwiftSignalKit

class TransformImageView: NSView {
    init() { super.init(frame: .zero); wantsLayer = true }
    required override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
}
typealias SimpleShapeLayer = CAShapeLayer
struct LayoutPositionFlags: OptionSet { let rawValue: Int }
extension CGPath {
    static func bubbleCorners(size: CGSize, flags: LayoutPositionFlags) -> CGPath { CGPath(rect: CGRect(origin: .zero, size: size), transform: nil) }
}
func assertOnMainThread() { precondition(Thread.isMainThread) }
func link(path: String?, ext: String) -> String? { path }
var rejectTimebaseCreation = false
func createTimebase() -> Unmanaged<CMTimebase>? {
    if rejectTimebaseCreation { return nil }
    var timebase: CMTimebase?
    CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase)
    return timebase.map { Unmanaged.passRetained($0) }
}
class ControlledAssetReader: AVAssetReader {
    static var rejectStart = false
    var failed = false
    override var status: AVAssetReader.Status { failed ? .failed : super.status }
    override func startReading() -> Bool { Self.rejectStart ? false : super.startReading() }
}
class ControlledSampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
    var callback: (() -> Void)?
    var requests = 0
    var stops = 0
    var clears = 0
    var flushes = 0
    var readyForSample = false
    var enqueued = 0
    override var isReadyForMoreMediaData: Bool { readyForSample }
    override func enqueue(_ sampleBuffer: CMSampleBuffer) { enqueued += 1; readyForSample = false }
    override func requestMediaDataWhenReady(on queue: DispatchQueue, using block: @escaping () -> Void) {
        requests += 1
        callback = block
    }
    override func stopRequestingMediaData() {
        stops += 1
        callback = nil
        super.stopRequestingMediaData()
    }
    override func flushAndRemoveImage() { clears += 1; super.flushAndRemoveImage() }
    override func flush() { flushes += 1; super.flush() }
    func fire() { sampleBufferQueue.sync { callback?() } }
}

__SOURCE__

final class RendererTests: XCTestCase {
    static var directory: URL!
    static var video: URL!
    var timers: [CFRunLoopTimer] = []
    var readers: [AVAssetReader] = []
    var layers: [ControlledSampleBufferDisplayLayer] = []

    override class func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        video = directory.appendingPathComponent("sample.mp4")
        let writer = try! AVAssetWriter(outputURL: video, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 32])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 32, kCVPixelBufferHeightKey as String: 32])
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<15 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
            precondition(input.isReadyForMoreMediaData)
            var pixel: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 32, 32, kCVPixelFormatType_32ARGB, nil, &pixel)
            CVPixelBufferLockBaseAddress(pixel!, [])
            memset(CVPixelBufferGetBaseAddress(pixel!), Int32(index), CVPixelBufferGetDataSize(pixel!))
            CVPixelBufferUnlockBaseAddress(pixel!, [])
            precondition(adaptor.append(pixel!, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        precondition(done.wait(timeout: .now() + 10) == .success)
        precondition(writer.status == .completed)
    }
    override class func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }
    override func tearDown() {
        sampleBufferQueue.sync {}
        layers.forEach { $0.stopRequestingMediaData(); $0.controlTimebase = nil }
        timers.forEach { CFRunLoopTimerInvalidate($0) }
        readers.forEach { $0.cancelReading() }
        layers.removeAll(); readers.removeAll(); timers.removeAll()
        ControlledAssetReader.rejectStart = false
        rejectTimebaseCreation = false
        super.tearDown()
    }
    func data(_ suffix: String = "") -> AVGifData {
        let url: URL
        if suffix.isEmpty { url = Self.video } else {
            url = Self.directory.appendingPathComponent(suffix + ".mp4")
            if !FileManager.default.fileExists(atPath: url.path) { try! FileManager.default.copyItem(at: Self.video, to: url) }
        }
        return AVGifData.dataFrom(url.path)!
    }
    func start(_ view: GIFPlayerView, data: AVGifData? = nil) -> ControlledSampleBufferDisplayLayer {
        let timebase = createTimebase()!.takeRetainedValue()
        CMTimebaseSetRate(timebase, rate: 0)
        view.set(data: data ?? self.data(), timebase: timebase)
        sampleBufferQueue.sync {}
        let layer = view.sampleBufferLayer as! ControlledSampleBufferDisplayLayer
        layers.append(layer)
        layer.fire()
        if let timer = view._timer.with({ $0 }) { timers.append(timer) }
        if let reader = view._reader.with({ $0 }) { readers.append(reader) }
        XCTAssertNotNil(view._reader.with { $0 })
        XCTAssertNotNil(view._timer.with { $0 })
        return layer
    }
    func assertStopped(_ view: GIFPlayerView, layer: ControlledSampleBufferDisplayLayer) {
        sampleBufferQueue.sync {}
        XCTAssertNil(layer.callback)
        XCTAssertNil(layer.controlTimebase)
        XCTAssertNil(view._reader.with { $0 })
        XCTAssertNil(view._output.with { $0 })
        XCTAssertNil(view._asset.with { $0 })
        XCTAssertNil(view._track.with { $0 })
        XCTAssertNil(view._timer.with { $0 })
        XCTAssertNil(view._timebase.with { $0 })
    }
    func testStopWithoutReadinessCallbackReleasesAllRenderState() {
        let view = GIFPlayerView()
        let layer = start(view)
        let timer = view._timer.with { $0 }!
        view.set(data: nil)
        assertStopped(view, layer: layer)
        XCTAssertFalse(CFRunLoopTimerIsValid(timer))
    }
    func testStopCancelsRealAssetReader() {
        let view = GIFPlayerView()
        _ = start(view)
        let reader = view._reader.with { $0 }!
        view.set(data: nil)
        sampleBufferQueue.sync {}
        let deadline = Date().addingTimeInterval(2)
        while reader.status == .reading && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
        XCTAssertEqual(reader.status, .cancelled)
    }
    func testDeinitDoesNotDependOnAnotherDisplayCallback() {
        weak var weakView: GIFPlayerView?
        let (layer, timer) = autoreleasepool { () -> (ControlledSampleBufferDisplayLayer, CFRunLoopTimer) in
            let view = GIFPlayerView()
            weakView = view
            let layer = start(view)
            return (layer, view._timer.with { $0 }!)
        }
        CATransaction.flush()
        sampleBufferQueue.sync {}
        XCTAssertNil(weakView)
        XCTAssertNil(layer.callback)
        XCTAssertNil(layer.controlTimebase)
        XCTAssertFalse(CFRunLoopTimerIsValid(timer))
    }
    func testReplacementStopsOldRequestBeforeRegisteringNewOne() {
        let view = GIFPlayerView()
        let layer = start(view)
        let oldTimer = view._timer.with { $0 }!
        let stops = layer.stops
        view.set(data: data("replacement"))
        sampleBufferQueue.sync {}
        XCTAssertGreaterThan(layer.stops, stops)
        XCTAssertFalse(CFRunLoopTimerIsValid(oldTimer))
        XCTAssertNil(view._reader.with { $0 })
        layer.fire()
        XCTAssertNotNil(view._reader.with { $0 })
        view.set(data: nil)
        assertStopped(view, layer: layer)
    }
    func testStopThenRestartBeforeQueueDrainsKeepsNewestData() {
        let view = GIFPlayerView()
        let layer = start(view)
        let entered = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0)
        sampleBufferQueue.async { entered.signal(); resume.wait() }
        entered.wait()
        view.set(data: nil)
        let next = data("restart")
        view.set(data: next)
        resume.signal()
        sampleBufferQueue.sync {}
        layer.fire()
        XCTAssertEqual(view._asset.with { $0?.url }, next.asset.url)
        XCTAssertNotNil(layer.callback)
        XCTAssertNotNil(view._reader.with { $0 })
        view.set(data: nil)
        assertStopped(view, layer: layer)
    }
    func testSameDataDoesNotRegisterAnotherRequest() {
        let view = GIFPlayerView()
        let media = data()
        let layer = start(view, data: media)
        let requests = layer.requests
        view.set(data: media)
        sampleBufferQueue.sync {}
        XCTAssertEqual(layer.requests, requests)
        view.set(data: nil)
    }
    func testResetCanPreserveDisplayedImage() {
        let view = GIFPlayerView()
        let layer = start(view)
        let clears = layer.clears, flushes = layer.flushes
        view.reset(with: layer.controlTimebase, false)
        sampleBufferQueue.sync {}
        XCTAssertEqual(layer.clears, clears)
        XCTAssertGreaterThan(layer.flushes, flushes)
        view.set(data: nil)
    }
    func testTimerInvalidatedEvenIfLayerTimebaseWasDetached() {
        let view = GIFPlayerView()
        let layer = start(view)
        let timer = view._timer.with { $0 }!
        layer.controlTimebase = nil
        view.set(data: nil)
        sampleBufferQueue.sync {}
        XCTAssertFalse(CFRunLoopTimerIsValid(timer))
        XCTAssertNil(view._timer.with { $0 })
    }
    func testReaderProducesRealVideoSampleBeforeStopping() {
        let view = GIFPlayerView()
        let layer = start(view)
        layer.readyForSample = true
        layer.fire()
        XCTAssertEqual(layer.enqueued, 1)
        XCTAssertNotNil(layer.callback)
        view.set(data: nil)
        assertStopped(view, layer: layer)
    }
    func testLateCallbackAfterStopCannotRecreateReaderOrTimer() {
        let view = GIFPlayerView()
        let layer = start(view)
        let callback = layer.callback!
        view.set(data: nil)
        sampleBufferQueue.sync {}
        sampleBufferQueue.sync { callback() }
        assertStopped(view, layer: layer)
    }
    func testLateCallbackCannotReplaceNewSessionState() {
        let view = GIFPlayerView()
        let layer = start(view)
        let callback = layer.callback!
        view.set(data: nil)
        view.set(data: data("late"))
        sampleBufferQueue.sync {}
        layer.fire()
        let reader = view._reader.with { $0 }
        let timer = view._timer.with { $0 }
        sampleBufferQueue.sync { callback() }
        XCTAssertTrue(view._reader.with { $0 } === reader)
        XCTAssertTrue(view._timer.with { $0 } === timer)
        XCTAssertNotNil(layer.callback)
        view.set(data: nil)
        assertStopped(view, layer: layer)
    }
    func testDeinitBeforePendingSetupDoesNotStartRendering() {
        let entered = DispatchSemaphore(value: 0), resume = DispatchSemaphore(value: 0)
        sampleBufferQueue.async { entered.signal(); resume.wait() }
        entered.wait()
        weak var weakView: GIFPlayerView?
        let layer = autoreleasepool { () -> ControlledSampleBufferDisplayLayer in
            let view = GIFPlayerView()
            weakView = view
            view.set(data: data())
            let layer = view.sampleBufferLayer as! ControlledSampleBufferDisplayLayer
            layers.append(layer)
            return layer
        }
        CATransaction.flush()
        resume.signal()
        sampleBufferQueue.sync {}
        XCTAssertNil(weakView)
        XCTAssertEqual(layer.requests, 0)
        XCTAssertNil(layer.callback)
    }
    func testUnreadableAssetStopsRequestAndReleasesState() {
        let valid = data()
        let missing = AVURLAsset(url: Self.directory.appendingPathComponent("missing.mp4"))
        let broken = AVGifData(asset: missing, track: valid.track, animatedSticker: false, swapOnComplete: false)
        let view = GIFPlayerView()
        view.set(data: broken)
        sampleBufferQueue.sync {}
        let layer = view.sampleBufferLayer as! ControlledSampleBufferDisplayLayer
        layers.append(layer)
        layer.fire()
        assertStopped(view, layer: layer)
    }
    func testRejectedStartDoesNotLeaveActiveRequestOrTimer() {
        ControlledAssetReader.rejectStart = true
        let view = GIFPlayerView()
        view.set(data: data())
        sampleBufferQueue.sync {}
        let layer = view.sampleBufferLayer as! ControlledSampleBufferDisplayLayer
        layers.append(layer)
        layer.fire()
        if let timer = view._timer.with({ $0 }) { timers.append(timer) }
        assertStopped(view, layer: layer)
    }
    func testReaderFailureAfterStartStopsRequest() {
        let view = GIFPlayerView()
        let layer = start(view)
        let reader = view._reader.with { $0 } as! ControlledAssetReader
        reader.failed = true
        layer.fire()
        assertStopped(view, layer: layer)
    }
    func testValidMediaCanStartAfterFailedMedia() {
        ControlledAssetReader.rejectStart = true
        let view = GIFPlayerView()
        view.set(data: data())
        sampleBufferQueue.sync {}
        let layer = view.sampleBufferLayer as! ControlledSampleBufferDisplayLayer
        layers.append(layer)
        layer.fire()
        ControlledAssetReader.rejectStart = false
        view.set(data: nil)
        view.set(data: data())
        sampleBufferQueue.sync {}
        layer.fire()
        layer.readyForSample = true
        layer.fire()
        XCTAssertEqual(layer.enqueued, 1)
        view.set(data: nil)
        assertStopped(view, layer: layer)
    }
    func testSameDataCanBeRetriedAfterFailedStart() {
        ControlledAssetReader.rejectStart = true
        let view = GIFPlayerView()
        let media = data()
        view.set(data: media)
        sampleBufferQueue.sync {}
        let layer = view.sampleBufferLayer as! ControlledSampleBufferDisplayLayer
        layers.append(layer)
        layer.fire()
        ControlledAssetReader.rejectStart = false
        view.set(data: media)
        sampleBufferQueue.sync {}
        layer.fire()
        layer.readyForSample = true
        layer.fire()
        XCTAssertEqual(layer.enqueued, 1)
        view.set(data: nil)
        assertStopped(view, layer: layer)
    }
    func testRestartInvalidatesTimerAfterClockDetachment() {
        let view = GIFPlayerView()
        let layer = start(view)
        let timer = view._timer.with { $0 }!
        layer.controlTimebase = nil
        view.reset(with: nil)
        sampleBufferQueue.sync {}
        layer.fire()
        XCTAssertFalse(CFRunLoopTimerIsValid(timer))
        view.set(data: nil)
        assertStopped(view, layer: layer)
    }
    func testClockCreationFailureStopsWithoutCrashing() {
        rejectTimebaseCreation = true
        let view = GIFPlayerView()
        view.set(data: data())
        sampleBufferQueue.sync {}
        let layer = view.sampleBufferLayer as! ControlledSampleBufferDisplayLayer
        layers.append(layer)
        layer.fire()
        assertStopped(view, layer: layer)
    }
}
