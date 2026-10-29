import Foundation

enum NovagramJobContactParser {
    static let maxContacts = 5

    private static let linkRegex = NovagramJobRegex.make("(?:https?://|(?<![\\w./@])(?:t\\.me|telegram\\.me)/)[^\\s<>\"'«»()\\[\\]]+", caseInsensitive: true)
    private static let emailRegex = NovagramJobRegex.make("(?<![\\w.%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}")
    private static let usernameRegex = NovagramJobRegex.make("(?<![\\w@./])@([A-Za-z][A-Za-z0-9_]{4,31})(?![\\w@])(?!\\.[A-Za-z]{2,})")

    static let internationalPhoneRegex = NovagramJobRegex.make("(?<![\\d+])(?:\\+\\s?998|998)[\\s\\-()]*\\d{2}[\\s\\-()]*\\d{3}[\\s\\-]*\\d{2}[\\s\\-]*\\d{2}(?!\\d)|(?<![\\d+])\\+\\s?7[\\s\\-()]*\\d{3}[\\s\\-()]*\\d{3}[\\s\\-]*\\d{2}[\\s\\-]*\\d{2}(?!\\d)")
    static let localPhoneRegex = NovagramJobRegex.make("(?<![\\d+.,])\\(?(?:20|33|50|55|61|62|65|66|67|69|70|71|72|73|74|75|76|77|78|79|88|90|91|93|94|95|97|98|99)\\)?[\\s\\-]?\\d{3}[\\s\\-]?\\d{2}[\\s\\-]?\\d{2}(?!\\d)")

    static var phoneRegexes: [NSRegularExpression] {
        return [internationalPhoneRegex, localPhoneRegex]
    }

    private static let trailingLinkPunctuation = CharacterSet(charactersIn: ".,;:!?")

    static func normalizedPhone(_ raw: String) -> String? {
        let digits = String(raw.filter { $0.isASCII && $0.isNumber })
        if digits.count == 12 && digits.hasPrefix("998") {
            return "+" + digits
        }
        if digits.count == 11 && digits.hasPrefix("7") {
            return "+" + digits
        }
        if digits.count == 9 {
            return "+998" + digits
        }
        return nil
    }

    static func contacts(_ text: String) -> [NovagramJobContact] {
        var found: [(range: NSRange, contact: NovagramJobContact)] = []
        for match in NovagramJobRegex.matches(linkRegex, in: text) {
            guard let raw = NovagramJobRegex.substring(text, match.range) else { continue }
            let link = raw.trimmingCharacters(in: trailingLinkPunctuation)
            found.append((match.range, .link(link)))
        }
        for match in NovagramJobRegex.matches(emailRegex, in: text) {
            guard let email = NovagramJobRegex.substring(text, match.range) else { continue }
            found.append((match.range, .email(email.lowercased())))
        }
        for match in NovagramJobRegex.matches(usernameRegex, in: text) {
            guard let name = NovagramJobRegex.substring(text, match.range(at: 1)) else { continue }
            found.append((match.range, .username(name)))
        }
        for regex in phoneRegexes {
            for match in NovagramJobRegex.matches(regex, in: text) {
                guard let raw = NovagramJobRegex.substring(text, match.range), let phone = normalizedPhone(raw) else { continue }
                found.append((match.range, .phone(phone)))
            }
        }
        found.sort { lhs, rhs in
            lhs.range.location == rhs.range.location ? lhs.range.length > rhs.range.length : lhs.range.location < rhs.range.location
        }
        var result: [NovagramJobContact] = []
        var seenKeys = Set<String>()
        var coveredUntil = 0
        for item in found where item.range.location >= coveredUntil {
            coveredUntil = item.range.location + item.range.length
            let key = dedupeKey(item.contact)
            guard seenKeys.insert(key).inserted else { continue }
            result.append(item.contact)
            if result.count == maxContacts {
                break
            }
        }
        return result
    }

    private static func dedupeKey(_ contact: NovagramJobContact) -> String {
        switch contact {
        case let .username(value):
            return "u:" + value.lowercased()
        case let .phone(value):
            return "p:" + value
        case let .email(value):
            return "e:" + value.lowercased()
        case let .link(value):
            return "l:" + value.lowercased()
        }
    }
}
