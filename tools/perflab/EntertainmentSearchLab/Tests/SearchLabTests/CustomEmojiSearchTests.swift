import XCTest
import SwiftSignalKit
@testable import SearchLab

final class CustomEmojiSearchTests: XCTestCase {
    func drain() {
        let done = expectation(description: "debounced search")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    func testPhraseWithoutUnicodeKeywordsSearchesCustomEmojiAndPacks() {
        let h = EmojiHarness()
        h.context.engine.emojiState = .single(.init(items: [.init(fileId: 7)], canLoadMore: false, isLoadingMore: false))
        h.context.engine.remoteSets = .single(.init(entries: [9]))
        var latest: EmojiPanelSearchData?
        let d = h.fullSearchResults().start(next: { latest = $0 })
        h.searchValue.set(.init(state: .Focus, request: "  PEPPA\t PIG  "))
        drain()
        XCTAssertEqual(h.context.engine.emojiRequests.map(\.query), ["peppa pig"])
        XCTAssertEqual(h.context.engine.emojiRequests.first?.emoticons, [])
        XCTAssertEqual(h.context.engine.emojiRequests.first?.language, "en")
        XCTAssertEqual(h.context.engine.setQueries, ["peppa pig", "peppa pig"])
        XCTAssertEqual(latest?.values, [])
        XCTAssertEqual(latest?.files.map(\.fileId), [7])
        XCTAssertEqual(latest?.packs.entries, [9])
        XCTAssertEqual(latest?.isLoading, false)
        d.dispose()
    }

    func testKeywordsAreForwardedAlongsideWholePhrase() {
        let h = EmojiHarness()
        h.context.input.results = [["❤️"]]
        let d = h.fullSearchResults().start()
        h.searchValue.set(.init(state: .Focus, request: "red heart"))
        drain()
        XCTAssertEqual(h.context.engine.emojiRequests.first?.query, "red heart")
        XCTAssertEqual(h.context.engine.emojiRequests.first?.emoticons, ["❤️"])
        d.dispose()
    }

    func testRapidTypingOnlyStartsFinalRemoteQuery() {
        let h = EmojiHarness()
        let d = h.fullSearchResults().start()
        for query in ["p", "pe", "peppa", "peppa pig"] {
            h.searchValue.set(.init(state: .Focus, request: query))
        }
        drain()
        XCTAssertEqual(h.context.engine.emojiRequests.map(\.query), ["peppa pig"])
        d.dispose()
    }

    func testNewQueryCancelsOldEmojiAndPackSubscriptions() {
        let h = EmojiHarness()
        var oldEmoji: Subscriber<EmojiSearchContext.State, NoError>?
        var oldPacks: Subscriber<FoundStickerSets, NoError>?
        var disposedEmoji = false
        var disposedPacks = false
        h.context.engine.emojiState = Signal { subscriber in
            oldEmoji = subscriber
            subscriber.putNext(.init(items: [], canLoadMore: false, isLoadingMore: true))
            return ActionDisposable { disposedEmoji = true }
        }
        h.context.engine.remoteSets = Signal { subscriber in
            oldPacks = subscriber
            return ActionDisposable { disposedPacks = true }
        }
        var latest: EmojiPanelSearchData?
        let d = h.fullSearchResults().start(next: { latest = $0 })
        h.searchValue.set(.init(state: .Focus, request: "old query"))
        drain()
        h.context.engine.emojiState = .single(.init(items: [.init(fileId: 2)], canLoadMore: false, isLoadingMore: false))
        h.context.engine.remoteSets = .single(.init(entries: [2]))
        h.searchValue.set(.init(state: .Focus, request: "new query"))
        XCTAssertTrue(disposedEmoji)
        XCTAssertTrue(disposedPacks)
        drain()
        oldEmoji?.putNext(.init(items: [.init(fileId: 1)], canLoadMore: false, isLoadingMore: false))
        oldPacks?.putNext(.init(entries: [1]))
        XCTAssertEqual(latest?.files.map(\.fileId), [2])
        XCTAssertEqual(latest?.packs.entries, [2])
        d.dispose()
    }

    func testClearingSearchClearsRemoteFilesPacksAndContext() {
        let h = EmojiHarness()
        h.context.engine.emojiState = .single(.init(items: [.init(fileId: 1)], canLoadMore: false, isLoadingMore: false))
        h.context.engine.remoteSets = .single(.init(entries: [1]))
        var latest: EmojiPanelSearchData?
        let d = h.fullSearchResults().start(next: { latest = $0 })
        h.searchValue.set(.init(state: .Focus, request: "peppa pig"))
        drain()
        XCTAssertNotNil(latest?.context)
        h.searchValue.set(.init(state: .Focus, request: ""))
        XCTAssertNil(latest?.values)
        XCTAssertNil(latest?.context)
        XCTAssertEqual(latest?.files, [])
        XCTAssertEqual(latest?.packs.entries, [])
        d.dispose()
    }

    func testLocalPackResultsRemainWhileRemoteSearchIsLoading() {
        let engine = StickerEngine()
        engine.localSets = .single(.init(entries: [1]))
        var remote: Subscriber<FoundStickerSets, NoError>?
        engine.remoteSets = Signal { remote = $0; return EmptyDisposable }
        var results: [EmojiPanelSearchData] = []
        let d = panelCustomEmojiSearch(engine: engine, query: "peppa pig", values: [], languageCode: "en").start(next: { results.append($0) })
        XCTAssertEqual(results.last?.packs.entries, [1])
        XCTAssertEqual(results.last?.isLoading, true)
        remote?.putNext(.init(entries: [2]))
        XCTAssertEqual(results.last?.packs.entries, [1, 2])
        XCTAssertEqual(results.last?.isLoading, false)
        d.dispose()
    }

    func testRemotePackCompletionWithoutEmissionEndsLoading() {
        let engine = StickerEngine()
        engine.remoteSets = .complete()
        var latest: EmojiPanelSearchData?
        let d = panelCustomEmojiSearch(engine: engine, query: "peppa pig", values: [], languageCode: "en").start(next: { latest = $0 })
        XCTAssertEqual(latest?.packs.entries, [])
        XCTAssertEqual(latest?.isLoading, false)
        d.dispose()
    }

    func testNoEmptyStateUntilBothCustomEmojiAndPacksFinish() {
        let engine = StickerEngine()
        let emoji = ValuePromise(EmojiSearchContext.State(items: [], canLoadMore: false, isLoadingMore: true))
        let packs = Promise<FoundStickerSets>()
        engine.emojiState = emoji.get()
        engine.remoteSets = packs.get()
        var latest: EmojiPanelSearchData?
        let d = panelCustomEmojiSearch(engine: engine, query: "unknown phrase", values: [], languageCode: "en").start(next: { latest = $0 })
        XCTAssertEqual(latest?.isLoading, true)
        packs.set(.single(.init()))
        XCTAssertEqual(latest?.isLoading, true)
        emoji.set(.init(items: [], canLoadMore: false, isLoadingMore: false))
        XCTAssertEqual(latest?.isLoading, false)
        d.dispose()
    }

    func testCategoryUsesIdentifiersWithoutTextPackSearch() {
        let h = EmojiHarness()
        let d = h.fullSearchResults().start()
        h.statePromise.set(.init(selectedEmojiCategory: .init(identifiers: ["❤️", "💟"])))
        XCTAssertEqual(h.context.engine.emojiRequests.first?.emoticons, ["❤️", "💟"])
        XCTAssertNil(h.context.engine.emojiRequests.first?.query)
        XCTAssertTrue(h.context.engine.setQueries.isEmpty)
        XCTAssertTrue(h.context.input.queries.isEmpty)
        d.dispose()
    }

    func testSpecializedPickersDoNotRequestUnrelatedCustomEmoji() {
        for mode in [EmojiMode.status, .messageEffects] {
            let h = EmojiHarness()
            h.mode = mode
            let d = h.fullSearchResults().start()
            h.searchValue.set(.init(state: .Focus, request: "red heart"))
            drain()
            XCTAssertTrue(h.context.engine.emojiRequests.isEmpty)
            d.dispose()
        }
    }

    func testDuplicateKeywordUpdatesDoNotRestartRemoteSearch() {
        let h = EmojiHarness()
        h.context.input.results = [["❤️"], ["❤️"]]
        let d = h.fullSearchResults().start()
        h.searchValue.set(.init(state: .Focus, request: "red heart"))
        drain()
        XCTAssertEqual(h.context.engine.emojiRequests.count, 1)
        d.dispose()
    }

    func testSearchContextSurvivesWhileSubscribedAndPublishesFurtherPages() {
        let engine = StickerEngine()
        let states = ValuePromise(EmojiSearchContext.State(items: [.init(fileId: 1)], canLoadMore: true, isLoadingMore: false))
        engine.emojiState = states.get()
        var ids: [Int] = []
        let d = panelCustomEmojiSearch(engine: engine, query: "pig", values: [], languageCode: "en").start(next: { ids = $0.files.map(\.fileId) })
        weak var context = engine.emojiContexts.first
        engine.emojiContexts.removeAll()
        XCTAssertNotNil(context)
        states.set(.init(items: [.init(fileId: 1), .init(fileId: 2)], canLoadMore: false, isLoadingMore: false))
        XCTAssertEqual(ids, [1, 2])
        d.dispose()
        XCTAssertNil(context)
    }
}

final class EmojiSearchPackTests: XCTestCase {
    func testSearchReplacesBrowsingPacksEvenWithoutUnicodeMatches() {
        XCTAssertEqual(panelEmojiDisplayedSections(isSearching: true, isMessageEffects: false, browsing: ["Plush Pepe", "Kawaii Emoji"], matching: ["Peppa Pig"]), ["Peppa Pig"])
        XCTAssertEqual(panelEmojiDisplayedSections(isSearching: true, isMessageEffects: false, browsing: ["Plush Pepe"], matching: [String]()), [])
    }

