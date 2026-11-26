import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext

public struct PendingChatRemovalToast: Equatable {
    public let peerId: PeerId
    public let text: String
    public let deadline: CFTimeInterval
    public let duration: Double
}

public final class PendingChatRemovals {
    private struct Pending {
        let peerId: PeerId
        let commit: () -> Signal<Never, NoError>
    }

    public static let timeout: Double = 5.0

    private static var instances: [AccountRecordId: PendingChatRemovals] = [:]

    public static func get(_ context: any AccountContextProtocol) -> PendingChatRemovals {
        let id = context.account.id
        if let current = instances[id] {
            return current
        }
        let value = PendingChatRemovals()
        instances[id] = value
        return value
    }

    private var pending: Pending?
    private var timer: SwiftSignalKit.Timer?
    private var hidden: Set<PeerId> = Set() {
        didSet {
            hiddenValue.set(hidden)
        }
    }
    private let hiddenValue = ValuePromise<Set<PeerId>>(Set(), ignoreRepeated: true)
    private let toastValue = ValuePromise<PendingChatRemovalToast?>(nil, ignoreRepeated: true)

    public var hiddenPeerIds: Signal<Set<PeerId>, NoError> {
        return hiddenValue.get()
    }

    public var toast: Signal<PendingChatRemovalToast?, NoError> {
        return toastValue.get()
    }

    public func schedule(peerId: PeerId, text: String, commit: @escaping () -> Signal<Never, NoError>) {
        if hidden.contains(peerId) {
            return
        }
        commitPending()

        pending = Pending(peerId: peerId, commit: commit)
        hidden.insert(peerId)
        toastValue.set(PendingChatRemovalToast(peerId: peerId, text: text, deadline: CACurrentMediaTime() + PendingChatRemovals.timeout, duration: PendingChatRemovals.timeout))

        let timer = SwiftSignalKit.Timer(timeout: PendingChatRemovals.timeout, repeat: false, completion: { [weak self] in
            self?.commitPending()
        }, queue: .mainQueue())
        self.timer = timer
        timer.start()
    }

    public func undo() {
        timer?.invalidate()
        timer = nil
        guard let pending = self.pending else {
            return
        }
        self.pending = nil
        toastValue.set(nil)
        hidden.remove(pending.peerId)
    }

    private func commitPending() {
        timer?.invalidate()
        timer = nil
        guard let pending = self.pending else {
            return
        }
        self.pending = nil
        toastValue.set(nil)
        let peerId = pending.peerId
        _ = (pending.commit() |> deliverOnMainQueue).start(completed: { [weak self] in
            self?.hidden.remove(peerId)
        })
    }
}
