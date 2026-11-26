import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
struct Point { static let zero = Point() }
struct Dimensions: Equatable { init(_ point: Point) {} }
class Resource {}
final class LocalFileReferenceMediaResource: Resource { let localFilePath = "/missing/story-submission-test-image" }
class Media { func _asMedia() -> Media { self } }
final class TelegramMediaImage: Media {
    struct Representation { let dimensions = Dimensions(.zero); let resource: Resource }
    var representations: [Representation] = []
}
final class TelegramMediaFile: Media {
    var dimensions: Dimensions? = Dimensions(.zero)
    var duration: Int? = 10
    let resource = Resource()
}
enum EngineStoryInputMedia {
    case existing(media: Media)
    case image(dimensions: Dimensions, data: Data, stickers: [Int])
    case video(dimensions: Dimensions, duration: Int, resource: Resource, firstFrameFile: Int?, stickers: [Int], coverTime: Int?)
}
enum Stories {
    enum PendingTarget: Equatable { case myStories, peer(Int) }
    struct PendingForwardInfo: Equatable { let peerId: Int; let storyId: Int32; let isModified: Bool }
}
struct Privacy: Equatable {
    var pin = true
    var selectedPrivacy = 1
    var isForwardingDisabled = false
}
struct StoryItem { var id: Int32 = 5; var media = Media(); var music: Media? = nil }
struct Story { var peerId: Int? = 10; var storyItem = StoryItem() }
enum StoryPrivacyReason { case share(Story), upload(Media, Int), settings(Story) }
struct TextState {
    var inputText = "caption"
    func textInputState() -> TextState { self }
    func messageTextEntities() -> [String] { ["bold"] }
}
struct State {
    var privacyLoaded = true
    var initited = true
    var textState = TextState()
    var privacy = Privacy()
    var sendAsPeerId: Int? = nil
    func find(_ category: Int) -> Int { category }
}
enum StoriesUploadAvailability { case available(remainingCount: Int32), weeklyLimit, monthlyLimit, expiringLimit, premiumRequired, unknownLimit, channelBoostRequired }
enum EditError { case generic }
final class AvailabilityRequest {
    let target: Stories.PendingTarget
    var subscriber: Subscriber<StoriesUploadAvailability, NoError>?
    var cancelled = false
    init(_ target: Stories.PendingTarget) { self.target = target }
    func emit(_ value: StoriesUploadAvailability) { subscriber?.putNext(value) }
    func complete() { subscriber?.putCompletion() }
}
final class EditRequest {
    let id: Int32; let privacy: Int
    var subscriber: Subscriber<Never, EditError>?
    var cancelled = false
    init(id: Int32, privacy: Int) { self.id = id; self.privacy = privacy }
    func succeed() { subscriber?.putCompletion() }
    func fail() { subscriber?.putError(.generic) }
}
struct Upload {
    let target: Stories.PendingTarget
    let text: String
    let entities: [String]
    let privacy: Int
    let forward: Stories.PendingForwardInfo?
    let media: EngineStoryInputMedia
}
final class Messages {
    var checks: [AvailabilityRequest] = []
    var edits: [EditRequest] = []
    var uploads: [Upload] = []
    var onCheck: ((AvailabilityRequest) -> Void)?
    var onEdit: ((EditRequest) -> Void)?
    func checkStoriesUploadAvailability(target: Stories.PendingTarget) -> Signal<StoriesUploadAvailability, NoError> {
        Signal { subscriber in
            let request = AvailabilityRequest(target); request.subscriber = subscriber; self.checks.append(request)
            self.onCheck?(request)
            return ActionDisposable { request.cancelled = true; request.subscriber = nil }
        }
    }
    func editStoryPrivacy(id: Int32, privacy: Int) -> Signal<Never, EditError> {
        Signal { subscriber in
            let request = EditRequest(id: id, privacy: privacy); request.subscriber = subscriber; self.edits.append(request)
            self.onEdit?(request)
            return ActionDisposable { request.cancelled = true; request.subscriber = nil }
        }
    }
    func uploadStory(target: Stories.PendingTarget, media: EngineStoryInputMedia, mediaAreas: [Int], text: String, entities: [String], pin: Bool, privacy: Int, isForwardingDisabled: Bool, period: Int, randomId: Int64, forwardInfo: Stories.PendingForwardInfo?, folders: [Int64], music: TelegramMediaFile?) -> Signal<Int32, NoError> {
        Signal { subscriber in
            self.uploads.append(.init(target: target, text: text, entities: entities, privacy: privacy, forward: forwardInfo, media: media))
            subscriber.putNext(1); subscriber.putCompletion(); return EmptyDisposable
        }
    }
}
final class Engine { let messages = Messages() }
final class Context { let engine = Engine(); let peerId = 10 }
final class Window { var alerts = 0; var toasts: [String] = []; var closes = 0; var premium = 0 }
func alert(for window: Window, info: String) { window.alerts += 1 }
func showModalText(for window: Window, text: String) { window.toasts.append(text) }
func arc4random64() -> Int64 { 123 }
struct Strings { let unknownError = "error"; let storyPrivacySaveRepost = "posted"; let storyPrivacySavePrivacy = "saved" }
func strings() -> Strings { Strings() }
struct FeatureNavigationHooks {
    static let shared = FeatureNavigationHooks()
    func showPremiumBoarding(_ context: Context, _ window: Window, _ a: Int?, _ b: Bool, _ c: Int?) { window.premium += 1 }
}
enum Validation { case none }
final class Controller {
    var validateData: (Int) -> Validation = { _ in .none }
    var willDisappear: (Int) -> Void = { _ in }
}
final class Rig {
    let context = Context()
    let controller = Controller()
    let stateValue = Atomic(value: State())
    let actionsDisposable = DisposableSet()
    let window = Window()
    var block: (() -> Void)?
    var editAudience: (() -> Void)?
    init(_ reason: StoryPrivacyReason = .share(Story())) {
        let context = self.context
        let controller = self.controller
        let stateValue = self.stateValue
        let actionsDisposable = self.actionsDisposable
        let window = self.window
        let close: (() -> Void)? = { window.closes += 1 }
        __FIELDS__
        let blockListDisposable = MetaDisposable()
        var blockListOperationId: UUID?
        editAudience = { audienceOperationId = UUID() }
        block = { blockListOperationId = UUID() }
        __DISAPPEAR__
        __VALIDATE__
    }
    func done() { _ = controller.validateData(0) }
    deinit { actionsDisposable.dispose() }
}

