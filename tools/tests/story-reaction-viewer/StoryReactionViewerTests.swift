import Foundation
import XCTest
import SwiftSignalKit
struct Peer { let id:Int }
struct Story { let id:Int32; let myReaction:Int? }
struct Item { let storyItem:Story }
struct Slice { let peer:Peer; let item:Item }
struct ContentState { let slice:Slice? }
final class StoryContext { var stateValue:ContentState? }
final class View { var storyContext:StoryContext?=StoryContext() }
struct InteractionState { let entryId:Int?; let storyId:Int32? }
final class Messages {
    struct Request { let peer:Int; let id:Int32; let reaction:Int?; let previous:Int?? }
    var requests:[Request]=[]
    func setStoryReaction(peerId:Int,id:Int32,reaction:Int?)->Signal<Never,NoError> {
        requests.append(.init(peer:peerId,id:id,reaction:reaction,previous:nil));return .complete()
    }
    func setStoryReaction(peerId:Int,id:Int32,reaction:Int?,previousReaction:Int?)->Signal<Never,NoError> {
        requests.append(.init(peer:peerId,id:id,reaction:reaction,previous:.some(previousReaction)));return .complete()
    }
}
final class Engine { let messages=Messages() }
final class Context { let engine=Engine() }
final class Analytics { static let shared=Analytics();var count=0;func send(_ event:Int) { count+=1 } }
enum AnalyticsEvents { static func storiesReact()->Int { 1 } }
final class Controller {
    let context=Context();let genericView=View()
    func action()->(Int?,InteractionState)->Void {
        let context=self.context
        return { [weak self] current,state in
__ACTION__
        }
    }
}
final class StoryReactionViewerTests:XCTestCase {
    override func setUp() { Analytics.shared.count=0 }
    func seed(_ c:Controller,peer:Int=10,id:Int32=1,previous:Int?=nil) {
        c.genericView.storyContext?.stateValue = .init(slice:.init(peer:.init(id:peer),item:.init(storyItem:.init(id:id,myReaction:previous))))
    }
    func testCurrentStoryProvidesKnownPreviousReaction() {
        let c=Controller();seed(c,previous:3);c.action()(4,.init(entryId:10,storyId:1))
        let request=c.context.engine.messages.requests.first
        XCTAssertEqual(request?.peer,10);XCTAssertEqual(request?.id,1);XCTAssertEqual(request?.reaction,4)
        if let outer=request?.previous { XCTAssertEqual(outer,3) } else { XCTFail("Unknown baseline") }
        XCTAssertEqual(Analytics.shared.count,1)
    }
    func testKnownNilSelectionRemainsKnown() {
        let c=Controller();seed(c);c.action()(4,.init(entryId:10,storyId:1))
        guard let request=c.context.engine.messages.requests.first else { return XCTFail() }
        switch request.previous { case .some(.none): break; default:XCTFail("Known nil lost") }
    }
    func testRemovalCarriesPreviousReactionWithoutReactAnalytics() {
        let c=Controller();seed(c,previous:3);c.action()(nil,.init(entryId:10,storyId:1))
        XCTAssertNil(c.context.engine.messages.requests.first?.reaction);XCTAssertEqual(Analytics.shared.count,0)
    }
    func testStalePeerCannotReactToCurrentStory() {
        let c=Controller();seed(c,peer:20);c.action()(4,.init(entryId:10,storyId:1))
        XCTAssertTrue(c.context.engine.messages.requests.isEmpty);XCTAssertEqual(Analytics.shared.count,0)
    }
    func testStaleStoryCannotReactAfterNavigation() {
        let c=Controller();seed(c,id:2);c.action()(4,.init(entryId:10,storyId:1));XCTAssertTrue(c.context.engine.messages.requests.isEmpty)
    }
    func testMissingCurrentSliceDoesNotInventBaseline() {
        let c=Controller();c.action()(4,.init(entryId:10,storyId:1));XCTAssertTrue(c.context.engine.messages.requests.isEmpty)
    }
    func testMissingTargetIdentityDoesNotReact() {
        let c=Controller();seed(c);c.action()(4,.init(entryId:nil,storyId:1));c.action()(4,.init(entryId:10,storyId:nil));XCTAssertTrue(c.context.engine.messages.requests.isEmpty)
    }
    func testRetainedActionDoesNotRetainClosedControllerOrReact() {
        var c:Controller?=Controller();seed(c!);let context=c!.context;let action=c!.action();weak var weakController=c;c=nil
        XCTAssertNil(weakController);action(4,.init(entryId:10,storyId:1));XCTAssertTrue(context.engine.messages.requests.isEmpty)
    }
}
