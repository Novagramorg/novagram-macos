import Foundation
import SwiftSignalKit
import XCTest

final class Context {}
final class Request {
    weak var operation:MediaObjectToAvatar?;let subscriber:Subscriber<MediaObjectToAvatar.Result,NoError>;var disposed=false
    init(_ operation:MediaObjectToAvatar,_ subscriber:Subscriber<MediaObjectToAvatar.Result,NoError>) {self.operation=operation;self.subscriber=subscriber}
}
final class Endpoint {static var requests:[Request]=[];static var synchronous=false;static var preparations=0}
final class MediaObjectToAvatar {
    struct Result {enum Status {case failed};var status:Status?=nil;let result:Int?}
    let context:Context;let object:Int;let codec:String;var holder:MediaObjectToAvatar?
    init(context:Context,object:Int=1,codec:String="codec") {self.context=context;self.object=object;self.codec=codec}
    __START__
    func generate()->Signal<Result,NoError> {Endpoint.preparations+=1;return Signal { [weak self] s in guard let self else {return EmptyDisposable};let r=Request(self,s);Endpoint.requests.append(r);if Endpoint.synchronous {s.putNext(Result(result:1));s.putCompletion()};return ActionDisposable {r.disposed=true}}}
}
final class AvatarGeneratorLifetimeTests:XCTestCase {
    override func setUp() {Endpoint.requests=[];Endpoint.synchronous=false;Endpoint.preparations=0}
    func testCreatingSignalDoesNotStartGenerator() {let value=MediaObjectToAvatar(context:Context());let signal=value.start();XCTAssertTrue(Endpoint.requests.isEmpty);XCTAssertEqual(Endpoint.preparations,0);withExtendedLifetime(signal) {}}
    func testUnsubscribedSignalDoesNotRetainGenerator() {var value:MediaObjectToAvatar?=MediaObjectToAvatar(context:Context());weak var weakValue=value;let signal=value!.start();value=nil;XCTAssertNil(weakValue);withExtendedLifetime(signal) {}}
    func testUnusedSignalReleaseReleasesContext() {var context:Context?=Context();weak var weakContext=context;var signal:Signal<MediaObjectToAvatar.Result,NoError>?=MediaObjectToAvatar(context:context!).start();context=nil;XCTAssertNotNil(weakContext);signal=nil;XCTAssertNil(weakContext);withExtendedLifetime(signal) {}}
    func testSubscriptionKeepsOperationAliveUntilCancelled() {let signal=MediaObjectToAvatar(context:Context()).start();let d=signal.start();guard let r=Endpoint.requests.first else {return XCTFail("No generator")};XCTAssertNotNil(r.operation);d.dispose();XCTAssertTrue(r.disposed);XCTAssertNil(r.operation)}
    func testPendingCancellationReleasesAccountContext() {var context:Context?=Context();weak var weakContext=context;var signal:Signal<MediaObjectToAvatar.Result,NoError>?=MediaObjectToAvatar(context:context!).start();context=nil;let d=signal!.start();signal=nil;XCTAssertNotNil(weakContext);d.dispose();XCTAssertNil(weakContext)}
    func testSubscriptionsHaveIndependentOperations() {let signal=MediaObjectToAvatar(context:Context()).start();let a=signal.start(),b=signal.start();XCTAssertEqual(Endpoint.requests.count,2);guard Endpoint.requests.count==2 else {return};let ra=Endpoint.requests[0],rb=Endpoint.requests[1];XCTAssertFalse(ra.operation === rb.operation);a.dispose();XCTAssertNil(ra.operation);XCTAssertNotNil(rb.operation);XCTAssertFalse(rb.disposed);b.dispose();XCTAssertNil(rb.operation)}
    func testEmptyCompletionReleasesOperation() {let d=MediaObjectToAvatar(context:Context()).start().start();guard let r=Endpoint.requests.first else {return XCTFail("No generator")};r.subscriber.putCompletion();XCTAssertTrue(r.disposed);XCTAssertNil(r.operation);withExtendedLifetime(d) {}}
    func testFailureResultThenCancellationReleasesOperation() {var values=0;let d=MediaObjectToAvatar(context:Context()).start().start(next:{_ in values+=1});guard let r=Endpoint.requests.first else {return XCTFail("No generator")};r.subscriber.putNext(.init(result:nil));d.dispose();XCTAssertEqual(values,1);XCTAssertNil(r.operation);XCTAssertTrue(r.disposed)}
    func testSynchronousCompletionReleasesOperation() {Endpoint.synchronous=true;var values=0;let d=MediaObjectToAvatar(context:Context()).start().start(next:{_ in values+=1});XCTAssertEqual(values,1);XCTAssertTrue(Endpoint.requests[0].disposed);let drained=expectation(description:"Main queue cleanup");DispatchQueue.main.async {drained.fulfill()};wait(for:[drained],timeout:1);XCTAssertNil(Endpoint.requests[0].operation);withExtendedLifetime(d) {}}
    func testLateResultAfterCancellationIsIgnored() {var values=0;let d=MediaObjectToAvatar(context:Context()).start().start(next:{_ in values+=1});let r=Endpoint.requests[0];d.dispose();r.subscriber.putNext(.init(result:1));XCTAssertEqual(values,0)}
    func testSuccessfulResultTerminatesOnce() {var values=0;var completions=0;let d=MediaObjectToAvatar(context:Context()).start().start(next:{_ in values+=1},completed:{completions+=1});let r=Endpoint.requests[0];r.subscriber.putNext(.init(result:1));r.subscriber.putNext(.init(result:2));XCTAssertEqual(values,1);XCTAssertEqual(completions,1);XCTAssertTrue(r.disposed);XCTAssertNil(r.operation);withExtendedLifetime(d) {}}
    func testExplicitFailureTerminatesAndReleasesGenerator() {var failed=0;var completed=0;let d=MediaObjectToAvatar(context:Context()).start().start(next:{if case .failed=$0.status {failed+=1}},completed:{completed+=1});let r=Endpoint.requests[0];r.subscriber.putNext(.init(status:.failed,result:nil));XCTAssertEqual(failed,1);XCTAssertEqual(completed,1);XCTAssertTrue(r.disposed);XCTAssertNil(r.operation);withExtendedLifetime(d) {}}
    func testEmptySourceReportsTerminalFailure() {var failed=0;let d=MediaObjectToAvatar(context:Context()).start().start(next:{if case .failed=$0.status {failed+=1}});Endpoint.requests[0].subscriber.putCompletion();XCTAssertEqual(failed,1);withExtendedLifetime(d) {}}
    func testProgressDoesNotTerminateBeforeResult() {var values=0;var completed=0;let d=MediaObjectToAvatar(context:Context()).start().start(next:{_ in values+=1},completed:{completed+=1});let r=Endpoint.requests[0];r.subscriber.putNext(.init(result:nil));XCTAssertEqual(completed,0);XCTAssertFalse(r.disposed);r.subscriber.putNext(.init(result:1));XCTAssertEqual(values,2);XCTAssertEqual(completed,1);withExtendedLifetime(d) {}}

}
