import Foundation
import Postbox
import SwiftSignalKit

// Novagram "Unlimited Pins" (port of the iOS TelegramCore file of the same name).
//
// The switch raises the client-side pin limit to 1000. The server keeps only `dialogs_pinned_limit`
// pins and overwrites the local list on every sync, so the pins past that limit are remembered here
// and put back by the sync paths (Holes, ResetState, ManagedSynchronizePinnedChatsOperations).
//
// Pinned lists are newest-first (`itemIds.insert(itemId, at: 0)`) and the server keeps the head,
// so the device-local pins are always the tail.
//
// Scope: `.group` locations only (main list and archive), keyed per account, nothing kept while the
// switch is off. Reordering with a drag does not update the store (same as iOS).
public enum NovagramLocalPins {
    private static let suiteName = "pro_messager"
    private static let enabledKey = "unlimited_pins"
    private static let maxPins = 1000

    public static var isEnabled: Bool {
        return UserDefaults(suiteName: suiteName)?.bool(forKey: enabledKey) ?? false
    }

    private static func key(accountPeerId: PeerId, groupId: PeerGroupId) -> String {
        return "unlimited_pins_local_\(accountPeerId.toInt64())_\(groupId.rawValue)"
    }

    static func pinLimit(serverLimit: Int) -> Int {
        return isEnabled ? maxPins : serverLimit
    }

    // The pins that live only on this device, in display order (below the synced ones).
    public static func overflowPeerIds(accountPeerId: PeerId, groupId: PeerGroupId) -> [PeerId] {
        guard isEnabled, let defaults = UserDefaults(suiteName: suiteName) else {
            return []
        }
        guard let raw = defaults.array(forKey: key(accountPeerId: accountPeerId, groupId: groupId)) as? [NSNumber] else {
            return []
        }
        return raw.map { PeerId($0.int64Value) }
    }

    public static func setOverflowPeerIds(_ peerIds: [PeerId], accountPeerId: PeerId, groupId: PeerGroupId) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }
        let storeKey = key(accountPeerId: accountPeerId, groupId: groupId)
        if peerIds.isEmpty {
            defaults.removeObject(forKey: storeKey)
        } else {
            defaults.set(peerIds.map { NSNumber(value: $0.toInt64()) }, forKey: storeKey)
        }
    }

    public static func removePeerId(_ peerId: PeerId, accountPeerId: PeerId, groupId: PeerGroupId) {
        let current = overflowPeerIds(accountPeerId: accountPeerId, groupId: groupId)
        guard current.contains(peerId) else {
            return
        }
        setOverflowPeerIds(current.filter { $0 != peerId }, accountPeerId: accountPeerId, groupId: groupId)
    }

    // TogglePeerChatPinned: after a pin or unpin, everything past the server limit is the local tail.
    static func recordOverflow(itemIds: [PinnedItemId], serverLimit: Int, toggled itemId: PinnedItemId, accountPeerId: PeerId, groupId: PeerGroupId) {
        if isEnabled {
            var overflow: [PeerId] = []
            if itemIds.count > serverLimit {
                for item in itemIds[serverLimit...] {
                    if case let .peer(peerId) = item {
                        overflow.append(peerId)
                    }
                }
            }
            setOverflowPeerIds(overflow, accountPeerId: accountPeerId, groupId: groupId)
        } else if case let .peer(peerId) = itemId {
            removePeerId(peerId, accountPeerId: accountPeerId, groupId: groupId)
        }
    }

    public static func clearAll(accountPeerId: PeerId) {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }
        let prefix = "unlimited_pins_local_\(accountPeerId.toInt64())_"
        for storeKey in defaults.dictionaryRepresentation().keys where storeKey.hasPrefix(prefix) {
            defaults.removeObject(forKey: storeKey)
        }
    }

    public static func clearAllAccounts() {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return
        }
        for storeKey in defaults.dictionaryRepresentation().keys where storeKey.hasPrefix("unlimited_pins_local_") {
            defaults.removeObject(forKey: storeKey)
        }
    }

    // Puts the device-local pins back into a list the server just sent. Ids already present are left
    // alone, so the order is kept and nothing is duplicated.
    public static func merged(serverItemIds: [PinnedItemId], accountPeerId: PeerId, groupId: PeerGroupId) -> [PinnedItemId] {
        let overflow = overflowPeerIds(accountPeerId: accountPeerId, groupId: groupId)
        guard !overflow.isEmpty else {
            return serverItemIds
        }
        var existing = Set<PeerId>()
        for item in serverItemIds {
            if case let .peer(peerId) = item {
                existing.insert(peerId)
            }
        }
        var result = serverItemIds
        for peerId in overflow where !existing.contains(peerId) {
            result.append(.peer(peerId))
        }
        return result
    }
}

// Turning the switch off unpins exactly the ids this feature added (read back from the store), then
// forgets them. Clearing the store alone would leave those chats pinned in Postbox.
func _internal_novagramTrimPinnedChatsToServerLimit(postbox: Postbox, accountPeerId: PeerId) -> Signal<Never, NoError> {
    return postbox.transaction { transaction -> Void in
        for groupId in [PeerGroupId.root, Namespaces.PeerGroup.archive] {
            // Read the store directly: `overflowPeerIds` is empty once the switch is off.
            guard let defaults = UserDefaults(suiteName: "pro_messager"),
                  let raw = defaults.array(forKey: "unlimited_pins_local_\(accountPeerId.toInt64())_\(groupId.rawValue)") as? [NSNumber],
                  !raw.isEmpty
            else {
                continue
            }
            let overflow = Set(raw.map { PeerId($0.int64Value) })
            let itemIds = transaction.getPinnedItemIds(groupId: groupId)
            let remaining = itemIds.filter { item in
                if case let .peer(peerId) = item {
                    return !overflow.contains(peerId)
                }
                return true
            }
            guard remaining.count != itemIds.count else {
                continue
            }
            // The sync operation snapshots the current list first, as TogglePeerChatPinned does.
            addSynchronizePinnedChatsOperation(transaction: transaction, groupId: groupId)
            transaction.setPinnedItemIds(groupId: groupId, itemIds: remaining)
        }
        NovagramLocalPins.clearAll(accountPeerId: accountPeerId)
    }
    |> ignoreValues
}

public func novagramTrimPinnedChatsToServerLimit(account: Account) -> Signal<Never, NoError> {
    return _internal_novagramTrimPinnedChatsToServerLimit(postbox: account.postbox, accountPeerId: account.peerId)
}
