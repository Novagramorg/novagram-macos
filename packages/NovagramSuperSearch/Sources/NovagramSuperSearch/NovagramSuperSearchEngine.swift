import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramContext
import NovagramCore
import NovagramSearchKit

final class NovagramSuperSearchItem: Equatable {
    let hit: NovagramSuperSearchHit
    let message: Message?
    let peer: EnginePeer?
    let isDeleted: Bool

    init(hit: NovagramSuperSearchHit, message: Message?, peer: EnginePeer?, isDeleted: Bool) {
        self.hit = hit
        self.message = message
        self.peer = peer
        self.isDeleted = isDeleted
    }

    var messageId: MessageId {
        return MessageId(peerId: PeerId(hit.id.peerId), namespace: hit.id.namespace, id: hit.id.id)
    }

    static func == (lhs: NovagramSuperSearchItem, rhs: NovagramSuperSearchItem) -> Bool {
        return lhs.hit == rhs.hit && lhs.message?.stableVersion == rhs.message?.stableVersion && lhs.peer == rhs.peer && lhs.isDeleted == rhs.isDeleted
    }
}

struct NovagramSuperSearchPeer: Equatable {
    let peer: EnginePeer
    let subscribers: Int32?
}

struct NovagramSuperSearchSourceStatus: Equatable {
    var isLoading: Bool = false
    var failed: Bool = false
    var canLoadMore: Bool = false
    var count: Int = 0
}

struct NovagramSuperSearchState: Equatable {
    var items: [NovagramSuperSearchItem] = []
    var peers: [NovagramSuperSearchPeer] = []
    var statuses: [NovagramSuperSearchSource: NovagramSuperSearchSourceStatus] = [:]
    var hasQuery: Bool = false
    var hasRun: Bool = false
    var isWaiting: Bool = false
    var globalState: TelegramGlobalPostSearchState?

    var isLoading: Bool {
        return isWaiting || statuses.values.contains(where: { $0.isLoading })
    }

    func status(_ source: NovagramSuperSearchSource) -> NovagramSuperSearchSourceStatus {
        return statuses[source] ?? NovagramSuperSearchSourceStatus()
    }
}

private typealias NovagramSuperSearchRequest = (SearchMessagesState?) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError>

private final class NovagramSuperSearchTask {
    let source: NovagramSuperSearchSource
    let request: NovagramSuperSearchRequest
    var pagingState: SearchMessagesState?
    var completed: Bool = false
    var isLoading: Bool = false

    init(source: NovagramSuperSearchSource, request: @escaping NovagramSuperSearchRequest) {
        self.source = source
        self.request = request
    }
}

private struct NovagramSuperSearchRequestKey: Equatable {
    let query: String
    let sources: Set<NovagramSuperSearchSource>
    let period: NovagramSuperSearchPeriod
    let tags: MessageTags?
    let languages: Set<NovagramSearchLanguage>

    func sameExceptSources(_ other: NovagramSuperSearchRequestKey) -> Bool {
        return query == other.query && period == other.period && tags == other.tags && languages == other.languages
    }
}

final class NovagramSuperSearchEngine {
    private static let queryDebounce: Double = 1.0
    private static let filterDebounce: Double = 0.4
    private static let pageLimit: Int32 = 50

    private let context: any AccountContextProtocol
    private let queue = Queue()
    private let statePromise = ValuePromise(NovagramSuperSearchState(), ignoreRepeated: true)
    private var state = NovagramSuperSearchState()
    private var filter = NovagramSuperSearchFilter()
    private var requestKey: NovagramSuperSearchRequestKey?
    private var plan: NovagramSuperSearchPlan?
    private var ranSources: Set<NovagramSuperSearchSource> = []
    private var generation = 0
    private var minDate: Int32?
    private var tasks: [NovagramSuperSearchTask] = []
    private var failed: Set<NovagramSuperSearchSource> = []
    private var results = NovagramSuperSearchResults()
    private var messages: [NovagramSuperSearchHitId: Message] = [:]
    private var archivePeers: [NovagramSuperSearchHitId: EnginePeer] = [:]
    private var archiveDeleted: Set<NovagramSuperSearchHitId> = []
    private var peers: [NovagramSuperSearchPeer] = []
    private var peersRequested = false
    private var peersLoading = false
    private var channelTasksAdded = false
    private var archiveSession: NovagramArchiveSearchSession?
    private var archiveLoading = false
    private var archivePages = 1
    private var archiveHitCount = 0
    private var taskDisposables = DisposableSet()
    private let peersDisposable = MetaDisposable()
    private let archiveDisposable = MetaDisposable()
    private let archivePeersDisposable = MetaDisposable()
    private let translationDisposable = MetaDisposable()
    private let quotaDisposable = MetaDisposable()

