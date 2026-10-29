import Foundation

public struct NovagramJobQuery: Equatable {
    public static let maxServerQueries = 5
    static let maxHashtagTerms = 3

    public let raw: String
    public let serverQueries: [String]
    public let hashtagTerms: [String]
    let matcher: NovagramJobQueryMatcher

    public var isEmpty: Bool {
        return serverQueries.isEmpty
    }

    public init(raw: String, serverQueries: [String], hashtagTerms: [String]) {
        self.raw = raw
        self.serverQueries = serverQueries
        self.hashtagTerms = hashtagTerms
        self.matcher = NovagramJobQueryMatcher(syntax: NovagramJobQuerySyntax(raw))
    }

    init(raw: String, serverQueries: [String], hashtagTerms: [String], matcher: NovagramJobQueryMatcher) {
        self.raw = raw
        self.serverQueries = serverQueries
        self.hashtagTerms = hashtagTerms
        self.matcher = matcher
    }

    public static func parse(_ raw: String, expandScripts: Bool = true) -> NovagramJobQuery {
        let syntax = NovagramJobQuerySyntax(raw)
        return NovagramJobQuery(
            raw: raw,
            serverQueries: serverQueries(for: syntax, expandScripts: expandScripts),
            hashtagTerms: hashtagTerms(for: syntax),
            matcher: NovagramJobQueryMatcher(syntax: syntax)
        )
    }

    public static func parse(_ raw: String, languages: Set<NovagramSearchLanguage>, translations: [NovagramSearchLanguage: String]) -> NovagramJobQuery {
        let syntax = NovagramJobQuerySyntax(raw)
        let plan = NovagramSearchConversion.plan(query: raw, languages: languages)
        var variants = NovagramSearchLanguage.allCases.compactMap { plan.transliterations[$0] }
        for language in plan.translationsNeeded {
            if let translated = translatedText(for: language, translations: translations) {
                variants.append(translated)
            }
        }
        let variantSyntaxes = variants.map(NovagramJobQuerySyntax.init)
        return NovagramJobQuery(
            raw: raw,
            serverQueries: capped(branchQueries(syntax) + variantSyntaxes.flatMap(branchQueries)),
            hashtagTerms: hashtagTerms(for: syntax),
            matcher: NovagramJobQueryMatcher(syntax: syntax, alternatives: variantSyntaxes)
        )
    }

    public func matches(_ text: String) -> Bool {
        return matcher.matches(text)
    }

    private static func translatedText(for language: NovagramSearchLanguage, translations: [NovagramSearchLanguage: String]) -> String? {
        switch language {
        case .uzLatin, .uzCyrillic:
            let other: NovagramSearchLanguage = language == .uzLatin ? .uzCyrillic : .uzLatin
            guard let text = translations[language] ?? translations[other] else { return nil }
            return NovagramSearchConversion.transliterate(text, to: language) ?? text
        case .russian, .english:
            return translations[language]
        }
    }

    private static func branchQueries(_ syntax: NovagramJobQuerySyntax) -> [String] {
        return syntax.branches.map { branch -> String in
            (branch.terms.map { $0.text } + branch.phrases).joined(separator: " ")
        }
    }

    private static func capped(_ queries: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for query in queries {
            let key = NovagramJobText.normalized(query)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(query)
        }
        return Array(result.prefix(maxServerQueries))
    }

    static func uzbekScriptVariant(_ query: String) -> String? {
        guard NovagramJobText.otherScriptVariant(query) != nil else { return nil }
        let target: NovagramSearchLanguage = query.contains(where: NovagramJobText.isLatinLetter) ? .uzCyrillic : .uzLatin
        return NovagramSearchConversion.transliterate(query, to: target)?.lowercased()
    }

    private static func serverQueries(for syntax: NovagramJobQuerySyntax, expandScripts: Bool) -> [String] {
        let originals = branchQueries(syntax)
        return capped(originals + (expandScripts ? originals.compactMap(uzbekScriptVariant) : []))
    }

    private static let roleKeywordCharacters: CharacterSet = {
        var set = CharacterSet.letters
        set.formUnion(.decimalDigits)
        set.insert(charactersIn: "+#.")
        return set
    }()

    static func looksLikeRoleKeyword(_ term: String) -> Bool {
        let length = term.count
        guard length >= 2, length <= 32 else { return false }
        guard term.unicodeScalars.allSatisfy({ roleKeywordCharacters.contains($0) }) else { return false }
        return term.contains(where: { $0.isLetter })
    }

    private static func hashtagTerms(for syntax: NovagramJobQuerySyntax) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        let explicit = syntax.branches.flatMap { $0.terms.filter { $0.isHashtag } }
        let implicit = syntax.branches.flatMap { $0.terms.filter { !$0.isHashtag } }
        for term in explicit + implicit {
            let tag = term.text.lowercased()
            guard looksLikeRoleKeyword(tag), !seen.contains(tag) else { continue }
            seen.insert(tag)
            result.append(tag)
        }
        return Array(result.prefix(maxHashtagTerms))
    }
}

struct NovagramJobQuerySyntax {
    struct Term {
        let text: String
        let isHashtag: Bool
    }

