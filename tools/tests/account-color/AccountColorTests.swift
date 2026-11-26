import Foundation
import SwiftSignalKit
import XCTest

typealias PeerId=Int
struct PeerNameColor:Equatable {let rawValue:Int32;static let old=PeerNameColor(rawValue:1);static let new=PeerNameColor(rawValue:2)}
struct PeerCollectibleColor:Equatable {let collectibleId:Int64;let backgroundEmojiId:Int64}
enum PeerColor:Equatable {case preset(PeerNameColor),collectible(PeerCollectibleColor)}
class Peer {let id:Int;init(_ id:Int) {self.id=id}}
final class TelegramUser:Peer {
    let nameColor:PeerColor;let backgroundEmojiId:Int64?;let profileColor:PeerNameColor?;let profileBackgroundEmojiId:Int64?;let other:String
    init(_ id:Int=1,name:PeerColor = .preset(.old),background:Int64?=10,profile:PeerNameColor? = .old,profileBackground:Int64?=20,other:String="original") {nameColor=name;backgroundEmojiId=background;profileColor=profile;profileBackgroundEmojiId=profileBackground;self.other=other;super.init(id)}
    func withUpdatedNameColor(_ value:PeerColor)->TelegramUser {.init(id,name:value,background:backgroundEmojiId,profile:profileColor,profileBackground:profileBackgroundEmojiId,other:other)}
    func withUpdatedBackgroundEmojiId(_ value:Int64?)->TelegramUser {.init(id,name:nameColor,background:value,profile:profileColor,profileBackground:profileBackgroundEmojiId,other:other)}
    func withUpdatedProfileColor(_ value:PeerNameColor?)->TelegramUser {.init(id,name:nameColor,background:backgroundEmojiId,profile:value,profileBackground:profileBackgroundEmojiId,other:other)}
    func withUpdatedProfileBackgroundEmojiId(_ value:Int64?)->TelegramUser {.init(id,name:nameColor,background:backgroundEmojiId,profile:profileColor,profileBackground:value,other:other)}
}
final class Transaction {unowned let postbox:Postbox;init(_ postbox:Postbox) {self.postbox=postbox};func getPeer(_ id:Int)->Peer? {postbox.peers[id]}}
func updatePeersCustom(transaction:Transaction,peers:[TelegramUser],update:(TelegramUser?,TelegramUser)->TelegramUser) {for peer in peers {transaction.postbox.peers[peer.id]=update(transaction.postbox.peers[peer.id] as? TelegramUser,peer);transaction.postbox.writes+=1}}
final class Postbox {
    var peers:[Int:Peer]=[1:TelegramUser()];var writes=0;var automatic=true;var tasks:[()->Void]=[]
    func transaction<T>(_ body:@escaping(Transaction)->T)->Signal<T,NoError> {Signal {s in let run={let value=body(Transaction(self));s.putNext(value);s.putCompletion()};if self.automatic {run()} else {self.tasks.append(run)};return EmptyDisposable}}
    func drain() {while !tasks.isEmpty {tasks.removeFirst()()}}
}
enum Api {
    enum Bool {case boolTrue,boolFalse}
    struct Color {let flags:Int32;let color:Int32?;let backgroundEmojiId:Int64?}
    struct Collectible {let collectibleId:Int64}
    enum PeerColor {case peerColor(Color),inputPeerColorCollectible(Collectible)}
    struct Request {let flags:Int32;let color:PeerColor}
    enum functions {enum account {static func updateColor(flags:Int32,color:PeerColor)->Request {.init(flags:flags,color:color)}}}
}
enum RpcError {case generic}
protocol NetworkRequestDependencyTag {func shouldDependOn(other:NetworkRequestDependencyTag)->Bool}
final class Pending {
    let subscriber:Subscriber<Api.Bool,RpcError>;var disposed=false;var onDispose:(()->Void)?
    init(_ subscriber:Subscriber<Api.Bool,RpcError>) {self.subscriber=subscriber}
    func send(_ value:Api.Bool) {subscriber.putNext(value)}
    func respond(_ value:Api.Bool) {subscriber.putNext(value);subscriber.putCompletion()}
    func complete() {subscriber.putCompletion()}
    func fail() {subscriber.putError(.generic)}
    func dispose() {if !disposed {disposed=true;onDispose?()}}
}
final class Network {
    var requests:[(Api.Request,Pending)]=[];var tags:[NetworkRequestDependencyTag?]=[];var onSubscribe:((Int,Pending)->Void)?
    func request(_ request:Api.Request,tag:NetworkRequestDependencyTag?=nil)->Signal<Api.Bool,RpcError> {Signal {s in let p=Pending(s);self.requests.append((request,p));self.tags.append(tag);self.onSubscribe?(self.requests.count-1,p);return ActionDisposable {p.dispose()}}}
}
final class Account {let peerId=1;let postbox=Postbox();let network=Network()}
__SOURCE__
final class Observation {var errors=0;var completed=0;var disposable:Disposable?;func start<E>(_ signal:Signal<Void,E>) {disposable=signal.start(error:{[weak self] _ in self?.errors+=1},completed:{[weak self] in self?.completed+=1})};deinit {disposable?.dispose()}}
func user(_ a:Account)->TelegramUser {a.postbox.peers[1] as! TelegramUser}
final class AccountColorTests:XCTestCase {
    func apply(_ a:Account,name:UpdateNameColor = .preset(color:.new,backgroundEmojiId:11),profile:PeerNameColor? = .new,background:Int64?=21)->Observation {let o=Observation();o.start(_internal_updateNameColorAndEmoji(account:a,nameColor:name,profileColor:profile,profileBackgroundEmojiId:background));return o}
    func testNoOptimisticColorMutation() {let a=Account();let o=apply(a);XCTAssertEqual(a.postbox.writes,0);XCTAssertEqual(user(a).nameColor,.preset(.old));XCTAssertEqual(user(a).profileColor,.old);XCTAssertEqual(o.completed,0)}
    func testBothAcceptedCommitBeforeCompletion() {let a=Account();let o=apply(a);a.network.requests[0].1.respond(.boolTrue);XCTAssertEqual(o.completed,0);XCTAssertEqual(user(a).nameColor,.preset(.new));XCTAssertEqual(user(a).profileColor,.old);a.network.requests[1].1.respond(.boolTrue);XCTAssertEqual(o.completed,1);XCTAssertEqual(o.errors,0);XCTAssertEqual(user(a).profileColor,.new)}
    func testBothFalseAreFailureWithoutWrites() {let a=Account();let o=apply(a);a.network.requests[0].1.respond(.boolFalse);a.network.requests[1].1.respond(.boolFalse);XCTAssertEqual(o.errors,1);XCTAssertEqual(o.completed,0);XCTAssertEqual(a.postbox.writes,0)}
    func testBothTransportFailuresPreserveCurrentUser() {let a=Account();let o=apply(a);a.network.requests[0].1.fail();a.network.requests[1].1.fail();XCTAssertEqual(o.errors,1);XCTAssertEqual(a.postbox.writes,0);XCTAssertEqual(user(a).backgroundEmojiId,10);XCTAssertEqual(user(a).profileBackgroundEmojiId,20)}
    func testBothEmptyResponsesFail() {let a=Account();let o=apply(a);a.network.requests[0].1.complete();a.network.requests[1].1.complete();XCTAssertEqual(o.errors,1);XCTAssertEqual(o.completed,0);XCTAssertEqual(a.postbox.writes,0)}
    func testNameAcceptanceSurvivesProfileRejection() {let a=Account();let o=apply(a);a.network.requests[0].1.respond(.boolTrue);a.network.requests[1].1.respond(.boolFalse);XCTAssertEqual(user(a).nameColor,.preset(.new));XCTAssertEqual(user(a).backgroundEmojiId,11);XCTAssertEqual(user(a).profileColor,.old);XCTAssertEqual(user(a).profileBackgroundEmojiId,20);XCTAssertEqual(o.errors,1)}
    func testProfileAcceptanceSurvivesNameRejection() {let a=Account();let o=apply(a);a.network.requests[0].1.respond(.boolFalse);a.network.requests[1].1.respond(.boolTrue);XCTAssertEqual(user(a).nameColor,.preset(.old));XCTAssertEqual(user(a).backgroundEmojiId,10);XCTAssertEqual(user(a).profileColor,.new);XCTAssertEqual(user(a).profileBackgroundEmojiId,21);XCTAssertEqual(o.errors,1)}
    func testFirstFailureDoesNotCancelOtherRequest() {let a=Account();let o=apply(a);a.network.requests[0].1.fail();XCTAssertFalse(a.network.requests[1].1.disposed);XCTAssertEqual(o.errors,0);a.network.requests[1].1.respond(.boolTrue);XCTAssertEqual(user(a).profileColor,.new);XCTAssertEqual(o.errors,1)}
    func testProfileFailureDoesNotCancelNameRequest() {let a=Account();let o=apply(a);a.network.requests[1].1.fail();XCTAssertFalse(a.network.requests[0].1.disposed);a.network.requests[0].1.respond(.boolTrue);XCTAssertEqual(user(a).nameColor,.preset(.new));XCTAssertEqual(user(a).profileColor,.old);XCTAssertEqual(o.errors,1)}
    func testAcceptedProfileBeforeNameFailureKeepsNameFields() {let a=Account();let o=apply(a);a.network.requests[1].1.respond(.boolTrue);a.network.requests[0].1.fail();XCTAssertEqual(user(a).nameColor,.preset(.old));XCTAssertEqual(user(a).profileColor,.new);XCTAssertEqual(o.errors,1)}
    func testAcceptedNameBeforeProfileFailureKeepsProfileFields() {let a=Account();let o=apply(a);a.network.requests[0].1.respond(.boolTrue);a.network.requests[1].1.fail();XCTAssertEqual(user(a).nameColor,.preset(.new));XCTAssertEqual(user(a).profileColor,.old);XCTAssertEqual(o.errors,1)}
    func testMissingPeerFailsWithoutNetwork() {let a=Account();a.postbox.peers.removeAll();let o=apply(a);XCTAssertEqual(o.errors,1);XCTAssertEqual(o.completed,0);XCTAssertTrue(a.network.requests.isEmpty)}
    func testNonUserPeerFailsWithoutNetwork() {let a=Account();a.postbox.peers[1]=Peer(1);let o=apply(a);XCTAssertEqual(o.errors,1);XCTAssertTrue(a.network.requests.isEmpty)}
    func testCurrentUnrelatedFieldsArePreserved() {let a=Account();let o=apply(a);a.postbox.peers[1]=TelegramUser(other:"new current fields");a.network.requests[0].1.respond(.boolTrue);a.network.requests[1].1.respond(.boolTrue);XCTAssertEqual(user(a).other,"new current fields");XCTAssertEqual(user(a).nameColor,.preset(.new));XCTAssertEqual(user(a).profileColor,.new);XCTAssertEqual(o.completed,1)}
    func testNameCommitPreservesCurrentProfileFields() {let a=Account();let o=apply(a);a.postbox.peers[1]=TelegramUser(profile:.init(rawValue:99),profileBackground:999);a.network.requests[0].1.respond(.boolTrue);a.network.requests[1].1.respond(.boolFalse);XCTAssertEqual(user(a).profileColor,.init(rawValue:99));XCTAssertEqual(user(a).profileBackgroundEmojiId,999);XCTAssertEqual(user(a).backgroundEmojiId,11);XCTAssertEqual(o.errors,1)}
    func testProfileCommitPreservesCurrentNameFields() {let a=Account();let o=apply(a);a.postbox.peers[1]=TelegramUser(name:.preset(.init(rawValue:99)),background:999);a.network.requests[1].1.respond(.boolTrue);a.network.requests[0].1.respond(.boolFalse);XCTAssertEqual(user(a).nameColor,.preset(.init(rawValue:99)));XCTAssertEqual(user(a).backgroundEmojiId,999);XCTAssertEqual(user(a).profileBackgroundEmojiId,21);XCTAssertEqual(o.errors,1)}
    func testRemovedPeerIsNotRecreatedAfterAcceptance() {let a=Account();let o=apply(a);a.postbox.peers.removeAll();a.network.requests[0].1.respond(.boolTrue);a.network.requests[1].1.respond(.boolTrue);XCTAssertNil(a.postbox.peers[1]);XCTAssertEqual(o.completed,1)}
    func testChangedPeerTypeIsNotOverwritten() {let a=Account();let o=apply(a);let other=Peer(1);a.postbox.peers[1]=other;a.network.requests[0].1.respond(.boolTrue);a.network.requests[1].1.respond(.boolTrue);XCTAssertTrue(a.postbox.peers[1] === other);XCTAssertEqual(o.completed,1)}
    func testCancelledLookupDoesNotWriteOrStartRequests() {let a=Account();a.postbox.automatic=false;let o=apply(a);o.disposable?.dispose();a.postbox.drain();XCTAssertEqual(a.postbox.writes,0);XCTAssertTrue(a.network.requests.isEmpty);XCTAssertEqual(o.completed,0)}
    func testCancelledBeforeResponsesKeepsLocalState() {let a=Account();let o=apply(a);o.disposable?.dispose();a.network.requests[0].1.respond(.boolTrue);a.network.requests[1].1.respond(.boolTrue);XCTAssertEqual(a.postbox.writes,0);XCTAssertTrue(a.network.requests.allSatisfy {$0.1.disposed});XCTAssertEqual(o.completed,0)}
    func testAcceptedQueuedCommitSurvivesObserverCancellation() {let a=Account();let o=apply(a);a.postbox.automatic=false;a.network.requests[0].1.respond(.boolTrue);o.disposable?.dispose();a.postbox.drain();XCTAssertEqual(user(a).nameColor,.preset(.new));XCTAssertEqual(user(a).profileColor,.old);XCTAssertEqual(o.completed,0);XCTAssertEqual(o.errors,0)}
    func testBothAcceptedQueuedCommitsSurviveCancellation() {let a=Account();let o=apply(a);a.postbox.automatic=false;a.network.requests[1].1.respond(.boolTrue);a.network.requests[0].1.respond(.boolTrue);o.disposable?.dispose();a.postbox.drain();XCTAssertEqual(user(a).nameColor,.preset(.new));XCTAssertEqual(user(a).profileColor,.new);XCTAssertEqual(o.completed,0)}
    func testPartialFailureWaitsForAcceptedCommit() {let a=Account();let o=apply(a);a.postbox.automatic=false;a.network.requests[0].1.respond(.boolTrue);a.network.requests[1].1.fail();XCTAssertEqual(o.errors,0);a.postbox.drain();XCTAssertEqual(user(a).nameColor,.preset(.new));XCTAssertEqual(user(a).profileColor,.old);XCTAssertEqual(o.errors,1)}
    func testProfileClearWaitsForAcceptance() {let a=Account();let o=apply(a,profile:nil,background:nil);XCTAssertEqual(user(a).profileColor,.old);a.network.requests[1].1.respond(.boolTrue);XCTAssertNil(user(a).profileColor);XCTAssertNil(user(a).profileBackgroundEmojiId);a.network.requests[0].1.respond(.boolTrue);XCTAssertEqual(o.completed,1)}
    func testRejectedProfileClearKeepsPreviousFields() {let a=Account();let o=apply(a,profile:nil,background:nil);a.network.requests[0].1.respond(.boolTrue);a.network.requests[1].1.respond(.boolFalse);XCTAssertEqual(user(a).profileColor,.old);XCTAssertEqual(user(a).profileBackgroundEmojiId,20);XCTAssertEqual(o.errors,1)}
    func testNamePatternClearWaitsForAcceptance() {let a=Account();let o=apply(a,name:.preset(color:.new,backgroundEmojiId:nil));XCTAssertEqual(user(a).backgroundEmojiId,10);a.network.requests[0].1.respond(.boolTrue);XCTAssertNil(user(a).backgroundEmojiId);a.network.requests[1].1.respond(.boolTrue);XCTAssertEqual(o.completed,1)}
    func testCollectibleColorMetadataCommitsAfterAcceptance() {let a=Account();let value=PeerCollectibleColor(collectibleId:100,backgroundEmojiId:55);let o=apply(a,name:.collectible(value));XCTAssertEqual(user(a).nameColor,.preset(.old));a.network.requests[0].1.respond(.boolTrue);XCTAssertEqual(user(a).nameColor,.collectible(value));XCTAssertEqual(user(a).backgroundEmojiId,55);a.network.requests[1].1.respond(.boolFalse);XCTAssertEqual(user(a).profileColor,.old);XCTAssertEqual(o.errors,1)}
    func testRejectedCollectibleDoesNotChangeName() {let a=Account();let o=apply(a,name:.collectible(.init(collectibleId:100,backgroundEmojiId:55)));a.network.requests[0].1.respond(.boolFalse);a.network.requests[1].1.respond(.boolTrue);XCTAssertEqual(user(a).nameColor,.preset(.old));XCTAssertEqual(user(a).backgroundEmojiId,10);XCTAssertEqual(o.errors,1)}
    func testWireTargetsAndPresetFlags() {let a=Account();let o=apply(a);XCTAssertEqual(a.network.requests.map {$0.0.flags},[4,6]);for request in a.network.requests {guard case let .peerColor(c)=request.0.color else {return XCTFail()};XCTAssertEqual(c.flags,3);XCTAssertEqual(c.color,2)};withExtendedLifetime(o){}}
    func testWireCollectibleIdAndProfileClearFlags() {let a=Account();let o=apply(a,name:.collectible(.init(collectibleId:100,backgroundEmojiId:55)),profile:nil,background:nil);guard case let .inputPeerColorCollectible(c)=a.network.requests[0].0.color else {return XCTFail()};XCTAssertEqual(c.collectibleId,100);guard case let .peerColor(profile)=a.network.requests[1].0.color else {return XCTFail()};XCTAssertEqual(profile.flags,0);withExtendedLifetime(o){}}
    func testDuplicateReplyDoesNotCommitTwice() {let a=Account();let o=apply(a);a.network.requests[0].1.send(.boolTrue);a.network.requests[0].1.send(.boolTrue);a.network.requests[0].1.complete();a.network.requests[1].1.respond(.boolTrue);XCTAssertEqual(a.postbox.writes,2);XCTAssertEqual(o.completed,1)}
    func testFalseThenUnexpectedTrueDoesNotChangeRejectedField() {let a=Account();let o=apply(a);a.network.requests[0].1.send(.boolFalse);a.network.requests[0].1.send(.boolTrue);a.network.requests[0].1.complete();a.network.requests[1].1.respond(.boolTrue);XCTAssertEqual(user(a).nameColor,.preset(.old));XCTAssertEqual(o.errors,1)}
    func testSynchronousResponsesCompleteAndDispose() {let a=Account();a.network.onSubscribe={_,p in p.respond(.boolTrue)};let o=apply(a);XCTAssertEqual(o.completed,1);XCTAssertTrue(a.network.requests.allSatisfy {$0.1.disposed});XCTAssertEqual(user(a).profileColor,.new)}
    func testSynchronousFailureStillStartsAndObservesOtherField() {let a=Account();a.network.onSubscribe={index,p in if index==0 {p.fail()} else {p.respond(.boolTrue)}};let o=apply(a);XCTAssertEqual(a.network.requests.count,2);XCTAssertEqual(user(a).nameColor,.preset(.old));XCTAssertEqual(user(a).profileColor,.new);XCTAssertEqual(o.errors,1)}
    func testReturnedSignalDoesNotRetainAccount() {var a:Account?=Account();weak var weakAccount=a;let signal=_internal_updateNameColorAndEmoji(account:a!,nameColor:.preset(color:.new,backgroundEmojiId:11),profileColor:.new,profileBackgroundEmojiId:21);a=nil;XCTAssertNil(weakAccount);withExtendedLifetime(signal){}}
    func testPendingOperationDoesNotRetainAccount() {var a:Account?=Account();let network=a!.network;let postbox=a!.postbox;weak var weakAccount=a;let o=apply(a!);a=nil;XCTAssertNil(weakAccount);network.requests[0].1.respond(.boolTrue);network.requests[1].1.respond(.boolTrue);XCTAssertEqual(o.completed,1);XCTAssertEqual((postbox.peers[1] as? TelegramUser)?.profileColor,.new)}
    func testColdSignalDoesNotStartWork() {let a=Account();let signal=_internal_updateNameColorAndEmoji(account:a,nameColor:.preset(color:.new,backgroundEmojiId:11),profileColor:.new,profileBackgroundEmojiId:21);XCTAssertTrue(a.network.requests.isEmpty);XCTAssertEqual(a.postbox.writes,0);withExtendedLifetime(signal){}}
    func testRepeatedSubscriptionsRemainIndependent() {let a=Account();let signal=_internal_updateNameColorAndEmoji(account:a,nameColor:.preset(color:.new,backgroundEmojiId:11),profileColor:.new,profileBackgroundEmojiId:21);let x=Observation(),y=Observation();x.start(signal);y.start(signal);x.disposable?.dispose();a.network.requests[2].1.respond(.boolTrue);a.network.requests[3].1.respond(.boolTrue);XCTAssertEqual(x.completed,0);XCTAssertEqual(y.completed,1)}
    func testDependencyTagsMatchOnlySameField() {let a=Account();let x=apply(a),y=apply(a);guard let n0=a.network.tags[0],let p0=a.network.tags[1],let n1=a.network.tags[2],let p1=a.network.tags[3] else {return XCTFail("missing tags")};XCTAssertTrue(n1.shouldDependOn(other:n0));XCTAssertTrue(p1.shouldDependOn(other:p0));XCTAssertFalse(n1.shouldDependOn(other:p0));XCTAssertFalse(p1.shouldDependOn(other:n0));withExtendedLifetime((x,y)){} }
}
