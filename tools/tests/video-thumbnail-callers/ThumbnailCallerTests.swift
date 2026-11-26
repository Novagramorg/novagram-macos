import Cocoa
import AVFoundation
import SwiftSignalKit
import XCTest

let baseline = ProcessInfo.processInfo.environment["CALLER_BASELINE"] == "1"
var displayScale: CGFloat = 2
extension CGSize { func multipliedByScreenScale() -> CGSize { CGSize(width: width * displayScale, height: height * displayScale) } }
extension CGImage { var blurred: CGImage { self } }
extension CGFloat { static var borderSize: CGFloat { 1 } }
func floorToScreenPixels(_ scale: CGFloat, _ value: CGFloat) -> CGFloat { floor(value * scale) / scale }
func picture(_ width: Int = 20, _ height: Int = 20) -> CGImage { CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()! }
struct Metrics { static let minAspect: CGFloat = 0.66; static let trimmableDuration: Double = 2 }
struct Theme { struct Colors { let accent = NSColor.blue }; let colors = Colors() }
let theme = Theme()
struct LocalStrings { let voiceOverCommonPause = "Pause", voiceOverCommonPlay = "Play" }
func strings() -> LocalStrings { LocalStrings() }
final class AudioWaveform {}
enum KeyHandlerResult { case invoked }
enum Key { case Space }
enum Priority { case modal }
final class Window {
    var handler: (() -> KeyHandlerResult)?
    func set(handler: @escaping (Int) -> KeyHandlerResult, with owner: AnyObject, for key: Key, priority: Priority) { self.handler = { handler(0) } }
    func removeAllHandlers(for owner: AnyObject) { handler = nil }
}
class View {
    var frame = CGRect.zero
    var window: Window? = Window()
    var needsLayout = false, isHidden = false, isVideo = false
    var subviews: [View] = []
    var image: CGImage?
    var backingScaleFactor: CGFloat = 2
    var backgroundColor = NSColor.clear
    func layout() {}
    func viewDidMoveToWindow() {}
    func viewDidAppear(_ animated: Bool) {}
    func viewWillDisappear(_ animated: Bool) {}
    func setAccessibilityLabel(_ text: String) {}
}
typealias ImageView = View
final class Waveform: View { var waveform: AudioWaveform? }
final class Thumbnails: View {
    var images: [CGImage] = []
    var rendered: [[Int]] = []
    var onRender: (() -> Void)?
    var isEmpty: Bool { images.isEmpty }
    func render(_ images: [CGImage]) { self.images = images; rendered.append(images.map { $0.width }); onRender?() }
    __LAYOUT__
}
final class Request {
    let path: String, size: CGSize, count: Int
    var subscriber: Subscriber<([CGImage], Bool), NoError>?
    var disposed = false
    init(_ path: String, _ size: CGSize, _ count: Int) { self.path = path; self.size = size; self.count = count }
    func send(_ image: CGImage? = picture()) { subscriber?.putNext((image.map { [$0] } ?? [], true)) }
    var signal: Signal<([CGImage], Bool), NoError> { Signal { [weak self] subscriber in self?.subscriber = subscriber; if let image = Factory.synchronousImage { subscriber.putNext(([image], true)) }; return ActionDisposable { [weak self] in self?.disposed = true } } }
}
enum Factory { static var requests: [Request] = []; static var synchronousImage: CGImage? }
func generateVideoScrubberThumbs(for asset: AVURLAsset, composition: AVVideoComposition?, size: CGSize, count: Int, gradually: Bool, blur: Bool) -> Signal<([CGImage], Bool), NoError> {
    let request = Request(asset.url.path, size, count); Factory.requests.append(request); return request.signal
}
final class Recording: View {
    let thumbnails = Thumbnails(), dimClip = View(), selection = View(), waveformView = Waveform(), leftHandle = View(), rightHandle = View(), playPill = View()
    var videoPath: String?, videoPlaceholder: CGImage?, thumbnailsRequest: __REQUEST__
    var thumbnailsGeneration = UUID()
    var drag: Bool?
    let thumbnailsDisposable = MetaDisposable()
    var duration: Double = 10, trimRange = 0.0..<10.0, position: Double = 0, isPlaying = false
    override init() { super.init(); isVideo = true }
    func refreshPlayIcon() {}
    func updateDurationText() {}
    __RECORDING__
    func configure(_ path: String = "/tmp/a.mp4", placeholder: CGImage? = nil, size: CGSize = CGSize(width: 200, height: 40)) { setVideo(path: path, placeholder: placeholder); updateThumbnails(size: size) }
    deinit { thumbnailsDisposable.dispose() }
}
final class EditVideoScrubberView {
    static let stripHeight: CGFloat = 40
    var stripWidth: CGFloat = 200
    var frames: [[Int]] = [], positions: [Double] = []
    func setThumbnails(_ images: [CGImage], width: CGFloat) { frames.append(images.map { $0.width }) }
    func setPosition(_ value: Double) { positions.append(value) }
}
final class GenericView { let scrubber = EditVideoScrubberView(); var playing: [Bool] = []; func updatePlaying(_ value: Bool) { playing.append(value) } }
final class Player { var rate: Float = 0; var plays = 0; func play() { plays += 1; rate = 1 }; func pause() { rate = 0 } }
struct EditData { var trimStart: Double = 2, trimEnd: Double = 8 }
final class Editor: View {
    let genericView = GenericView(), player = Player()
    let asset = AVURLAsset(url: URL(fileURLWithPath: "/tmp/editor.mp4"))
    var duration: Double = 10, displaySize = CGSize(width: 640, height: 480)
    let thumbnailsDisposable = MetaDisposable()
    var thumbnailsCount = 0, thumbnailsSize = CGSize.zero, thumbnailsGeneration = UUID()
    var isClosing = false, presentationActive = true, resumeAfterSeek = false, isSeeking = false, isGif = false
    var data = EditData(), currentTime: Double = 3
    var isPlaying: Bool { player.rate != 0 }
    var seeks: [Double] = []
    var endSeek: (() -> Void)!, tick: ((CMTime) -> Void)!
    override init() { super.init(); endSeek = __END_SEEK__; tick = __TICK__ }
    func seekExact(_ value: Double) { seeks.append(value); currentTime = value }
    func pause() { player.pause(); genericView.updatePlaying(false) }
    __EDITOR__
    deinit { thumbnailsDisposable.dispose() }
}
class Case: XCTestCase {
    override func setUp() { Factory.requests = []; Factory.synchronousImage = nil; displayScale = 2 }
    func drain(_ assertions: @escaping () -> Void) { let done = expectation(description: "main queue"); DispatchQueue.main.async { assertions(); done.fulfill() }; wait(for: [done], timeout: 2) }
    func enqueue(_ request: Request, image: CGImage = picture()) { let sent = DispatchSemaphore(value: 0); DispatchQueue.global().async { request.send(image); sent.signal() }; XCTAssertEqual(sent.wait(timeout: .now() + 2), .success) }
}
final class RecordingTests: Case {
    func testMediaReplacementImmediatelyCancelsOldRequest() { let s = Recording(); s.configure(); let old = Factory.requests[0]; s.setVideo(path: "/tmp/b.mp4", placeholder: nil); XCTAssertTrue(old.disposed) }
    func testMediaReplacementClearsOldImagesBeforeNewDecode() { let s = Recording(); s.configure(); Factory.requests[0].send(picture(21)); s.setVideo(path: "/tmp/b.mp4", placeholder: nil); XCTAssertTrue(s.thumbnails.images.isEmpty) }
    func testOldMediaCannotRenderBeforeNextLayout() { let s = Recording(); s.configure(); let old = Factory.requests[0]; s.setVideo(path: "/tmp/b.mp4", placeholder: nil); old.send(picture(21)); XCTAssertTrue(s.thumbnails.images.isEmpty) }
    func testSamePathReplacementInvalidatesPriorFileContents() { let s = Recording(); s.configure(); let old = Factory.requests[0]; s.setVideo(path: "/tmp/a.mp4", placeholder: nil); XCTAssertTrue(old.disposed); s.updateThumbnails(size: CGSize(width: 200, height: 40)); XCTAssertEqual(Factory.requests.count, 2) }
    func testRepeatedLayoutReusesCurrentRequest() { let s = Recording(); s.configure(); s.updateThumbnails(size: CGSize(width: 200, height: 40)); XCTAssertEqual(Factory.requests.count, 1) }
    func testHeightChangeWithSameCountRequestsCorrectResolution() { let s = Recording(); s.configure(); s.updateThumbnails(size: CGSize(width: 400, height: 80)); XCTAssertEqual(Factory.requests.count, 2); XCTAssertEqual(Factory.requests.last?.size.height, 80) }
    func testDisplayScaleChangeInvalidatesRequest() { let s = Recording(); s.configure(); displayScale = 1; s.updateThumbnails(size: CGSize(width: 200, height: 40)); XCTAssertEqual(Factory.requests.count, 2) }
    func testNewPlaceholderReplacesPriorMedia() { let s = Recording(); s.configure(); Factory.requests[0].send(picture(21)); s.configure("/tmp/b.mp4", placeholder: picture(22)); XCTAssertEqual(s.thumbnails.images.map { $0.width }, Array(repeating: 22, count: 5)) }
    func testFailedNewMediaDoesNotExposePriorFrames() { let s = Recording(); s.configure(); Factory.requests[0].send(picture(21)); s.configure("/tmp/b.mp4"); Factory.requests[1].send(nil); XCTAssertTrue(s.thumbnails.images.isEmpty) }
    func testClearingPathCancelsAndRemovesImages() { let s = Recording(); s.configure(); Factory.requests[0].send(); s.setVideo(path: nil, placeholder: nil); XCTAssertTrue(Factory.requests[0].disposed); XCTAssertTrue(s.thumbnails.images.isEmpty) }
    func testDetachCancelsAndReattachReloads() { let s = Recording(); s.configure(); s.window = nil; s.viewDidMoveToWindow(); XCTAssertTrue(Factory.requests[0].disposed); s.window = Window(); s.viewDidMoveToWindow(); s.updateThumbnails(size: CGSize(width: 200, height: 40)); XCTAssertEqual(Factory.requests.count, 2) }
    func testDetachedViewDoesNotStartDecode() { let s = Recording(); s.window = nil; s.configure(); XCTAssertTrue(Factory.requests.isEmpty) }
    func testSwitchingToAudioCancelsVideoRequest() { let s = Recording(); s.configure(); s.update(duration: 10, waveform: nil, trimRange: 0..<10, position: 0, isPlaying: false, isVideo: false); XCTAssertTrue(Factory.requests[0].disposed); s.updateThumbnails(size: CGSize(width: 200, height: 40)); XCTAssertEqual(Factory.requests.count, 1) }
    func testQueuedOldMediaResultIgnoredAfterReplacement() { let s = Recording(); s.configure(); enqueue(Factory.requests[0], image: picture(21)); s.setVideo(path: "/tmp/b.mp4", placeholder: nil); drain { XCTAssertTrue(s.thumbnails.images.isEmpty) } }
    func testQueuedResultIgnoredAfterDetachAndReattach() { let s = Recording(); s.configure(); enqueue(Factory.requests[0]); s.window = nil; s.viewDidMoveToWindow(); s.window = Window(); s.viewDidMoveToWindow(); drain { XCTAssertTrue(s.thumbnails.images.isEmpty) } }
    func testInvalidSizingNeverConvertsNonFiniteCount() throws { if baseline { throw XCTSkip("Original unchecked floating-point conversion can trap") }; let s = Recording(); s.setVideo(path: "/tmp/a.mp4", placeholder: nil); for size in [CGSize(width: CGFloat.nan, height: 40), CGSize(width: CGFloat.infinity, height: 40), CGSize(width: 200, height: CGFloat.nan), CGSize(width: 1e100, height: 1), CGSize(width: 100, height: 0), CGSize(width: 100, height: -1)] { s.updateThumbnails(size: size) }; XCTAssertTrue(Factory.requests.isEmpty) }
    func testDecodeCallbacksDoNotRetainRecordingView() { var s: Recording? = Recording(); s!.configure(); let request = Factory.requests[0]; weak var weakView = s; s = nil; XCTAssertNil(weakView); XCTAssertTrue(request.disposed); request.send() }
    func testSynchronousDeliveryCanReplaceMediaWithoutLosingNewRequest() { let s = Recording(); s.configure(); let old = Factory.requests[0]; var replace = true; s.thumbnails.onRender = { if replace { replace = false; s.configure("/tmp/b.mp4") } }; old.send(picture(21)); s.thumbnails.onRender = nil; XCTAssertTrue(old.disposed); XCTAssertFalse(Factory.requests.last!.disposed); XCTAssertEqual(Factory.requests.last!.path, "/tmp/b.mp4") }
}
final class EditorTests: Case {
    func testRepeatedLayoutCoalescesRequests() { let e = Editor(); e.updateThumbnailsIfNeeded(); e.updateThumbnailsIfNeeded(); XCTAssertEqual(Factory.requests.count, 1) }
    func testDisplayScaleChangeRegeneratesThumbnails() { let e = Editor(); e.updateThumbnailsIfNeeded(); displayScale = 1; e.updateThumbnailsIfNeeded(); XCTAssertEqual(Factory.requests.count, 2) }
    func testDisappearanceCancelsDecodeAndReappearanceRestarts() { let e = Editor(); e.updateThumbnailsIfNeeded(); e.viewWillDisappear(false); XCTAssertTrue(Factory.requests[0].disposed); e.viewDidAppear(false); XCTAssertEqual(Factory.requests.count, 2) }
    func testHiddenEditorCannotStartDecode() { let e = Editor(); e.viewWillDisappear(false); e.updateThumbnailsIfNeeded(); XCTAssertTrue(Factory.requests.isEmpty) }
    func testClosingEditorCannotStartDecode() { let e = Editor(); e.isClosing = true; e.updateThumbnailsIfNeeded(); XCTAssertTrue(Factory.requests.isEmpty) }
    func testDisappearanceShowsPausedControlsOnReturn() { let e = Editor(); e.play(); e.viewWillDisappear(false); e.viewDidAppear(false); XCTAssertEqual(e.player.rate, 0); XCTAssertEqual(e.genericView.playing.last, false) }
    func testHiddenGifCannotRestartFromEndNotification() { let e = Editor(); e.isGif = true; e.viewWillDisappear(false); e.handlePlaybackEnd(); XCTAssertEqual(e.player.plays, 0) }
    func testHiddenEditorCannotRestartFromPlayAction() { let e = Editor(); e.viewWillDisappear(false); e.play(); XCTAssertEqual(e.player.plays, 0) }
    func testClosingGifCannotRestartFromEndNotification() { let e = Editor(); e.isGif = true; e.isClosing = true; e.handlePlaybackEnd(); XCTAssertEqual(e.player.plays, 0) }
    func testHiddenEditorCannotResumeFromSeekCompletion() { let e = Editor(); e.resumeAfterSeek = true; e.isSeeking = true; e.viewWillDisappear(false); e.endSeek(); XCTAssertEqual(e.player.plays, 0); XCTAssertFalse(e.resumeAfterSeek); XCTAssertFalse(e.isSeeking) }
    func testVisibleGifStillLoops() { let e = Editor(); e.isGif = true; e.handlePlaybackEnd(); XCTAssertEqual(e.player.plays, 1); XCTAssertEqual(e.seeks.last, 2) }
    func testVisibleVideoStillStopsAtTrimStart() { let e = Editor(); e.player.play(); e.handlePlaybackEnd(); XCTAssertEqual(e.player.rate, 0); XCTAssertEqual(e.seeks.last, 2) }
    func testReappearingGifStillAutoplays() { let e = Editor(); e.isGif = true; e.viewWillDisappear(false); e.viewDidAppear(false); XCTAssertEqual(e.player.plays, 1) }
    func testQueuedThumbnailsCannotRenderAfterHide() { let e = Editor(); e.updateThumbnailsIfNeeded(); enqueue(Factory.requests[0]); e.viewWillDisappear(false); drain { XCTAssertTrue(e.genericView.scrubber.frames.isEmpty) } }
    func testOldThumbnailRequestCannotRenderAfterReappearance() { let e = Editor(); e.updateThumbnailsIfNeeded(); let old = Factory.requests[0]; e.viewWillDisappear(false); e.viewDidAppear(false); old.send(picture(21)); Factory.requests.last!.send(picture(22)); XCTAssertEqual(e.genericView.scrubber.frames, [[22]]) }
    func testInvalidDimensionsAndWidthDoNotTrap() throws { if baseline { throw XCTSkip("Original unchecked floating-point conversion can trap") }; for value in [CGFloat.nan, CGFloat.infinity, CGFloat.greatestFiniteMagnitude, -1, 0] { let e = Editor(); e.genericView.scrubber.stripWidth = value; e.updateThumbnailsIfNeeded(); let f = Editor(); f.displaySize.width = value; f.updateThumbnailsIfNeeded() }; XCTAssertTrue(Factory.requests.isEmpty) }
    func testDecoderCallbackDoesNotRetainEditor() { var e: Editor? = Editor(); e!.updateThumbnailsIfNeeded(); let request = Factory.requests[0]; weak var weakEditor = e; e = nil; XCTAssertNil(weakEditor); XCTAssertTrue(request.disposed) }
    func testHiddenPeriodicCallbackDoesNotMovePlayhead() { let e = Editor(); e.viewWillDisappear(false); e.player.rate = 1; e.tick(CMTime(seconds: 5, preferredTimescale: 30)); XCTAssertTrue(e.genericView.scrubber.positions.isEmpty) }
}
final class LayoutTests: Case {
    func testWideFramesFillStripWithoutDroppingLaterSamples() { let v = Thumbnails(); v.frame = CGRect(x: 0, y: 0, width: 200, height: 40); v.subviews = (0..<5).map { _ in let v = View(); v.image = picture(80, 40); return v }; v.layout(); XCTAssertEqual(v.subviews.last?.frame.maxX, 200); XCTAssertEqual(v.subviews.first?.frame.width, 40) }
    func testPortraitFramesDoNotLeaveGap() { let v = Thumbnails(); v.frame = CGRect(x: 0, y: 0, width: 200, height: 40); v.subviews = (0..<5).map { _ in let v = View(); v.image = picture(20, 40); return v }; v.layout(); XCTAssertEqual(v.subviews.last?.frame.maxX, 200) }
    func testFractionalWidthIsFullyCovered() { let v = Thumbnails(); v.frame = CGRect(x: 0, y: 0, width: 203, height: 40); v.subviews = (0..<6).map { _ in View() }; v.layout(); XCTAssertEqual(v.subviews.last!.frame.maxX, 203, accuracy: 0.0001) }
    func testEmptyStripLayoutIsSafe() { let v = Thumbnails(); v.layout(); XCTAssertTrue(v.subviews.isEmpty) }
}
