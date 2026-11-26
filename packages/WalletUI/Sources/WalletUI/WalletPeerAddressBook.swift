import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramContext
import WalletContext

private struct WalletRememberedPeers {
    weak var owner: AnyObject?
    var peers: [String: EnginePeer]
}

private let walletRememberedPeers = Atomic<[ObjectIdentifier: WalletRememberedPeers]>(value: [:])

@available(macOS 10.15, *)
extension WalletContext {
    func rememberPresentedWalletPeer(_ peer: EnginePeer, address: String) {
        self.rememberWalletPeer(peer, address: address)
        guard let key = WalletContext.transferAddress(from: address) else {
            return
        }
        let contextId = ObjectIdentifier(self)
        _ = walletRememberedPeers.modify { current in
            var current = current.filter { $0.value.owner != nil }
            var entry = current[contextId] ?? WalletRememberedPeers(owner: self, peers: [:])
            entry.peers[key] = peer
            current[contextId] = entry
            return current
        }
    }

    func walletPeer(forAddress address: String) -> EnginePeer? {
        guard let key = WalletContext.transferAddress(from: address) else {
            return nil
        }
        let contextId = ObjectIdentifier(self)
        if let peer = walletRememberedPeers.with({ entries -> EnginePeer? in
            guard let entry = entries[contextId], entry.owner === self else {
                return nil
            }
            return entry.peers[key]
        }) {
            return peer
        }
        for transaction in self.stateValue.transactions.items {
            if case let .user(peer, peerAddress, _) = transaction.peer, WalletContext.transferAddress(from: peerAddress) == key {
                return peer
            }
        }
        return nil
    }

    func walletPeerDisplayName(forAddress address: String, environment: WalletUIEnvironment) -> String? {
        return self.walletPeer(forAddress: address).map { environment.peerTitle($0._asPeer(), compact: false) }
    }
}

struct WalletAddressOwner: Equatable {
    let peer: EnginePeer
    let publicKey: Data?
}

@available(macOS 10.15, *)
func walletAddressOwner(context: any AccountContextProtocol, address: String) -> Signal<WalletAddressOwner?, NoError> {
    guard let normalizedAddress = WalletContext.transferAddress(from: address) else {
        return .single(nil)
    }
    return context.engine.wallet.getUserAddresses(addresses: [address], force: false)
    |> `catch` { _ in Signal<[WalletUserAddress], NoError>.single([]) }
    |> mapToSignal { entries -> Signal<WalletAddressOwner?, NoError> in
        guard let entry = entries.first(where: { WalletContext.transferAddress(from: $0.address) == normalizedAddress }), let userId = entry.userId as EnginePeer.Id? else {
            return .single(nil)
        }
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: userId))
        |> map { peer -> WalletAddressOwner? in
            guard let peer, case .user = peer else {
                return nil
            }
            return WalletAddressOwner(peer: peer, publicKey: entry.publicKey.isEmpty ? nil : entry.publicKey)
        }
    }
}
