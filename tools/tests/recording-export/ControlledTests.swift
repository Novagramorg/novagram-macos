import Foundation
import CoreMedia
import SwiftSignalKit
import XCTest

class AVAsset { let duration:CMTime; init(_ seconds:Double=10){duration=CMTime(seconds:seconds,preferredTimescale:60000)} }
final class AVURLAsset:AVAsset {let url:URL;init(url:URL){self.url=url;super.init(10)}}
var invalidOutput=false
func recordingVideoDuration(_ asset:AVAsset)->Double? {
    if let asset=asset as? AVURLAsset,asset.url.path != "/source.mp4" {
        guard !invalidOutput,FileManager.default.fileExists(atPath:asset.url.path) else{return nil}
        return 5.95
    }
    return asset.duration.seconds > 0 ? asset.duration.seconds : nil
}
enum FileType {case mp4,mov}
enum Status {case unknown,completed,failed,cancelled}
let AVAssetExportPresetPassthrough="passthrough"
final class AVAssetExportSession {
    static var sessions:[AVAssetExportSession]=[]
    static var unavailable=false,unsupported=false
    var outputURL:URL?,outputFileType:FileType?,shouldOptimizeForNetworkUse=false
    var timeRange:CMTimeRange?
    var status=Status.unknown,error:Error?
    var completion:(()->Void)?
    var starts=0,cancels=0
    var supportedFileTypes:[FileType]{Self.unsupported ? [.mov]:[.mp4]}
    init?(asset:AVAsset,presetName:String){if Self.unavailable{return nil};Self.sessions.append(self)}
    func exportAsynchronously(completion:@escaping()->Void){starts+=1;self.completion=completion}
    func cancelExport(){cancels+=1}
    func finish(_ status:Status = .completed,write:Bool=true){self.status=status;if write,let outputURL{try! Data([1,2,3]).write(to:outputURL)};completion?()}
}
__SOURCE__

