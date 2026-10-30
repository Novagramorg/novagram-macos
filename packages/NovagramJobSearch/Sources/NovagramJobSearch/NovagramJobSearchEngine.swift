import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramContext
import NovagramCore
import NovagramSearchKit

public enum NovagramJobSource: String, Hashable {
    case hashtags
    case myChats
    case watched
    case global
}

public struct NovagramJobSources: Equatable {
    public var hashtags: Bool
    public var myChats: Bool
    public var watched: Bool

    public init(hashtags: Bool = true, myChats: Bool = true, watched: Bool = true) {
        self.hashtags = hashtags
        self.myChats = myChats
        self.watched = watched
    }
}

public final class NovagramJobResult: Equatable {
    public let message: Message
    public let text: String
    public let info: NovagramJobPostInfo
    public let source: NovagramJobSource

    init(message: Message, text: String, info: NovagramJobPostInfo, source: NovagramJobSource) {
        self.message = message
        self.text = text
        self.info = info
        self.source = source
    }

    public static func == (lhs: NovagramJobResult, rhs: NovagramJobResult) -> Bool {
        return lhs.message.id == rhs.message.id && lhs.message.stableVersion == rhs.message.stableVersion && lhs.info == rhs.info && lhs.source == rhs.source
    }
}

public struct NovagramJobSearchState: Equatable {
    public var items: [NovagramJobResult] = []
    public var isLoading: Bool = false
    public var canLoadMore: Bool = false
    public var hasRun: Bool = false
    public var failedSources: Set<NovagramJobSource> = []
    public var globalState: TelegramGlobalPostSearchState?
    public var isGlobalLoading: Bool = false

    public init() {}
}

private final class NovagramJobSearchTask {
    let source: NovagramJobSource
    let request: (SearchMessagesState?) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError>
    var pagingState: SearchMessagesState?
    var completed: Bool = false

    init(source: NovagramJobSource, request: @escaping (SearchMessagesState?) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError>) {
        self.source = source
        self.request = request
    }
}

func novagramJobIsSpam(_ message: Message, text: String) -> Bool {
    let peer = message.peers[message.id.peerId]
    return NovagramJobSpamGuard.isSpamSource(title: novagramJobPeerTitle(peer), username: peer.flatMap { EnginePeer($0).addressName }) || NovagramJobSpamGuard.isSpamText(text)
}

public final class NovagramJobSearchEngine {
    public static let maxConcurrentRequests = 6
    private static let debounceDelay: Double = 0.4
    static let maxRunHashtags = 8
    private static let presetKeywordCount = 3
    private static let watchedChannelLimit = 15
    static let pageLimit: Int32 = 50

    private let context: any AccountContextProtocol
    private let account: NovagramJobAccount
    private let queue = Queue()
    private let statePromise = ValuePromise(NovagramJobSearchState(), ignoreRepeated: true)
    private var state = NovagramJobSearchState()
    private var tasks: [NovagramJobSearchTask] = []
    private var pending: [Int] = []
    private var active = 0
    private var isWaiting = false
    private var generation = 0
    private var filter = NovagramJobFilter()
    private var query = NovagramSearchQuery.parse("")
    private var found: [MessageId: NovagramJobResult] = [:]
    private var globalFound: [MessageId: NovagramJobResult] = [:]
    private var remember = true
    private var taskDisposables = DisposableSet()
    private let globalDisposable = MetaDisposable()
    private let translationDisposable = MetaDisposable()
    private let quotaDisposable = MetaDisposable()

    public var stateSignal: Signal<NovagramJobSearchState, NoError> {
        return statePromise.get()
    }

