import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext

public func permanentExportedInvitation(context: any AccountContextProtocol, peerId: PeerId) -> Signal<ExportedInvitation?, NoError> {
    return context.account.postbox.transaction { transaction -> ExportedInvitation? in
        let cachedData = transaction.getPeerCachedData(peerId: peerId)
        if let cachedData = cachedData as? CachedChannelData {
            return cachedData.exportedInvitation
        }
        if let cachedData = cachedData as? CachedGroupData {
            return cachedData.exportedInvitation
        }
        return nil
    } |> mapToSignal { invitation in
        if invitation == nil {
            return context.engine.peers.revokePersistentPeerExportedInvitation(peerId: peerId)
        } else {
            return .single(invitation)
        }
    }
}
