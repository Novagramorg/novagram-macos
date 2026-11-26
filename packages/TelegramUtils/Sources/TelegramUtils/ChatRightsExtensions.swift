import Foundation
import TelegramCore
import Postbox
import Localization
import TGUIKit

public extension RenderedChannelParticipant {
    var isCreator: Bool {
        return participant.isCreator
    }
}

public extension ChannelParticipant {
    var isCreator:Bool {
        switch self {
        case .creator:
            return true
        default:
            return false
        }
    }
}

public extension TelegramChatAdminRightsFlags {
    var localizedString:String {
        switch self {
        case TelegramChatAdminRightsFlags.canAddAdmins:
            return strings().eventLogServicePromoteAddNewAdmins
        case TelegramChatAdminRightsFlags.canBanUsers:
            return strings().eventLogServicePromoteBanUsers
        case TelegramChatAdminRightsFlags.canChangeInfo:
            return strings().eventLogServicePromoteChangeInfo
        case TelegramChatAdminRightsFlags.canInviteUsers:
            return strings().eventLogServicePromoteAddUsers
        case TelegramChatAdminRightsFlags.canDeleteMessages:
            return strings().eventLogServicePromoteDeleteMessages
        case TelegramChatAdminRightsFlags.canEditMessages:
            return strings().eventLogServicePromoteEditMessages
        case TelegramChatAdminRightsFlags.canPinMessages:
            return strings().eventLogServicePromotePinMessages
        case TelegramChatAdminRightsFlags.canPostMessages:
            return strings().eventLogServicePromotePostMessages
        case TelegramChatAdminRightsFlags.canPostMessages:
            return strings().eventLogServicePromotePostMessages
        case TelegramChatAdminRightsFlags.canManageDirect:
            return strings().eventLogServicePromoteManageDirect
        case TelegramChatAdminRightsFlags.canBeAnonymous:
            return strings().eventLogServicePromoteRemainAnonymous
        case TelegramChatAdminRightsFlags.canManageCalls:
            return strings().channelAdminLogCanManageCalls
        case TelegramChatAdminRightsFlags.canManageTopics:
            return strings().channelAdminLogCanManageTopics
        default:
            return "Undefined Promotion"
        }
    }
}

public extension TelegramChatBannedRightsFlags {
    var localizedString:String {
        switch self {
        case TelegramChatBannedRightsFlags.banSendGifs:
            return strings().eventLogServiceDemoteSendGifs
        case TelegramChatBannedRightsFlags.banPinMessages:
            return strings().eventLogServiceDemotePinMessages
        case TelegramChatBannedRightsFlags.banAddMembers:
            return strings().eventLogServiceDemoteAddMembers
        case TelegramChatBannedRightsFlags.banSendPolls:
            return strings().eventLogServiceDemotePostPolls
        case TelegramChatBannedRightsFlags.banEmbedLinks:
            return strings().eventLogServiceDemoteEmbedLinks
        case TelegramChatBannedRightsFlags.banReadMessages:
            return ""
        case TelegramChatBannedRightsFlags.banSendGames:
            return strings().eventLogServiceDemoteEmbedLinks
        case TelegramChatBannedRightsFlags.banSendInline:
            return strings().eventLogServiceDemoteSendInline
        case TelegramChatBannedRightsFlags.banSendMedia:
            return strings().eventLogServiceDemoteSendMedia
        case TelegramChatBannedRightsFlags.banSendText:
            return strings().eventLogServiceDemoteSendMessages
        case TelegramChatBannedRightsFlags.banSendStickers:
            return strings().eventLogServiceDemoteSendStickers
        case TelegramChatBannedRightsFlags.banChangeInfo:
            return strings().eventLogServiceDemoteChangeInfo
        case TelegramChatBannedRightsFlags.banEditRank:
            return "Edit Custom Tag";
        default:
            return ""
        }
    }
}

public extension TelegramChatBannedRights {
    var formattedUntilDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        //formatter.timeZone = NSTimeZone.local
        
        formatter.timeZone = NSTimeZone.local
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(untilDate)))
    }
}

public func <(lhs:RenderedChannelParticipant, rhs: RenderedChannelParticipant) -> Bool {
    let lhsInvitedAt: Int32
    let rhsInvitedAt: Int32
    
    switch lhs.participant {
    case .creator:
        lhsInvitedAt = Int32.min
    case .member(_, let invitedAt, _, _, _, _):
        lhsInvitedAt = invitedAt
    }
    switch rhs.participant {
    case .creator:
        rhsInvitedAt = Int32.min
    case .member(_, let invitedAt, _, _, _, _):
        rhsInvitedAt = invitedAt
    }
    return lhsInvitedAt < rhsInvitedAt
}
