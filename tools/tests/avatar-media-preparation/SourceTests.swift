import Foundation
import SwiftSignalKit
import XCTest

enum AvatarMediaPreparationError:Error,Equatable {case generic}
final class Source<T,E> {var subscribers:[Subscriber<T,E>]=[];var starts=0;var disposals=0;var onStart:((Subscriber<T,E>)->Void)?;var signal:Signal<T,E> {Signal {s in self.starts+=1;self.subscribers.append(s);self.onStart?(s);return ActionDisposable {self.disposals+=1}}};func send(_ value:T) {subscribers.forEach {$0.putNext(value)}};func fail(_ error:E) {subscribers.forEach {$0.putError(error)}};func finish() {subscribers.forEach {$0.putCompletion()}}}
struct Resource {let complete:Bool;let path:String}
enum FetchResourceError {case generic}
enum FetchResourceSourceType {case local,remote}
enum Category {case video,file}
struct Media {let resource=1;let isVideo:Bool}
typealias TelegramMediaFile=Media
struct FileMediaReference {let media:Media;let userLocation=1;let userContentType=1;func resourceReference(_ resource:Int)->Int {resource};static func standalone(media:Media)->Self {.init(media:media)}}
final class MediaBox {let fetch=Source<FetchResourceSourceType,FetchResourceError>();let data=Source<Resource,NoError>();func resourceData(_ resource:Int)->Signal<Resource,NoError> {data.signal}}
final class Postbox {let mediaBox=MediaBox()}
final class Account {let postbox=Postbox()}
final class Context {let account=Account()}
func fetchedMediaResource(mediaBox:MediaBox,userLocation:Int,userContentType:Int,reference:Int,statsCategory:Category)->Signal<FetchResourceSourceType,FetchResourceError> {mediaBox.fetch.signal}
struct CGImage {var size:CGSize {.init(width:1,height:1)}}
final class NSImage:Equatable {static func ==(lhs:NSImage,rhs:NSImage)->Bool {lhs === rhs};let _cgImage:CGImage?;init(cgImage:CGImage,size:CGSize) {_cgImage=cgImage}}
final class Decoder {static var fails=false;static var renderFails=false}
func convertFromWebP(_ data:Data)->NSImage? {Decoder.fails ? nil:NSImage(cgImage:CGImage(),size:.zero)}
func avatarCompositedImage(from:CGImage,zoom:CGFloat,offset:CGPoint,background:CGImage)->CGImage? {Decoder.renderFails ? nil:from}
final class AvatarPreparedVideo:Equatable {static func ==(lhs:AvatarPreparedVideo,rhs:AvatarPreparedVideo)->Bool {lhs === rhs};static var paths:[String]=[];static var fails=false;let videoPath="/video",thumbnailPath="/thumb";static func prepare(path:String)->Result<AvatarPreparedVideo,AvatarMediaPreparationError> {paths.append(path);return fails ? .failure(.generic):.success(AvatarPreparedVideo())}}
final class StickerToMp4Context {static let queue=Queue(name:"avatar-preparation-tests")}
__RESOURCE__
__CLASSES__
enum VideoAvatarGeneratorState:Equatable {case start(thumb:String),progress(Float),complete(thumb:String,video:String,keyFrame:Double?),error}
final class MediaObjectToAvatar {
 struct Object {struct Foreground {enum Source {case emoji,sticker,animated,gif};let type:Source};let foreground:Foreground}
 struct Result {enum Status {case initializing(String),converting(Float),done(String,String),failed};enum Output {case image(NSImage),video(String,String)};var status:Status?=nil;var result:Output?=nil}
 let object:Object;let source=Source<Result,NoError>();init(_ type:Object.Foreground.Source) {object=Object(foreground:.init(type:type))};func start()->Signal<Result,NoError> {source.signal}
}
__ADAPTER__
final class SourceTests:XCTestCase {
 var files:[String]=[]
 override func setUp() {Decoder.fails=false;Decoder.renderFails=false;AvatarPreparedVideo.paths=[];AvatarPreparedVideo.fails=false}
 override func tearDown() {for p in files {try? FileManager.default.removeItem(atPath:p)}}
 func run(_ f:()->Void) {StickerToMp4Context.queue.sync(f)}
 func path()->String {let p=NSTemporaryDirectory()+UUID().uuidString;try! Data([1]).write(to:URL(fileURLWithPath:p));files.append(p);return p}
 func box(_ c:Context)->MediaBox {c.account.postbox.mediaBox}
 func signal(_ c:Context)->Signal<String,AvatarMediaPreparationError> {avatarMediaResourcePath(context:c,fileReference:.standalone(media:.init(isVideo:true)))}
 func testFetchFailurePropagatesWithoutDataSubscription() {let c=Context();var errors=0;let d=signal(c).start(error:{_ in errors+=1});box(c).fetch.fail(.generic);XCTAssertEqual(errors,1);XCTAssertEqual(box(c).data.starts,0);d.dispose()}
 func testSuccessfulFetchDoesNotRequireNextValue() {let c=Context();var paths:[String]=[];let d=signal(c).start(next:{paths.append($0)});box(c).fetch.finish();XCTAssertEqual(box(c).data.starts,1);box(c).data.send(.init(complete:true,path:"/ok"));XCTAssertEqual(paths,["/ok"]);d.dispose()}
 func testFetchValueAloneDoesNotReadPrematurely() {let c=Context();let d=signal(c).start();box(c).fetch.send(.remote);XCTAssertEqual(box(c).data.starts,0);box(c).fetch.finish();XCTAssertEqual(box(c).data.starts,1);d.dispose()}
 func testIncompleteDataIsIgnoredAndOnlyFirstCompletePathDelivered() {let c=Context();var paths:[String]=[];let d=signal(c).start(next:{paths.append($0)});box(c).fetch.finish();box(c).data.send(.init(complete:false,path:"/part"));box(c).data.send(.init(complete:true,path:"/first"));box(c).data.send(.init(complete:true,path:"/second"));XCTAssertEqual(paths,["/first"]);XCTAssertEqual(box(c).data.disposals,1);d.dispose()}
 func testEmptyDataCompletionReportsFailure() {let c=Context();var errors=0;let d=signal(c).start(error:{_ in errors+=1});box(c).fetch.finish();box(c).data.finish();XCTAssertEqual(errors,1);d.dispose()}
 func testCancelPendingFetchSuppressesLateCompletion() {let c=Context();let d=signal(c).start();d.dispose();box(c).fetch.finish();XCTAssertEqual(box(c).fetch.disposals,1);XCTAssertEqual(box(c).data.starts,0)}
 func testCancelPendingDataSuppressesLatePath() {let c=Context();var paths:[String]=[];let d=signal(c).start(next:{paths.append($0)});box(c).fetch.finish();d.dispose();box(c).data.send(.init(complete:true,path:"/late"));XCTAssertTrue(paths.isEmpty);XCTAssertEqual(box(c).data.disposals,1)}
 func testResourceSignalDoesNotRetainAccountContext() {var c:Context?=Context();weak var weakContext=c;let s=signal(c!);c=nil;XCTAssertNil(weakContext);withExtendedLifetime(s) {}}
 func testSynchronousFetchAndDataFinishOnce() {let c=Context();box(c).fetch.onStart={$0.putCompletion()};box(c).data.onStart={$0.putNext(.init(complete:true,path:"/now"));$0.putCompletion()};var paths:[String]=[];var errors=0;let d=signal(c).start(next:{paths.append($0)},error:{_ in errors+=1});XCTAssertEqual(paths,["/now"]);XCTAssertEqual(errors,0);XCTAssertEqual(box(c).data.disposals,1);d.dispose()}
 func testVideoStartIsIdempotent() {let c=Context();let source=FetchVideoToFile(context:c,file:.init(isVideo:true));run {source.start();source.start()};XCTAssertEqual(box(c).fetch.starts,1)}
 func testVideoFetchFailureIsTerminal() {let c=Context();let source=FetchVideoToFile(context:c,file:.init(isVideo:true));var errors=0;var completed=0;let d=source.status.start(next:{if case .failure=$0 {errors+=1}},completed:{completed+=1});run {source.start();box(c).fetch.fail(.generic)};XCTAssertEqual(errors,1);XCTAssertEqual(completed,1);d.dispose()}
 func testVideoPreparationFailureIsTerminal() {let c=Context();let source=FetchVideoToFile(context:c,file:.init(isVideo:true));AvatarPreparedVideo.fails=true;var errors=0;let d=source.status.start(next:{if case .failure=$0 {errors+=1}});run {source.start();box(c).fetch.finish();box(c).data.send(.init(complete:true,path:"/bad"))};XCTAssertEqual(errors,1);d.dispose()}
 func testVideoResultContainsBothPreparedPaths() {let c=Context();let source=FetchVideoToFile(context:c,file:.init(isVideo:true));var paths:[String]=[];let d=source.status.start(next:{if case let .success(v)=$0 {paths=[v.videoPath,v.thumbnailPath]}});run {source.start();box(c).fetch.finish();box(c).data.send(.init(complete:true,path:"/input"));box(c).data.send(.init(complete:true,path:"/again"))};XCTAssertEqual(paths,["/video","/thumb"]);XCTAssertEqual(AvatarPreparedVideo.paths,["/input"]);d.dispose()}
 func testVideoSourceReleaseCancelsPendingFetch() {let c=Context();var source:FetchVideoToFile?=FetchVideoToFile(context:c,file:.init(isVideo:true));run {source!.start();source=nil};XCTAssertEqual(box(c).fetch.disposals,1)}
 func testRetainedVideoStatusDoesNotKeepSourceAlive() {let c=Context();var source:FetchVideoToFile?=FetchVideoToFile(context:c,file:.init(isVideo:true));weak var weakSource=source;let status=source!.status;run {source!.start();source=nil};XCTAssertNil(weakSource);XCTAssertEqual(box(c).fetch.disposals,1);withExtendedLifetime(status) {}}
 func sticker(_ c:Context,_ background:Signal<CGImage,NoError> = .single(CGImage()))->FetchStickerToImage {FetchStickerToImage(context:c,background:background,zoom:1,offset:.zero,file:.init(isVideo:false))}
 func testStickerDownloadFailureIsTerminal() {let c=Context();let source=sticker(c);var errors=0;let d=source.status.start(next:{if case .failure=$0 {errors+=1}});run {source.start();box(c).fetch.fail(.generic)};XCTAssertEqual(errors,1);d.dispose()}
 func testStickerDecodeFailureIsTerminal() {let c=Context();let source=sticker(c);Decoder.fails=true;let p=path();var errors=0;let d=source.status.start(next:{if case .failure=$0 {errors+=1}});run {source.start();box(c).fetch.finish();box(c).data.send(.init(complete:true,path:p))};XCTAssertEqual(errors,1);d.dispose()}
 func testMissingStickerFileIsTerminal() {let c=Context();let source=sticker(c);var errors=0;let d=source.status.start(next:{if case .failure=$0 {errors+=1}});run {source.start();box(c).fetch.finish();box(c).data.send(.init(complete:true,path:"/nonexistent/avatar"))};XCTAssertEqual(errors,1);d.dispose()}

