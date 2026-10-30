//
//  NovagramEditedHistoryManager.swift
//  Telegram-Mac
//
//  iOS portasi: submodules/Novagram/EditedHistory/Sources/EditedMessageHistoryController.swift
//
//  iOS uses a TelegramCore message attribute (`EditedMessageHistoryAttribute`) that
//  is NOT present in the shared TelegramCore submodule consumed by Telegram-Mac
//  (the Mac submodule pins a different commit). Patching the upstream
//  TelegramCore submodule for one Novagram feature is high-risk for future pulls,
//  so this Mac port maintains its OWN per-message edit history store keyed by
//  (peerId, messageId) → [Entry].
//
//  Storage: UserDefaults(suiteName: "uz.fenixuz.app.editedHistory"), with the
//  per-key payload being a JSON blob of [{text, timestamp}]. Each entry is
//  recorded the first time we see a message edit for that (peer, msg) pair.
//
//  Consumer wiring (separate file `NovagramEditedHistoryController.swift`):
//    - When the chat-message context menu builds for an edited message, push
//      NovagramEditedHistoryController(messageId:peerId:) onto the navigation.
//    - The recorder (`record(text:peerId:messageId:timestamp:)`) is meant to be
//      called from the chat update pipeline when an edit notification fires.
//      For now, callers can opportunistically record edits whenever they have
//      both the old and new text in scope.

import Foundation
import Postbox
import TelegramCore

public struct NovagramEditedHistoryEntry: Codable, Equatable {
    public let text: String
    public let timestamp: Int32
    // Media of that version (photo, video, file) as a base64 PostboxEncoder blob, like iOS keeps it in
    // EditedMessageHistoryAttribute. nil for versions without media and for entries saved before 2026-10-29.
    public let mediaData: String?

    public init(text: String, timestamp: Int32, mediaData: String? = nil) {
        self.text = text
        self.timestamp = timestamp
        self.mediaData = mediaData
    }

    public var media: [Media] {
        guard let mediaData, let data = Data(base64Encoded: mediaData) else {
            return []
        }
        let objects: [PostboxCoding] = PostboxDecoder(buffer: MemoryBuffer(data: data)).decodeObjectArrayForKey("m")
        return objects.compactMap { $0 as? Media }
    }

    static func encode(_ media: [Media]) -> String? {
        guard !media.isEmpty else {
            return nil
        }
        let encoder = PostboxEncoder()
        encoder.encodeGenericObjectArray(media.map { $0 as PostboxCoding }, forKey: "m")
        return encoder.makeData().base64EncodedString()
    }
}

// What a message looked like the last time the chat showed it.
private struct NovagramSeenVersion {
    let text: String
    let media: [Media]
    let timestamp: Int32

    var mediaIds: [MediaId?] {
        return media.map { $0.id }
    }

    // A photo or file still uploading: its cloud copy replaces it without any user edit.
    var hasLocalMedia: Bool {
        return media.contains(where: { $0.id?.namespace == Namespaces.Media.LocalImage || $0.id?.namespace == Namespaces.Media.LocalFile })
    }
}

public final class NovagramEditedHistoryManager {
    public static let shared = NovagramEditedHistoryManager()

    private let defaults = UserDefaults(suiteName: "uz.fenixuz.app.editedHistory")
    private let lock = NSLock()
    private var lastSeen: [MessageId: NovagramSeenVersion] = [:]

    private init() {}

    // MARK: - Public API

    /// Process a batch of messages to observe and record edits: a changed text or changed media
    /// (iOS records both). The saved version keeps its own time, as on iOS.
    public func processMessages(_ messages: [Message], account: Account? = nil) {
        lock.lock(); defer { lock.unlock() }
        var archived: [NovagramArchiveEdit] = []
        for message in messages {
            let msgId = message.id
            let edited = message.attributes.compactMap({ $0 as? EditedMessageAttribute }).first
            let current = NovagramSeenVersion(text: message.text, media: message.media.filter { !($0 is TelegramMediaWebpage) }, timestamp: edited?.date ?? message.timestamp)
            if let previous = lastSeen[msgId], edited != nil {
                let textChanged = previous.text != current.text
                let mediaChanged = previous.mediaIds != current.mediaIds
                if textChanged || (mediaChanged && !previous.hasLocalMedia) {
                    var existing = loadLocked(peerId: msgId.peerId, messageId: msgId.id)
                    let entry = NovagramEditedHistoryEntry(text: previous.text, timestamp: previous.timestamp, mediaData: NovagramEditedHistoryEntry.encode(previous.media))
                    if !existing.contains(entry) {
                        existing.append(entry)
                        if existing.count > 50 {
                            existing = Array(existing.suffix(50))
                        }
                        saveLocked(existing, peerId: msgId.peerId, messageId: msgId.id)
                        archived.append(NovagramArchiveEdit(message: message, previousText: previous.text, editDate: current.timestamp))
                    }
                }
            }
            lastSeen[msgId] = current
        }
        if let account, !archived.isEmpty {
            NovagramMessageArchive.shared.recordEdited(archived, account: account)
        }
    }

    public func entries(peerId: PeerId, messageId: Int32) -> [NovagramEditedHistoryEntry] {
        lock.lock(); defer { lock.unlock() }
        return loadLocked(peerId: peerId, messageId: messageId)
    }

    /// Append a single entry. Idempotent for the (text + timestamp) pair —
    /// recording the same edit twice does not duplicate.
    public func record(text: String, peerId: PeerId, messageId: Int32, timestamp: Int32) {
        lock.lock(); defer { lock.unlock() }
        var existing = loadLocked(peerId: peerId, messageId: messageId)
        let entry = NovagramEditedHistoryEntry(text: text, timestamp: timestamp)
        if existing.contains(entry) { return }
        existing.append(entry)
        // Cap at 50 entries per message to prevent unbounded growth.
        if existing.count > 50 {
            existing = Array(existing.suffix(50))
        }
        saveLocked(existing, peerId: peerId, messageId: messageId)
    }

    public func clear(peerId: PeerId, messageId: Int32) {
        lock.lock(); defer { lock.unlock() }
        defaults?.removeObject(forKey: key(peerId: peerId, messageId: messageId))
    }

    public func hasHistory(peerId: PeerId, messageId: Int32) -> Bool {
        return !entries(peerId: peerId, messageId: messageId).isEmpty
    }

    // MARK: - Storage helpers

    private func key(peerId: PeerId, messageId: Int32) -> String {
        return "msg_\(peerId.toInt64())_\(messageId)"
    }

    private func loadLocked(peerId: PeerId, messageId: Int32) -> [NovagramEditedHistoryEntry] {
        guard let data = defaults?.data(forKey: key(peerId: peerId, messageId: messageId)) else {
            return []
        }
        return (try? JSONDecoder().decode([NovagramEditedHistoryEntry].self, from: data)) ?? []
    }

    private func saveLocked(_ entries: [NovagramEditedHistoryEntry], peerId: PeerId, messageId: Int32) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults?.set(data, forKey: key(peerId: peerId, messageId: messageId))
    }
}
