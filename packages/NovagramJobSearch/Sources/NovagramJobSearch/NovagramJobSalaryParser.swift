import Foundation

enum NovagramJobSalaryParser {
    static let maxFragmentLength = 40

    private struct Amount {
        let range: NSRange
        let numberText: String
        let number: Double
        let multiplier: Double?
        let isMillion: Bool
        let currency: NovagramJobCurrency?
        let hasPlus: Bool

        var looksLikeYear: Bool {
            return numberText.count == 4 && numberText.allSatisfy({ $0.isNumber }) && (1950...2035).contains(number)
        }
    }

    private static let numberPattern = "\\d{1,3}(?:[ \\u00A0,.']\\d{3})+(?!\\d)|\\d+(?:[.,]\\d+)?"
    private static let multiplierPattern = "mln|млн|millions?|миллион\\p{L}*|ming|минг|тыс\\p{L}*|k|к"
    private static let currencyPattern = "\\$|€|₽|usd|у\\.\\s?е\\.?|y\\.\\s?e\\.?|долл\\p{L}*\\.?|dollar\\p{L}*|so'm|som|sum|сўм|сум|uzs|rub\\p{L}*|руб\\p{L}*\\.?|eur|euro|евро"
    private static let prefixCurrencyPattern = "\\$|€|₽|usd|uzs|eur"

    private static let amountRegex = NovagramJobRegex.make(
        "(?<![\\p{L}\\p{N}.,+])(?:(?<pre>" + prefixCurrencyPattern + ")\\s?)?(?<num>" + numberPattern + ")"
            + "(?:\\s{0,2}(?<mult>(?:" + multiplierPattern + ")\\.?)(?![\\p{L}]))?"
            + "(?:\\s{0,2}(?<post>" + currencyPattern + ")(?![\\p{L}']))?"
            + "(?<plus>\\s?\\+)?",
        caseInsensitive: true
    )
    private static let groupedNumberRegex = NovagramJobRegex.make("^\\d{1,3}(?:[ \\u00A0,.']\\d{3})+$")
    private static let connectorRegex = NovagramJobRegex.make("^\\s*(?:-|–|—|~|\\.{2,3}|до|to|dan|дан)\\s*$", caseInsensitive: true)
    private static let minPrefixRegex = NovagramJobRegex.make("(?:^|[^\\p{L}])(?:от|from|starting at|starting from|min\\.?)\\s*:?\\s*$", caseInsensitive: true)
    private static let maxPrefixRegex = NovagramJobRegex.make("(?:^|[^\\p{L}])(?:до|up to|max\\.?)\\s*:?\\s*$", caseInsensitive: true)
    private static let minSuffixRegex = NovagramJobRegex.make("^\\s*(?:dan|дан)(?![\\p{L}])", caseInsensitive: true)
    private static let maxSuffixRegex = NovagramJobRegex.make("^\\s*(?:gacha|гача)(?![\\p{L}])", caseInsensitive: true)

    private static let maskRegexes: [NSRegularExpression] = NovagramJobContactParser.phoneRegexes + [
        NovagramJobRegex.make("(?<!\\d)\\d{1,2}[./-]\\d{1,2}[./-]\\d{2,4}(?!\\d)"),
        NovagramJobRegex.make("(?<!\\d)\\d{4}-\\d{2}-\\d{2}(?!\\d)"),
        NovagramJobRegex.make("(?<![\\d.,])\\d{1,2}[:.]\\d{2}\\s*[-–—]\\s*\\d{1,2}[:.]\\d{2}(?!\\d)"),
        NovagramJobRegex.make("(?<!\\d)\\d{1,2}:\\d{2}(?!\\d)"),
        NovagramJobRegex.make(
            "(?<![\\d.,])\\d+(?:[.,]\\d+)?(?:\\s*[-–—]\\s*\\d+)?\\s*-?\\s*\\+?\\s*(?:yil|yosh|йил|ёш|год|лет|года|years?|yrs?|soat|час|hours?|kun|дн|days?|oy(?![\\p{L}])|месяц|months?|%|ta(?![\\p{L}])|kishi|человек|people|qavat|этаж|m2|м2|km|км)",
            caseInsensitive: true
        )
    ]

