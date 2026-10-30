import Cocoa
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramContext
import UserNotifications
import NovagramCore
import NovagramSearchKit

private struct NovagramJobAlertRequest {
    let source: NovagramJobSource
    var emptyMeansFailed: Bool
    let signal: Signal<(SearchMessagesResult, SearchMessagesState), NoError>
}

private struct NovagramJobAlertPage {
    let recordId: Int64
    let load: (String) -> Void
}

struct NovagramJobAlertOutcome {
    let search: NovagramJobSavedSearch
    let items: [NovagramJobResult]
    let isComplete: Bool
}

public final class NovagramJobAlertMonitor {
    public static let shared = NovagramJobAlertMonitor()
    private static let firstCheckDelay: Double = 2 * 60
    private static let checkInterval: Double = 30 * 60
    private static let searchesPerRun = 5
    private static let watchedChannelLimit = 10
    private static let searchIdKey = "novagram_job_search"
    private static let accountKey = "novagram_job_account"

    private var context: (any AccountContextProtocol)?
    private var timer: SwiftSignalKit.Timer?
    private let checkDisposable = MetaDisposable()
    private var lastChecked: [String: Double] = [:]
    private var pages: [Int: NovagramJobAlertPage] = [:]
    private var nextPageToken = 0
    private var unseen: [Int64: Int] = [:]
    private let unseenPromise = ValuePromise<[Int64: Int]>([:], ignoreRepeated: true)

    public func start(context: any AccountContextProtocol) {
        reset()
        self.context = context
        schedule(after: NovagramJobAlertMonitor.firstCheckDelay)
    }

    public func stop(context: any AccountContextProtocol) {
        guard let current = self.context, (current as AnyObject) === (context as AnyObject) else {
            return
        }
        reset()
    }

    private func reset() {
        timer?.invalidate()
        timer = nil
        checkDisposable.set(nil)
        context = nil
    }

    public func unseenCount(account: NovagramJobAccount) -> Signal<Int, NoError> {
        return unseenPromise.get() |> map { $0[account.recordId] ?? 0 } |> distinctUntilChanged
    }

    public func markSeen(account: NovagramJobAccount) {
        Queue.mainQueue().async {
            self.unseen[account.recordId] = nil
            self.unseenPromise.set(self.unseen)
        }
    }

    public func clearUnseen(accountRecordId: Int64) {
        Queue.mainQueue().async {
            self.unseen[accountRecordId] = nil
            self.unseenPromise.set(self.unseen)
        }
    }

    func pageDidAppear(account: NovagramJobAccount, load: @escaping (String) -> Void) -> Int {
        nextPageToken += 1
        pages[nextPageToken] = NovagramJobAlertPage(recordId: account.recordId, load: load)
        return nextPageToken
    }

    func pageDidDisappear(token: Int) {
        pages[token] = nil
    }

    public func handleNotificationClick(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let searchId = userInfo[NovagramJobAlertMonitor.searchIdKey] as? String else {
            return false
        }
        guard NovagramJobSearchAvailability.isEnabled else {
            return true
        }
        guard let context, (userInfo[NovagramJobAlertMonitor.accountKey] as? Int64) == context.peerId.toInt64() else {
            return true
        }
        NSApp.activate(ignoringOtherApps: true)
        let recordId = context.account.id.int64
        if let token = pages.keys.filter({ pages[$0]?.recordId == recordId }).max(), let page = pages[token] {
            page.load(searchId)
        } else {
            NovagramHooks.shared.openJobSearch(context, searchId)
        }
        return true
    }

    private func schedule(after delay: Double) {
        timer?.invalidate()
        let timer = SwiftSignalKit.Timer(timeout: delay, repeat: false, completion: { [weak self] in
            self?.check()
        }, queue: .mainQueue())
        self.timer = timer
        timer.start()
    }

