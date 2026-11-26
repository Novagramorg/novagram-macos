import Cocoa
import XCTest

let baseline = ProcessInfo.processInfo.environment["TRIM_BASELINE"] == "1"
let skipUnsafe = baseline && ProcessInfo.processInfo.environment["TRIM_UNSAFE"] != "1"
__STATE__
__METRICS__
func floorToScreenPixels(_ scale: CGFloat, _ value: CGFloat) -> CGFloat { floor(value * scale) / scale }
extension CGSize { var bounds: CGRect { CGRect(origin: .zero, size: self) } }
extension String { static func durationTransformed(elapsed: Int) -> String { String(elapsed) } }
extension NSAttributedString {
    static func initialize(string: String, color: NSColor, font: NSFont) -> NSAttributedString { NSAttributedString(string: string) }
}
final class TextViewLayout {
    let text: String
    init(_ value: NSAttributedString, maximumNumberOfLines: Int) { text = value.string }
    func measure(width: CGFloat) {}
}
struct Theme { struct Colors { let accent = NSColor.blue, text = NSColor.white }; let colors = Colors() }
let theme = Theme()
struct LocalStrings { let voiceOverCommonPause = "Pause", voiceOverCommonPlay = "Play" }
func strings() -> LocalStrings { LocalStrings() }
final class AudioWaveform {
    var requests: [Int] = []
    func peaks(count: Int) -> [CGFloat] { requests.append(count); return Array(repeating: 0.5, count: count) }
}
class SimpleLayer {
    var bounds = CGRect.zero
    var needsDisplayOnBoundsChange = false
    init() {}
    init(layer: Any) {}
    required init?(coder: NSCoder) { fatalError() }
    func draw(in ctx: CGContext) {}
}
__WAVEFORM__
final class Window { var mouseLocationOutsideOfEventStream = CGPoint.zero }
class View {
    var frame = CGRect.zero
    var window: Window? = Window()
    var layer: CALayer? = CALayer()
    var needsLayout = false, isHidden = false, isVideo = false
    var backgroundColor = NSColor.clear
    var waveform: AudioWaveform?
    var backingScaleFactor: CGFloat = 2
    var displayedRange: Range<CGFloat> = 0..<0
    var displayedProgress: CGFloat = 0
    func viewDidMoveToWindow() {}
    func setAccessibilityLabel(_ value: String) {}
    func convert(_ point: CGPoint, from: View?) -> CGPoint { point }
    func update(_ layout: TextViewLayout) {}
    func update(trimRange: Range<CGFloat>, progressWidth: CGFloat) { displayedRange = trimRange; displayedProgress = progressWidth }
}
typealias Control = View
struct ContainedViewLayoutTransition {
    static let immediate = ContainedViewLayoutTransition()
    func updateFrame(view: View, frame: CGRect) { view.frame = frame }
}
final class Scrubber: View {
    let thumbnails = View(), dimClip = View(), dimLeft = View(), dimRight = View(), selection = View(), waveformView = View(), leftHandle = View(), rightHandle = View(), seekArea = View(), playPill = View(), durationView = View()
    var duration: Double = 0, trimRange: Range<Double> = 0..<0, position: Double = 0, isPlaying = false
    var selectionFrame = CGRect.zero, durationText = ""
    var videoPath: String?, videoPlaceholder: CGImage?
    var drag: DragState?
    var trimUpdated: ((Range<Double>, Bool, Bool) -> Void)?, seek: ((Double) -> Void)?
    func refreshPlayIcon() {}
    func invalidateThumbnails(clear: Bool) {}
    func updateThumbnails(size: CGSize) {}
    func layoutPlayPill(gap: CGFloat, leftX: CGFloat, height: CGFloat, transition: ContainedViewLayoutTransition) {}
    __METHODS__
    func configure(duration: Double = 10, range: Range<Double>? = nil, width: CGFloat = 232, position: Double = 0) {
        frame = CGRect(x: 0, y: 0, width: width, height: 40)
        update(duration: duration, waveform: AudioWaveform(), trimRange: range ?? 0..<max(0, duration), position: position, isPlaying: false, isVideo: false)
        updateLayout(size: frame.size, transition: .immediate)
    }
    func pointer(_ x: CGFloat) { window?.mouseLocationOutsideOfEventStream = CGPoint(x: x, y: 10) }
}
struct ChatRecordingPreviewData {
    let path = "/tmp/recording.m4a"
    var duration: Double
    var waveform: AudioWaveform? = nil
    var thumb: CGImage? = nil
}
final class Journey {
    var readyCount = 0
    func previewReady() { readyCount += 1 }
    func trimChanged(changed: Bool, committed: Bool) {}
}
final class Recorder {
    var isCancelled = false
    var trimRange: Range<Double>?
    var duration: Double?
    var previewUpdates: [Range<Double>] = []
    var analyticsRecordingJourney: Journey? = Journey()
    func updateTrimRange(_ range: Range<Double>?, duration: Double? = nil) { trimRange = range; if let duration { self.duration = duration } }
    func updatePreviewTrim(_ range: Range<Double>, updatedEnd: Bool, applied: Bool) { previewUpdates.append(range) }
}
final class RecordingPreviewPlayer {
    var onUpdate: (() -> Void)?
    var range: Range<Double>
    init(postbox: Int, preview: ChatRecordingPreviewData, trimRange: Range<Double>) { range = trimRange }
    func updateTrim(_ range: Range<Double>, updatedEnd: Bool, applied: Bool) { self.range = range; onUpdate?() }
}
struct Interaction { struct Context { struct Account { let postbox = 0 }; let account = Account() }; let interactionContext = Context() }
final class RecordingInput {
    var isPaused = true, isResuming = false, isDismissing = false
    let recorder = Recorder(), scrubber = Scrubber(), chatInteraction = Interaction()
    var preview: ChatRecordingPreviewData?, previewPlayer: RecordingPreviewPlayer?
    var trimRange: Range<Double> = 0..<0
    var isVideoRecorder = false, needsLayout = false, refreshes = 0
    func refreshScrubber() { refreshes += 1 }
    __INPUT__
}
final class TrimTests: XCTestCase {
    func testFullSelectionReachesStartFromVisibleSeekEdge() { let s = Scrubber(); s.configure(); XCTAssertEqual(s.value(forX: s.seekArea.frame.minX), 0, accuracy: 0.001) }
    func testFullSelectionReachesEndFromVisibleSeekEdge() { let s = Scrubber(); s.configure(); XCTAssertEqual(s.value(forX: s.seekArea.frame.maxX), 10, accuracy: 0.001) }
    func testTrimSelectionReachesStartFromVisibleSeekEdge() { let s = Scrubber(); s.configure(range: 2..<8); XCTAssertEqual(s.value(forX: s.seekArea.frame.minX), 2, accuracy: 0.001) }
    func testTrimSelectionReachesEndFromVisibleSeekEdge() { let s = Scrubber(); s.configure(range: 2..<8); XCTAssertEqual(s.value(forX: s.seekArea.frame.maxX), 8, accuracy: 0.001) }
    func testPixelRoundedEndpointsRemainReachable() { let s = Scrubber(); s.configure(range: 2.333..<8.777, width: 233); XCTAssertEqual(s.value(forX: s.seekArea.frame.minX), 2.333); XCTAssertEqual(s.value(forX: s.seekArea.frame.maxX), 8.777) }
    func testSeekUsesSourceTimeline() { let s = Scrubber(); s.configure(range: 2..<8); XCTAssertEqual(s.value(forX: 96), 4, accuracy: 0.001) }
    func testSeekClampsOutsideSelection() { let s = Scrubber(); s.configure(range: 2..<8); XCTAssertEqual(s.value(forX: -100), 2); XCTAssertEqual(s.value(forX: 1000), 8) }
    func testDetachedSeekIgnored() { let s = Scrubber(); s.configure(); s.window = nil; var values: [Double] = []; s.seek = { values.append($0) }; s.performSeek(from: s); XCTAssertTrue(values.isEmpty) }
    func testNonfinitePointerIgnored() { let s = Scrubber(); s.configure(); s.pointer(.nan); var values: [Double] = []; s.seek = { values.append($0) }; s.performSeek(from: s); XCTAssertTrue(values.isEmpty) }
    func testTinyTimelineDoesNotSeek() { let s = Scrubber(); s.configure(width: 20); var values: [Double] = []; s.seek = { values.append($0) }; s.performSeek(from: s); XCTAssertTrue(values.isEmpty) }
    func testRightDragUsesSourceScale() { let s = Scrubber(); s.configure(range: 2..<8); s.pointer(100); s.beginDrag(from: s, isEnd: true); s.pointer(120); s.moveDrag(from: s, isEnd: true); XCTAssertEqual(s.trimRange, 2..<9) }
    func testLeftDragUsesSourceScale() { let s = Scrubber(); s.configure(range: 2..<8); s.pointer(100); s.beginDrag(from: s, isEnd: false); s.pointer(120); s.moveDrag(from: s, isEnd: false); XCTAssertEqual(s.trimRange, 3..<8) }
    func testDragClampsOvershoot() { let s = Scrubber(); s.configure(range: 2..<8); s.pointer(100); s.beginDrag(from: s, isEnd: true); s.pointer(1000); s.moveDrag(from: s, isEnd: true); XCTAssertEqual(s.trimRange.upperBound, 10); s.pointer(120); s.moveDrag(from: s, isEnd: true); XCTAssertEqual(s.trimRange.upperBound, 9) }
    func testShortTrimDoesNotExpandOnStationaryDrag() { let s = Scrubber(); s.configure(duration: 100, range: 5..<10); s.pointer(100); s.beginDrag(from: s, isEnd: true); s.moveDrag(from: s, isEnd: true); XCTAssertEqual(s.trimRange, 5..<10) }
    func testDifferentHandleCannotReuseDrag() { let s = Scrubber(); s.configure(range: 2..<8); s.beginDrag(from: s, isEnd: true); s.pointer(20); s.moveDrag(from: s, isEnd: false); XCTAssertEqual(s.trimRange, 2..<8); XCTAssertNil(s.drag) }
    func testShortPreviewCannotBeginTrim() { let s = Scrubber(); s.configure(duration: 1); s.beginDrag(from: s, isEnd: true); XCTAssertNil(s.drag) }
    func testNonfiniteDragOriginRejected() { let s = Scrubber(); s.configure(); s.pointer(.infinity); s.beginDrag(from: s, isEnd: true); XCTAssertNil(s.drag) }
    func testResizeInvalidatesDrag() { let s = Scrubber(); s.configure(range: 2..<8); s.beginDrag(from: s, isEnd: true); s.frame.size.width = 300; s.pointer(20); s.moveDrag(from: s, isEnd: true); XCTAssertNil(s.drag); XCTAssertEqual(s.trimRange, 2..<8) }
    func testResizePreventsCommit() { let s = Scrubber(); s.configure(); s.beginDrag(from: s, isEnd: true); s.frame.size.width = 300; var calls = 0; s.trimUpdated = { _, _, _ in calls += 1 }; s.endDrag(); XCTAssertEqual(calls, 0) }
    func testDetachInvalidatesDrag() { let s = Scrubber(); s.configure(); s.beginDrag(from: s, isEnd: true); s.window = nil; s.viewDidMoveToWindow(); XCTAssertNil(s.drag) }
    func testSamePathReplacementInvalidatesDrag() { let s = Scrubber(); s.configure(); s.beginDrag(from: s, isEnd: true); s.setVideo(path: "/tmp/a.mp4", placeholder: nil); XCTAssertNil(s.drag) }
    func testShorterPreviewInvalidatesDrag() { let s = Scrubber(); s.configure(range: 7..<9); s.beginDrag(from: s, isEnd: true); s.update(duration: 3, waveform: nil, trimRange: 0..<3, position: 0, isPlaying: false, isVideo: false); XCTAssertNil(s.drag) }
    func testExternalTrimChangeInvalidatesDrag() { let s = Scrubber(); s.configure(); s.beginDrag(from: s, isEnd: true); s.update(duration: 10, waveform: nil, trimRange: 2..<8, position: 2, isPlaying: false, isVideo: false); XCTAssertNil(s.drag) }
    func testProgressUpdatePreservesActiveDrag() { let s = Scrubber(); s.configure(range: 2..<8); s.beginDrag(from: s, isEnd: true); s.update(duration: 10, waveform: nil, trimRange: 2..<8, position: 4, isPlaying: true, isVideo: false); XCTAssertNotNil(s.drag) }
    func testOwnTrimCallbackPreservesActiveDrag() { let s = Scrubber(); s.configure(range: 2..<8); s.trimUpdated = { range, _, _ in s.update(duration: 10, waveform: nil, trimRange: range, position: 2, isPlaying: false, isVideo: false) }; s.beginDrag(from: s, isEnd: true); s.pointer(20); s.moveDrag(from: s, isEnd: true); XCTAssertNotNil(s.drag); XCTAssertEqual(s.trimRange, 2..<9) }
    func testEndCommitsOnce() { let s = Scrubber(); s.configure(); s.beginDrag(from: s, isEnd: true); var calls = 0; s.trimUpdated = { _, end, applied in XCTAssertTrue(end); XCTAssertTrue(applied); calls += 1 }; s.endDrag(); s.endDrag(); XCTAssertEqual(calls, 1) }
    func testProgressMatchesSeekCoordinates() { let s = Scrubber(); s.configure(range: 2..<8, position: 4); XCTAssertEqual(s.waveformView.displayedProgress + Metrics.waveInset, 96, accuracy: 0.001) }
    func testWaveformSelectionMatchesSeekArea() { let s = Scrubber(); s.configure(range: 2..<8); XCTAssertEqual(s.waveformView.displayedRange.lowerBound + Metrics.waveInset, s.seekArea.frame.minX); XCTAssertEqual(s.waveformView.displayedRange.upperBound + Metrics.waveInset, s.seekArea.frame.maxX) }
    func testTinyLayoutFitsBounds() { let s = Scrubber(); s.configure(width: 20); XCTAssertLessThanOrEqual(s.selectionFrame.maxX, 20); XCTAssertGreaterThanOrEqual(s.seekArea.frame.width, 0) }
    func testZeroLayoutFitsBounds() { let s = Scrubber(); s.configure(width: 0); XCTAssertEqual(s.selectionFrame.width, 0); XCTAssertEqual(s.seekArea.frame.width, 0) }
    func testNonfinitePositionNormalized() { let s = Scrubber(); s.configure(range: 2..<8, position: .infinity); XCTAssertEqual(s.position, 2) }
    func testNegativeSelectionClamped() { let s = Scrubber(); s.configure(range: -5..<8); XCTAssertEqual(s.trimRange, 0..<8) }
    func testInvalidDurationIsEmpty() throws { if skipUnsafe { throw XCTSkip("Original unchecked duration conversion traps") }; let s = Scrubber(); s.update(duration: .infinity, waveform: nil, trimRange: 0..<Double.infinity, position: 0, isPlaying: false, isVideo: false); XCTAssertEqual(s.duration, 0); XCTAssertEqual(s.trimRange, 0..<0); XCTAssertEqual(s.durationText, "0") }
    func testOversizedDurationLabelDoesNotTrap() throws { if skipUnsafe { throw XCTSkip("Original unchecked duration conversion traps") }; let s = Scrubber(); s.update(duration: Double.greatestFiniteMagnitude, waveform: nil, trimRange: 0..<Double.greatestFiniteMagnitude, position: 0, isPlaying: false, isVideo: false); XCTAssertEqual(s.durationText, "0") }
}
final class PreviewTests: XCTestCase {
    func testShorterPreviewOutsideOldRangeResetsSelection() throws { if skipUnsafe { throw XCTSkip("Original inverted range traps") }; let s = RecordingInput(); s.recorder.trimRange = 7..<9; s.applyPreview(ChatRecordingPreviewData(duration: 3)); XCTAssertEqual(s.trimRange, 0..<3); XCTAssertEqual(s.recorder.trimRange, 0..<3); XCTAssertEqual(s.previewPlayer?.range, 0..<3) }
    func testPartiallyOverlappingTrimClamped() { let s = RecordingInput(); s.recorder.trimRange = 2..<9; s.applyPreview(ChatRecordingPreviewData(duration: 5)); XCTAssertEqual(s.trimRange, 2..<5); XCTAssertEqual(s.recorder.duration, 5) }
    func testEmptyTrimResetsToFullPreview() { let s = RecordingInput(); s.recorder.trimRange = 3..<3; s.applyPreview(ChatRecordingPreviewData(duration: 5)); XCTAssertEqual(s.trimRange, 0..<5) }
    func testNegativeTrimClamped() { let s = RecordingInput(); s.recorder.trimRange = -3..<4; s.applyPreview(ChatRecordingPreviewData(duration: 5)); XCTAssertEqual(s.trimRange, 0..<4) }
    func testInfinitePreviewRejected() { let s = RecordingInput(); s.applyPreview(ChatRecordingPreviewData(duration: .infinity)); XCTAssertNil(s.preview); XCTAssertNil(s.previewPlayer); XCTAssertEqual(s.recorder.analyticsRecordingJourney?.readyCount, 0) }
    func testMissingPreviewIgnoresTrim() { let s = RecordingInput(); s.updateTrim(2..<8, updatedEnd: true, applied: true); XCTAssertNil(s.recorder.trimRange); XCTAssertTrue(s.recorder.previewUpdates.isEmpty) }
    func testTrimUpdateClampedAtAllConsumers() { let s = RecordingInput(); s.applyPreview(ChatRecordingPreviewData(duration: 5)); s.updateTrim(-2..<8, updatedEnd: true, applied: true); XCTAssertEqual(s.trimRange, 0..<5); XCTAssertEqual(s.recorder.trimRange, 0..<5); XCTAssertEqual(s.recorder.previewUpdates, [0..<5]); XCTAssertEqual(s.previewPlayer?.range, 0..<5) }
    func testVideoPreviewUsesSameRangeValidation() throws { if skipUnsafe { throw XCTSkip("Original inverted range traps") }; let s = RecordingInput(); s.isVideoRecorder = true; s.recorder.trimRange = 7..<9; s.applyPreview(ChatRecordingPreviewData(duration: 3)); XCTAssertEqual(s.trimRange, 0..<3); XCTAssertEqual(s.scrubber.videoPath, "/tmp/recording.m4a"); XCTAssertNil(s.previewPlayer) }
}
final class WaveformTests: XCTestCase {
    func render(_ width: CGFloat) -> [Int] {
        let wave = AudioWaveform(), layer = TrimWaveformLayer()
        layer.waveform = wave; layer.bounds = CGRect(x: 0, y: 0, width: width, height: 40)
        let ctx = CGContext(data: nil, width: 232, height: 40, bitsPerComponent: 8, bytesPerRow: 928, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        layer.draw(in: ctx)
        return wave.requests
    }
    func testNormalWaveformSamplingPreserved() { XCTAssertEqual(render(232), [77]) }
    func testZeroWaveformDoesNotAllocate() { XCTAssertEqual(render(0), []) }
    func testInfiniteWaveformDoesNotTrap() throws { if skipUnsafe { throw XCTSkip("Original unchecked sample conversion traps") }; XCTAssertEqual(render(.infinity), []) }
    func testOversizedWaveformDoesNotAllocate() { XCTAssertEqual(render(30000), []) }
}
