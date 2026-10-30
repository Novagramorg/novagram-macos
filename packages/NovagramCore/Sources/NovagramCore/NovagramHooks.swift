import Foundation
import Postbox
import TelegramCore
import TelegramContext
import SwiftSignalKit

// Novagram screens live in the app target (they use the concrete AccountContext and the app's
// table rows). Telegram packages reach them through these closures; the app installs them in
// Telegram-Mac/packages-integration/hooks/NovagramHooksInstall.swift. Defaults do nothing.
public struct NovagramHooks {
    public var presentEditedHistory: (_ context: any AccountContextProtocol, _ peerId: PeerId, _ messageId: Int32, _ currentText: String) -> Void = { _, _, _, _ in }
    public var openChat: (_ context: any AccountContextProtocol, _ peerId: PeerId) -> Void = { _, _ in }
    // Statistics: the user confirmed a logout of this account (called right before logoutFromAccount).
    public var accountWillLogOut: (_ accountId: AccountRecordId) -> Void = { _ in }
    // Chat list menu → Recent actions (admin log) of a channel or supergroup.
    public var openRecentActions: (_ context: any AccountContextProtocol, _ peer: Peer) -> Void = { _, _ in }
    public var openJobSearch: (_ context: any AccountContextProtocol, _ savedSearchId: String?) -> Void = { _, _ in }
    public var jobSearchUnseenCount: (_ context: any AccountContextProtocol) -> Signal<Int, NoError> = { _ in .single(0) }
    public var handleNotificationClick: (_ userInfo: [AnyHashable: Any]) -> Bool = { _ in false }

    public init() {}

    public static var shared = NovagramHooks()

    public static func install(_ hooks: NovagramHooks) {
        shared = hooks
    }
}