    var stateSignal: Signal<NovagramSuperSearchState, NoError> {
        return statePromise.get()
    }

    init(context: any AccountContextProtocol) {
        self.context = context
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
        peersDisposable.dispose()
        archiveDisposable.dispose()
        archivePeersDisposable.dispose()
        translationDisposable.dispose()
        quotaDisposable.dispose()
    }

    func update(query: String, filter: NovagramSuperSearchFilter) {
        queue.async { [weak self] in
            self?.apply(query: query, filter: filter)
        }
    }

    private func apply(query: String, filter: NovagramSuperSearchFilter) {
        let normalized = NovagramSuperSearchEngine.normalized(query)
        let key = NovagramSuperSearchRequestKey(query: normalized, sources: filter.sources.subtracting([.globalPosts]), period: filter.period, tags: NovagramSuperSearchEngine.tags(filter.mediaKinds), languages: filter.languages)
        let previous = requestKey
        self.filter = filter
        guard key != previous else {
            publish()
            return
        }
        requestKey = key
        if let previous, previous.sameExceptSources(key), let plan {
            let added = key.sources.subtracting(ranSources)
            ranSources.formUnion(added)
            start(sources: added, plan: plan, generation: generation)
            publish()
            return
        }
        generation += 1
        cancelRequests()
        plan = nil
        state.hasQuery = !normalized.isEmpty
        state.hasRun = false
        guard !normalized.isEmpty else {
            clearResults()
            state.isWaiting = false
            publish()
            return
        }
        state.isWaiting = true
        publish()
        let generation = self.generation
        let delay = previous?.query != normalized ? NovagramSuperSearchEngine.queryDebounce : NovagramSuperSearchEngine.filterDebounce
        queue.after(delay, { [weak self] in
            self?.translateAndBegin(generation: generation, raw: query, filter: filter)
        })
    }

