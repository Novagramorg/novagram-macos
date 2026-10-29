import Foundation

enum NovagramJobSpamGuard {
    static let sourceMarkers = ["altcoin", "crypto", "крипто", "coin", "token", "pepe", "pump", "signals", "сигналы", "forex", "binance", "airdrop", "trading", "casino", "казино", "betting", "ставки", "bitcoin", "ethereum", "usdt", "cryptocurrenc", "market data"]
    static let sourceWords = ["nft", "btc", "eth", "trx", "markets"]
    static let textMarkers = ["altcoin", "bitcoin", "ethereum", "usdt", "cryptocurrenc", "market data"]
    static let textWords = ["btc", "eth", "markets"]
    private static let promoWords = ["picks", "guide"]
    private static let promoDomain = try? NSRegularExpression(pattern: "[a-z0-9-]+\\.(com|net|io|xyz|top|org|pro|club|app)\\b", options: [.caseInsensitive])

    static func isSpamSource(title: String, username: String?) -> Bool {
        let text = (title + " " + (username ?? "")).lowercased()
        return contains(text, markers: sourceMarkers, words: sourceWords) || hasPromoDomain(text)
    }

    static func isSpamText(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return contains(lowered, markers: textMarkers, words: textWords) || hasPromoDomain(lowered)
    }

    private static func contains(_ text: String, markers: [String], words: [String]) -> Bool {
        if markers.contains(where: { text.contains($0) }) {
            return true
        }
        let tokens = Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        return words.contains(where: tokens.contains)
    }

    private static func hasPromoDomain(_ text: String) -> Bool {
        guard promoWords.contains(where: { text.contains($0) }), let promoDomain else {
            return false
        }
        return promoDomain.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }
}
