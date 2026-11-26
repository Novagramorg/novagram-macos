import Foundation
import XCTest
import SwiftSignalKit

struct EnginePeer { typealias Id=Int; let id:Int }
struct EngineStoryItem { let id:Int32 }
struct StoryId:Hashable { let peerId:Int; let id:Int32 }
__SOURCE__
final class Request {
    let peer:Int
    let ids:[Int32]
    var subscriber:Subscriber<Never,NoError>?
    var canceled=false
    init(_ peer:Int,_ ids:[Int32]) { self.peer=peer; self.ids=ids }
    func finish() { subscriber?.putCompletion() }
}
final class Messages {
    var requests:[Request]=[]
    var onStart:((Request)->Void)?
    var onDispose:((Request)->Void)?
    func refreshStoryViews(peerId:Int,ids:[Int32])->Signal<Never,NoError> {
        Signal { subscriber in
            let request=Request(peerId,ids); request.subscriber=subscriber; self.requests.append(request); self.onStart?(request)
            return ActionDisposable { request.canceled=true; request.subscriber=nil; self.onDispose?(request) }
        }
    }
}
final class Engine { let messages=Messages() }
final class Account { let peerId=10 }
final class Context {
    let account=Account()
    let engine=Engine()
    var now:Double=0
    var requests:[Request] { engine.messages.requests }
}
func storyPreloadInfos(_ items:[(EnginePeer,EngineStoryItem)],preferHighQualityStories:Bool)->[Int] { [] }
final class Feed {
    let context:Context
    __FEED_PROPERTIES__
    init(_ c:Context) { self.context=c; __INIT__ }
    func update(_ ids:[Int32],peer:Int=10) { updateKeys(ids.map { StoryKey(peerId:peer,id:$0) }) }
    fileprivate func updateKeys(_ pollItems:[StoryKey]) { __FEED__ }
    func dispose() { __FEED_DISPOSE__ }
    deinit { dispose() }
}
final class List {
    let context:Context
    __LIST_PROPERTIES__
    init(_ c:Context) { self.context=c; __INIT__ }
    struct Item { let storyItem:EngineStoryItem }
    struct Slice { let peer:EnginePeer; let item:Item }
    struct StateValue { let slice:Slice? }
    struct State { let items:[Item] }
    func update(_ ids:[Int32],focus:Int=0,peer peerId:Int=10) {
        let peer=EnginePeer(id:peerId)
        let values=ids.map { Item(storyItem:.init(id:$0)) }
        let focusedIndex:Int?=values.indices.contains(focus) ? focus : nil
        let stateValue=StateValue(slice:focusedIndex.map { Slice(peer:peer,item:values[$0]) })
        let state=State(items:values)
        let preferHighQualityStories=false
        var preloadInfos:[Int]=[]
        __LIST__
        _=preloadInfos
    }
    func dispose() { __LIST_DISPOSE__ }
    deinit { dispose() }
}
final class StoryMetadataRefreshTests:XCTestCase {
    func testFeedSendsOneBatchNotOnePerStory() {
        let c=Context(); let f=Feed(c); f.update([1,2,3]); XCTAssertEqual(c.requests.count,1); XCTAssertEqual(c.requests.first?.ids,[1,2,3])
    }
    func testFeedDeduplicatesBeforeThreeStoryLimit() {
        let c=Context(); let f=Feed(c); f.update([1,1,2,3,4]); XCTAssertEqual(c.requests.count,1); XCTAssertEqual(c.requests.first?.ids,[1,2,3])
    }
    func testListIncludesFocusedAndTwoFollowingStories() {
        let c=Context(); let l=List(c); l.update([1,2,3,4]); XCTAssertEqual(c.requests.count,1); XCTAssertEqual(c.requests.first?.ids,[1,2,3])
    }
    func testListFocusOffsetSelectsCorrectWindow() {
        let c=Context(); let l=List(c); l.update([1,2,3,4,5],focus:2); XCTAssertEqual(c.requests.first?.ids,[3,4,5])
    }
    func testListOwnStoryEligibilityPreserved() {
        let c=Context(); let l=List(c); l.update([1,2,3],peer:20); XCTAssertTrue(c.requests.isEmpty)
    }
    func testUnchangedFeedDoesNotOverlapRequests() {
        let c=Context(); let f=Feed(c); f.update([1,2]); c.now=100
        for _ in 0..<20 { f.update([1,2]) }; XCTAssertEqual(c.requests.count,1)
    }
    func testListCountChangesCannotStartFeedbackLoop() {
        let c=Context(); let l=List(c); l.update([1,2,3])
        for _ in 0..<20 { l.update([1,2,3]) }; XCTAssertEqual(c.requests.count,1)
    }
    func testCompletedListWaitsForCooldown() {
        let c=Context(); let l=List(c); l.update([1,2]); c.requests[0].finish()
        l.update([1,2]); c.now=9.9; l.update([1,2]); XCTAssertEqual(c.requests.count,1)
        c.now=10; l.update([1,2]); XCTAssertEqual(c.requests.count,2)
    }
    func testCompletedFeedCanRetryOnLaterStateUpdate() {
        let c=Context(); let f=Feed(c); f.update([1]); c.requests[0].finish(); c.now=10; f.update([1]); XCTAssertEqual(c.requests.count,2)
    }
    func testCooldownStartsAtCompletionNotRequestStart() {
        let c=Context(); let f=Feed(c); f.update([1]); c.now=100; c.requests[0].finish(); f.update([1]); XCTAssertEqual(c.requests.count,1)
        c.now=110; f.update([1]); XCTAssertEqual(c.requests.count,2)
    }
    func testNoBackgroundTimerStartsRequests() {
        let c=Context(); let f=Feed(c); f.update([1]); c.requests[0].finish(); c.now=100; XCTAssertEqual(c.requests.count,1)
    }
    func testNavigationCancelsOldBatchBeforeNewStart() {
        let c=Context(); let f=Feed(c); f.update([1,2,3]); let old=c.requests
        c.engine.messages.onStart={ _ in XCTAssertTrue(old.allSatisfy { $0.canceled }) }; f.update([2,3,4]); XCTAssertEqual(c.requests.count,2)
    }
    func testListNavigationCancelsOldBatch() {
        let c=Context(); let l=List(c); l.update([1,2,3,4]); let old=c.requests[0]; l.update([1,2,3,4],focus:1)
        XCTAssertTrue(old.canceled); XCTAssertEqual(c.requests.last?.ids,[2,3,4])
    }
    func testEmptyFeedWindowCancelsAndReentryRefreshes() {
        let c=Context(); let f=Feed(c); f.update([1]); let old=c.requests[0]; f.update([]); XCTAssertTrue(old.canceled)
        f.update([1]); XCTAssertEqual(c.requests.count,2)
    }
    func testEmptyListWindowCancelsAndReentryRefreshes() {
        let c=Context(); let l=List(c); l.update([1]); let old=c.requests[0]; l.update([]); XCTAssertTrue(old.canceled)
        l.update([1]); XCTAssertEqual(c.requests.count,2)
    }
    func testSwitchingPeerCancelsPreviousPeer() {
        let c=Context(); let f=Feed(c); f.update([1],peer:10); f.update([1],peer:20)
        XCTAssertTrue(c.requests[0].canceled); XCTAssertEqual(c.requests.last?.peer,20)
    }
    func testPeerBatchesPreserveDistinctStoryIdentity() {
        let c=Context(); let f=Feed(c); f.updateKeys([.init(peerId:10,id:1),.init(peerId:20,id:1),.init(peerId:10,id:2)])
        XCTAssertEqual(c.requests.count,2); XCTAssertEqual(c.requests[0].peer,10); XCTAssertEqual(c.requests[0].ids,[1,2]); XCTAssertEqual(c.requests[1].ids,[1])
    }
    func testInvalidIdsDoNotOccupyWindow() {
        let c=Context(); let f=Feed(c); f.update([0,-1,1,2,3]); XCTAssertEqual(c.requests.first?.ids,[1,2,3])
    }
    func testManyVisitedWindowsDoNotKeepActiveOldRequests() {
        let c=Context(); let f=Feed(c)
        for i in 1...100 { f.update([Int32(i)]); XCTAssertEqual(c.requests.filter { !$0.canceled }.count,1) }
        f.update([1]); XCTAssertEqual(c.requests.count,101); XCTAssertEqual(c.requests.filter { !$0.canceled }.count,1)
    }
    func testReorderedWindowRefreshesOnce() {
        let c=Context(); let f=Feed(c); f.update([1,2]); f.update([2,1]); XCTAssertEqual(c.requests.count,2); XCTAssertEqual(c.requests.last?.ids,[2,1])
    }
    func testCompletionReleasesSubscriptionImmediately() {
        let c=Context(); let f=Feed(c); f.update([1]); c.requests[0].finish(); XCTAssertTrue(c.requests[0].canceled); XCTAssertNil(c.requests[0].subscriber)
    }
    func testOwnerReleaseCancelsFeedRequest() {
        let c=Context(); var f:Feed?=Feed(c); weak var owner=f; f?.update([1]); f=nil; XCTAssertNil(owner); XCTAssertTrue(c.requests[0].canceled)
    }
    func testOwnerReleaseCancelsListRequest() {
        let c=Context(); var l:List?=List(c); weak var owner=l; l?.update([1]); l=nil; XCTAssertNil(owner); XCTAssertTrue(c.requests[0].canceled)
    }
    func testSynchronousCompletionCannotLoopDuringPublication() {
        let c=Context(); let f=Feed(c); c.engine.messages.onStart={ $0.finish() }; f.update([1]); f.update([1])
        XCTAssertEqual(c.requests.count,1); XCTAssertTrue(c.requests[0].canceled); c.now=10; f.update([1]); XCTAssertEqual(c.requests.count,2)
    }
}
__MANAGER_TESTS__
