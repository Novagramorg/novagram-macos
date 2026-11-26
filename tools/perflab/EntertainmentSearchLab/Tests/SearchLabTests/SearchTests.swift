import XCTest
import SwiftSignalKit
@testable import SearchLab

final class KeywordTests: XCTestCase {
    let dictionary: [EmojiKeywordSearchEntry] = [
        .init(keyword: "red heart", emoticons: ["❤️"]),
        .init(keyword: "red apple", emoticons: ["🍎"]),
        .init(keyword: "angry face", emoticons: ["😠"]),
        .init(keyword: "happy birthday", emoticons: ["🎂", "🎉"])
    ]
    func lookup(_ query: String, complete: Bool = false) -> ([String], [String]) {
        var requests: [String] = []
        var result: [String] = []
        let disposable = searchEmojiKeywordMatches(query: query, languageCodes: ["en-US"], completeMatch: complete) { _, query, exact in
            requests.append(query)
            return .single(self.dictionary.filter { entry in
                exact ? entry.keyword == query : query.split(separator: " ").allSatisfy { token in
                    entry.keyword.split(separator: " ").contains { $0.hasPrefix(token) }
                }
            })
        }.start(next: { result = $0 })
        disposable.dispose()
        return (result, requests)
    }
    func testTwoWordsMatchPhrase() { XCTAssertEqual(lookup("red heart").0, ["❤️"]) }
    func testPartialSecondWord() { XCTAssertEqual(lookup("red hea").0, ["❤️"]) }
    func testBirthdayPhrase() { XCTAssertEqual(lookup("happy birthday").0, ["🎂", "🎉"]) }
    func testWhitespaceAndCase() { XCTAssertEqual(lookup("  RED\t HEA\n").0, ["❤️"]) }
    func testUnmatchedPhraseDoesNotUnionIndividualWords() {
        let result = lookup("red angry")
        XCTAssertEqual(result.0, [])
        XCTAssertEqual(result.1, ["red angry"])
    }
    func testEmptyQueryDoesNotSearch() { XCTAssertEqual(lookup(" \n ").1, []) }
    func testExactMatchStillExact() { XCTAssertEqual(lookup("red hea", complete: true).0, []) }
    func testExactPhrase() { XCTAssertEqual(lookup("red heart", complete: true).0, ["❤️"]) }
    func testLocalThenEnglishAndStableDeduplication() {
        var requests: [String] = []
        var results: [[String]] = []
        let d = searchEmojiKeywordMatches(query: "red heart", languageCodes: ["ru-RU", "ru_RU"], completeMatch: false) { language, query, exact in
            requests.append(language)
            XCTAssertEqual(query, "red heart")
            XCTAssertFalse(exact)
            return .single([.init(keyword: query, emoticons: language == "en-US" ? ["❤️", "💟"] : ["❤️", "❤️"])])
        }.start(next: { results.append($0) })
        XCTAssertEqual(requests, ["ru-RU", "en-US"])
        XCTAssertEqual(results, [["❤️"], ["❤️", "💟"]])
        d.dispose()
    }
    func testEnglishKeyboardDoesNotRepeatEnglishSearch() {
        var calls = 0
        let d = searchEmojiKeywordMatches(query: "happy birthday", languageCodes: ["en-GB", "en_GB"], completeMatch: false) { _, _, _ in
            calls += 1
            return .single([])
        }.start()
        XCTAssertEqual(calls, 1)
        d.dispose()
    }
    func testMissingKeyboardUsesEnglish() {
        var requests: [String] = []
        let d = searchEmojiKeywordMatches(query: "red heart", languageCodes: ["emoji", ""], completeMatch: false) { language, _, _ in
            requests.append(language)
            return .single([])
        }.start()
        XCTAssertEqual(requests, ["en-US"])
        d.dispose()
    }
    func testCancellationCancelsEnglishFallback() {
        var cancelled = false
        let d = searchEmojiKeywordMatches(query: "red heart", languageCodes: ["ru"], completeMatch: false) { language, _, _ in
            if language == "ru" { return .single([]) }
            return Signal { _ in ActionDisposable { cancelled = true } }
        }.start()
        d.dispose()
        XCTAssertTrue(cancelled)
    }
    func testExactFilterRejectsLongerKeywordReturnedByIndex() {
        var results: [String] = []
        let d = searchEmojiKeywordMatches(query: "red", languageCodes: ["en"], completeMatch: true) { _, _, _ in
            .single(self.dictionary)
        }.start(next: { results = $0 })
        XCTAssertEqual(results, [])
        d.dispose()
    }
}

