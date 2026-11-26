import Cocoa
import CoreMedia
import AVFoundation
import SwiftSignalKit
import XCTest

__VALUES__
__RANGE__
func delay<T, E>(_ timeout: Double, queue: Queue) -> (Signal<T, E>) -> Signal<T, E> { { $0 } }
extension CGRect { func apply(multiplier: CGSize) -> CGRect { CGRect(x: origin.x * multiplier.width, y: origin.y * multiplier.height, width: width * multiplier.width, height: height * multiplier.height) } }
func makeImage(_ width: Int = 2) -> CGImage { CGContext(data: nil, width: width, height: 2, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()! }
func makeValues(_ key: CGFloat? = 0.3, paused: Bool = true, suspended: Bool = true) -> VideoScrubberValues { VideoScrubberValues(movePos: key ?? 0, keyFrame: key, leftTrim: 0.2, rightTrim: 0.6, minDist: 0.1, maxDist: 1, paused: paused, suspended: suspended) }
final class Request<T> {
    var subscriber: Subscriber<T, NoError>?
    var disposed = false
    var starts = 0
    var initial: T?
    var empty = false
    var signal: Signal<T, NoError> { Signal { [weak self] subscriber in
        guard let self else { return EmptyDisposable }
        self.subscriber = subscriber; self.starts += 1
        if let initial = self.initial { subscriber.putNext(initial); subscriber.putCompletion() }
        if self.empty { subscriber.putCompletion() }
        return ActionDisposable { [weak self] in self?.disposed = true }
    } }
    func send(_ value: T) { subscriber?.putNext(value) }
    func complete() { subscriber?.putCompletion() }
}
final class Asset {
    let duration = CMTime(seconds: 10, preferredTimescale: 1000)
    var previews: [Request<(CGImage?, CGImage?)>] = []
    var times: [Double] = []
    var thumbs: [Request<([CGImage], Bool)>] = []
    var initialPreview: (CGImage?, CGImage?)?
    var emptyPreview = false
}
final class Composition {}
func generateVideoAvatarPreview(for asset: Asset, composition: Composition?, highSize: CGSize, lowSize: CGSize, at seconds: Double) -> Signal<(CGImage?, CGImage?), NoError> {
    let request = Request<(CGImage?, CGImage?)>(); request.initial = asset.initialPreview; request.empty = asset.emptyPreview
    asset.previews.append(request); asset.times.append(seconds); return request.signal
}
func generateVideoScrubberThumbs(for asset: Asset, composition: Composition?, size: CGSize, count: Int, gradually: Bool, blur: Bool) -> Signal<([CGImage], Bool), NoError> {
    let request = Request<([CGImage], Bool)>(); asset.thumbs.append(request); return request.signal
}
final class Selection { var selectedRect = CGRect(x: 0, y: 0, width: 100, height: 100) }
final class Scrubber {
    var frame = CGRect(x: 0, y: 0, width: 370, height: 40)
    var rendered: [Int] = []
    var updateValues: ((VideoScrubberValues) -> Void)?
    func render(_ images: [CGImage], size: CGSize) { rendered.append(images.first?.width ?? 0) }
}
final class GenericView {
    let selectionRectView = Selection(); let scrubberView = Scrubber(); let playerSize = CGSize(width: 100, height: 100)
    var values: [CGFloat] = []; var completions: [(Bool) -> Void] = []; var moves: [(CGFloat) -> Void] = []; var clears = 0; var imageUpdates = 0
    var immediate = false
    func updateKeyFrameImage(_ image: CGImage?) { imageUpdates += 1 }
    func setKeyFrame(value: CGFloat?, highRes: CGImage? = nil, lowRes: CGImage? = nil, animated: Bool, completion: @escaping (Bool) -> Void = { _ in }, moveToCurrentKeyFrame: @escaping (CGFloat) -> Void = { _ in }) {
        if let value { values.append(value); completions.append(completion); moves.append(moveToCurrentKeyFrame); if immediate || !animated { completion(true) } } else { clears += 1 }
    }
}
final class Item { var forwardPlaybackEndTime = CMTime.invalid }
final class Player {
    var rate: Float = 1; var plays = 0; var seeks: [CMTime] = []; var observers: [(CMTime) -> Void] = []
    func pause() { rate = 0 }
    func play() { rate = 1; plays += 1 }
    func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) { seeks.append(time) }
    func addPeriodicTimeObserver(forInterval: CMTime, queue: DispatchQueue?, using: @escaping (CMTime) -> Void) -> Any { observers.append(using); return observers.count - 1 }
    func removeTimeObserver(_ token: Any) {}
}
class Base { func viewWillAppear(_ animated: Bool) {}; func viewWillDisappear(_ animated: Bool) {} }
final class Editor: Base {
    let asset = Asset(), genericView = GenericView(), player = Player(), item = Item()
    let scrubberValues: Atomic<VideoScrubberValues>
    var appliedKeyFrame: CGFloat?
    let keyFrameGeneratorDisposable = MetaDisposable(), updateThumbsDisposable = MetaDisposable()
    var keyFrameGeneration = UUID(), keyFrameInteractionGeneration = UUID(), thumbnailGeneration = UUID(), playbackGeneration = UUID()
    var playbackActive = true, firstTime = true, keyFramePreviewResumePending = false, observesValues = false
    var generatedRect: CGRect?, timeObserverToken: Any?, playToEndObserver: NSObjectProtocol?
    var compositionAvailable = true
    var updates = 0
    var seeks: [Double] { player.seeks.map { $0.seconds / 10 } }
    init(_ values: VideoScrubberValues = makeValues()) { scrubberValues = Atomic(value: values); super.init(); genericView.scrubberView.updateValues = __INPUT__ }
    func currentVideoComposition() -> Composition? { compositionAvailable ? Composition() : nil }
    func updateValues(_ f: (VideoScrubberValues) -> VideoScrubberValues) { updates += 1; let value = scrubberValues.modify(f); if observesValues { applyValuesToPlayer(value) } }
    func choose(_ values: VideoScrubberValues) { genericView.scrubberView.updateValues?(values); applyValuesToPlayer(values) }
    func deliver(_ index: Int = 0, image: CGImage? = makeImage()) { asset.previews[index].send((image, image)) }
    __INVALIDATE__
    __METHODS__
    deinit { keyFrameGeneratorDisposable.dispose(); updateThumbsDisposable.dispose(); if let playToEndObserver { NotificationCenter.default.removeObserver(playToEndObserver) } }
}
final class ControllerTests: XCTestCase {
    func testRepeatedPlaybackUpdatesCoalescePendingPreview() { let e = Editor(); e.applyValuesToPlayer(makeValues()); e.applyValuesToPlayer(makeValues()); XCTAssertEqual(e.asset.previews.count, 1) }
    func testChangingSelectionCancelsPriorPreview() { let e = Editor(); e.applyValuesToPlayer(makeValues()); e.choose(makeValues(0.4)); XCTAssertTrue(e.asset.previews[0].disposed); e.deliver(0); e.deliver(1); XCTAssertEqual(e.genericView.values, [0.4]) }
    func testClearingSelectionCancelsPendingPreview() { let e = Editor(); e.applyValuesToPlayer(makeValues()); e.choose(makeValues(nil)); XCTAssertTrue(e.asset.previews[0].disposed); e.deliver(); XCTAssertTrue(e.genericView.values.isEmpty) }
    func testHiddenEditorCancelsPreviewGeneration() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.viewWillDisappear(false); XCTAssertTrue(e.asset.previews[0].disposed); e.deliver(); XCTAssertTrue(e.genericView.values.isEmpty) }
    func testHiddenEditorIgnoresAnimationCompletion() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(); let finish = e.genericView.completions[0]; e.viewWillDisappear(false); let count = e.updates; finish(true); XCTAssertEqual(e.updates, count); XCTAssertTrue(e.scrubberValues.with { $0.paused }) }
    func testOldAnimationCannotResumeNewSelection() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(); let finish = e.genericView.completions[0]; e.choose(makeValues(0.4)); let count = e.updates; finish(true); XCTAssertEqual(e.updates, count); XCTAssertEqual(e.scrubberValues.with { $0.keyFrame }, 0.4) }
    func testOldAnimationCannotResumeSameFrameAfterUserInteraction() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(); e.choose(makeValues(0.3).withUpdatedMove(0.4)); let count = e.updates; e.genericView.completions[0](true); XCTAssertEqual(e.updates, count); XCTAssertEqual(e.scrubberValues.with { $0.movePos }, 0.4) }
    func testValidAnimationCompletionResumesOnce() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(); e.genericView.completions[0](true); let v = e.scrubberValues.with { $0 }; XCTAssertFalse(v.paused); XCTAssertFalse(v.suspended); XCTAssertEqual(v.movePos, 0.3) }
    func testFailedAnimationReleasesSuspension() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(); e.genericView.completions[0](false); XCTAssertFalse(e.scrubberValues.with { $0.suspended }); XCTAssertFalse(e.scrubberValues.with { $0.paused }) }
    func testNilPreviewReleasesSuspensionWithoutBlankView() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(image: nil); XCTAssertFalse(e.scrubberValues.with { $0.suspended }); XCTAssertTrue(e.genericView.values.isEmpty) }
    func testEmptyPreviewReleasesSuspension() { let e = Editor(); e.asset.emptyPreview = true; e.runKeyFrameUpdater(0.3); XCTAssertFalse(e.scrubberValues.with { $0.suspended }) }
    func testUnavailableCompositionReleasesSuspension() { let e = Editor(); e.compositionAvailable = false; e.runKeyFrameUpdater(0.3); XCTAssertFalse(e.scrubberValues.with { $0.suspended }); XCTAssertTrue(e.asset.previews.isEmpty) }
    func testSynchronousPreviewDoesNotLoseOwnership() { let e = Editor(); e.asset.initialPreview = (makeImage(), makeImage()); e.genericView.immediate = true; e.runKeyFrameUpdater(0.3); XCTAssertFalse(e.scrubberValues.with { $0.suspended }); XCTAssertTrue(e.asset.previews[0].disposed); XCTAssertEqual(e.appliedKeyFrame, 0.3) }
    func testRefreshDoesNotResumeManualPause() { let e = Editor(makeValues(0.3, paused: true, suspended: false)); e.runKeyFrameUpdater(0.3); e.deliver(); e.genericView.completions[0](true); XCTAssertTrue(e.scrubberValues.with { $0.paused }) }
    func testHiddenEditorIgnoresOldPreviewClick() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(); e.viewWillDisappear(false); let count = e.seeks.count; e.genericView.moves[0](0.3); XCTAssertEqual(e.seeks.count, count) }
    func testOldPreviewClickCannotSeekNewSelection() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(); e.choose(makeValues(0.4)); let count = e.seeks.count; e.genericView.moves[0](0.3); XCTAssertEqual(e.seeks.count, count) }
    func testCurrentPreviewClickSeeksAndPreservesPause() { let e = Editor(makeValues(0.3, paused: true, suspended: false)); e.observesValues = true; e.runKeyFrameUpdater(0.3); e.deliver(); e.genericView.moves[0](0.3); XCTAssertEqual(e.seeks.last, 0.3); XCTAssertTrue(e.scrubberValues.with { $0.paused }); XCTAssertEqual(e.player.seeks.last?.seconds, 3) }
    func testRepeatedCropDoesNotRestartPendingThumbnails() { let e = Editor(); e.updateUserInterface(false); e.updateUserInterface(false); XCTAssertEqual(e.asset.thumbs.count, 1) }
    func testNewCropReplacesOldPreviewAndThumbnails() { let e = Editor(); e.updateUserInterface(false); e.genericView.selectionRectView.selectedRect.origin.x = 5; e.updateUserInterface(false); XCTAssertTrue(e.asset.previews[0].disposed); XCTAssertTrue(e.asset.thumbs[0].disposed); e.deliver(0); e.deliver(1); XCTAssertEqual(e.genericView.values, [0.3]) }
    func testHiddenEditorCancelsThumbnailsAndInvalidatesCache() { let e = Editor(); e.updateUserInterface(false); e.viewWillDisappear(false); XCTAssertTrue(e.asset.thumbs[0].disposed); XCTAssertNil(e.generatedRect); e.asset.thumbs[0].send(([makeImage()], true)); XCTAssertTrue(e.genericView.scrubberView.rendered.isEmpty) }
    func testReappearanceRestartsCoverAndTimeline() { let e = Editor(); e.updateUserInterface(false); e.viewWillDisappear(false); e.viewWillAppear(false); XCTAssertEqual(e.asset.thumbs.count, 2); XCTAssertGreaterThanOrEqual(e.asset.previews.count, 2) }
    func testCropThumbnailCannotReplaceNewCover() { let e = Editor(); e.updateUserInterface(false); e.choose(makeValues(0.4)); e.asset.thumbs[0].send(([makeImage()], true)); XCTAssertEqual(e.genericView.imageUpdates, 0) }
    func testPreviewCallbacksDoNotRetainEditor() { var e: Editor? = Editor(); e!.runKeyFrameUpdater(0.3); e!.deliver(); let view = e!.genericView; let request = e!.asset.previews[0]; weak var weakEditor = e; e = nil; XCTAssertNil(weakEditor); XCTAssertTrue(request.disposed); view.completions[0](true); view.moves[0](0.3) }
    func testReturningToSameFrameCannotReviveOldAnimation() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(); let finish = e.genericView.completions[0]; e.choose(makeValues(0.4)); e.choose(makeValues(0.3)); let count = e.updates; finish(true); XCTAssertEqual(e.updates, count) }
    func testReappearingEditorIgnoresOldAnimation() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(); let finish = e.genericView.completions[0]; e.viewWillDisappear(false); e.viewWillAppear(false); let count = e.updates; finish(true); XCTAssertEqual(e.updates, count) }
    func testCropChangeInvalidatesOldAnimationCompletion() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(); let finish = e.genericView.completions[0]; e.genericView.selectionRectView.selectedRect.origin.x = 5; e.updateUserInterface(false); let count = e.updates; finish(true); XCTAssertEqual(e.updates, count) }
    func testDuplicateGeneratorOutputDoesNotCreateMultiplePreviews() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(); e.deliver(); XCTAssertEqual(e.genericView.values, [0.3]) }
    func testPendingPreviewDoesNotRetainEditor() { var e: Editor? = Editor(); e!.runKeyFrameUpdater(0.3); let request = e!.asset.previews[0]; weak var weakEditor = e; e = nil; XCTAssertNil(weakEditor); XCTAssertTrue(request.disposed) }
    func testPreviewCompletionResumesFromCoverRatherThanTrimStart() { let e = Editor(); e.observesValues = true; e.player.pause(); e.runKeyFrameUpdater(0.3); e.deliver(); e.genericView.completions[0](true); XCTAssertEqual(e.player.seeks.last?.seconds, 3); XCTAssertEqual(e.player.rate, 1) }
    func testRepeatedCompletionCannotRestartPlaybackTwice() { let e = Editor(); e.runKeyFrameUpdater(0.3); e.deliver(); e.genericView.completions[0](true); let plays = e.player.plays; e.genericView.completions[0](true); XCTAssertEqual(e.player.plays, plays) }
    func testStaleValuesCannotPauseCurrentPlayback() { let e = Editor(makeValues(0.4, paused: false, suspended: false)); e.applyValuesToPlayer(makeValues(0.3)); XCTAssertEqual(e.player.rate, 1); XCTAssertTrue(e.asset.previews.isEmpty) }
    func testQueuedPreviewCannotArriveAfterHide() {
        let e = Editor(); e.runKeyFrameUpdater(0.3)
        let delivered = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { e.deliver(); delivered.signal() }
        XCTAssertEqual(delivered.wait(timeout: .now() + 2), .success)
        e.viewWillDisappear(false)
        let done = expectation(description: "drain main queue")
        DispatchQueue.main.async { XCTAssertTrue(e.genericView.values.isEmpty); done.fulfill() }
        wait(for: [done], timeout: 2)
    }
    func testQueuedPreviewCannotReplaceNewSelection() {
        let e = Editor(); e.runKeyFrameUpdater(0.3)
        let delivered = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { e.deliver(); delivered.signal() }
        XCTAssertEqual(delivered.wait(timeout: .now() + 2), .success)
        e.choose(makeValues(0.4)); e.deliver(1)
        let done = expectation(description: "drain main queue")
        DispatchQueue.main.async { XCTAssertEqual(e.genericView.values, [0.4]); done.fulfill() }
        wait(for: [done], timeout: 2)
    }
    func testCropRefreshPreservesPauseAfterCoverClick() {
        let e = Editor(makeValues(0.3, paused: true, suspended: false)); e.observesValues = true
        e.runKeyFrameUpdater(0.3); e.deliver(); e.genericView.moves[0](0.3)
        e.updateUserInterface(false); e.deliver(1)
        XCTAssertTrue(e.scrubberValues.with { $0.paused })
        XCTAssertEqual(e.player.rate, 0)
    }
    func testCropRefreshDuringCoverAnimationStillResumesFromCover() {
        let e = Editor(); e.observesValues = true; e.player.pause()
        e.runKeyFrameUpdater(0.3); e.deliver(); e.updateUserInterface(false); e.deliver(1)
        XCTAssertFalse(e.scrubberValues.with { $0.paused })
        XCTAssertEqual(e.player.seeks.last?.seconds, 3)
    }
    func testCoverAtTrimEndUsesDecodableInteriorTime() { let e = Editor(makeValues(0.6)); e.runKeyFrameUpdater(0.6); XCTAssertEqual(e.asset.times.last!, 5.95, accuracy: 0.0001) }
}