    private func check() {
        guard let context else {
            return
        }
        schedule(after: NovagramJobAlertMonitor.checkInterval)
        guard NovagramJobSearchAvailability.isEnabled, pages.isEmpty else {
            return
        }
        let account = NovagramJobSearchEngine.account(context)
        let searches = NovagramJobStore.savedSearches(account: account).filter { $0.alertsEnabled }.sorted { lhs, rhs in
            let lhsChecked = lastChecked[lhs.id] ?? 0
            let rhsChecked = lastChecked[rhs.id] ?? 0
            if lhsChecked != rhsChecked {
                return lhsChecked < rhsChecked
            }
            return lhs.lastSeenDate < rhs.lastSeenDate
        }.prefix(NovagramJobAlertMonitor.searchesPerRun)
        guard !searches.isEmpty else {
            return
        }
        let now = Date().timeIntervalSince1970
        for search in searches {
            lastChecked[search.id] = now
        }
        let watched = Array(NovagramJobStore.watchedChannels(account: account).prefix(NovagramJobAlertMonitor.watchedChannelLimit))
        checkDisposable.set((NovagramJobAlertMonitor.fetch(context: context, searches: Array(searches), watched: watched) |> deliverOnMainQueue).start(next: { [weak self] outcomes in
            self?.deliver(outcomes, account: account)
        }))
    }

    private func deliver(_ outcomes: [NovagramJobAlertOutcome], account: NovagramJobAccount) {
        guard NovagramJobSearchAvailability.isEnabled, pages.isEmpty else {
            return
        }
        for outcome in outcomes where outcome.isComplete && !outcome.items.isEmpty {
            guard var current = NovagramJobStore.savedSearches(account: account).first(where: { $0.id == outcome.search.id }), current.alertsEnabled else {
                continue
            }
            let newest = outcome.items.map { $0.message.timestamp }.max() ?? 0
            let fresh = outcome.items.filter { $0.message.timestamp > current.lastSeenDate }
            guard !fresh.isEmpty else {
                continue
            }
            current.lastSeenDate = max(current.lastSeenDate, newest)
            NovagramJobStore.save(current, account: account)
            unseen[account.recordId, default: 0] += fresh.count
            notify(count: fresh.count, search: current, account: account)
        }
        unseenPromise.set(unseen)
    }

    private func notify(count: Int, search: NovagramJobSavedSearch, account: NovagramJobAccount) {
        guard #available(macOS 10.14, *) else {
            return
        }
        let strings = NovagramL10n.current
        let content = UNMutableNotificationContent()
        content.title = strings.jobSearch_title
        content.body = strings.jobSearch_alertBody(count, search.title)
        content.sound = .default
        content.userInfo = [NovagramJobAlertMonitor.searchIdKey: search.id, NovagramJobAlertMonitor.accountKey: account.peerId]
        let request = UNNotificationRequest(identifier: "novagram_job_\(search.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private static func requestKeys(for search: NovagramJobSavedSearch, query: NovagramSearchQuery, watched: [Int64]) -> [(key: String, source: NovagramJobSource, text: String, preset: Bool)] {
        var keys: [(key: String, source: NovagramJobSource, text: String, preset: Bool)] = []
        let presetTags = Set(NovagramJobSearchEngine.cleanHashtags(NovagramJobPresets.hashtags(for: search.filter.mode)).map { $0.lowercased() })
        let presets = NovagramJobSearchEngine.cleanHashtags(NovagramJobSearchEngine.runHashtags(search.filter))
        for tag in presets {
            keys.append(("h:" + tag.lowercased(), .hashtags, tag, presetTags.contains(tag.lowercased())))
        }
        for tag in NovagramJobSearchEngine.cleanHashtags(query.hashtagTerms) where !presets.contains(where: { $0.lowercased() == tag.lowercased() }) {
            keys.append(("h:" + tag.lowercased(), .hashtags, tag, false))
        }
        let texts = query.serverQueries.isEmpty ? NovagramJobSearchEngine.presetKeywords(for: search.filter.mode) : query.serverQueries
        for text in texts {
            keys.append(("c:" + text, .myChats, text, false))
        }
        for channel in watched {
            keys.append(("w:\(channel)", .watched, "", false))
        }
        return keys
    }

    static func fetch(context: any AccountContextProtocol, searches: [NovagramJobSavedSearch], watched: [Int64]) -> Signal<[NovagramJobAlertOutcome], NoError> {
        let querySignals = searches.map { search -> Signal<(String, NovagramSearchQuery), NoError> in
            let filter = search.filter
            let needed = NovagramSearchConversion.plan(query: filter.query, languages: filter.languages).translationsNeeded
            guard !needed.isEmpty else {
                return .single((search.id, NovagramSearchQuery.parse(filter.query, languages: filter.languages, translations: [:])))
            }
            return NovagramJobTranslations.fetch(engine: context.engine, query: filter.query, needed: needed) |> map { translations in
                (search.id, NovagramSearchQuery.parse(filter.query, languages: filter.languages, translations: translations))
            }
        }
        return combineLatest(querySignals) |> mapToSignal { pairs -> Signal<[NovagramJobAlertOutcome], NoError> in
            let queries = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
            return fetchPosts(context: context, searches: searches, watched: watched, queries: queries)
        }
    }

