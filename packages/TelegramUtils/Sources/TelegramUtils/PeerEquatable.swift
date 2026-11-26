import Foundation
import TelegramCore
import Postbox

public struct PeerEquatable: Equatable {
    public let peer: Peer
    
    public var peerId: PeerId {
        return peer.id
    }
    public var id: PeerId {
        return peer.id
    }
    public init(peer: Peer) {
        self.peer = peer
    }
    public init(_ peer: Peer) {
        self.peer = peer
    }
    public init?(_ peer: Peer?) {
        if let peer = peer {
            self.peer = peer
        } else {
            return nil
        }
    }
    public static func ==(lhs: PeerEquatable, rhs: PeerEquatable) -> Bool {
        return lhs.peer.isEqual(rhs.peer)
    }
}

public struct CachedDataEquatable: Equatable {
    public let data: CachedPeerData
    public init?(data: CachedPeerData?) {
        if let data = data {
            self.data = data
        } else {
            return nil
        }
    }
    public init?(_ data: CachedPeerData?) {
        self.init(data: data)
    }
    public init(data: CachedPeerData) {
        self.data = data
    }
    public init(_ data: CachedPeerData) {
        self.init(data: data)
    }
    public static func ==(lhs: CachedDataEquatable, rhs: CachedDataEquatable) -> Bool {
        return lhs.data.isEqual(to: rhs.data)
    }
}
