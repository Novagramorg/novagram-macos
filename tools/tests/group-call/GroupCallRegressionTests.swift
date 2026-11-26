import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int
struct VideoSourceMac: Equatable { var id: Int = 1 }
enum PresentationGroupCallMuteAction: Equatable {
    case muted(isPushToTalkActive: Bool)
    case unmuted
}
struct GroupCallInfo { var id: Int64 = 1; var accessHash: Int64 = 2 }
struct GroupCallInitialOutput {
    struct Video { var capturer: OngoingCallVideoCapturer; var source: VideoSourceMac }
    var isMuted = true
    var video: Video?
    var screencast: Video?
}
final class OngoingCallVideoCapturer {
    func setOnFatalError(_ f: @escaping () -> Void) {}
    func setOnPause(_ f: @escaping (Bool) -> Void) {}
}
protocol OngoingGroupCallEncryptionContext {}
final class ConferenceCallE2EContext {
    struct ContextStateHolder {}
    let state = Atomic(value: ContextStateHolder())
}
final class OngoingGroupCallEncryptionContextImpl: OngoingGroupCallEncryptionContext {
    init(e2eCall: Atomic<ConferenceCallE2EContext.ContextStateHolder>, channelId: Int) {}
}
final class GroupCallParticipantsContext {
    struct Participant {
        struct MuteState: Equatable { var canUnmute: Bool; var mutedByYou: Bool }
    }
    var videoUpdates = 0
    func updateVideoState(peerId: PeerId, isVideoMuted: Bool?, isVideoPaused: Bool?, isPresentationPaused: Bool?) {
        videoUpdates += 1
    }
}
final class Request<Value> {
    enum Failure: Error { case generic }
    var subscriber: Subscriber<Value, Failure>?
    var cancelled = false
    var signal: Signal<Value, Failure> {
        Signal { subscriber in
            self.subscriber = subscriber
            return ActionDisposable { self.cancelled = true }
        }
    }
    func succeed(_ value: Value) { subscriber?.putNext(value) }
    func fail() { subscriber?.putError(.generic) }
}
struct JoinResult { var jsonParams: String; var endpointId: String }
final class Calls {
    var joins: [Request<JoinResult>] = []
    var leaves = 0
    var cancelledLeaves = 0
    func joinGroupCallAsScreencast(callId: Int64, accessHash: Int64, joinPayload: String) -> Signal<JoinResult, Request<JoinResult>.Failure> {
        let request = Request<JoinResult>()
        joins.append(request)
        return request.signal
    }
    func leaveGroupCallAsScreencast(callId: Int64, accessHash: Int64) -> Signal<Never, NoError> {
        Signal { _ in
            self.leaves += 1
            return ActionDisposable { self.cancelledLeaves += 1 }
        }
    }
}
final class Engine { let calls = Calls() }
final class AccountContext { let engine = Engine() }
final class DevicesContext { var currentMicroId: String?; var currentOutputId: String? }
final class OngoingGroupCallContext {
    enum ConnectionMode { case rtc }
    enum VideoContentType { case screencast }
    struct MediaChannelDescription {}
    struct VideoChannel: Equatable {
        enum Quality { case thumbnail, medium, full }
        struct SsrcGroup: Equatable { var semantics: String; var ssrcs: [UInt32] }
        var audioSsrc: UInt32
        var peerId: Int64
        var endpointId: String
        var ssrcGroups: [SsrcGroup]
        var minQuality: Quality
        var maxQuality: Quality
    }
    let payloads = ValuePipe<(String, UInt32)>()
    var joinPayload: Signal<(String, UInt32), NoError> { payloads.signal() }
    var responses: [String] = []
    var muteUpdates: [Bool] = []
    var channelUpdates: [[VideoChannel]] = []
    var stopped = false
    var videoRequests = 0
    var videoDisabled = false
    init() {}
    init(audioSessionActive: Signal<Bool, NoError>, video: OngoingCallVideoCapturer?, requestMediaChannelDescriptions: @escaping (Set<UInt32>, @escaping ([MediaChannelDescription]) -> Void) -> Disposable, rejoinNeeded: @escaping () -> Void, outgoingAudioBitrateKbit: Int?, videoContentType: VideoContentType, enableNoiseSuppression: Bool, disableAudioInput: Bool, enableSystemMute: Bool, useReferenceImpl: Bool, prioritizeVP8: Bool, logPath: String, onMutedSpeechActivityDetected: @escaping (Bool) -> Void, isConference: Bool, audioIsActiveByDefault: Bool, isStream: Bool, sharedAudioDevice: Int?, encryptionContext: OngoingGroupCallEncryptionContext?) {}
    func setConnectionMode(_ mode: ConnectionMode, keepBroadcastConnectedIfWasEnabled: Bool, isUnifiedBroadcast: Bool) {}
    func setJoinResponse(payload: String) { responses.append(payload) }
    func stop(account: Int, reportCallId: Int?, debugLog: Promise<String?>) { stopped = true }
    func disableVideo() { videoDisabled = true }
    func requestVideo(_ capturer: OngoingCallVideoCapturer) { videoRequests += 1 }
    func setIsMuted(_ value: Bool) { muteUpdates.append(value) }
    func switchAudioInput(_ id: String) {}
    func switchAudioOutput(_ id: String) {}
    func setRequestedVideoChannels(_ channels: [VideoChannel]) { channelUpdates.append(channels) }
}
struct PresentationGroupCallRequestedVideo {
    var audioSsrc: UInt32 = 10
    var peerId: Int64 = 20
    var endpointId: String = "camera"
    var ssrcGroups: [OngoingGroupCallContext.VideoChannel.SsrcGroup] = []
    var minQuality: OngoingGroupCallContext.VideoChannel.Quality = .thumbnail
    var maxQuality: OngoingGroupCallContext.VideoChannel.Quality = .full
}
enum CallVideoTuning { static let isOptimized = true }
final class CallHarness {
    struct Sources { var screencast: VideoSourceMac?; var video: VideoSourceMac? }
    struct State {
        var muteState: GroupCallParticipantsContext.Participant.MuteState? = .init(canUnmute: true, mutedByYou: false)
        var sources = Sources()
        var presentationEndpointId: String?
    }
    struct InternalState { var callInfo: GroupCallInfo? = GroupCallInfo() }
    var internalState = InternalState()
    var stateValue = State()
    let account = 0
    let accountContext = AccountContext()
    let devicesContext = DevicesContext()
    let joinAsPeerId = 1
    var leaving = false
    var markedAsCanBeRemoved = false
    var didConnectOnce = false
    var initialOutput = GroupCallInitialOutput()
    var didApplyInitialOutput = false
    var isMutedValue = PresentationGroupCallMuteAction.muted(isPushToTalkActive: false)
    var muteActionVersion = 0
    let isMutedPromise = ValuePromise<PresentationGroupCallMuteAction>(.muted(isPushToTalkActive: false))
    var permissions: (PresentationGroupCallMuteAction, @escaping (Bool) -> Void) -> Void = { _, f in f(true) }
    var genericCallContext: OngoingGroupCallContext? = OngoingGroupCallContext()
    var screencastCallContext: OngoingGroupCallContext?
    var participantsContext: GroupCallParticipantsContext? = GroupCallParticipantsContext()
    var screenCapturer: OngoingCallVideoCapturer?
    var videoCapturer: OngoingCallVideoCapturer?
    var hasScreencast = false
    var hasVideo = false
    var isConference = false
    var e2eContext: ConferenceCallE2EContext?
    var mustStopSharing: (() -> Void)?
    var mustStopVideo: (() -> Void)?
    var requestedVideoChannels: [OngoingGroupCallContext.VideoChannel] = []
    var suspendVideoChannelRequests = false
    let joinDisposable = MetaDisposable()
    let requestDisposable = MetaDisposable()
    let screencastJoinDisposable = MetaDisposable()
    let screencastRequestDisposable = MetaDisposable()
    let networkStateDisposable = MetaDisposable()
    let audioLevelsDisposable = MetaDisposable()
    let participantsContextStateDisposable = MetaDisposable()
    var checkCallDisposable: Disposable?
    var myAudioLevelTimer: SwiftSignalKit.Timer?
    let typingDisposable = MetaDisposable()
    let _canBeRemoved = Promise<Bool>(false)
    var serverMuteUpdates: [Bool] = []
    func updateMuteState(peerId: PeerId, isMuted: Bool) -> GroupCallParticipantsContext.Participant.MuteState? {
        serverMuteUpdates.append(isMuted)
        return isMuted ? .init(canUnmute: true, mutedByYou: false) : nil
    }
    METHODS_FROM_SOURCE
}

