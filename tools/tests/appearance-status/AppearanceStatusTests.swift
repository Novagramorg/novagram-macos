import Foundation
import SwiftSignalKit
import XCTest

struct MediaId: Equatable { let id: Int64 }
final class TelegramMediaFile { let fileId: MediaId; var mimeType = "emoji"; var isCustomEmoji = true; var dimensions:Dimensions?; let resource=0; init(_ id: Int64 = 10) { fileId = .init(id:id) }; func _parse() -> TelegramMediaFile { self } }
struct PeerEmojiStatus: Equatable { enum Content: Equatable { case emoji(fileId:Int64), starGift(id:Int64,fileId:Int64,title:String,slug:String,patternFileId:Int64,innerColor:Int32,outerColor:Int32,patternColor:Int32,textColor:Int32) }; let content: Content; let expirationDate:Int32?; var fileId:Int64 { switch content { case let .emoji(id):return id; case let .starGift(_,id,_,_,_,_,_,_,_):return id } } }
enum NameColor: Equatable { case blue, other(Int32) }
enum PeerColor: Equatable { case preset(NameColor); var nameColor:NameColor? { if case let .preset(color)=self { return color }; return nil }; func getUpdate(_ id:Int64?) -> Int { 0 } }
class Peer { let id:Int; var emojiStatus:PeerEmojiStatus?; var nameColor:PeerColor? = .preset(.blue); var profileColor:NameColor?; var backgroundEmojiId:Int64?; var profileBackgroundEmojiId:Int64?; init(_ id:Int = 1,status:PeerEmojiStatus? = nil) { self.id=id; emojiStatus=status } }
final class TelegramUser:Peer {}
final class TelegramChannel:Peer {}
struct EnginePeer { let peer:Peer; init(_ peer:Peer) { self.peer=peer }; var id:Int { peer.id }; var emojiStatus:PeerEmojiStatus? { peer.emojiStatus }; var nameColor:PeerColor? { peer.nameColor }; func _asPeer()->Peer { peer } }
enum StarGift {
    struct UniqueGift {
        enum Owner:Equatable { case peerId(Int), address(String); var peerId:Int? { if case let .peerId(id)=self { return id };return nil } }
        enum Attribute { case backdrop(String,Int,Int32,Int32,Int32,Int32,Int), other }
        var id:Int64 = 100; let title = "gift", slug = "gift-1"; var owner:Owner? = .peerId(1); var hostPeerId:Int?; var file:TelegramMediaFile? = TelegramMediaFile(10); var pattern:TelegramMediaFile? = TelegramMediaFile(20); var attributes:[Attribute] = [.backdrop("bg",0,1,2,3,4,0)]
    }
}
enum RpcError { case generic }
final class Request<T,E> { let subscriber:Subscriber<T,E>; var disposed=false; var onDispose:(()->Void)?; init(_ s:Subscriber<T,E>) { subscriber=s }; func send(_ value:T) { subscriber.putNext(value) }; func complete() { subscriber.putCompletion() }; func fail(_ e:E) { subscriber.putError(e) }; func dispose() { if !disposed { disposed=true; onDispose?() } } }
struct Call:Equatable { let peer:Int; let file:Int64?; let gift:Int64?; let expiry:Int32? }
final class AccountData {
    var calls:[Call]=[]; var requests:[Request<Never,RpcError>]=[]; var colors:[Request<Void,RpcError>]=[]; var synchronous:Bool?
    func request(_ call:Call)->Signal<Never,RpcError> { Signal { s in let r=Request(s);self.calls.append(call);self.requests.append(r);if let result=self.synchronous { if result {r.complete()} else {r.fail(.generic)} };return ActionDisposable {r.dispose()} } }
    func setEmojiStatusWithResult(file:TelegramMediaFile?,expirationDate:Int32?)->Signal<Never,RpcError> { request(.init(peer:1,file:file?.fileId.id,gift:nil,expiry:expirationDate)) }
    func setStarGiftStatusWithResult(starGift:StarGift.UniqueGift,expirationDate:Int32?)->Signal<Never,RpcError> { request(.init(peer:1,file:starGift.file?.fileId.id,gift:starGift.id,expiry:expirationDate)) }
    func setStarGiftStatus(starGift:StarGift.UniqueGift,expirationDate:Int32?)->Signal<Never,NoError> { setStarGiftStatusWithResult(starGift:starGift,expirationDate:expirationDate) |> `catch` {_ in .complete()} }
    func updateNameColorAndEmoji(nameColor:Int,profileColor:NameColor?,profileBackgroundEmojiId:Int64?)->Signal<Void,RpcError> { Signal { s in let r=Request(s); self.colors.append(r);return ActionDisposable {r.dispose()} } }
}
final class Peers {
    var colors:[Request<Void,RpcError>]=[];var packs:[Request<Void,RpcError>]=[]
    func updatePeerNameColorAndEmoji(peerId:Int,nameColor:NameColor,backgroundEmojiId:Int64?,profileColor:NameColor?,profileBackgroundEmojiId:Int64?)->Signal<Void,RpcError> {Signal {s in let r=Request(s);self.colors.append(r);return ActionDisposable {r.dispose()}}}
    func updateGroupSpecificEmojiset(peerId:Int,info:Int?)->Signal<Void,RpcError> {Signal {s in let r=Request(s);self.packs.append(r);return ActionDisposable {r.dispose()}}}