final class StickerIntegrationTests: XCTestCase {
    func testPhraseAndMatchedEmojiReachEngine() {
        let context = StickerContext()
        context.input.results = [["❤️", "❤️", "👍🏽", "👍"]]
        let d = stickerSearch(context: context, searchText: "red heart", input: .single("en-US")).start()
        XCTAssertEqual(context.input.completeMatches, [false])
        XCTAssertEqual(context.engine.requests.count, 1)
        XCTAssertEqual(context.engine.requests[0].query, "red heart")
        XCTAssertEqual(context.engine.requests[0].emoticons, ["❤", "👍"])
        XCTAssertEqual(context.engine.requests[0].language, "en-US")
        d.dispose()
    }
    func testPartialPhraseUsesPrefixMatching() {
        let context = StickerContext()
        let d = stickerSearch(context: context, searchText: "happy birth", input: .single("en")).start()
        XCTAssertEqual(context.input.queries, ["happy birth"])
        XCTAssertEqual(context.input.completeMatches, [false])
        d.dispose()
    }
    func testShortKeywordUsesExactMatch() {
        let context = StickerContext()
        let d = stickerSearch(context: context, searchText: "hi", input: .single("en")).start()
        XCTAssertEqual(context.input.completeMatches, [true])
        d.dispose()
    }
    func testLiteralEmojiSearchHasNoTextQuery() {
        let context = StickerContext()
        context.input.results = [["👍🏽"]]
        let d = stickerSearch(context: context, searchText: "👍🏽", input: .single("en")).start()
        XCTAssertNil(context.engine.requests[0].query)
        XCTAssertEqual(context.engine.requests[0].emoticons, ["👍"])
        d.dispose()
    }
    func testEnglishFallbackUpdatesStickerMatches() {
        let context = StickerContext()
        context.input.results = [[], ["🎂", "🎉"]]
        let d = stickerSearch(context: context, searchText: "happy birthday", input: .single("ru")).start()
        XCTAssertEqual(context.engine.requests.last?.emoticons, ["🎂", "🎉"])
        d.dispose()
    }
}

final class RequestTrackerTests: XCTestCase {
    func testInFlightRequestAndCompletedPageAreSuppressed() {
        var tracker = PanelSearchRequestTracker<Int>()
        let first = tracker.begin(key: 1, query: "happy birthday", offset: "")!
        XCTAssertNil(tracker.begin(key: 1, query: "happy birthday", offset: ""))
        XCTAssertEqual(tracker.finish(first, nextOffset: "next")?.nextOffset, "next")
        XCTAssertNil(tracker.begin(key: 1, query: "happy birthday", offset: ""))
    }
    func testCursorCyclesTerminate() {
        var tracker = PanelSearchRequestTracker<Int>()
        let first = tracker.begin(key: 1, query: "a", offset: "a")!
        XCTAssertEqual(tracker.finish(first, nextOffset: "b")?.nextOffset, "b")
        let second = tracker.begin(key: 1, query: "a", offset: "b")!
        XCTAssertNil(tracker.finish(second, nextOffset: "a")?.nextOffset)
    }
    func testLateCallbackCannotFinishNewIdenticalQuery() {
        var tracker = PanelSearchRequestTracker<Int>()
        let old = tracker.begin(key: 1, query: "a", offset: "")!
        tracker.reset(1)
        let new = tracker.begin(key: 1, query: "a", offset: "")!
        XCTAssertNil(tracker.finish(old, nextOffset: "wrong"))
        XCTAssertEqual(tracker.finish(new, nextOffset: "right")?.nextOffset, "right")
    }
    func testIndependentTabKeys() {
        var tracker = PanelSearchRequestTracker<Int>()
        XCTAssertNotNil(tracker.begin(key: 1, query: "", offset: ""))
        XCTAssertNotNil(tracker.begin(key: 2, query: "", offset: ""))
    }
    func testClearingCachedPagesPreservesInFlightGuard() {
        var tracker = PanelSearchRequestTracker<Int>()
        let request = tracker.begin(key: 1, query: "", offset: "")!
        tracker.clearCompleted(1)
        XCTAssertNil(tracker.begin(key: 1, query: "", offset: ""))
        _ = tracker.finish(request, nextOffset: nil)
        tracker.clearCompleted(1)
        XCTAssertNotNil(tracker.begin(key: 1, query: "", offset: ""))
    }
    func testStableDeduplicationAcrossPages() {
        XCTAssertEqual(panelSearchAppendingUnique([1, 2], [2, 3, 3, 4], id: { $0 }), [1, 2, 3, 4])
    }
    func testNilAndEmptyOffsetTerminate() {
        for offset: String? in [nil, ""] {
            var tracker = PanelSearchRequestTracker<Int>()
            let request = tracker.begin(key: 1, query: "", offset: "")!
            XCTAssertNil(tracker.finish(request, nextOffset: offset)?.nextOffset)
            XCTAssertNil(tracker.finish(request, nextOffset: "late"))
        }
    }
}