    private static func fetchPosts(context: any AccountContextProtocol, searches: [NovagramJobSavedSearch], watched: [Int64], queries: [String: NovagramSearchQuery]) -> Signal<[NovagramJobAlertOutcome], NoError> {
        let engine = context.engine
        let now = NovagramJobSearchEngine.now()
        let floor = searches.map { max($0.lastSeenDate, $0.filter.period.minDate(now: now) ?? 0) }.min() ?? 0
        let minDate: Int32? = floor > 0 ? floor : nil
        let limit = NovagramJobSearchEngine.pageLimit
        var requests: [String: NovagramJobAlertRequest] = [:]
        var keysBySearch: [String: [String]] = [:]
        for search in searches {
            let keys = requestKeys(for: search, query: queries[search.id] ?? NovagramSearchQuery.parse(search.filter.query), watched: watched)
            keysBySearch[search.id] = keys.map { $0.key }
            for item in keys {
                if var existing = requests[item.key] {
                    existing.emptyMeansFailed = existing.emptyMeansFailed || item.preset
                    requests[item.key] = existing
                    continue
                }
                let signal: Signal<(SearchMessagesResult, SearchMessagesState), NoError>
                switch item.source {
                case .hashtags:
                    signal = engine.messages.searchHashtagPosts(hashtag: item.text, state: nil, limit: limit)
                case .watched:
                    let peerId = PeerId(Int64(item.key.dropFirst(2)) ?? 0)
                    signal = engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: minDate, maxDate: nil), query: "", state: nil, limit: limit)
                default:
                    signal = engine.messages.searchMessages(location: .general(scope: .everywhere, groupId: nil, tags: nil, minDate: minDate, maxDate: nil, folderId: nil, communityId: nil), query: item.text, state: nil, limit: limit)
                }
                requests[item.key] = NovagramJobAlertRequest(source: item.source, emptyMeansFailed: item.preset, signal: signal)
            }
        }
        let keys = Array(requests.keys)
        guard !keys.isEmpty else {
            return .single(searches.map { NovagramJobAlertOutcome(search: $0, items: [], isComplete: true) })
        }
        let signals = keys.map { key -> Signal<[Message]?, NoError> in
            let request = requests[key]
            let limited = NovagramJobRequestLimiter.shared.limited((request?.signal ?? .complete()) |> take(1))
            return (limited |> map { result -> [Message]? in
                if request?.emptyMeansFailed == true && result.0.messages.isEmpty {
                    return nil
                }
                return result.0.messages
            } |> then(.single(nil))) |> take(1)
        }
        return combineLatest(signals) |> deliverOn(Queue.concurrentDefaultQueue()) |> map { results -> [NovagramJobAlertOutcome] in
            var messagesByKey: [String: [Message]] = [:]
            var failed = Set<String>()
            for (key, messages) in zip(keys, results) {
                if let messages {
                    messagesByKey[key] = NovagramSearchPrivacy.kept(messages, message: { $0 })
                } else {
                    failed.insert(key)
                }
            }
            var parsed: [MessageId: NovagramJobResult] = [:]
            return searches.map { search in
                let searchKeys = keysBySearch[search.id] ?? []
                guard !searchKeys.contains(where: failed.contains) else {
                    return NovagramJobAlertOutcome(search: search, items: [], isComplete: false)
                }
                let query = queries[search.id] ?? NovagramSearchQuery.parse(search.filter.query)
                var seen = Set<MessageId>()
                var items: [NovagramJobResult] = []
                for key in searchKeys {
                    let source = requests[key]?.source ?? .myChats
                    for message in messagesByKey[key] ?? [] where message.timestamp > search.lastSeenDate && !message.text.isEmpty && !novagramJobIsSpam(message, text: message.text) && seen.insert(message.id).inserted {
                        let result = parsed[message.id] ?? NovagramJobResult(message: message, text: message.text, info: NovagramJobPostParser.parse(message.text), source: source)
                        parsed[message.id] = result
                        if search.filter.accepts(text: result.text, info: result.info, date: message.timestamp, now: now, query: query) {
                            items.append(result)
                        }
                    }
                }
                return NovagramJobAlertOutcome(search: search, items: items, isComplete: true)
            }
        }
    }
}
