import Foundation

public struct PeerId: Equatable {
    public let namespace: Int32
    public let id: Int64
    public init(namespace: Int32 = 0, id: Int64 = 1) { self.namespace = namespace; self.id = id }
}
public protocol Peer {
    var displayTitle: String { get }
    var compactDisplayTitle: String { get }
}
public struct TestPeer: Peer {
    public let displayTitle: String
    public var compactDisplayTitle: String { displayTitle }
    public init(_ title: String) { displayTitle = title }
}
public struct MessageId: Equatable { public let id: Int32 }
public struct EmojiInteraction: Equatable { public let value: Int }
enum Namespaces {
    enum Peer {
        static let CloudUser: Int32 = 0
        static let SecretChat: Int32 = 1
    }
}
var locale = 0
func localize(_ key: String, _ values: [String]) -> String {
    let text = key.replacingOccurrences(of: "peerActivity", with: "").replacingOccurrences(of: "ChatMulti", with: "").replacingOccurrences(of: "User", with: "").replacingOccurrences(of: "Chat", with: "").replacingOccurrences(of: "1", with: "")
    return (locale == 0 ? text : "العربية " + text) + (values.isEmpty ? "" : " " + values.joined(separator: ", "))
}