    var calls:[Call]=[]; var requests:[Request<Never,RpcError>]=[]
    func request(_ call:Call)->Signal<Never,RpcError> { Signal {s in let r=Request(s);self.calls.append(call);self.requests.append(r);return ActionDisposable {r.dispose()} } }
    func updatePeerEmojiStatus(peerId:Int,fileId:Int64?,expirationDate:Int32?)->Signal<Never,RpcError> { request(.init(peer:peerId,file:fileId,gift:nil,expiry:expirationDate)) }
    func updatePeerStarGiftStatus(peerId:Int,starGift:StarGift.UniqueGift,expirationDate:Int32?)->Signal<Never,RpcError> { request(.init(peer:peerId,file:starGift.file?.fileId.id,gift:starGift.id,expiry:expirationDate)) }
}
struct Dimensions {init(_ size:CGSize) {}}
struct WallpaperFile:Equatable {let file:TelegramMediaFile;let settings:Int;static func ==(l:Self,r:Self)->Bool {l.file.fileId == r.file.fileId && l.settings==r.settings}}
enum Wallpaper:Equatable {case file(WallpaperFile),builtin;static func image(_ reps:[TelegramMediaImageRepresentation],_ settings:Int)->Wallpaper {.builtin}}
struct TelegramMediaImageRepresentation {init(dimensions:Dimensions,resource:Int,progressiveSizes:[Int],immediateThumbnailData:Data?,hasVideo:Bool,isPersonal:Bool) {}}
enum UploadContent {case wallpaper(wallpaper:Wallpaper,forBoth:Bool)}
final class Uploads {var count=0;func add(peerId:Int,content:UploadContent) {count+=1}}
final class Account {let pendingPeerMediaUploadManager=Uploads()}
final class Themes {var requests:[Request<Never,RpcError>]=[];func setChatWallpaper(peerId:Int,wallpaper:Wallpaper?,forBoth:Bool)->Signal<Never,RpcError> {Signal {s in let r=Request(s);self.requests.append(r);return ActionDisposable {r.dispose()}}}}
final class Engine {let accountData=AccountData();let peers=Peers();let themes=Themes()}

