import Foundation

public enum NovagramJobStore {
    public static let didChangeNotification = Notification.Name("NovagramJobStoreDidChange")

    static let suiteName = "pro_messager"
    static let keyPrefix = "novagram_job_search_"
    static let maxSavedSearches = 20
    static let maxWatchedChannels = 30

    static var defaults: UserDefaults = UserDefaults(suiteName: suiteName) ?? .standard

    private static let lock = NSLock()

    struct Record: Codable {
        var accountRecordId: Int64
        var savedSearches: [NovagramJobSavedSearch] = []
        var watchedChannels: [Int64] = []
        var lastFilter: NovagramJobFilter?

        init(accountRecordId: Int64) {
            self.accountRecordId = accountRecordId
        }
    }

    static func key(for account: NovagramJobAccount) -> String {
        return keyPrefix + String(account.peerId)
    }

    private static func load(_ key: String) -> Record? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private static func read<T>(_ account: NovagramJobAccount, _ body: (Record) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(load(key(for: account)) ?? Record(accountRecordId: account.recordId))
    }

    private static func update(_ account: NovagramJobAccount, _ body: (inout Record) -> Void) {
        lock.lock()
        let key = key(for: account)
        var record = load(key) ?? Record(accountRecordId: account.recordId)
        record.accountRecordId = account.recordId
        body(&record)
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: key)
        }
        lock.unlock()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    public static func savedSearches(account: NovagramJobAccount) -> [NovagramJobSavedSearch] {
        return read(account) { $0.savedSearches }
    }

    public static func save(_ search: NovagramJobSavedSearch, account: NovagramJobAccount) {
        update(account) { record in
            if let index = record.savedSearches.firstIndex(where: { $0.id == search.id }) {
                record.savedSearches[index] = search
            } else {
                record.savedSearches.insert(search, at: 0)
            }
            record.savedSearches = Array(record.savedSearches.prefix(maxSavedSearches))
        }
    }

    public static func remove(id: String, account: NovagramJobAccount) {
        update(account) { record in
            record.savedSearches.removeAll(where: { $0.id == id })
        }
    }

    public static func watchedChannels(account: NovagramJobAccount) -> [Int64] {
        return read(account) { $0.watchedChannels }
    }

    public static func setWatched(_ peerId: Int64, watched: Bool, account: NovagramJobAccount) {
        update(account) { record in
            record.watchedChannels.removeAll(where: { $0 == peerId })
            if watched {
                record.watchedChannels.insert(peerId, at: 0)
            }
            record.watchedChannels = Array(record.watchedChannels.prefix(maxWatchedChannels))
        }
    }

    public static func lastFilter(account: NovagramJobAccount) -> NovagramJobFilter? {
        return read(account) { $0.lastFilter }
    }

    public static func setLastFilter(_ filter: NovagramJobFilter, account: NovagramJobAccount) {
        update(account) { record in
            record.lastFilter = filter
        }
    }

    public static func clear(accountRecordId: Int64) {
        lock.lock()
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(keyPrefix) }
        var removed = false
        for key in keys where load(key)?.accountRecordId == accountRecordId {
            defaults.removeObject(forKey: key)
            removed = true
        }
        lock.unlock()
        if removed {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }
}
