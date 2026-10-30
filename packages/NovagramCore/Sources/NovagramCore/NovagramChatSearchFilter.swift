import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

public enum NovagramChatSearchFilter {
    public typealias Search = (String, SearchMessagesState?) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError>

    private static let regexPrefix = "re:"
    private static let openingQuotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}", "\u{201E}"]
    private static let closingQuotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}"]
    private static let maxExtraPages = 5
    private static let minimumNewMatches = 10
    private static let maxScannedMessages = 2000
    private static let cacheSize = 8
    private static let regexTimeLimit: CFAbsoluteTime = 0.05
    private static let pageTimeLimit: CFAbsoluteTime = 1

    enum Mode {
        case phrase(String)
        case regex(NSRegularExpression)
        case plain(String)
    }

    private struct Progress {
        let state: SearchMessagesState
        let result: SearchMessagesResult
        let matched: Int
        let finished: Bool
        let checked: [MessageId: Bool]
    }

    private static let lock = NSLock()
    private static var recent: [Progress] = []

    public static func wrap(query: String, state: SearchMessagesState?, search: @escaping Search) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError> {
        guard NovagramSearchFeatures.isEnabled, let mode = mode(for: query) else {
            return search(query, state)
        }
        let matches: (Message) -> Bool
        let serverQuery: String
        let scanLimit: Int?
        switch mode {
        case let .plain(text):
            return search(text, state)
        case let .phrase(phrase):
            serverQuery = phrase
            scanLimit = nil
            matches = { $0.text.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        case let .regex(regex):
            serverQuery = ""
            scanLimit = maxScannedMessages
            matches = { regexMatches(regex, in: $0.text) }
        }
        let previous = state.flatMap(cached(for:))
        if let previous, previous.finished {
            return .single((previous.result, previous.state))
        }
        return page(serverQuery: serverQuery, state: state, previousMatched: previous?.matched ?? 0, checked: previous?.checked ?? [:], extraPages: 0, scanLimit: scanLimit, matches: matches, search: search)
    }

    static func mode(for query: String) -> Mode? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(regexPrefix) {
            let pattern = String(trimmed.dropFirst(regexPrefix.count)).trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty else {
                return nil
            }
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                return .regex(regex)
            }
            return .plain(pattern)
        }
        guard trimmed.count > 2, let first = trimmed.first, let last = trimmed.last, openingQuotes.contains(first), closingQuotes.contains(last) else {
            return nil
        }
        let phrase = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else {
            return nil
        }
        return .phrase(phrase)
    }

    private static func page(serverQuery: String, state: SearchMessagesState?, previousMatched: Int, checked: [MessageId: Bool], extraPages: Int, scanLimit: Int?, matches: @escaping (Message) -> Bool, search: @escaping Search) -> Signal<(SearchMessagesResult, SearchMessagesState), NoError> {
        return search(serverQuery, state)
        |> deliverOn(Queue.concurrentDefaultQueue())
        |> mapToSignal { result, updatedState -> Signal<(SearchMessagesResult, SearchMessagesState), NoError> in
            let deadline = CFAbsoluteTimeGetCurrent() + pageTimeLimit
            var checked = checked
            let kept = result.messages.filter { message in
                if let known = checked[message.id] {
                    return known
                }
                guard CFAbsoluteTimeGetCurrent() < deadline else {
                    return false
                }
                let hit = matches(message)
                checked[message.id] = hit
                return hit
            }
            let timedOut = CFAbsoluteTimeGetCurrent() >= deadline
            let capped = scanLimit.map { result.messages.count >= $0 } ?? false
            let finished = result.completed || capped || timedOut || updatedState == state
            let isShort = kept.count - previousMatched < minimumNewMatches
            if isShort && !finished && extraPages < maxExtraPages {
                return page(serverQuery: serverQuery, state: updatedState, previousMatched: previousMatched, checked: checked, extraPages: extraPages + 1, scanLimit: scanLimit, matches: matches, search: search)
            }
            let filtered = SearchMessagesResult(
                messages: kept,
                readStates: result.readStates,
                threadInfo: result.threadInfo,
                totalCount: Int32(kept.count),
                completed: finished
            )
            remember(Progress(state: updatedState, result: filtered, matched: kept.count, finished: finished, checked: checked))
            return .single((filtered, updatedState))
        }
    }

    private static func regexMatches(_ regex: NSRegularExpression, in text: String) -> Bool {
        let deadline = CFAbsoluteTimeGetCurrent() + regexTimeLimit
        var found = false
        regex.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(text.startIndex..., in: text)) { match, _, stop in
            if match != nil {
                found = true
                stop.pointee = true
            } else if CFAbsoluteTimeGetCurrent() > deadline {
                stop.pointee = true
            }
        }
        return found
    }

    private static func cached(for state: SearchMessagesState) -> Progress? {
        lock.lock()
        defer { lock.unlock() }
        return recent.last(where: { $0.state == state })
    }

    private static func remember(_ progress: Progress) {
        lock.lock()
        defer { lock.unlock() }
        recent.removeAll(where: { $0.state == progress.state })
        recent.append(progress)
        if recent.count > cacheSize {
            recent.removeFirst(recent.count - cacheSize)
        }
    }
}
