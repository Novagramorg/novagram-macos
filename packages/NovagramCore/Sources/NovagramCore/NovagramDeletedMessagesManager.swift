//
//  NovagramDeletedMessagesManager.swift
//  Telegram-Mac
//
//  "Show deleted messages" — the macOS consumer for the `show_deleted_messages`
//  toggle (Settings → Novagram → Chat). iOS implements this by patching TelegramCore
//  to tag deletions with a `DeletedMessageAttribute`, then filtering the history view
//  on it. Mac's TelegramCore submodule is pinned to a different commit WITHOUT that
//  attribute, and patching the shared core is high-risk for future pulls — so this is
//  a self-contained, client-side port (same reasoning as NovagramEditedHistoryManager).
//
//  Mechanism (no core patch):
//    1. Every history pass feeds the currently-loaded `[MessageHistoryEntry]` into the
//       manager (`process`), which caches them per peer — this is where the CONTENT of a
//       message lives before the server/user deletes it.
//    2. ChatController subscribes to the authoritative `account.stateManager.deletedMessages`
//       signal and calls `recordDeleted`. For each deleted id we still have cached, we build
//       a "tombstone" entry (original message + a 🗑 marker) and keep it.
//    3. When the toggle is ON, `process` re-injects tombstones that fall inside the loaded
//       index window, so deleted messages stay visible instead of vanishing.
//
//  Fail-safe: the toggle is OFF by default, and when OFF (or when there is nothing to
//  inject) `process` returns the input array UNCHANGED — normal chat is never touched.
//  Tombstones are session-scoped (in-memory, bounded); persisting Postbox messages across
//  launches is out of scope for v1.
//

import Foundation
import Postbox
import TelegramCore

private struct NovagramDeletedChatKey: Hashable {
    let accountId: AccountRecordId
    let peerId: PeerId
}

public final class NovagramDeletedMessages {
    public static let shared = NovagramDeletedMessages()
    private init() {}


    private let lock = NSLock()

    // Recently-loaded entries per peer — the source of content when a delete fires.
    private var live: [NovagramDeletedChatKey: [MessageId: MessageHistoryEntry]] = [:]
    private var liveOrder: [NovagramDeletedChatKey: [MessageId]] = [:]  // insertion order for bounded eviction
    // Deleted entries per peer, already 🗑-marked and ready to re-inject.
    private var tombstones: [NovagramDeletedChatKey: [MessageId: MessageHistoryEntry]] = [:]

    private let liveCap = 600
    private let tombstoneCap = 300
    private let marker = "🗑 "

    /// Reads the same UserDefaults key the settings toggle writes (`pro_messager`/`show_deleted_messages`).
    public var isEnabled: Bool {
        return UserDefaults(suiteName: "pro_messager")?.bool(forKey: "show_deleted_messages") ?? false
    }

    /// Called on every history pass: caches the current entries, then (only when enabled)
    /// returns them with any in-window tombstones merged in. When disabled or empty it
    /// returns `entries` unchanged.
    /// `hasLater` = there are newer messages below the loaded window (view.laterId != nil).
    /// When false the chat bottom is loaded, so a tombstone newer than everything on screen
    /// (the just-sent-then-deleted case) belongs at the end and must still be shown.
    public func process(_ entries: [MessageHistoryEntry], peerId: PeerId, account: Account, hasEarlier: Bool, hasLater: Bool) -> [MessageHistoryEntry] {
        let key = NovagramDeletedChatKey(accountId: account.id, peerId: peerId)
        cache(entries, key: key)
        guard isEnabled else { return entries }
        return merge(entries, key: key, hasEarlier: hasEarlier, hasLater: hasLater)
    }