final class GifIntegrationTests: XCTestCase {
    func drain(_ duration: TimeInterval = 0.03) {
        let expectation = expectation(description: "main queue")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
    }
    func testTwoWordQueryAndServerNextOffset() {
        let h = GifHarness()
        h.update(.init(state: .Focus, request: "  happy birthday  "))
        drain(0.25)
        XCTAssertEqual(h.context.engine.requests.count, 1)
        XCTAssertEqual(h.context.engine.requests[0].query, "happy birthday")
        XCTAssertEqual(h.state.search?.isLoading, true)
        h.context.engine.requests[0].emit([1, 2], next: "server-page-2")
        drain()
        XCTAssertEqual(h.state.search?.nextOffset, "server-page-2")
        XCTAssertEqual(h.state.search?.isLoading, false)
        h.search(nil, "happy birthday", h.state.search!.nextOffset!)
        drain()
        XCTAssertEqual(h.context.engine.requests[1].offset, "server-page-2")
        h.context.engine.requests[1].emit([2, 3, 3], next: "")
        drain()
        XCTAssertEqual(h.state.search?.items.count, 3)
        XCTAssertNil(h.state.search?.nextOffset)
    }
    func testRapidTypingOnlySubscribesLatestPhrase() {
        let h = GifHarness()
        for query in ["h", "happy", "happy b", "happy birthday"] {
            h.update(.init(state: .Focus, request: query))
        }
        drain(0.25)
        XCTAssertEqual(h.context.engine.requests.map { $0.query }, ["happy birthday"])
    }
    func testChangingQueryCancelsOldAndRejectsLateResults() {
        let h = GifHarness()
        h.update(.init(state: .Focus, request: "red heart"))
        drain(0.25)
        let old = h.context.engine.requests[0]
        h.update(.init(state: .Focus, request: "happy birthday"))
        XCTAssertTrue(old.disposed)
        old.emit([99], next: "bad")
        drain(0.25)
        XCTAssertEqual(h.state.search?.items.count, 0)
        h.context.engine.requests[1].emit([1], next: "good")
        drain()
        XCTAssertEqual(h.state.search?.nextOffset, "good")
    }
    func testRepeatedQueryDoesNotResetResultsOrStartNetwork() {
        let h = GifHarness()
        h.update(.init(state: .Focus, request: "red heart"))
        drain(0.25)
        h.context.engine.requests[0].emit([1], next: "next")
        drain()
        h.update(.init(state: .Focus, request: "red heart "))
        drain(0.25)
        XCTAssertEqual(h.context.engine.requests.count, 1)
        XCTAssertEqual(h.state.search?.items.count, 1)
    }
    func testEmptyOrClosedSearchCancelsRequest() {
        for state in [SearchState(state: .Focus, request: " \n "), SearchState(state: .None, request: "red heart")] {
            let h = GifHarness()
            h.update(.init(state: .Focus, request: "red heart"))
            h.update(state)
            drain(0.25)
            XCTAssertTrue(h.context.engine.requests.isEmpty)
            XCTAssertNil(h.state.search)
        }
    }
    func testScrollStormHasOneRequestPerPage() {
        let h = GifHarness()
        for _ in 0..<1000 { h.search(.trending, "", "") }
        drain()
        XCTAssertEqual(h.context.engine.requests.count, 1)
        h.context.engine.requests[0].emit([1], next: "page2")
        drain()
        for _ in 0..<1000 { h.search(.trending, "", "page2") }
        drain()
        XCTAssertEqual(h.context.engine.requests.count, 2)
    }
    func testEvictedTabCanReload() {
        let h = GifHarness()
        h.search(.trending, "", "")
        drain()
        h.context.engine.requests[0].emit([1], next: "")
        drain()
        _ = h.stateValue.modify { state in var state = state; state.entries = [:]; return state }
        h.search(.trending, "", "")
        drain()
        XCTAssertEqual(h.context.engine.requests.count, 2)
    }
    func testCompletionWithoutResultEndsLoading() {
        let h = GifHarness()
        h.update(.init(state: .Focus, request: "red heart"))
        drain(0.25)
        h.context.engine.requests[0].subscriber.putCompletion()
        drain()
        XCTAssertEqual(h.completedCount, 1)
        XCTAssertEqual(h.state.search?.isLoading, false)
        XCTAssertNil(h.state.search?.nextOffset)
    }
    func testBackgroundTabDoesNotEndTextLoading() {
        let h = GifHarness()
        h.update(.init(state: .Focus, request: "red heart"))
        h.search(.trending, "", "")
        drain()
        h.context.engine.requests[0].emit([1], next: "")
        drain()
        XCTAssertEqual(h.completedCount, 0)
    }
}

