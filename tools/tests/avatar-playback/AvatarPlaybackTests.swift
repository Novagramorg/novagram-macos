import Foundation
import CoreMedia
import SwiftSignalKit
import XCTest

__VALUES__
__RANGE__
__INITIAL__
let magicNumber:CGFloat=8/370
final class Token:NSObject {let id:Int;init(_ id:Int) {self.id=id}}
extension Int {static var AVPlayerItemDidPlayToEndTime:Int {1}}
final class NotificationCenter {
 static let `default`=NotificationCenter();var callbacks:[(Int)->Void]=[];var removed:[Int]=[]
 func addObserver(forName:Int,object:AnyObject,queue:OperationQueue?,using:@escaping(Int)->Void)->NSObjectProtocol {let token=Token(callbacks.count);callbacks.append(using);return token}
 func removeObserver(_ token:Any) {removed.append((token as! Token).id)}
}
final class Asset {var duration:CMTime;init(_ duration:Double) {self.duration=CMTime(seconds:duration,preferredTimescale:1000)}}
final class Item {var forwardPlaybackEndTime=CMTime.invalid}
final class Player {
 var rate:Float=0;var seeks:[CMTime]=[];var observers:[(CMTime)->Void]=[];var removed:[Int]=[];var plays=0
 func pause() {rate=0};func play() {rate=1;plays+=1}
 func seek(to time:CMTime,toleranceBefore:CMTime,toleranceAfter:CMTime) {seeks.append(time)}
 func addPeriodicTimeObserver(forInterval:CMTime,queue:DispatchQueue?,using:@escaping(CMTime)->Void)->Any {observers.append(using);return observers.count-1}
 func removeTimeObserver(_ value:Any) {removed.append(value as! Int)}
}
final class Bar {var frame=CGRect(x:0,y:0,width:370,height:40)}
final class View {let scrubberView=Bar();var cleared=0;func setKeyFrame(value:CGFloat?,animated:Bool) {cleared+=1}}
enum Outcome {case error}
final class State {var errors=0;func set(_ signal:Signal<Outcome,NoError>) {_=signal.start(next:{_ in self.errors+=1})}}
class Base {func viewWillAppear(_ animated:Bool) {};func viewWillDisappear(_ animated:Bool) {}}
func makeValues(left:CGFloat=0,right:CGFloat=1,move:CGFloat=0,key:CGFloat?=nil,paused:Bool=false,suspended:Bool=false)->VideoScrubberValues {VideoScrubberValues(movePos:move,keyFrame:key,leftTrim:left,rightTrim:right,minDist:0.1,maxDist:1,paused:paused,suspended:suspended)}
final class Editor:Base {
 let asset:Asset;let player=Player();let item=Item();let genericView=View();let state=State();let scrubberValues:Atomic<VideoScrubberValues>;var appliedKeyFrame:CGFloat?;var playbackGeneration=UUID();var playbackActive=true;var firstTime=true;var thumbnailGeneration=UUID();let updateThumbsDisposable=MetaDisposable();var generatedRect:CGRect?;var timeObserverToken:Any?;var playToEndObserver:NSObjectProtocol?;var closed=false;var updates=0;var keyRequests:[CGFloat]=[]
 init(duration:Double=10,values:VideoScrubberValues=makeValues()) {asset=Asset(duration);scrubberValues=Atomic(value:values);super.init();__NOTIFICATION__}
 func updateValues(_ f:(VideoScrubberValues)->VideoScrubberValues) {updates+=1;_=scrubberValues.modify(f)}
 func close() {closed=true}
 func invalidateKeyFramePreview() {appliedKeyFrame=nil;genericView.setKeyFrame(value:nil,animated:false)}
 func updateUserInterface(_ firstTime:Bool) {}
 func runKeyFrameUpdater(_ value:CGFloat) {keyRequests.append(value);appliedKeyFrame=value}
 func initialize() {let asset=self.asset;let genericView=self.genericView;__INITIALIZATION__}
 __METHODS__
}
final class PlaybackTests:XCTestCase {
 override func setUp() {NotificationCenter.default.callbacks=[];NotificationCenter.default.removed=[]}
 func testLongVideoStartsAtTrimStartRatherThanWholeVideoOffset() {let e=Editor(duration:600,values:makeValues(left:0.5,right:0.5+10/600));e.play();XCTAssertEqual(e.player.seeks.last?.seconds,300);XCTAssertEqual(e.item.forwardPlaybackEndTime.seconds,310,accuracy:0.001)}
 func testLongVideoDoesNotLoopBeforeTenSecondSelectionEnds() {let v=makeValues(left:0.5,right:0.5+10/600,move:0.5);let e=Editor(duration:600,values:v);e.player.rate=1;e.applyValuesToPlayer(v);XCTAssertEqual(e.player.plays,0);XCTAssertEqual(e.item.forwardPlaybackEndTime.seconds,310,accuracy:0.001)}
 func testPositionAtTrimEndLoopsToExactStart() {let v=makeValues(left:0.2,right:0.6,move:0.6);let e=Editor(values:v);e.player.rate=1;e.applyValuesToPlayer(v);XCTAssertEqual(e.player.seeks.last?.seconds,2);XCTAssertEqual(e.player.plays,1)}
 func testSuspendedSeekClampsToSelectedRange() {let e=Editor();let actual=e.seekToNormal(makeValues(left:0.2,right:0.6,move:0.9,suspended:true));XCTAssertEqual(e.player.seeks.last?.seconds,5.95);XCTAssertEqual(actual,0.595)}
 func testSuspendedSeekBeforeTrimUsesStart() {let e=Editor();_=e.seekToNormal(makeValues(left:0.2,right:0.6,move:0.1,suspended:true));XCTAssertEqual(e.player.seeks.last?.seconds,2)}
 func testInvalidSeekDoesNotReachPlayer() {let e=Editor();_=e.seekToNormal(makeValues(left:0.8,right:0.2));XCTAssertTrue(e.player.seeks.isEmpty)}
 func testNonFiniteMoveDoesNotReachPlayer() {let e=Editor();_=e.seekToNormal(makeValues(move:.nan,suspended:true));XCTAssertTrue(e.player.seeks.isEmpty)}
 func testInvalidDurationDoesNotInstallObserverOrPlay() {let e=Editor(duration:0);e.play();XCTAssertEqual(e.player.plays,0);XCTAssertTrue(e.player.observers.isEmpty)}
 func testRepeatPlayRemovesOldObserver() {let e=Editor();e.play();e.play();XCTAssertEqual(e.player.removed,[0]);XCTAssertEqual(e.player.observers.count,2)}
 func testOldObserverCannotMovePlayheadAfterRestart() {let e=Editor();e.play();e.play();let before=e.updates;e.player.observers[0](CMTime(seconds:8,preferredTimescale:1000));XCTAssertEqual(e.updates,before);XCTAssertEqual(e.scrubberValues.with {$0.movePos},0)}
 func testCurrentObserverUpdatesPlayhead() {let e=Editor();e.play();e.player.observers[0](CMTime(seconds:4,preferredTimescale:1000));XCTAssertEqual(e.scrubberValues.with {$0.movePos},0.4)}
 func testNonNumericObserverTimeIsIgnored() {let e=Editor();e.play();let before=e.updates;e.player.observers[0](.indefinite);XCTAssertEqual(e.updates,before)}
 func testHiddenEditorIgnoresQueuedObserver() {let e=Editor();e.play();e.viewWillDisappear(false);let before=e.updates;e.player.observers[0](CMTime(seconds:4,preferredTimescale:1000));XCTAssertEqual(e.updates,before);XCTAssertEqual(e.player.rate,0)}
 func testHiddenEditorCannotRestartFromEndNotification() {let e=Editor();e.play();let callback=NotificationCenter.default.callbacks.last!;e.viewWillDisappear(false);let plays=e.player.plays;callback(0);XCTAssertEqual(e.player.plays,plays);XCTAssertEqual(e.player.rate,0)}
 func testOldEndNotificationCannotRestartNewPlayback() {let e=Editor();e.play();let callback=NotificationCenter.default.callbacks.last!;e.play();let plays=e.player.plays;callback(0);XCTAssertEqual(e.player.plays,plays)}
 func testReappearanceResumesPlaybackWithFreshObserver() {let e=Editor();e.play();e.viewWillDisappear(false);e.viewWillAppear(false);XCTAssertEqual(e.player.rate,1);XCTAssertEqual(e.player.observers.count,2)}
 func testReappearancePreservesPausedState() {let e=Editor(values:makeValues(paused:true));e.viewWillDisappear(false);e.viewWillAppear(false);XCTAssertEqual(e.player.rate,0);XCTAssertEqual(e.player.plays,0)}
 func testRetainedObserverDoesNotRetainEditor() {var e:Editor?=Editor();let player=e!.player;e!.play();weak var weakEditor=e;e=nil;XCTAssertNil(weakEditor);player.observers[0](CMTime(seconds:1,preferredTimescale:1000))}
}
final class InitialValuesTests:XCTestCase {
 func testHalfSecondClipHasValidNormalizedLimits() {let e=Editor(duration:0.5);e.initialize();let v=e.scrubberValues.with {$0};XCTAssertEqual(v.minDist,1);XCTAssertEqual(v.maxDist,1);XCTAssertEqual(v.rightTrim,1)}
 func testFiveSecondClipHasOneSecondMinimumAndFullMaximum() {let e=Editor(duration:5);e.initialize();let v=e.scrubberValues.with {$0};XCTAssertEqual(v.minDist,0.2);XCTAssertEqual(v.maxDist,1);XCTAssertEqual(v.rightTrim,1)}
 func testLongClipHasTenSecondMaximum() {let e=Editor(duration:600);e.initialize();let v=e.scrubberValues.with {$0};XCTAssertEqual(v.minDist,1/600,accuracy:0.000001);XCTAssertEqual(v.maxDist,10/600,accuracy:0.000001);XCTAssertEqual(v.rightTrim,10/600,accuracy:0.000001)}
 func testZeroWidthScrubberDoesNotProduceNaN() {let e=Editor(duration:5);e.genericView.scrubberView.frame.size.width=0;e.initialize();let v=e.scrubberValues.with {$0};XCTAssertTrue(v.minDist.isFinite);XCTAssertEqual(v.minDist,0.2);XCTAssertEqual(v.maxDist,1)}
 func testZeroDurationReportsErrorAndCloses() {let e=Editor(duration:0);e.initialize();XCTAssertTrue(e.closed);XCTAssertEqual(e.state.errors,1)}
 func testSubMillisecondDurationCannotStartInvalidRange() {XCTAssertNil(initialAvatarVideoScrubberValues(duration:0.0001))}
}
func -(lhs:CGPoint,rhs:CGPoint)->CGPoint {CGPoint(x:lhs.x-rhs.x,y:lhs.y-rhs.y)}
final class MouseWindow {var mouseLocationOutsideOfEventStream=CGPoint.zero}
final class Control {var frame=CGRect(x:0,y:0,width:8,height:40);var window:MouseWindow?=MouseWindow()}
final class Drag {
 var values:VideoScrubberValues;var frame:CGRect;let leftTrim=Control();let control=Control();let imageViewsContainer=Control();var changes:[VideoScrubberValues]=[];var handler:((Control)->Void)!;var updateValues:((VideoScrubberValues)->Void)?
 init(_ value:VideoScrubberValues=makeValues(left:0.2,right:0.4),width:CGFloat=108,choose:Bool=false) {values=value;frame=CGRect(x:0,y:0,width:width,height:40);imageViewsContainer.frame.size.width=width-8;var distanceStart:CGPoint? = .zero;let chooseFrame=choose;func possibleDrag(_ value:CGFloat)->Bool {value>=0 && value<=1};updateValues={ [weak self] value in self?.values=value;self?.changes.append(value)};handler=__DRAG__}
 func move(_ x:CGFloat) {control.window?.mouseLocationOutsideOfEventStream=CGPoint(x:x,y:0);handler(control)}
}
final class DragTests:XCTestCase {
 func testMovingPastRightEndPreservesDuration() {let d=Drag();d.move(100);XCTAssertEqual(d.values.leftTrim,0.8,accuracy:0.000001);XCTAssertEqual(d.values.rightTrim,1);XCTAssertEqual(d.values.rightTrim-d.values.leftTrim,0.2,accuracy:0.000001)}
 func testMovingPastLeftEndPreservesDuration() {let d=Drag();d.move(-100);XCTAssertEqual(d.values.leftTrim,0);XCTAssertEqual(d.values.rightTrim,0.2,accuracy:0.000001)}
 func testInteriorDragMovesBothEndsEqually() {let d=Drag();d.move(10);XCTAssertEqual(d.values.leftTrim,0.3,accuracy:0.000001);XCTAssertEqual(d.values.rightTrim,0.5,accuracy:0.000001);XCTAssertTrue(d.values.paused)}
 func testReturningFromBoundaryMovesImmediately() {let d=Drag();d.move(100);d.move(90);XCTAssertEqual(d.values.leftTrim,0.7,accuracy:0.000001);XCTAssertEqual(d.values.rightTrim,0.9,accuracy:0.000001)}
 func testZeroTrackWidthDoesNotMutateRange() {let d=Drag(width:8);d.move(1);XCTAssertTrue(d.changes.isEmpty)}
 func testNegativeTrackWidthDoesNotMutateRange() {let d=Drag(width:4);d.move(1);XCTAssertTrue(d.changes.isEmpty)}
 func testKeyFrameInsideMovedRangeIsPreserved() {let d=Drag(makeValues(left:0.2,right:0.4,key:0.3));d.move(5);XCTAssertEqual(d.values.keyFrame,0.3)}
 func testKeyFrameOutsideMovedRangeIsCleared() {let d=Drag(makeValues(left:0.2,right:0.4,key:0.3));d.move(100);XCTAssertNil(d.values.keyFrame)}
 func testFrameChoosingDoesNotMoveTrimRange() {let d=Drag(makeValues(left:0.2,right:0.4,move:0.25),choose:true);d.move(5);XCTAssertEqual(d.values.leftTrim,0.2);XCTAssertEqual(d.values.rightTrim,0.4);XCTAssertEqual(d.values.movePos,0.3,accuracy:0.000001)}
}
