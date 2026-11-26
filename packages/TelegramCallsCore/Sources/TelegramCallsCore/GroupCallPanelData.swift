import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramContext
import TelegramUtils
import AVFoundation
import TelegramMediaUtils
import SystemPermissions
import ProxyUtils

public protocol GroupCallContextProtocol: AnyObject {
    var call: PresentationGroupCall { get }
}

public struct GroupCallPanelData : Equatable {
    public let peerId: PeerId?
    public let info: GroupCallInfo?
    public let isChannel: Bool
    public let topParticipants: [GroupCallParticipantsContext.Participant]
    public let participantCount: Int
    public let activeSpeakers: Set<PeerId>
    public private(set) weak var groupCall: (any GroupCallContextProtocol)?
    public init(
        peerId: PeerId?,
        isChannel: Bool,
        info: GroupCallInfo?,
        topParticipants: [GroupCallParticipantsContext.Participant],
        participantCount: Int,
        activeSpeakers: Set<PeerId>,
        groupCall: (any GroupCallContextProtocol)?
    ) {
        self.peerId = peerId
        self.info = info
        self.isChannel = isChannel
        self.topParticipants = topParticipants
        self.participantCount = participantCount
        self.activeSpeakers = activeSpeakers
        self.groupCall = groupCall
    }
    
    public static func ==(lhs: GroupCallPanelData, rhs: GroupCallPanelData) -> Bool {
        if lhs.peerId != rhs.peerId {
            return false
        }
        if lhs.info != rhs.info {
            return false
        }
        if lhs.topParticipants != rhs.topParticipants {
            return false
        }
        if lhs.activeSpeakers != rhs.activeSpeakers {
            return false
        }
        if (lhs.groupCall != nil) != (rhs.groupCall != nil) {
            return false
        }
        if lhs.participantCount != rhs.participantCount {
            return false
        }
        if lhs.isChannel != rhs.isChannel {
            return false
        }
        return true
    }
}
