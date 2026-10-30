import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import NovagramSearchKit

public enum NovagramChatSearchFilter {
    public typealias Search = (String, SearchMessagesState?) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError>

    private struct Progress {
        let result: SearchMessagesResult
        let matched: Int
        let finished: Bool
        let checked: [MessageId: Bool]
    }

    private static let progress = NovagramChatSearchProgressCache<SearchMessagesState, Progress>()

    public static func wrap(query: String, state: SearchMessagesState?, search: @escaping Search) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError> {
        let parsed = NovagramChatSearchQuery(query, isFeaturesEnabled: NovagramSearchFeatures.isEnabled)
        guard let matcher = NovagramChatSearchMatcher(parsed) else {
            return search(parsed.serverQuery, state)
        }
        let previous = state.flatMap { progress.value(query: query, state: $0) }
        if let state = state, let previous = previous, previous.finished {
            return .single((previous.result, state))
        }
        return page(matcher, state: state, previousMatched: previous?.matched ?? 0, checked: previous?.checked ?? [:], extraPages: 0, search: search)
    }

    private static func page(_ matcher: NovagramChatSearchMatcher, state: SearchMessagesState?, previousMatched: Int, checked: [MessageId: Bool], extraPages: Int, search: @escaping Search) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError> {
        return search(matcher.query.serverQuery, state)
        |> deliverOn(Queue.concurrentDefaultQueue())
        |> mapToSignal { result, updatedState -> Signal<(SearchMessagesResult, SearchMessagesState), NoError> in
            guard let filtered = matcher.filterPage(result.messages, id: { $0.id }, text: { $0.text }, checked: checked) else {
                return .complete()
            }
            let finished = matcher.isFinished(serverCompleted: result.completed, scannedCount: result.messages.count, timedOut: filtered.timedOut, stateUnchanged: updatedState == state)
            if matcher.shouldReadNextPage(matched: filtered.kept.count, previousMatched: previousMatched, isFinished: finished, extraPagesRead: extraPages) {
                return page(matcher, state: updatedState, previousMatched: previousMatched, checked: filtered.checked, extraPages: extraPages + 1, search: search)
            }
            let kept = SearchMessagesResult(
                messages: filtered.kept,
                readStates: result.readStates,
                threadInfo: result.threadInfo,
                totalCount: Int32(filtered.kept.count),
                completed: finished
            )
            progress.store(Progress(result: kept, matched: filtered.kept.count, finished: finished, checked: filtered.checked), query: matcher.query.typed, state: updatedState)
            return .single((kept, updatedState))
        }
    }
}
