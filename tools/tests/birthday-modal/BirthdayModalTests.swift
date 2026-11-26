import Foundation
import SwiftSignalKit
import XCTest

struct TelegramBirthday:Equatable {let day:Int;let month:Int;let year:Int?}
extension Date {var birthday:TelegramBirthday {let c=Calendar(identifier:.gregorian);let y=c.component(.year,from:self);return .init(day:c.component(.day,from:self),month:c.component(.month,from:self),year:y==4 ? nil:y)}}
enum UpdateBirthdayError {case generic,flood}
final class Window {var messages:[String]=[]}
final class View {weak var window:Window?;init(_ window:Window) {self.window=window}}
class ViewController {let view:View;let frame=CGRect.zero;init(_ window:Window) {view=View(window)};func viewWillAppear(_ animated:Bool) {};func viewWillDisappear(_ animated:Bool) {}}
protocol ChatBirthdayCalendar:ViewController {var date:Date {get};func hideYear()}
final class CalendarController:ViewController,ChatBirthdayCalendar {var date:Date;init(_ date:Date,_ window:Window) {self.date=date;super.init(window)};func hideYear() {let c=Calendar(identifier:.gregorian);var components=c.dateComponents([.year,.month,.day],from:date);components.year=4;date=c.date(from:components)!}}
final class Navigation {var controller:ViewController;init(_ controller:ViewController) {self.controller=controller}}
final class Modal {var closes=0;var resized=0;var onClose:(()->Void)?;func close() {closes+=1;onClose?()};func setInteractionHeight(height:Int,animated:Bool) {};func resize(with size:CGSize,animated:Bool) {resized+=1}}
final class ModalInteractions {var updates=0;func updateBottomText(_ value:Int?) {updates+=1}}
final class Queue {static let main=Queue();var jobs:[()->Void]=[];static func mainQueue()->Queue {main};func justDispatch(_ f:@escaping()->Void) {jobs.append(f)};func drain() {while !jobs.isEmpty {jobs.removeFirst()()}}}
func deliverOnMainQueue<T,E>(_ s:Signal<T,E>)->Signal<T,E> {s}
final class Progress {static var pending:[MetaDisposable]=[];static var predicates:[()->Bool]=[]}
func showModalProgress<T,E>(signal:Signal<T,E>,for window:Window,shouldPresent:@escaping()->Bool={true})->Signal<T,E> {Signal {s in let d=MetaDisposable();Progress.pending.append(d);Progress.predicates.append(shouldPresent);d.set(signal.start(next:{s.putNext($0)},error:{s.putError($0)},completed:{s.putCompletion()}));return d}}
struct Strings {let loginFloodWait="Flood",unknownError="Error",birthdayAlertAdded="Added"}
func strings()->Strings {Strings()}
func showModalText(for window:Window,text:String) {window.messages.append(text)}
final class Request {let birthday:TelegramBirthday?;let subscriber:Subscriber<Never,UpdateBirthdayError>;var disposed=false;init(_ birthday:TelegramBirthday?,_ subscriber:Subscriber<Never,UpdateBirthdayError>) {self.birthday=birthday;self.subscriber=subscriber};func accept() {subscriber.putCompletion()};func reject(_ error:UpdateBirthdayError = .generic) {subscriber.putError(error)}}
final class AccountData {var requests:[Request]=[];var onStart:((Request)->Void)?;func updateBirthday(birthday:TelegramBirthday?)->Signal<Never,UpdateBirthdayError> {Signal {s in let r=Request(birthday,s);self.requests.append(r);self.onStart?(r);return ActionDisposable {r.disposed=true}}}}
struct Engine {let accountData=AccountData()}
final class Context {var window=Window();let engine=Engine()}
final class ChatNavigationHooks {static let shared=ChatNavigationHooks();func updateAccountBirthday(_ date:Date,_ context:Context) {_ = context.engine.accountData.updateBirthday(birthday:date.birthday).startStandalone(error:{[weak context] error in guard let context else {return};showModalText(for:context.window,text:error == .flood ? "Flood":"Error")},completed:{[weak context] in guard let context else {return};showModalText(for:context.window,text:"Added")})}}
__HELPER__
final class Wrap:ViewController {
    let context:Context;let controller:Navigation;var modal:Modal?=Modal();var isVisible=true;var hasSubmitted=false;let saveAction=ChatBirthdaySaveAction()
    init(_ date:Date,context:Context=Context()) {self.context=context;controller=Navigation(CalendarController(date,context.window));super.init(context.window)}
    __LIFECYCLE__
    func makeAccept()->()->Void {let context=self.context;return __ACCEPT__}
    func makeHide(_ interactions:ModalInteractions)->(String)->Void {return __HIDE__}
    var calendar:CalendarController {controller.controller as! CalendarController}
}
final class BirthdayModalTests:XCTestCase {
    override func setUp() {Progress.pending=[];Progress.predicates=[];Queue.mainQueue().drain()}
    func date(_ day:Int=15)->Date {Calendar(identifier:.gregorian).date(from:DateComponents(year:2000,month:6,day:day))!}
    func make()->Wrap {Wrap(date())}
    func testPendingSaveDoesNotCloseOrShowSuccess() {let w=make();w.makeAccept()();XCTAssertEqual(w.modal?.closes,0);XCTAssertTrue(w.context.window.messages.isEmpty);XCTAssertEqual(w.context.engine.accountData.requests.count,1)}
    func testSaveUsesSelectionSnapshot() {let w=make();w.calendar.date=date(25);w.makeAccept()();XCTAssertEqual(w.context.engine.accountData.requests[0].birthday,date(25).birthday)}
    func testSuccessClosesAfterAcceptance() {let w=make();w.makeAccept()();XCTAssertEqual(w.modal?.closes,0);w.context.engine.accountData.requests[0].accept();XCTAssertEqual(w.modal?.closes,1);XCTAssertTrue(w.hasSubmitted);XCTAssertEqual(w.context.window.messages,["Added"])}
    func testGenericFailureKeepsPickerOpen() {let w=make();w.makeAccept()();w.context.engine.accountData.requests[0].reject();XCTAssertEqual(w.modal?.closes,0);XCTAssertFalse(w.hasSubmitted);XCTAssertEqual(w.context.window.messages,["Error"]);XCTAssertEqual(w.calendar.date,date())}
    func testFloodFailureKeepsPickerOpen() {let w=make();w.makeAccept()();w.context.engine.accountData.requests[0].reject(.flood);XCTAssertEqual(w.modal?.closes,0);XCTAssertFalse(w.hasSubmitted);XCTAssertEqual(w.context.window.messages,["Flood"])}
    func testRetryAfterFailureUsesNewSelection() {let w=make();let accept=w.makeAccept();accept();w.context.engine.accountData.requests[0].reject();w.calendar.date=date(25);accept();let requests=w.context.engine.accountData.requests;XCTAssertEqual(requests.count,2);guard requests.count==2 else {return};XCTAssertEqual(requests[1].birthday,date(25).birthday);requests[1].accept();XCTAssertEqual(w.modal?.closes,1)}
    func testDuplicatePendingSaveStartsOneRequest() {let w=make();let accept=w.makeAccept();accept();accept();XCTAssertEqual(w.context.engine.accountData.requests.count,1);XCTAssertEqual(w.modal?.closes,0)}
    func testDuplicateAfterAcceptanceDoesNotRepeat() {let w=make();let accept=w.makeAccept();accept();w.context.engine.accountData.requests[0].accept();accept();XCTAssertEqual(w.context.engine.accountData.requests.count,1);XCTAssertEqual(w.modal?.closes,1)}
    func testDisappearanceCancelsPendingRequest() {let w=make();w.makeAccept()();w.viewWillDisappear(false);XCTAssertTrue(w.context.engine.accountData.requests[0].disposed);w.context.engine.accountData.requests[0].accept();XCTAssertEqual(w.modal?.closes,0);XCTAssertTrue(w.context.window.messages.isEmpty)}
    func testCancelledRequestCannotShowLateError() {let w=make();w.makeAccept()();w.viewWillDisappear(false);w.context.engine.accountData.requests[0].reject(.flood);XCTAssertTrue(w.context.window.messages.isEmpty)}
    func testReappearanceAllowsFreshRequest() {let w=make();let accept=w.makeAccept();accept();w.viewWillDisappear(false);w.viewWillAppear(false);accept();let requests=w.context.engine.accountData.requests;XCTAssertEqual(requests.count,2);guard requests.count==2 else {return};requests[0].accept();XCTAssertEqual(w.modal?.closes,0);requests[1].accept();XCTAssertEqual(w.modal?.closes,1)}
    func testProgressCancellationAllowsRetryWithoutError() {let w=make();let accept=w.makeAccept();accept();guard let progress=Progress.pending.last else {return XCTFail("Missing progress")};progress.dispose();Queue.mainQueue().drain();XCTAssertTrue(w.context.window.messages.isEmpty);XCTAssertEqual(w.modal?.closes,0);accept();XCTAssertEqual(w.context.engine.accountData.requests.count,2)}
    func testChangedSelectionDuringSaveRemainsOpen() {let w=make();w.makeAccept()();w.calendar.date=date(25);w.context.engine.accountData.requests[0].accept();XCTAssertEqual(w.modal?.closes,0);XCTAssertFalse(w.hasSubmitted);XCTAssertEqual(w.calendar.date,date(25));XCTAssertEqual(w.context.window.messages,["Added"])}
    func testChangedSelectionCanBeSavedAfterEarlierSuccess() {let w=make();let accept=w.makeAccept();accept();w.calendar.date=date(25);w.context.engine.accountData.requests[0].accept();accept();let requests=w.context.engine.accountData.requests;XCTAssertEqual(requests.count,2);guard requests.count==2 else {return};requests[1].accept();XCTAssertEqual(w.modal?.closes,1)}
    func testWindowReplacementSuppressesSuccess() {let w=make();w.makeAccept()();let new=Window();w.view.window=new;w.context.engine.accountData.requests[0].accept();XCTAssertEqual(w.modal?.closes,0);XCTAssertTrue(w.context.window.messages.isEmpty);XCTAssertTrue(new.messages.isEmpty)}
    func testContextWindowReplacementSuppressesError() {let w=make();let old=w.context.window;w.makeAccept()();w.context.window=Window();w.context.engine.accountData.requests[0].reject();XCTAssertTrue(old.messages.isEmpty);XCTAssertTrue(w.context.window.messages.isEmpty)}
    func testReplacedCalendarSuppressesCompletion() {let w=make();let old=w.calendar;w.makeAccept()();w.controller.controller=CalendarController(date(25),w.context.window);w.context.engine.accountData.requests[0].accept();XCTAssertEqual(w.modal?.closes,0);XCTAssertTrue(w.context.window.messages.isEmpty);withExtendedLifetime(old) {}}
    func testMissingWindowDoesNotRequest() {let w=make();w.view.window=nil;w.makeAccept()();XCTAssertTrue(w.context.engine.accountData.requests.isEmpty)}
    func testWrongContextWindowDoesNotRequest() {let w=make();let other=Window();w.view.window=other;w.makeAccept()();XCTAssertTrue(w.context.engine.accountData.requests.isEmpty)}
    func testHideYearWhilePendingDoesNothing() {let w=make();let i=ModalInteractions();w.makeAccept()();w.makeHide(i)("");XCTAssertEqual(w.calendar.date,date());XCTAssertEqual(i.updates,0)}
    func testHideYearAvailableAfterFailure() {let w=make();let i=ModalInteractions();w.makeAccept()();w.context.engine.accountData.requests[0].reject();w.makeHide(i)("");XCTAssertNil(w.calendar.date.birthday.year);XCTAssertEqual(i.updates,1)}
    func testSynchronousSuccessCompletesOnce() {let w=make();w.context.engine.accountData.onStart={$0.accept()};w.makeAccept()();Queue.mainQueue().drain();XCTAssertEqual(w.modal?.closes,1);XCTAssertFalse(w.saveAction.isPending)}
    func testSynchronousFailureAllowsRetry() {let w=make();w.context.engine.accountData.onStart={$0.reject()};let accept=w.makeAccept();accept();accept();XCTAssertEqual(w.context.engine.accountData.requests.count,2);XCTAssertEqual(w.modal?.closes,0)}
    func testDeinitCancelsWithoutRetainingModalOrContext() {var w:Wrap?=make();let data=w!.context.engine.accountData;let window=w!.context.window;weak var context=w!.context;weak var weakWrap=w;let accept=w!.makeAccept();accept();w=nil;XCTAssertNil(weakWrap);XCTAssertNil(context);XCTAssertTrue(data.requests[0].disposed);data.requests[0].accept();XCTAssertTrue(window.messages.isEmpty);accept()}
    func testProgressPredicateRejectsHiddenModal() {let w=make();w.makeAccept()();guard let predicate=Progress.predicates.last else {return XCTFail("Missing predicate")};XCTAssertTrue(predicate());w.viewWillDisappear(false);XCTAssertFalse(predicate())}
    func testClosingOnSuccessCanDisposeReentrantly() {let w=make();w.modal?.onClose={[weak w] in w?.viewWillDisappear(false)};w.makeAccept()();w.context.engine.accountData.requests[0].accept();XCTAssertEqual(w.modal?.closes,1);XCTAssertEqual(w.context.window.messages,["Added"]);XCTAssertFalse(w.saveAction.isPending)}
}
