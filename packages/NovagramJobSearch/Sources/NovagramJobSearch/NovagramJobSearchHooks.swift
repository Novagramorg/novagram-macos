import Foundation
import Postbox
import TelegramContext

public struct NovagramJobSearchHooks {
    public var openMessage: (_ context: any AccountContextProtocol, _ message: Message) -> Void = { _, _ in }
    public var openPeer: (_ context: any AccountContextProtocol, _ peerId: PeerId) -> Void = { _, _ in }

    public init() {}

    public static var shared = NovagramJobSearchHooks()

    public static func install(_ hooks: NovagramJobSearchHooks) {
        shared = hooks
    }
}
