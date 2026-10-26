import Foundation
import Postbox
import TelegramContext

// Novagram screens live in the app target (they use the concrete AccountContext and the app's
// table rows). Telegram packages reach them through these closures; the app installs them in
// Telegram-Mac/packages-integration/hooks/NovagramHooksInstall.swift. Defaults do nothing.
public struct NovagramHooks {
    public var presentEditedHistory: (_ context: any AccountContextProtocol, _ peerId: PeerId, _ messageId: Int32, _ currentText: String) -> Void = { _, _, _, _ in }

    public init() {}

    public static var shared = NovagramHooks()

    public static func install(_ hooks: NovagramHooks) {
        shared = hooks
    }
}
