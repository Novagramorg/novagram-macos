import Foundation
import TGUIKit

struct PeerCallActionSpec: Equatable {
    let type: PeerCallActionType
    let active: Bool
    let enabled: Bool
    let interactive: Bool
    let attract: Bool
}

func peerCallActionSpecs(_ external: ExternalPeerCallState) -> [PeerCallActionSpec] {
    var specs: [PeerCallActionSpec] = []

    let disableEverything: Bool
    switch external.state {
    case .terminating, .terminated:
        disableEverything = true
    default:
        disableEverything = false
    }

    let videoEnabled: Bool
    switch external.state {
    case .reconnecting, .active:
        videoEnabled = !external.canBeRemoved
    default:
        videoEnabled = false
    }

    var redial: Bool = false
    if case let .terminated(reason) = external.state {
        redial = reason?.recall ?? false
    }

    let muteEnabled = !external.canBeRemoved && !disableEverything && !redial
    let endEnabled = !external.canBeRemoved

    specs.append(contentsOf: novagramCallRecordSpecs(external)) // Novagram
    if external.videoState != .notAvailable, external.state != .ringing, !redial {
        let videoActive = external.videoState == .active(true)
        specs.append(PeerCallActionSpec(type: .video, active: videoActive && !external.isScreenCapture, enabled: videoEnabled, interactive: true, attract: false))
        specs.append(PeerCallActionSpec(type: .screencast, active: videoActive && external.isScreenCapture, enabled: videoEnabled, interactive: true, attract: false))
    }

    specs.append(PeerCallActionSpec(type: .mute, active: external.isMuted && muteEnabled, enabled: muteEnabled, interactive: true, attract: false))

    if external.state == .ringing {
        specs.append(PeerCallActionSpec(type: .accept, active: false, enabled: true, interactive: true, attract: true))
    }
    if redial {
        specs.append(PeerCallActionSpec(type: .redial, active: false, enabled: true, interactive: true, attract: false))
    }
    specs.append(PeerCallActionSpec(type: .end, active: false, enabled: endEnabled, interactive: true, attract: false))
    return specs
}

struct PeerCallStatusTooltipFlags: Equatable {
    let lowSignal: Bool
    let lowBattery: Bool

    var isEmpty: Bool {
        return !lowSignal && !lowBattery
    }
}

func peerCallStatusTooltipFlags(_ state: PeerCallState) -> PeerCallStatusTooltipFlags {
    var isConnected = false
    switch state.externalState.state {
    case .active, .reconnecting:
        isConnected = !state.externalState.canBeRemoved
    default:
        break
    }
    let lowSignal: Bool
    if isConnected, let reception = state.reception {
        lowSignal = reception < 2 && state.seconds > 4
    } else {
        lowSignal = false
    }
    let lowBattery = isConnected && state.externalState.remoteBatteryLevel == .low
    return PeerCallStatusTooltipFlags(lowSignal: lowSignal, lowBattery: lowBattery)
}

func peerCallMicroTooltips(_ state: PeerCallState) -> [PeerCallTooltipStatusView.TooltipType] {
    var tooltips: [PeerCallTooltipStatusView.TooltipType] = []
    if state.externalState.isMuted, state.isActive {
        tooltips.append(.yourMicroOff)
    }
    if state.externalState.remoteAudioState == .muted, state.isActive {
        tooltips.append(.microOff(state.compactTitle))
    }
    return tooltips
}

func peerCallSmallVideoSize(_ displayResolution: CGSize?) -> NSSize {
    if let resolution = displayResolution, resolution.width > 0, resolution.height > 0 {
        return resolution.aspectFitted(NSMakeSize(190, 190))
    }
    return NSMakeSize(190, 100)
}

struct PeerCallVideoRequests {
    private var pending: [Bool: Int] = [:]
    private var next: Int = 0
    
    func isPending(isIncoming: Bool) -> Bool {
        return self.pending[isIncoming] != nil
    }
    
    mutating func begin(isIncoming: Bool) -> Int? {
        if self.pending[isIncoming] != nil {
            return nil
        }
        let token = self.next
        self.next += 1
        self.pending[isIncoming] = token
        return token
    }
    
    mutating func complete(isIncoming: Bool, token: Int) -> Bool {
        guard self.pending[isIncoming] == token else {
            return false
        }
        self.pending[isIncoming] = nil
        return true
    }
    
    mutating func cancel(isIncoming: Bool) {
        self.pending[isIncoming] = nil
    }
}

func peerCallState(_ state: PeerCallState, applying external: ExternalPeerCallState, actions: [PeerCallAction]) -> PeerCallState {
    var state = state
    state.externalState = external
    state.actions = actions
    if state.secretKey == nil {
        state.secretKeyViewState = .concealed
    }
    return state
}
