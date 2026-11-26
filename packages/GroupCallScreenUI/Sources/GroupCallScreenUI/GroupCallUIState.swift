import Cocoa
import Foundation
import TGUIKit
import SwiftSignalKit
import Postbox
import InAppSettings
import TelegramCore
import TgVoipWebrtc
import Localization
import TelegramCallsCore
import TelegramUtils

public final class GroupCallUIState : Equatable {

    public struct RecentActive : Equatable {
        public let peerId: PeerId
        public let timestamp: TimeInterval
    }
    
    public struct ControlsTooltip : Hashable {
        public enum `Type` : Int32 {
            case camera
            case micro
        }
        public let type: `Type`
        public let timestamp: TimeInterval
    }
    

    
    public enum Mode : Equatable {
        case voice
        case video
    }
    public struct ActiveVideo : Hashable {
        public enum Mode : Int {
            case main
            case list
            case profile
        }
        
        public static var allModes:[Mode] {
            return [.list, .main]
        }
 
        public let endpointId: String
        public let mode: Mode
        public let index: Int
        public func hash(into hasher: inout Hasher) {
            hasher.combine(endpointId)
            hasher.combine(mode.hashValue)
            hasher.combine(index)
        }
    }
    
    
    
    public struct PinnedData : Equatable {
        public struct Focused: Equatable {
            public var id: String
            public var time: TimeInterval
        }
        public var permanent: String? = nil
        public var focused: Focused? = nil
        public var excludePins: Set<String> = Set()
        public var isEmpty: Bool {
            return permanent != nil || focused != nil
        }
    }
    
    public struct Messages: Equatable {
        
        public struct NextMessageAction : Equatable {
            public var rect: NSRect?
            public var fileId: Int64?
            public var file: TelegramMediaFile?
            public var effectFile: TelegramMediaFile?
            public var effectFileId: Int64?
        }
        
        public var input: Bool = false
        public var reactions: AvailableReactions?
        public var messages: [GroupCallMessagesContext.Message] = []
        public var nextMessageAction: NextMessageAction?
    }

    public let memberDatas:[PeerGroupCallData]
    public let isMuted: Bool
    public let state: PresentationGroupCallState
    public let summaryState: PresentationGroupCallSummaryState?
    public let peer: Peer?
    public let cachedData: CachedChannelData?
    public let myAudioLevel: Float
    public let voiceSettings: VoiceCallSettings
    public let isWindowVisible: Bool
    public let dominantSpeaker: DominantVideo?
    public let pinnedData: PinnedData
    public let isFullScreen: Bool
    public let mode: Mode
    public let videoSources: VideoSources
    public let version: Int
    public let activeVideoViews: [ActiveVideo]
    public let hideParticipants: Bool
    public let isVideoEnabled: Bool
    public let isStream: Bool
    public let windowIsFullscreen: Bool
    public let videoJoined: Bool
    
    public let messages: Messages
    
    public let tooltipSpeaker: PeerGroupCallData?
    public let activeVideoMembers: [GroupCallUIState.ActiveVideo.Mode : [PeerGroupCallData]]
    
    public let controlsTooltip: ControlsTooltip?
    public let dismissedTooltips: Set<ControlsTooltip.`Type`>
    
    public let myPeer: PeerGroupCallData?
    
    public let initialTimestamp: TimeInterval
    
    public let showConferenceKey: Bool
    
    public let isConference: Bool
    
    public let encryptionKeyEmoji: [String]?
        
    public init(memberDatas: [PeerGroupCallData], state: PresentationGroupCallState, isMuted: Bool, summaryState: PresentationGroupCallSummaryState?, myAudioLevel: Float, peer: Peer?, cachedData: CachedChannelData?, voiceSettings: VoiceCallSettings, isWindowVisible: Bool, dominantSpeaker: DominantVideo?, pinnedData: PinnedData, isFullScreen: Bool, mode: Mode, videoSources: VideoSources, version: Int, activeVideoViews: [ActiveVideo], hideParticipants: Bool, isVideoEnabled: Bool, tooltipSpeaker: PeerGroupCallData?, controlsTooltip: ControlsTooltip?, dismissedTooltips: Set<ControlsTooltip.`Type`>, videoJoined: Bool, isStream: Bool, windowIsFullscreen: Bool, initialTimestamp: TimeInterval, isConference: Bool, showConferenceKey: Bool, encryptionKeyEmoji: [String]?, messages: Messages) {
        self.summaryState = summaryState
        self.memberDatas = memberDatas
        self.peer = peer
        self.isMuted = isMuted
        self.cachedData = cachedData
        self.state = state
        self.myAudioLevel = myAudioLevel
        self.voiceSettings = voiceSettings
        self.isWindowVisible = isWindowVisible
        self.dominantSpeaker = dominantSpeaker
        self.pinnedData = pinnedData
        self.isFullScreen = isFullScreen
        self.windowIsFullscreen = windowIsFullscreen
        self.mode = activeVideoViews.isEmpty ? mode : .video
        self.videoSources = videoSources
        self.version = version
        self.isConference = isConference
        self.encryptionKeyEmoji = encryptionKeyEmoji
        self.activeVideoViews = activeVideoViews
        self.hideParticipants = hideParticipants
        self.isVideoEnabled = isVideoEnabled
        self.tooltipSpeaker = tooltipSpeaker
        self.controlsTooltip = controlsTooltip
        self.dismissedTooltips = dismissedTooltips
        self.videoJoined = videoJoined
        self.isStream = isStream
        self.myPeer = memberDatas.first(where: { $0.peer.id == $0.accountPeerId })
        self.initialTimestamp = initialTimestamp
        self.showConferenceKey = showConferenceKey
        self.messages = messages
        var modeMembers:[GroupCallUIState.ActiveVideo.Mode : [PeerGroupCallData]] = [:]
        
        let modes:[GroupCallUIState.ActiveVideo.Mode] = [.list, .main]
        
        for mode in modes {
            var members:[PeerGroupCallData] = []
            for activeVideo in activeVideoViews.filter({ $0.mode == mode }) {
                let member = memberDatas.first(where: { peer in
                    
                    if let endpoint = peer.videoEndpoint {
                        if activeVideo.endpointId == endpoint {
                            return true
                        }
                    }
                    if let endpoint = peer.presentationEndpoint {
                        if activeVideo.endpointId == endpoint {
                            return true
                        }
                    }
                    return false
                })
                if let member = member, !members.contains(where: { $0.peer.id == member.peer.id }) {
                    members.append(member)
                }
            }
            modeMembers[mode] = members
        }
        self.activeVideoMembers = modeMembers
    }
    
