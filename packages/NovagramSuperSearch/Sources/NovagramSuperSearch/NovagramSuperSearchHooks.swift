import Foundation
import Postbox
import TelegramContext

public struct NovagramSuperSearchHooks {
    public var openMessage: (_ context: any AccountContextProtocol, _ message: Message) -> Void = { _, _ in }
    public var openMessageId: (_ context: any AccountContextProtocol, _ messageId: MessageId) -> Void = { _, _ in }
    public var openPeer: (_ context: any AccountContextProtocol, _ peerId: PeerId) -> Void = { _, _ in }

    public init() {}

    public static var shared = NovagramSuperSearchHooks()

    public static func install(_ hooks: NovagramSuperSearchHooks) {
        shared = hooks
    }
}
