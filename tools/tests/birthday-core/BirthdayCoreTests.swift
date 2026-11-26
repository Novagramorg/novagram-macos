import Foundation
import SwiftSignalKit
import XCTest

protocol NetworkRequestDependencyTag {func shouldDependOn(other:NetworkRequestDependencyTag)->Bool}
enum Api {
    enum Bool {case boolTrue,boolFalse}
    enum Birthday {
        struct Cons_birthday {let flags:Int32;let day:Int32;let month:Int32;let year:Int32?}
        case birthday(Cons_birthday)
    }
    struct Request {let flags:Int32;let birthday:Birthday?}
    enum functions {enum account {static func updateBirthday(flags:Int32,birthday:Birthday?)->Request {.init(flags:flags,birthday:birthday)}}}
}
struct RpcError {let errorDescription:String}
final class Pending {
    let request:Api.Request;let tag:NetworkRequestDependencyTag?;let automaticFloodWait:Bool;let subscriber:Subscriber<Api.Bool,RpcError>;var disposed=false
    init(_ request:Api.Request,_ tag:NetworkRequestDependencyTag?,_ automaticFloodWait:Bool,_ subscriber:Subscriber<Api.Bool,RpcError>) {self.request=request;self.tag=tag;self.automaticFloodWait=automaticFloodWait;self.subscriber=subscriber}
    func respond(_ value:Api.Bool = .boolTrue) {subscriber.putNext(value);subscriber.putCompletion()}
    func fail(_ value:String="REJECTED") {subscriber.putError(.init(errorDescription:value))}
    func complete() {subscriber.putCompletion()}
}
final class Network {
    var requests:[Pending]=[];var onStart:((Pending)->Void)?
    func request(_ request:Api.Request,tag:NetworkRequestDependencyTag?=nil,automaticFloodWait:Bool=true)->Signal<Api.Bool,RpcError> {Signal {s in let p=Pending(request,tag,automaticFloodWait,s);self.requests.append(p);self.onStart?(p);return ActionDisposable {p.disposed=true}}}
}
class CachedPeerData {}
final class CachedUserData:CachedPeerData {
    let birthday:TelegramBirthday?;let other:Int
    init(birthday:TelegramBirthday?=nil,other:Int=0) {self.birthday=birthday;self.other=other}
    func withUpdatedBirthday(_ birthday:TelegramBirthday?)->CachedUserData {.init(birthday:birthday,other:other)}
}
final class Transaction {
    unowned let postbox:Postbox;init(_ postbox:Postbox) {self.postbox=postbox}
    func updatePeerCachedData(peerIds:Set<Int>,update:(Int,CachedPeerData?)->CachedPeerData?) {for id in peerIds {postbox.cached[id]=update(id,postbox.cached[id]);postbox.writes+=1}}
}
final class Postbox {
    var cached:[Int:CachedPeerData]=[99:CachedUserData(birthday:TelegramBirthday(day:1,month:2,year:1990),other:7),20:CachedUserData(birthday:TelegramBirthday(day:3,month:4,year:nil),other:8)]
    var tasks:[()->Void]=[];var writes=0
    func transaction<T>(_ body:@escaping(Transaction)->T)->Signal<T,NoError> {Signal {s in self.tasks.append {let value=body(Transaction(self));s.putNext(value);s.putCompletion()};return EmptyDisposable}}
    func drain() {while !tasks.isEmpty {tasks.removeFirst()()}}
}
final class Account {let peerId=99;let postbox=Postbox();let network=Network()}
__SOURCE__
final class Observation {var errors:[UpdateBirthdayError]=[];var completed=0;var disposable:Disposable?;func start(_ s:Signal<Never,UpdateBirthdayError>) {disposable=s.start(error:{[weak self] in self?.errors.append($0)},completed:{[weak self] in self?.completed+=1})};deinit {disposable?.dispose()}}
final class BirthdayCoreTests:XCTestCase {
    let birthday=TelegramBirthday(day:29,month:2,year:2000)
    func run(_ a:Account,clear:Bool=false)->Observation {let o=Observation();o.start(_internal_updateBirthday(account:a,birthday:clear ? nil : birthday));return o}
    func cached(_ a:Account,_ id:Int=99)->CachedUserData? {a.postbox.cached[id] as? CachedUserData}
    func testPendingDoesNotMutateOrComplete() {for clear in [false,true] {let a=Account();let o=run(a,clear:clear);XCTAssertEqual(a.postbox.writes,0);XCTAssertNotNil(cached(a)?.birthday);XCTAssertEqual(o.completed,0)}}
    func testFalseResponseIsErrorForSetAndClear() {for clear in [false,true] {let a=Account();let o=run(a,clear:clear);a.network.requests[0].respond(.boolFalse);a.postbox.drain();XCTAssertEqual(o.errors.count,1);XCTAssertEqual(o.completed,0);XCTAssertEqual(a.postbox.writes,0);XCTAssertNotNil(cached(a)?.birthday)}}
    func testEmptyResponseIsError() {for clear in [false,true] {let a=Account();let o=run(a,clear:clear);a.network.requests[0].complete();a.postbox.drain();XCTAssertEqual(o.errors.count,1);XCTAssertEqual(o.completed,0);XCTAssertEqual(a.postbox.writes,0)}}
    func testAcceptedSetCommitsBeforeCompletion() {let a=Account();let o=run(a);a.network.requests[0].respond();XCTAssertEqual(o.completed,0);a.postbox.drain();XCTAssertEqual(cached(a)?.birthday,birthday);XCTAssertEqual(o.completed,1);XCTAssertTrue(o.errors.isEmpty)}
    func testAcceptedClearCommitsBeforeCompletion() {let a=Account();let o=run(a,clear:true);a.network.requests[0].respond();XCTAssertNotNil(cached(a)?.birthday);a.postbox.drain();XCTAssertNil(cached(a)?.birthday);XCTAssertEqual(o.completed,1)}
    func testNetworkErrorPreservesCache() {let a=Account();let o=run(a);a.network.requests[0].fail();a.postbox.drain();XCTAssertEqual(o.errors.count,1);if case .generic?=o.errors.first {} else {XCTFail()};XCTAssertEqual(a.postbox.writes,0);XCTAssertEqual(o.completed,0)}
    func testFloodErrorRemainsDistinct() {for text in ["FLOOD_WAIT","FLOOD_WAIT_123"] {let a=Account();let o=run(a);a.network.requests[0].fail(text);if case .flood?=o.errors.first {} else {XCTFail()};XCTAssertEqual(a.postbox.writes,0)}}
    func testAutomaticFloodWaitIsDisabled() {let a=Account();let o=run(a);XCTAssertFalse(a.network.requests[0].automaticFloodWait);withExtendedLifetime(o) {}}
    func testMissingCacheCreatedOnAcceptance() {let a=Account();a.postbox.cached[99]=nil;let o=run(a);a.network.requests[0].respond();a.postbox.drain();XCTAssertEqual(cached(a)?.birthday,birthday);XCTAssertEqual(o.completed,1)}
    func testUnrelatedCurrentCacheFieldsPreserved() {let a=Account();let o=run(a);a.postbox.cached[99]=CachedUserData(other:100);a.network.requests[0].respond();a.postbox.drain();XCTAssertEqual(cached(a)?.other,100);XCTAssertEqual(cached(a,20)?.other,8);XCTAssertEqual(cached(a,20)?.birthday?.day,3);XCTAssertEqual(o.completed,1)}
    func testDuplicateTrueResponseCommitsOnce() {let a=Account();let o=run(a);let p=a.network.requests[0];p.subscriber.putNext(.boolTrue);p.subscriber.putNext(.boolTrue);p.complete();a.postbox.drain();XCTAssertEqual(a.postbox.writes,1);XCTAssertEqual(o.completed,1)}
    func testTrueThenFalseUsesFirstResult() {let a=Account();let o=run(a);let p=a.network.requests[0];p.subscriber.putNext(.boolTrue);p.subscriber.putNext(.boolFalse);p.complete();a.postbox.drain();XCTAssertEqual(a.postbox.writes,1);XCTAssertEqual(o.completed,1);XCTAssertTrue(o.errors.isEmpty)}
    func testFalseThenTrueCannotCommit() {let a=Account();let o=run(a);let p=a.network.requests[0];p.subscriber.putNext(.boolFalse);p.subscriber.putNext(.boolTrue);p.complete();a.postbox.drain();XCTAssertEqual(a.postbox.writes,0);XCTAssertEqual(o.errors.count,1);XCTAssertEqual(o.completed,0)}
    func testSignalIsCold() {let a=Account();let s=_internal_updateBirthday(account:a,birthday:birthday);XCTAssertTrue(a.network.requests.isEmpty);XCTAssertTrue(a.postbox.tasks.isEmpty);withExtendedLifetime(s) {}}
    func testColdSignalDoesNotRetainAccount() {var a:Account?=Account();weak var wa=a;let s=_internal_updateBirthday(account:a!,birthday:birthday);a=nil;XCTAssertNil(wa);withExtendedLifetime(s) {}}
    func testPendingSignalDoesNotRetainAccount() {var a:Account?=Account();let p=a!.postbox;let n=a!.network;let o=run(a!);weak var wa=a;a=nil;XCTAssertNil(wa);n.requests[0].respond();p.drain();XCTAssertEqual(o.completed,1)}
    func testCancelledBeforeResponseSuppressesWrites() {let a=Account();let o=run(a);o.disposable?.dispose();a.network.requests[0].respond();a.postbox.drain();XCTAssertTrue(a.network.requests[0].disposed);XCTAssertEqual(a.postbox.writes,0);XCTAssertEqual(o.completed,0)}
    func testAcceptedQueuedCommitSurvivesCancellation() {let a=Account();let o=run(a);a.network.requests[0].respond();o.disposable?.dispose();a.postbox.drain();XCTAssertEqual(cached(a)?.birthday,birthday);XCTAssertEqual(o.completed,0)}
    func testRepeatedSubscriptionsAreIndependent() {let a=Account();let s=_internal_updateBirthday(account:a,birthday:birthday);let x=Observation(),y=Observation();x.start(s);y.start(s);XCTAssertEqual(a.network.requests.count,2);x.disposable?.dispose();XCTAssertTrue(a.network.requests[0].disposed);XCTAssertFalse(a.network.requests[1].disposed);a.network.requests[1].respond();a.postbox.drain();XCTAssertEqual(y.completed,1)}
    func testSynchronousResponseCompletesAfterCommit() {let a=Account();a.network.onStart={$0.respond()};let o=run(a);XCTAssertEqual(o.completed,0);a.postbox.drain();XCTAssertEqual(o.completed,1)}
    func testSetAndClearShareDependencyTag() {let a=Account();let x=run(a),y=run(a,clear:true);let tags=a.network.requests.compactMap(\.tag);guard tags.count==2 else {return XCTFail("Missing tags")};XCTAssertTrue(tags[0].shouldDependOn(other:tags[1]));XCTAssertTrue(tags[1].shouldDependOn(other:tags[0]));withExtendedLifetime((x,y)) {}}
    func testBirthdayWireFlagsAndValues() {let a=Account();let o=run(a);let r=a.network.requests[0].request;XCTAssertEqual(r.flags,1);guard case let .birthday(d)?=r.birthday else {return XCTFail()};XCTAssertEqual(d.flags,1);XCTAssertEqual(d.day,29);XCTAssertEqual(d.month,2);XCTAssertEqual(d.year,2000);withExtendedLifetime(o) {}}
    func testNoYearOmitsYearFlag() {let a=Account();let o=Observation();o.start(_internal_updateBirthday(account:a,birthday:TelegramBirthday(day:29,month:2,year:nil)));guard case let .birthday(d)?=a.network.requests[0].request.birthday else {return XCTFail()};XCTAssertEqual(d.flags,0);XCTAssertNil(d.year);XCTAssertEqual(d.day,29);withExtendedLifetime(o) {}}
    func testClearOmitsBirthdayFlag() {let a=Account();let o=run(a,clear:true);XCTAssertEqual(a.network.requests[0].request.flags,0);XCTAssertNil(a.network.requests[0].request.birthday);withExtendedLifetime(o) {}}
}