    func testClearingSearchRestoresBrowsingPacks() {
        XCTAssertEqual(panelEmojiDisplayedSections(isSearching: false, isMessageEffects: false, browsing: ["Plush Pepe"], matching: ["Peppa Pig"]), ["Plush Pepe"])
    }

    func testMessageEffectsKeepTheirAlreadyFilteredSections() {
        XCTAssertEqual(panelEmojiDisplayedSections(isSearching: true, isMessageEffects: true, browsing: ["Matched effect"], matching: [String]()), ["Matched effect"])
    }

    func testPackGroupsAndFilesAreDeduplicatedAndKeepInstallationStatus() {
        var packs = FoundStickerSets(entries: [.init(collection: 1, file: 10), .init(collection: 1, file: 10), .init(collection: 1, file: 11), .init(collection: 2, file: 20)])
        let info1 = StickerPackCollectionInfo(id: 1, title: "Peppa Pig")
        let info2 = StickerPackCollectionInfo(id: 2, title: "Pig")
        packs.infos = [(1, info1, nil, false), (1, info1, nil, false), (2, info2, nil, true), (3, StickerPackCollectionInfo(id: 3, title: "Empty"), nil, false)]
        let result = panelEmojiMatchingPacks(packs, installedIds: [1])
        XCTAssertEqual(result.map { $0.info.id }, [1, 2])
        XCTAssertEqual(result.map { $0.items.map { $0.file.fileId } }, [[10, 11], [20]])
        XCTAssertEqual(result.map(\.installed), [true, true])
    }

    func testPackWithSameCountButDifferentItemsIsNotEqual() {
        var first = EmojiSectionEqualityFixture()
        first.items = [1, 2]
        var second = first
        second.items = [1, 3]
        XCTAssertNotEqual(first, second)
    }

    func testSameCountReplacementOfRemoteResultsUpdatesState() {
        var first = EmojiStateEqualityFixture()
        first.searchFiles = [1]
        var second = first
        second.searchFiles = [2]
        XCTAssertNotEqual(first, second)
        second = first
        second.searchSections = [2]
        XCTAssertNotEqual(first, second)
    }
}