    /// Records deletions from `stateManager.deletedMessages`. Returns true if a tombstone
    /// was newly created for `peerId` (so the caller can nudge that chat to refresh).
    @discardableResult
    public func recordDeleted(_ ids: [DeletedMessageId], peerId: PeerId, account: Account) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var createdForPeer = false
        var archived: [Message] = []
        for did in ids {
            // TelegramCore maps CloudUser (1-on-1) & CloudGroup deletions to `.global(id.id)` —
            // peer stripped, shared id space. Channels/secret chats keep `.messageId`. Resolve
            // `.global` against our cache (any non-channel cloud message with that numeric id).
            let targets: [MessageId]
            switch did {
            case let .messageId(mid):
                targets = [mid]
            case let .global(gid):
                targets = live.compactMap { (key, msgs) -> MessageId? in
                    let peer = key.peerId
                    guard key.accountId == account.id, peer.namespace == Namespaces.Peer.CloudUser || peer.namespace == Namespaces.Peer.CloudGroup else { return nil }
                    return msgs.values.first(where: { $0.message.id.id == gid })?.message.id
                }
            }
            for mid in targets {
                let key = NovagramDeletedChatKey(accountId: account.id, peerId: mid.peerId)
                guard tombstones[key]?[mid] == nil else { continue }
                guard let entry = live[key]?[mid] else {
                    continue
                }
                tombstones[key, default: [:]][mid] = markDeleted(entry)
                archived.append(entry.message)
                enforceTombstoneCap(key)
                if mid.peerId == peerId {
                    createdForPeer = true
                }
            }
        }
        if !archived.isEmpty {
            NovagramMessageArchive.shared.recordDeleted(archived, account: account)
        }
        return createdForPeer
    }

    // MARK: - Internals

    private func cache(_ entries: [MessageHistoryEntry], key: NovagramDeletedChatKey) {
        lock.lock(); defer { lock.unlock() }
        for e in entries {
            let id = e.message.id
            if live[key]?[id] == nil {
                liveOrder[key, default: []].append(id)
            }
            live[key, default: [:]][id] = e
        }
        guard var order = liveOrder[key], order.count > liveCap else { return }
        // Evict oldest, but never drop an id we've tombstoned (we still need its content).
        var overflow = order.count - liveCap
        var i = 0
        while overflow > 0 && i < order.count {
            let id = order[i]
            if tombstones[key]?[id] == nil {
                live[key]?.removeValue(forKey: id)
                order.remove(at: i)
                overflow -= 1
            } else {
                i += 1
            }
        }
        liveOrder[key] = order
    }

    private func merge(_ entries: [MessageHistoryEntry], key: NovagramDeletedChatKey, hasEarlier: Bool, hasLater: Bool) -> [MessageHistoryEntry] {
        lock.lock(); defer { lock.unlock() }
        guard let tomb = tombstones[key], !tomb.isEmpty else { return entries }
        // Need at least one loaded message to anchor positions against.
        guard let lower = entries.first?.index else {
            return entries
        }
        let upper = entries.last?.index
        let present = Set(entries.map { $0.message.id })
        var result = entries
        var injected = 0
        for (id, entry) in tomb {
            if present.contains(id) { continue }
            // Skip only when the tombstone is beyond the loaded window AND there is still
            // unloaded content in that direction (so it isn't just the deleted edge message).
            if entry.index < lower, hasEarlier { continue }
            if let upper = upper, entry.index > upper, hasLater { continue }
            result.append(entry)
            injected += 1
        }
        if injected > 0 {
            result.sort()
        }
        return result
    }

    private func markDeleted(_ entry: MessageHistoryEntry) -> MessageHistoryEntry {
        let msg = entry.message
        let markedText = msg.text.isEmpty ? "🗑" : (marker + msg.text)
        let markedMessage = msg.withUpdatedText(markedText)
        return MessageHistoryEntry(message: markedMessage,
                                   isRead: entry.isRead,
                                   location: entry.location,
                                   monthLocation: entry.monthLocation,
                                   attributes: entry.attributes)
    }

    private func enforceTombstoneCap(_ key: NovagramDeletedChatKey) {
        guard var dict = tombstones[key], dict.count > tombstoneCap else { return }
        let dropCount = dict.count - tombstoneCap
        let oldest = dict.values.sorted(by: { $0.index < $1.index }).prefix(dropCount)
        for e in oldest {
            dict.removeValue(forKey: e.message.id)
        }
        tombstones[key] = dict
    }
}