final class InlinePacks {
    var requests:[Request<TelegramMediaFile?,NoError>]=[]; var ids:[Int64]=[]; var automatic=true
    func load(fileId:Int64)->Signal<TelegramMediaFile?,NoError> { Signal {s in let r=Request(s);self.requests.append(r);self.ids.append(fileId);if self.automatic {r.send(TelegramMediaFile(fileId));r.complete()};return ActionDisposable {r.dispose()} } }
}
final class Window {var errors=0}
protocol AccountContextProtocol:AnyObject {var peerId:Int {get};var engine:Engine {get};var inlinePacksContext:InlinePacks {get}}
final class Context:AccountContextProtocol {let peerId=1;let engine=Engine();let account=Account();let inlinePacksContext=InlinePacks();let window=Window();var timestamp:Int32=1_700_000_000}
struct Strings {let unknownError="Error"}
func strings()->Strings {Strings()}
func showModalText(for window:Window,text:String) {window.errors+=1}
final class Queue {static let main=Queue();var jobs:[()->Void]=[];static func mainQueue()->Queue {main};func justDispatch(_ f:@escaping()->Void) {jobs.append(f)};func drain() {while !jobs.isEmpty {jobs.removeFirst()()}}}
func deliverOnMainQueue<T,E>(_ signal:Signal<T,E>)->Signal<T,E> {signal}
final class Progress {static var pending:[MetaDisposable]=[];static func reset() {pending.forEach {$0.dispose()};pending.removeAll()}}
func showModalProgress<T,E>(signal:Signal<T,E>,for window:Window,shouldPresent:@escaping()->Bool={true})->Signal<T,E> {Signal {s in let d=MetaDisposable();Progress.pending.append(d);d.set(signal.start(next:{s.putNext($0)},error:{s.putError($0)},completed:{s.putCompletion()}));return d}}
__HELPERS__
struct State {
    var peer:EnginePeer;var selected:PeerColor? = .preset(.blue);var selected_profile:PeerColor?;var backgroundEmojiId:Int64?;var backgroundEmojiId_profile:Int64?;var emojiStatus:PeerEmojiStatus?;var emojiStatusGift:StarGift.UniqueGift?;var selected_Gift:StarGift.UniqueGift?;var wallpaper:Wallpaper?;var actualWallpaper:Wallpaper?;var saving=false;var emojiPack:Int?;var actualEmojiPack:Int?
    init(_ peer:Peer=TelegramUser(),status:PeerEmojiStatus?=nil,gift:StarGift.UniqueGift?=nil) {self.peer=EnginePeer(peer);self.emojiStatus=status;self.emojiStatusGift=gift}
    __SAME__
}
final class Collector {var state:State?;var bought:[Int64]=[];init(_ state:State) {self.state=state};func getData()->State? {state};func buyAndApply(_ gift:StarGift.UniqueGift) {bought.append(gift.id)}}
final class View {weak var window:Window?;init(_ window:Window) {self.window=window}}
final class ChildController {var willAppear:((ChildController)->Void)?;var didAppear:((ChildController)->Void)?;var willDisappear:((ChildController)->Void)?}
final class Parent {
    let peer:Peer;let context:Context;let view:View;let profileData:Collector;let nameData:Collector;let saveAction=SelectColorSaveAction();let profileController=ChildController();let nameController=ChildController();var returns=0
    init(context:Context=Context(),peer:Peer=TelegramUser(),status:PeerEmojiStatus?=nil,gift:StarGift.UniqueGift?=nil) {self.peer=peer;self.context=context;view=View(context.window);profileData=Collector(State(peer,status:status,gift:gift));nameData=Collector(State(peer));__LIFECYCLE__}
    func isLoaded()->Bool {true};func executeReturn() {returns+=1};func disappear() {profileController.willDisappear?(profileController);view.window=nil};func appear() {view.window=context.window;profileController.willAppear?(profileController);profileController.didAppear?(profileController)}
    __PARENT__
}
final class Observation {var errors=0;var completed=0;var disposable:Disposable?;func start<E>(_ signal:Signal<Never,E>) {disposable=signal.start(error:{[weak self] _ in self?.errors+=1},completed:{[weak self] in self?.completed+=1})};deinit {disposable?.dispose()}}
func child(context:Context,state:State)->Observation {let peerId=state.peer.id;let emojiStatus=state.emojiStatus;let emojiStatusGift=state.emojiStatusGift;var signals:[Signal<Never,__CHILD_SIGNAL_TYPE__>]=[];__CHILD__;let o=Observation();o.start(combineLatest(signals) |> ignoreValues);return o}
struct Sticker {let file:TelegramMediaFile}
final class Emojis {var closes=0;func closePopover() {closes+=1}}
final class Interactions {var selectColorSendAnimatedEmoji:((Sticker,StarGift.UniqueGift?,Int?,Int32?,CGRect?)->Void)?}
func accountPicker(context:Context,stateValue:Atomic<State>,file:TelegramMediaFile,gift:StarGift.UniqueGift?=nil,timeout:Int32?=nil) {let updateState:((State)->State)->Void={f in _=stateValue.modify(f)};__PICKER__;callback(file,gift,timeout,nil)}
func channelPicker(context:Context,stateValue:Atomic<State>,file:TelegramMediaFile,gift:StarGift.UniqueGift?=nil,timeout:Int32?=nil) {let updateState:((State)->State)->Void={f in _=stateValue.modify(f)};let emojis=Emojis();let interactions=Interactions();__CHANNEL_PICKER__;interactions.selectColorSendAnimatedEmoji?(Sticker(file:file),gift,nil,timeout,nil)}
func emoji(_ id:Int64=10,expiry:Int32?=nil)->PeerEmojiStatus {.init(content:.emoji(fileId:id),expirationDate:expiry)}
func collectible(_ id:Int64=100,expiry:Int32?=nil)->PeerEmojiStatus {.init(content:.starGift(id:id,fileId:10,title:"gift",slug:"gift-1",patternFileId:20,innerColor:1,outerColor:2,patternColor:3,textColor:4),expirationDate:expiry)}
enum Source {case account(Peer),channel(Peer),group(Peer)}
final class SingleController {let view:View;var willAppear:((SingleController)->Void)?;var willDisappear:((SingleController)->Void)?;var onDeinit:(()->Void)?;init(_ window:Window) {view=View(window)};func isLoaded()->Bool {true};func close() {willDisappear?(self);view.window=nil};deinit {onDeinit?()}}
final class SingleScreen {
    let context:Context;let stateValue:Atomic<State>;let saveAction=SelectColorSaveAction();let actionsDisposable=DisposableSet();var controller:SingleController?;var closes=0;var successes=0
    init(peer:Peer=TelegramUser(),status:PeerEmojiStatus?=nil,gift:StarGift.UniqueGift?=nil) {
        let context=Context();self.context=context;stateValue=Atomic(value:State(peer,status:status,gift:gift));let controller=SingleController(context.window);self.controller=controller
        let saveAction=self.saveAction;let actionsDisposable=self.actionsDisposable
        __SINGLE_HOOKS__
    }
    func apply() {
        guard let controller, let window=controller.view.window else {return}
        let context=self.context;let saveAction=self.saveAction;let actionsDisposable=self.actionsDisposable;let stateValue=self.stateValue;let state=stateValue.with {$0};let peerId=state.peer.id
        let source:Source=state.peer._asPeer() is TelegramChannel ? .channel(state.peer._asPeer()) : .account(state.peer._asPeer())
        let nameColor=state.selected ?? .preset(.blue);let backgroundEmojiId=state.backgroundEmojiId;let profileColor=state.selected_profile;let profileBackgroundEmojiId=state.backgroundEmojiId_profile
        let emojiStatus=state.emojiStatus;let emojiStatusGift=state.emojiStatusGift;let wallpaper=state.wallpaper;let actualWallpaper=state.actualWallpaper;let emojiPack=state.emojiPack;let actualEmojiPack=state.actualEmojiPack
        let updateState:((State)->State)->Void={f in _=stateValue.modify(f)}
        let close:(()->Void)? = { [weak self] in self?.closes+=1;_=stateValue.modify {s in var s=s;s.saving=false;return s} }
        __REQUEST__
        request { [weak self] in self?.successes+=1 }
    }
    var saving:Bool {stateValue.with {$0.saving}}
}
final class AppearanceStatusTests:XCTestCase {
    override func tearDown() {Progress.reset();Queue.main.drain()}
    func testParentNormalUsesAccountApiOnce() {let p=Parent(status:emoji());p.collectAndInvoke();XCTAssertEqual(p.context.engine.accountData.calls.count,1);XCTAssertTrue(p.context.engine.peers.calls.isEmpty)}
    func testParentClearCallsAccountApi() {let p=Parent(peer:TelegramUser(status:emoji()),status:nil);p.collectAndInvoke();XCTAssertEqual(p.context.engine.accountData.calls,[.init(peer:1,file:nil,gift:nil,expiry:nil)])}
    func testParentGiftUsesResultApi() {let p=Parent(status:collectible(),gift:.init());p.collectAndInvoke();p.context.engine.accountData.requests[0].fail(.generic);XCTAssertEqual(p.returns,0);XCTAssertEqual(p.context.window.errors,1)}
    func testParentWaitsForAllRequests() {let p=Parent(status:emoji());p.collectAndInvoke();XCTAssertEqual(p.returns,0);p.context.engine.accountData.colors[0].complete();XCTAssertEqual(p.returns,0);p.context.engine.accountData.requests.first?.complete();XCTAssertEqual(p.returns,1)}
    func testParentColorFailureStaysAndReportsError() {let p=Parent();p.collectAndInvoke();p.context.engine.accountData.colors[0].fail(.generic);XCTAssertEqual(p.returns,0);XCTAssertEqual(p.context.window.errors,1)}
    func testParentStatusFailureCancelsOtherRequests() {let p=Parent(status:emoji());p.collectAndInvoke();p.context.engine.accountData.requests.first?.fail(.generic);XCTAssertEqual(p.returns,0);XCTAssertEqual(p.context.window.errors,1);XCTAssertTrue(p.context.engine.accountData.colors[0].disposed)}
    func testParentDuplicateApplyCoalesces() {let p=Parent(status:emoji());p.collectAndInvoke();p.collectAndInvoke();XCTAssertEqual(p.context.engine.accountData.colors.count,1)}
    func testParentFailureAllowsRetry() {let p=Parent();p.collectAndInvoke();p.context.engine.accountData.colors[0].fail(.generic);p.collectAndInvoke();XCTAssertEqual(p.context.engine.accountData.colors.count,2);XCTAssertEqual(p.returns,0)}
    func testParentDisappearCancels() {let p=Parent(status:emoji());p.collectAndInvoke();p.disappear();XCTAssertTrue(p.context.engine.accountData.colors[0].disposed);p.context.engine.accountData.requests.first?.complete();XCTAssertEqual(p.returns,0)}
    func testParentReappearCanSaveAgain() {let p=Parent();p.collectAndInvoke();p.disappear();p.appear();p.collectAndInvoke();XCTAssertEqual(p.context.engine.accountData.colors.count,2);XCTAssertEqual(p.returns,0)}
    func testParentClosedCannotStart() {let p=Parent();p.disappear();p.collectAndInvoke();XCTAssertTrue(p.context.engine.accountData.colors.isEmpty)}
    func testParentReleaseCancelsWithoutRetainingContext() {var p:Parent?=Parent(status:emoji());let engine=p!.context.engine;weak var context=p!.context;weak var owner=p;p!.collectAndInvoke();p=nil;XCTAssertNil(owner);XCTAssertNil(context);XCTAssertTrue(engine.accountData.colors[0].disposed)}
    func testParentOldCleanupCannotCancelRetry() {let p=Parent();p.collectAndInvoke();p.context.engine.accountData.colors[0].fail(.generic);p.collectAndInvoke();Queue.main.drain();p.collectAndInvoke();XCTAssertEqual(p.context.engine.accountData.colors.count,2);XCTAssertFalse(p.context.engine.accountData.colors[1].disposed)}
    func testParentProgressCancellationIsSilent() {let p=Parent();p.collectAndInvoke();Progress.pending.first?.dispose();Queue.main.drain();XCTAssertEqual(p.returns,0);XCTAssertEqual(p.context.window.errors,0);p.collectAndInvoke();XCTAssertEqual(p.context.engine.accountData.colors.count,2)}
    func testParentForeignPeerCannotChangeAccount() {let p=Parent(peer:TelegramUser(2),status:emoji());p.collectAndInvoke();XCTAssertTrue(p.context.engine.accountData.colors.isEmpty);XCTAssertTrue(p.context.engine.peers.calls.isEmpty)}
    func testChildAccountNormalUsesAccountApi() {let c=Context();let o=child(context:c,state:State(status:emoji()));XCTAssertEqual(c.engine.accountData.calls.count,1);XCTAssertTrue(c.engine.peers.calls.isEmpty);withExtendedLifetime(o){}}
    func testChildChannelNormalSendsOneRequest() {let c=Context();let o=child(context:c,state:State(TelegramChannel(20),status:emoji()));XCTAssertEqual(c.engine.peers.calls.count,1);XCTAssertTrue(c.engine.accountData.calls.isEmpty);withExtendedLifetime(o){}}
    func testChildChannelGiftNeverMutatesAccountOrSendsPlainEmoji() {let c=Context();var g=StarGift.UniqueGift();g.owner = .peerId(20);let o=child(context:c,state:State(TelegramChannel(20),status:collectible(),gift:g));XCTAssertEqual(c.engine.peers.calls,[.init(peer:20,file:10,gift:100,expiry:nil)]);XCTAssertTrue(c.engine.accountData.calls.isEmpty);withExtendedLifetime(o){}}
    func testChildClearAccountUsesAccountApi() {let c=Context();let o=child(context:c,state:State(TelegramUser(status:emoji())));XCTAssertEqual(c.engine.accountData.calls,[.init(peer:1,file:nil,gift:nil,expiry:nil)]);XCTAssertTrue(c.engine.peers.calls.isEmpty);withExtendedLifetime(o){}}
    func testChildClearChannelOnce() {let c=Context();let o=child(context:c,state:State(TelegramChannel(20,status:emoji())));XCTAssertEqual(c.engine.peers.calls,[.init(peer:20,file:nil,gift:nil,expiry:nil)]);withExtendedLifetime(o){}}
    func testChildRequestFailureIsNotSuccess() {let c=Context();let o=child(context:c,state:State(TelegramChannel(20),status:emoji()));c.engine.peers.requests.forEach {$0.fail(.generic)};XCTAssertEqual(o.errors,1);XCTAssertEqual(o.completed,0)}
    func testChildGiftExpiryPreserved() {let c=Context();let o=child(context:c,state:State(status:collectible(expiry:123),gift:.init()));XCTAssertEqual(c.engine.accountData.calls.last?.expiry,123);withExtendedLifetime(o){}}
    func testChildUnchangedDoesNotSend() {let c=Context();let o=child(context:c,state:State(TelegramUser(status:emoji()),status:emoji()));XCTAssertTrue(c.engine.accountData.calls.isEmpty);XCTAssertTrue(c.engine.peers.calls.isEmpty);XCTAssertEqual(o.completed,1)}
    func testAccountPickerDurationBecomesExpiry() {let c=Context();let s=Atomic(value:State());accountPicker(context:c,stateValue:s,file:TelegramMediaFile(),timeout:60);XCTAssertEqual(s.with {$0.emojiStatus?.expirationDate},1_700_000_060)}
    func testAccountPickerZeroMeansIndefinite() {let c=Context();let s=Atomic(value:State());accountPicker(context:c,stateValue:s,file:TelegramMediaFile(),timeout:0);XCTAssertNil(s.with {$0.emojiStatus?.expirationDate})}
    func testAccountPickerClearRemovesGiftAndStatus() {let c=Context();let s=Atomic(value:State(status:collectible(),gift:.init()));let f=TelegramMediaFile();f.mimeType="bundle/clear";accountPicker(context:c,stateValue:s,file:f);XCTAssertNil(s.with {$0.emojiStatus});XCTAssertNil(s.with {$0.emojiStatusGift})}
    func testAccountPickerPreservesCollectibleIdentity() {let c=Context();let s=Atomic(value:State());accountPicker(context:c,stateValue:s,file:TelegramMediaFile(),gift:.init(),timeout:60);XCTAssertEqual(s.with {$0.emojiStatus},collectible(expiry:1_700_000_060));XCTAssertEqual(s.with {$0.emojiStatusGift?.id},100)}
    func testAccountPickerRejectsInvalidDurations() {let c=Context();for t:Int32 in [-1,Int32.max] {let s=Atomic(value:State(status:emoji(99)));accountPicker(context:c,stateValue:s,file:TelegramMediaFile(),timeout:t);XCTAssertEqual(s.with {$0.emojiStatus},emoji(99))}}
    func testChannelPickerDurationBecomesExpiry() {let c=Context();let s=Atomic(value:State(TelegramChannel(20)));channelPicker(context:c,stateValue:s,file:TelegramMediaFile(),timeout:60);XCTAssertEqual(s.with {$0.emojiStatus?.expirationDate},1_700_000_060)}
    func testChannelPickerKeepsGiftIdentity() {let c=Context();let s=Atomic(value:State(TelegramChannel(20)));var g=StarGift.UniqueGift();g.owner = .peerId(20);channelPicker(context:c,stateValue:s,file:TelegramMediaFile(),gift:g);XCTAssertEqual(s.with {$0.emojiStatus},collectible());XCTAssertEqual(s.with {$0.emojiStatusGift?.id},100)}
    func testDirtyComparisonIncludesExpiry() {let peer=TelegramUser(status:emoji(expiry:100));XCTAssertFalse(State(peer,status:emoji(expiry:200)).isSame(to:peer))}
    func testDirtyComparisonIncludesGiftIdentity() {let peer=TelegramUser(status:collectible(100));XCTAssertFalse(State(peer,status:collectible(200)).isSame(to:peer))}
    func testDirtyComparisonDistinguishesPlainAndCollectible() {let peer=TelegramUser(status:emoji());XCTAssertFalse(State(peer,status:collectible()).isSame(to:peer))}
    func testHelperFileMissingFailsWithoutClear() {let c=Context();c.inlinePacksContext.automatic=false;let o=Observation();o.start(SelectColorStatusUpdate.request(context:c,peer:EnginePeer(TelegramUser()),status:emoji(),gift:nil));c.inlinePacksContext.requests[0].send(nil);XCTAssertEqual(o.errors,1);XCTAssertTrue(c.engine.accountData.calls.isEmpty)}
    func testHelperEmptyFileLoadFails() {let c=Context();c.inlinePacksContext.automatic=false;let o=Observation();o.start(SelectColorStatusUpdate.request(context:c,peer:EnginePeer(TelegramUser()),status:emoji(),gift:nil));c.inlinePacksContext.requests[0].complete();XCTAssertEqual(o.errors,1)}
    func testHelperWrongFileFails() {let c=Context();c.inlinePacksContext.automatic=false;let o=Observation();o.start(SelectColorStatusUpdate.request(context:c,peer:EnginePeer(TelegramUser()),status:emoji(),gift:nil));c.inlinePacksContext.requests[0].send(TelegramMediaFile(999));XCTAssertEqual(o.errors,1);XCTAssertTrue(c.engine.accountData.calls.isEmpty)}
    func testHelperCancellationDuringLoad() {let c=Context();c.inlinePacksContext.automatic=false;let o=Observation();o.start(SelectColorStatusUpdate.request(context:c,peer:EnginePeer(TelegramUser()),status:emoji(),gift:nil));o.disposable?.dispose();c.inlinePacksContext.requests[0].send(TelegramMediaFile());XCTAssertTrue(c.engine.accountData.calls.isEmpty);XCTAssertTrue(c.inlinePacksContext.requests[0].disposed)}
    func testHelperMissingOrMismatchedGiftFails() {let c=Context();for g:StarGift.UniqueGift? in [nil,StarGift.UniqueGift(id:200)] {let o=Observation();o.start(SelectColorStatusUpdate.request(context:c,peer:EnginePeer(TelegramUser()),status:collectible(),gift:g));XCTAssertEqual(o.errors,1)};XCTAssertTrue(c.engine.accountData.calls.isEmpty)}
    func testHelperHostedGiftAllowed() {let c=Context();var g=StarGift.UniqueGift();g.owner = .address("wallet");g.hostPeerId=1;let o=Observation();o.start(SelectColorStatusUpdate.request(context:c,peer:EnginePeer(TelegramUser()),status:collectible(),gift:g));XCTAssertEqual(c.engine.accountData.calls.last?.gift,100);withExtendedLifetime(o){}}
    func testHelperOtherOwnerGiftFails() {let c=Context();var g=StarGift.UniqueGift();g.owner = .peerId(2);let o=Observation();o.start(SelectColorStatusUpdate.request(context:c,peer:EnginePeer(TelegramUser()),status:collectible(),gift:g));XCTAssertEqual(o.errors,1);XCTAssertTrue(c.engine.accountData.calls.isEmpty)}
    func testHelperMalformedGiftCannotBecomeNormalEmoji() {var g=StarGift.UniqueGift();g.pattern=nil;XCTAssertNil(SelectColorStatusUpdate.selection(file:TelegramMediaFile(),gift:g,timeout:nil,timestamp:100));g.pattern=TelegramMediaFile(20);g.attributes=[];XCTAssertNil(SelectColorStatusUpdate.selection(file:TelegramMediaFile(),gift:g,timeout:nil,timestamp:100))}
    func testHelperMaximumTimestampIsSafe() {XCTAssertEqual(SelectColorStatusUpdate.selection(file:TelegramMediaFile(),gift:nil,timeout:1,timestamp:Int32.max-1)?.status?.expirationDate,Int32.max)}
    func testHelperNonEmojiIsRejected() {let f=TelegramMediaFile();f.isCustomEmoji=false;XCTAssertNil(SelectColorStatusUpdate.selection(file:f,gift:nil,timeout:nil,timestamp:100))}
    func testHelperCloseDuringStartedPreventsSubscription() {let a=SelectColorSaveAction();let c=Context();a.perform(signal:c.engine.accountData.setEmojiStatusWithResult(file:TelegramMediaFile(),expirationDate:nil) |> mapError {_ in .generic},window:c.window,canPresent:{true},started:{a.setActive(false)},failed:{XCTFail()},completed:{XCTFail()});XCTAssertTrue(c.engine.accountData.requests.isEmpty)}
    func testHelperCloseDuringDisposalSuppressesCallbacks() {let a=SelectColorSaveAction();let c=Context();a.perform(signal:c.engine.accountData.setEmojiStatusWithResult(file:TelegramMediaFile(),expirationDate:nil) |> mapError {_ in .generic},window:c.window,canPresent:{true},failed:{XCTFail()},completed:{XCTFail()});c.engine.accountData.requests[0].onDispose={a.setActive(false)};c.engine.accountData.requests[0].complete()}
    func testHelperCancelledCallbackRunsOnce() {let a=SelectColorSaveAction();let c=Context();var count=0;a.perform(signal:.never(),window:c.window,canPresent:{true},cancelled:{count+=1},failed:{XCTFail()},completed:{XCTFail()});a.reset();a.reset();Queue.main.drain();XCTAssertEqual(count,1)}
    func testSingleWaitsForAcknowledgedSave() {let s=SingleScreen(status:emoji());s.apply();XCTAssertTrue(s.saving);XCTAssertEqual(s.closes,0);s.context.engine.accountData.colors[0].complete();XCTAssertEqual(s.closes,0);s.context.engine.accountData.requests.first?.complete();XCTAssertEqual(s.closes,1);XCTAssertEqual(s.successes,1);XCTAssertFalse(s.saving)}
    func testSingleColorFailureClearsLoadingWithoutSuccess() {let s=SingleScreen();s.apply();s.context.engine.accountData.colors[0].fail(.generic);XCTAssertFalse(s.saving);XCTAssertEqual(s.closes,0);XCTAssertEqual(s.successes,0);XCTAssertEqual(s.context.window.errors,1)}
    func testSingleChannelStatusFailureIsReported() {let s=SingleScreen(peer:TelegramChannel(20),status:emoji());s.apply();s.context.engine.peers.colors[0].complete();s.context.engine.peers.requests.forEach {$0.fail(.generic)};XCTAssertFalse(s.saving);XCTAssertEqual(s.closes,0);XCTAssertEqual(s.successes,0);XCTAssertEqual(s.context.window.errors,1)}
    func testSingleCancellationClearsLoading() {let s=SingleScreen();s.apply();Progress.pending.last?.dispose();Queue.main.drain();XCTAssertFalse(s.saving);XCTAssertEqual(s.closes,0);XCTAssertEqual(s.context.window.errors,0)}
    func testSingleNavigationCancelsPendingSave() {let s=SingleScreen();s.apply();s.controller!.close();XCTAssertTrue(s.context.engine.accountData.colors[0].disposed);XCTAssertFalse(s.saving);s.context.engine.accountData.colors[0].complete();XCTAssertEqual(s.successes,0)}
    func testSingleFailureAllowsRetry() {let s=SingleScreen();s.apply();s.context.engine.accountData.colors[0].fail(.generic);s.apply();XCTAssertTrue(s.saving);XCTAssertEqual(s.closes,0);s.context.engine.accountData.colors[1].complete();XCTAssertEqual(s.successes,1)}
    func testSingleEmojiPackFailureIsReported() {let s=SingleScreen(peer:TelegramChannel(20));_=s.stateValue.modify {s in var s=s;s.emojiPack=1;return s};s.apply();s.context.engine.peers.colors[0].complete();s.context.engine.peers.packs[0].fail(.generic);XCTAssertEqual(s.successes,0);XCTAssertEqual(s.context.window.errors,1);XCTAssertFalse(s.saving)}
    func testSingleWallpaperFailureIsReported() {let s=SingleScreen(peer:TelegramChannel(20));_=s.stateValue.modify {s in var s=s;s.wallpaper = .builtin;return s};s.apply();s.context.engine.peers.colors[0].complete();s.context.engine.themes.requests[0].fail(.generic);XCTAssertEqual(s.successes,0);XCTAssertEqual(s.context.window.errors,1);XCTAssertFalse(s.saving)}
    func testSingleControllerReleaseCancelsAndReleasesContext() {var s:SingleScreen?=SingleScreen();let engine=s!.context.engine;weak var controller=s!.controller;weak var context=s!.context;s!.apply();s=nil;XCTAssertNil(controller);XCTAssertNil(context);XCTAssertTrue(engine.accountData.colors[0].disposed)}

}
