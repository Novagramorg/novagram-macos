import Foundation
import SwiftSignalKit
import XCTest

typealias PeerId = Int
protocol NetworkRequestDependencyTag { func shouldDependOn(other: NetworkRequestDependencyTag) -> Bool }
enum Api {
    struct UserData: Equatable { let id: Int; let firstName: String; let lastName: String }
    struct EmptyData: Equatable { let id: Int }
    enum User: Equatable { case user(UserData), userEmpty(EmptyData); var peerId: Int { switch self { case let .user(d): return d.id; case let .userEmpty(d): return d.id } } }
    struct Request { let flags: Int32; let firstName: String?; let lastName: String?; let about: String? }
    enum functions { enum account { static func updateProfile(flags: Int32, firstName: String?, lastName: String?, about: String?) -> Request { .init(flags: flags, firstName: firstName, lastName: lastName, about: about) } } }
}
class CachedPeerData {}
final class CachedUserData: CachedPeerData {
    let about: String?; let other: Int
    init(about: String? = nil, other: Int = 0) { self.about = about; self.other = other }
    func withUpdatedAbout(_ about: String?) -> CachedUserData { .init(about:about,other:other) }
}
struct AccumulatedPeers {
    let users: [Api.User]
    init(transaction: Transaction, chats: [Int], users: [Api.User]) { self.users = users }
}
func updatePeers(transaction: Transaction, accountPeerId: Int, peers: AccumulatedPeers) { transaction.postbox.users += peers.users; transaction.postbox.accountIds.append(accountPeerId) }
struct RpcError { let errorDescription: String }
final class Pending {
    let request: Api.Request; let tag: NetworkRequestDependencyTag?; let subscriber: Subscriber<Api.User,RpcError>; var disposed = false
    init(_ request: Api.Request, _ tag: NetworkRequestDependencyTag?, _ subscriber: Subscriber<Api.User,RpcError>) { self.request=request;self.tag=tag;self.subscriber=subscriber }
    func respond(_ id: Int = 99) { subscriber.putNext(.user(.init(id:id,firstName:"Normalized",lastName:"Name"))); subscriber.putCompletion() }
    func fail() { subscriber.putError(.init(errorDescription:"REJECTED")) }
    func complete() { subscriber.putCompletion() }
}
final class Network {
    var requests: [Pending] = []; var onStart: ((Pending)->Void)?
    func request(_ request: Api.Request, tag: NetworkRequestDependencyTag? = nil) -> Signal<Api.User,RpcError> { Signal { s in let p=Pending(request,tag,s);self.requests.append(p);self.onStart?(p);return ActionDisposable { p.disposed=true } } }
}
final class Transaction {
    unowned let postbox: Postbox; init(_ postbox: Postbox) { self.postbox=postbox }
    func updatePeerCachedData(peerIds: Set<Int>, update:(Int,CachedPeerData?)->CachedPeerData?) { for id in peerIds { postbox.cached[id]=update(id,postbox.cached[id]);postbox.cacheWrites+=1 } }
}
final class Postbox {
    var cached: [Int:CachedPeerData] = [99:CachedUserData(about:"Old",other:3),20:CachedUserData(about:"Other",other:4)]
    var users: [Api.User] = []; var tasks: [()->Void] = []; var cacheWrites=0;var accountIds:[Int]=[]
    func transaction<T>(_ body:@escaping(Transaction)->T)->Signal<T,NoError> { Signal { s in self.tasks.append { let v=body(Transaction(self));s.putNext(v);s.putCompletion() };return EmptyDisposable } }
    func drain() { while !tasks.isEmpty { tasks.removeFirst()() } }
}
final class Account { let peerId=99;let postbox=Postbox();let network=Network() }
__SOURCE__
final class Observation { var next=0;var errors=0;var completed=0;var disposable:Disposable?;func start<E>(_ signal:Signal<Void,E>) { disposable=signal.start(next:{[weak self] in self?.next+=1},error:{[weak self] _ in self?.errors+=1},completed:{[weak self] in self?.completed+=1}) };deinit {disposable?.dispose()} }
class ProfileFixture: XCTestCase {
    func about(_ a:Account,_ value:String?="New")->Observation {let o=Observation();o.start(_internal_updateAbout(account:a,about:value));return o}
    func name(_ a:Account)->Observation {let o=Observation();o.start(_internal_updateAccountPeerName(account:a,firstName:"First",lastName:"Last"));return o}
    func profile(_ a:Account,first:String?="First",last:String?="Last",bio:String?="New")->Observation {let o=Observation();o.start(_internal_updateAccountProfile(account:a,firstName:first,lastName:last,about:bio));return o}
    func cached(_ a:Account,_ id:Int=99)->CachedUserData? {a.postbox.cached[id] as? CachedUserData}
}
final class CoreLegacyTests: ProfileFixture {
    func testPendingAboutDoesNotMutate() {let a=Account();let o=about(a);XCTAssertEqual(cached(a)?.about,"Old");XCTAssertEqual(o.completed,0)}
    func testRejectedAboutKeepsCache() {let a=Account();let o=about(a);a.network.requests[0].fail();a.postbox.drain();XCTAssertEqual(o.errors,1);XCTAssertEqual(cached(a)?.about,"Old");XCTAssertEqual(a.postbox.cacheWrites,0)}
    func testEmptyAboutResponseFails() {let a=Account();let o=about(a);a.network.requests[0].complete();a.postbox.drain();XCTAssertEqual(o.errors,1);XCTAssertEqual(o.completed,0)}
    func testAcceptedAboutCreatesMissingCache() {let a=Account();a.postbox.cached[99]=nil;let o=about(a);a.network.requests[0].respond();a.postbox.drain();XCTAssertEqual(cached(a)?.about,"New");XCTAssertEqual(o.completed,1)}
    func testAcceptedAboutMergesReturnedUser() {let a=Account();let o=about(a);a.network.requests[0].respond();a.postbox.drain();XCTAssertEqual(a.postbox.users,[.user(.init(id:99,firstName:"Normalized",lastName:"Name"))]);XCTAssertEqual(o.completed,1)}
    func testNilAboutOmitsMutationAndRequest() {let a=Account();let o=about(a,nil);for p in a.network.requests {p.respond()};a.postbox.drain();XCTAssertTrue(a.network.requests.isEmpty);XCTAssertEqual(cached(a)?.about,"Old");XCTAssertEqual(o.completed,1)}
    func testEmptyAboutClearsAfterAcknowledgement() {let a=Account();let o=about(a,"");XCTAssertEqual(a.network.requests[0].request.flags,4);XCTAssertEqual(a.network.requests[0].request.about,"");XCTAssertEqual(cached(a)?.about,"Old");a.network.requests[0].respond();a.postbox.drain();XCTAssertEqual(cached(a)?.about,"");XCTAssertEqual(o.completed,1)}
    func testCurrentCachedMetadataAndOtherPeerPreserved() {let a=Account();let o=about(a);a.postbox.cached[99]=CachedUserData(about:"External",other:9);a.network.requests[0].respond();a.postbox.drain();XCTAssertEqual(cached(a)?.other,9);XCTAssertEqual(cached(a,20)?.about,"Other");XCTAssertEqual(o.completed,1)}
    func testWrongUserCannotChangeBio() {let a=Account();let o=about(a);a.network.requests[0].respond(20);a.postbox.drain();XCTAssertEqual(o.errors,1);XCTAssertEqual(cached(a)?.about,"Old");XCTAssertTrue(a.postbox.users.isEmpty)}
    func testEmptyUserCannotChangeBio() {let a=Account();let o=about(a);a.network.requests[0].subscriber.putNext(.userEmpty(.init(id:99)));a.network.requests[0].complete();a.postbox.drain();XCTAssertEqual(o.errors,1);XCTAssertEqual(cached(a)?.about,"Old")}
    func testDuplicateAboutResponsesCommitOnce() {let a=Account();let o=about(a);let p=a.network.requests[0];p.subscriber.putNext(.user(.init(id:99,firstName:"A",lastName:"")));p.subscriber.putNext(.user(.init(id:99,firstName:"B",lastName:"")));p.complete();a.postbox.drain();XCTAssertEqual(a.postbox.cacheWrites,1);XCTAssertEqual(o.next,1)}
    func testColdLegacySignalsReleaseAccount() {for mode in 0...1 {var a:Account?=Account();weak var wa=a;let s:[Any]=mode==0 ? [_internal_updateAccountPeerName(account:a!,firstName:"A",lastName:"B")] : [_internal_updateAbout(account:a!,about:"Bio")];a=nil;XCTAssertNil(wa);withExtendedLifetime(s) {}}}
    func testPendingLegacySignalsReleaseAccount() {for mode in 0...1 {var a:Account?=Account();let p=a!.postbox;let n=a!.network;let o=mode==0 ? name(a!) : about(a!);weak var wa=a;a=nil;XCTAssertNil(wa);n.requests[0].respond();p.drain();XCTAssertEqual(o.completed,1)}}
    func testLegacyNameRejectsForeignUserWithoutMutation() {let a=Account();let o=name(a);a.network.requests[0].respond(20);a.postbox.drain();XCTAssertTrue(a.postbox.users.isEmpty);XCTAssertEqual(o.errors,0);XCTAssertEqual(o.completed,1)}
    func testLegacyNamePreservesNoErrorContract() {let a=Account();let o=name(a);a.network.requests[0].fail();a.postbox.drain();XCTAssertEqual(o.errors,0);XCTAssertEqual(o.next,1);XCTAssertEqual(o.completed,1);XCTAssertTrue(a.postbox.users.isEmpty)}
    func testLegacyCancellationBeforeResponse() {let a=Account();let o=about(a);o.disposable?.dispose();a.network.requests[0].respond();a.postbox.drain();XCTAssertTrue(a.network.requests[0].disposed);XCTAssertEqual(a.postbox.cacheWrites,0);XCTAssertEqual(o.completed,0)}
    func testLegacyAcceptedCommitSurvivesCancellation() {let a=Account();let o=about(a);a.network.requests[0].respond();o.disposable?.dispose();a.postbox.drain();XCTAssertEqual(cached(a)?.about,"New");XCTAssertEqual(o.completed,0)}
    func testLegacyNamesWireFlags() {let a=Account();let o=name(a);let p=a.network.requests[0].request;XCTAssertEqual(p.flags,3);XCTAssertEqual(p.firstName,"First");XCTAssertEqual(p.lastName,"Last");XCTAssertNil(p.about);withExtendedLifetime(o) {}}
}
final class CoreProfileTests: ProfileFixture {
    func testCombinedSaveUsesOneRequest() {let a=Account();let o=profile(a);XCTAssertEqual(a.network.requests.count,1);let r=a.network.requests[0].request;XCTAssertEqual(r.flags,7);XCTAssertEqual(r.firstName,"First");XCTAssertEqual(r.lastName,"Last");XCTAssertEqual(r.about,"New");withExtendedLifetime(o) {}}
    func testAllOptionalFlagCombinations() {for flags in 0..<8 {let a=Account();let o=profile(a,first:flags & 1 != 0 ? "F" : nil,last:flags & 2 != 0 ? "L" : nil,bio:flags & 4 != 0 ? "B" : nil);if flags==0 {XCTAssertTrue(a.network.requests.isEmpty);XCTAssertEqual(o.next,1);XCTAssertEqual(o.completed,1)} else {XCTAssertEqual(a.network.requests[0].request.flags,Int32(flags));XCTAssertEqual(o.completed,0)}}}
    func testRejectedCombinedSaveReportsErrorWithoutMutation() {let a=Account();let o=profile(a);a.network.requests[0].fail();a.postbox.drain();XCTAssertEqual(o.errors,1);XCTAssertEqual(o.completed,0);XCTAssertEqual(o.next,0);XCTAssertTrue(a.postbox.users.isEmpty);XCTAssertEqual(cached(a)?.about,"Old")}
    func testAcceptedCombinedSaveCommitsBeforeCompletion() {let a=Account();let o=profile(a);a.network.requests[0].respond();XCTAssertEqual(o.completed,0);a.postbox.drain();XCTAssertEqual(o.next,1);XCTAssertEqual(o.completed,1);XCTAssertEqual(cached(a)?.about,"New");XCTAssertEqual(a.postbox.users.count,1);XCTAssertEqual(a.postbox.accountIds,[99])}
    func testEmptyResponseFails() {let a=Account();let o=profile(a);a.network.requests[0].complete();a.postbox.drain();XCTAssertEqual(o.errors,1);XCTAssertEqual(o.completed,0)}
    func testForeignResponseFails() {let a=Account();let o=profile(a);a.network.requests[0].respond(20);a.postbox.drain();XCTAssertEqual(o.errors,1);XCTAssertTrue(a.postbox.users.isEmpty);XCTAssertEqual(a.postbox.cacheWrites,0)}
    func testEmptyUserResponseFails() {let a=Account();let o=profile(a);a.network.requests[0].subscriber.putNext(.userEmpty(.init(id:99)));a.postbox.drain();XCTAssertEqual(o.errors,1);XCTAssertTrue(a.postbox.users.isEmpty)}
    func testNameOnlyPreservesBio() {let a=Account();let o=profile(a,bio:nil);a.network.requests[0].respond();a.postbox.drain();XCTAssertEqual(cached(a)?.about,"Old");XCTAssertEqual(a.postbox.cacheWrites,0);XCTAssertEqual(o.completed,1)}
    func testDuplicateResponseCommitsOnce() {let a=Account();let o=profile(a);let p=a.network.requests[0];for name in ["A","B"] {p.subscriber.putNext(.user(.init(id:99,firstName:name,lastName:"")))};p.complete();a.postbox.drain();XCTAssertEqual(a.postbox.users,[.user(.init(id:99,firstName:"A",lastName:""))]);XCTAssertEqual(a.postbox.cacheWrites,1);XCTAssertEqual(o.next,1)}
    func testColdSignalRetainsNoAccount() {var a:Account?=Account();weak var wa=a;let n=a!.network;let s=_internal_updateAccountProfile(account:a!,firstName:"A",lastName:nil,about:nil);a=nil;XCTAssertNil(wa);XCTAssertTrue(n.requests.isEmpty);withExtendedLifetime(s) {}}
    func testCancellationBeforeResponseDoesNotCommit() {let a=Account();let o=profile(a);o.disposable?.dispose();a.network.requests[0].respond();a.postbox.drain();XCTAssertTrue(a.postbox.users.isEmpty);XCTAssertEqual(o.completed,0)}
    func testQueuedAcceptedCommitSurvivesCancellation() {let a=Account();let o=profile(a);a.network.requests[0].respond();o.disposable?.dispose();a.postbox.drain();XCTAssertEqual(a.postbox.users.count,1);XCTAssertEqual(cached(a)?.about,"New");XCTAssertEqual(o.completed,0)}
    func testRepeatedSubscriptionsOwnTheirRequests() {let a=Account();let s=_internal_updateAccountProfile(account:a,firstName:"A",lastName:nil,about:nil);let x=Observation(),y=Observation();x.start(s);y.start(s);XCTAssertEqual(a.network.requests.count,2);x.disposable?.dispose();XCTAssertTrue(a.network.requests[0].disposed);XCTAssertFalse(a.network.requests[1].disposed);a.network.requests[1].respond();a.postbox.drain();XCTAssertEqual(y.completed,1)}
    func testSynchronousResponse() {let a=Account();a.network.onStart={$0.respond()};let o=profile(a);a.postbox.drain();XCTAssertEqual(o.next,1);XCTAssertEqual(o.completed,1)}
    func testSharedDependencyTagAcrossAllEntrypoints() {let a=Account();let x=profile(a),y=about(a),z=name(a);let tags=a.network.requests.compactMap(\.tag);guard tags.count==3 else {return XCTFail("Missing tags")};for t in tags {for other in tags {XCTAssertTrue(t.shouldDependOn(other:other))}};withExtendedLifetime((x,y,z)) {}}
}
