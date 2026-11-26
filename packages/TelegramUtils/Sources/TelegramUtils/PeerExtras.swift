import Foundation
import TelegramCore
import Postbox

public func uniquePeers(from peers:[Peer], defaultExculde:[PeerId] = []) -> [Peer] {
    var excludePeerIds:[PeerId:PeerId] = [:]
    for peerId in defaultExculde {
        excludePeerIds[peerId] = peerId
    }
    return peers.filter { peer -> Bool in
        let first = excludePeerIds[peer.id] == nil
        excludePeerIds[peer.id] = peer.id
        return first
    }
}

public func peerCompactDisplayTitles(_ peerIds: [PeerId], _ dict: SimpleDictionary<PeerId, Peer>) -> String {
    var names:String = ""
    for peerId in peerIds {
        if let peer = dict[peerId] {
            names += TelegramUtilsHooks.shared.peerCompactTitle(peer)
            if peerId != peerIds.last {
                names += ", "
            }
        }
    }
    return names
}

public extension Peer {
    var isCopyProtected: Bool {
        return isCopyProtected(cachedData: nil)
    }
    func isCopyProtected(cachedData: CachedPeerData?) -> Bool {
        if let peer = self as? TelegramGroup {
            return peer.flags.contains(.copyProtectionEnabled) && !peer.groupAccess.isCreator
        } else if let peer = self as? TelegramChannel {
            return peer.flags.contains(.copyProtectionEnabled) && !(peer.adminRights != nil || peer.groupAccess.isCreator)
        } else if self is TelegramUser, let cachedData = cachedData as? CachedUserData {
            return cachedData.flags.contains(.copyProtectionEnabled) || cachedData.flags.contains(.myCopyProtectionEnabled)
        } else {
            return false
        }
    }
    
    var maybePremiumRequired: Bool {
        if let peer = self as? TelegramUser {
            return peer.flags.contains(.requirePremium) && !peer.flags.contains(.mutualContact)
        }
        return false
    }
}
