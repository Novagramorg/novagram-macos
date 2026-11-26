import Foundation
import XCTest
import SwiftSignalKit

typealias StarsAmount = Int
struct MediaId: Hashable { let id: Int }
struct EngineMedia: Equatable { typealias Id = MediaId; let id: MediaId?; var revision = 0 }
struct TelegramMediaFile: Equatable { let revision: Int }
struct EnginePeer: Equatable {
    typealias Id = Int
    typealias Presence = Int
    let id: Int
    var hash = 1
    var addressName: String? = nil
    func _asPeer() -> EnginePeer { self }
}
struct PeerReference: Equatable {
    let id: Int
    let hash: Int
    init?(_ peer: EnginePeer) { guard peer.id > 0 else { return nil }; id=peer.id; hash=peer.hash }
}
enum MessageReaction { enum Reaction: Hashable { case custom(Int64), builtin(String), stars } }
enum MediaArea: Equatable { case reaction(Int, MessageReaction.Reaction, Int) }
struct EngineStoryItem: Equatable {
    typealias ForwardInfo = Int
    let id: Int32
    var media: EngineMedia
    var alternativeMediaList: [EngineMedia] = []
    var mediaAreas: [MediaArea] = []
    var text = ""
    var isPublic = true
}
struct StoryId: Hashable { let peerId: Int; let id: Int32 }
__PRODUCTION__
final class Attempt {
    let info: StoryPreloadInfo
    var disposed = false
    var complete: (() -> Void)?
    init(_ info: StoryPreloadInfo) { self.info=info }
}
final class Account { let peerId=10 }
final class Context {
    let account=Account()
    var attempts: [Attempt] = []
    var onStart: ((Attempt)->Void)?
    var onDispose: ((Attempt)->Void)?
}
func preloadStoryMedia(context: Context, info: StoryPreloadInfo) -> Signal<Never, NoError> {
    Signal { subscriber in
        let attempt=Attempt(info); context.attempts.append(attempt)
        attempt.complete=subscriber.putCompletion
        context.onStart?(attempt)
        return ActionDisposable { attempt.disposed=true; attempt.complete=nil; context.onDispose?(attempt) }
    }
}
func additional(_ quality: Bool = false, paid: Int? = nil, muted: Bool = false) -> StoryContentContextState.AdditionalPeerData {
    .init(isMuted: muted,areVoiceMessagesAvailable: true,presence: nil,canViewStats: false,premiumRequired: false,preferHighQualityStories: quality,slowModeTimeout: nil,slowModeValidUntilTimestamp: nil,canAvoidRestrictions: false,paidMessage: paid)
}
func content(_ story: EngineStoryItem, position: Int? = nil, files: [MediaId:TelegramMediaFile] = [:], day: Int? = nil) -> StoryContentItem {
    .init(position: position,dayCounters: day.map { .init(position: $0,totalCount: 3) },peer: .init(id: 10),storyItem: story,entityFiles: files,itemPeer: nil)
}
func slice(_ items: [EngineStoryItem], quality: Bool, data: StoryContentContextState.AdditionalPeerData? = nil) -> StoryContentContextState.FocusedSlice? {
    guard let first=items.first else { return nil }
    return .init(peer: .init(id: 10),additionalPeerData: data ?? additional(quality),item: content(first),totalCount: items.count,previousItemId: nil,nextItemId: items.dropFirst().first?.id,allItems: items.map { content($0) },forwardInfoStories: [:])
}
final class Feed {
    let context: Context
    __PROPERTIES__
    init(_ c: Context) { context=c }
    func update(_ possibleItems: [(EnginePeer, EngineStoryItem)], quality: Bool = false) {
        let context=self.context
        let stateValue=StoryContentContextState(slice: slice(possibleItems.map { $0.1 },quality: quality),previousSlice: nil,nextSlice: nil)
        __FEED__
    }
    func dispose() { __DISPOSE__ }
    deinit { dispose() }
}
final class List {
    let context: Context
    __PROPERTIES__
    var stateValue: StoryContentContextState?
    let statePromise=Promise<StoryContentContextState>()
    let updatedPromise=Promise<Void>()
    struct Item { let storyItem: EngineStoryItem }
    struct State { let items: [Item] }
    init(_ c: Context) { context=c }
    func update(_ values: [EngineStoryItem], quality preferHighQualityStories: Bool = false) {
        let context=self.context
        let peer=EnginePeer(id: 10)
        let focusedIndex: Int? = values.isEmpty ? nil : 0
        let state=State(items: values.map { Item(storyItem: $0) })
        let stateValue=StoryContentContextState(slice: slice(values,quality: preferHighQualityStories),previousSlice: nil,nextSlice: nil)
        __LIST__
    }
    func dispose() { __DISPOSE__ }
    deinit { dispose() }
}
final class StoryPreloadFreshnessTests: XCTestCase {
    func item(_ id: Int32 = 1, media: Int = 100, revision: Int = 0, alt: Int? = nil, reactions: [MessageReaction.Reaction] = []) -> EngineStoryItem {
        .init(id: id,media: .init(id: .init(id: media),revision: revision),alternativeMediaList: alt.map { [.init(id: .init(id: $0))] } ?? [],mediaAreas: reactions.map { .reaction(0,$0,0) })
    }
    func testFeedQualitySwitchRestartsSelectedResource() {
        let c=Context(); let f=Feed(c); let values=[(EnginePeer(id: 10),item(alt: 101))]
        f.update(values); f.update(values,quality: true)
        XCTAssertEqual(c.attempts.map { $0.info.media.id?.id },[101,100]); XCTAssertTrue(c.attempts.first?.disposed == true)
    }
    func testFeedSameIDResourceEditRestarts() {
        let c=Context(); let f=Feed(c)
        f.update([(.init(id: 10),item())]); f.update([(.init(id: 10),item(revision: 2))])
        XCTAssertEqual(c.attempts.count,2); XCTAssertEqual(c.attempts.last?.info.media.revision,2); XCTAssertTrue(c.attempts.first?.disposed == true)
    }
    func testFeedReactionEditRestarts() {
        let c=Context(); let f=Feed(c)
        f.update([(.init(id: 10),item(reactions: [.custom(1)]))]); f.update([(.init(id: 10),item(reactions: [.custom(2)]))])
        XCTAssertEqual(c.attempts.count,2); XCTAssertEqual(c.attempts.last?.info.reactions,[.custom(2)])
    }
    func testSameMediaDifferentStoriesKeepIndependentReferences() {
        let c=Context(); let f=Feed(c); f.update([(.init(id: 10),item(1)),(.init(id: 10),item(2))])
        XCTAssertEqual(c.attempts.map { $0.info.storyId },[1,2])
    }
    func testSameMediaAcrossPeersKeepsIndependentReferences() {
        let c=Context(); let f=Feed(c); f.update([(.init(id: 10),item()),(.init(id: 20),item())])
        XCTAssertEqual(c.attempts.map { $0.info.peer.id },[10,20])
    }
    func testRenewedPeerAccessHashRestarts() {
        let c=Context(); let f=Feed(c); f.update([(.init(id: 10),item())]); f.update([(.init(id: 10,hash: 2),item())])
        XCTAssertEqual(c.attempts.count,2); XCTAssertEqual(c.attempts.last?.info.peer.hash,2)
    }
    func testUnchangedFeedReusesAttempt() {
        let c=Context(); let f=Feed(c); let values=[(EnginePeer(id: 10),item())]
        f.update(values); f.update(values); XCTAssertEqual(c.attempts.count,1); XCTAssertFalse(c.attempts[0].disposed)
    }
    func testReactionOrderAndDuplicatesDoNotRestart() {
        let c=Context(); let f=Feed(c)
        f.update([(.init(id: 10),item(reactions: [.custom(1),.custom(2)]))]); f.update([(.init(id: 10),item(reactions: [.custom(2),.custom(1),.custom(2)]))])
        XCTAssertEqual(c.attempts.count,1)
    }
    func testTextOnlyEditDoesNotRestartMedia() {
        let c=Context(); let f=Feed(c); var value=item(); f.update([(.init(id: 10),value)]); value.text="edited"; f.update([(.init(id: 10),value)])
        XCTAssertEqual(c.attempts.count,1)
    }
    func testEmptyWindowCancelsAndReentryRetries() {
        let c=Context(); let f=Feed(c); let values=[(EnginePeer(id: 10),item())]
        f.update(values); c.attempts[0].complete?(); f.update([]); f.update(values); XCTAssertEqual(c.attempts.count,2)
    }
    func testSlidingWindowDisposesBeforeStartingReplacement() {
        let c=Context(); let f=Feed(c); f.update([(.init(id: 10),item(1))])
        c.onStart={ _ in XCTAssertTrue(c.attempts[0].disposed) }; f.update([(.init(id: 10),item(2,media: 200))]); XCTAssertEqual(c.attempts.count,2)
    }
    func testWindowIsBoundedToThreeStories() {
        let c=Context(); let f=Feed(c); f.update((1...5).map { (.init(id: 10),item(Int32($0),media: $0)) })
        XCTAssertEqual(c.attempts.map { $0.info.storyId },[1,2,3])
    }
    func testDuplicateStoryUsesFirstPosition() {
        let c=Context(); let f=Feed(c); f.update([(.init(id: 10),item(revision: 1)),(.init(id: 10),item(revision: 2))])
        XCTAssertEqual(c.attempts.count,1); XCTAssertEqual(c.attempts.first?.info.media.revision,1)
    }
    func testListQualitySwitchPublishesAndRestarts() {
        let c=Context(); let l=List(c); let values=[item(1),item(2,alt: 101)]
        l.update(values); l.update(values,quality: true)
        XCTAssertEqual(l.stateValue?.slice?.additionalPeerData.preferHighQualityStories,true)
        XCTAssertEqual(c.attempts.map { $0.info.media.id?.id },[101,100]); XCTAssertTrue(c.attempts.first?.disposed == true)
    }
    func testListNeighborEditPublishesAndRestarts() {
        let c=Context(); let l=List(c); l.update([item(1),item(2)])
        l.update([item(1),item(2,revision: 2)])
        XCTAssertEqual(c.attempts.count,2); XCTAssertEqual(l.stateValue?.slice?.allItems.last?.storyItem.media.revision,2)
    }
    func testListNeighborReactionChangeRestarts() {
        let c=Context(); let l=List(c); l.update([item(1),item(2,reactions: [.custom(1)])])
        l.update([item(1),item(2,reactions: [.custom(2)])]); XCTAssertEqual(c.attempts.count,2)
    }
    func testListSameMediaNeighborsRemainDistinct() {
        let c=Context(); let l=List(c); l.update([item(1),item(2),item(3)])
        XCTAssertEqual(c.attempts.map { $0.info.storyId },[2,3])
    }
    func testListDoesNotRestartForUnchangedSnapshot() {
        let c=Context(); let l=List(c); let values=[item(1),item(2)]
        l.update(values); l.update(values); XCTAssertEqual(c.attempts.count,1)
    }
    func testListEmptySnapshotCancelsPreloads() {
        let c=Context(); let l=List(c); l.update([item(1),item(2)]); l.update([])
        XCTAssertTrue(c.attempts[0].disposed); XCTAssertNil(l.stateValue?.slice)
    }
    func testOwnerReleaseCancelsPreloads() {
        let c=Context(); var f: Feed?=Feed(c); weak var owner=f; f?.update([(.init(id: 10),item())]); f=nil
        XCTAssertNil(owner); XCTAssertTrue(c.attempts[0].disposed)
    }
    func testSliceEqualityIncludesFeeAndMuteSettings() {
        let values=[item()]; let a=slice(values,quality: false)
        XCTAssertNotEqual(a,slice(values,quality: false,data: additional(paid: 5)))
        XCTAssertNotEqual(a,slice(values,quality: false,data: additional(muted: true)))
    }
    func changedSlice(_ value: StoryContentItem) -> StoryContentContextState.FocusedSlice {
        .init(peer: .init(id: 10),additionalPeerData: additional(),item: value,totalCount: 1,previousItemId: nil,nextItemId: nil,allItems: [value],forwardInfoStories: [:])
    }
    func testSliceEqualityIncludesEntityFiles() {
        XCTAssertNotEqual(changedSlice(content(item())),changedSlice(content(item(),files: [.init(id: 1):.init(revision: 2)])))
    }
    func testSliceEqualityIncludesDayAndPosition() {
        let a=changedSlice(content(item()))
        XCTAssertNotEqual(a,changedSlice(content(item(),position: 2))); XCTAssertNotEqual(a,changedSlice(content(item(),day: 2)))
    }
    func testOwnerReleaseAlsoReleasesContext() {
        var c: Context?=Context(); weak var context=c; var f: Feed?=Feed(c!)
        f?.update([(.init(id: 10),item())]); c=nil; f=nil; XCTAssertNil(context)
    }
    func testListOwnerReleaseCancelsPreloads() {
        let c=Context(); var l: List?=List(c); weak var owner=l; l?.update([item(1),item(2)]); l=nil
        XCTAssertNil(owner); XCTAssertTrue(c.attempts[0].disposed)
    }
    func testValidAlternativeCanPreloadWithoutPrimaryMediaID() {
        let c=Context(); let f=Feed(c); var value=item(alt: 101); value.media = .init(id: nil)
        f.update([(.init(id: 10),value)]); XCTAssertEqual(c.attempts.first?.info.media.id?.id,101)
    }
    func testInvalidPeerAndMissingMediaDoNotPreload() {
        let c=Context(); let f=Feed(c); var value=item(); value.media = .init(id: nil)
        f.update([(.init(id: -1),item()),(.init(id: 10),value)]); XCTAssertTrue(c.attempts.isEmpty)
    }

}
__MANAGER_TESTS__
