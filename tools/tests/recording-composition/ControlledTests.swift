import Foundation
import CoreMedia
import SwiftSignalKit
import XCTest

enum MediaType { case video }
final class Track { var timeRange: CMTimeRange; init(_ seconds: Double) {timeRange=CMTimeRange(start:.zero,duration:CMTime(seconds:seconds,preferredTimescale:1000))} }
class AVAsset {
    var duration:CMTime
    var video:Track?
    var insertionFails=false
    init(_ seconds:Double,video:Bool=true) {duration=seconds.isFinite ? CMTime(seconds:seconds,preferredTimescale:1000) : .indefinite;self.video=video ? Track(seconds.isFinite ? seconds : 1):nil}
    func tracks(withMediaType:MediaType)->[Track] {video.map{[$0]} ?? []}
}
var assets:[String:AVAsset]=[:]
final class AVURLAsset:AVAsset {
    init(url:URL) {let source=assets[url.path] ?? AVAsset(0,video:false);super.init(0);duration=source.duration;video=source.video;insertionFails=source.insertionFails}
}
enum InsertError:Error {case failed}
final class AVMutableComposition:AVAsset {
    var inserted:[AVAsset]=[]
    init(){super.init(0,video:false)}
    func insertTimeRange(_ range:CMTimeRange,of asset:AVAsset,at:CMTime)throws {
        if asset.insertionFails {throw InsertError.failed}
        inserted.append(asset);duration=CMTimeAdd(duration,range.duration);video=Track(duration.seconds)
    }
}
__HELPERS__
final class Probe<T> {
    var subscribers:[Subscriber<T,NoError>]=[]
    var starts=0,disposals=0
    var immediate:T?
    var signal:Signal<T,NoError>{Signal{[weak self] s in guard let self else{return EmptyDisposable};starts+=1;subscribers.append(s);if let immediate{s.putNext(immediate)};return ActionDisposable{[weak self] in self?.disposals+=1}}}
    func send(_ value:T){for s in subscribers{s.putNext(value)}}
    func complete(){for s in subscribers{s.putCompletion()}}
}
var exports:[Probe<String?>]=[]
var exportAssets:[AVAsset]=[]
var immediateOutput:String?
func passthroughExport(asset:AVAsset,name:String)->Signal<String?,NoError>{exportAssets.append(asset);let p=Probe<String?>();if let immediateOutput{p.immediate=immediateOutput};exports.append(p);return p.signal}
final class ManualQueue {
    var pending:[()->Void]=[]
    func async(_ f:@escaping()->Void){pending.append(f)}
    func drain(){let old=pending;pending=[];for f in old{f()}}
}
var removed:[String]=[]
func removeFile(at:String){removed.append(at)}
final class Upload {var id:Int64=42;var finished=0;func fileDidChangedSize(_ value:Bool){if value{finished+=1}}}
enum Status {case stoppingRecording, recording, failed, finishRecording(path:String,duration:Int,id:Int64?,thumb:Int?)}
final class VideoRecorderPipeline {
    static let queue=ManualQueue()
    var segments:[URL]=[URL(fileURLWithPath:"/a.mp4"),URL(fileURLWithPath:"/b.mp4")]
    var isDiscarded=false
    var composedFile:String?="/old-preview.mp4"
    var compositionRequestId=UUID()
    let composeDisposable=MetaDisposable()
    var completedDuration:Double=10
    let url=URL(fileURLWithPath:"/a.mp4")
    var sentPath:String?
    var resultDuration=0
    var liveUploading:Upload?=Upload()
    var thumbnail:Int?
    var status=Status.stoppingRecording
    func removeUnlessSent(_ path:String){if path != sentPath{removeFile(at:path)}}
    __METHODS__
    deinit{composeDisposable.dispose()}
}
final class CompositionTests:XCTestCase {
    override func setUp(){assets=["/a.mp4":AVAsset(2),"/b.mp4":AVAsset(3),"/joined.mp4":AVAsset(5),"/old-preview.mp4":AVAsset(4)];exports=[];exportAssets=[];removed=[];immediateOutput=nil;VideoRecorderPipeline.queue.pending=[]}
    func testEmptySegmentsFailWithoutExport(){let p=VideoRecorderPipeline();p.segments=[];var called=0;var result:(String,Double)?;p.composedRecording{called+=1;result=$0};if let e=exports.first{e.send(nil);VideoRecorderPipeline.queue.drain()};XCTAssertEqual(called,1);XCTAssertNil(result);XCTAssertTrue(exports.isEmpty)}
    func testSingleSegmentUsesActualDuration(){let p=VideoRecorderPipeline();p.segments=[p.url];var result:(String,Double)?;p.composedRecording{result=$0};XCTAssertEqual(result?.0,"/a.mp4");XCTAssertEqual(result?.1,2)}
    func testMissingSingleSegmentIsFailure(){let p=VideoRecorderPipeline();p.segments=[URL(fileURLWithPath:"/missing.mp4")];var result:(String,Double)?;p.composedRecording{result=$0};XCTAssertNil(result)}
    func testInvalidSingleDurationIsFailure(){let p=VideoRecorderPipeline();p.segments=[p.url];assets["/a.mp4"]=AVAsset(.infinity);var result:(String,Double)?;p.composedRecording{result=$0};XCTAssertNil(result)}
    func testMissingSegmentIsNotSilentlySkipped(){let p=VideoRecorderPipeline();assets.removeValue(forKey:"/b.mp4");var calls=0;p.composedRecording{XCTAssertNil($0);calls+=1};if let e=exports.first{e.send("/joined.mp4");VideoRecorderPipeline.queue.drain()};XCTAssertTrue(exports.isEmpty);XCTAssertEqual(calls,1)}
    func testInsertionErrorIsNotSilentlySkipped(){let p=VideoRecorderPipeline();assets["/b.mp4"]!.insertionFails=true;var calls=0;p.composedRecording{XCTAssertNil($0);calls+=1};if let e=exports.first{e.send("/joined.mp4");VideoRecorderPipeline.queue.drain()};XCTAssertTrue(exports.isEmpty);XCTAssertEqual(calls,1)}
    func testFailedExportDoesNotSubstituteLastSegment(){let p=VideoRecorderPipeline();var result:(String,Double)?;p.composedRecording{result=$0};exports[0].send(nil);VideoRecorderPipeline.queue.drain();XCTAssertNil(result);XCTAssertEqual(p.segments.count,2);XCTAssertFalse(removed.contains("/a.mp4"));XCTAssertFalse(removed.contains("/b.mp4"))}
    func testFailedJoinPreservesPriorPreview(){let p=VideoRecorderPipeline();p.composedRecording{_ in};exports[0].send(nil);VideoRecorderPipeline.queue.drain();XCTAssertEqual(p.composedFile,"/old-preview.mp4");XCTAssertFalse(removed.contains("/old-preview.mp4"))}
    func testEmptyExporterCompletionIsExplicitFailure(){let p=VideoRecorderPipeline();var calls=0;p.composedRecording{XCTAssertNil($0);calls+=1};exports[0].complete();VideoRecorderPipeline.queue.drain();XCTAssertEqual(calls,1)}
    func testUnreadableOutputFailsAndIsRemoved(){let p=VideoRecorderPipeline();var result:(String,Double)?;p.composedRecording{result=$0};exports[0].send("/missing.mp4");VideoRecorderPipeline.queue.drain();XCTAssertNil(result);XCTAssertTrue(removed.contains("/missing.mp4"));XCTAssertEqual(p.composedFile,"/old-preview.mp4")}
    func testSuccessfulJoinUsesActualOutputDuration(){let p=VideoRecorderPipeline();assets["/joined.mp4"]=AVAsset(4.95);var result:(String,Double)?;p.composedRecording{result=$0};exports[0].send("/joined.mp4");VideoRecorderPipeline.queue.drain();XCTAssertEqual(result?.0,"/joined.mp4");XCTAssertEqual(result?.1,4.95);XCTAssertEqual(p.composedFile,"/joined.mp4");XCTAssertTrue(removed.contains("/old-preview.mp4"))}
    func testSuccessfulJoinContainsEverySegmentInOrder(){let p=VideoRecorderPipeline();p.composedRecording{_ in};let composition=exportAssets.first as? AVMutableComposition;XCTAssertEqual(composition?.inserted.map{$0.duration.seconds},[2,3])}
    func testOnlyFirstExportResultIsAccepted(){let p=VideoRecorderPipeline();var calls=0;p.composedRecording{_ in calls+=1};exports[0].send("/joined.mp4");exports[0].send("/joined.mp4");VideoRecorderPipeline.queue.drain();XCTAssertEqual(calls,1)}
    func testDiscardBeforeCompositionDoesNotStartExport(){let p=VideoRecorderPipeline();p.isDiscarded=true;var result:(String,Double)?;p.composedRecording{result=$0};XCTAssertNil(result);XCTAssertTrue(exports.isEmpty)}
    func testDiscardBeforeQueuedResultDeletesUnclaimedOutput(){let p=VideoRecorderPipeline();var result:(String,Double)?;p.composedRecording{result=$0};exports[0].send("/joined.mp4");p.isDiscarded=true;VideoRecorderPipeline.queue.drain();XCTAssertNil(result);XCTAssertTrue(removed.contains("/joined.mp4"))}
    func testChangedSegmentsRejectQueuedOutput(){let p=VideoRecorderPipeline();var result:(String,Double)?;p.composedRecording{result=$0};exports[0].send("/joined.mp4");p.segments=[p.url];VideoRecorderPipeline.queue.drain();XCTAssertNil(result);XCTAssertTrue(removed.contains("/joined.mp4"))}
    func testNewerJoinCannotBeOverwrittenByQueuedOldResult(){let p=VideoRecorderPipeline();var oldCalls=0,newCalls=0;p.composedRecording{_ in oldCalls+=1};exports[0].send("/joined.mp4");p.composedRecording{_ in newCalls+=1};VideoRecorderPipeline.queue.drain();XCTAssertEqual(oldCalls,0);XCTAssertEqual(newCalls,0);XCTAssertTrue(removed.contains("/joined.mp4"));XCTAssertEqual(p.composedFile,"/old-preview.mp4")}
    func testClearedPreviewInvalidatesQueuedJoin(){let p=VideoRecorderPipeline();var calls=0;p.composedRecording{_ in calls+=1};exports[0].send("/joined.mp4");p.clearComposedURL();VideoRecorderPipeline.queue.drain();XCTAssertEqual(calls,0);XCTAssertNil(p.composedFile);XCTAssertTrue(removed.contains("/joined.mp4"))}
    func testReleasedPipelineRemovesQueuedResult(){var p:VideoRecorderPipeline?=VideoRecorderPipeline();weak var weakPipeline=p;p!.composedRecording{_ in XCTFail("released owner")};exports[0].send("/joined.mp4");p=nil;XCTAssertNil(weakPipeline);VideoRecorderPipeline.queue.drain();XCTAssertTrue(removed.contains("/joined.mp4"))}
    func testFinishFailureNeverPublishesLastSegment(){let p=VideoRecorderPipeline();p.finishWithComposedResult();exports[0].send(nil);VideoRecorderPipeline.queue.drain();if case .failed=p.status{}else{XCTFail("Expected failure")};XCTAssertNil(p.sentPath)}
    func testFinishUsesRealDurationAndNoLiveUploadForJoinedFile(){let p=VideoRecorderPipeline();p.finishWithComposedResult();exports[0].send("/joined.mp4");VideoRecorderPipeline.queue.drain();guard case let .finishRecording(path,duration,id,_)=p.status else{return XCTFail("No result")};XCTAssertEqual(path,"/joined.mp4");XCTAssertEqual(duration,5);XCTAssertNil(id);XCTAssertEqual(p.sentPath,"/joined.mp4")}
    func testFinishOriginalRetainsUploadIdentity(){let p=VideoRecorderPipeline();p.segments=[p.url];p.finishWithComposedResult();guard case let .finishRecording(_,duration,id,_)=p.status else{return XCTFail("No result")};XCTAssertEqual(duration,2);XCTAssertEqual(id,42);XCTAssertEqual(p.liveUploading?.finished,1)}
    func testDiscardedFinishDoesNotPublishSuccess(){let p=VideoRecorderPipeline();p.finishWithComposedResult();exports[0].send("/joined.mp4");p.isDiscarded=true;VideoRecorderPipeline.queue.drain();if case .finishRecording=p.status{XCTFail("Discarded result published")};XCTAssertNil(p.sentPath)}
    func testResumedFinishCannotReplaceRecordingStatus(){let p=VideoRecorderPipeline();p.finishWithComposedResult();exports[0].send("/joined.mp4");p.status = .recording;VideoRecorderPipeline.queue.drain();if case .recording=p.status{}else{XCTFail("Old finish replaced new status")};XCTAssertNil(p.sentPath)}
    func testFinishCallbackDoesNotRetainPipeline(){var p:VideoRecorderPipeline?=VideoRecorderPipeline();weak var weakPipeline=p;p!.finishWithComposedResult();p=nil;XCTAssertNil(weakPipeline)}
}

extension String {
    var duration: Double { assets[self]?.duration.seconds ?? .nan }
    func takePath() -> String? { self }
    func discard() { removeFile(at: self) }
}
