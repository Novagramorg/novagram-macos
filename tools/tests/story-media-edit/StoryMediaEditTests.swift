import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
struct Peer { let id: Int }
class Media { let id: Int; var parsedFor: Int?; init(_ id: Int) { self.id = id } }
class Resource {}
final class CloudDocumentMediaResource: Resource {
    let fileId: Int64 = 5
    let accessHash: Int64 = 6
    let fileReference = Data([7])
}
final class TelegramMediaFile: Media {
    let resource: Resource
    let mimeType = "video/mp4"
    let attributes = [8]
    init(_ id: Int, resource: Resource) { self.resource = resource; super.init(id) }
}
enum EngineStoryInputMedia {
    case image(Media), video(Media), existing(media: Media)
    var embeddedStickers: [TelegramMediaFile] { [] }
}
struct EngineStoryPrivacy { let valid: Bool }
struct MessageTextEntity { let associatedPeerIds: [Int] }
typealias MediaArea = Int
struct Buffer: Equatable { let data: Data }
struct SimpleDictionary<K: Hashable, V> {
    let values: [K: V]
    init(_ values: [K: V]) { self.values = values }
}
enum Api {
    struct InputPeer: Equatable { let id: Int }
    struct InputPrivacyRule: Equatable {}
    struct InputDocumentData: Equatable { let id: Int64; let accessHash: Int64; let fileReference: Buffer }
    enum InputDocument: Equatable { case inputDocument(InputDocumentData) }
    struct StoryDocument: Equatable { let id: InputDocument }
    enum InputFile: Equatable { case inputFileStoryDocument(StoryDocument) }
    struct UploadedDocument: Equatable {
        let flags: Int32; let file: InputFile; let thumb: Int?; let mimeType: String; let attributes: [Int]
        let stickers: [Int]?; let videoCover: Int?; let videoTimestamp: Int?; let ttlSeconds: Int?
    }
    enum InputMedia: Equatable { case uploaded(Int), inputMediaUploadedDocument(UploadedDocument) }
    typealias MediaArea = Int
    struct MessageEntity: Equatable { let resolvedPeers: [Int] }
    struct Peer { let peerId: Int }
    struct MediaData { let id: Int? }
    struct StoryItemData { let id: Int32; let media: MediaData }
    enum StoryItem { case storyItem(StoryItemData), storyItemDeleted }
    struct StoryUpdate { let peer: Peer; let story: StoryItem }
    enum Update { case updateStory(StoryUpdate), other }
    struct Updates { let allUpdates: [Update] }
    enum functions {
        enum stories {
            static func editStory(flags: Int32, peer: InputPeer, id: Int32, media: InputMedia?, mediaAreas: [MediaArea]?, caption: String?, entities: [MessageEntity]?, privacyRules: [InputPrivacyRule]?, music: Int?) -> RequestData {
                .init(flags: flags, peer: peer, id: id, media: media, areas: mediaAreas, caption: caption, entities: entities, privacy: privacyRules)
            }
        }
    }
}
struct RequestData {
    let flags: Int32; let peer: Api.InputPeer; let id: Int32; let media: Api.InputMedia?; let areas: [Int]?
    let caption: String?; let entities: [Api.MessageEntity]?; let privacy: [Api.InputPrivacyRule]?
}
struct MTRpcError: Error { let errorDescription: String }
struct ContentProgress { let progress: Float }
struct UploadedContent {
    enum Content { case media(Api.InputMedia, Int), unsupported }
    let content: Content
}
enum PendingMessageUploadedContentResult { case progress(ContentProgress), content(UploadedContent) }
final class UploadManager {
    var subscriber: Subscriber<PendingMessageUploadedContentResult?, NoError>?
    var subscriptions = 0
    var passFetchProgress = false
    var cancelled = false
    var onStart: (() -> Void)?
    var signal: Signal<PendingMessageUploadedContentResult?, NoError> {
        Signal { subscriber in
            self.subscriptions += 1; self.subscriber = subscriber; self.onStart?()
            return ActionDisposable { self.cancelled = true; self.subscriber = nil }
        }
    }
    func progress(_ value: Float) { subscriber?.putNext(.progress(.init(progress: value))) }
    func finish(_ value: PendingMessageUploadedContentResult?) { subscriber?.putNext(value); subscriber?.putCompletion() }
}
func prepareUploadStoryContent(account: Account, media: EngineStoryInputMedia) -> Media {
    switch media { case let .image(value), let .video(value), let .existing(value): return value }
}
func uploadedStoryContent(postbox: Postbox, network: Network, media: Media, mediaReference: Int?, embeddedStickers: [TelegramMediaFile], accountPeerId: Int, messageMediaPreuploadManager: UploadManager, revalidationContext: Int, auxiliaryMethods: Int, passFetchProgress: Bool) -> (Signal<PendingMessageUploadedContentResult?, NoError>, Media) {
    messageMediaPreuploadManager.passFetchProgress = passFetchProgress
    return (messageMediaPreuploadManager.signal, media)
}
func apiInputPeer(_ peer: Peer) -> Api.InputPeer? { peer.id >= 0 ? .init(id: peer.id) : nil }
func inputDocumentAttributesFromFileAttributes(_ attributes: [Int]) -> [Int] { attributes }
func apiInputPrivacyRules(privacy: EngineStoryPrivacy, transaction: Transaction) -> [Api.InputPrivacyRule]? { privacy.valid ? [.init()] : nil }
func apiMediaAreasFromMediaAreas(_ areas: [Int], transaction: Transaction?) -> [Int] { areas.filter { $0 >= 0 } }
func apiEntitiesFromMessageTextEntities(_ entities: [MessageTextEntity], associatedPeers: SimpleDictionary<Int, Peer>) -> [Api.MessageEntity] { entities.map { _ in .init(resolvedPeers: associatedPeers.values.keys.sorted()) } }
func textMediaAndExpirationTimerFromApiMedia(_ value: Api.MediaData, _ peerId: Int) -> (media: Media?, unused: Int) {
    let media = value.id.map(Media.init); media?.parsedFor = peerId
    return (media, 0)
}
struct Copy: Equatable { let from: Int; let to: Int; let peerId: Int?; let skipPreviews: Bool }
func applyMediaResourceChanges(from: Media, to: Media, postbox: Postbox, force: Bool, skipPreviews: Bool) { postbox.copies.append(.init(from: from.id, to: to.id, peerId: to.parsedFor, skipPreviews: skipPreviews)) }
final class Transaction {
    var peers: [Int: Peer] = [10: .init(id: 10), 20: .init(id: 20)]
    func getPeer(_ id: Int) -> Peer? { peers[id] }
}
final class Postbox {
    let storage = Transaction()
    var copies: [Copy] = []
    var delayNext = false
    var finish: (() -> Void)?
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            let run = { subscriber.putNext(f(self.storage)); subscriber.putCompletion() }
            if self.delayNext {
                self.delayNext = false; self.finish = run
                return ActionDisposable { self.finish = nil }
            }
            run(); return EmptyDisposable
        }
    }
}
final class Request {
    let data: RequestData
    var subscriber: Subscriber<Api.Updates, MTRpcError>?
    var cancelled = false
    init(_ data: RequestData) { self.data = data }
    func succeed(_ updates: Api.Updates = .init(allUpdates: [])) { subscriber?.putNext(updates); subscriber?.putCompletion() }
    func fail(_ description: String) { subscriber?.putError(.init(errorDescription: description)) }
}
final class Network {
    var requests: [Request] = []
    var onRequest: ((Request) -> Void)?
    func request(_ data: RequestData) -> Signal<Api.Updates, MTRpcError> {
        Signal { subscriber in
            let request = Request(data); request.subscriber = subscriber; self.requests.append(request); self.onRequest?(request)
            return ActionDisposable { request.cancelled = true; request.subscriber = nil }
        }
    }
}
final class StateManager { var updates: [Api.Updates] = []; func addUpdates(_ updates: Api.Updates) { self.updates.append(updates) } }
final class Account {
    let peerId = 10
    let postbox = Postbox(); let network = Network(); let stateManager = StateManager(); let messageMediaPreuploadManager = UploadManager()
    let mediaReferenceRevalidationContext = 0; let auxiliaryMethods = 0
}
__SOURCE__
extension StoryUploadResult: Equatable {}