    private static let salaryWordRegex = NovagramJobRegex.wordPrefix([
        "maosh", "oylik", "ish haqi", "ish haqqi", "daromad", "зарплат", "з/п", "зп", "оклад", "оплата", "доход",
        "маош", "ойлик", "иш ҳақи", "даромад", "salary", "pay", "compensation", "wage"
    ])
    static let negotiableRegex = NovagramJobRegex.wordPrefix([
        "kelishilgan", "kelishiladi", "kelishuv asosida", "kelishgan holda", "suhbat asosida", "suhbat natijasida",
        "келишилган", "келишилади", "келишув асосида", "суҳбат асосида",
        "договорн", "по договоренности", "по договорённости", "по результатам собеседования",
        "negotiable", "to be discussed"
    ])

    static func salary(unified: String, normalized: String) -> NovagramJobSalary? {
        for line in unified.split(whereSeparator: { $0.isNewline }) {
            if let salary = salary(line: String(line)) {
                return salary
            }
        }
        if let match = NovagramJobRegex.firstMatch(negotiableRegex, in: normalized),
           let fragment = NovagramJobRegex.substring(normalized, match.range) {
            return NovagramJobSalary(text: fragment, isNegotiable: true)
        }
        return nil
    }

    private static func masked(_ line: String) -> String {
        let result = NSMutableString(string: line)
        for regex in maskRegexes {
            for match in NovagramJobRegex.matches(regex, in: line) {
                result.replaceCharacters(in: match.range, with: String(repeating: " ", count: match.range.length))
            }
        }
        return result as String
    }

    private static func salary(line: String) -> NovagramJobSalary? {
        guard line.contains(where: { $0.isNumber }) else { return nil }
        let maskedLine = masked(line)
        let nsLine = maskedLine as NSString
        let amounts = NovagramJobRegex.matches(amountRegex, in: maskedLine).compactMap { amount($0, in: nsLine) }
        guard !amounts.isEmpty else { return nil }
        let normalizedLine = NovagramJobText.normalized(line)
        let hasSalaryWord = NovagramJobRegex.contains(salaryWordRegex, in: normalizedLine)
        let isNegotiable = NovagramJobRegex.contains(negotiableRegex, in: normalizedLine)
        var index = 0
        while index < amounts.count {
            let first = amounts[index]
            var second: Amount?
            if index + 1 < amounts.count {
                let next = amounts[index + 1]
                let gapStart = first.range.location + first.range.length
                let gap = nsLine.substring(with: NSRange(location: gapStart, length: max(0, next.range.location - gapStart)))
                if NovagramJobRegex.contains(connectorRegex, in: gap) {
                    second = next
                }
            }
            if var salary = makeSalary(first, second, line: line, nsLine: nsLine, hasSalaryWord: hasSalaryWord) {
                salary.isNegotiable = isNegotiable
                return salary
            }
            index += second == nil ? 1 : 2
        }
        return nil
    }

    private static func amount(_ match: NSTextCheckingResult, in line: NSString) -> Amount? {
        let numberRange = match.range(withName: "num")
        guard numberRange.location != NSNotFound else { return nil }
        let numberText = line.substring(with: numberRange)
        guard let number = parseNumber(numberText), number > 0 else { return nil }
        let multiplierRange = match.range(withName: "mult")
        let multiplierText = multiplierRange.location == NSNotFound ? nil : line.substring(with: multiplierRange).lowercased()
        let currencyRange = match.range(withName: "post").location != NSNotFound ? match.range(withName: "post") : match.range(withName: "pre")
        let currencyText = currencyRange.location == NSNotFound ? nil : line.substring(with: currencyRange).lowercased()
        return Amount(
            range: match.range,
            numberText: numberText,
            number: number,
            multiplier: multiplierText.map(multiplierValue),
            isMillion: multiplierText.map { multiplierValue($0) >= 1_000_000 } ?? false,
            currency: currencyText.flatMap(currency),
            hasPlus: match.range(withName: "plus").location != NSNotFound
        )
    }

