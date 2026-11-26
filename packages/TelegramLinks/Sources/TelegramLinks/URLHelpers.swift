import Foundation
import AppKit
import Postbox
import TelegramCore
import MtProtoKit
import Colors
import Strings

public func escape(with link:String, addPercent: Bool = true) -> String {
    var escaped = addPercent ? link.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? link : link

    escaped = escaped.removingPercentEncoding ?? escaped
    return escaped
}

public func urlVars(with url: String) -> ([String: String], Set<String>) {
    var vars: [String: String] = [:]
    let range = url.nsstring.range(of: "?")
    let ns: NSString = range.location != NSNotFound ? url.nsstring.substring(from: range.location + 1).nsstring : url.nsstring

    let hashes = ns.components(separatedBy: "&")
    var emptyVars: Set<String> = Set()
    for hash in hashes {
        let param = hash.components(separatedBy: "=")
        if param.count > 1 {
            let key = param[0].lowercased()
            let rawValue = param[1...].joined(separator: "=")
            vars[key] = rawValue.removingPercentEncoding ?? rawValue
        } else if param.count == 1 {
            emptyVars.insert(param[0])
        }
    }
    return (vars, emptyVars)
}

/// Telegram links reach us with the query introduced by "&" as often as by "?",
/// and a strict URL parser reads the whole tail as the host. Give the query the
/// separator it needs so such a link can be understood.
public func normalizedTelegramLinkQuery(_ url: String) -> String {
    guard !url.contains("?"), let separator = url.range(of: "&") else {
        return url
    }
    let scheme = url.prefix(while: { $0 != ":" }).lowercased()
    guard scheme == "tg" || scheme == "telegram" else {
        return url
    }
    return url.replacingCharacters(in: separator, with: "?")
}

public func addUrlParameter(value: String, to url: String) -> String {
    if let _ = url.range(of: "?") {
        return url + "&" + value
    } else {
        if url.hasSuffix("/") {
            return url + value
        } else {
            return url + "/" + value
        }
    }
}

public func proxySettings(from url:String) -> (ProxyServerSettings?, Bool) {
    if let settings = webProxySettings(from: url) {
        return (settings, true)
    }
    let url = url.nsstring
    if url.hasPrefix(telegram_scheme), let _ = URL(string: url as String) {
        let action = url.substring(from: telegram_scheme.length)

        let (vars, _) = urlVars(with: url as String)
        if action.hasPrefix("socks") {
            if let server = vars[keyURLHost], let maybePort = vars[keyURLPort], let port = Int32(maybePort) {
                let server = escape(with: server)
                return (ProxyServerSettings(host: server, port: port, connection: .socks5(username: vars[keyURLUser], password: vars[keyURLPass])), true)
            }
            return (nil , true)
        } else if action.hasPrefix("proxy") {
            if let server = vars[keyURLHost], let maybePort = vars[keyURLPort], let port = Int32(maybePort), let rawSecret = vars[keyURLSecret] {
                let server = escape(with: server)
                if let secret = MTProxySecret.parse(rawSecret)?.serialize() {
                    return (ProxyServerSettings(host: server, port: port, connection: .mtp(secret: secret)), true)
                }
            }
        }

    } else if let _ = URL(string: url as String) {
        let link = parseInAppLink(url, options: InAppLinkParsingOptions(hasApplyProxy: true))
        switch link {
        case let .socks(_, settings):
            return (settings, true)
        default:
            break
        }
    }
    return (nil, false)
}

func webProxySettings(from value: String) -> ProxyServerSettings? {
    return parseWebProxySettingsLink(value)
}

public struct ParsedWalletUrl {
    public let address: String
    public let amount: Int64?
    public let comment: String?

    public init(address: String, amount: Int64?, comment: String?) {
        self.address = address
        self.amount = amount
        self.comment = comment
    }
}

public func parseWalletUrl(_ url: URL) -> ParsedWalletUrl? {
    guard url.scheme == "ton" && url.host == "transfer" else {
        return nil
    }
    var address: String?
    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    if !path.isEmpty, !path.contains(where: { $0.isWhitespace }) {
        address = path
    }
    var amount: Int64?
    var comment: String?
    if let query = url.query, let components = URLComponents(string: "/?" + query), let queryItems = components.queryItems {
        for queryItem in queryItems {
            if let value = queryItem.value {
                if queryItem.name == "amount", !value.isEmpty, let amountValue = Int64(value) {
                    amount = amountValue
                } else if queryItem.name == "text", !value.isEmpty {
                    comment = value
                }
            }
        }
    }
    return address.flatMap { ParsedWalletUrl(address: $0, amount: amount, comment: comment) }
}

