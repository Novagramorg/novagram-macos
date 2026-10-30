import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext
import NovagramSearchKit

public struct NovagramArchiveHit: Equatable {
    public let key: String
    public let chatPeerId: PeerId
    public let messageId: Int32
    public let isDeleted: Bool
    public let eventDate: Int32
    public let date: Int32
    public let text: String
}

public final class NovagramArchiveSearchSession {
    fileprivate let pages = ValuePromise<Int>(1, ignoreRepeated: true)
    private let lock = NSLock()
    private var requestedPages = 1
    fileprivate var records: [NovagramArchivedMessage] = []
    fileprivate var cursor: NovagramArchiveSearchCursor?
    fileprivate var loadedPages = 0
    fileprivate var isFinished = false

    public func loadMore() {
        lock.lock()
        requestedPages += 1
        let value = requestedPages
        lock.unlock()
        pages.set(value)
    }
}

public struct NovagramArchiveSearchResults: Equatable {
    public let hits: [NovagramArchiveHit]
    public let query: String
    public let session: NovagramArchiveSearchSession?

    public static let empty = NovagramArchiveSearchResults(hits: [], query: "", session: nil)

    public static func == (lhs: NovagramArchiveSearchResults, rhs: NovagramArchiveSearchResults) -> Bool {
        return lhs.hits == rhs.hits && lhs.query == rhs.query && lhs.session === rhs.session
    }
}

struct NovagramArchiveEdit {
    let message: Message
    let previousText: String
    let editDate: Int32
}

public final class NovagramMessageArchive {
    public static let shared = NovagramMessageArchive()
    public static let minQueryLength = 2
    public static let pageSize = 20
    public static let maxPages = 50

    private static let suiteName = "pro_messager"
    private static let deletedKey = "show_deleted_messages"
    private static let editedKey = "edited_history_enabled"
    private static let migratedKey = "novagram_archive_migrated_v1"
    private static let debounceSeconds: Double = 0.25

    private let queue = Queue(name: "uz.novagram.messageArchive", qos: .utility)
    private let lock = NSLock()
    private var store: NovagramMessageArchiveStore?
    private var indexes: [Int64: NovagramArchiveIndex] = [:]
    private var lastRecords: [Int64: [NovagramArchivedMessage]] = [:]
    private var migrationStarted = false
    private let migrationDisposable = MetaDisposable()

    private init() {}

    public static var isDeletedEnabled: Bool {
        return UserDefaults(suiteName: suiteName)?.bool(forKey: deletedKey) ?? false
    }

    public static var isEditedEnabled: Bool {
        return UserDefaults(suiteName: suiteName)?.object(forKey: editedKey) as? Bool ?? true
    }

    private static var kinds: NovagramArchiveKinds {
        var kinds: NovagramArchiveKinds = []
        if isEditedEnabled {
            kinds.insert(.edited)
        }
        if isDeletedEnabled {
            kinds.insert(.deleted)
        }
        return kinds
    }

