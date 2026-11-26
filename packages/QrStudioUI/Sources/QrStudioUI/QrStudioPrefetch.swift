import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext

final class QrStudioPrefetch {
    private struct Key: Hashable {
        let accountPeerId: PeerId
        let peerId: PeerId
    }

    private final class Entry {
        let startedAt: Double
        let shareTheme = Promise<TelegramShareTheme?>()
        var giftsContext: ProfileGiftsContext?
        let filesDisposable = MetaDisposable()

        init(startedAt: Double) {
            self.startedAt = startedAt
        }

        deinit {
            self.filesDisposable.dispose()
        }
    }

    static let shared = QrStudioPrefetch()

    private static let lifetime: Double = 60.0
    private static let maxEntries = 2

    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private var backdropsDisposable: Disposable?
    private var backdropsAccountPeerId: PeerId?

    func prefetch(context: any AccountContextProtocol, peerId: PeerId, canEdit: Bool) {
        assert(Thread.isMainThread)
        let key = Key(accountPeerId: context.peerId, peerId: peerId)
        if self.freshEntry(for: key) == nil {
            let entry = Entry(startedAt: CFAbsoluteTimeGetCurrent())
            entry.shareTheme.set(context.engine.peers.getShareTheme(peerId: peerId) |> take(1))
            entry.filesDisposable.set(context.engine.peers.preloadShareTheme(peerId: peerId).start())
            if canEdit {
                entry.giftsContext = ProfileGiftsContext(account: context.account, peerId: peerId, filter: [.unique, .displayed, .hidden])
            }
            self.store(entry, for: key)
        }
        if self.backdropsAccountPeerId != context.peerId {
            self.backdropsAccountPeerId = context.peerId
            self.backdropsDisposable?.dispose()
            self.backdropsDisposable = context.engine.peers.shareThemeBackdrops().start()
        }
    }

    func makeController(context: any AccountContextProtocol, peerId: PeerId) -> Signal<QrStudioController?, NoError> {
        assert(Thread.isMainThread)
        self.prefetch(context: context, peerId: peerId, canEdit: peerId == context.peerId)
        let key = Key(accountPeerId: context.peerId, peerId: peerId)
        return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        |> mapToSignal { peer -> Signal<(EnginePeer?, AccountPrivacySettings?), NoError> in
            let needsPrivacy = peer?.id == context.peerId && (peer?.addressName ?? "").isEmpty
            let privacy: Signal<AccountPrivacySettings?, NoError> = needsPrivacy ? context.privacy |> filter { $0 != nil } |> take(1) : .single(nil)
            return privacy |> map { (peer, $0) }
        }
        |> deliverOnMainQueue
        |> map { [weak self] peer, privacy -> QrStudioController? in
            guard let peer else {
                return nil
            }
            let temporary = peer.id == context.peerId && privacy?.phoneDiscoveryEnabled == false && (peer.addressName ?? "").isEmpty
            let controller = QrStudioController(context: context, peer: peer, temporary: temporary)
            controller.loadViewIfNeeded()
            self?.entries[key] = nil
            self?.order.removeAll(where: { $0 == key })
            return controller
        }
    }

    func giftsContext(context: any AccountContextProtocol, peerId: PeerId) -> ProfileGiftsContext {
        assert(Thread.isMainThread)
        if let giftsContext = self.freshEntry(for: Key(accountPeerId: context.peerId, peerId: peerId))?.giftsContext {
            return giftsContext
        }
        return ProfileGiftsContext(account: context.account, peerId: peerId, filter: [.unique, .displayed, .hidden])
    }

    private func freshEntry(for key: Key) -> Entry? {
        guard let entry = self.entries[key] else {
            return nil
        }
        if CFAbsoluteTimeGetCurrent() - entry.startedAt > QrStudioPrefetch.lifetime {
            self.entries[key] = nil
            self.order.removeAll(where: { $0 == key })
            return nil
        }
        return entry
    }

    private func store(_ entry: Entry, for key: Key) {
        self.order.removeAll(where: { $0 == key })
        self.entries[key] = entry
        self.order.append(key)
        while self.order.count > QrStudioPrefetch.maxEntries {
            let evicted = self.order.removeFirst()
            self.entries[evicted] = nil
        }
        Queue.mainQueue().after(QrStudioPrefetch.lifetime, { [weak self, weak entry] in
            guard let self, let entry, self.entries[key] === entry else {
                return
            }
            self.entries[key] = nil
            self.order.removeAll(where: { $0 == key })
        })
    }
}

public func prefetchQrStudio(context: any AccountContextProtocol) {
    QrStudioPrefetch.shared.prefetch(context: context, peerId: context.peerId, canEdit: true)
}

public func prefetchQrStudio(context: any AccountContextProtocol, peer: Peer) {
    let canEdit: Bool
    if peer.id == context.peerId {
        canEdit = true
    } else if let channel = peer as? TelegramChannel, let addressName = channel.addressName, !addressName.isEmpty {
        canEdit = channel.flags.contains(.isCreator) || channel.hasPermission(.changeInfo)
    } else {
        if (peer.addressName ?? "").isEmpty {
            return
        }
        canEdit = false
    }
    QrStudioPrefetch.shared.prefetch(context: context, peerId: peer.id, canEdit: canEdit)
}