    struct Branch {
        var terms: [Term] = []
        var phrases: [String] = []

        var isEmpty: Bool {
            return terms.isEmpty && phrases.isEmpty
        }
    }

    private enum Token {
        case or
        case word(String)
        case phrase(String, negated: Bool)
    }

    private static let openingQuotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}", "\u{00AB}", "\u{201E}"]
    private static let closingQuotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}", "\u{00BB}"]
    private static let orWords: Set<String> = ["yoki", "или", "or", "ёки"]
    private static let edgePunctuation = CharacterSet(charactersIn: ",;:!?()[]{}<>")

    private(set) var branches: [Branch] = []
    private(set) var excludedTerms: [String] = []
    private(set) var excludedPhrases: [String] = []

    init(_ raw: String) {
        var current = Branch()
        for token in NovagramJobQuerySyntax.tokenize(raw) {
            switch token {
            case .or:
                if !current.isEmpty {
                    branches.append(current)
                }
                current = Branch()
            case let .phrase(text, negated):
                let words = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                guard !words.isEmpty else { continue }
                if negated {
                    excludedPhrases.append(words)
                } else {
                    current.phrases.append(words)
                }
            case let .word(word):
                if NovagramJobQuerySyntax.orWords.contains(word.lowercased()) {
                    if !current.isEmpty {
                        branches.append(current)
                    }
                    current = Branch()
                } else if word.hasPrefix("-") {
                    let excluded = NovagramJobQuerySyntax.clean(String(word.dropFirst()))
                    if !excluded.isEmpty {
                        excludedTerms.append(excluded)
                    }
                } else if word.hasPrefix("#") {
                    let tag = NovagramJobQuerySyntax.clean(String(word.drop(while: { $0 == "#" })))
                    if !tag.isEmpty {
                        current.terms.append(Term(text: tag, isHashtag: true))
                    }
                } else {
                    let term = NovagramJobQuerySyntax.clean(word)
                    if !term.isEmpty {
                        current.terms.append(Term(text: term, isHashtag: false))
                    }
                }
            }
        }
        if !current.isEmpty {
            branches.append(current)
        }
    }

    private static func clean(_ word: String) -> String {
        return word.trimmingCharacters(in: edgePunctuation)
    }

    private static func tokenize(_ raw: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(raw)
        var word = ""
        func flushWord() {
            if !word.isEmpty {
                tokens.append(.word(word))
                word = ""
            }
        }
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let startsPhrase = openingQuotes.contains(character) && (word.isEmpty || word == "-")
            if startsPhrase {
                let negated = word == "-"
                word = ""
                var end = index + 1
                while end < characters.count && !closingQuotes.contains(characters[end]) {
                    end += 1
                }
                tokens.append(.phrase(String(characters[(index + 1)..<min(end, characters.count)]), negated: negated))
                index = end + 1
                continue
            }
            if character == "|" {
                flushWord()
                tokens.append(.or)
            } else if character.isWhitespace {
                flushWord()
            } else {
                word.append(character)
            }
            index += 1
        }
        flushWord()
        return tokens
    }
}

struct NovagramJobQueryMatcher: Equatable {
    struct Term: Equatable {
        let forms: [String]

        init(_ text: String) {
            let normalized = NovagramJobText.normalized(text)
            var forms = [normalized]
            if let variant = NovagramJobText.otherScriptVariant(text).map(NovagramJobText.normalized), !variant.isEmpty, variant != normalized {
                forms.append(variant)
            }
            self.forms = forms
        }

        func matchesWordStart(in text: String) -> Bool {
            return forms.contains(where: { NovagramJobText.containsAtWordStart(text, $0) })
        }

        func matchesSubstring(in text: String) -> Bool {
            return forms.contains(where: { text.contains($0) })
        }
    }

    struct Branch: Equatable {
        let terms: [Term]
        let phrases: [Term]

        func matches(_ text: String) -> Bool {
            return terms.allSatisfy { $0.matchesWordStart(in: text) } && phrases.allSatisfy { $0.matchesSubstring(in: text) }
        }
    }

    let branches: [Branch]
    let excludedTerms: [Term]
    let excludedPhrases: [Term]

    init(syntax: NovagramJobQuerySyntax, alternatives: [NovagramJobQuerySyntax] = []) {
        branches = ([syntax] + alternatives).flatMap { $0.branches }.map { Branch(terms: $0.terms.map { Term($0.text) }, phrases: $0.phrases.map(Term.init)) }
        excludedTerms = syntax.excludedTerms.map(Term.init)
        excludedPhrases = syntax.excludedPhrases.map(Term.init)
    }

    func matches(_ text: String) -> Bool {
        if branches.isEmpty && excludedTerms.isEmpty && excludedPhrases.isEmpty {
            return true
        }
        let normalized = NovagramJobText.normalized(text)
        if excludedTerms.contains(where: { $0.matchesWordStart(in: normalized) }) {
            return false
        }
        if excludedPhrases.contains(where: { $0.matchesSubstring(in: normalized) }) {
            return false
        }
        return branches.isEmpty || branches.contains(where: { $0.matches(normalized) })
    }
}