class ExportCase:XCTestCase {
    var subscriptions:[Disposable]=[]
    override func setUp(){invalidOutput=false;AVAssetExportSession.sessions=[];AVAssetExportSession.unavailable=false;AVAssetExportSession.unsupported=false}
    override func tearDown(){for d in subscriptions{d.dispose()};drain();for s in AVAssetExportSession.sessions{if let url=s.outputURL{try? FileManager.default.removeItem(at:url)};s.completion=nil};AVAssetExportSession.sessions=[]}
    func drain(){RecordingVideoExportOperation.queue.sync{};RecordingVideoExportOperation.queue.sync{}}
    func start(_ receive:@escaping(RecordingVideoExportResult?)->Void={_ in})->Disposable{let d=exportTrimmedVideo(path:"/source.mp4",range:2..<8).start(next:receive);subscriptions.append(d);drain();return d}
    func session()->AVAssetExportSession{AVAssetExportSession.sessions.last!}
    func exists(_ session:AVAssetExportSession)->Bool{FileManager.default.fileExists(atPath:session.outputURL!.path)}
}
final class ExportTests:ExportCase {
    func testConstructionDoesNotStartExport(){_=exportTrimmedVideo(path:"/source.mp4",range:2..<8);drain();XCTAssertTrue(AVAssetExportSession.sessions.isEmpty)}
    func testInvalidBoundsFailBeforeSessionCreation(){for range in [-1.0..<2,2.0..<2,2.0..<11,0.0..<Double.infinity]{var calls=0;let d=exportTrimmedVideo(path:"/source.mp4",range:range).start(next:{XCTAssertNil($0);calls+=1});subscriptions.append(d);drain();XCTAssertEqual(calls,1)};XCTAssertTrue(AVAssetExportSession.sessions.isEmpty)}
    func testUnrepresentableTinyRangeFails(){var calls=0;let d=exportTrimmedVideo(path:"/source.mp4",range:0..<0.0000000001).start(next:{XCTAssertNil($0);calls+=1});subscriptions.append(d);drain();XCTAssertEqual(calls,1);XCTAssertTrue(AVAssetExportSession.sessions.isEmpty)}
    func testSessionCreationFailureCompletes(){AVAssetExportSession.unavailable=true;var calls=0;_=start{XCTAssertNil($0);calls+=1};XCTAssertEqual(calls,1)}
    func testUnsupportedMP4NeverStarts(){AVAssetExportSession.unsupported=true;var calls=0;_=start{XCTAssertNil($0);calls+=1};XCTAssertEqual(calls,1);XCTAssertEqual(session().starts,0)}
    func testValidTrimUsesRequestedBounds(){_=start();XCTAssertEqual(session().timeRange?.start.seconds,2);XCTAssertEqual(session().timeRange?.duration.seconds,6);XCTAssertEqual(session().outputFileType,.mp4)}
    func testFullExportDoesNotSetTrimRange(){let d=passthroughExport(asset:AVAsset(),name:"join").start();subscriptions.append(d);drain();XCTAssertNil(session().timeRange)}
    func testFailedExportRemovesPartialFile(){var calls=0;_=start{XCTAssertNil($0);calls+=1};let s=session();s.finish(.failed);drain();XCTAssertEqual(calls,1);XCTAssertFalse(exists(s))}
    func testCancelledStatusRemovesPartialFile(){var calls=0;_=start{XCTAssertNil($0);calls+=1};let s=session();s.finish(.cancelled);drain();XCTAssertEqual(calls,1);XCTAssertFalse(exists(s))}
    func testCompletedWithoutReadableFileFails(){var calls=0;_=start{XCTAssertNil($0);calls+=1};session().finish(write:false);drain();XCTAssertEqual(calls,1)}
    func testInvalidOutputMetadataRemovesFile(){invalidOutput=true;var calls=0;_=start{XCTAssertNil($0);calls+=1};let s=session();s.finish();drain();XCTAssertEqual(calls,1);XCTAssertFalse(exists(s))}
    func testErrorEvenWithCompletedStatusFails(){var calls=0;_=start{XCTAssertNil($0);calls+=1};let s=session();s.error=NSError(domain:"test",code:1);s.finish();drain();XCTAssertEqual(calls,1);XCTAssertFalse(exists(s))}
    func testIgnoredSuccessfulResultRemovesFile(){_=start();let s=session();s.finish();drain();XCTAssertFalse(exists(s))}
    func testHeldResultOwnsFileUntilReleased(){var result:RecordingVideoExportResult?;_=start{result=$0};let s=session();s.finish();drain();XCTAssertEqual(result?.duration,5.95);XCTAssertTrue(exists(s));result=nil;XCTAssertFalse(exists(s))}
    func testClaimedResultSurvivesSubscriptionDisposal(){var path:String?;let d=start{path=$0?.takePath()};let s=session();s.finish();drain();d.dispose();drain();XCTAssertEqual(path,s.outputURL?.path);XCTAssertTrue(exists(s))}
    func testResultCanOnlyBeClaimedOnce(){var result:RecordingVideoExportResult?;_=start{result=$0};let s=session();s.finish();drain();XCTAssertNotNil(result?.takePath());XCTAssertNil(result?.takePath());result?.discard();XCTAssertTrue(exists(s))}
    func testDiscardedResultCannotBeClaimed(){var result:RecordingVideoExportResult?;_=start{result=$0};let s=session();s.finish();drain();result?.discard();XCTAssertNil(result?.takePath());XCTAssertFalse(exists(s))}
    func testDisposeBeforeStartDoesNotCreateSession(){let done=expectation(description:"cancel before queue start");RecordingVideoExportOperation.queue.async{let d=exportTrimmedVideo(path:"/source.mp4",range:2..<8).start(next:{_ in XCTFail("Cancelled result")});d.dispose();done.fulfill()};wait(for:[done],timeout:2);drain();XCTAssertTrue(AVAssetExportSession.sessions.isEmpty)}
    func testDisposeDuringExportCancelsAndDeletesPartial(){var calls=0;let d=start{_ in calls+=1};let s=session();try! Data([1]).write(to:s.outputURL!);d.dispose();drain();XCTAssertGreaterThan(s.cancels,0);XCTAssertFalse(exists(s));XCTAssertEqual(calls,0)}
    func testLateCompletionAfterCancelDeletesRecreatedFile(){var calls=0;let d=start{_ in calls+=1};let s=session();d.dispose();drain();s.finish();drain();XCTAssertFalse(exists(s));XCTAssertEqual(calls,0)}
    func testCancelWhileCompletionIsQueuedDoesNotTransferFile(){var calls=0;let d=start{_ in calls+=1};let s=session();let done=expectation(description:"queued completion");RecordingVideoExportOperation.queue.async{s.finish();d.dispose();done.fulfill()};wait(for:[done],timeout:2);drain();XCTAssertFalse(exists(s));XCTAssertEqual(calls,0)}
    func testQueuedMainDeliveryCancelledBeforeConsumptionRemovesFile(){var calls=0;let d=(exportTrimmedVideo(path:"/source.mp4",range:2..<8) |> deliverOnMainQueue).start(next:{_ in calls+=1});subscriptions.append(d);drain();let s=session();RecordingVideoExportOperation.queue.sync{s.finish()};drain();d.dispose();let done=expectation(description:"main delivery drained");DispatchQueue.main.async{done.fulfill()};wait(for:[done],timeout:2);drain();XCTAssertEqual(calls,0);XCTAssertFalse(exists(s))}
    func testFailureCompletesOnceDespiteDuplicateCallback(){var calls=0;_=start{_ in calls+=1};let s=session();s.finish(.failed);drain();s.finish(.failed);drain();XCTAssertEqual(calls,1);XCTAssertFalse(exists(s))}
    func testSuccessCompletesOnceDespiteDuplicateCallback(){var calls=0;var path:String?;_=start{calls+=1;path=$0?.takePath()};let s=session();s.finish();drain();s.completion?();drain();XCTAssertEqual(calls,1);XCTAssertNotNil(path);XCTAssertTrue(exists(s))}
    func testActiveOperationDoesNotRetainCompletedSession(){_=start();weak var weakSession=session();session().finish();drain();for s in AVAssetExportSession.sessions{s.completion=nil};AVAssetExportSession.sessions=[];XCTAssertNil(weakSession)}
}

