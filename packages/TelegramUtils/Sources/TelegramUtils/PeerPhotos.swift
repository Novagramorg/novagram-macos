import Cocoa
import TelegramContext
import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import TelegramCore


private struct PeerPhotos {
    public let photos: [TelegramPeerPhotoHolder]
    public let time: TimeInterval
}

public struct TelegramPeerPhotoHolder {
    public let value: TelegramPeerPhoto
    public let caption: String?
    public init(value: TelegramPeerPhoto, caption: String?) {
        self.value = value
        self.caption = caption
    }
}

private var peerAvatars:Atomic<[PeerId: PeerPhotos]> = Atomic(value: [:])
private let maxCachedPeerPhotos: Int = 200


public func syncPeerPhotos(peerId: PeerId) -> [TelegramPeerPhotoHolder] {
    return peerAvatars.with { $0[peerId].map { $0.photos } ?? [] }
}
public func resetPeerPhotos(peerId: PeerId) {
    _ = peerAvatars.modify { current in
        var current = current
        current.removeValue(forKey: peerId)
        return current
    }
}

public func peerPhotos(context: (any AccountContextProtocol), peerId: PeerId, force: Bool = false) -> Signal<[TelegramPeerPhotoHolder], NoError> {
    let photos = peerAvatars.with { $0[peerId] }
    if let photos = photos, photos.time > Date().timeIntervalSince1970, !force {
        return .single(photos.photos)
    } else {
        return .single(peerAvatars.with { $0[peerId]?.photos } ?? []) |> then(combineLatest(context.engine.peers.requestPeerPhotos(peerId: peerId), getCachedDataView(peerId: peerId, postbox: context.account.postbox) |> take(1), getPeerView(peerId: peerId, postbox: context.account.postbox) |> take(1)) |> delay(0.4, queue: .concurrentDefaultQueue()) |> map { photos, cachedData, peer in
            return peerAvatars.modify { value in
                var value = value
                var photos:[TelegramPeerPhotoHolder] = photos.map {
                    return .init(value: $0, caption: nil)
                }
                if let cachedData = cachedData, let value = cachedData.personalPhoto {
                    if photos.firstIndex(where: { $0.value.image.id == value.id }) == nil {
                        photos.insert(.init(value: TelegramPeerPhoto(image: value, reference: nil, date: 0, index: 0, totalCount: photos.first?.value.totalCount ?? 0, messageId: nil), caption: nil), at: 0)
                    }
                } else if let cachedData = cachedData, let value = cachedData.photo {
                    if photos.firstIndex(where: { $0.value.image.id == value.id }) == nil {
                        photos.insert(.init(value: TelegramPeerPhoto(image: value, reference: nil, date: 0, index: 0, totalCount: photos.first?.value.totalCount ?? 0, messageId: nil), caption: nil), at: 0)
                    }
                }
                value[peerId] = PeerPhotos(photos: photos, time: Date().timeIntervalSince1970 + 5 * 60)
                if value.count > maxCachedPeerPhotos {
                    let evicted = value.filter { $0.key != peerId }.sorted(by: { $0.value.time < $1.value.time }).prefix(value.count - maxCachedPeerPhotos)
                    for (key, _) in evicted {
                        value.removeValue(forKey: key)
                    }
                }
                return value
            }[peerId]?.photos ?? []
        })
    }
}

public func hasCachedPeerPhotos(peerId: PeerId) -> Bool {
    return peerAvatars.with { $0[peerId] != nil }
}
