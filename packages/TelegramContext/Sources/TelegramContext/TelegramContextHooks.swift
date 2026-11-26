import Foundation
import Postbox
import TelegramCore

public struct TelegramContextHooks {
    public let peerTitle: (Peer) -> String

    public init(peerTitle: @escaping (Peer) -> String) {
        self.peerTitle = peerTitle
    }

    public static var shared: TelegramContextHooks = TelegramContextHooks(peerTitle: { _ in return "" })
}

public func installTelegramContextHooks(_ hooks: TelegramContextHooks) {
    TelegramContextHooks.shared = hooks
}