    public var hasVideo: Bool {
        return videoSources.video != nil
    }
    public var hasScreencast: Bool {
        return videoSources.screencast != nil
    }
    
    public var commentsEnabled: Bool {
        return self.state.messagesEnabled?.isEnabled == true
    }
    
    public var canManageComments: Bool {
        return self.state.messagesEnabled?.canChange == true
    }
    
    public var canUnmute: Bool {
        return (self.state.muteState?.canUnmute == true) || self.state.canManageCall
    }
    
    deinit {
        
    }
    
    public var cantRunVideo: Bool {
        if isVideoEnabled {
            return false
        }
        return (!videoJoined) && !memberDatas.filter({ $0.videoEndpointId != nil || $0.presentationEndpointId != nil }).isEmpty
    }
    
    
    
    public var title: String {
        if state.scheduleTimestamp != nil {
            return strings().voiceChatTitleScheduled
        } else if let custom = state.title, !custom.isEmpty {
            return custom
        } else {
            return peer?.displayTitle ?? strings().callGroupCall
        }
    }
    
    public static func == (lhs: GroupCallUIState, rhs: GroupCallUIState) -> Bool {
        if lhs.memberDatas != rhs.memberDatas {
            return false
        }
        if lhs.state != rhs.state {
            return false
        }
        if lhs.myAudioLevel != rhs.myAudioLevel {
            return false
        }
        if lhs.summaryState != rhs.summaryState {
            return false
        }
        if let lhsPeer = lhs.peer, let rhsPeer = rhs.peer {
            if !lhsPeer.isEqual(rhsPeer) {
                return false
            }
        } else if (lhs.peer != nil) != (rhs.peer != nil) {
            return false
        }
        if lhs.voiceSettings != rhs.voiceSettings {
            return false
        }
        if lhs.windowIsFullscreen != rhs.windowIsFullscreen {
            return false
        }
        if let lhsCachedData = lhs.cachedData, let rhsCachedData = rhs.cachedData {
            if !lhsCachedData.isEqual(to: rhsCachedData) {
                return false
            }
        } else if (lhs.cachedData != nil) != (rhs.cachedData != nil) {
            return false
        }
        if lhs.isWindowVisible != rhs.isWindowVisible {
            return false
        }
        if lhs.dominantSpeaker != rhs.dominantSpeaker {
            return false
        }
        if lhs.pinnedData != rhs.pinnedData {
            return false
        }
        if lhs.isFullScreen != rhs.isFullScreen {
            return false
        }
        if lhs.mode != rhs.mode {
            return false
        }
        if lhs.isStream != rhs.isStream {
            return false
        }
        if lhs.hasVideo != rhs.hasVideo {
            return false
        }
        if lhs.isMuted != rhs.isMuted {
            return false
        }
        if lhs.videoSources != rhs.videoSources {
            return false
        }
        if lhs.version != rhs.version {
            return false
        }
        if lhs.activeVideoViews != rhs.activeVideoViews {
            return false
        }
        if lhs.hideParticipants != rhs.hideParticipants {
            return false
        }
        if lhs.isVideoEnabled != rhs.isVideoEnabled {
            return false
        }
        if lhs.isMuted != rhs.isMuted {
            return false
        }
        if lhs.activeVideoMembers != rhs.activeVideoMembers {
            return false
        }
        if lhs.tooltipSpeaker != rhs.tooltipSpeaker {
            return false
        }
        if lhs.controlsTooltip != rhs.controlsTooltip {
            return false
        }
        if lhs.dismissedTooltips != rhs.dismissedTooltips {
            return false
        }
        if lhs.videoJoined != rhs.videoJoined {
            return false
        }
        if lhs.showConferenceKey != rhs.showConferenceKey {
            return false
        }
        if lhs.encryptionKeyEmoji != rhs.encryptionKeyEmoji {
            return false
        }
        if lhs.isConference != rhs.isConference {
            return false
        }
        if lhs.messages != rhs.messages {
            return false
        }
        return true
    }
    
    public func videoActive(_ mode: ActiveVideo.Mode) -> [PeerGroupCallData] {
        return activeVideoMembers[mode] ?? []
    }
    
    
}


extension GroupCallUIState.ControlsTooltip {
    public var text: String {
        switch self.type {
        case .camera:
            return strings().voiceChatTooltipEnableCamera
        case .micro:
            return strings().voiceChatTooltipEnableMicro
        }
    }
}
