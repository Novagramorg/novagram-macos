import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox

final class PremiumStatusPeerObservation {
    private let disposable = MetaDisposable()
    private weak var account: Account?
    private var peer: Peer?
    private var onUpdate: ((Peer) -> Void)?
    private var generation: UInt64 = 0

    func update(peer: Peer, account: Account, enabled: Bool, onUpdate: @escaping (Peer) -> Void) {
        guard enabled else {
            self.generation &+= 1
            self.account = nil
            self.peer = nil
            self.onUpdate = nil
            self.disposable.set(nil)
            return
        }

        let isCurrent: Bool
        if self.account === account, let current = self.peer, current.id == peer.id {
            isCurrent = current === peer || current.isEqual(peer)
        } else {
            isCurrent = false
        }
        self.account = account
        self.peer = peer
        self.onUpdate = onUpdate
        guard !isCurrent else {
            return
        }

        self.generation &+= 1
        let generation = self.generation
        self.disposable.set(nil)
        let peerId = peer.id
        let updatedPeer = account.postbox.combinedView(keys: [.basicPeer(peerId)]) |> map { view in
            return (view.views[.basicPeer(peerId)] as? BasicPeerView)?.peer
        }
        |> filter { $0 != nil }
        |> map { $0! }
        |> deliverOnMainQueue

        let subscription = updatedPeer.start(next: { [weak self] updated in
            guard let self, self.generation == generation, let current = self.peer else {
                return
            }
            if !updated.isEqual(current) {
                self.peer = updated
                self.onUpdate?(updated)
            }
        })
        if self.generation == generation {
            self.disposable.set(subscription)
        } else {
            subscription.dispose()
        }
    }

    deinit {
        disposable.dispose()
    }
}