final class EmojiIndexTests: XCTestCase {
    func testVariationSelectors() {
        let index = PanelEmojiSearchIndex(["❤️"])
        XCTAssertTrue(index.contains("❤"))
        XCTAssertTrue(index.contains("❤︎"))
        XCTAssertFalse(index.contains("💙"))
    }
    func testSkinToneAliases() {
        let index = PanelEmojiSearchIndex(["👍"])
        for value in ["👍", "👍🏻", "👍🏼", "👍🏽", "👍🏾", "👍🏿"] { XCTAssertTrue(index.contains(value)) }
    }
    func testZWJGenderAndFamiliesRemainDistinct() {
        let index = PanelEmojiSearchIndex(["👩‍💻", "👨‍👩‍👧"])
        XCTAssertTrue(index.contains("👩🏽‍💻"))
        XCTAssertFalse(index.contains("👨‍💻"))
        XCTAssertFalse(index.contains("👨‍👩‍👦"))
        XCTAssertFalse(index.contains("💻"))
    }
    func testEmptyIndex() { XCTAssertFalse(PanelEmojiSearchIndex([]).contains("😀")) }
    func testCanonicalMembershipMatchesLinearReference() {
        let values = (0..<100).map { String(UnicodeScalar(0x1f600 + $0)!) }
        let index = PanelEmojiSearchIndex(values)
        for i in 0..<1000 {
            let value = String(UnicodeScalar(0x1f600 + i)!)
            XCTAssertEqual(index.contains(value), values.contains(value))
        }
    }
}

