import AppKit
import SwiftSignalKit

struct PeerId: Hashable { let value: Int64 }
protocol Peer: AnyObject {
    var id: PeerId { get }
    func isEqual(_ other: Peer) -> Bool
}
final class TestPeer: Peer {
    let id: PeerId
    let revision: Int
    init(_ id: Int64, _ revision: Int = 0) { self.id = PeerId(value: id); self.revision = revision }
    func isEqual(_ other: Peer) -> Bool {
        guard let other = other as? TestPeer else { return false }
        return id == other.id && revision == other.revision
    }
}
enum PostboxViewKey: Hashable { case basicPeer(PeerId) }
final class BasicPeerView {
    let peer: Peer?
    init(_ peer: Peer?) { self.peer = peer }
}
struct CombinedView { let views: [PostboxViewKey: Any] }
final class Account {
    let postbox = RecordingPostbox()
}
final class InlineStickersContext {}
struct Rendered {
    let peer: Peer
    let account: Account
    let inlinePacksContext: InlineStickersContext?
    let left: Bool
    let color: NSColor?
    let isSelected: Bool
    let isBig: Bool
    let animated: Bool
    let playTwice: Bool
    let isLite: Bool
    let autoupdate: Bool
}

final class RecordingPostbox {
    struct Registration {
        let keys: [PostboxViewKey]
        let subscriber: Subscriber<CombinedView, NoError>
    }
    private var registrations: [Int: Registration] = [:]
    var current: [PeerId: Peer] = [:]
    private(set) var queries = 0
    private(set) var starts = 0
    private(set) var disposals = 0
    var activeCount: Int { registrations.count }
    var emitOnSubscribe = true

    func combinedView(keys: [PostboxViewKey]) -> Signal<CombinedView, NoError> {
        queries += 1
        return Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            self.starts += 1
            let id = self.starts
            self.registrations[id] = Registration(keys: keys, subscriber: subscriber)
            if self.emitOnSubscribe {
                var views: [PostboxViewKey: Any] = [:]
                for key in keys {
                    if case let .basicPeer(peerId) = key { views[key] = BasicPeerView(self.current[peerId]) }
                }
                subscriber.putNext(CombinedView(views: views))
            }
            return ActionDisposable { [weak self] in
                self?.disposals += 1
                self?.registrations.removeValue(forKey: id)
            }
        }
    }

    func emit(_ peer: Peer) {
        current[peer.id] = peer
        let key = PostboxViewKey.basicPeer(peer.id)
        for registration in Array(registrations.values) where registration.keys.contains(key) {
            registration.subscriber.putNext(CombinedView(views: [key: BasicPeerView(peer)]))
        }
    }

    func emitMissing(_ id: PeerId) {
        current.removeValue(forKey: id)
        let key = PostboxViewKey.basicPeer(id)
        for registration in Array(registrations.values) where registration.keys.contains(key) {
            registration.subscriber.putNext(CombinedView(views: [key: BasicPeerView(nil)]))
        }
    }

    func delivery(_ peer: Peer) -> () -> Void {
        let key = PostboxViewKey.basicPeer(peer.id)
        let recipients = Array(registrations.values).filter { $0.keys.contains(key) }
        return {
            for recipient in recipients { recipient.subscriber.putNext(CombinedView(views: [key: BasicPeerView(peer)])) }
        }
    }
}