    private static func parseNumber(_ text: String) -> Double? {
        if NovagramJobRegex.contains(groupedNumberRegex, in: text) {
            return Double(String(text.filter { $0.isASCII && $0.isNumber }))
        }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private static func multiplierValue(_ text: String) -> Double {
        let lower = text.lowercased()
        if lower.hasPrefix("mln") || lower.hasPrefix("млн") || lower.hasPrefix("million") || lower.hasPrefix("миллион") {
            return 1_000_000
        }
        return 1_000
    }

    private static func currency(_ text: String) -> NovagramJobCurrency? {
        let lower = text.lowercased()
        if lower == "$" || lower.hasPrefix("usd") || lower.hasPrefix("долл") || lower.hasPrefix("dollar") || lower.hasPrefix("у.") || lower.hasPrefix("y.") {
            return .usd
        }
        if lower.hasPrefix("so") || lower.hasPrefix("su") || lower.hasPrefix("сў") || lower.hasPrefix("су") || lower.hasPrefix("uzs") {
            return .uzs
        }
        if lower == "₽" || lower.hasPrefix("rub") || lower.hasPrefix("руб") {
            return .rub
        }
        if lower == "€" || lower.hasPrefix("eur") || lower.hasPrefix("евро") {
            return .eur
        }
        return nil
    }

    private static func makeSalary(_ first: Amount, _ second: Amount?, line: String, nsLine: NSString, hasSalaryWord: Bool) -> NovagramJobSalary? {
        let currency = first.currency ?? second?.currency
        let secondMultiplier = second?.multiplier
        let firstMultiplier = first.multiplier ?? (first.number < 1000 ? secondMultiplier : nil)
        let hasMultiplier = firstMultiplier != nil || secondMultiplier != nil
        let hasMillion = first.isMillion || (second?.isMillion ?? false)
        if currency == nil && !hasMultiplier {
            guard hasSalaryWord, first.number >= 100, !first.looksLikeYear, !(second?.looksLikeYear ?? false) else { return nil }
        }
        if currency == nil && hasMultiplier && !hasMillion && !hasSalaryWord {
            return nil
        }
        let firstValue = first.number * (firstMultiplier ?? 1)
        let before = nsLine.substring(to: first.range.location)
        let minPrefix = NovagramJobRegex.firstMatch(minPrefixRegex, in: before)
        let last = second ?? first
        let lastEnd = last.range.location + last.range.length
        let after = nsLine.substring(from: lastEnd)
        var minValue: Double?
        var maxValue: Double?
        if let second = second {
            let secondValue = second.number * (secondMultiplier ?? 1)
            minValue = Swift.min(firstValue, secondValue)
            maxValue = Swift.max(firstValue, secondValue)
        } else if first.hasPlus || minPrefix != nil || NovagramJobRegex.contains(minSuffixRegex, in: after) {
            minValue = firstValue
        } else if NovagramJobRegex.contains(maxPrefixRegex, in: before) || NovagramJobRegex.contains(maxSuffixRegex, in: after) {
            maxValue = firstValue
        } else {
            minValue = firstValue
            maxValue = firstValue
        }
        var fragmentStart = first.range.location
        if let minPrefix = minPrefix {
            let prefixText = (before as NSString).substring(with: minPrefix.range)
            let leading = prefixText.prefix(while: { !$0.isLetter }).utf16.count
            fragmentStart = minPrefix.range.location + leading
        }
        let fragmentRange = NSRange(location: fragmentStart, length: lastEnd - fragmentStart)
        let fragment = (NovagramJobRegex.substring(line, fragmentRange) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return NovagramJobSalary(text: clipped(fragment), min: minValue, max: maxValue, currency: currency)
    }

    private static func clipped(_ text: String) -> String {
        guard text.count > maxFragmentLength else { return text }
        return String(text.prefix(maxFragmentLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
