import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit

public struct NovagramCallRecordRequest {
    public let window: Window
    public let engine: TelegramEngine
    public let peerId: PeerId
    public let hasVideo: Bool
    public let callId: UUID?
}

private final class NovagramCallIdEntry {
    weak var arguments: PeerCallArguments?
    let callId: UUID

    init(arguments: PeerCallArguments, callId: UUID) {
        self.arguments = arguments
        self.callId = callId
    }
}

private var novagramCallIds: [NovagramCallIdEntry] = []

public func novagramSetCallId(_ arguments: PeerCallArguments, _ callId: UUID) {
    novagramCallIds.removeAll { $0.arguments == nil || $0.arguments === arguments }
    novagramCallIds.append(NovagramCallIdEntry(arguments: arguments, callId: callId))
}

func novagramCallId(_ arguments: PeerCallArguments) -> UUID? {
    return novagramCallIds.first(where: { $0.arguments === arguments })?.callId
}

public struct NovagramCallRecordCallState: Equatable {
    public let callId: UUID?
    public let isEnded: Bool
    public let isMuted: Bool
}

// Novagram local call recording. The recorder lives in NovagramCore; the app installs these closures in
// Telegram-Mac/packages-integration/hooks/NovagramHooksInstall.swift. Defaults do nothing.
public struct NovagramCallRecordHooks {
    public var isAvailable: () -> Bool = { false }
    public var isRecording: () -> Bool = { false }
    public var recordingSignal: () -> Signal<Bool, NoError> = { .single(false) }
    public var title: (_ isRecording: Bool) -> String = { _ in "" }
    public var toggle: (NovagramCallRecordRequest) -> Void = { _ in }
    public var autoStart: (NovagramCallRecordRequest) -> Void = { _ in }
    public var callDidUpdate: (_ window: Window?, _ state: NovagramCallRecordCallState) -> Void = { _, _ in }

    public init() {}

    public static var shared = NovagramCallRecordHooks()

    public static func install(_ hooks: NovagramCallRecordHooks) {
        shared = hooks
    }
}

let novagramCallRecordResource = ImageResource(name: "novagram_record", bundle: .module)

func novagramCallRecordTitle() -> String {
    let hooks = NovagramCallRecordHooks.shared
    return hooks.title(hooks.isRecording())
}

func novagramCallRecordSpecs(_ external: ExternalPeerCallState) -> [PeerCallActionSpec] {
    let hooks = NovagramCallRecordHooks.shared
    let isRecording = hooks.isRecording()
    guard isRecording || hooks.isAvailable(), !external.canBeRemoved, external.conferenceReference == nil else {
        return []
    }
    switch external.state {
    case .terminating, .terminated:
        return []
    default:
        return [PeerCallActionSpec(type: .record, active: isRecording, enabled: true, interactive: true, attract: false)]
    }
}

func novagramCallHasVideo(_ external: ExternalPeerCallState) -> Bool {
    if case .active = external.videoState {
        return true
    }
    return external.remoteVideoState == .active
}

func novagramCallIsEnded(_ external: ExternalPeerCallState) -> Bool {
    switch external.state {
    case .terminating, .terminated:
        return true
    default:
        return external.canBeRemoved
    }
}

func novagramToggleCallRecording(_ window: Window?, _ arguments: PeerCallArguments, _ external: ExternalPeerCallState) {
    guard let window else {
        return
    }
    NovagramCallRecordHooks.shared.toggle(NovagramCallRecordRequest(window: window, engine: arguments.engine, peerId: arguments.peerId, hasVideo: novagramCallHasVideo(external), callId: novagramCallId(arguments)))
}

func novagramCallCanAutoRecord(_ external: ExternalPeerCallState) -> Bool {
    guard !external.canBeRemoved, external.conferenceReference == nil else {
        return false
    }
    switch external.state {
    case .requesting(ringing: true), .connecting, .active, .reconnecting:
        return true
    default:
        return false
    }
}

func novagramCallRecordState(_ signal: Signal<ExternalPeerCallState, NoError>, window: Window?, arguments: @escaping () -> PeerCallArguments?) -> Signal<ExternalPeerCallState, NoError> {
    let hooks = NovagramCallRecordHooks.shared
    return combineLatest(signal, hooks.recordingSignal()) |> map { [weak window] external, _ in
        hooks.callDidUpdate(window, NovagramCallRecordCallState(callId: arguments().flatMap(novagramCallId), isEnded: novagramCallIsEnded(external), isMuted: external.isMuted))
        if let window, let arguments = arguments() {
            if novagramCallCanAutoRecord(external) {
                hooks.autoStart(NovagramCallRecordRequest(window: window, engine: arguments.engine, peerId: arguments.peerId, hasVideo: novagramCallHasVideo(external), callId: novagramCallId(arguments)))
            }
            NovagramCallWeakNetwork.shared.update(window: window, external: external, turnOffVideo: { [weak arguments] in
                arguments?.toggleCamera(external)
            })
        }
        return external
    }
}
