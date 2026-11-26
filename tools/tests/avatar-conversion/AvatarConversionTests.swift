import Foundation
import CoreMedia
import SwiftSignalKit
import XCTest

typealias CGImage=Int
typealias CVPixelBuffer=Int
typealias CFURL=URL
typealias CFDictionary=[String:Double]
let kUTTypeJPEG="jpeg",kCGImageDestinationLossyCompressionQuality="quality"
final class Destination {let url:URL;init(_ url:URL) {self.url=url}}
final class Images {static var destinationFails=false;static var finalizeFails=false;static var bufferFails=false;static var imageFails=false;static var paths:[String]=[]}
func CGImageDestinationCreateWithURL(_ url:CFURL,_ type:String,_ count:Int,_ options:CFDictionary?)->Destination? {guard !Images.destinationFails else {return nil};Images.paths.append(url.path);try? Data([1]).write(to:url);return Destination(url)}
func CGImageDestinationAddImage(_ destination:Destination,_ image:CGImage,_ options:CFDictionary) {}
func CGImageDestinationFinalize(_ destination:Destination)->Bool {!Images.finalizeFails}
func avatarCompositedImage(from:CGImage,zoom:CGFloat,offset:CGPoint,background:CGImage)->CGImage? {Images.imageFails ? nil:from}
func avatarPixelBuffer(from:CGImage,zoom:CGFloat,offset:CGPoint,background:CGImage)->CVPixelBuffer? {Images.bufferFails ? nil:from}
struct Resource {let complete:Bool;let path:String}
final class MediaBox {var source:Signal<Resource,NoError> = .never();func resourceData(_ resource:Int)->Signal<Resource,NoError> {source}}
final class Postbox {let mediaBox=MediaBox()}
final class Account {let postbox=Postbox()}
final class Context {let account=Account();var fetchStarts=0;var fetchDisposals=0;var fetchFails=false}
struct Media {let isWebm:Bool;let mimeType:String;let resource=1}
struct FileMediaReference {let media:Media}
enum AvatarMediaPreparationError:Error {case generic}
func avatarMediaResourcePath(context:Context,fileReference:FileMediaReference)->Signal<String,AvatarMediaPreparationError> {Signal {subscriber in context.fetchStarts+=1;let disposable:Disposable;if context.fetchFails {subscriber.putError(.generic);disposable=EmptyDisposable} else {disposable=(context.account.postbox.mediaBox.resourceData(fileReference.media.resource) |> filter {$0.complete} |> take(1)).start(next:{subscriber.putNext($0.path)},completed:{subscriber.putCompletion()})};return ActionDisposable {context.fetchDisposals+=1;disposable.dispose()}}}