    public init(context: any AccountContextProtocol, observesQuota: Bool = true) {
        self.context = context
        self.account = NovagramJobSearchEngine.account(context)
        guard observesQuota else {
            return
        }
        let queue = self.queue
        quotaDisposable.set((context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.GlobalPostSearchState()) |> deliverOn(queue)).start(next: { [weak self] value in
            guard let self else {
                return
            }
            self.state.globalState = value
            self.publish()
        }))
        if context.isPremium {
            _ = context.engine.messages.refreshGlobalPostSearchState().start()
        }
    }

    deinit {
        taskDisposables.dispose()
        globalDisposable.dispose()
        quotaDisposable.dispose()
        translationDisposable.dispose()
    }

    public static func account(_ context: any AccountContextProtocol) -> NovagramJobAccount {
        return NovagramJobAccount(peerId: context.peerId.toInt64(), recordId: context.account.id.int64)
    }

    public func update(filter: NovagramJobFilter, sources: NovagramJobSources, debounce: Bool = true, remember: Bool = true) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.generation += 1
            self.filter = filter
            self.query = NovagramSearchQuery.parse(filter.query, languages: filter.languages, translations: [:])
            self.remember = remember
            let generation = self.generation
            self.cancelTasks()
            self.isWaiting = true
            self.publish()
            if debounce {
                self.queue.after(NovagramJobSearchEngine.debounceDelay, { [weak self] in
                    self?.start(generation: generation, filter: filter, sources: sources)
                })
            } else {
                self.start(generation: generation, filter: filter, sources: sources)
            }
        }
    }

    public func loadMore() {
        queue.async { [weak self] in
            guard let self, self.active == 0, self.pending.isEmpty else {
                return
            }
            self.pending = self.tasks.indices.filter { !self.tasks[$0].completed }
            guard !self.pending.isEmpty else {
                return
            }
            self.pump()
            self.publish()
        }
    }

    public func cancel() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.generation += 1
            self.isWaiting = false
            self.cancelTasks()
            self.globalDisposable.set(nil)
        }
    }

    public func searchGlobalPosts() {
        let context = self.context
        guard context.isPremium else {
            return
        }
        queue.async { [weak self] in
            guard let self, !self.state.isGlobalLoading else {
                return
            }
            if let quota = self.state.globalState, quota.remainingFreeSearches <= 0 {
                return
            }
            let text = self.query.serverQueries.first ?? self.query.raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return
            }
            let generation = self.generation
            let minDate = self.filter.period.minDate(now: NovagramJobSearchEngine.now())
            let location: SearchMessagesLocation = .general(scope: .globalPosts(allowPaidStars: nil), groupId: nil, tags: nil, minDate: minDate, maxDate: nil, folderId: nil, communityId: nil)
            self.state.isGlobalLoading = true
            self.state.failedSources.remove(.global)
            self.publish()
            var handled = false
            self.globalDisposable.set((NovagramJobRequestLimiter.shared.limited(context.engine.messages.searchMessages(location: location, query: text, state: nil, limit: NovagramJobSearchEngine.pageLimit) |> take(1)) |> deliverOn(self.queue)).start(next: { [weak self] result, _ in
                handled = true
                self?.finishGlobal(generation: generation, messages: result.messages)
            }, completed: { [weak self] in
                if !handled {
                    self?.finishGlobal(generation: generation, messages: nil)
                }
            }))
        }
    }

    private func finishGlobal(generation: Int, messages: [Message]?) {
        state.isGlobalLoading = false
        if let messages {
            for message in NovagramSearchPrivacy.kept(messages, message: { $0 }) where !message.text.isEmpty && !novagramJobIsSpam(message, text: message.text) {
                var info = NovagramJobPostParser.parse(message.text)
                info.contacts = NovagramJobMessageContacts.merged(parsed: info.contacts, message: message)
                globalFound[message.id] = NovagramJobResult(message: message, text: message.text, info: info, source: .global)
            }
        } else {
            state.failedSources.insert(.global)
        }
        publish()
        _ = context.engine.messages.refreshGlobalPostSearchState().start()
    }

    private func cancelTasks() {
        translationDisposable.set(nil)
        taskDisposables.dispose()
        taskDisposables = DisposableSet()
        tasks = []
        pending = []
        active = 0
    }

    private func start(generation: Int, filter: NovagramJobFilter, sources: NovagramJobSources) {
        guard generation == self.generation else {
            return
        }
        let needed = NovagramSearchConversion.plan(query: filter.query, languages: filter.languages).translationsNeeded
        guard !needed.isEmpty else {
            begin(generation: generation, filter: filter, sources: sources)
            return
        }
        translationDisposable.set((NovagramJobTranslations.fetch(engine: context.engine, query: filter.query, needed: needed) |> deliverOn(queue)).start(next: { [weak self] translations in
            guard let self, generation == self.generation else {
                return
            }
            self.query = NovagramSearchQuery.parse(filter.query, languages: filter.languages, translations: translations)
            self.begin(generation: generation, filter: filter, sources: sources)
        }))
    }

    private func begin(generation: Int, filter: NovagramJobFilter, sources: NovagramJobSources) {
        self.isWaiting = false
        if remember {
            NovagramJobStore.setLastFilter(filter, account: account)
        }
        self.found = [:]
        self.tasks = makeTasks(sources: sources)
        self.pending = Array(tasks.indices)
        state.items = []
        state.hasRun = true
        state.failedSources = []
        pump()
        publish()
    }

    private func pump() {
        while active < NovagramJobSearchEngine.maxConcurrentRequests, !pending.isEmpty {
            run(pending.removeFirst())
        }
    }

    private func run(_ index: Int) {
        let task = tasks[index]
        let generation = self.generation
        active += 1
        var handled = false
        taskDisposables.add((NovagramJobRequestLimiter.shared.limited(task.request(task.pagingState) |> take(1)) |> deliverOn(queue)).start(next: { [weak self] result, pagingState in
            handled = true
            self?.finish(index: index, generation: generation, result: result, pagingState: pagingState)
        }, completed: { [weak self] in
            if !handled {
                self?.finish(index: index, generation: generation, result: nil, pagingState: nil)
            }
        }))
    }

    private func finish(index: Int, generation: Int, result: SearchMessagesResult?, pagingState: SearchMessagesState?) {
        guard generation == self.generation, index < tasks.count else {
            return
        }
        active -= 1
        let task = tasks[index]
        if let result {
            task.pagingState = pagingState
            task.completed = result.completed || result.messages.isEmpty
            ingest(result.messages, source: task.source)
        } else {
            task.completed = true
            state.failedSources.insert(task.source)
        }
        pump()
        publish()
    }

    private func ingest(_ messages: [Message], source: NovagramJobSource) {
        let now = NovagramJobSearchEngine.now()
        for message in NovagramSearchPrivacy.kept(messages, message: { $0 }) where found[message.id] == nil {
            let text = message.text
            guard !text.isEmpty else {
                continue
            }
            guard !novagramJobIsSpam(message, text: text) else {
                continue
            }
            var info = NovagramJobPostParser.parse(text)
            info.contacts = NovagramJobMessageContacts.merged(parsed: info.contacts, message: message)
            guard filter.accepts(text: text, info: info, date: message.timestamp, now: now, query: query) else {
                continue
            }
            found[message.id] = NovagramJobResult(message: message, text: text, info: info, source: source)
        }
    }

    private func publish() {
        let now = NovagramJobSearchEngine.now()
        var merged = found
        for (id, result) in globalFound where merged[id] == nil && filter.accepts(text: result.text, info: result.info, date: result.message.timestamp, now: now, query: query) {
            merged[id] = result
        }
        state.items = merged.values.sorted { lhs, rhs in
            if lhs.message.timestamp != rhs.message.timestamp {
                return lhs.message.timestamp > rhs.message.timestamp
            }
            return lhs.message.id > rhs.message.id
        }
        state.isLoading = isWaiting || active > 0 || !pending.isEmpty || !state.hasRun
        state.canLoadMore = !state.isLoading && tasks.contains(where: { !$0.completed })
        statePromise.set(state)
    }

    private func makeTasks(sources: NovagramJobSources) -> [NovagramJobSearchTask] {
        let engine = context.engine
        let minDate = filter.period.minDate(now: NovagramJobSearchEngine.now())
        let limit = NovagramJobSearchEngine.pageLimit
        let texts = query.serverQueries.isEmpty ? NovagramJobSearchEngine.presetKeywords(for: filter.mode) : query.serverQueries
        var result: [NovagramJobSearchTask] = []
        if sources.hashtags {
            for hashtag in hashtags() {
                result.append(NovagramJobSearchTask(source: .hashtags, request: { state in
                    engine.messages.searchHashtagPosts(hashtag: hashtag, state: state, limit: limit)
                }))
            }
        }
        if sources.myChats {
            let location: SearchMessagesLocation = .general(scope: .everywhere, groupId: nil, tags: nil, minDate: minDate, maxDate: nil, folderId: nil, communityId: nil)
            for text in texts {
                result.append(NovagramJobSearchTask(source: .myChats, request: { state in
                    engine.messages.searchMessages(location: location, query: text, state: state, limit: limit)
                }))
            }
        }
        if sources.watched {
            let channelText = query.serverQueries.count == 1 ? query.serverQueries[0] : ""
            for channel in NovagramJobStore.watchedChannels(account: account).prefix(NovagramJobSearchEngine.watchedChannelLimit) {
                let location: SearchMessagesLocation = .peer(peerId: PeerId(channel), fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: minDate, maxDate: nil)
                result.append(NovagramJobSearchTask(source: .watched, request: { state in
                    engine.messages.searchMessages(location: location, query: channelText, state: state, limit: limit)
                }))
            }
        }
        return result
    }

    private func hashtags() -> [String] {
        return NovagramJobSearchEngine.cleanHashtags(NovagramJobSearchEngine.runHashtags(filter) + query.hashtagTerms)
    }

    static func runHashtags(_ filter: NovagramJobFilter) -> [String] {
        return Array(filter.hashtags(for: filter.mode).prefix(maxRunHashtags))
    }

    static func presetKeywords(for mode: NovagramJobMode) -> [String] {
        return Array(NovagramJobPresets.keywords(for: mode).prefix(presetKeywordCount))
    }

    static func cleanHashtags(_ all: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in all {
            let clean = tag.replacingOccurrences(of: "[#$]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, seen.insert(clean.lowercased()).inserted else {
                continue
            }
            result.append(clean)
        }
        return result
    }

    static func now() -> Int32 {
        return Int32(Date().timeIntervalSince1970)
    }
}
