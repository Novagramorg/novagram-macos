import Foundation
import Postbox
import TelegramCore

enum NovagramJobMessageContacts {
    static let maxContacts = 5
    private static let reservedPaths: Set<String> = ["joinchat", "addstickers", "addemoji", "addlist", "share", "proxy", "socks", "c", "s", "iv", "boost", "login", "setlanguage", "addtheme", "bg", "confirmphone", "invoice", "giftcode", "m"]
    private static let telegramHosts: Set<String> = ["t.me", "telegram.me", "telegram.dog"]

    static func merged(parsed: [NovagramJobContact], message: Message) -> [NovagramJobContact] {
        let ownUsername = message.peers[message.id.peerId].flatMap { EnginePeer($0).addressName }?.lowercased()
        var direct: [NovagramJobContact] = []
        var links: [NovagramJobContact] = []
        let append: (NovagramJobContact?) -> Void = { contact in
            guard let contact else {
                return
            }
            if case .link = contact {
                links.append(contact)
            } else {
                direct.append(contact)
            }
        }
        let text = message.text as NSString
        for attribute in message.attributes {
            guard let attribute = attribute as? TextEntitiesMessageAttribute else {
                continue
            }
            for entity in attribute.entities.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
                let range = NSRange(location: entity.range.lowerBound, length: entity.range.count)
                let value = range.location >= 0 && range.location + range.length <= text.length ? text.substring(with: range) : ""
                switch entity.type {
                case .Url:
                    append(contact(url: value, ownUsername: ownUsername))
                case let .TextUrl(url):
                    append(contact(url: url, ownUsername: ownUsername))
                case .Mention:
                    append(username(String(value.drop(while: { $0 == "@" })), ownUsername: ownUsername))
                case let .TextMention(peerId):
                    append(message.peers[peerId].flatMap { EnginePeer($0).addressName }.flatMap { username($0, ownUsername: ownUsername) })
                case .Email:
                    append(value.isEmpty ? nil : .email(value))
                case .PhoneNumber:
                    append(value.isEmpty ? nil : .phone(value))
                default:
                    break
                }
            }
        }
        for attribute in message.attributes {
            guard let markup = attribute as? ReplyMarkupMessageAttribute else {
                continue
            }
            for row in markup.rows {
                for button in row.buttons {
                    if case let .url(url) = button.action {
                        append(contact(url: url, ownUsername: ownUsername))
                    }
                }
            }
        }
        var seen = Set<String>()
        var result: [NovagramJobContact] = []
        for item in parsed + direct + links where seen.insert(key(item)).inserted {
            result.append(item)
        }
        return Array(result.prefix(maxContacts))
    }

    private static func key(_ contact: NovagramJobContact) -> String {
        switch contact {
        case let .username(value):
            return "u:" + value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        case let .phone(value):
            return "p:" + value.filter { $0.isNumber }
        case let .email(value):
            return "e:" + value.lowercased()
        case let .link(value):
            return "l:" + value.lowercased()
        }
    }

    private static func username(_ name: String, ownUsername: String?) -> NovagramJobContact? {
        let clean = name.trimmingCharacters(in: CharacterSet(charactersIn: "@ /"))
        let lowered = clean.lowercased()
        guard !clean.isEmpty, !clean.hasPrefix("+"), !lowered.hasSuffix("bot"), lowered != ownUsername, !reservedPaths.contains(lowered) else {
            return nil
        }
        guard clean.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            return nil
        }
        return .username(clean)
    }

    private static func contact(url raw: String, ownUsername: String?) -> NovagramJobContact? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("tg://") {
            guard lowered.hasPrefix("tg://resolve"), let components = URLComponents(string: trimmed), let domain = components.queryItems?.first(where: { $0.name == "domain" })?.value else {
                return nil
            }
            return username(domain, ownUsername: ownUsername)
        }
        if lowered.hasPrefix("mailto:") {
            return .email(String(trimmed.dropFirst("mailto:".count)))
        }
        if lowered.hasPrefix("tel:") {
            return .phone(String(trimmed.dropFirst("tel:".count)))
        }
        let withScheme = lowered.hasPrefix("http://") || lowered.hasPrefix("https://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: withScheme), let host = components.host?.lowercased() else {
            return nil
        }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard telegramHosts.contains(bareHost) else {
            return .link(withScheme)
        }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count == 1, let name = parts.first else {
            return nil
        }
        return username(name, ownUsername: ownUsername)
    }
}
