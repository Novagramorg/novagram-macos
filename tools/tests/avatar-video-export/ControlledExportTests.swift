import Foundation
import CoreMedia
import XCTest

typealias CVPixelBuffer=Int
let AVVideoWidthKey="width",AVVideoHeightKey="height",AVVideoCodecKey="codec",AVVideoCompressionPropertiesKey="compression",AVVideoAverageBitRateKey="bitrate",AVVideoMaxKeyFrameIntervalKey="interval"
struct AVVideoCodecType {let rawValue:String;static let h264=Self(rawValue:"h264")}
enum AVMediaType {case video}
enum AVFileType {case mp4}
final class DispatchQueue {var jobs:[()->Void]=[];func async(_ action:@escaping()->Void) {jobs.append(action)};func drain() {while !jobs.isEmpty {jobs.removeFirst()()}}}
struct ObservationOptions {static let new=Self()}
final class NSKeyValueObservation {let stop:()->Void;init(_ stop:@escaping()->Void) {self.stop=stop};deinit {stop()}}
final class AVAssetWriter {
    enum Status {case unknown,writing,completed,failed,cancelled}
    static var instances:[AVAssetWriter]=[];static var allowSettings=true;static var allowInput=true;static var startResult=true
    let url:URL;var status=Status.unknown {didSet {observer?(self,0)}};var error:Error?;var observer:((AVAssetWriter,Int)->Void)?;var input:AVAssetWriterInput?;var started=0;var cancelled=0;var finishCalls=0;var finishedCallback:(()->Void)?;var ended:CMTime?
    init(url:URL,fileType:AVFileType) throws {self.url=url;try Data([1]).write(to:url);Self.instances.append(self)}
    func canApply(outputSettings:[String:Any],forMediaType:AVMediaType)->Bool {Self.allowSettings}
    func canAdd(_ input:AVAssetWriterInput)->Bool {Self.allowInput}
    func add(_ input:AVAssetWriterInput) {self.input=input}
    func startWriting()->Bool {started+=1;status=Self.startResult ? .writing:.failed;return Self.startResult}
    func startSession(atSourceTime:CMTime) {}
    func endSession(atSourceTime:CMTime) {ended=atSourceTime}
    func finishWriting(completionHandler:@escaping()->Void) {finishCalls+=1;finishedCallback=completionHandler}
    func cancelWriting() {cancelled+=1;status = .cancelled}
    func observe(_ path:KeyPath<AVAssetWriter,Status>,options:[ObservationOptions],changeHandler:@escaping(AVAssetWriter,Int)->Void)->NSKeyValueObservation {observer=changeHandler;return NSKeyValueObservation { [weak self] in self?.observer=nil}}
    func complete(_ status:Status) {self.status=status;finishedCallback?()}
}
final class AVAssetWriterInput {
    var isReadyForMoreMediaData=true;var marked=0;var callback:(()->Void)?;var appends:[CMTime]=[];var appendResult=true;var onAppend:(()->Void)?
    init(mediaType:AVMediaType,outputSettings:[String:Any]) {}
    func requestMediaDataWhenReady(on queue:DispatchQueue,using callback:@escaping()->Void) {self.callback=callback;queue.async(callback)}
    func markAsFinished() {marked+=1;callback=nil}
}
final class AVAssetWriterInputPixelBufferAdaptor {
    let input:AVAssetWriterInput;init(assetWriterInput:AVAssetWriterInput,sourcePixelBufferAttributes:[String:Any]?) {input=assetWriterInput}
    func append(_ buffer:CVPixelBuffer,withPresentationTime time:CMTime)->Bool {input.appends.append(time);input.onAppend?();return input.appendResult}
}
__SOURCE__
final class ControlledExportTests:XCTestCase {
    override func setUp() {AVAssetWriter.instances=[];AVAssetWriter.allowSettings=true;AVAssetWriter.allowInput=true;AVAssetWriter.startResult=true}
    override func tearDown() {for w in AVAssetWriter.instances {try? FileManager.default.removeItem(at:w.url)}}
    func make() throws ->(AvatarVideoExport,AVAssetWriter,DispatchQueue) {let e=try AvatarVideoExport(codec:"h264");return(e,AVAssetWriter.instances.last!,DispatchQueue())}
    func testStartFailureReturnsNoPathAndRemovesFile() throws {let(e,w,q)=try make();AVAssetWriter.startResult=false;var calls=0;e.start(queue:q,isCancelled:{false},next:{XCTFail();return .failed},completed:{XCTAssertNil($0);calls+=1});XCTAssertEqual(calls,1);XCTAssertFalse(FileManager.default.fileExists(atPath:w.url.path))}
    func testBackpressureReturnsAndResumes() throws {let(e,w,q)=try make();w.input!.isReadyForMoreMediaData=false;var count=0;e.start(queue:q,isCancelled:{false},next:{count+=1;return .finished(CMTime(value:1,timescale:1))},completed:{_ in});q.drain();XCTAssertEqual(count,0);XCTAssertEqual(w.finishCalls,0);w.input!.isReadyForMoreMediaData=true;w.input!.callback?();XCTAssertEqual(count,1);XCTAssertEqual(w.finishCalls,1)}
    func testCancellationWhileBackpressuredCompletes() throws {let(e,w,q)=try make();w.input!.isReadyForMoreMediaData=false;var calls=0;e.start(queue:q,isCancelled:{false},next:{XCTFail();return .failed},completed:{XCTAssertNil($0);calls+=1});q.drain();e.cancel();q.drain();XCTAssertEqual(calls,1);XCTAssertEqual(w.cancelled,1)}
    func testFailedAppendDoesNotFinishSuccessfully() throws {let(e,w,q)=try make();w.input!.appendResult=false;var calls=0;e.start(queue:q,isCancelled:{false},next:{.frame(1,.zero)},completed:{XCTAssertNil($0);calls+=1});q.drain();XCTAssertEqual(calls,1);XCTAssertEqual(w.input!.appends.count,1);XCTAssertEqual(w.finishCalls,0);XCTAssertFalse(FileManager.default.fileExists(atPath:w.url.path))}
    func testWriterFailureWhileNotReadyReportsFailure() throws {let(e,w,q)=try make();w.input!.isReadyForMoreMediaData=false;var calls=0;e.start(queue:q,isCancelled:{false},next:{XCTFail();return .failed},completed:{XCTAssertNil($0);calls+=1});q.drain();w.status = .failed;q.drain();XCTAssertEqual(calls,1)}
    func testRejectedFinishDoesNotPublishPath() throws {let(e,w,q)=try make();var calls=0;e.start(queue:q,isCancelled:{false},next:{.finished(CMTime(value:1,timescale:1))},completed:{XCTAssertNil($0);calls+=1});q.drain();w.complete(.failed);q.drain();XCTAssertEqual(calls,1);XCTAssertFalse(FileManager.default.fileExists(atPath:w.url.path))}
    func testSuccessWaitsForAcceptedFinish() throws {let(e,w,q)=try make();var paths:[String?]=[];e.start(queue:q,isCancelled:{false},next:{.finished(CMTime(value:1,timescale:1))},completed:{paths.append($0)});q.drain();XCTAssertTrue(paths.isEmpty);w.complete(.completed);q.drain();XCTAssertEqual(paths.count,1);XCTAssertEqual(paths.first!,w.url.path);XCTAssertTrue(FileManager.default.fileExists(atPath:w.url.path))}
    func testCancelledFinishCannotPublishLateSuccess() throws {let(e,w,q)=try make();var paths:[String?]=[];e.start(queue:q,isCancelled:{false},next:{.finished(CMTime(value:1,timescale:1))},completed:{paths.append($0)});q.drain();e.cancel();w.complete(.completed);q.drain();XCTAssertEqual(paths.count,1);XCTAssertNil(paths[0])}
    func testDuplicateStartDoesNotRestartWriter() throws {let(e,w,q)=try make();w.input!.isReadyForMoreMediaData=false;e.start(queue:q,isCancelled:{false},next:{.failed},completed:{_ in});e.start(queue:q,isCancelled:{false},next:{XCTFail();return .failed},completed:{_ in XCTFail()});q.drain();XCTAssertEqual(w.started,1)}
    func testCancellationPredicateDuringRenderPreventsAppend() throws {let(e,w,q)=try make();var cancelled=false;var calls=0;e.start(queue:q,isCancelled:{cancelled},next:{cancelled=true;return .frame(1,.zero)},completed:{XCTAssertNil($0);calls+=1});q.drain();XCTAssertTrue(w.input!.appends.isEmpty);XCTAssertEqual(calls,1)}
    func testReentrantCancellationDuringRenderPreventsAppend() throws {let(e,w,q)=try make();var calls=0;e.start(queue:q,isCancelled:{false},next:{[weak e] in e?.cancel();return .frame(1,.zero)},completed:{XCTAssertNil($0);calls+=1});q.drain();XCTAssertTrue(w.input!.appends.isEmpty);XCTAssertEqual(calls,1)}
    func testFailureCallbackCanCancelAgain() throws {let(e,_,q)=try make();var calls=0;e.start(queue:q,isCancelled:{false},next:{.failed},completed:{[weak e] _ in calls+=1;e?.cancel()});q.drain();XCTAssertEqual(calls,1)}
    func testUnsupportedSettingsRejectConstruction() {AVAssetWriter.allowSettings=false;XCTAssertThrowsError(try AvatarVideoExport(codec:"bad"))}
    func testUnsupportedInputRejectConstruction() {AVAssetWriter.allowInput=false;XCTAssertThrowsError(try AvatarVideoExport(codec:"h264"))}
    func testReadinessCallbackDoesNotRetainExporter() throws {var e:AvatarVideoExport?=try AvatarVideoExport(codec:"h264");let w=AVAssetWriter.instances.last!;w.input!.isReadyForMoreMediaData=false;let q=DispatchQueue();e!.start(queue:q,isCancelled:{false},next:{.failed},completed:{_ in});q.drain();weak var weakExport=e;e=nil;XCTAssertNil(weakExport);XCTAssertEqual(w.cancelled,1);XCTAssertFalse(FileManager.default.fileExists(atPath:w.url.path))}
    func testNextReadinessCallbackContinuesAtNextFrame() throws {let(e,w,q)=try make();var index=0;w.input!.onAppend={w.input!.isReadyForMoreMediaData=false};e.start(queue:q,isCancelled:{false},next:{index+=1;return index<=2 ? .frame(1,CMTime(value:Int64(index-1),timescale:30)):.finished(CMTime(value:2,timescale:30))},completed:{_ in});q.drain();XCTAssertEqual(index,1);w.input!.isReadyForMoreMediaData=true;w.input!.callback?();XCTAssertEqual(index,2);w.input!.isReadyForMoreMediaData=true;w.input!.callback?();XCTAssertEqual(w.input!.appends.count,2);XCTAssertEqual(w.finishCalls,1)}
}
