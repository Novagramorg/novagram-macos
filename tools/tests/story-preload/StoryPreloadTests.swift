import Foundation
import XCTest
import SwiftSignalKit
import RangeSet

final class Probe<T, E> {
    var initial: T?
    var finishOnStart = false
    var errorOnStart: E?
    var starts = 0
    var disposals = 0
    var subscribers: [UUID: Subscriber<T, E>] = [:]
    init(_ initial: T? = nil) { self.initial = initial }
    var signal: Signal<T, E> {
        Signal { subscriber in
            self.starts += 1
            let id = UUID(); self.subscribers[id] = subscriber
            if let initial = self.initial { subscriber.putNext(initial) }
            if let error = self.errorOnStart { subscriber.putError(error) }
            if self.finishOnStart { subscriber.putCompletion() }
            return ActionDisposable { self.subscribers.removeValue(forKey: id); self.disposals += 1 }
        }
    }
    func send(_ value: T) { for subscriber in Array(subscribers.values) { subscriber.putNext(value) } }
    func fail(_ error: E) { for subscriber in Array(subscribers.values) { subscriber.putError(error) } }
    func complete() { for subscriber in Array(subscribers.values) { subscriber.putCompletion() } }
    var active: Int { subscribers.count }
}
struct ResourceId: Hashable { let stringRepresentation: String }
struct Resource { let id: ResourceId; init(_ id: String) { self.id = .init(stringRepresentation: id) } }
struct MediaId: Hashable { let id: Int64 }
enum Attribute { case Video(Int, Int, Int, Int32?, Int, Int) }
struct TelegramMediaFile {
    let fileId: MediaId
    let resource: Resource
    var size: Int64? = nil
    var attributes: [Attribute] = []
    func _parse() -> TelegramMediaFile { self }
}
struct ImageRepresentation { let resource: Resource }
struct Image { let representations: [ImageRepresentation] }
func largestImageRepresentation(_ values: [ImageRepresentation]) -> ImageRepresentation? { values.last }
enum EngineMedia { case image(Image), file(TelegramMediaFile), unsupported; func _asMedia() -> EngineMedia { self } }
struct EnginePeer {
    typealias Id = Int
    let id: Int
    var isPremium = false
    func _asPeer() -> EnginePeer { self }
}
struct PeerReference {
    let id: Int
    init?(_ peer: EnginePeer) { guard peer.id > 0 else { return nil }; id = peer.id }
}
enum MessageReaction { enum Reaction: Equatable { case builtin(String), custom(Int64), stars } }
enum MediaArea { case reaction(Int, MessageReaction.Reaction, Int) }
struct EngineStoryItem {
    var id: Int32 = 1
    var media: EngineMedia = .unsupported
    var alternativeMediaList: [EngineMedia] = []
    var mediaAreas: [MediaArea] = []
}
struct StoryPreloadInfo { let peer: PeerReference; let storyId: Int32; let media: EngineMedia; let reactions: [MessageReaction.Reaction] }
enum MediaBoxFetchPriority { case `default` }
enum FetchResourceError { case generic }
enum FetchResourceSourceType { case local, remote }
enum MediaStatus { case Local, Remote }
struct ResourceData { let complete: Bool }
struct CachedVideoFirstFrameRepresentation {}
enum UserLocation { case peer(Int), other }
enum UserContentType { case story, sticker }
enum MediaReference { case story(peer: PeerReference, id: Int32, media: EngineMedia) }
enum ResourceReference {
    case media(media: MediaReference, resource: Resource), standalone(resource: Resource)
    var resource: Resource { switch self { case let .media(_, resource), let .standalone(resource): return resource } }
}
final class MediaBox {
    var statuses: [String: Probe<MediaStatus, NoError>] = [:]
    var data: [String: Probe<ResourceData, NoError>] = [:]
    var ranges: [String: Probe<RangeSet<Int64>, NoError>] = [:]
    var fetches: [String: Probe<FetchResourceSourceType, FetchResourceError>] = [:]
    var frames: [String: Probe<Int, NoError>] = [:]
    var requests: [(String, Range<Int64>?)] = []
    func status(_ id: String) -> Probe<MediaStatus, NoError> {
        if statuses[id] == nil { statuses[id] = Probe(.Remote) }; return statuses[id]!
    }
    func dataProbe(_ id: String) -> Probe<ResourceData, NoError> {
        if data[id] == nil { data[id] = Probe(.init(complete: false)) }; return data[id]!
    }
    func rangeProbe(_ id: String) -> Probe<RangeSet<Int64>, NoError> {
        if ranges[id] == nil { ranges[id] = Probe(RangeSet<Int64>()) }; return ranges[id]!
    }
    func fetch(_ id: String) -> Probe<FetchResourceSourceType, FetchResourceError> {
        if fetches[id] == nil { fetches[id] = Probe() }; return fetches[id]!
    }
    func frame(_ id: String) -> Probe<Int, NoError> {
        if frames[id] == nil { frames[id] = Probe() }; return frames[id]!
    }
    func resourceStatus(_ resource: Resource) -> Signal<MediaStatus, NoError> { status(resource.id.stringRepresentation).signal }
    func resourceData(_ resource: Resource) -> Signal<ResourceData, NoError> { dataProbe(resource.id.stringRepresentation).signal }
    func resourceRangesStatus(_ resource: Resource) -> Signal<RangeSet<Int64>, NoError> { rangeProbe(resource.id.stringRepresentation).signal }
    func cachedResourceRepresentation(_ resource: Resource, representation: CachedVideoFirstFrameRepresentation, complete: Bool, fetch: Bool, attemptSynchronously: Bool) -> Signal<Int, NoError> { frame(resource.id.stringRepresentation).signal }
}
func fetchedMediaResource(mediaBox: MediaBox, userLocation: UserLocation, userContentType: UserContentType, reference: ResourceReference, range: (Range<Int64>, MediaBoxFetchPriority)? = nil) -> Signal<FetchResourceSourceType, FetchResourceError> {
    Signal { subscriber in
        let id = reference.resource.id.stringRepresentation
        mediaBox.requests.append((id, range?.0))
        return mediaBox.fetch(id).signal.start(next: subscriber.putNext, error: subscriber.putError, completed: subscriber.putCompletion)
    }
}
struct AvailableReaction { let value: MessageReaction.Reaction; let selectAnimation: TelegramMediaFile }
struct AvailableReactions { let reactions: [AvailableReaction] }
final class Stickers {
    let available = Probe<AvailableReactions?, NoError>(.some(nil))
    let custom = Probe<[Int64: TelegramMediaFile], NoError>([:])
    var requestedIds: [[Int64]] = []
    func availableReactions() -> Signal<AvailableReactions?, NoError> { available.signal }
    func resolveInlineStickers(fileIds: [Int64]) -> Signal<[Int64: TelegramMediaFile], NoError> {
        Signal { subscriber in
            self.requestedIds.append(fileIds)
            return self.custom.signal.start(next: subscriber.putNext, completed: subscriber.putCompletion)
        }
    }
}
struct Settings: Equatable { var highQualityStories = false }
final class SharedContext { let settings = Probe<Settings, NoError>(.init()); var baseApplicationSettings: Signal<Settings, NoError> { settings.signal } }
enum TelegramEngine { enum EngineData { enum Item { enum Peer { struct Peer { let id: Int } } } } }
final class EngineData {
    let own = Probe<EnginePeer?, NoError>(EnginePeer(id: 10))
    let peer = Probe<EnginePeer?, NoError>(EnginePeer(id: 20))
    func subscribe(_ item: TelegramEngine.EngineData.Item.Peer.Peer) -> Signal<EnginePeer?, NoError> { own.signal }
    func get(_ item: TelegramEngine.EngineData.Item.Peer.Peer) -> Signal<EnginePeer?, NoError> { peer.signal |> take(1) }
}
final class Resources {
    var active: [String: Int] = [:]
    var starts: [(String, Int)] = []
    func pushPriorityDownload(resourceId: String, priority: Int) -> Disposable {
        active[resourceId, default: 0] += 1; starts.append((resourceId, priority))
        return ActionDisposable { self.active[resourceId, default: 0] -= 1 }
    }
    var count: Int { active.values.reduce(0, +) }
}
final class Engine { let stickers = Stickers(); let data = EngineData(); let resources = Resources() }
final class Postbox { let mediaBox = MediaBox() }
final class Account { let peerId = 10; let postbox = Postbox() }
protocol AccountContextProtocol { var account: Account { get }; var engine: Engine { get }; var sharedContext: SharedContext { get } }
final class Context: AccountContextProtocol { let account = Account(); let engine = Engine(); let sharedContext = SharedContext(); var box: MediaBox { account.postbox.mediaBox } }
__PRODUCTION__

