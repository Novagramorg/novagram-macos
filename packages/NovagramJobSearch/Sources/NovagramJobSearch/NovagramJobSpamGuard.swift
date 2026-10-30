import Foundation

enum NovagramJobSpamGuard {
    static let sourceMarkers = ["altcoin", "crypto", "крипто", "pepe", "signals", "сигналы", "forex", "binance", "airdrop", "casino", "казино", "betting", "ставки", "bitcoin", "ethereum", "usdt", "cryptocurrenc", "market data"]
    static let sourceWords = ["nft", "btc", "eth", "trx", "markets"]
    static let weakSourceWords = ["coin", "coins", "token", "tokens", "pump", "trading"]
    private static let weakWordThreshold = 2
    static let textMarkers = ["altcoin", "bitcoin", "ethereum", "usdt", "cryptocurrenc", "market data", "фриланс-бот", "фриланс бот", "freelance bot", "ежедневными заказами", "поиске заказов", "поиске клиентов"]
    static let textWords = ["btc", "eth", "markets"]
    private static let promoWords = ["picks", "guide"]
    private static let promoDomain = try? NSRegularExpression(pattern: "[a-z0-9-]+\\.(com|net|io|xyz|top|org|pro|club|app)\\b", options: [.caseInsensitive])

    private static let priceRangeTitle = try? NSRegularExpression(pattern: "\\$\\d[\\d,]*\\s*-\\s*\\$\\d[\\d,]*\\s*\\.{3,}")
    private static let tokenPrice = try? NSRegularExpression(pattern: "\\b[A-Z]{2,10}\\s+\\$0\\.\\d{3,}")

    static func matches(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        guard let regex else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    static func isSpamSource(title: String, username: String?) -> Bool {
        if matches(priceRangeTitle, title) {
            return true
        }
        let text = (title + " " + (username ?? "")).lowercased()
        let weakWords = weakSourceWords.filter(wordTokens(text).contains).count
        return contains(text, markers: sourceMarkers, words: sourceWords) || weakWords >= weakWordThreshold || hasPromoDomain(text)
    }

    static func isSpamText(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return contains(lowered, markers: textMarkers, words: textWords) || hasPromoDomain(lowered) || isHashtagStuffing(text) || matches(tokenPrice, text)
    }

    private static let stuffingMinHashtags = 3
    private static let stuffingMaxOtherLetters = 10

    static func isHashtagStuffing(_ text: String) -> Bool {
        var hashtags = 0
        var otherLetters = 0
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            if word.hasPrefix("#") {
                hashtags += 1
            } else {
                otherLetters += word.filter { $0.isLetter }.count
            }
        }
        return hashtags >= stuffingMinHashtags && otherLetters < stuffingMaxOtherLetters
    }

    private static func contains(_ text: String, markers: [String], words: [String]) -> Bool {
        if markers.contains(where: { text.contains($0) }) {
            return true
        }
        let tokens = wordTokens(text)
        return words.contains(where: tokens.contains)
    }

    private static func wordTokens(_ text: String) -> Set<String> {
        return Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }

    private static func hasPromoDomain(_ text: String) -> Bool {
        let tokens = wordTokens(text)
        guard promoWords.contains(where: tokens.contains), let promoDomain else {
            return false
        }
        return promoDomain.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }
}