enum LottieAnimationType {case lottie,webm,webp}
final class RenderedFrame {let image:CGImage?;init(_ image:CGImage?) {self.image=image}}
final class Renderer {var startFrame:Int32=0;var endFrame:Int32=4;var fps=24;var mainFps=24;var failAt:Int32?;var renders:[Int32]=[];var previous:[Int32:Bool]=[:];var webmEnd:Int32?;func render(at frame:Int32,frames:[RenderedFrame],previousFrame:RenderedFrame?)->RenderedFrame? {renders.append(frame);previous[frame]=previousFrame != nil;if frame==failAt {return nil};if let end=webmEnd,frame>=end {endFrame=end;return nil};return RenderedFrame(Int(frame))}}
final class LottieAnimation {enum Key {case bundle(String)};struct CacheKey {init(key:Key,size:CGSize) {}};let type:LottieAnimationType;static var renderer:Renderer?;init(compressed:Data,key:CacheKey,type:LottieAnimationType) {self.type=type};func initialize()->Renderer? {Self.renderer}}
final class StickerToMp4 {enum Status:Equatable {case initializing(String),converting(Float),done(String,String),failed}}
enum ConstructionError:Error {case failed}
final class AvatarVideoExport {
 enum Frame {case frame(CVPixelBuffer,CMTime),finished(CMTime),failed}
 static var instances:[AvatarVideoExport]=[];static var constructionFails=false
 var started=0;var cancels=0;var next:(()->Frame)?;var completed:((String?)->Void)?;var isCancelled:(()->Bool)?;var terminal=false;var times:[CMTime]=[];var end:CMTime?
 init(codec:String) throws {if Self.constructionFails {throw ConstructionError.failed};Self.instances.append(self)}
 func start(queue:DispatchQueue,isCancelled:@escaping()->Bool,next:@escaping()->Frame,completed:@escaping(String?)->Void) {started+=1;self.isCancelled=isCancelled;self.next=next;self.completed=completed}
 func pull() {guard !terminal else {return};guard isCancelled?()==false else {cancel();return};switch next?() {case let .frame(_,time):times.append(time);case let .finished(time):end=time;case .failed:complete(nil);case nil:break}}
 func complete(_ path:String?) {guard !terminal else {return};terminal=true;let f=completed;completed=nil;next=nil;f?(path)}
 func cancel() {cancels+=1;complete(nil)}
}
__SEQUENCE__
__CONTEXT__
final class AvatarConversionTests:XCTestCase {
 var paths:[String]=[]
 override func setUp() {Images.paths=[];Images.destinationFails=false;Images.finalizeFails=false;Images.bufferFails=false;Images.imageFails=false;AvatarVideoExport.instances=[];AvatarVideoExport.constructionFails=false;LottieAnimation.renderer=Renderer()}
 override func tearDown() {for path in paths+Images.paths {try? FileManager.default.removeItem(atPath:path)}}
 func run(_ f:()->Void) {StickerToMp4Context.queue.sync(f)}
 func file()->String {let p=NSTemporaryDirectory()+UUID().uuidString;try! Data([1]).write(to:URL(fileURLWithPath:p));paths.append(p);return p}
 func make(webm:Bool=false,background:Signal<CGImage,NoError> = .single(1),context:Context?=nil,cancelled:Atomic<Bool> = Atomic(value:false))->StickerToMp4Context {let c=context ?? Context();if context==nil {c.account.postbox.mediaBox.source = .single(Resource(complete:true,path:file()))};return StickerToMp4Context(context:c,background:background,zoom:1,offset:.zero,fileReference:.init(media:.init(isWebm:webm,mimeType:"application/json")),codec:"h264",cancelled:cancelled)}
 func testInvalidRendererReportsFailure() {LottieAnimation.renderer=nil;let c=make();run {c.start();XCTAssertEqual(c.status,.failed)};XCTAssertEqual(AvatarVideoExport.instances[0].started,0)}
 func testInvalidFrameRateReportsFailure() {LottieAnimation.renderer!.mainFps=0;let c=make();run {c.start();XCTAssertEqual(c.status,.failed)}}
 func testEmptyFrameRangeReportsFailure() {LottieAnimation.renderer!.endFrame=0;let c=make();run {c.start();XCTAssertEqual(c.status,.failed)}}
 func testMissingFirstFrameReportsFailure() {LottieAnimation.renderer!.failAt=0;let c=make();run {c.start();XCTAssertEqual(c.status,.failed)}}
 func testThumbnailCreationFailureDoesNotStartExport() {Images.destinationFails=true;let c=make();run {c.start();XCTAssertEqual(c.status,.failed)};XCTAssertEqual(AvatarVideoExport.instances[0].started,0)}
 func testThumbnailFinalizeFailureDeletesPartialFile() {Images.finalizeFails=true;let c=make();run {c.start();XCTAssertEqual(c.status,.failed)};XCTAssertFalse(FileManager.default.fileExists(atPath:Images.paths[0]))}
 func testBufferFailureDeletesThumbnailAndReportsFailure() {let c=make();run {c.start();Images.bufferFails=true;AvatarVideoExport.instances[0].pull();XCTAssertEqual(c.status,.failed)};XCTAssertFalse(FileManager.default.fileExists(atPath:Images.paths[0]))}
 func testRepeatedResourceAndBackgroundEventsDoNotRestartExport() {let context=Context();let resources=ValuePipe<Resource>();context.account.postbox.mediaBox.source=resources.signal();let backgrounds=ValuePipe<CGImage>();let c=make(background:backgrounds.signal(),context:context);let path=file();run {c.start();resources.putNext(.init(complete:true,path:path));backgrounds.putNext(1);resources.putNext(.init(complete:true,path:path));backgrounds.putNext(2);XCTAssertEqual(AvatarVideoExport.instances[0].started,1)}}
 func testRepeatedStartDoesNotFetchTwice() {let c=make();run {c.start();c.start();XCTAssertEqual(c.context.fetchStarts,1)}}
 func testCancelBeforeStartDoesNotFetchOrRender() {let c=make();run {c.cancel();c.start();XCTAssertEqual(c.context.fetchStarts,0);XCTAssertEqual(c.status,.failed)};XCTAssertTrue(LottieAnimation.renderer!.renders.isEmpty)}
 func testCancellationWhileWaitingDisposesFetch() {let context=Context();let c=make(context:context);run {c.start();c.cancel();XCTAssertEqual(context.fetchDisposals,1);XCTAssertEqual(c.status,.failed)}}
 func testCancelledSignalCannotResumePreparation() {let context=Context();let resources=ValuePipe<Resource>();context.account.postbox.mediaBox.source=resources.signal();let c=make(context:context);let path=file();run {c.start();c.cancel();resources.putNext(.init(complete:true,path:path));XCTAssertEqual(AvatarVideoExport.instances[0].started,0)}}
 func testCancellationDuringExportDeletesThumbnail() {let c=make();run {c.start();c.cancel();XCTAssertEqual(c.status,.failed)};XCTAssertFalse(FileManager.default.fileExists(atPath:Images.paths[0]))}
 func testFailedFinishDoesNotPublishDone() {let c=make();run {c.start();AvatarVideoExport.instances[0].complete(nil);XCTAssertEqual(c.status,.failed)}}
 func testSuccessTransfersOutputAndThumbnail() {var c:StickerToMp4Context?=make();let video=file();run {c!.start();AvatarVideoExport.instances[0].complete(video);XCTAssertEqual(c!.status,.done(video,Images.paths[0]));c=nil};XCTAssertTrue(FileManager.default.fileExists(atPath:video));XCTAssertTrue(FileManager.default.fileExists(atPath:Images.paths[0]))}
 func testCancelFlagBeforeCompletionRejectsOutput() {let flag=Atomic(value:false);let c=make(cancelled:flag);let video=file();run {c.start();_ = flag.swap(true);AvatarVideoExport.instances[0].complete(video);XCTAssertEqual(c.status,.failed)};XCTAssertFalse(FileManager.default.fileExists(atPath:video));XCTAssertFalse(FileManager.default.fileExists(atPath:Images.paths[0]))}
 func testFirstFrameIsReusedForSequentialDecoder() {let c=make(webm:true);run {c.start();AvatarVideoExport.instances[0].pull();AvatarVideoExport.instances[0].pull()};XCTAssertEqual(LottieAnimation.renderer!.renders,[0,1]);XCTAssertEqual(LottieAnimation.renderer!.previous[1],true)}
 func testShortWebmEndsAtDecodedDuration() {let r=LottieAnimation.renderer!;r.endFrame=180;r.webmEnd=2;let c=make(webm:true);run {c.start();let e=AvatarVideoExport.instances[0];e.pull();e.pull();e.pull();XCTAssertEqual(e.end?.seconds,2.0/24);XCTAssertEqual(e.times.count,2)}}
 func testLottieRenderFailureDoesNotBecomeTruncatedSuccess() {LottieAnimation.renderer!.failAt=2;let c=make();run {c.start();let e=AvatarVideoExport.instances[0];e.pull();e.pull();e.pull();XCTAssertEqual(c.status,.failed);XCTAssertNil(e.end)}}
 func testMissingResourceFileReportsFailureWithoutFetchLeak() {let context=Context();context.account.postbox.mediaBox.source = .single(.init(complete:true,path:"/nonexistent/avatar-source"));let c=make(context:context);run {c.start();XCTAssertEqual(c.status,.failed);XCTAssertEqual(context.fetchStarts,1);XCTAssertEqual(context.fetchDisposals,1)}}
 func testExporterConstructionFailureReportsFailure() {AvatarVideoExport.constructionFails=true;let c=make();run {c.start();XCTAssertEqual(c.status,.failed);XCTAssertEqual(c.context.fetchStarts,0)}}
 func testDisposalDuringProgressCannotPublishSuccess() {let flag=Atomic(value:false);let c=make(cancelled:flag);var observation:Disposable?;run {observation=c.statusValue.start(next:{status in if case .converting=status {_ = flag.swap(true)}});c.start();let e=AvatarVideoExport.instances[0];e.pull();e.pull();XCTAssertEqual(c.status,.failed)};observation?.dispose()}
 func testContextReleaseCancelsExporterAndDeletesThumbnail() {var c:StickerToMp4Context?=make();weak var weakContext=c;run {c!.start();c=nil};XCTAssertNil(weakContext);XCTAssertTrue(AvatarVideoExport.instances[0].terminal);XCTAssertFalse(FileManager.default.fileExists(atPath:Images.paths[0]))}
 func testTypedDownloadFailureTerminatesConversion() {let context=Context();context.fetchFails=true;let c=make(context:context);run {c.start();XCTAssertEqual(c.status,.failed);XCTAssertEqual(context.fetchDisposals,1)};XCTAssertEqual(AvatarVideoExport.instances[0].started,0)}
 func testEmptyBackgroundTerminatesInsteadOfWaitingForever() {let c=make(background:.complete());run {c.start();XCTAssertEqual(c.status,.failed)};XCTAssertEqual(AvatarVideoExport.instances[0].started,0)}
 func testCompletedPreparationDoesNotFailRunningExport() {let c=make();run {c.start();XCTAssertFalse(c.completed);XCTAssertEqual(AvatarVideoExport.instances[0].started,1)}}

 func testThumbnailCompositingFailureTerminatesExport() {Images.imageFails=true;let c=make();run {c.start();XCTAssertEqual(c.status,.failed)};XCTAssertEqual(AvatarVideoExport.instances[0].started,0)}

 func testEmptyBackgroundCancelsPendingDownload() {let context=Context();let c=make(background:.complete(),context:context);run {c.start();XCTAssertEqual(c.status,.failed);XCTAssertEqual(context.fetchDisposals,context.fetchStarts)};XCTAssertEqual(AvatarVideoExport.instances[0].started,0)}
 func testAsynchronousEmptyBackgroundCancelsPendingDownload() {let context=Context();var backgroundSubscriber:Subscriber<CGImage,NoError>?;let background=Signal<CGImage,NoError> {backgroundSubscriber=$0;return EmptyDisposable};let c=make(background:background,context:context);run {c.start();XCTAssertEqual(context.fetchDisposals,0);backgroundSubscriber?.putCompletion();XCTAssertEqual(c.status,.failed);XCTAssertEqual(context.fetchDisposals,1)};XCTAssertEqual(AvatarVideoExport.instances[0].started,0)}

}