final class StoryMediaEditTests: XCTestCase {
    var values: [StoryUploadResult] = []
    func start(_ account: Account, peer: Int = 20, id: Int32 = 5, media: EngineStoryInputMedia? = nil, areas: [Int]? = nil, text: String? = nil, entities: [MessageTextEntity]? = nil, privacy: EngineStoryPrivacy? = nil) -> Disposable {
        _internal_editStory(account: account, peerId: peer, id: id, media: media, mediaAreas: areas, text: text, entities: entities, privacy: privacy).start(next: { self.values.append($0) })
    }
    func uploaded(_ value: Int = 100) -> PendingMessageUploadedContentResult { .content(.init(content: .media(.uploaded(value), 0))) }
    func story(_ peer: Int = 20, _ id: Int32 = 5, _ media: Int? = 500) -> Api.Update { .updateStory(.init(peer: .init(peerId: peer), story: .storyItem(.init(id: id, media: .init(id: media))))) }
    func testRejectedRpcReportsFailureInsteadOfStoryId() {
        let account = Account(); let operation = start(account, text: "caption")
        account.network.requests.first?.fail("STORY_ID_INVALID")
        XCTAssertEqual(values, [.completed(nil)]); XCTAssertTrue(account.stateManager.updates.isEmpty); XCTAssertTrue(account.postbox.copies.isEmpty)
        operation.dispose()
    }
    func testNotModifiedIsSuccessfulWithoutSyntheticUpdates() {
        let account = Account(); let operation = start(account, text: "same")
        account.network.requests.first?.fail("STORY_NOT_MODIFIED")
        XCTAssertEqual(values, [.completed(5)]); XCTAssertTrue(account.stateManager.updates.isEmpty); operation.dispose()
    }
    func testSuccessfulResponseForwardsUpdatesBeforeCompletion() {
        let account = Account(); var updateCountOnCompletion: Int?
        let operation = _internal_editStory(account: account, peerId: 20, id: 5, media: nil, mediaAreas: nil, text: "new", entities: nil, privacy: nil).start(next: { _ in updateCountOnCompletion = account.stateManager.updates.count })
        XCTAssertNil(updateCountOnCompletion)
        account.network.requests.first?.succeed(.init(allUpdates: [story()]))
        XCTAssertEqual(updateCountOnCompletion, 1); operation.dispose()
    }
    func testFailedImageUploadDoesNotSendPartialCaptionEdit() {
        let account = Account(); let operation = start(account, media: .image(Media(1)), text: "new")
        account.messageMediaPreuploadManager.finish(nil)
        XCTAssertTrue(account.network.requests.isEmpty); XCTAssertEqual(values, [.completed(nil)]); operation.dispose()
    }
    func testFailedVideoUploadPreservesProgressThenFails() {
        let account = Account(); let operation = start(account, media: .video(Media(1)))
        account.messageMediaPreuploadManager.progress(0.25); account.messageMediaPreuploadManager.finish(nil)
        XCTAssertTrue(account.messageMediaPreuploadManager.passFetchProgress)
        XCTAssertEqual(values, [.progress(0.25), .completed(nil)]); XCTAssertTrue(account.network.requests.isEmpty); operation.dispose()
    }
    func testUnsupportedUploadedContentIsRejected() {
        let account = Account(); let operation = start(account, media: .image(Media(1)))
        account.messageMediaPreuploadManager.finish(.content(.init(content: .unsupported)))
        XCTAssertEqual(values, [.completed(nil)]); XCTAssertTrue(account.network.requests.isEmpty); operation.dispose()
    }
    func testExistingCloudDocumentCoverFallbackIsPreserved() {
        let account = Account(); let operation = start(account, media: .existing(media: TelegramMediaFile(7, resource: CloudDocumentMediaResource())))
        account.messageMediaPreuploadManager.finish(nil)
        guard let request = account.network.requests.first else { XCTFail("missing cover request"); operation.dispose(); return }
        XCTAssertEqual(request.data.flags & 1, 1)
        guard case .inputMediaUploadedDocument? = request.data.media else { XCTFail("wrong cover media"); operation.dispose(); return }
        request.succeed(.init(allUpdates: [story()]))
        XCTAssertEqual(account.postbox.copies, [.init(from: 7, to: 500, peerId: 20, skipPreviews: true)])
        XCTAssertEqual(values, [.completed(5)]); operation.dispose()
    }
    func testExistingLocalDocumentCannotFallbackAfterFailure() {
        let account = Account(); let operation = start(account, media: .existing(media: TelegramMediaFile(7, resource: Resource())))
        account.messageMediaPreuploadManager.finish(nil)
        XCTAssertEqual(values, [.completed(nil)]); XCTAssertTrue(account.network.requests.isEmpty); operation.dispose()
    }
    func testClearingCaptionSuppliesEmptyEntitiesVector() {
        let account = Account(); let operation = start(account, text: "")
        XCTAssertEqual(account.network.requests.first?.data.caption, "")
        XCTAssertEqual(account.network.requests.first?.data.entities, [])
        XCTAssertEqual(account.network.requests.first?.data.flags, 2); operation.dispose()
    }
    func testPlainCaptionWithoutEntitiesSuppliesEmptyVector() {
        let account = Account(); let operation = start(account, text: "plain")
        XCTAssertEqual(account.network.requests.first?.data.entities, [])
        XCTAssertEqual(account.network.requests.first?.data.flags, 2); operation.dispose()
    }
    func testAbsentCaptionDoesNotSendEntitiesOrCaptionFlag() {
        let account = Account(); let operation = start(account, entities: [.init(associatedPeerIds: [10])])
        XCTAssertNil(account.network.requests.first?.data.caption); XCTAssertNil(account.network.requests.first?.data.entities)
        XCTAssertEqual(account.network.requests.first?.data.flags, 0); operation.dispose()
    }
    func testCaptionEntitiesResolveAssociatedPeers() {
        let account = Account(); let operation = start(account, text: "mention", entities: [.init(associatedPeerIds: [20, 99])])
        XCTAssertEqual(account.network.requests.first?.data.entities, [.init(resolvedPeers: [20])]); operation.dispose()
    }
    func testClearingMediaAreasSendsPresentEmptyVector() {
        let account = Account(); let operation = start(account, areas: [])
        XCTAssertEqual(account.network.requests.first?.data.areas, [])
        XCTAssertEqual(account.network.requests.first?.data.flags, 8); operation.dispose()
    }
    func testOmittedMediaAreasLeavesServerAreasUntouched() {
        let account = Account(); let operation = start(account)
        XCTAssertNil(account.network.requests.first?.data.areas); XCTAssertEqual(account.network.requests.first?.data.flags, 0); operation.dispose()
    }
    func testUnresolvableMediaAreaRejectsWholeEdit() {
        let account = Account(); let operation = start(account, areas: [1, -1], text: "caption")
        XCTAssertEqual(values, [.completed(nil)]); XCTAssertTrue(account.network.requests.isEmpty); operation.dispose()
    }
    func testAllUnresolvableMediaAreasCannotClearExistingAreas() {
        let account = Account(); let operation = start(account, areas: [-1])
        XCTAssertEqual(values, [.completed(nil)]); XCTAssertTrue(account.network.requests.isEmpty); operation.dispose()
    }
    func testAllRequestFieldsAndTargetArePreserved() {
        let account = Account(); let operation = start(account, id: 77, media: .image(Media(1)), areas: [4, 5], text: "new", entities: [], privacy: .init(valid: true))
        account.messageMediaPreuploadManager.finish(uploaded())
        guard let data = account.network.requests.first?.data else { XCTFail("missing request"); operation.dispose(); return }
        XCTAssertEqual(data.peer.id, 20); XCTAssertEqual(data.id, 77); XCTAssertEqual(data.flags, 15)
        XCTAssertEqual(data.media, .uploaded(100)); XCTAssertEqual(data.areas, [4, 5]); XCTAssertEqual(data.caption, "new"); XCTAssertEqual(data.entities, []); XCTAssertEqual(data.privacy, [.init()])
        operation.dispose()
    }
    func testUnresolvablePrivacyRejectsBeforeRequest() {
        let account = Account(); let operation = start(account, privacy: .init(valid: false))
        XCTAssertEqual(values, [.completed(nil)]); XCTAssertTrue(account.network.requests.isEmpty); operation.dispose()
    }
    func testMissingOrInvalidTargetPeerRejectsBeforeRequest() {
        for peer in [99, -1] {
            values = []
            let account = Account(); account.postbox.storage.peers[-1] = .init(id: -1)
            let operation = start(account, peer: peer)
            XCTAssertEqual(values, [.completed(nil)]); XCTAssertTrue(account.network.requests.isEmpty); operation.dispose()
        }
    }
    func testResourcesOnlyCopyForMatchingStoryAndPeer() {
        let account = Account(); let operation = start(account, media: .image(Media(1)))
        account.messageMediaPreuploadManager.finish(uploaded())
        account.network.requests.first?.succeed(.init(allUpdates: [story(10, 5, 501), story(20, 6, 502), .other, story()]))
        XCTAssertEqual(account.postbox.copies, [.init(from: 1, to: 500, peerId: 20, skipPreviews: false)])
        XCTAssertEqual(account.stateManager.updates.first?.allUpdates.count, 4); operation.dispose()
    }
    func testUnparseableOrDeletedMatchingStoryDoesNotCopyResources() {
        let account = Account(); let operation = start(account, media: .image(Media(1)))
        account.messageMediaPreuploadManager.finish(uploaded())
        account.network.requests.first?.succeed(.init(allUpdates: [story(20, 5, nil), .updateStory(.init(peer: .init(peerId: 20), story: .storyItemDeleted))]))
        XCTAssertTrue(account.postbox.copies.isEmpty); XCTAssertEqual(values, [.completed(5)]); operation.dispose()
    }
    func testCancellationDuringUploadStopsEdit() {
        let account = Account(); let operation = start(account, media: .image(Media(1)))
        operation.dispose(); account.messageMediaPreuploadManager.finish(uploaded())
        XCTAssertTrue(account.messageMediaPreuploadManager.cancelled); XCTAssertTrue(values.isEmpty); XCTAssertTrue(account.network.requests.isEmpty)
    }
    func testCancellationDuringTransactionStopsEdit() {
        let account = Account(); account.postbox.delayNext = true
        let operation = start(account, text: "new")
        XCTAssertNotNil(account.postbox.finish); operation.dispose(); account.postbox.finish?()
        XCTAssertNil(account.postbox.finish); XCTAssertTrue(values.isEmpty); XCTAssertTrue(account.network.requests.isEmpty)
    }
    func testCancellationDuringRpcPreventsResourceCopyAndSuccess() {
        let account = Account(); let operation = start(account, media: .image(Media(1)))
        account.messageMediaPreuploadManager.finish(uploaded()); operation.dispose()
        account.network.requests.first?.succeed(.init(allUpdates: [story()]))
        XCTAssertTrue(account.network.requests.first?.cancelled == true); XCTAssertTrue(account.postbox.copies.isEmpty); XCTAssertTrue(account.stateManager.updates.isEmpty); XCTAssertTrue(values.isEmpty)
    }
    func testSynchronousUploadAndRpcFinishOnce() {
        let account = Account()
        account.messageMediaPreuploadManager.onStart = { [weak account] in account?.messageMediaPreuploadManager.finish(self.uploaded()) }
        account.network.onRequest = { $0.succeed() }
        let operation = start(account, media: .video(Media(1)))
        XCTAssertEqual(values, [.completed(5)]); XCTAssertEqual(account.network.requests.count, 1); operation.dispose()
    }
}
