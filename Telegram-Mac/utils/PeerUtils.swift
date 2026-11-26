import Cocoa
import Postbox
import TelegramCore
import TGUIKit
import Localization
#if SHARE
import TelegramUtilsShare
#else
import TelegramUtils
#endif

extension Peer {
    public var displayLetters: [String] {
        switch self {
        case let user as TelegramUser:
            if let firstName = user.firstName, let lastName = user.lastName, !firstName.isEmpty && !lastName.isEmpty {
                return [firstName[firstName.startIndex ..< firstName.index(after: firstName.startIndex)].uppercased(), lastName[lastName.startIndex ..< lastName.index(after: lastName.startIndex)].uppercased()]
            } else if let firstName = user.firstName, !firstName.isEmpty {
                return [firstName[firstName.startIndex ..< firstName.index(after: firstName.startIndex)].uppercased()]
            } else if let lastName = user.lastName, !lastName.isEmpty {
                return [lastName[lastName.startIndex ..< lastName.index(after: lastName.startIndex)].uppercased()]
            } else {
                let name = strings().peerDeletedUser
                if !name.isEmpty {
                    return [name[name.startIndex ..< name.index(after: name.startIndex)].uppercased()]
                }
            }
            
            return []
        case let group as TelegramGroup:
            if !group.title.isEmpty {
                return [group.title[group.title.startIndex ..< group.title.index(after: group.title.startIndex)].uppercased()]
            } else {
                return []
            }
        case let channel as TelegramChannel:
            if !channel.title.isEmpty {
                return [channel.title[channel.title.startIndex ..< channel.title.index(after: channel.title.startIndex)].uppercased()]
            } else {
                return []
            }
        case let community as TelegramCommunity:
            if !community.title.isEmpty {
                return [community.title[community.title.startIndex ..< community.title.index(after: community.title.startIndex)].uppercased()]
            } else {
                return []
            }
        default:
            return []
        }
    }

    var isForum: Bool {
        if let channel = self as? TelegramChannel {
            return channel.flags.contains(.isForum)
        } else {
            return false
        }
    }
}