var removedSources:[String]=[]
func removeFile(at path:String){removedSources.append(path);try? FileManager.default.removeItem(atPath:path)}
__TRIM_HELPER__
struct ChatRecordingPreviewData {let path:String;let duration:Double;let waveform:Int?;let thumb:Int?}
enum VideoCameraRecordingStatus {case paused(info:ChatRecordingPreviewData)}
final class ManualQueue {
 var tasks:[()->Void]=[]
 func async(_ f:@escaping()->Void){tasks.append(f)}
 func drain(){let tasks=self.tasks;self.tasks=[];for task in tasks{task()}}
}
final class VideoRecorderPipeline {
 static let queue=ManualQueue()
 var isPaused=true,isDiscarded=false
 var removals=0
 var derivedFiles:[String]=[],segments:[URL]=[]
 var completedDuration:Double=10,lastSegmentDuration:Double=0
 var liveUploading:Int?=1,thumbnail:Int?
 var status=VideoCameraRecordingStatus.paused(info:ChatRecordingPreviewData(path:"/source.mp4",duration:10,waveform:nil,thumb:nil))
 func composedRecording(_ callback:@escaping((String,Double)?)->Void){callback(("/source.mp4",10))}
 func removeSegmentFiles(){removals+=1}
 __APPLY_TRIM__
}
final class ConsumerTests:ExportCase {
 override func setUp(){super.setUp();removedSources=[];VideoRecorderPipeline.queue.tasks=[]}
 func mainDrain(){let done=expectation(description:"main");DispatchQueue.main.async{done.fulfill()};wait(for:[done],timeout:2)}
 func testTrimHelperCancellationBeforeMainPreservesSourceAndDeletesOutput(){var calls=0;let d=trimmedVideoFile("/source.mp4",trimRange:2..<8).start(next:{_ in calls+=1});subscriptions.append(d);drain();let s=session();s.finish();drain();XCTAssertTrue(removedSources.isEmpty);d.dispose();mainDrain();drain();XCTAssertEqual(calls,0);XCTAssertTrue(removedSources.isEmpty);XCTAssertFalse(exists(s))}
 func testTrimHelperClaimsOnlyOnMainConsumption(){var result:(String,Double)?;let d=trimmedVideoFile("/source.mp4",trimRange:2..<8).start(next:{result=$0});subscriptions.append(d);drain();let s=session();s.finish();drain();XCTAssertTrue(removedSources.isEmpty);mainDrain();XCTAssertEqual(removedSources,["/source.mp4"]);XCTAssertEqual(result?.1,5.95);XCTAssertTrue(exists(s))}
 func testTrimHelperFailedExportRetainsSource(){var calls=0;let d=trimmedVideoFile("/source.mp4",trimRange:2..<8).start(next:{XCTAssertNil($0);calls+=1});subscriptions.append(d);drain();let s=session();s.finish(.failed);drain();mainDrain();XCTAssertEqual(calls,1);XCTAssertTrue(removedSources.isEmpty);XCTAssertFalse(exists(s))}
 func trim(_ p:VideoRecorderPipeline,_ next:@escaping(Bool)->Void={_ in})->Disposable{let d=p.applyTrim(2..<8).start(next:next);subscriptions.append(d);VideoRecorderPipeline.queue.drain();drain();return d}
 func testPipelineCancellationBeforeCommitDeletesOwnedOutput(){let p=VideoRecorderPipeline();let d=trim(p);let s=session();s.finish();drain();d.dispose();VideoRecorderPipeline.queue.drain();XCTAssertFalse(exists(s));XCTAssertEqual(p.removals,0);XCTAssertEqual(p.completedDuration,10)}
 func testPipelineDiscardBeforeCommitDeletesOwnedOutput(){let p=VideoRecorderPipeline();_=trim(p);let s=session();s.finish();drain();p.isDiscarded=true;VideoRecorderPipeline.queue.drain();XCTAssertFalse(exists(s));XCTAssertEqual(p.removals,0)}
 func testPipelineResumeBeforeCommitDeletesOwnedOutput(){let p=VideoRecorderPipeline();_=trim(p);let s=session();s.finish();drain();p.isPaused=false;VideoRecorderPipeline.queue.drain();XCTAssertFalse(exists(s));XCTAssertEqual(p.removals,0)}
 func testPipelineCommitClaimsFileAndPublishesActualDuration(){let p=VideoRecorderPipeline();var results:[Bool]=[];_=trim(p){results.append($0)};let s=session();s.finish();drain();VideoRecorderPipeline.queue.drain();XCTAssertEqual(results,[true]);XCTAssertEqual(p.completedDuration,5.95);XCTAssertEqual(p.removals,1);XCTAssertEqual(p.segments,[s.outputURL!]);XCTAssertTrue(exists(s));if case let .paused(info)=p.status{XCTAssertEqual(info.duration,5.95)}}
 func testPipelineFailureDoesNotReplaceSource(){let p=VideoRecorderPipeline();var results:[Bool]=[];_=trim(p){results.append($0)};let s=session();s.finish(.failed);drain();VideoRecorderPipeline.queue.drain();XCTAssertEqual(results,[false]);XCTAssertEqual(p.removals,0);XCTAssertEqual(p.completedDuration,10)}
}