final class StoryPreloadTests: XCTestCase {
    func file(_ id: Int64, prefix: Int32? = nil, size: Int64? = nil) -> TelegramMediaFile {
        .init(fileId: .init(id: id), resource: Resource("f\(id)"), size: size, attributes: [.Video(0, 0, 0, prefix, 0, 0)])
    }
    func story(_ media: EngineMedia = .unsupported, _ reactions: [MessageReaction.Reaction] = []) -> EngineStoryItem {
        .init(media: media, mediaAreas: reactions.map { .reaction(0, $0, 0) })
    }
    func image(_ name: String = "image") -> EngineMedia { .image(.init(representations: [.init(resource: Resource(name))])) }
    func prepare(_ c: Context, _ ids: [Int64]) { c.engine.stickers.custom.initial = Dictionary(uniqueKeysWithValues: ids.map { ($0, file($0)) }) }
    func wait(_ c: Context, _ item: EngineStoryItem) -> Signal<Never, NoError> { waitUntilStoryMediaPreloaded(context: c, peerId: 20, storyItem: item) }
    func background(_ c: Context, _ item: EngineStoryItem) -> Signal<Never, NoError> {
        preloadStoryMedia(context: c, info: .init(peer: PeerReference(.init(id: 20))!, storyId: item.id, media: item.media, reactions: item.mediaAreas.map { switch $0 { case let .reaction(_, r, _): return r } }))
    }
    func testLocalReactionSkipsFetchAndPriority() {
        let c = Context(); prepare(c, [1]); c.box.status("f1").initial = .Local
        var completed = 0; let d = wait(c, story(.unsupported, [.custom(1)])).start(completed: { completed += 1 })
        XCTAssertEqual(completed, 1); XCTAssertTrue(c.box.requests.isEmpty); XCTAssertTrue(c.engine.resources.starts.isEmpty); d.dispose()
    }
    func testReactionErrorFinishesAttemptAndReleasesObserver() {
        let c = Context(); prepare(c, [1]); var completed = 0
        let d = wait(c, story(.unsupported, [.custom(1)])).start(completed: { completed += 1 })
        c.box.fetch("f1").fail(.generic)
        XCTAssertEqual(completed, 1); XCTAssertEqual(c.box.status("f1").active, 0); XCTAssertEqual(c.engine.resources.count, 0); d.dispose()
    }
    func testReactionFetchCompletionDoesNotWaitForStatusDelivery() {
        let c = Context(); prepare(c, [1]); var completed = 0
        let d = wait(c, story(.unsupported, [.custom(1)])).start(completed: { completed += 1 })
        c.box.fetch("f1").complete(); XCTAssertEqual(completed, 1); XCTAssertEqual(c.box.status("f1").active, 0); d.dispose()
    }
    func testLocalStatusCompletesAndCancelsFetch() {
        let c = Context(); prepare(c, [1]); var completed = 0
        let d = wait(c, story(.unsupported, [.custom(1)])).start(completed: { completed += 1 })
        c.box.status("f1").send(.Local); XCTAssertEqual(completed, 1); XCTAssertEqual(c.box.fetch("f1").active, 0); XCTAssertEqual(c.engine.resources.count, 0); d.dispose()
    }
    func testFailedReactionDoesNotEndAnotherPendingReaction() {
        let c = Context(); prepare(c, [1, 2]); var completed = 0
        let d = wait(c, story(.unsupported, [.custom(1), .custom(2)])).start(completed: { completed += 1 })
        c.box.fetch("f1").fail(.generic); XCTAssertEqual(completed, 0); XCTAssertEqual(c.engine.resources.active["f1"], 0); XCTAssertEqual(c.box.fetch("f2").active, 1)
        c.box.status("f2").send(.Local); XCTAssertEqual(completed, 1); XCTAssertEqual(c.engine.resources.count, 0); d.dispose()
    }
    func testFailedReactionDoesNotEndPendingImage() {
        let c = Context(); prepare(c, [1]); var completed = 0
        let d = wait(c, story(image(), [.custom(1)])).start(completed: { completed += 1 })
        c.box.fetch("f1").fail(.generic); XCTAssertEqual(completed, 0); XCTAssertEqual(c.box.fetch("image").active, 1)
        c.box.dataProbe("image").send(.init(complete: true)); XCTAssertEqual(completed, 1); d.dispose()
    }
    func testImageErrorFinishesAttempt() {
        let c = Context(); var completed = 0
        let d = wait(c, story(image())).start(completed: { completed += 1 })
        c.box.fetch("image").fail(.generic); XCTAssertEqual(completed, 1); XCTAssertEqual(c.box.dataProbe("image").active, 0); XCTAssertEqual(c.engine.resources.count, 0); d.dispose()
    }
    func testCompletedImageReleasesPriorityWhileReactionPending() {
        let c = Context(); prepare(c, [1]); var completed = 0
        let d = wait(c, story(image(), [.custom(1)])).start(completed: { completed += 1 })
        c.box.dataProbe("image").send(.init(complete: true)); XCTAssertEqual(completed, 0); XCTAssertEqual(c.engine.resources.active["image"], 0)
        c.box.fetch("f1").complete(); XCTAssertEqual(completed, 1); d.dispose()
    }
    func testCachedImageSkipsFetch() {
        let c = Context(); c.box.dataProbe("image").initial = .init(complete: true); var completed = 0
        let d = wait(c, story(image())).start(completed: { completed += 1 }); XCTAssertEqual(completed, 1); XCTAssertTrue(c.box.requests.isEmpty); d.dispose()
    }
    func testPartialVideoWaitsForPrefixAndReleasesFirstFrame() {
        let c = Context(); var completed = 0
        let d = wait(c, story(.file(file(1, prefix: 100)))).start(completed: { completed += 1 })
        XCTAssertEqual(c.box.requests.first?.1, 0..<100); XCTAssertEqual(c.box.frame("f1").active, 1)
        c.box.rangeProbe("f1").send(RangeSet(0..<Int64(99))); XCTAssertEqual(completed, 0)
        c.box.rangeProbe("f1").send(RangeSet(0..<Int64(100))); XCTAssertEqual(completed, 1); XCTAssertEqual(c.box.frame("f1").active, 0); d.dispose()
    }
    func testRangeFetchCompletionFinishesWithoutReadyStatus() {
        let c = Context(); var completed = 0
        let d = wait(c, story(.file(file(1, prefix: 100)))).start(completed: { completed += 1 })
        c.box.fetch("f1").complete(); XCTAssertEqual(completed, 1); XCTAssertEqual(c.box.rangeProbe("f1").active, 0); XCTAssertEqual(c.box.frame("f1").active, 0); d.dispose()
    }
    func testVideoPrefixClampedToKnownSize() {
        let c = Context(); var completed = 0
        let d = wait(c, story(.file(file(1, prefix: 100, size: 30)))).start(completed: { completed += 1 })
        XCTAssertEqual(c.box.requests.first?.1, 0..<30); c.box.rangeProbe("f1").send(RangeSet(0..<Int64(30))); XCTAssertEqual(completed, 1); d.dispose()
    }
    func testMissingPrefixDoesNotBlockOpeningOrStartRedundantWork() {
        let c = Context(); var completed = 0
        let d = wait(c, story(.file(file(1)))).start(completed: { completed += 1 })
        XCTAssertEqual(completed, 1); XCTAssertTrue(c.box.requests.isEmpty); XCTAssertEqual(c.box.frame("f1").starts, 0); d.dispose()
    }
    func testInvalidNegativePrefixDoesNotCrash() {
        let c = Context(); var completed = 0
        let d = wait(c, story(.file(file(1, prefix: -1)))).start(completed: { completed += 1 }); XCTAssertEqual(completed, 1); d.dispose()
        let b = background(c, story(.file(file(1, prefix: -1)))).start(); XCTAssertEqual(c.box.requests.last?.1, 0..<0); b.dispose()
    }
    func testCancelReleasesAllResourcesAndSuppressesCompletion() {
        let c = Context(); prepare(c, [2]); var completed = 0
        let d = wait(c, story(.file(file(1, prefix: 100)), [.custom(2)])).start(completed: { completed += 1 })
        d.dispose(); c.box.fetch("f1").complete(); c.box.status("f2").send(.Local)
        XCTAssertEqual(completed, 0); XCTAssertEqual(c.engine.resources.count, 0); XCTAssertEqual(c.box.frame("f1").active, 0); XCTAssertEqual(c.box.fetch("f2").active, 0); XCTAssertEqual(c.box.rangeProbe("f1").active, 0)
    }
    func testSynchronousErrorDoesNotStartFirstFrame() {
        let c = Context(); c.box.fetch("f1").errorOnStart = .generic; var completed = 0
        let d = wait(c, story(.file(file(1, prefix: 100)))).start(completed: { completed += 1 })
        XCTAssertEqual(completed, 1); XCTAssertEqual(c.box.frame("f1").starts, 0); XCTAssertEqual(c.engine.resources.count, 0); d.dispose()
    }
    func testFirstFrameValueReleasesAuxiliarySubscription() {
        let c = Context(); let d = wait(c, story(.file(file(1, prefix: 100)))).start()
        c.box.frame("f1").send(1); XCTAssertEqual(c.box.frame("f1").active, 0); XCTAssertEqual(c.box.fetch("f1").active, 1); d.dispose()
    }
    func testUnavailableReactionsDoNotWait() {
        let c = Context(); var completed = 0
        let d = wait(c, story(.unsupported, [.custom(1), .builtin("x"), .stars])).start(completed: { completed += 1 })
        XCTAssertEqual(completed, 1); XCTAssertTrue(c.box.requests.isEmpty); d.dispose()
    }
    func testBuiltinReactionErrorFinishes() {
        let c = Context(); c.engine.stickers.available.initial = AvailableReactions(reactions: [.init(value: .builtin("x"), selectAnimation: file(1)), .init(value: .builtin("y"), selectAnimation: file(2))]); var completed = 0
        let d = wait(c, story(.unsupported, [.builtin("x")])).start(completed: { completed += 1 })
        XCTAssertEqual(c.box.requests.map { $0.0 }, ["f1"]); c.box.fetch("f1").fail(.generic); XCTAssertEqual(completed, 1); d.dispose()
    }
    func testBackgroundReactionFailureCompletes() {
        let c = Context(); prepare(c, [1]); var completed = 0
        let d = background(c, story(.unsupported, [.custom(1)])).start(completed: { completed += 1 })
        c.box.fetch("f1").fail(.generic); XCTAssertEqual(completed, 1); XCTAssertEqual(c.box.status("f1").active, 0); d.dispose()
    }
    func testBackgroundBuiltinReactionFailureCompletes() {
        let c = Context(); c.engine.stickers.available.initial = AvailableReactions(reactions: [.init(value: .builtin("x"), selectAnimation: file(1))]); var completed = 0
        let d = background(c, story(.unsupported, [.builtin("x")])).start(completed: { completed += 1 })
        c.box.fetch("f1").fail(.generic); XCTAssertEqual(completed, 1); d.dispose()
    }
    func testBackgroundPrefixUsesKnownFileSize() {
        let c = Context(); let d = background(c, story(.file(file(1, prefix: 100, size: 30)))).start()
        XCTAssertEqual(c.box.requests.first?.1, 0..<30); d.dispose()
    }
    func testRepeatedCustomIdsResolveAndFetchOnce() {
        let c = Context(); prepare(c, [1]); let d = wait(c, story(.unsupported, [.custom(1), .custom(1)])).start()
        XCTAssertEqual(c.engine.stickers.requestedIds, [[1]]); XCTAssertEqual(c.box.fetch("f1").starts, 1); d.dispose()
    }
    func testQualitySelectionHonorsPremiumAndSetting() {
        for premium in [false, true] { for setting in [false, true] {
            let c = Context(); c.sharedContext.settings.initial = .init(highQualityStories: setting); c.engine.data.own.initial = .init(id: 10, isPremium: premium)
            var item = story(image("full")); item.alternativeMediaList = [image("small")]
            let d = wait(c, item).start(); XCTAssertEqual(c.box.requests.first?.0, premium && setting ? "full" : "small"); d.dispose()
        } }
    }
    func testMissingPeerCompletesWithoutFetching() {
        let c = Context(); c.engine.data.peer.initial = .some(nil); var completed = 0
        let d = wait(c, story(image())).start(completed: { completed += 1 }); XCTAssertEqual(completed, 1); XCTAssertTrue(c.box.requests.isEmpty); d.dispose()
    }
    func testSubscriptionsOwnIndependentPriorities() {
        let c = Context(); let signal = wait(c, story(image())); let a = signal.start(); let b = signal.start()
        XCTAssertEqual(c.engine.resources.count, 2); a.dispose(); XCTAssertEqual(c.engine.resources.count, 1); b.dispose(); XCTAssertEqual(c.engine.resources.count, 0)
    }
    func testConstructingSignalDoesNotStartFetchOrPriority() {
        let c = Context(); let signal = wait(c, story(image())); withExtendedLifetime(signal) {}
        XCTAssertTrue(c.box.requests.isEmpty); XCTAssertTrue(c.engine.resources.starts.isEmpty)
    }
    func testCancellationReleasesContext() {
        var c: Context? = Context(); weak var owner = c
        let d = wait(c!, story(image())).start()
        c = nil; d.dispose(); XCTAssertNil(owner)
    }
    func testZeroPrefixDoesNotBlockOpening() {
        let c = Context(); var completed = 0
        let d = wait(c, story(.file(file(1, prefix: 0)))).start(completed: { completed += 1 })
        XCTAssertEqual(completed, 1); XCTAssertTrue(c.box.requests.isEmpty); d.dispose()
    }
    func testBackgroundLocalReactionSkipsFetch() {
        let c = Context(); prepare(c, [1]); c.box.status("f1").initial = .Local; var completed = 0
        let d = background(c, story(.unsupported, [.custom(1)])).start(completed: { completed += 1 })
        XCTAssertEqual(completed, 1); XCTAssertTrue(c.box.requests.isEmpty); d.dispose()
    }

    func testBackgroundZeroPrefixDoesNotRequestFullVideo() {
        let c = Context(); let d = background(c, story(.file(file(1, prefix: 0)))).start()
        XCTAssertEqual(c.box.requests.first?.1, 0..<0); d.dispose()
    }
    func testUnknownFileSizePreservesPrefix() {
        let c = Context(); let d = background(c, story(.file(file(1, prefix: 100)))).start()
        XCTAssertEqual(c.box.requests.first?.1, 0..<100); d.dispose()
    }
    func testEmptyFileDoesNotWaitForImpossiblePrefix() {
        let c = Context(); var completed = 0
        let d = wait(c, story(.file(file(1, prefix: 100, size: 0)))).start(completed: { completed += 1 })
        XCTAssertEqual(completed, 1); XCTAssertTrue(c.box.requests.isEmpty); d.dispose()
    }
    func testMissingPrefixKeepsBackgroundFetchPolicy() {
        let c = Context(); let d = background(c, story(.file(file(1)))).start()
        XCTAssertEqual(c.box.requests.count, 1); XCTAssertNil(c.box.requests.first?.1); d.dispose()
    }

}
