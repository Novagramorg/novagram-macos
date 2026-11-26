import Foundation
import SwiftSignalKit
import XCTest

class Peer {func isEqual(_ other:Peer)->Bool {self === other}}
final class TelegramUser:Peer {let firstName:String?;let lastName:String?;let usernames:[Username]=[];let phone:String?=nil;let smallProfileImage:TelegramMediaImageRepresentation?=nil;init(_ first:String="Old",_ last:String="Name") {firstName=first;lastName=last}}
struct Username {let isActive:Bool;let username:String}
struct TelegramMediaImageRepresentation:Equatable {}
struct PeerInfoUpdatingPhotoState:Equatable {}
struct PeerStatusSettings:Equatable {}
struct TelegramBirthday:Equatable {}
struct EnginePeer:Equatable {}
struct Updated_ChatTextInputState:Equatable {}
final class CachedUserData {let about:String?;let peerStatusSettings:PeerStatusSettings?=nil;let birthday:TelegramBirthday?=nil;let businessHours:Int?=nil;let businessLocation:Int?=nil;init(_ about:String?="Old bio") {self.about=about}}
struct PeerView {let peerId:Int;var peers:[Int:Peer];var cachedData:Any?;init(peer:Peer=TelegramUser(),cached:CachedUserData?=CachedUserData()) {peerId=99;peers=[99:peer];cachedData=cached}}
__STATE__
__VALUES__
struct InputDataIdentifier:Hashable {let value:String;init(_ value:String) {self.value=value}}
struct InputDataValue {let stringValue:String?}
let _id_info=InputDataIdentifier("info"),_id_about=InputDataIdentifier("about"),_id_logout=InputDataIdentifier("logout"),_id_username=InputDataIdentifier("username"),_id_phone=InputDataIdentifier("phone")
enum FieldFailure {case shake}
indirect enum InputDataValidation {case fail(Failure);enum Failure {case none,fields([InputDataIdentifier:FieldFailure]),doSomething((@escaping(InputDataValidation)->Void)->Void)}}
final class Queue {static let main=Queue();var jobs:[()->Void]=[];static func mainQueue()->Queue {main};func justDispatch(_ f:@escaping()->Void) {jobs.append(f)};func drain() {while !jobs.isEmpty {jobs.removeFirst()()}}}
func deliverOnMainQueue<T,E>(_ s:Signal<T,E>)->Signal<T,E> {s}
final class Window {var errors=0;var successes=0}
final class View {weak var window:Window?;init(_ window:Window) {self.window=window}}
final class Controller {let view:View;var willAppear:((Controller)->Void)?;var willDisappear:((Controller)->Void)?;var onDeinit:(()->Void)?;init(_ w:Window) {view=View(w)};func isLoaded()->Bool {true};deinit {onDeinit?()}}
final class Progress {static var pending:[MetaDisposable]=[]}
func showModalProgress<T,E>(signal:Signal<T,E>,for window:Window,shouldPresent:@escaping()->Bool={true})->Signal<T,E> {Signal {s in let d=MetaDisposable();Progress.pending.append(d);d.set(signal.start(next:{s.putNext($0)},error:{s.putError($0)},completed:{s.putCompletion()}));return d}}
func showModalText(for window:Window,text:String) {window.errors+=1}
func showModalSuccess(for window:Window,icon:Int,delay:Double)->Signal<Void,NoError> {window.successes+=1;return .complete()}
struct Strings {let unknownError="Error"}
func strings()->Strings {Strings()}
struct Theme {struct Icons {let successModalProgress=0};let icons=Icons()}
let theme=Theme()
extension String {var length:Int {count}}
struct Limits {let about_length_limit_default=10}
enum Limit {case caption(Int)}
final class SettingsNavigationHooks {static let shared=SettingsNavigationHooks();func showPremiumLimit(_ context:Context,_ limit:Limit) {context.limitsShown+=1}}
final class Arguments {func logout() {};func username() {};func changeNumber() {}}
enum APIError {case generic}
final class Request {
    let first:String?;let last:String?;let bio:String?;let subscriber:Subscriber<Void,APIError>;var disposed=false
    init(_ first:String?,_ last:String?,_ bio:String?,_ subscriber:Subscriber<Void,APIError>) {self.first=first;self.last=last;self.bio=bio;self.subscriber=subscriber}
    func accept() {subscriber.putNext(());subscriber.putCompletion()};func reject() {subscriber.putError(.generic)}
}
final class AccountData {
    var requests:[Request]=[];var onStart:((Request)->Void)?
    func updateProfile(firstName:String?,lastName:String?,about:String?)->Signal<Void,APIError> {Signal {s in let r=Request(firstName,lastName,about,s);self.requests.append(r);self.onStart?(r);return ActionDisposable {r.disposed=true}}}
    func updateAccountPeerName(firstName:String,lastName:String)->Signal<Void,NoError> {updateProfile(firstName:firstName,lastName:lastName,about:nil) |> `catch` {_ in .single(())}}
    func updateAbout(about:String?)->Signal<Void,APIError> {updateProfile(firstName:nil,lastName:nil,about:about)}
}
struct Engine {let accountData=AccountData()}
final class Context {let window=Window();let engine=Engine();var isPremium=false;let premiumLimits=Limits();var limitsShown=0}
__HELPER__
final class Screen {
    let context=Context();let profileSaveAction=EditAccountProfileSaveAction();let birthdaySaveAction=EditAccountProfileSaveAction();let stateValue:Atomic<EditInfoState>;var peerView:PeerView?;var controller:Controller?;let actionsDisposable=DisposableSet();let updateNameDisposable=MetaDisposable();var closes=0;var shakes=0
    init(state:EditInfoState=EditInfoState(stateInited:true,firstName:"New",lastName:"Name",about:"Old bio"),peerView:PeerView?=PeerView()) {
        stateValue=Atomic(value:state);self.peerView=peerView;let controller=Controller(context.window);self.controller=controller
        let avatarAcquisition=EditAccountProfileSaveAction();let actionsDisposable=self.actionsDisposable;let profileSaveAction=self.profileSaveAction;let birthdaySaveAction=self.birthdaySaveAction
        actionsDisposable.add(updateNameDisposable)
        __HOOKS__
    }
    func validate(_ data:[InputDataIdentifier:InputDataValue]=[:]) {
        let context=self.context;let profileSaveAction=self.profileSaveAction;let stateValue=self.stateValue;let peerView=self.peerView;let arguments=Arguments();let updateNameDisposable=self.updateNameDisposable
        let getController:(()->Controller?)? = {[weak self] in self?.controller}
        let close:(()->Void)? = {[weak self] in self?.closes+=1}
        let updateState:((EditInfoState)->EditInfoState)->Void = {f in _=stateValue.modify(f)}
        let validation:([InputDataIdentifier:InputDataValue])->InputDataValidation = __VALIDATE__
        consume(validation(data))
    }
    func update(_ data:[InputDataIdentifier:InputDataValue]) {
        let stateValue=self.stateValue;let updateState:((EditInfoState)->EditInfoState)->Void = {f in _=stateValue.modify(f)}
        let update:([InputDataIdentifier:InputDataValue])->InputDataValidation = __UPDATE__
        _=update(data)
    }
    func consume(_ value:InputDataValidation) {switch value {case let .fail(f):switch f {case let .doSomething(action):action {[weak self] in self?.consume($0)};case .fields:shakes+=1;case .none:break}}}
    func disappear() {if let c=controller {c.willDisappear?(c);c.view.window=nil}}
    func appear() {if let c=controller {c.view.window=context.window;c.willAppear?(c)}}
    deinit {actionsDisposable.dispose()}
}
final class ProfileEditorTests:XCTestCase {
    override func setUp() {Progress.pending=[];Queue.mainQueue().drain()}
    func testCombinedSaveUsesOneRequest() {let s=Screen();s.update([_id_about:.init(stringValue:"New bio")]);s.validate();XCTAssertEqual(s.context.engine.accountData.requests.count,1);let r=s.context.engine.accountData.requests[0];XCTAssertEqual(r.first,"New");XCTAssertEqual(r.last,"Name");XCTAssertEqual(r.bio,"New bio")}
    func testNameRejectionDoesNotCloseOrShowSuccess() {let s=Screen();s.validate();s.context.engine.accountData.requests[0].reject();XCTAssertEqual(s.closes,0);XCTAssertEqual(s.context.window.successes,0);XCTAssertEqual(s.context.window.errors,1)}
    func testBioRejectionDoesNotCloseOrShowSuccess() {let s=Screen(state:EditInfoState(stateInited:true,firstName:"Old",lastName:"Name",about:"New bio"));s.validate();s.context.engine.accountData.requests[0].reject();XCTAssertEqual(s.closes,0);XCTAssertEqual(s.context.window.successes,0);XCTAssertEqual(s.context.window.errors,1)}
    func testAcceptedSaveClosesOnce() {let s=Screen();s.validate();XCTAssertEqual(s.closes,0);s.context.engine.accountData.requests[0].accept();XCTAssertEqual(s.closes,1);XCTAssertEqual(s.context.window.successes,1);XCTAssertEqual(s.context.window.errors,0)}
    func testEmptyFirstNameStopsBeforeNetwork() {let s=Screen(state:EditInfoState(stateInited:true,firstName:"",lastName:"Name",about:"Old bio"));s.validate();XCTAssertEqual(s.shakes,1);XCTAssertTrue(s.context.engine.accountData.requests.isEmpty);XCTAssertEqual(s.closes,0)}
    func testWhitespaceFirstNameStopsBeforeNetwork() {let s=Screen(state:EditInfoState(stateInited:true,firstName:" \n ",lastName:"Name",about:"Old bio"));s.validate();XCTAssertEqual(s.shakes,1);XCTAssertTrue(s.context.engine.accountData.requests.isEmpty)}
    func testOversizedBioStopsBeforeNetwork() {let s=Screen();s.update([_id_about:.init(stringValue:"A long biography")]);s.validate([_id_about:.init(stringValue:"A long biography")]);XCTAssertEqual(s.context.limitsShown,1);XCTAssertEqual(s.shakes,1);XCTAssertTrue(s.context.engine.accountData.requests.isEmpty)}
    func testPremiumBioCanExceedDefaultLimit() {let s=Screen();s.context.isPremium=true;s.update([_id_about:.init(stringValue:"A long biography")]);s.validate([_id_about:.init(stringValue:"A long biography")]);XCTAssertEqual(s.context.limitsShown,0);XCTAssertFalse(s.context.engine.accountData.requests.isEmpty)}
    func testDuplicateSaveIsCoalesced() {let s=Screen();s.validate();s.validate();XCTAssertEqual(s.context.engine.accountData.requests.count,1);XCTAssertFalse(s.context.engine.accountData.requests[0].disposed)}
    func testRetryAfterFailure() {let s=Screen();s.validate();s.context.engine.accountData.requests[0].reject();s.validate();XCTAssertEqual(s.context.engine.accountData.requests.count,2);s.context.engine.accountData.requests[1].accept();XCTAssertEqual(s.closes,1);XCTAssertEqual(s.context.window.errors,1)}
    func testDisappearCancelsRequest() {let s=Screen();s.validate();s.disappear();XCTAssertTrue(s.context.engine.accountData.requests[0].disposed);s.context.engine.accountData.requests[0].accept();XCTAssertEqual(s.closes,0);XCTAssertEqual(s.context.window.successes,0)}
    func testNoSaveWhileDisappeared() {let s=Screen();s.disappear();s.validate();XCTAssertTrue(s.context.engine.accountData.requests.isEmpty)}
    func testReappearanceAllowsFreshSave() {let s=Screen();s.validate();s.disappear();s.appear();s.validate();XCTAssertEqual(s.context.engine.accountData.requests.count,2);s.context.engine.accountData.requests[0].accept();XCTAssertEqual(s.closes,0);s.context.engine.accountData.requests[1].accept();XCTAssertEqual(s.closes,1)}
    func testWindowReplacementSuppressesSuccess() {let s=Screen();s.validate();let w=Window();s.controller?.view.window=w;s.context.engine.accountData.requests[0].accept();XCTAssertEqual(s.closes,0);XCTAssertEqual(s.context.window.successes,0)}
    func testMissingPeerViewDoesNotClose() {let s=Screen(peerView:nil);s.validate();XCTAssertTrue(s.context.engine.accountData.requests.isEmpty);XCTAssertEqual(s.closes,0)}
    func testNonUserDoesNotClose() {let s=Screen(peerView:PeerView(peer:Peer()));s.validate();XCTAssertTrue(s.context.engine.accountData.requests.isEmpty);XCTAssertEqual(s.closes,0)}
    func testUnchangedValuesCloseWithoutSuccessToast() {let s=Screen(state:EditInfoState(stateInited:true,firstName:"Old",lastName:"Name",about:"Old bio"));s.validate();XCTAssertEqual(s.closes,1);XCTAssertTrue(s.context.engine.accountData.requests.isEmpty);XCTAssertEqual(s.context.window.successes,0)}
    func testTypedBioWithMissingCacheIsSaved() {let s=Screen(peerView:PeerView(cached:nil));s.update([_id_about:.init(stringValue:"New bio")]);s.validate();XCTAssertTrue(s.context.engine.accountData.requests.contains {$0.bio=="New bio"})}
    func testExplicitEmptyBioWithMissingCacheIsSaved() {let s=Screen(peerView:PeerView(cached:nil));s.update([_id_about:.init(stringValue:"")]);s.validate();XCTAssertTrue(s.context.engine.accountData.requests.contains {$0.bio==""})}
    func testMissingInputDoesNotClearDraftBio() {let s=Screen();s.update([:]);XCTAssertEqual(s.stateValue.with {$0.about},"Old bio")}
    func testDelayedCacheHydratesUntouchedBio() {let state=EditInfoState().withUpdatedPeerView(PeerView(cached:nil));let updated=state.withUpdatedPeerView(PeerView(cached:CachedUserData("Loaded")));XCTAssertEqual(updated.about,"Loaded")}
    func testDelayedCachePreservesTypedBioBeforeInitialPeer() {let state=EditInfoState().withUpdatedAbout("Typed");let updated=state.withUpdatedPeerView(PeerView(cached:CachedUserData("Loaded")));XCTAssertEqual(updated.about,"Typed")}
    func testEditingNameDoesNotPreventBioHydration() {let state=EditInfoState().withUpdatedFirstName("Typed name").withUpdatedInited(true);let updated=state.withUpdatedPeerView(PeerView(cached:CachedUserData("Loaded")));XCTAssertEqual(updated.firstName,"Typed name");XCTAssertEqual(updated.about,"Loaded")}
    func testBioOnlyChangesAffectEquality() {let s=EditInfoState();XCTAssertNotEqual(s,s.withUpdatedAbout("New"))}
    func testBioDraftSurvivesStateCopyMethods() {let s=EditInfoState().withUpdatedAbout("Typed");let copies=[s.withUpdatedInited(true),s.withUpdatedFirstName("X"),s.withUpdatedLastName("Y"),s.withUpdatedUpdatingPhotoState {_ in nil},s.withoutUpdatingPhotoState(),s.withUpdatedAddToException(false),s.withUpdatedPersonalChannel(nil),s.withUpdatedNotes(.init())];for c in copies {let next=c.withUpdatedPeerView(PeerView());XCTAssertEqual(next.about,"Typed")}}
    func testControllerReleaseCancelsWithoutRetainingScreen() {var s:Screen?=Screen();let context=s!.context;s!.validate();weak var weakScreen=s;s=nil;XCTAssertNil(weakScreen);XCTAssertTrue(context.engine.accountData.requests[0].disposed);context.engine.accountData.requests[0].accept();XCTAssertEqual(context.window.successes,0)}
    func testProgressCancellationIsQuietAndAllowsRetry() {let s=Screen();s.validate();Progress.pending.last?.dispose();Queue.mainQueue().drain();XCTAssertEqual(s.context.window.errors,0);XCTAssertEqual(s.closes,0);s.validate();XCTAssertEqual(s.context.engine.accountData.requests.count,2)}
    func testNewBioDraftDuringSaveStaysOpen() {let s=Screen();s.validate();s.update([_id_about:.init(stringValue:"Later bio")]);s.context.engine.accountData.requests[0].accept();XCTAssertEqual(s.closes,0);XCTAssertEqual(s.stateValue.with {$0.about},"Later bio");XCTAssertFalse(s.profileSaveAction.isPending);XCTAssertEqual(s.context.window.successes,1)}
    func testNewNameDraftDuringSaveStaysOpen() {let s=Screen();s.validate();_=s.stateValue.modify {$0.withUpdatedFirstName("Later name")};s.context.engine.accountData.requests[0].accept();XCTAssertEqual(s.closes,0);XCTAssertEqual(s.stateValue.with {$0.firstName},"Later name");XCTAssertFalse(s.profileSaveAction.isPending)}
    func testSynchronousAcceptance() {let s=Screen();s.context.engine.accountData.onStart={$0.accept()};s.validate();Queue.mainQueue().drain();XCTAssertEqual(s.closes,1);XCTAssertFalse(s.profileSaveAction.isPending)}
}
final class ProfileActionTests:XCTestCase {
    override func setUp() {Progress.pending=[];Queue.mainQueue().drain()}
    func testPredicateInvalidatesBeforeStarting() {let a=EditAccountProfileSaveAction();var subscriptions=0;let signal=Signal<Never,EditAccountProfileSaveError> {_ in subscriptions+=1;return EmptyDisposable};a.perform(signal:signal,window:Window(),canPresent:{a.setActive(false);return true},failed:{ _ in XCTFail()},completed:{XCTFail()});XCTAssertEqual(subscriptions,0)}
    func testCancellationQueueCannotResetNewOperation() {let a=EditAccountProfileSaveAction();let w=Window();a.perform(signal:.never(),window:w,canPresent:{true},failed:{ (_:EditAccountProfileSaveError) in },completed:{});a.reset();a.perform(signal:.never(),window:w,canPresent:{true},failed:{ (_:EditAccountProfileSaveError) in },completed:{});Queue.mainQueue().drain();XCTAssertTrue(a.isPending)}
    func testStartedCallbackCanCancelBeforeSubscription() {let a=EditAccountProfileSaveAction();var subscriptions=0;a.perform(signal:Signal<Never,EditAccountProfileSaveError> {_ in subscriptions+=1;return EmptyDisposable},window:Window(),canPresent:{true},started:{a.reset()},failed:{ _ in XCTFail()},completed:{XCTFail()});XCTAssertEqual(subscriptions,0)}
    func testHelperDeinitCancelsRequest() {var a:EditAccountProfileSaveAction?=EditAccountProfileSaveAction();var disposed=0;a!.perform(signal:Signal<Never,EditAccountProfileSaveError> {_ in ActionDisposable {disposed+=1}},window:Window(),canPresent:{true},failed:{ (_:EditAccountProfileSaveError) in },completed:{});weak var wa=a;a=nil;XCTAssertNil(wa);XCTAssertEqual(disposed,1)}
}