    public func configure(directory: URL) {
        queue.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            self.store = NovagramMessageArchiveStore(directory: directory)
            self.indexes.removeAll()
        }
    }

    func recordDeleted(_ messages: [Message], account: Account) {
        guard NovagramMessageArchive.isDeletedEnabled else {
            return
        }
        let deletedAt = NovagramMessageArchive.now()
        let records = messages.compactMap { message in
            NovagramMessageArchive.record(message, account: account, kind: .deleted(deletedAt: deletedAt), text: message.text)
        }
        save(records, accountRecordId: account.id.int64)
    }

    func recordEdited(_ edits: [NovagramArchiveEdit], account: Account) {
        guard NovagramMessageArchive.isEditedEnabled else {
            return
        }
        let records = edits.compactMap { edit in
            NovagramMessageArchive.record(edit.message, account: account, kind: .edited(editDate: edit.editDate), text: edit.previousText)
        }
        save(records, accountRecordId: account.id.int64)
    }

    public func clear(accountRecordId: Int64) {
        setLastRecords([], accountRecordId: accountRecordId)
        queue.async {
            self.store?.clear(accountRecordId: accountRecordId)
            self.indexes[accountRecordId] = nil
        }
    }

    public func search(accountRecordId: Int64, query rawQuery: String) -> Signal<NovagramArchiveSearchResults, NoError> {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let kinds = NovagramMessageArchive.kinds
        guard query.count >= NovagramMessageArchive.minQueryLength, !kinds.isEmpty else {
            setLastRecords([], accountRecordId: accountRecordId)
            return .single(.empty)
        }
        let immediate = quickResults(accountRecordId: accountRecordId, query: query, kinds: kinds)
        let session = NovagramArchiveSearchSession()
        let queue = self.queue
        let full: Signal<NovagramArchiveSearchResults, NoError> = Signal<Void, NoError>.single(Void())
            |> delay(NovagramMessageArchive.debounceSeconds, queue: queue)
            |> mapToSignal { _ in session.pages.get() }
            |> deliverOn(queue)
            |> map { [weak self] pages -> NovagramArchiveSearchResults in
                guard let self else {
                    return .empty
                }
                return self.fill(session, pages: pages, accountRecordId: accountRecordId, query: query, kinds: kinds)
            }
        return .single(immediate) |> then(full)
    }

    public func migrateLegacyIfNeeded(sharedContext: any SharedAccountContextProtocol, currentAccount: Account) {
        lock.lock()
        let started = migrationStarted
        migrationStarted = true
        lock.unlock()
        guard !started else {
            return
        }
        queue.async {
            guard let store = self.store else {
                return
            }
            let marker = store.directory.standardizedFileURL.path
            guard !NovagramMessageArchive.migratedFolders().contains(marker) else {
                return
            }
            let legacy = UserDefaults(suiteName: NovagramArchiveMacLegacyImport.suiteName)?.dictionaryRepresentation() ?? [:]
            let chatIds = Set(NovagramArchiveMacLegacyImport.records(from: legacy, accountPeerId: 0, accountRecordId: 0).map { $0.chatPeerId })
            guard !chatIds.isEmpty else {
                NovagramMessageArchive.markMigrated(marker)
                return
            }
            let signal = sharedContext.activeAccountsWithInfo
                |> take(1)
                |> mapToSignal { _, accounts -> Signal<[(Account, [Int64: Int])], NoError> in
                    var ordered = [currentAccount]
                    ordered += accounts.map { $0.account }.filter { $0.id != currentAccount.id }
                    return combineLatest(ordered.map { NovagramMessageArchive.chatScores(chatIds, account: $0) })
                }
                |> deliverOn(self.queue)
            self.migrationDisposable.set(signal.start(next: { scores in
                self.importLegacy(legacy, scores: scores, currentAccount: currentAccount, marker: marker)
            }))
        }
    }

    private func importLegacy(_ legacy: [String: Any], scores: [(Account, [Int64: Int])], currentAccount: Account, marker: String) {
        guard let store = store else {
            return
        }
        var owners: [Int64: AccountRecordId] = [:]
        var best: [Int64: Int] = [:]
        for (account, accountScores) in scores {
            for (chatId, score) in accountScores where score > (best[chatId] ?? 0) {
                best[chatId] = score
                owners[chatId] = account.id
            }
        }
        var records: [NovagramArchivedMessage] = []
        for (account, _) in scores {
            let isCurrent = account.id == currentAccount.id
            records += NovagramArchiveMacLegacyImport.records(from: legacy, accountPeerId: account.peerId.toInt64(), accountRecordId: account.id.int64, includeChat: { chatId in
                guard PeerId(chatId).namespace != Namespaces.Peer.SecretChat else {
                    return false
                }
                if let owner = owners[chatId] {
                    return owner == account.id
                }
                return isCurrent
            })
        }
        store.save(records)
        indexes.removeAll()
        NovagramMessageArchive.markMigrated(marker)
    }

    private static func chatScores(_ chatIds: Set<Int64>, account: Account) -> Signal<(Account, [Int64: Int]), NoError> {
        return account.postbox.transaction { transaction -> (Account, [Int64: Int]) in
            var scores: [Int64: Int] = [:]
            for chatId in chatIds {
                let peerId = PeerId(chatId)
                if transaction.getPeerChatListIndex(peerId) != nil {
                    scores[chatId] = 2
                } else if transaction.getPeer(peerId) != nil {
                    scores[chatId] = 1
                }
            }
            return (account, scores)
        }
    }

    private static func migratedFolders() -> [String] {
        return UserDefaults(suiteName: suiteName)?.stringArray(forKey: migratedKey) ?? []
    }

    private static func markMigrated(_ marker: String) {
        let defaults = UserDefaults(suiteName: suiteName)
        var folders = migratedFolders()
        if !folders.contains(marker) {
            folders.append(marker)
        }
        defaults?.set(folders, forKey: migratedKey)
    }

    private func save(_ records: [NovagramArchivedMessage], accountRecordId: Int64) {
        guard !records.isEmpty else {
            return
        }
        queue.async {
            guard let store = self.store, store.save(records) > 0 else {
                return
            }
            self.indexes[accountRecordId] = nil
        }
    }

    private func index(accountRecordId: Int64) -> NovagramArchiveIndex {
        if let cached = indexes[accountRecordId] {
            return cached
        }
        let index = store?.index(accountRecordId: accountRecordId) ?? NovagramArchiveIndex(records: [])
        indexes[accountRecordId] = index
        return index
    }

    private func fill(_ session: NovagramArchiveSearchSession, pages: Int, accountRecordId: Int64, query: String, kinds: NovagramArchiveKinds) -> NovagramArchiveSearchResults {
        let target = min(pages, NovagramMessageArchive.maxPages)
        if session.loadedPages < target, !session.isFinished {
            let index = self.index(accountRecordId: accountRecordId)
            let isExcluded = NovagramMessageArchive.exclusion()
            while session.loadedPages < target, !session.isFinished {
                let request = NovagramArchiveSearchRequest(rawQuery: query, kinds: kinds, accountRecordId: accountRecordId, limit: NovagramMessageArchive.pageSize, cursor: session.cursor)
                let page = NovagramArchiveSearch.search(request, in: index, isChatExcluded: isExcluded)
                session.records += page.records
                session.cursor = page.nextCursor
                session.loadedPages += 1
                session.isFinished = page.nextCursor == nil
            }
        }
        setLastRecords(session.records, accountRecordId: accountRecordId)
        let hasMore = !session.isFinished && session.loadedPages < NovagramMessageArchive.maxPages
        return NovagramArchiveSearchResults(hits: session.records.map(NovagramMessageArchive.hit), query: query, session: hasMore ? session : nil)
    }

    private func quickResults(accountRecordId: Int64, query: String, kinds: NovagramArchiveKinds) -> NovagramArchiveSearchResults {
        lock.lock()
        let previous = lastRecords[accountRecordId] ?? []
        lock.unlock()
        guard !previous.isEmpty else {
            return .empty
        }
        let request = NovagramArchiveSearchRequest(rawQuery: query, kinds: kinds, accountRecordId: accountRecordId, limit: NovagramMessageArchive.pageSize)
        let page = NovagramArchiveSearch.search(request, in: previous, isChatExcluded: NovagramMessageArchive.exclusion())
        return NovagramArchiveSearchResults(hits: page.records.map(NovagramMessageArchive.hit), query: query, session: nil)
    }

    private func setLastRecords(_ records: [NovagramArchivedMessage], accountRecordId: Int64) {
        lock.lock()
        lastRecords[accountRecordId] = records
        lock.unlock()
    }

    private static func exclusion() -> (Int64) -> Bool {
        let privacy = NovagramSearchPrivacyPass()
        return { chatId in
            let peerId = PeerId(chatId)
            if NovagramHiddenChatsManager.shared.isPeerHiddenInStorage(peerId) {
                return true
            }
            return privacy.isLocked(peerId)
        }
    }

    private static func hit(_ record: NovagramArchivedMessage) -> NovagramArchiveHit {
        let kind = record.kind.isDeleted ? "d" : "e"
        let key = "\(kind)_\(record.chatPeerId)_\(record.messageId)_\(record.kind.eventDate)_\(record.text.hashValue)"
        return NovagramArchiveHit(key: key, chatPeerId: PeerId(record.chatPeerId), messageId: record.messageId, isDeleted: record.kind.isDeleted, eventDate: record.kind.eventDate, date: record.date, text: record.text)
    }

    private static func record(_ message: Message, account: Account, kind: NovagramArchivedMessageKind, text: String) -> NovagramArchivedMessage? {
        guard message.id.peerId.namespace != Namespaces.Peer.SecretChat, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return NovagramArchivedMessage(
            accountPeerId: account.peerId.toInt64(),
            accountRecordId: account.id.int64,
            chatPeerId: message.id.peerId.toInt64(),
            messageId: message.id.id,
            threadId: message.threadId,
            authorPeerId: message.author?.id.toInt64(),
            date: message.timestamp,
            kind: kind,
            text: text
        )
    }

    private static func now() -> Int32 {
        return Int32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970))
    }
}