final class Layer {
    var cornerRadius: CGFloat = 0
    var alpha: [(Bool) -> Void] = [], positions: [(Bool) -> Void] = []
    func animateAlpha(from: CGFloat, to: CGFloat, duration: Double, timingFunction: CAMediaTimingFunctionName = .easeIn, removeOnCompletion: Bool = true, completion: ((Bool) -> Void)? = nil) { if let completion { alpha.append(completion) } }
    func animateScale(from: CGFloat, to: CGFloat, duration: Double, removeOnCompletion: Bool) {}
    func animatePosition(from: CGPoint, to: CGPoint, duration: Double, removeOnCompletion: Bool, completion: @escaping (Bool) -> Void) { positions.append(completion) }
    func removeAllAnimations() {}
}
enum Event { case Click }
class View {
    var frame: CGRect
    var layer: Layer? = Layer()
    var subviews: [View] = []
    weak var superview: View?
    var backgroundColor: NSColor = .clear
    var image: CGImage?
    var handler: ((View) -> Void)?
    var needsLayout = false
    init(frame: CGRect = .zero) { self.frame = frame }
    func addSubview(_ view: View) { view.superview = self; subviews.append(view) }
    func removeFromSuperview() { superview?.subviews.removeAll { $0 === self }; superview = nil }
    func convert(_ point: CGPoint, from: View) -> CGPoint { point }
    func set(handler: @escaping (View) -> Void, for event: Event) { self.handler = handler }
}
final class Timeline: View { func timelinePosition(for value: CGFloat) -> CGFloat { 8 + value * max(0, frame.width - 16) } }
final class CropView: View { var selectedRect = CGRect(x: 0, y: 0, width: 100, height: 100) }
final class VideoAvatarKeyFramePreviewView: View {
    let imageView = View(), flash = View()
    var keyFrame: CGFloat?
    override init(frame: CGRect = .zero) { super.init(frame: frame); addSubview(imageView); addSubview(flash) }
    __UPDATE__
}
final class PreviewView: View {
    var keyFramePreview: VideoAvatarKeyFramePreviewView?, keyFrameDotView: View?
    var keyFrameGeneration = UUID(), keyFrameAnimating = false
    let controls = View(frame: CGRect(x: 0, y: 200, width: 370, height: 44))
    let scrubberView = Timeline(frame: CGRect(x: 0, y: 0, width: 370, height: 44))
    let selectionRectView = CropView()
    __VIEW__
    var latest: VideoAvatarKeyFramePreviewView { subviews.compactMap { $0 as? VideoAvatarKeyFramePreviewView }.last! }
    func show(_ value: CGFloat, animated: Bool = true, completion: @escaping (Bool) -> Void = { _ in }, click: @escaping (CGFloat) -> Void = { _ in }) { setKeyFrame(value: value, highRes: makeImage(), lowRes: makeImage(), animated: animated, completion: completion, moveToCurrentKeyFrame: click) }
}
final class ViewTests: XCTestCase {
    func testClearDuringFlashRemovesPendingView() { let v = PreviewView(); v.show(0.3); let p = v.latest; v.setKeyFrame(value: nil, animated: false); XCTAssertTrue(v.subviews.isEmpty); p.flash.layer!.alpha[0](true); XCTAssertTrue(v.subviews.isEmpty); XCTAssertNil(v.keyFramePreview) }
    func testReplacementDuringFlashCannotCreateOldDot() { let v = PreviewView(); v.show(0.3); let old = v.latest; v.show(0.4); let current = v.latest; old.flash.layer!.alpha[0](true); XCTAssertEqual(v.subviews.count, 1); XCTAssertTrue(v.keyFramePreview === current); XCTAssertNil(old.superview) }
    func testClearDuringMovementCannotResurrectPreview() { let v = PreviewView(); var completions = 0; v.show(0.3, completion: { _ in completions += 1 }); let p = v.latest; p.flash.layer!.alpha[0](true); let finish = p.layer!.positions[0]; v.setKeyFrame(value: nil, animated: false); finish(true); XCTAssertTrue(v.subviews.isEmpty); XCTAssertNil(v.keyFramePreview); XCTAssertNil(v.keyFrameDotView); XCTAssertEqual(completions, 0) }
    func testOldMovementCannotReplaceNewPreview() { let v = PreviewView(); v.show(0.3); let old = v.latest; old.flash.layer!.alpha[0](true); let finish = old.layer!.positions[0]; v.show(0.4); let current = v.latest; finish(true); XCTAssertTrue(v.keyFramePreview === current); XCTAssertEqual(v.subviews.count, 1) }
    func testCurrentAnimationFinishesAtCompactSize() { let v = PreviewView(); var completed = false; v.show(0.3, completion: { completed = $0 }); let p = v.latest; p.flash.layer!.alpha[0](true); p.layer!.positions[0](true); XCTAssertTrue(completed); XCTAssertEqual(p.frame.size, CGSize(width: 30, height: 30)); XCTAssertEqual(v.subviews.count, 2); XCTAssertTrue(v.keyFramePreview === p) }
    func testCancelledMovementClearsReferences() { let v = PreviewView(); v.show(0.3); let p = v.latest; p.flash.layer!.alpha[0](true); p.layer!.positions[0](false); XCTAssertNil(v.keyFramePreview); XCTAssertNil(v.keyFrameDotView); XCTAssertTrue(v.subviews.isEmpty) }
    func testCancelledFlashClearsReferences() { let v = PreviewView(); var result: Bool?; v.show(0.3, completion: { result = $0 }); let p = v.latest; p.flash.layer!.alpha[0](false); XCTAssertNil(v.keyFramePreview); XCTAssertTrue(v.subviews.isEmpty); XCTAssertEqual(result, false) }
    func testNonAnimatedPreviewFinishesSynchronously() { let v = PreviewView(); var completed = false; v.show(0.3, animated: false, completion: { completed = $0 }); XCTAssertTrue(completed); XCTAssertEqual(v.keyFramePreview?.frame.width, 30); XCTAssertEqual(v.subviews.count, 2) }
    func testRetainedOldPreviewCannotInvokeClick() { let v = PreviewView(); var clicks = 0; v.show(0.3, click: { _ in clicks += 1 }); let old = v.latest; v.setKeyFrame(value: nil, animated: false); old.handler?(old); XCTAssertEqual(clicks, 0) }
    func testRetainedAnimationsDoNotRetainOwner() { var v: PreviewView? = PreviewView(); v!.show(0.3); let p = v!.latest; weak var weakView = v; v = nil; XCTAssertNil(weakView); p.flash.layer!.alpha[0](true) }
}
