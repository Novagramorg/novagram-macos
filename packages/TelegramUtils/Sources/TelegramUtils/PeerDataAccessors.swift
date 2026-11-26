import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

public extension CachedPeerData {
    var photo: TelegramMediaImage? {
        if let data = self as? CachedUserData {
            switch data.photo {
            case let .known(image):
                return image
            default:
                return nil
            }
        }
        if let data = self as? CachedChannelData {
            return data.photo
        }
        if let data = self as? CachedGroupData {
            return data.photo
        }
        return nil
    }
    var personalPhoto: TelegramMediaImage? {
        if let data = self as? CachedUserData {
            switch data.personalPhoto {
            case let .known(image):
                return image
            default:
                return nil
            }
        }
        return nil
    }
    var fallbackPhoto: TelegramMediaImage? {
        if let data = self as? CachedUserData {
            switch data.fallbackPhoto {
            case let .known(image):
                return image
            default:
                return nil
            }
        }
        return nil
    }
}

public extension Peer {
    var username:String? {
        if let peer = self as? TelegramChannel {
            return peer.addressName
        } else if let peer = self as? TelegramGroup {
            return peer.addressName
        } else if let peer = self as? TelegramUser {
            return peer.addressName
        }
        return nil
    }
}

public extension TelegramUser {
    func canBeDirectRecipient(accountPeerId: PeerId) -> Bool {
        return !self.isDeleted && self.botInfo == nil && !isServicePeer(self) && self.id != accountPeerId
    }
}

public func getPeerView(peerId: PeerId, postbox: Postbox) -> Signal<Peer?, NoError> {
    return postbox.combinedView(keys: [.basicPeer(peerId)]) |> map { view in
        return (view.views[.basicPeer(peerId)] as? BasicPeerView)?.peer
    }
}

public func getCachedDataView(peerId: PeerId, postbox: Postbox) -> Signal<CachedPeerData?, NoError> {
    return postbox.combinedView(keys: [.cachedPeerData(peerId: peerId)]) |> map { view in
        return (view.views[.cachedPeerData(peerId: peerId)] as? CachedPeerDataView)?.cachedPeerData
    }
}