final class StorySubmissionTests: XCTestCase {
    func testRepeatedDoneStartsOneAvailabilityCheck() {
        for upload in [false, true] {
            let rig = Rig(upload ? .upload(TelegramMediaFile(), 10) : .share(Story()))
            rig.done(); rig.done(); rig.done()
            XCTAssertEqual(rig.context.engine.messages.checks.count, 1)
        }
    }
    func testDuplicateAvailabilityAndDoneCannotUploadTwice() {
        let rig = Rig(); rig.done()
        rig.context.engine.messages.checks[0].emit(.available(remainingCount: 2))
        rig.context.engine.messages.checks[0].emit(.available(remainingCount: 2))
        rig.done()
        XCTAssertEqual(rig.context.engine.messages.uploads.count, 1)
        XCTAssertEqual(rig.context.engine.messages.checks.count, 1)
        XCTAssertEqual(rig.window.closes, 1)
    }
    func testAvailabilityFailureAllowsRetryAndDoesNotUpsellOtherLimits() {
        let limits: [StoriesUploadAvailability] = [.weeklyLimit, .monthlyLimit, .expiringLimit, .unknownLimit, .channelBoostRequired]
        for limit in limits {
            let rig = Rig(); rig.done(); rig.context.engine.messages.checks[0].emit(limit)
            XCTAssertTrue(rig.context.engine.messages.uploads.isEmpty)
            XCTAssertEqual(rig.window.premium, 0)
            XCTAssertEqual(rig.window.alerts, 1)
            rig.done(); XCTAssertEqual(rig.context.engine.messages.checks.count, 2)
        }
    }
    func testPremiumRequirementStillOffersPremiumAndAllowsRetry() {
        let rig = Rig(); rig.done(); rig.context.engine.messages.checks[0].emit(.premiumRequired)
        XCTAssertEqual(rig.window.premium, 1)
        XCTAssertEqual(rig.window.alerts, 0)
        rig.done(); XCTAssertEqual(rig.context.engine.messages.checks.count, 2)
    }
    func testEmptyAvailabilityCompletionAllowsRetry() {
        let rig = Rig(); rig.done(); rig.context.engine.messages.checks[0].complete(); rig.done()
        XCTAssertEqual(rig.context.engine.messages.checks.count, 2)
        XCTAssertTrue(rig.context.engine.messages.uploads.isEmpty)
    }
    func testDisappearingModalCannotUploadAfterAvailabilityReturns() {
        let rig = Rig(); rig.done(); rig.controller.willDisappear(0)
        rig.context.engine.messages.checks[0].emit(.available(remainingCount: 2)); rig.done()
        XCTAssertTrue(rig.context.engine.messages.checks[0].cancelled)
        XCTAssertTrue(rig.context.engine.messages.uploads.isEmpty)
        XCTAssertEqual(rig.context.engine.messages.checks.count, 1)
        XCTAssertEqual(rig.window.closes, 0)
    }
    func testUploadUsesSubmittedSnapshotAndTarget() {
        let rig = Rig(.upload(TelegramMediaFile(), 10))
        _ = rig.stateValue.modify { state in var state = state; state.sendAsPeerId = 99; state.privacy.selectedPrivacy = 3; return state }
        rig.done()
        _ = rig.stateValue.modify { state in var state = state; state.textState.inputText = "later"; state.sendAsPeerId = 88; state.privacy.selectedPrivacy = 2; return state }
        rig.context.engine.messages.checks[0].emit(.available(remainingCount: 2))
        let upload = rig.context.engine.messages.uploads[0]
        XCTAssertEqual(upload.target, .peer(99)); XCTAssertEqual(upload.text, "caption"); XCTAssertEqual(upload.privacy, 3); XCTAssertEqual(upload.entities, ["bold"])
    }
    func testSharePreservesForwardIdentity() {
        let rig = Rig(.share(.init(peerId: 50, storyItem: .init(id: 77))))
        rig.done(); rig.context.engine.messages.checks[0].emit(.available(remainingCount: 1))
        XCTAssertEqual(rig.context.engine.messages.uploads[0].forward, .init(peerId: 50, storyId: 77, isModified: false))
    }
    func testInvalidUploadReportsErrorAndCanRetry() {
        let rig = Rig(.upload(Media(), 10)); rig.done(); rig.done()
        XCTAssertEqual(rig.window.alerts, 2)
        XCTAssertTrue(rig.context.engine.messages.checks.isEmpty)
        XCTAssertEqual(rig.window.closes, 0)
    }
    func testDoneWaitsForPrivacyAndPeerInitialization() {
        for initialized in [false, true] {
            let rig = Rig()
            _ = rig.stateValue.modify { state in var state = state; state.privacyLoaded = initialized; state.initited = false; return state }
            rig.done(); XCTAssertTrue(rig.context.engine.messages.checks.isEmpty)
        }
    }
    func testDoneWaitsForPendingAudienceOperation() {
        let rig = Rig(); rig.editAudience?(); rig.done()
        XCTAssertTrue(rig.context.engine.messages.checks.isEmpty)
    }
    func testDoneWaitsForPendingBlocklistOperation() {
        let rig = Rig(); rig.block?(); rig.done()
        XCTAssertTrue(rig.context.engine.messages.checks.isEmpty)
    }
    func testPrivacyEditWaitsForSuccessBeforeClosing() {
        let rig = Rig(.settings(Story())); rig.done()
        XCTAssertTrue(rig.window.toasts.isEmpty); XCTAssertEqual(rig.window.closes, 0)
        rig.done(); XCTAssertEqual(rig.context.engine.messages.edits.count, 1)
        rig.context.engine.messages.edits[0].succeed()
        XCTAssertEqual(rig.window.toasts, ["saved"]); XCTAssertEqual(rig.window.closes, 1)
        rig.done(); XCTAssertEqual(rig.context.engine.messages.edits.count, 1)
    }
    func testPrivacyEditFailureKeepsModalAndAllowsRetry() {
        let rig = Rig(.settings(Story())); rig.done(); rig.context.engine.messages.edits[0].fail()
        XCTAssertTrue(rig.window.toasts.isEmpty); XCTAssertEqual(rig.window.closes, 0); XCTAssertEqual(rig.window.alerts, 1)
        rig.done(); XCTAssertEqual(rig.context.engine.messages.edits.count, 2)
    }
    func testPrivacyEditCancellationSuppressesLateCompletion() {
        let rig = Rig(.settings(Story())); rig.done(); rig.controller.willDisappear(0)
        rig.context.engine.messages.edits[0].succeed()
        XCTAssertTrue(rig.context.engine.messages.edits[0].cancelled)
        XCTAssertTrue(rig.window.toasts.isEmpty)
    }
    func testForeignPeerStoryCannotAccidentallyEditOwnSameId() {
        let rig = Rig(.settings(.init(peerId: 20))); rig.done()
        XCTAssertTrue(rig.context.engine.messages.edits.isEmpty)
        XCTAssertEqual(rig.window.alerts, 1)
        XCTAssertEqual(rig.window.closes, 0)
    }
    func testSynchronousAvailabilityStillCommitsOnlyOnce() {
        let rig = Rig(); rig.context.engine.messages.onCheck = { $0.emit(.available(remainingCount: 1)) }
        rig.done(); rig.done()
        XCTAssertEqual(rig.context.engine.messages.uploads.count, 1)
        XCTAssertEqual(rig.context.engine.messages.checks.count, 1)
    }
    func testSynchronousEditErrorDoesNotLeaveSubmissionLocked() {
        let rig = Rig(.settings(Story())); rig.context.engine.messages.onEdit = { $0.fail() }
        rig.done(); rig.done()
        XCTAssertEqual(rig.context.engine.messages.edits.count, 2)
        XCTAssertEqual(rig.window.alerts, 2)
    }
    func testPendingSubmissionDoesNotRetainControllerOwner() {
        var rig: Rig? = Rig(); rig!.done()
        let request = rig!.context.engine.messages.checks[0]
        weak var weakRig = rig
        rig = nil
        XCTAssertNil(weakRig); XCTAssertTrue(request.cancelled)
    }
}
