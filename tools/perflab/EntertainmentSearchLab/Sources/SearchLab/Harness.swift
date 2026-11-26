import Foundation
import SwiftSignalKit
import Strings

struct File: Equatable { let fileId: Int }
enum ChatContextResult: Equatable {
    struct Reference: Equatable { let id: String; let file: File? }
    case internalReference(Reference)
    case external(String)
    var id: String {
        switch self {
        case let .internalReference(value): return value.id
        case let .external(id): return id
        }
    }
}
struct ChatContextResultCollection: Equatable {
    let nextOffset: String
    let results: [ChatContextResult]
}
struct State {
    struct Entry: Equatable { let collection: ChatContextResultCollection?; let row: ChatContextResult }
    enum TabEntryId: Equatable {
        case recent, trending, recommended(Int)
        var stableId: AnyHashable {
            switch self {
            case .recent: return 0
            case .trending: return 1
            case let .recommended(id): return id
            }
        }
    }
    struct Search {
        static let stableId: AnyHashable = -1
        let request: String
        var nextOffset: String?
        var items: [Entry]
        var isLoading = true
    }
    struct Entries { var items: [Entry]; var nextOffset: String? }
    var search: Search?
    var entries: [AnyHashable: Entries] = [:]
}
struct SearchState: Equatable {
    enum Focus: Equatable { case Focus, None }
    let state: Focus
    let request: String
}
final class GifEngine {
    final class Request {
        let query: String
        let offset: String
        let subscriber: Subscriber<ChatContextResultCollection?, NoError>
        var disposed = false
        init(_ query: String, _ offset: String, _ subscriber: Subscriber<ChatContextResultCollection?, NoError>) {
            self.query = query
            self.offset = offset
            self.subscriber = subscriber
        }
        func emit(_ ids: [Int], next: String) {
            subscriber.putNext(.init(nextOffset: next, results: ids.map { .internalReference(.init(id: "result-\($0)", file: .init(fileId: $0))) }))
            subscriber.putCompletion()
        }
    }
    var requests: [Request] = []
    var stickers: GifEngine { self }
    func searchGifs(query: String, nextOffset: String) -> Signal<ChatContextResultCollection?, NoError> {
        return Signal { subscriber in
            let request = Request(query, nextOffset, subscriber)
            self.requests.append(request)
            return ActionDisposable { request.disposed = true }
        }
    }
}
final class GifContext { let engine = GifEngine() }
final class GifHarness {
    let context = GifContext()
    let stateValue = Atomic(value: State())
    let disposableDict = DisposableDict<AnyHashable>()
    var completedCount = 0
    var search: ((State.TabEntryId?, String, String) -> Void)!
    var update: ((SearchState) -> Void)!
    init() { install() }
    deinit { disposableDict.dispose() }
    var state: State { stateValue.with { $0 } }
}
struct FoundStickerItem { let id: Int }
final class StickerEngine {
    struct Request { let query: String?; let emoticons: [String]; let language: String }
    var requests: [Request] = []
    var stickers: StickerEngine { self }
    var categories: [EmojiCategory] = []
    var keywordRequests: [String] = []
    var keywordResults: [EmojiKeywordSearchEntry] = []
    func searchEmojiKeywords(inputLanguageCode: String, query: String, completeMatch: Bool) -> Signal<[EmojiKeywordSearchEntry], NoError> {
        keywordRequests.append(query)
        return .single(keywordResults)
    }
    var emojiRequests: [Request] = []
    var emojiContexts: [EmojiSearchContext] = []
    var emojiState: Signal<EmojiSearchContext.State, NoError> = .single(.init(items: [], canLoadMore: false, isLoadingMore: false))
    func emojiSearchContext(query: String?, emoticon: [String], inputLanguageCode: String) -> EmojiSearchContext {
        emojiRequests.append(.init(query: query, emoticons: emoticon, language: inputLanguageCode))
        let context = EmojiSearchContext(state: emojiState)
        emojiContexts.append(context)
        return context
    }
    func searchEmojiSets(query: String) -> Signal<FoundStickerSets, NoError> {
        setQueries.append(query)
        return localSets
    }
    func searchEmojiSetsRemotely(query: String) -> Signal<FoundStickerSets, NoError> {
        setQueries.append(query)
        return remoteSets
    }
    var setQueries: [String] = []
    var localSets: Signal<FoundStickerSets, NoError> = .single(.init(entries: []))
    var remoteSets: Signal<FoundStickerSets, NoError> = .single(.init(entries: []))
    func searchStickerSets(query: String) -> Signal<FoundStickerSets, NoError> {
        setQueries.append(query)
        return localSets
    }
    func searchStickerSetsRemotely(query: String) -> Signal<FoundStickerSets, NoError> {
        setQueries.append(query)
        return remoteSets
    }
    func searchStickers(category: EmojiCategory) -> Signal<(items: [FoundStickerItem], isFinalResult: Bool), NoError> {
        categories.append(category)
        return .single(([.init(id: 42)], true))
    }
    func searchStickers(query: String?, emoticon: [String], inputLanguageCode: String) -> Signal<(items: [FoundStickerItem], isFinalResult: Bool), NoError> {
        requests.append(.init(query: query, emoticons: emoticon, language: inputLanguageCode))
        return .single(([], true))
    }
}
final class StickerInput {
    var completeMatches: [Bool] = []
    var queries: [String] = []
    var results: [[String]] = [[]]
    var factory: ((String) -> Signal<[String], NoError>)?
    func searchEmoji(postbox: Int, engine: StickerEngine, sharedContext: any SharedAccountContextProtocol, query: String, completeMatch: Bool, checkPrediction: Bool) -> Signal<[String], NoError> {
        completeMatches.append(completeMatch)
        queries.append(query)
        if let factory = factory { return factory(query) }
        return Signal { subscriber in
            for result in self.results { subscriber.putNext(result) }
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
}
final class StickerContext {
    let engine = StickerEngine()
    let input = StickerInput()
    var account: StickerContext { self }
    let postbox = 0
    let sharedContext = SharedContext(accountManager: 1)
}
struct EntertainmentUIHooks {
    static let shared = EntertainmentUIHooks()
    func inputSource(_ context: StickerContext) -> StickerInput { context.input }
}

struct EmojiCategory: Equatable {
    enum Kind { case generic, premium }
    let identifiers: [String]
    var kind: Kind = .generic
}
struct CategoryState: Equatable { var selectedEmojiCategory: EmojiCategory? }
enum Position: Equatable { case initial, scroll(Int) }
enum EmojiMode { case emoji, stories, status, messageEffects }
final class EmojiHarness {
    var mode: EmojiMode = .emoji
    let context = StickerContext()
    let searchValue = ValuePromise(SearchState(state: .None, request: ""))
    let statePromise: ValuePromise<CategoryState>
    init(statePromise: ValuePromise<CategoryState> = makeEmojiStatePromise()) { self.statePromise = statePromise }
    let position = ValuePromise(Position.initial)
}

typealias StickerPacksScrollState = Position
enum EmojiSearchCategories { typealias Group = EmojiCategory }

func currentKeyboardLanguage() -> String { "en" }
struct FoundStickerSets {
    var infos: [(Int, Any, Int?, Bool)] = []
    var entries: [PackEntry]
    init(entries: [PackEntry] = []) { self.entries = entries }
    func merge(with other: FoundStickerSets) -> FoundStickerSets {
        var result = FoundStickerSets(entries: entries + other.entries)
        result.infos = infos + other.infos
        return result
    }
}
struct StickerPacksSearchData {
    let sets: FoundStickerSets
    let loading: Bool
    let basicFeaturedCount: Int
    let emojiRelated: [FoundStickerItem]
    let premiumStickers: [File]
}
struct StickerPacksUpdateData {
    enum Update { case generic(animated: Bool, scrollToTop: Bool?) }
    let view: Int?
    let update: Update
    let specificPack: Int?
    let searchData: StickerPacksSearchData
    let hasUnread: Bool
    let featured: [Int]
    let mode: Int
    let state: CategoryState
}

typealias Postbox = Int
typealias TelegramEngine = StickerEngine
protocol SharedAccountContextProtocol { var accountManager: Int { get } }
struct SharedContext: SharedAccountContextProtocol { let accountManager: Int }
struct Settings { let predictEmoji: Bool }
func baseAppSettings(accountManager: Int) -> Signal<Settings, NoError> { .single(.init(predictEmoji: accountManager == 1)) }

extension EmojiHarness {
    func signal() -> Signal<[String]?, NoError> {
        searchResults() |> filter { !$0.isLoading } |> map { $0.values }
    }
}

class TableRowItem {}
final class GeneralRowItem: TableRowItem {}
final class StickerPackPanelRowItem: TableRowItem {}
struct TableView {
    let items: [TableRowItem]
    func enumerateItems(with callback: (TableRowItem) -> Bool) {
        for item in items { if !callback(item) { break } }
    }
}

typealias TelegramMediaFile = File
final class EmojiSearchContext {
    struct State: Equatable {
        let items: [File]
        let canLoadMore: Bool
        let isLoadingMore: Bool
    }
    let state: Signal<State, NoError>
    init(state: Signal<State, NoError>) { self.state = state }
}

typealias ItemCollectionId = Int
struct StickerPackCollectionInfo { let id: Int; let title: String }
struct StickerPackItem { let file: File }
struct PackEntry: ExpressibleByIntegerLiteral, Equatable {
    struct Index { let collectionId: Int }
    let index: Index
    let item: Any
    init(collection: Int, file: Int) {
        index = Index(collectionId: collection)
        item = StickerPackItem(file: File(fileId: file))
    }
    init(integerLiteral value: Int) { self.init(collection: value, file: value) }
    static func == (lhs: PackEntry, rhs: PackEntry) -> Bool {
        return lhs.index.collectionId == rhs.index.collectionId && (lhs.item as? StickerPackItem)?.file == (rhs.item as? StickerPackItem)?.file
    }
}
