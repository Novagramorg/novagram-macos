//
//  NovagramAutoApproveManager.swift
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
private let kAutoApproveKey = "fenix_autoaccept_global"
// The Mac key before 2026-10; copied into the iOS key once.
private let kAutoApproveLegacyKey = "auto_approve_join_requests"

// Port of the iOS NovagramAutoAcceptManager. Requests are approved when the chat or its info page is
// opened, and by a scan of the first 300 chats every 60 seconds while the switch is on.
public final class NovagramAutoApproveManager {
    public static let shared = NovagramAutoApproveManager()
    public static let defaultsKey = kAutoApproveKey

    private let defaults = UserDefaults(suiteName: kAutoApproveSuite)
    private let cooldownSeconds: Int32 = 15
    private let pollIntervalSeconds: Double = 60
    private let chatListScanCount = 300
    // updateAll keeps working only while its context is alive.
    private var retainedContexts: [PeerId: PeerInvitationImportersContext] = [:]
    private var lastApprovedAt: [PeerId: Int32] = [:]
    private let monitorDisposable = MetaDisposable()
    private weak var monitorContext: AccountContextProtocol?
    private var monitorGeneration = 0
    private var settingsObserver: NSObjectProtocol?

    private init() {
        if defaults?.object(forKey: kAutoApproveKey) == nil, let legacy = defaults?.object(forKey: kAutoApproveLegacyKey) as? Bool {
            defaults?.set(legacy, forKey: kAutoApproveKey)
            defaults?.removeObject(forKey: kAutoApproveLegacyKey)
        }
    }

    public var isEnabled: Bool {
        return defaults?.bool(forKey: kAutoApproveKey) ?? false
    }

    public func setEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: kAutoApproveKey)
        NotificationCenter.default.post(name: NSNotification.Name("NovagramSettingsChanged"), object: nil)
    }

    // Peer info page.
    public func checkAndApprove(context: any AccountContextProtocol, peerId: PeerId, joinRequestsCount: Int32) {
        guard isEnabled && joinRequestsCount > 0 else {
            return
        }
        approveWithCooldown(context: context, peerId: peerId)
    }

    // Chat opened.
    public func autoApproveIfNeeded(context: any AccountContextProtocol, peer: Peer?) {
        guard isEnabled, let peer, canApproveRequests(peer: peer) else {
            return
        }
        approveIfPending(context: context, peerId: peer.id)
    }

    // Called when an account context starts; the scan itself runs only while the switch is on.
    public func start(context: any AccountContextProtocol) {
        monitorContext = context
        if settingsObserver == nil {
            settingsObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name("NovagramSettingsChanged"), object: nil, queue: .main, using: { [weak self] _ in
                self?.restartMonitor()
            })
        }
        restartMonitor()
    }

    public func stop() {
        monitorContext = nil
        restartMonitor()
    }

    private func restartMonitor() {
        monitorGeneration += 1
        monitorDisposable.set(nil)
        guard isEnabled, monitorContext != nil else {
            return
        }
        scheduleScan(generation: monitorGeneration, delay: 0.5)
    }

    private func scheduleScan(generation: Int, delay: Double) {
        Queue.mainQueue().after(delay, { [weak self] in
            guard let self, generation == self.monitorGeneration, self.isEnabled, let context = self.monitorContext else {
                return
            }
            self.scanAdminPeers(context: context)
            self.scheduleScan(generation: generation, delay: self.pollIntervalSeconds)
        })
    }

    private func scanAdminPeers(context: any AccountContextProtocol) {
        let signal = context.engine.messages.chatList(group: .root, count: chatListScanCount)
            |> take(1)
            |> deliverOnMainQueue
        monitorDisposable.set(signal.start(next: { [weak self, weak context] chatList in
            guard let self, let context, self.isEnabled else {
                return
            }
            for item in chatList.items {
                guard let peer = item.renderedPeer.chatMainPeer?._asPeer() else {
                    continue
                }
                if self.canApproveRequests(peer: peer) {
                    self.approveIfPending(context: context, peerId: peer.id)
                }
            }
        }))
    }

    private func approveIfPending(context: any AccountContextProtocol, peerId: PeerId) {
        if isCoolingDown(peerId) {
            return
        }
        _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.CachedData(id: peerId))
            |> deliverOnMainQueue).start(next: { [weak self, weak context] cachedData in
            guard let self, let context, self.pendingRequestCount(cachedData) > 0 else {
                return
            }
            self.approveWithCooldown(context: context, peerId: peerId)
        })
    }

    private func approveWithCooldown(context: any AccountContextProtocol, peerId: PeerId) {
        if isCoolingDown(peerId) {
            return
        }
        lastApprovedAt[peerId] = Int32(Date().timeIntervalSince1970)
        let importers = context.engine.peers.peerInvitationImporters(peerId: peerId, subject: .requests(query: nil))
        retainedContexts[peerId] = importers
        importers.updateAll(action: .approve)
        Queue.mainQueue().after(30.0, { [weak self] in
            self?.retainedContexts.removeValue(forKey: peerId)
        })
    }

    private func isCoolingDown(_ peerId: PeerId) -> Bool {
        guard let last = lastApprovedAt[peerId] else {
            return false
        }
        return Int32(Date().timeIntervalSince1970) - last < cooldownSeconds
    }

    private func pendingRequestCount(_ cachedData: CachedPeerData?) -> Int32 {
        if let channel = cachedData as? CachedChannelData {
            return channel.inviteRequestsPending ?? 0
        } else if let group = cachedData as? CachedGroupData {
            return group.inviteRequestsPending ?? 0
        }
        return 0
    }

    private func canApproveRequests(peer: Peer) -> Bool {
        if let channel = peer as? TelegramChannel {
            return channel.hasPermission(.inviteMembers)
        } else if let group = peer as? TelegramGroup {
            switch group.role {
            case .creator:
                return true
            case let .admin(rights, _):
                return rights.rights.contains(.canInviteUsers)
            case .member:
                return false
            }
        }
        return false
    }
}