final class EmojiIntegrationTests: XCTestCase {
    func drain(_ duration: TimeInterval = 0.2) {
        let done = expectation(description: "search queue")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { done.fulfill() }
        wait(for: [done], timeout: 2)
    }
    func testPhraseNormalizationAndDuplicateSuppression() {
        let h = EmojiHarness()
        var subscribed: [String] = []
        h.context.input.factory = { query in Signal { subscriber in
            subscribed.append(query)
            subscriber.putNext(["❤️"])
            subscriber.putCompletion()
            return EmptyDisposable
        } }
        let d = h.signal().start()
        h.searchValue.set(.init(state: .Focus, request: " RED\tHEA  "))
        drain()
        h.searchValue.set(.init(state: .Focus, request: "red hea"))
        drain()
        XCTAssertEqual(subscribed, ["red hea"])
        d.dispose()
    }
    func testLatestQueryCancelsOldImmediatelyDuringDebounce() {
        let h = EmojiHarness()
        var callbacks: [String: Subscriber<[String], NoError>] = [:]
        var cancelled: [String] = []
        var values: [[String]?] = []
        h.context.input.factory = { query in Signal { subscriber in
            callbacks[query] = subscriber
            return ActionDisposable { cancelled.append(query) }
        } }
        let d = h.signal().start(next: { values.append($0) })
        h.searchValue.set(.init(state: .Focus, request: "red heart"))
        drain()
        h.searchValue.set(.init(state: .Focus, request: "happy birthday"))
        XCTAssertEqual(cancelled, ["red heart"])
        callbacks["red heart"]?.putNext(["wrong"])
        drain()
        callbacks["happy birthday"]?.putNext(["🎂"])
        XCTAssertEqual(values.compactMap { $0 }, [["🎂"]])
        d.dispose()
    }
    func testCategoryBypassesKeywordSearch() {
        let h = EmojiHarness()
        var values: [[String]?] = []
        let d = h.signal().start(next: { values.append($0) })
        h.statePromise.set(.init(selectedEmojiCategory: .init(identifiers: ["❤️", "💟"])))
        h.searchValue.set(.init(state: .None, request: "❤️💟"))
        drain()
        XCTAssertEqual(values.last!, ["❤️", "💟"])
        XCTAssertTrue(h.context.input.queries.isEmpty)
        d.dispose()
    }
    func testEmptyQueryClearsPendingResults() {
        let h = EmojiHarness()
        var values: [[String]?] = []
        let d = h.signal().start(next: { values.append($0) })
        h.searchValue.set(.init(state: .Focus, request: "red heart"))
        h.searchValue.set(.init(state: .Focus, request: " \n "))
        drain()
        XCTAssertNil(values.last!)
        d.dispose()
    }
    func testStickerScrollingDoesNotRestartActiveSearch() {
        let h = EmojiHarness()
        h.searchValue.set(.init(state: .Focus, request: "red heart"))
        var values: [(String, Position, EmojiCategory?)] = []
        let d = h.stickerInputs().start(next: { values.append($0) })
        drain(0.03)
        for i in 0..<100 { h.position.set(.scroll(i)) }
        drain(0.03)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0].1, .initial)
        d.dispose()
    }
    func testBrowsingStillRespondsToScroll() {
        let h = EmojiHarness()
        var values: [Position] = []
        let d = h.stickerInputs().start(next: { values.append($0.1) })
        drain(0.03)
        h.position.set(.scroll(5))
        drain(0.03)
        XCTAssertEqual(values, [.initial, .scroll(5)])
        d.dispose()
    }
    func testChangingCategoryWithSameQueryIsNotDeduplicated() {
        let h = EmojiHarness()
        var values: [EmojiCategory?] = []
        let d = h.stickerInputs().start(next: { values.append($0.2) })
        drain(0.03)
        h.statePromise.set(.init(selectedEmojiCategory: .init(identifiers: ["❤️"])))
        drain(0.03)
        h.statePromise.set(.init(selectedEmojiCategory: .init(identifiers: ["👍"])))
        drain(0.03)
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values.last??.identifiers, ["👍"])
        d.dispose()
    }
}