    func loadMore(_ source: NovagramSuperSearchSource) {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            if source == .archive {
                guard !self.archiveLoading, let session = self.archiveSession, self.archiveHitCount >= self.archivePages * NovagramMessageArchive.pageSize, self.archivePages < NovagramMessageArchive.maxPages else {
                    return
                }
                self.archivePages += 1
                self.archiveLoading = true
                session.loadMore()
                self.publish()
                return
            }
            self.failed.remove(source)
            for task in self.tasks where task.source == source && !task.completed && !task.isLoading {
                self.run(task)
            }
            self.publish()
        }
    }

    func searchGlobalPosts() {
        guard context.isPremium else {
            return
        }
        queue.async { [weak self] in
            guard let self, let plan = self.plan, let text = plan.textQueries.first else {
                return
            }
            if let quota = self.state.globalState, quota.remainingFreeSearches <= 0 {
                return
            }
            guard !self.tasks.contains(where: { $0.source == .globalPosts && $0.isLoading }) else {
                return
            }
            self.tasks.removeAll(where: { $0.source == .globalPosts })
            self.results.removeAll(from: .globalPosts)
            self.failed.remove(.globalPosts)
            let engine = self.context.engine
            let location: SearchMessagesLocation = .general(scope: .globalPosts(allowPaidStars: nil), groupId: nil, tags: nil, minDate: self.minDate, maxDate: nil, folderId: nil, communityId: nil)
            let task = NovagramSuperSearchTask(source: .globalPosts, request: { state in
                engine.messages.searchMessages(location: location, query: text, state: state, limit: NovagramSuperSearchEngine.pageLimit)
            })
            self.tasks.append(task)
            self.run(task)
            self.publish()
        }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.generation += 1
            self.cancelRequests()
        }
    }

    private func cancelRequests() {
        translationDisposable.set(nil)
        peersDisposable.set(nil)
        archiveDisposable.set(nil)
        archivePeersDisposable.set(nil)
        taskDisposables.dispose()
        taskDisposables = DisposableSet()
        tasks = []
        peersLoading = false
        archiveLoading = false
    }

    private func clearResults() {
        plan = nil
        ranSources = []
        failed = []
        results = NovagramSuperSearchResults()
        messages = [:]
        archivePeers = [:]
        archiveDeleted = []
        peers = []
        peersRequested = false
        peersLoading = false
        channelTasksAdded = false
        archiveSession = nil
        archiveLoading = false
        archivePages = 1
        archiveHitCount = 0
    }

    private func translateAndBegin(generation: Int, raw: String, filter: NovagramSuperSearchFilter) {
        guard generation == self.generation else {
            return
        }
        let needed = NovagramSuperSearchPlan.translationsNeeded(raw: raw, filter: filter)
        guard !needed.isEmpty else {
            begin(generation: generation, raw: raw, filter: filter, translations: [:])
            return
        }
        translationDisposable.set((NovagramSuperSearchTranslations.fetch(engine: context.engine, query: raw, needed: needed) |> deliverOn(queue)).start(next: { [weak self] translations in
            guard let self, generation == self.generation else {
                return
            }
            self.begin(generation: generation, raw: raw, filter: filter, translations: translations)
        }))
    }

    private func begin(generation: Int, raw: String, filter: NovagramSuperSearchFilter, translations: [NovagramSearchLanguage: String]) {
        var everySource = filter
        everySource.sources = Set(NovagramSuperSearchSource.allCases)
        let plan = NovagramSuperSearchPlan.make(raw: raw, filter: everySource, translations: translations)
        clearResults()
        self.plan = plan
        state.isWaiting = false
        state.hasRun = true
        minDate = filter.period.minDate(now: NovagramSuperSearchEngine.now())
        ranSources = self.filter.sources.subtracting([.globalPosts])
        start(sources: ranSources, plan: plan, generation: generation)
        publish()
    }

    private func start(sources: Set<NovagramSuperSearchSource>, plan: NovagramSuperSearchPlan, generation: Int) {
        let runnable = Set(plan.sources).intersection(sources)
        let engine = context.engine
        let limit = NovagramSuperSearchEngine.pageLimit
        var added: [NovagramSuperSearchTask] = []
        if runnable.contains(.myChats) {
            let location: SearchMessagesLocation = .general(scope: .everywhere, groupId: nil, tags: NovagramSuperSearchEngine.tags(filter.mediaKinds), minDate: minDate, maxDate: nil, folderId: nil, communityId: nil)
            for text in plan.textQueries {
                added.append(NovagramSuperSearchTask(source: .myChats, request: { state in
                    engine.messages.searchMessages(location: location, query: text, state: state, limit: limit)
                }))
            }
        }
        if runnable.contains(.hashtagPosts) {
            for hashtag in plan.hashtags {
                added.append(NovagramSuperSearchTask(source: .hashtagPosts, request: { state in
                    engine.messages.searchHashtagPosts(hashtag: hashtag, state: state, limit: limit)
                }))
            }
        }
        tasks += added
        added.forEach(run)
        if runnable.contains(.publicChats) || runnable.contains(.publicChannelPosts), let peerQuery = plan.peerQuery {
            if !peersRequested {
                loadPeers(query: peerQuery, generation: generation)
            } else if !peersLoading {
                addChannelTasks()
            }
        }
        if runnable.contains(.archive) {
            loadArchive(raw: plan.raw, generation: generation)
        }
    }

    private func run(_ task: NovagramSuperSearchTask) {
        let generation = self.generation
        task.isLoading = true
        var handled = false
        taskDisposables.add((NovagramSuperSearchRequestLimiter.shared.limited(task.request(task.pagingState) |> take(1)) |> deliverOn(queue)).start(next: { [weak self, weak task] result, pagingState in
            handled = true
            guard let self, let task else {
                return
            }
            self.finish(task, generation: generation, result: result, pagingState: pagingState)
        }, completed: { [weak self, weak task] in
            guard !handled, let self, let task else {
                return
            }
            self.finish(task, generation: generation, result: nil, pagingState: nil)
        }))
    }

    private func finish(_ task: NovagramSuperSearchTask, generation: Int, result: SearchMessagesResult?, pagingState: SearchMessagesState?) {
        guard generation == self.generation else {
            return
        }
        task.isLoading = false
        if let result {
            task.pagingState = pagingState
            task.completed = result.completed || result.messages.isEmpty || task.source == .globalPosts
            ingest(result.messages, source: task.source)
        } else {
            task.completed = true
            failed.insert(task.source)
        }
        if task.source == .globalPosts {
            _ = context.engine.messages.refreshGlobalPostSearchState().start()
        }
        publish()
    }

    private func ingest(_ found: [Message], source: NovagramSuperSearchSource) {
        var hits: [NovagramSuperSearchHit] = []
        for message in NovagramSearchPrivacy.kept(found, message: { $0 }) {
            let hit = NovagramSuperSearchEngine.hit(message, source: source)
            if messages[hit.id] == nil {
                messages[hit.id] = message
            }
            hits.append(hit)
        }
        results.add(hits)
    }

    private func loadPeers(query: String, generation: Int) {
        peersRequested = true
        peersLoading = true
        var handled = false
        let signal = NovagramSuperSearchRequestLimiter.shared.limited(context.engine.contacts.searchRemotePeers(query: query, scope: .everywhere) |> take(1))
        peersDisposable.set((signal |> deliverOn(queue)).start(next: { [weak self] local, remote in
            handled = true
            self?.finishPeers(local + remote, generation: generation)
        }, completed: { [weak self] in
            if !handled {
                self?.finishPeers(nil, generation: generation)
            }
        }))
    }

    private func finishPeers(_ found: [FoundPeer]?, generation: Int) {
        guard generation == self.generation else {
            return
        }
        peersLoading = false
        guard let found else {
            failed.insert(.publicChats)
            publish()
            return
        }
        var seen = Set<PeerId>()
        peers = found.compactMap { item -> NovagramSuperSearchPeer? in
            let peerId = item.peer.id
            guard seen.insert(peerId).inserted, !NovagramHiddenChatsManager.shared.isPeerHiddenInStorage(peerId) else {
                return nil
            }
            return NovagramSuperSearchPeer(peer: item.peer, subscribers: item.subscribers)
        }
        addChannelTasks()
        publish()
    }

    private func addChannelTasks() {
        guard !channelTasksAdded, ranSources.contains(.publicChannelPosts), let plan, let text = plan.textQueries.first else {
            return
        }
        channelTasksAdded = true
        let engine = context.engine
        let minDate = self.minDate
        let limit = NovagramSuperSearchEngine.pageLimit
        let channels = peers.filter { if case .channel = $0.peer { return true } else { return false } }.prefix(NovagramSuperSearchPlan.maxChannelsToSearchInside)
        let added = channels.map { channel -> NovagramSuperSearchTask in
            let location: SearchMessagesLocation = .peer(peerId: channel.peer.id, fromId: nil, tags: nil, reactions: nil, threadId: nil, minDate: minDate, maxDate: nil)
            return NovagramSuperSearchTask(source: .publicChannelPosts, request: { state in
                engine.messages.searchMessages(location: location, query: text, state: state, limit: limit)
            })
        }
        tasks += added
        added.forEach(run)
    }

    private func loadArchive(raw: String, generation: Int) {
        guard archiveSession == nil, !archiveLoading else {
            return
        }
        archiveLoading = true
        archiveDisposable.set((NovagramMessageArchive.shared.search(accountRecordId: context.account.id.int64, query: raw) |> deliverOn(queue)).start(next: { [weak self] found in
            guard let self, generation == self.generation else {
                return
            }
            self.archiveSession = found.session
            self.loadArchivePeers(found.hits, generation: generation)
        }))
    }

    private func loadArchivePeers(_ found: [NovagramArchiveHit], generation: Int) {
        let hits = found.filter { !NovagramHiddenChatsManager.shared.isPeerHiddenInStorage($0.chatPeerId) }
        let peerIds = Array(Set(hits.map { $0.chatPeerId }))
        let request = EngineDataMap(peerIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) })
        archivePeersDisposable.set((context.engine.data.get(request) |> deliverOn(queue)).start(next: { [weak self] peers in
            guard let self, generation == self.generation else {
                return
            }
            self.archiveLoading = false
            self.archiveHitCount = found.count
            self.results.removeAll(from: .archive)
            var mapped: [NovagramSuperSearchHit] = []
            for hit in hits {
                let peer = peers[hit.chatPeerId] ?? nil
                let id = NovagramSuperSearchHitId(peerId: hit.chatPeerId.toInt64(), namespace: Namespaces.Message.Cloud, id: hit.messageId)
                if let peer {
                    self.archivePeers[id] = peer
                }
                if hit.isDeleted {
                    self.archiveDeleted.insert(id)
                }
                mapped.append(NovagramSuperSearchHit(id: id, date: hit.date, text: hit.text, source: .archive, chatTitle: NovagramSuperSearchEngine.title(peer?._asPeer()), chatUsername: peer?.addressName, chatKind: NovagramSuperSearchEngine.chatKind(peer?._asPeer()), mediaKind: .text))
            }
            self.results.add(mapped)
            self.publish()
        }))
    }

    private func publish() {
        let privacy = NovagramSearchPrivacyPass()
        let visible = results.visible(filter: filter, now: NovagramSuperSearchEngine.now()).filter { hit in
            let peerId = PeerId(hit.id.peerId)
            return !NovagramHiddenChatsManager.shared.isPeerHiddenInStorage(peerId) && !privacy.isLocked(peerId)
        }
        state.items = visible.map { hit in
            let message = messages[hit.id]
            let peer = message.flatMap { $0.peers[$0.id.peerId] }.map { EnginePeer($0) } ?? archivePeers[hit.id]
            return NovagramSuperSearchItem(hit: hit, message: message, peer: peer, isDeleted: message == nil && archiveDeleted.contains(hit.id))
        }
        state.peers = filter.sources.contains(.publicChats) ? peers.filter { isPeerVisible($0) && !NovagramHiddenChatsManager.shared.isPeerHiddenInStorage($0.peer.id) } : []
        var statuses: [NovagramSuperSearchSource: NovagramSuperSearchSourceStatus] = [:]
        for source in NovagramSuperSearchSource.allCases {
            let sourceTasks = tasks.filter { $0.source == source }
            var status = NovagramSuperSearchSourceStatus()
            status.isLoading = sourceTasks.contains(where: { $0.isLoading })
            status.canLoadMore = !status.isLoading && sourceTasks.contains(where: { !$0.completed })
            status.failed = failed.contains(source)
            status.count = results.count(for: source)
            switch source {
            case .publicChats:
                status.isLoading = peersLoading
                status.canLoadMore = false
                status.count = peers.count
            case .publicChannelPosts:
                status.isLoading = status.isLoading || (peersLoading && ranSources.contains(.publicChannelPosts))
            case .archive:
                status.isLoading = archiveLoading
                status.canLoadMore = !archiveLoading && archiveSession != nil && archiveHitCount >= archivePages * NovagramMessageArchive.pageSize && archivePages < NovagramMessageArchive.maxPages
            default:
                break
            }
            statuses[source] = status
        }
        state.statuses = statuses
        statePromise.set(state)
    }

    private func isPeerVisible(_ item: NovagramSuperSearchPeer) -> Bool {
        let peer = item.peer._asPeer()
        if !filter.chatKinds.isEmpty, !filter.chatKinds.contains(NovagramSuperSearchEngine.chatKind(peer)) {
            return false
        }
        if filter.hideSpam, NovagramSuperSearchSpam.isSpam(chatTitle: NovagramSuperSearchEngine.title(peer), chatUsername: item.peer.addressName, text: "") {
            return false
        }
        return true
    }

    static func normalized(_ query: String) -> String {
        return query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func tags(_ kinds: Set<NovagramSuperSearchMediaKind>) -> MessageTags? {
        guard !kinds.isEmpty, !kinds.contains(.text) else {
            return nil
        }
        var tags: MessageTags = []
        for kind in kinds {
            switch kind {
            case .photo:
                tags.insert(.photo)
            case .video:
                tags.insert(.video)
            case .file:
                tags.insert(.file)
            case .link:
                tags.insert(.webPage)
            case .voice:
                tags.insert(.voiceOrInstantVideo)
            case .music:
                tags.insert(.music)
            case .text:
                break
            }
        }
        return tags
    }

    static func hit(_ message: Message, source: NovagramSuperSearchSource) -> NovagramSuperSearchHit {
        let peer = message.peers[message.id.peerId]
        let id = NovagramSuperSearchHitId(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, id: message.id.id)
        return NovagramSuperSearchHit(id: id, date: message.timestamp, text: message.text, source: source, chatTitle: title(peer), chatUsername: peer.flatMap { EnginePeer($0).addressName }, chatKind: chatKind(peer), mediaKind: mediaKind(message))
    }

    static func title(_ peer: Peer?) -> String {
        if let channel = peer as? TelegramChannel {
            return channel.title
        }
        if let group = peer as? TelegramGroup {
            return group.title
        }
        if let user = peer as? TelegramUser {
            return [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
        return ""
    }

    static func chatKind(_ peer: Peer?) -> NovagramSuperSearchChatKind {
        if let user = peer as? TelegramUser {
            return user.botInfo != nil ? .bot : .privateChat
        }
        if let channel = peer as? TelegramChannel {
            if case .broadcast = channel.info {
                return .channel
            }
            return .group
        }
        if peer is TelegramGroup {
            return .group
        }
        return .privateChat
    }

    static func mediaKind(_ message: Message) -> NovagramSuperSearchMediaKind {
        for media in message.media {
            if media is TelegramMediaImage {
                return .photo
            }
            if let file = media as? TelegramMediaFile {
                if file.isVoice || file.isInstantVideo {
                    return .voice
                }
                if file.isMusic {
                    return .music
                }
                if file.isVideo {
                    return .video
                }
                return .file
            }
            if media is TelegramMediaWebpage {
                return .link
            }
        }
        return .text
    }

    static func now() -> Int32 {
        return Int32(Date().timeIntervalSince1970)
    }
}
