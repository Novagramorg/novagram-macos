import Foundation
import Postbox
import TelegramCore

import SwiftSignalKit
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif


public func storedMessageFromSearchPeer(account: Account, peer: Peer) -> Signal<PeerId, NoError> {
    return account.postbox.transaction { transaction -> PeerId in
        if transaction.getPeer(peer.id) == nil {
            updatePeersCustom(transaction: transaction, peers: [peer], update: { previousPeer, updatedPeer in
                return updatedPeer
            })
        }
        if let group = transaction.getPeer(peer.id) as? TelegramGroup, let migrationReference = group.migrationReference {
            return migrationReference.peerId
        }
        return peer.id
    }
}
