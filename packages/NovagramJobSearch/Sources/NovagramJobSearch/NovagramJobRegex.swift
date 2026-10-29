import Foundation

enum NovagramJobRegex {
    static let wordStart = "(?<![\\p{L}\\p{N}_'])"
    static let wordEnd = "(?![\\p{L}\\p{N}_])"

    static func make(_ pattern: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        } catch {
            preconditionFailure("Invalid NovagramJob pattern \(pattern): \(error)")
        }
    }

    static func alternation(_ literals: [String]) -> String {
        var seen = Set<String>()
        return literals
            .map(NovagramJobText.normalized)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
    }

    static func wordPrefix(_ literals: [String]) -> NSRegularExpression {
        return make(wordStart + "(?:" + alternation(literals) + ")")
    }

    static func fullRange(_ text: String) -> NSRange {
        return NSRange(location: 0, length: text.utf16.count)
    }

    static func matches(_ regex: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        return regex.matches(in: text, options: [], range: fullRange(text))
    }

    static func firstMatch(_ regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        return regex.firstMatch(in: text, options: [], range: fullRange(text))
    }

    static func contains(_ regex: NSRegularExpression, in text: String) -> Bool {
        return firstMatch(regex, in: text) != nil
    }

    static func substring(_ text: String, _ range: NSRange) -> String? {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
