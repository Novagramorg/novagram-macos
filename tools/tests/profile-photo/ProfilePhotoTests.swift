import Foundation
import SwiftSignalKit
import XCTest

final class Source<T, E> {
    var subscribers:[Subscriber<T,E>]=[];var starts=0;var disposals=0;var onStart:((Subscriber<T,E>)->Void)?;var onDispose:(()->Void)?
    var signal:Signal<T,E> {Signal {s in self.starts+=1;self.subscribers.append(s);self.onStart?(s);return ActionDisposable {self.disposals+=1;self.onDispose?()}}}
    func send(_ value:T) {for s in subscribers {s.putNext(value)}}
    func finish() {for s in subscribers {s.putCompletion()}}
    func fail(_ error:E) {for s in subscribers {s.putError(error)}}
}
final class NSImage {let name:String;init(_ name:String) {self.name=name};convenience init?(contentsOfFile:String) {self.init(contentsOfFile)};var _cgImage:Int? {nil}}
final class Window {}
final class Context {let window=Window();let engine=Engine()}
struct EngineMediaResource {let resource:TelegramMediaResource;init(_ resource:TelegramMediaResource) {self.resource=resource}}
protocol TelegramMediaResource {var localFilePath:String {get}}
struct LocalFileReferenceMediaResource:TelegramMediaResource {let localFilePath:String;init(localFilePath:String,randomId:Int64,isUniquelyReferencedTemporaryFile:Bool=false) {self.localFilePath=localFilePath}}
func arc4random64()->Int64 {1}
enum UploadPeerPhotoError {case generic}
enum UpdatePeerPhotoStatus {case progress(Float),complete}
enum VideoAvatarGeneratorState {case error,start(thumb:String),progress(Float),complete(thumb:String,video:String,keyFrame:Double?)}
struct PeerInfoUpdatingPhotoState {let progress:Float;let cancel:()->Void;init(progress:Float,image:Int?=nil,cancel:@escaping()->Void) {self.progress=progress;self.cancel=cancel};func withUpdatedProgress(_ value:Float)->Self {.init(progress:value,cancel:cancel)}}
struct EditInfoState {var photo:PeerInfoUpdatingPhotoState?;func withoutUpdatingPhotoState()->Self {Self()};func withUpdatedUpdatingPhotoState(_ f:(PeerInfoUpdatingPhotoState?)->PeerInfoUpdatingPhotoState?)->Self {.init(photo:f(photo))}}
final class StateBox {var value=EditInfoState();var updates=0;var onUpdate:(()->Void)?;func update(_ f:(EditInfoState)->EditInfoState) {value=f(value);updates+=1;onUpdate?()};func modify(_ f:(EditInfoState)->EditInfoState)->EditInfoState {value=f(value);return value};func set(_ signal:Signal<EditInfoState,NoError>) {_ = signal.start(next:{self.value=$0;self.updates+=1;self.onUpdate?()})}}
final class Upload {let path:String;let source=Source<UpdatePeerPhotoStatus,UploadPeerPhotoError>();init(_ path:String) {self.path=path}}
final class AccountData {
    var uploads:[Upload]=[];var onStart:((Upload)->Void)?
    func updateAccountPhoto(resource:EngineMediaResource,videoResource:EngineMediaResource?,videoStartTimestamp:Double?,markup:Int?,mapResourceToAvatarSizes:@escaping(TelegramMediaResource,[Int])->Signal<Int,NoError>)->Signal<UpdatePeerPhotoStatus,UploadPeerPhotoError> {
        Signal {s in let upload=Upload(resource.resource.localFilePath);self.uploads.append(upload);upload.source.onStart={ [weak self, weak upload] sub in if let upload {self?.onStart?(upload)}};return upload.source.signal.start(next:{s.putNext($0)},error:{s.putError($0)},completed:{s.putCompletion()})}
    }
}
final class Peers {
    var uploads:[Upload]=[]
    func uploadedPeerPhoto(resource:EngineMediaResource)->Signal<EngineMediaResource,UploadPeerPhotoError> {.single(resource)}
    func uploadedPeerVideo(resource:EngineMediaResource)->Signal<EngineMediaResource,UploadPeerPhotoError> {.single(resource)}
    func updatePeerPhoto(peerId:Int,photo:Signal<EngineMediaResource,UploadPeerPhotoError>,video:Signal<EngineMediaResource?,UploadPeerPhotoError>,videoStartTimestamp:Double?,mapResourceToAvatarSizes:@escaping(TelegramMediaResource,[Int])->Signal<Int,NoError>)->Signal<UpdatePeerPhotoStatus,UploadPeerPhotoError> {Signal {s in let u=Upload("video");self.uploads.append(u);return u.source.signal.start(next:{s.putNext($0)},error:{s.putError($0)},completed:{s.putCompletion()})}}
}
final class Engine {let accountData=AccountData();let peers=Peers()}
func mapResourceToAvatarSizes(engine:Engine,resource:TelegramMediaResource,representations:[Int])->Signal<Int,NoError> {.complete()}
extension Signal {static func next(_ value:T)->Signal<T,E> {Signal {s in s.putNext(value);return EmptyDisposable}}}
func deliverOnMainQueue<T,E>(_ signal:Signal<T,E>)->Signal<T,E> {signal}
final class Prep {static var sources:[String:Source<String,NoError>]=[:];static var calls:[String]=[]}
func putToTemp(image:NSImage,compress:Bool)->Signal<String,NoError> {Prep.calls.append(image.name);return Prep.sources[image.name]!.signal}
enum Dimensions {case square}
enum Settings {case disableSizes(dimensions:Dimensions,circle:Bool)}
enum AnimationType {case scaleCenter}
final class Editor {
    let path:String;let output=Source<(URL,Int?),NoError>();var onShow:(()->Void)?
    init(_ path:String) {self.path=path};var result:Signal<(URL,Int?),NoError> {output.signal}
    func accept(_ path:String="/edited") {output.send((URL(fileURLWithPath:path),nil))}
}
final class Editors {static var shown:[Editor]=[];static var invalid=false;static var onShow:((Editor)->Void)?}
func EditImageModalController(_ url:URL,context:Context,settings:Settings)->Editor? {Editors.invalid ? nil:Editor(url.path)}
func showModal(with controller:Editor,for window:Window,animationType:AnimationType) {Editors.shown.append(controller);Editors.onShow?(controller)}
__HELPER__
final class ActiveAction {func setActive(_ active:Bool) {}}
final class Screen {
    let context=Context();let state=StateBox();let photoDisposable=MetaDisposable();let photoAction=EditAccountPhotoAction();let actionsDisposable=DisposableSet()
    var updatePhoto:((Signal<NSImage,NoError>)->Void)!;var updateVideo:((Signal<VideoAvatarGeneratorState,NoError>)->Void)!;var cancel:(()->Void)!
    init() {
        let context=self.context;let photoDisposable=self.photoDisposable;let photoAction=self.photoAction;let state=self.state;let stateValue=self.state;let peerId=1
        let updateState:((EditInfoState)->EditInfoState)->Void={state.update($0)}
        __CANCEL__
        __PHOTO__
        __VIDEO__
        self.cancel=cancel;self.updatePhoto=updatePhoto;self.updateVideo=updateVideo
        actionsDisposable.add(photoDisposable);actionsDisposable.add(photoAction)
    }
    func remove() {let profileSaveAction=ActiveAction();let birthdaySaveAction=ActiveAction();let actionsDisposable=self.actionsDisposable;let action:()->Void=__REMOVAL__;action()}
    deinit {let profileSaveAction=ActiveAction();let birthdaySaveAction=ActiveAction();let actionsDisposable=self.actionsDisposable;let action:()->Void=__DEINIT__;action()}
}
final class ProfilePhotoTests:XCTestCase {
    override func setUp() {Prep.sources=[:];Prep.calls=[];Editors.shown=[];Editors.invalid=false;Editors.onShow=nil}
    func prep(_ name:String)->Source<String,NoError> {let p=Source<String,NoError>();Prep.sources[name]=p;return p}
    func open(_ screen:Screen,_ name:String="a")->Editor {let p=prep(name);screen.updatePhoto(.single(NSImage(name)));p.send("/"+name);return Editors.shown.last!}
    func testPendingImageCancelled() {let s=Screen();let image=Source<NSImage,NoError>();let p=prep("a");s.updatePhoto(image.signal);s.cancel();image.send(NSImage("a"));XCTAssertEqual(image.disposals,1);XCTAssertEqual(p.starts,0)}
    func testPendingPreparationCancelled() {let s=Screen();let p=prep("a");s.updatePhoto(.single(NSImage("a")));s.cancel();p.send("/a");XCTAssertTrue(Editors.shown.isEmpty);XCTAssertEqual(p.disposals,1)}
    func testRemovalCancelsPreparation() {let s=Screen();let p=prep("a");s.updatePhoto(.single(NSImage("a")));s.remove();p.send("/a");XCTAssertTrue(Editors.shown.isEmpty);XCTAssertEqual(p.disposals,1)}
    func testNewPhotoCancelsOlderPreparation() {let s=Screen();let a=prep("a"),b=prep("b");s.updatePhoto(.single(NSImage("a")));s.updatePhoto(.single(NSImage("b")));b.send("/b");a.send("/a");XCTAssertEqual(Editors.shown.map(\.path),["/b"]);XCTAssertEqual(a.disposals,1)}
    func testVideoCancelsOlderPhotoPreparation() {let s=Screen();let p=prep("a");s.updatePhoto(.single(NSImage("a")));let video=Source<VideoAvatarGeneratorState,NoError>();s.updateVideo(video.signal);p.send("/a");XCTAssertTrue(Editors.shown.isEmpty);XCTAssertEqual(p.disposals,1);XCTAssertEqual(video.disposals,0)}
    func testNewPhotoCancelsVideoImmediately() {let s=Screen();let video=Source<VideoAvatarGeneratorState,NoError>();s.updateVideo(video.signal);_ = prep("a");s.updatePhoto(.single(NSImage("a")));XCTAssertEqual(video.disposals,1)}
    func testNewPhotoCancelsOldEditorImmediately() {let s=Screen();let editor=open(s);_ = prep("b");s.updatePhoto(.single(NSImage("b")));editor.accept();XCTAssertTrue(s.context.engine.accountData.uploads.isEmpty);XCTAssertEqual(editor.output.disposals,1)}
    func testNewPhotoCancelsOldUploadImmediately() {let s=Screen();let editor=open(s);editor.accept();let upload=s.context.engine.accountData.uploads[0];_ = prep("b");s.updatePhoto(.single(NSImage("b")));XCTAssertEqual(upload.source.disposals,1)}
    func testRepeatedImagesOpenOneEditor() {let s=Screen();let image=Source<NSImage,NoError>();let p=prep("a");s.updatePhoto(image.signal);image.send(NSImage("a"));p.send("/a");image.send(NSImage("a"));p.send("/other");XCTAssertEqual(Editors.shown.count,1)}
    func testRepeatedPreparedPathsOpenOneEditor() {let s=Screen();let p=prep("a");s.updatePhoto(.single(NSImage("a")));p.send("/a");p.send("/other");XCTAssertEqual(Editors.shown.count,1)}
    func testRepeatedEditorResultsUploadOnce() {let s=Screen();let e=open(s);e.accept();e.accept("/new");XCTAssertEqual(s.context.engine.accountData.uploads.count,1)}
    func testCancelEditorPreventsUpload() {let s=Screen();let e=open(s);s.cancel();e.accept();XCTAssertTrue(s.context.engine.accountData.uploads.isEmpty)}
    func testCancelUploadClearsProgress() {let s=Screen();let e=open(s);e.accept();let u=s.context.engine.accountData.uploads[0];s.cancel();XCTAssertNil(s.state.value.photo);XCTAssertEqual(u.source.disposals,1);u.source.send(.progress(0.7));XCTAssertNil(s.state.value.photo)}
    func testSuccessfulUploadClearsProgress() {let s=Screen();let e=open(s);e.accept();let u=s.context.engine.accountData.uploads[0];u.source.send(.progress(0.4));XCTAssertEqual(s.state.value.photo?.progress,0.4);u.source.send(.complete);u.source.finish();XCTAssertNil(s.state.value.photo)}
    func testFailedUploadClearsProgressAndAllowsRetry() {let s=Screen();open(s).accept();s.context.engine.accountData.uploads[0].source.fail(.generic);XCTAssertNil(s.state.value.photo);open(s,"b").accept();XCTAssertEqual(s.context.engine.accountData.uploads.count,2)}
    func testInvalidImageDoesNotUpload() {let s=Screen();Editors.invalid=true;let p=prep("a");s.updatePhoto(.single(NSImage("a")));p.send("/a");XCTAssertTrue(Editors.shown.isEmpty);XCTAssertTrue(s.context.engine.accountData.uploads.isEmpty)}
    func testEmptyPreparationDoesNotPresent() {let s=Screen();let p=prep("a");s.updatePhoto(.single(NSImage("a")));p.finish();XCTAssertTrue(Editors.shown.isEmpty)}
    func testRemovedScreenCannotStartNewPhoto() {let s=Screen();s.remove();let p=prep("a");s.updatePhoto(.single(NSImage("a")));p.send("/a");XCTAssertEqual(p.starts,0);XCTAssertTrue(Editors.shown.isEmpty)}
    func testRetainedPreparationDoesNotRetainContextAfterDeinit() {var s:Screen?=Screen();let p=prep("a");s!.updatePhoto(.single(NSImage("a")));weak var context=s!.context;s=nil;XCTAssertNil(context);XCTAssertEqual(p.disposals,1);p.send("/a");XCTAssertTrue(Editors.shown.isEmpty)}
    func testSynchronousPreparationKeepsEditorSubscription() {let s=Screen();let p=prep("a");p.onStart={$0.putNext("/a");$0.putCompletion()};s.updatePhoto(.single(NSImage("a")));let e=Editors.shown[0];XCTAssertEqual(e.output.disposals,0);e.accept();XCTAssertEqual(s.context.engine.accountData.uploads.count,1)}
    func testCancellationDuringPresentationPreventsUpload() {let s=Screen();Editors.onShow={_ in s.cancel()};let e=open(s);e.accept();XCTAssertTrue(s.context.engine.accountData.uploads.isEmpty)}
    func testReplacementDuringPresentationKeepsNewOperation() {let s=Screen();let b=prep("b");Editors.onShow={e in if e.path=="/a" {s.updatePhoto(.single(NSImage("b")))}};let e=open(s);e.accept();b.send("/b");XCTAssertTrue(s.context.engine.accountData.uploads.isEmpty);XCTAssertEqual(b.disposals,1);Editors.shown.last?.accept();XCTAssertEqual(s.context.engine.accountData.uploads.map(\.path),["/edited"])}
    func testCancelDuringInitialProgressDoesNotStartUpload() {let s=Screen();let e=open(s);s.state.onUpdate={if s.state.value.photo != nil {s.cancel()}};e.accept();XCTAssertTrue(s.context.engine.accountData.uploads.isEmpty);XCTAssertNil(s.state.value.photo)}
    func testSynchronousUploadCancelDoesNotRestoreOldSubscription() {let s=Screen();s.context.engine.accountData.onStart={_ in s.cancel()};open(s).accept();let u=s.context.engine.accountData.uploads[0];XCTAssertEqual(u.source.disposals,1);XCTAssertNil(s.state.value.photo)}
    func testDuplicateVideoCompletionStartsOneUpload() {let s=Screen();let v=Source<VideoAvatarGeneratorState,NoError>();s.updateVideo(v.signal);v.send(.complete(thumb:"/thumb",video:"/video",keyFrame:nil));v.send(.complete(thumb:"/thumb",video:"/video",keyFrame:nil));XCTAssertEqual(s.context.engine.peers.uploads.count,1);XCTAssertEqual(s.context.engine.peers.uploads[0].source.disposals,0)}
    func testProgressAfterVideoCompletionDoesNotCancelUpload() {let s=Screen();let v=Source<VideoAvatarGeneratorState,NoError>();s.updateVideo(v.signal);v.send(.complete(thumb:"/thumb",video:"/video",keyFrame:nil));v.send(.progress(0.9));XCTAssertEqual(s.context.engine.peers.uploads[0].source.disposals,0)}
    func testVideoWithoutStartEventStillShowsProgress() {let s=Screen();let v=Source<VideoAvatarGeneratorState,NoError>();s.updateVideo(v.signal);v.send(.complete(thumb:"/thumb",video:"/video",keyFrame:nil));XCTAssertEqual(s.state.value.photo?.progress,0.2);s.context.engine.peers.uploads[0].source.send(.progress(0.5));XCTAssertEqual(s.state.value.photo?.progress,0.6)}
    func testVideoGeneratorEndingBeforeResultClearsProgress() {let s=Screen();let v=Source<VideoAvatarGeneratorState,NoError>();s.updateVideo(v.signal);v.send(.start(thumb:"/thumb"));v.send(.progress(0.5));v.finish();XCTAssertNil(s.state.value.photo)}
    func testVideoErrorClearsProgress() {let s=Screen();let v=Source<VideoAvatarGeneratorState,NoError>();s.updateVideo(v.signal);v.send(.start(thumb:"/thumb"));v.send(.error);XCTAssertNil(s.state.value.photo);XCTAssertTrue(s.context.engine.peers.uploads.isEmpty)}
    func testCancelDuringVideoInitialProgressDoesNotUpload() {let s=Screen();let v=Source<VideoAvatarGeneratorState,NoError>();s.updateVideo(v.signal);s.state.onUpdate={if s.state.value.photo != nil {s.cancel()}};v.send(.complete(thumb:"/thumb",video:"/video",keyFrame:nil));XCTAssertTrue(s.context.engine.peers.uploads.isEmpty)}
    func testCancelDuringVideoStartDisposesGenerator() {let s=Screen();let v=Source<VideoAvatarGeneratorState,NoError>();s.updateVideo(v.signal);s.state.onUpdate={if s.state.value.photo != nil {s.cancel()}};v.send(.start(thumb:"/thumb"));v.send(.complete(thumb:"/thumb",video:"/video",keyFrame:nil));XCTAssertTrue(s.context.engine.peers.uploads.isEmpty);XCTAssertEqual(v.disposals,1)}
    func testRemovedScreenCannotStartVideoGenerator() {let s=Screen();s.remove();let v=Source<VideoAvatarGeneratorState,NoError>();s.updateVideo(v.signal);XCTAssertEqual(v.starts,0)}
    func testNewOperationDuringOldDisposalIsNotOverwritten() {let s=Screen();let a=prep("a"),b=prep("b"),c=prep("c");s.updatePhoto(.single(NSImage("a")));a.onDispose={s.updatePhoto(.single(NSImage("c")))};s.updatePhoto(.single(NSImage("b")));XCTAssertEqual(b.starts,0);c.send("/c");Editors.shown.last?.accept();XCTAssertEqual(s.context.engine.accountData.uploads.count,1)}
    func testCancelPreservesNewProgressStartedByDisposal() {let s=Screen();let a=prep("a");s.updatePhoto(.single(NSImage("a")));let v=Source<VideoAvatarGeneratorState,NoError>();v.onStart={$0.putNext(.start(thumb:"/thumb"))};a.onDispose={s.updateVideo(v.signal)};s.cancel();XCTAssertNotNil(s.state.value.photo);XCTAssertEqual(v.disposals,0)}

    func testUploadStateDoesNotRetainItselfAfterScreenDeinit() {var s:Screen?=Screen();let e=open(s!);e.accept();weak var state=s!.state;let data=s!.context.engine.accountData;s=nil;XCTAssertNil(state);XCTAssertEqual(data.uploads[0].source.disposals,1)}
    func testRetainedProgressCancelDoesNotRetainState() {var s:Screen?=Screen();open(s!).accept();let cancel=s!.state.value.photo!.cancel;weak var state=s!.state;s=nil;XCTAssertNil(state);cancel()}

}
