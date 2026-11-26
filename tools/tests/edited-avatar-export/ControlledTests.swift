import Foundation
import CoreMedia
import SwiftSignalKit
import XCTest

typealias CFURL=URL
typealias CFDictionary=[String:Double]
let kUTTypeJPEG="jpeg",kCGImageDestinationLossyCompressionQuality="quality"
final class State {
 static var sessionFails=false,unsupportedType=false,imageFails=false,destinationFails=false,finalizeFails=false,synchronous=false
 static var sessions:[AVAssetExportSession]=[];static var thumbnailTimes:[CMTime]=[];static var paths:[String]=[];static var durations:[String:Double]=[:]
 static func reset() {for path in paths {try? FileManager.default.removeItem(atPath:path)};sessionFails=false;unsupportedType=false;imageFails=false;destinationFails=false;finalizeFails=false;synchronous=false;sessions=[];thumbnailTimes=[];paths=[];durations=[:]}
}
enum AVFileType {case mp4,other}
enum AVMediaType {case video}
class AVComposition {var duration=CMTime(seconds:10,preferredTimescale:1000)}
final class AVVideoComposition {}
final class AVURLAsset {let url:URL;init(url:URL) {self.url=url};var duration:CMTime {CMTime(seconds:State.durations[url.path] ?? 0,preferredTimescale:1000)};func tracks(withMediaType:AVMediaType)->[Int] {FileManager.default.fileExists(atPath:url.path) ? [1]:[]}}
enum Failure:Error {case failed}
final class AVAssetImageGenerator {var maximumSize=CGSize.zero;var appliesPreferredTrackTransform=false;var requestedTimeToleranceBefore=CMTime.zero;var requestedTimeToleranceAfter=CMTime.zero;var videoComposition:AVVideoComposition?;init(asset:AVComposition) {};func copyCGImage(at time:CMTime,actualTime:UnsafeMutablePointer<CMTime>?)throws ->Int {State.thumbnailTimes.append(time);if State.imageFails {throw Failure.failed};return 1}}
final class Destination {let path:String;init(_ path:String) {self.path=path}}
func CGImageDestinationCreateWithURL(_ url:CFURL,_ type:String,_ count:Int,_ options:CFDictionary?)->Destination? {State.paths.append(url.path);return State.destinationFails ? nil:Destination(url.path)}
func CGImageDestinationAddImage(_ destination:Destination,_ image:Int,_ options:CFDictionary?) {}
func CGImageDestinationFinalize(_ destination:Destination)->Bool {try? Data([1]).write(to:URL(fileURLWithPath:destination.path));return !State.finalizeFails}
final class AVAssetExportSession {
 enum Status {case unknown,exporting,completed,failed,cancelled}
 var outputFileType:AVFileType?;var shouldOptimizeForNetworkUse=false;var outputURL:URL? {didSet {if let outputURL {State.paths.append(outputURL.path)}}};var videoComposition:AVVideoComposition?;var timeRange=CMTimeRange.zero;var fileLengthLimit:Int64=0;var progress:Float=0;var status=Status.unknown;var error:Error?;var completion:(()->Void)?;var starts=0,cancels=0
 var supportedFileTypes:[AVFileType] {State.unsupportedType ? [.other]:[.mp4]}
 init?(asset:AVComposition,presetName:String) {if State.sessionFails {return nil};State.sessions.append(self)}
 func exportAsynchronously(completionHandler:@escaping()->Void) {starts+=1;status = .exporting;completion=completionHandler;if State.synchronous {finish()}}
 func finish(_ status:Status = .completed,duration:Double?=nil,write:Bool=true) {self.status=status;if let url=outputURL,write {try? Data([1,2,3]).write(to:url);State.durations[url.path]=duration ?? timeRange.duration.seconds};let completion=self.completion;self.completion=nil;completion?()}
 func cancelExport() {cancels+=1;status = .cancelled}
}
__SOURCE__
final class ControlledTests:XCTestCase {
 var disposables:[Disposable]=[]
 override func setUp() {EditedAvatarVideoExport.queue.sync {State.reset()}}
 override func tearDown() {disposables.forEach {$0.dispose()};flush();EditedAvatarVideoExport.queue.sync {State.reset()}}
 func flush() {EditedAvatarVideoExport.queue.sync {}}
 func start(left:Double=0.2,right:Double=0.8,key:Double?=0.5)->(()->[VideoAvatarGeneratorState]) {var values:[VideoAvatarGeneratorState]=[];EditedAvatarVideoExport.queue.sync {disposables.append(generateEditedAvatarVideo(AVComposition(),composition:AVVideoComposition(),quality:"test",leftTrim:left,rightTrim:right,keyFrame:key).start(next:{values.append($0)}))};flush();return {values}}
 func failures(_ values:[VideoAvatarGeneratorState])->Int {values.filter {if case .error=$0 {return true};return false}.count}
 func successes(_ values:[VideoAvatarGeneratorState])->[(String,String,Double?)] {values.compactMap {if case let .complete(thumb,video,key)=$0 {return (thumb,video,key)};return nil}}
 func testMissingSessionTerminatesWithoutCrash() {State.sessionFails=true;let values=start();XCTAssertEqual(values(),[.error]);XCTAssertTrue(State.thumbnailTimes.isEmpty)}
 func testUnsupportedFileTypeTerminatesBeforeThumbnail() {State.unsupportedType=true;let values=start();XCTAssertEqual(values(),[.error]);XCTAssertTrue(State.thumbnailTimes.isEmpty)}
 func testThumbnailDecodeFailureTerminatesWithoutExport() {State.imageFails=true;let values=start();XCTAssertEqual(values(),[.error]);XCTAssertEqual(State.sessions[0].starts,0);XCTAssertFalse(State.paths.contains {FileManager.default.fileExists(atPath:$0)})}
 func testThumbnailDestinationFailureTerminates() {State.destinationFails=true;let values=start();XCTAssertEqual(values(),[.error]);XCTAssertEqual(State.sessions[0].starts,0)}
 func testThumbnailFinalizeFailureCleansPartialFile() {State.finalizeFails=true;let values=start();XCTAssertEqual(values(),[.error]);XCTAssertFalse(State.paths.contains {FileManager.default.fileExists(atPath:$0)})}
 func testInvalidTrimDoesNotCreateSession() {let values=start(left:0.9,right:0.1);XCTAssertEqual(values(),[.error]);XCTAssertTrue(State.sessions.isEmpty)}
 func testSuccessUsesRelativeKeyFrameAndPreservesFilesAfterDisposal() throws {let values=start();EditedAvatarVideoExport.queue.sync {State.sessions[0].finish()};flush();let result=try XCTUnwrap(successes(values()).first);XCTAssertEqual(result.2,3);XCTAssertEqual(State.thumbnailTimes.first?.seconds,5);disposables[0].dispose();flush();XCTAssertTrue(FileManager.default.fileExists(atPath:result.0));XCTAssertTrue(FileManager.default.fileExists(atPath:result.1));XCTAssertEqual(failures(values()),0)}
 func testAbsentKeyFrameStaysNil() {let values=start(key:nil);EditedAvatarVideoExport.queue.sync {State.sessions[0].finish()};flush();XCTAssertEqual(successes(values()).count,1);XCTAssertNil(successes(values()).first?.2);XCTAssertEqual(State.thumbnailTimes.first?.seconds,2)}
 func testKeyFrameClampsToActualOutputDuration() {let values=start(key:0.8);EditedAvatarVideoExport.queue.sync {State.sessions[0].finish(duration:4)};flush();XCTAssertEqual(successes(values()).first?.2,3.95)}
 func testCompletedStatusWithoutReadableOutputIsFailure() {let values=start();EditedAvatarVideoExport.queue.sync {State.sessions[0].finish(write:false)};flush();XCTAssertEqual(failures(values()),1);XCTAssertTrue(successes(values()).isEmpty);XCTAssertFalse(State.paths.contains {FileManager.default.fileExists(atPath:$0)})}
 func testCompletedStatusWithErrorIsFailure() {let values=start();EditedAvatarVideoExport.queue.sync {State.sessions[0].error=Failure.failed;State.sessions[0].finish()};flush();XCTAssertEqual(failures(values()),1);XCTAssertTrue(successes(values()).isEmpty)}
 func testFailedExportDeletesThumbnailAndPartialVideo() {let values=start();EditedAvatarVideoExport.queue.sync {State.sessions[0].finish(.failed)};flush();XCTAssertEqual(failures(values()),1);XCTAssertFalse(State.paths.contains {FileManager.default.fileExists(atPath:$0)})}
 func testCancellationDeletesPendingThumbnail() {let values=start();XCTAssertTrue(State.paths.contains {FileManager.default.fileExists(atPath:$0)});disposables[0].dispose();flush();XCTAssertTrue(successes(values()).isEmpty);XCTAssertEqual(State.sessions[0].cancels,1);XCTAssertFalse(State.paths.contains {FileManager.default.fileExists(atPath:$0)})}
 func testLateCompletionAfterCancellationDeletesRecreatedOutput() {let values=start();disposables[0].dispose();flush();EditedAvatarVideoExport.queue.sync {State.sessions[0].finish()};flush();XCTAssertTrue(successes(values()).isEmpty);XCTAssertFalse(State.paths.contains {FileManager.default.fileExists(atPath:$0)})}
 func testSynchronousCompletionDoesNotRepeatTerminalEvent() {State.synchronous=true;let values=start();flush();XCTAssertEqual(successes(values()).count,1);XCTAssertEqual(failures(values()),0)}
 func testCancellationFromStartEventPreventsExport() {let disposable=MetaDisposable();var values:[VideoAvatarGeneratorState]=[];EditedAvatarVideoExport.queue.sync {disposable.set(generateEditedAvatarVideo(AVComposition(),composition:AVVideoComposition(),quality:"test",leftTrim:0,rightTrim:1,keyFrame:nil).start(next:{values.append($0);if case .start=$0 {disposable.dispose()}}))};flush();flush();XCTAssertEqual(State.sessions[0].starts,0);XCTAssertTrue(successes(values).isEmpty);XCTAssertFalse(State.paths.contains {FileManager.default.fileExists(atPath:$0)})}
 func testCancellationBeforeQueuedStartAvoidsSession() {EditedAvatarVideoExport.queue.sync {let d=generateEditedAvatarVideo(AVComposition(),composition:AVVideoComposition(),quality:"test",leftTrim:0,rightTrim:1,keyFrame:nil).start(next:{_ in XCTFail()});d.dispose()};flush();XCTAssertTrue(State.sessions.isEmpty)}
 func testSeparateSubscriptionsDoNotCancelEachOther() {let first=start(),second=start();disposables[0].dispose();flush();EditedAvatarVideoExport.queue.sync {State.sessions[1].finish()};flush();XCTAssertTrue(successes(first()).isEmpty);XCTAssertEqual(successes(second()).count,1)}
 func testOwnerReleaseCancelsAndCleansFilesEvenWithRetainedCompletion() {var operation:EditedAvatarVideoExport?=EditedAvatarVideoExport(subscriber:Subscriber(next:{_ in}));weak var weakOperation=operation;EditedAvatarVideoExport.queue.sync {operation!.start(asset:AVComposition(),composition:AVVideoComposition(),quality:"test",range:EditedAvatarVideoRange(duration:10,leftTrim:0,rightTrim:1,keyFrame:nil)!);operation=nil};XCTAssertNil(weakOperation);XCTAssertEqual(State.sessions[0].cancels,1);XCTAssertFalse(State.paths.contains {FileManager.default.fileExists(atPath:$0)});EditedAvatarVideoExport.queue.sync {State.sessions[0].finish()};flush();XCTAssertFalse(State.paths.contains {FileManager.default.fileExists(atPath:$0)})}
 func testProgressIsClampedAndStopsOnCancellation() {let progress=expectation(description:"progress");var values:[Float]=[];var received=false;EditedAvatarVideoExport.queue.sync {disposables.append(generateEditedAvatarVideo(AVComposition(),composition:AVVideoComposition(),quality:"test",leftTrim:0,rightTrim:1,keyFrame:nil).start(next:{if case let .progress(value)=$0 {values.append(value);if !received {received=true;progress.fulfill()}}}))};flush();EditedAvatarVideoExport.queue.sync {State.sessions[0].progress=2};wait(for:[progress],timeout:2);disposables[0].dispose();flush();XCTAssertEqual(values.first,1);let count=values.count;let after=expectation(description:"no late progress");DispatchQueue.main.asyncAfter(deadline:.now()+0.12) {after.fulfill()};wait(for:[after],timeout:2);flush();XCTAssertEqual(values.count,count)}
 func testNonFiniteProgressIsIgnored() {var values:[Float]=[];EditedAvatarVideoExport.queue.sync {disposables.append(generateEditedAvatarVideo(AVComposition(),composition:AVVideoComposition(),quality:"test",leftTrim:0,rightTrim:1,keyFrame:nil).start(next:{if case let .progress(value)=$0 {values.append(value)}}))};flush();EditedAvatarVideoExport.queue.sync {State.sessions[0].progress = .nan};let after=expectation(description:"timer ticks");DispatchQueue.main.asyncAfter(deadline:.now()+0.12) {after.fulfill()};wait(for:[after],timeout:2);disposables[0].dispose();flush();XCTAssertTrue(values.isEmpty)}

}