public enum ParsedSendGramsRecipient: Equatable {
    case username(String)
    case address(String)
}

public enum ParsedSendGramsLink: Equatable {
    case wallet
    case send(recipient: ParsedSendGramsRecipient, amount: Int64?)
    case invalid
}

let sendGramsPath = "sendgrams"
private let keyURLSendGramsRecipient = "to"
private let keyURLSendGramsAmount = "amount"
private let sendGramsDecimalDigits = 9
private let sendGramsDigits = CharacterSet(charactersIn: "0123456789")

func isSendGramsWebPath(_ value: String) -> Bool {
    var path = value.components(separatedBy: "?")[0]
    while path.hasSuffix("/") {
        path.removeLast()
    }
    return path.lowercased() == sendGramsPath
}

func isSendGramsSchemeAction(_ action: String) -> Bool {
    return action == sendGramsPath || action.hasPrefix(sendGramsPath + "?") || action.hasPrefix(sendGramsPath + "/")
}

func parseSendGramsAmount(_ value: String) -> Int64? {
    let parts = value.components(separatedBy: ".")
    guard parts.count <= 2 else {
        return nil
    }
    let integerPart = parts[0]
    let fractionPart = parts.count == 2 ? parts[1] : ""
    guard !integerPart.isEmpty, integerPart.rangeOfCharacter(from: sendGramsDigits.inverted) == nil else {
        return nil
    }
    guard parts.count == 1 || !fractionPart.isEmpty, fractionPart.count <= sendGramsDecimalDigits, fractionPart.rangeOfCharacter(from: sendGramsDigits.inverted) == nil else {
        return nil
    }
    let paddedFraction = fractionPart.padding(toLength: sendGramsDecimalDigits, withPad: "0", startingAt: 0)
    guard let integerValue = Int64(integerPart), let fractionValue = Int64(paddedFraction) else {
        return nil
    }
    let (scaled, scaleOverflow) = integerValue.multipliedReportingOverflow(by: 1_000_000_000)
    let (amount, sumOverflow) = scaled.addingReportingOverflow(fractionValue)
    guard !scaleOverflow, !sumOverflow, amount > 0 else {
        return nil
    }
    return amount
}

func isSendGramsAddress(_ value: String) -> Bool {
    guard (48 ... 68).contains(value.utf8.count), !value.contains("://") else {
        return false
    }
    return value.utf8.allSatisfy {
        (65 ... 90).contains($0) || (97 ... 122).contains($0) || (48 ... 57).contains($0)
            || $0 == 45 || $0 == 95 || $0 == 58
    }
}

func parseSendGramsLink(_ vars: [String: String]) -> ParsedSendGramsLink {
    let recipient = (vars[keyURLSendGramsRecipient] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let amountValue = vars[keyURLSendGramsAmount] ?? ""
    guard !recipient.isEmpty else {
        return amountValue.isEmpty ? .wallet : .invalid
    }
    var amount: Int64?
    if !amountValue.isEmpty {
        guard let value = parseSendGramsAmount(amountValue) else {
            return .invalid
        }
        amount = value
    }
    if recipient.hasPrefix("@") {
        let username = String(recipient.dropFirst())
        guard !username.isEmpty, username.utf8.allSatisfy({
            (65 ... 90).contains($0) || (97 ... 122).contains($0) || (48 ... 57).contains($0) || $0 == 95
        }) else {
            return .invalid
        }
        return .send(recipient: .username(username), amount: amount)
    }
    guard isSendGramsAddress(recipient) else {
        return .invalid
    }
    return .send(recipient: .address(recipient), amount: amount)
}

public func explicitUrl(_ url: String) -> String {
    var url = url
    if !url.hasPrefix("http") && !url.hasPrefix("https") && url.range(of: "://") == nil {
        url = "https://\(url)"
    }
    return url
}

public func urlWithoutScheme(from url: URL) -> (url: String, host: String)? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return nil
    }

    guard let host = components.host else {
        return nil
    }

    var urlString = host

    if !components.path.isEmpty {
        urlString += components.path
    }

    if let query = components.query, !query.isEmpty {
        urlString += "?" + query
    }

    if let fragment = components.fragment, !fragment.isEmpty {
        urlString += "#" + fragment
    }

    if urlString.hasSuffix("/") {
        _ = urlString.removeLast()
    }

    return (url: urlString, host: host)
}
