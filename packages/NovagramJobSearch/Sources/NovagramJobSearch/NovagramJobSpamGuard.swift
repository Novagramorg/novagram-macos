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

    static func isSpamSource(title: String, username: String?) -> Bool {
        let text = (title + " " + (username ?? "")).lowercased()
        let weakWords = weakSourceWords.filter(wordTokens(text).contains).count
        return contains(text, markers: sourceMarkers, words: sourceWords) || weakWords >= weakWordThreshold || hasPromoDomain(text)
    }

    static func isSpamText(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return contains(lowered, markers: textMarkers, words: textWords) || hasPromoDomain(lowered)
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