final class StickerResultsIntegrationTests: XCTestCase {
    func drain() {
        let done = expectation(description: "remote debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { done.fulfill() }
        wait(for: [done], timeout: 2)
    }
    func testLocalPacksAppearBeforeRemoteCompletes() {
        let context = StickerContext()
        context.engine.localSets = .single(.init(entries: [1]))
        context.engine.remoteSets = Signal { _ in EmptyDisposable }
        var values: [StickerPacksSearchData] = []
        let d = stickerResults(context: context, query: "red heart").start(next: { values.append($0.searchData) })
        XCTAssertEqual(values.first?.sets.entries, [1])
        XCTAssertEqual(values.first?.loading, false)
        d.dispose()
    }
    func testCategoryUsesCategoryAPIWithoutKeywordOrPackSearch() {
        let context = StickerContext()
        let category = EmojiCategory(identifiers: ["❤️", "💟"])
        var values: [StickerPacksSearchData] = []
        let d = stickerResults(context: context, query: "❤️💟", category: category).start(next: { values.append($0.searchData) })
        drain()
        XCTAssertEqual(context.engine.categories, [category])
        XCTAssertTrue(context.engine.setQueries.isEmpty)
        XCTAssertTrue(context.input.queries.isEmpty)
        XCTAssertEqual(values.last?.emojiRelated.map { $0.id }, [42])
        XCTAssertEqual(values.last?.loading, false)
        d.dispose()
    }
    func testEmptyResultsStopLoadingAfterBothSourcesComplete() {
        let context = StickerContext()
        var values: [Bool] = []
        let d = stickerResults(context: context, query: "red angry").start(next: { values.append($0.searchData.loading) })
        XCTAssertEqual(values.first, true)
        drain()
        XCTAssertEqual(values.last, false)
        d.dispose()
    }
}

final class InputSourceIntegrationTests: XCTestCase {
    func testLiteralEmojiSkipsDictionary() {
        let engine = StickerEngine()
        var result: [String] = []
        let d = InputSources(languages: ["en"]).searchEmoji(postbox: 0, engine: engine, sharedContext: SharedContext(accountManager: 1), query: "👍🏽 ❤️ 👍🏽", completeMatch: false, checkPrediction: false).start(next: { result = $0 })
        XCTAssertEqual(result, ["👍🏽", "❤️"])
        XCTAssertTrue(engine.keywordRequests.isEmpty)
        d.dispose()
    }
    func testPhraseReachesIndexAsOneNormalizedRequest() {
        let engine = StickerEngine()
        engine.keywordResults = [.init(keyword: "red heart", emoticons: ["❤️"])]
        var result: [String] = []
        let d = InputSources(languages: ["en"]).searchEmoji(postbox: 0, engine: engine, sharedContext: SharedContext(accountManager: 1), query: " RED\n HEART ", completeMatch: false, checkPrediction: false).start(next: { result = $0 })
        XCTAssertEqual(engine.keywordRequests, ["red heart"])
        XCTAssertEqual(result, ["❤️"])
        d.dispose()
    }
    func testNoPhraseMatchDoesNotIssueIndividualWordQueries() {
        let engine = StickerEngine()
        let d = InputSources(languages: ["en"]).searchEmoji(postbox: 0, engine: engine, sharedContext: SharedContext(accountManager: 1), query: "red angry", completeMatch: false, checkPrediction: false).start()
        XCTAssertEqual(engine.keywordRequests, ["red angry"])
        d.dispose()
    }
    func testPredictionSettingDoesNotDisableExplicitSearch() {
        for checkPrediction in [true, false] {
            let engine = StickerEngine()
            let d = InputSources(languages: ["en"]).searchEmoji(postbox: 0, engine: engine, sharedContext: SharedContext(accountManager: 0), query: "happy birthday", completeMatch: false, checkPrediction: checkPrediction).start()
            XCTAssertEqual(engine.keywordRequests.count, checkPrediction ? 0 : 1)
            d.dispose()
        }
    }
}

final class ColdStartTests: XCTestCase {
    func testEmojiSearchStartsBeforeFirstStateUpdate() {
        let h = EmojiHarness()
        var values: [[String]?] = []
        let d = h.signal().start(next: { values.append($0) })
        XCTAssertEqual(values.count, 1)
        if let first = values.first { XCTAssertNil(first) }
        d.dispose()
    }
    func testStickerSearchStartsBeforeFirstStateUpdate() {
        let h = EmojiHarness(statePromise: makeStickerStatePromise())
        let ready = expectation(description: "initial sticker inputs unblock loading")
        let d = (h.stickerInputs() |> take(1)).start(next: { query, position, category in
            XCTAssertEqual(query, "")
            XCTAssertEqual(position, .initial)
            XCTAssertNil(category)
            ready.fulfill()
        })
        wait(for: [ready], timeout: 0.5)
        d.dispose()
    }
    func testInitialSearchCanPublishFirstStateWithoutFeedbackLoop() {
        let h = EmojiHarness()
        var count = 0
        let d = h.signal().start(next: { _ in
            count += 1
            if count == 1 { h.statePromise.set(CategoryState()) }
        })
        XCTAssertEqual(count, 1)
        h.statePromise.set(.init(selectedEmojiCategory: .init(identifiers: ["❤️"])))
        XCTAssertEqual(count, 2)
        d.dispose()
    }
}

final class SearchPresentationTests: XCTestCase {
    func testBrowsingNeverShowsSearchStatus() {
        for loading in [false, true] {
            for results in [false, true] {
                XCTAssertEqual(PanelSearchPresentation.resolve(isSearching: false, isLoading: loading, hasResults: results), .hidden)
            }
        }
    }
    func testResultsRemainVisibleDuringPagination() {
        XCTAssertEqual(PanelSearchPresentation.resolve(isSearching: true, isLoading: true, hasResults: true), .hidden)
        XCTAssertEqual(PanelSearchPresentation.resolve(isSearching: true, isLoading: false, hasResults: true), .hidden)
    }
    func testNoResultsDistinguishesLoadingFromEmpty() {
        XCTAssertEqual(PanelSearchPresentation.resolve(isSearching: true, isLoading: true, hasResults: false), .loading)
        XCTAssertEqual(PanelSearchPresentation.resolve(isSearching: true, isLoading: false, hasResults: false), .empty)
    }
    func testEmojiQueryEmitsLoadingBeforeEmptyResult() {
        let h = EmojiHarness()
        var values: [PanelEmojiSearchResult] = []
        let done = expectation(description: "empty search completed")
        let d = h.searchResults().start(next: { value in
            values.append(value)
            if value.values == [] && !value.isLoading { done.fulfill() }
        })
        h.searchValue.set(.init(state: .Focus, request: "missing emoji"))
        XCTAssertEqual(values.last, .init(values: [], isLoading: true))
        wait(for: [done], timeout: 1)
        XCTAssertEqual(values.last, .init(values: [], isLoading: false))
        d.dispose()
    }
    func testClearingQueryRemovesLoadingImmediately() {
        let h = EmojiHarness()
        var values: [PanelEmojiSearchResult] = []
        let d = h.searchResults().start(next: { values.append($0) })
        h.searchValue.set(.init(state: .Focus, request: "missing emoji"))
        h.searchValue.set(.init(state: .Focus, request: ""))
        XCTAssertEqual(values.last, .init(values: nil, isLoading: false))
        d.dispose()
    }
    func testPlaceholderFramesFitSmallAndLargePanels() {
        for kind in [PanelSearchPlaceholderKind.emoji, .stickers, .gifs] {
            for size in [CGSize.zero, CGSize(width: 60, height: 30), CGSize(width: 280, height: 180), CGSize(width: 350, height: 448), CGSize(width: 700, height: 900)] {
                for frame in kind.frames(in: size) {
                    XCTAssertTrue(CGRect(origin: .zero, size: size).contains(frame))
                    XCTAssertGreaterThan(frame.width, 0)
                    XCTAssertGreaterThan(frame.height, 0)
                }
            }
        }
    }
}

final class StickerSearchContentTests: XCTestCase {
    func testWhitespaceRowDoesNotHideEmptyState() {
        XCTAssertFalse(stickerSearchHasResults(TableView(items: [GeneralRowItem()])))
    }
    func testActualStickerRowHidesEmptyState() {
        XCTAssertTrue(stickerSearchHasResults(TableView(items: [GeneralRowItem(), StickerPackPanelRowItem()])))
    }
}

final class EmojiStateEqualityTests: XCTestCase {
    func testLoadingToEmptyIsNotSuppressedByStateEquality() {
        var loading = EmojiStateEqualityFixture()
        loading.searchLoading = true
        let empty = EmojiStateEqualityFixture()
        XCTAssertNotEqual(loading, empty)
        let promise = ValuePromise(loading, ignoreRepeated: true)
        var updates = 0
        let d = promise.get().start(next: { _ in updates += 1 })
        promise.set(empty)
        XCTAssertEqual(updates, 2)
        d.dispose()
    }
}
