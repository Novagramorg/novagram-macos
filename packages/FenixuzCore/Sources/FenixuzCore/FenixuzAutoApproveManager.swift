//
//  FenixuzAutoApproveManager.swift
//  Telegram-Mac
//
//  Feature #40: Qo'shilish so'rovlarini avtomatik qabul qilish (Auto-Approve Join Requests)
//  Automatically approves join requests for channels/groups where the user is admin.
//

import Foundation
import Cocoa
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext

private let kAutoApproveSuite = "pro_messager"
private let kAutoApproveKey = "auto_approve_join_requests"

public final class FenixuzAutoApproveManager {
    public static let shared = FenixuzAutoApproveManager()

    private let defaults = UserDefaults(suiteName: kAutoApproveSuite)

    private init() {}

    public var isEnabled: Bool {
        return defaults?.bool(forKey: kAutoApproveKey) ?? false
    }

    public func setEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: kAutoApproveKey)
        NotificationCenter.default.post(name: NSNotification.Name("FenixSettingsChanged"), object: nil)
    }

    public func checkAndApprove(context: any AccountContextProtocol, peerId: PeerId, joinRequestsCount: Int32) {
        guard isEnabled && joinRequestsCount > 0 else {
            return
        }

        let manager = context.engine.peers.peerInvitationImporters(peerId: peerId, subject: .requests(query: nil))
        manager.updateAll(action: .approve)
    }
}
