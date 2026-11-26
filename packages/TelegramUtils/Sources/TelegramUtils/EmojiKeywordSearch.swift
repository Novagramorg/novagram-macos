import Foundation
import SwiftSignalKit

struct EmojiKeywordSearchEntry {
    let keyword: String
    let emoticons: [String]
}

func normalizedEmojiKeywordQuery(_ query: String) -> String {
    return query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
}

func searchEmojiKeywordMatches(query: String, languageCodes: [String], completeMatch: Bool, search: @escaping (String, String, Bool) -> Signal<[EmojiKeywordSearchEntry], NoError>) -> Signal<[String], NoError> {
    let query = normalizedEmojiKeywordQuery(query)
    guard !query.isEmpty else { return .single([]) }
    var seenLanguages = Set<String>()
    let languages = languageCodes.filter {
        let key = $0.lowercased().replacingOccurrences(of: "_", with: "-")
        return !key.isEmpty && key != "emoji" && seenLanguages.insert(key).inserted
    }
    let local: Signal<[[EmojiKeywordSearchEntry]], NoError>
    if languages.isEmpty {
        local = .single([])
    } else {
        local = combineLatest(languages.map { search($0, query, completeMatch) })
    }
    let entries = local |> mapToSignal { results -> Signal<[[EmojiKeywordSearchEntry]], NoError> in
        if languages.contains(where: { $0.lowercased().hasPrefix("en") }) {
            return .single(results)
        }
        return .single(results) |> then(search("en-US", query, completeMatch || query.count < 3) |> map { results + [$0] })
    }
    return entries |> map { groups in
        var seen = Set<String>()
        var result: [String] = []
        for group in groups {
            for entry in group {
                if completeMatch && normalizedEmojiKeywordQuery(entry.keyword) != query { continue }
                for emoji in entry.emoticons where seen.insert(emoji).inserted {
                    result.append(emoji)
                }
            }
        }
        return result
    } |> distinctUntilChanged
}