 func testEmptyBackgroundCancelsPendingStickerFetch() {let c=Context();let source=sticker(c,.complete());var errors=0;let d=source.status.start(next:{if case .failure=$0 {errors+=1}});run {source.start()};XCTAssertEqual(errors,1);XCTAssertEqual(box(c).fetch.disposals,box(c).fetch.starts);d.dispose()}
 func testAsynchronousEmptyBackgroundCancelsPendingStickerFetch() {let c=Context();let background=Source<CGImage,NoError>();let source=sticker(c,background.signal);var errors=0;let d=source.status.start(next:{if case .failure=$0 {errors+=1}});run {source.start();XCTAssertEqual(box(c).fetch.starts,1);background.finish()};XCTAssertEqual(errors,1);XCTAssertEqual(box(c).fetch.disposals,1);d.dispose()}
 func testEmptyBackgroundCannotSilentlyFinishWithoutResult() {let c=Context();let source=sticker(c,.complete());var errors=0;let d=source.status.start(next:{if case .failure=$0 {errors+=1}});run {source.start();box(c).fetch.finish();box(c).data.send(.init(complete:true,path:path()))};XCTAssertEqual(errors,1);d.dispose()}
 func testStickerSuccessIsOneResultAndNotOverwrittenByCompletion() {let c=Context();let backgrounds=ValuePipe<CGImage>();let source=sticker(c,backgrounds.signal());var successes=0;var failures=0;var completions=0;let d=source.status.start(next:{switch $0 {case .success:successes+=1;case .failure:failures+=1}},completed:{completions+=1});let p=path();run {source.start();box(c).fetch.finish();box(c).data.send(.init(complete:true,path:p));backgrounds.putNext(CGImage());backgrounds.putNext(CGImage());box(c).data.send(.init(complete:true,path:p))};XCTAssertEqual(successes,1);XCTAssertEqual(failures,0);XCTAssertEqual(completions,1);d.dispose()}
 func testStickerStartIsIdempotent() {let c=Context();let source=sticker(c);run {source.start();source.start()};XCTAssertEqual(box(c).fetch.starts,1)}
 func testStickerReleaseCancelsFetch() {let c=Context();var source:FetchStickerToImage?=sticker(c);run {source!.start();source=nil};XCTAssertEqual(box(c).fetch.disposals,1)}
 func testStaticStickerUsesPhotoRoute() {let object=MediaObjectToAvatar(.sticker);var photos=0;var videos=0;var d:Disposable?;makeAvatarVideo(object,updatePhoto:{photos+=1;d=$0.start()},updateVideo:{_ in videos+=1});XCTAssertEqual(photos,1);XCTAssertEqual(videos,0);d?.dispose()}
 func testEmojiFailureCompletesPhotoSignal() {let object=MediaObjectToAvatar(.emoji);var completed=0;var d:Disposable?;makeAvatarVideo(object,updatePhoto:{d=$0.start(completed:{completed+=1})},updateVideo:{_ in XCTFail()});object.source.send(.init(status:.failed));object.source.finish();XCTAssertEqual(completed,1);d?.dispose()}
 func testUnexpectedStaticVideoResultDoesNotHang() {let object=MediaObjectToAvatar(.emoji);var completed=0;var d:Disposable?;makeAvatarVideo(object,updatePhoto:{d=$0.start(next:{_ in XCTFail()},completed:{completed+=1})},updateVideo:{_ in XCTFail()});object.source.send(.init(result:.video("/v","/t")));object.source.finish();XCTAssertEqual(completed,1);d?.dispose()}
 func testStickerImageIsForwardedOnce() {let object=MediaObjectToAvatar(.sticker);let image=NSImage(cgImage:CGImage(),size:.zero);var images:[NSImage]=[];var d:Disposable?;makeAvatarVideo(object,updatePhoto:{d=$0.start(next:{images.append($0)})},updateVideo:{_ in XCTFail()});object.source.send(.init(result:.image(image)));XCTAssertEqual(images.count,1);XCTAssertTrue(images.first === image);d?.dispose()}
 func testProgressBeforeStaticImageKeepsWaiting() {let object=MediaObjectToAvatar(.emoji);var images=0;var completed=0;var d:Disposable?;makeAvatarVideo(object,updatePhoto:{d=$0.start(next:{_ in images+=1},completed:{completed+=1})},updateVideo:{_ in XCTFail()});object.source.send(.init(status:.converting(0.5)));XCTAssertEqual(completed,0);object.source.send(.init(result:.image(NSImage(cgImage:CGImage(),size:.zero))));object.source.finish();XCTAssertEqual(images,1);XCTAssertEqual(completed,1);d?.dispose()}
 func testAnimatedVideoMapsThumbnailAndPathInCorrectOrder() {let object=MediaObjectToAvatar(.animated);var values:[VideoAvatarGeneratorState]=[];var d:Disposable?;makeAvatarVideo(object,updatePhoto:{_ in XCTFail()},updateVideo:{d=$0.start(next:{values.append($0)})});object.source.send(.init(status:.initializing("/thumb")));object.source.send(.init(status:.converting(0.5)));object.source.send(.init(result:.video("/video","/thumb")));XCTAssertEqual(values,[.start(thumb:"/thumb"),.progress(0.5),.complete(thumb:"/thumb",video:"/video",keyFrame:nil)]);d?.dispose()}
 func testGifFailureMapsToVideoError() {let object=MediaObjectToAvatar(.gif);var values:[VideoAvatarGeneratorState]=[];var d:Disposable?;makeAvatarVideo(object,updatePhoto:{_ in XCTFail()},updateVideo:{d=$0.start(next:{values.append($0)})});object.source.send(.init(status:.failed));XCTAssertEqual(values,[.error]);d?.dispose()}
 func testEmptyStaticSourceCompletes() {let object=MediaObjectToAvatar(.emoji);var completed=0;var d:Disposable?;makeAvatarVideo(object,updatePhoto:{d=$0.start(completed:{completed+=1})},updateVideo:{_ in XCTFail()});object.source.finish();XCTAssertEqual(completed,1);d?.dispose()}

 func testStickerCompositingFailureIsTerminal() {let c=Context();let source=sticker(c);Decoder.renderFails=true;let p=path();var errors=0;let d=source.status.start(next:{if case .failure=$0 {errors+=1}});run {source.start();box(c).fetch.finish();box(c).data.send(.init(complete:true,path:p))};XCTAssertEqual(errors,1);d.dispose()}

}