final class GroupCallRegressionTests: XCTestCase {
    func startSharing(_ call: CallHarness) -> OngoingGroupCallContext {
        call.requestScreencast(deviceId: OngoingCallVideoCapturer(), source: .init())
        let context = call.screencastCallContext!
        context.payloads.putNext(("payload", 1))
        return context
    }
    func testScreencastDoesNotCancelMainCallRequest() {
        let call = CallHarness()
        var cancelled = false
        call.requestDisposable.set(ActionDisposable { cancelled = true })
        _ = startSharing(call)
        XCTAssertEqual(call.accountContext.engine.calls.joins.count, 1)
        XCTAssertFalse(cancelled)
    }
    func testStoppingScreencastCancelsJoinAndDisablesCapture() {
        let call = CallHarness()
        let context = startSharing(call)
        let request = call.accountContext.engine.calls.joins[0]
        call.disableScreencast()
        XCTAssertTrue(request.cancelled)
        XCTAssertTrue(context.videoDisabled)
        XCTAssertTrue(context.stopped)
        XCTAssertFalse(call.hasScreencast)
        XCTAssertNil(call.screenCapturer)
        context.payloads.putNext(("late", 2))
        XCTAssertEqual(call.accountContext.engine.calls.joins.count, 1)
    }
    func testStoppingDuringReconnectStillCancelsPayloadSubscription() {
        let call = CallHarness()
        let context = startSharing(call)
        call.internalState.callInfo = nil
        call.disableScreencast()
        context.payloads.putNext(("late", 2))
        XCTAssertEqual(call.accountContext.engine.calls.joins.count, 1)
    }
    func testRepeatedStopDoesNotCancelServerLeave() {
        let call = CallHarness()
        _ = startSharing(call)
        call.disableScreencast()
        call.disableScreencast()
        XCTAssertEqual(call.accountContext.engine.calls.leaves, 1)
        XCTAssertEqual(call.accountContext.engine.calls.cancelledLeaves, 0)
    }
    func testOldScreencastResponseCannotConfigureReplacement() {
        let call = CallHarness()
        _ = startSharing(call)
        let old = call.accountContext.engine.calls.joins[0]
        call.disableScreencast()
        let replacement = startSharing(call)
        old.succeed(.init(jsonParams: "old", endpointId: "old"))
        XCTAssertTrue(replacement.responses.isEmpty)
        XCTAssertNil(call.stateValue.presentationEndpointId)
        call.accountContext.engine.calls.joins[1].succeed(.init(jsonParams: "new", endpointId: "new"))
        XCTAssertEqual(replacement.responses, ["new"])
        XCTAssertEqual(call.stateValue.presentationEndpointId, "new")
    }
    func testScreencastJoinFailureCleansUpAndNotifies() {
        let call = CallHarness()
        let context = startSharing(call)
        var notifications = 0
        call.mustStopSharing = { notifications += 1; call.disableScreencast() }
        call.accountContext.engine.calls.joins[0].fail()
        XCTAssertEqual(notifications, 1)
        XCTAssertNil(call.screencastCallContext)
        XCTAssertNil(call.stateValue.sources.screencast)
        XCTAssertFalse(call.hasScreencast)
        XCTAssertTrue(context.stopped)
        XCTAssertEqual(call.accountContext.engine.calls.cancelledLeaves, 0)
    }
    func testDuplicateScreencastStartPreservesContext() {
        let call = CallHarness()
        let first = startSharing(call)
        call.requestScreencast(deviceId: OngoingCallVideoCapturer(), source: .init())
        XCTAssertTrue(call.screencastCallContext === first)
    }
    func testReconnectDoesNotRestoreDisabledInitialMedia() {
        let call = CallHarness()
        call.initialOutput = .init(isMuted: false, video: .init(capturer: .init(), source: .init()), screencast: .init(capturer: .init(), source: .init()))
        call.establishParticipantsContext()
        XCTAssertTrue(call.hasVideo)
        XCTAssertTrue(call.hasScreencast)
        XCTAssertEqual(call.isMutedValue, .unmuted)
        call.setIsMuted(action: .muted(isPushToTalkActive: false))
        call.disableVideo()
        call.disableScreencast()
        call.establishParticipantsContext()
        XCTAssertFalse(call.hasVideo)
        XCTAssertFalse(call.hasScreencast)
        XCTAssertEqual(call.isMutedValue, .muted(isPushToTalkActive: false))
        XCTAssertNil(call.initialOutput.video)
        XCTAssertNil(call.initialOutput.screencast)
    }
    func testNewerMuteActionInvalidatesPendingPermission() {
        let call = CallHarness()
        var callbacks: [(Bool) -> Void] = []
        call.permissions = { _, f in callbacks.append(f) }
        call.setIsMuted(action: .unmuted)
        call.setIsMuted(action: .muted(isPushToTalkActive: false))
        callbacks[1](true)
        callbacks[0](true)
        XCTAssertEqual(call.isMutedValue, .muted(isPushToTalkActive: false))
        XCTAssertFalse(call.genericCallContext!.muteUpdates.contains(false))
    }
    func testModeratorMuteStopsAudioAndPermissionCannotUndoIt() {
        let call = CallHarness()
        call.setIsMuted(action: .unmuted)
        call.applyParticipantMuteState(.init(canUnmute: false, mutedByYou: false))
        XCTAssertEqual(call.genericCallContext!.muteUpdates.last, true)
        XCTAssertEqual(call.stateValue.muteState?.canUnmute, false)
        var callback: ((Bool) -> Void)?
        call.permissions = { _, f in callback = f }
        call.setIsMuted(action: .unmuted)
        call.applyParticipantMuteState(.init(canUnmute: true, mutedByYou: false))
        callback?(true)
        XCTAssertEqual(call.isMutedValue, .muted(isPushToTalkActive: false))
        XCTAssertEqual(call.stateValue.muteState?.canUnmute, true)
    }
    func testOrdinaryParticipantMuteDoesNotInterruptPushToTalk() {
        let call = CallHarness()
        call.setIsMuted(action: .muted(isPushToTalkActive: true))
        call.applyParticipantMuteState(.init(canUnmute: true, mutedByYou: false))
        XCTAssertEqual(call.isMutedValue, .muted(isPushToTalkActive: true))
        XCTAssertEqual(call.genericCallContext!.muteUpdates.last, false)
    }
    func testUnchangedVideoRequestsAreSkippedAndSuspensionKeepsLatest() {
        let call = CallHarness()
        call.setRequestedVideoList(items: [.init()])
        call.setRequestedVideoList(items: [.init()])
        XCTAssertEqual(call.genericCallContext!.channelUpdates.count, 1)
        call.setSuspendVideoChannelRequests(true)
        var changed = PresentationGroupCallRequestedVideo()
        changed.maxQuality = .medium
        call.setRequestedVideoList(items: [changed])
        XCTAssertEqual(call.genericCallContext!.channelUpdates.count, 2)
        call.setSuspendVideoChannelRequests(false)
        XCTAssertEqual(call.genericCallContext!.channelUpdates.last?.first?.maxQuality, .medium)
    }
    func testTerminationCancelsPendingWorkAndRejectsMediaAndUnmute() {
        let call = CallHarness()
        _ = startSharing(call)
        let request = call.accountContext.engine.calls.joins[0]
        var cancelled = false
        call.requestDisposable.set(ActionDisposable { cancelled = true })
        var callback: ((Bool) -> Void)?
        call.permissions = { _, f in callback = f }
        call.setIsMuted(action: .unmuted)
        call.markAsCanBeRemoved()
        callback?(true)
        XCTAssertTrue(cancelled)
        XCTAssertTrue(request.cancelled)
        XCTAssertTrue(call.genericCallContext!.stopped)
        XCTAssertEqual(call.isMutedValue, .muted(isPushToTalkActive: false))
        call.requestVideo(deviceId: .init(), source: .init())
        XCTAssertFalse(call.hasVideo)
    }
}
