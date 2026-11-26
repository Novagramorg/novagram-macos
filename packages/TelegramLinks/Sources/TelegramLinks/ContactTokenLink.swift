import Foundation

struct ContactTokenLink: Equatable {
    let token: String
    let freeToken: String?
}

func parseContactTokenLink(_ link: String) -> ContactTokenLink? {
    let value = link.contains("://") ? link : "https://" + link
    guard let components = URLComponents(string: value), components.user == nil, components.password == nil, components.port == nil else {
        return nil
    }
    let token: String
    switch components.scheme?.lowercased() {
    case "tg":
        guard components.host?.lowercased() == "contact", components.path.isEmpty,
              let value = components.queryItems?.first(where: { $0.name == "token" })?.value else {
            return nil
        }
        token = value
    case "http", "https":
        guard let host = components.host?.lowercased(), ["t.me", "telegram.me", "telegram.dog"].contains(host), components.path.hasPrefix("/contact/") else {
            return nil
        }
        token = String(components.path.dropFirst("/contact/".count))
        guard !token.contains("/") else { return nil }
    default:
        return nil
    }
    guard !token.isEmpty else { return nil }
    let free = components.queryItems?.first(where: { $0.name == "free" })?.value
    return ContactTokenLink(token: token, freeToken: free.flatMap { $0.isEmpty ? nil : $0 })
}
