import Foundation
import CoreSpotlight
import Postbox
import TelegramCore
import SwiftSignalKit

// Spotlight: every contact of an account, found by name or @username. Opening a result shows the
// profile (app target: novagramContinueSpotlight). Hidden chats and chats under chat lock are never
// indexed, and Telegram's own recent-peer items for hidden chats are removed.
public final class NovagramSpotlightContacts {
    public static let identifierPrefix = "novagram-profile:"

    private let account: Account
    private let domain: String
    private let queue = Queue(name: "NovagramSpotlightContacts")
    private let disposable = MetaDisposable()
    private var settingsObserver: NSObjectProtocol?
    // peerId → what was indexed (name, username, photo), so unchanged contacts are not sent again.
    private var indexed: [PeerId: String] = [:]

    public init(account: Account) {
        self.account = account
        self.domain = "novagram.contacts.\(account.id.int64)"

        let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
        var revision = 0
        self.settingsObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name("NovagramSettingsChanged"), object: nil, queue: .main, using: { _ in
            revision += 1
            refresh.set(revision)
        })

        let contacts = TelegramEngine(account: account).data.subscribe(TelegramEngine.EngineData.Item.Contacts.List(includePresences: false))
        self.disposable.set((combineLatest(contacts, refresh.get()) |> deliverOn(self.queue)).start(next: { [weak self] list, _ in
            self?.update(list.peers)
        }))
    }

    deinit {
        disposable.dispose()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain], completionHandler: nil)
    }

    public static func isExcluded(_ peerId: PeerId) -> Bool {
        if NovagramHiddenChatsManager.shared.isPeerHiddenInStorage(peerId) {
            return true
        }
        return NovagramChatPincodeManager.shared.isMasterEnabled() && NovagramChatPincodeManager.shared.isLocked(peerId)
    }

    public static func identifier(accountId: AccountRecordId, peerId: PeerId) -> String {
        return "\(identifierPrefix)\(accountId.int64):\(peerId.toInt64())"
    }

    // "novagram-profile:<accountId>:<peerId>" → ids, nil for any other identifier.
    public static func parse(_ identifier: String) -> (AccountRecordId, PeerId)? {
        guard identifier.hasPrefix(identifierPrefix) else {
            return nil
        }
        let parts = identifier.dropFirst(identifierPrefix.count).split(separator: ":")
        guard parts.count == 2, let accountId = Int64(parts[0]), let peerId = Int64(parts[1]) else {
            return nil
        }
        return (AccountRecordId(rawValue: accountId), PeerId(peerId))
    }

    private func update(_ peers: [EnginePeer]) {
        var items: [CSSearchableItem] = []
        var current: [PeerId: String] = [:]
        for peer in peers {
            guard case let .user(user) = peer, !NovagramSpotlightContacts.isExcluded(peer.id) else {
                continue
            }
            let name = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            guard !name.isEmpty else {
                continue
            }
            let photoPath = user.smallProfileImage.flatMap { account.postbox.mediaBox.completedResourcePath($0.resource) }
            let signature = "\(name)|\(user.addressName ?? "")|\(photoPath ?? "")"
            current[peer.id] = signature
            if indexed[peer.id] == signature {
                continue
            }
            items.append(makeItem(peerId: peer.id, name: name, user: user, photoPath: photoPath))
        }

        let removed = indexed.keys.filter { current[$0] == nil }.map { NovagramSpotlightContacts.identifier(accountId: account.id, peerId: $0) }
        indexed = current
        if !removed.isEmpty {
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: removed, completionHandler: nil)
        }
        if !items.isEmpty {
            CSSearchableIndex.default().indexSearchableItems(items, completionHandler: nil)
        }

        // Telegram's own Spotlight items (recent chats) use "accountId=<id>&source=peerId:<id>".
        let hiddenTelegramItems = NovagramHiddenChatsManager.shared.hiddenPeerIds.map { "accountId=\(account.id.int64)&source=peerId:\($0.toInt64())" }
        if !hiddenTelegramItems.isEmpty {
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: hiddenTelegramItems, completionHandler: nil)
        }
    }

    private func makeItem(peerId: PeerId, name: String, user: TelegramUser, photoPath: String?) -> CSSearchableItem {
        let attributes: CSSearchableItemAttributeSet
        if #available(macOS 11.0, *) {
            attributes = CSSearchableItemAttributeSet(contentType: .contact)
        } else {
            attributes = CSSearchableItemAttributeSet(itemContentType: "public.contact")
        }
        attributes.title = name
        attributes.displayName = name
        if let username = user.addressName {
            attributes.contentDescription = "@\(username) · Novagram"
            attributes.keywords = [user.firstName, user.lastName, username, "@\(username)"].compactMap { $0 }
        } else {
            attributes.contentDescription = "Novagram"
            attributes.keywords = [user.firstName, user.lastName].compactMap { $0 }
        }
        if let photoPath {
            attributes.thumbnailData = try? Data(contentsOf: URL(fileURLWithPath: photoPath))
        }
        return CSSearchableItem(uniqueIdentifier: NovagramSpotlightContacts.identifier(accountId: account.id, peerId: peerId), domainIdentifier: domain, attributeSet: attributes)
    }
}
