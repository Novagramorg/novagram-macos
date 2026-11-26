import Foundation

public final class ExportJsonWriter {
    private let baseURL: URL
    private let url: URL
    private var handle: FileHandle?

    private var chatsOpen = false
    private var chatsListNeedsComma = false
    private var messagesNeedComma = false

    public init(baseURL: URL) {
        self.baseURL = baseURL
        self.url = baseURL.appendingPathComponent("result.json")
    }

    public func begin(about: String) throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        handle = try FileHandle(forWritingTo: url)
        write("{\n")
        write("\"about\": \(jsonScalar(about))")
    }

    public func writeSection(_ key: String, object: Any) {
        write(",\n\(jsonScalar(key)): \(serialize(object))")
    }

    public func beginChats(about: String) {
        write(",\n\"chats\": {\n\"about\": \(jsonScalar(about)),\n\"list\": [")
        chatsOpen = true
        chatsListNeedsComma = false
    }

    public func beginChat(name: String, type: String, id: Int64) {
        write(chatsListNeedsComma ? ",\n" : "\n")
        chatsListNeedsComma = true
        write("{\n\"name\": \(jsonScalar(name)),\n\"type\": \(jsonScalar(type)),\n\"id\": \(id),\n\"messages\": [")
        messagesNeedComma = false
    }

    public func appendMessage(_ object: [String: Any]) {
        write(messagesNeedComma ? ",\n" : "\n")
        messagesNeedComma = true
        write(serialize(object))
    }

    public func endChat() {
        write("]\n}")
    }

    public func endChats() {
        if chatsOpen {
            write("\n]\n}")
            chatsOpen = false
        }
    }

    @discardableResult
    public func finish() -> URL {
        endChats()
        write("\n}\n")
        handle?.closeFile()
        handle = nil
        return url
    }

    // MARK: - Serialization

    private func serialize(_ object: Any) -> String {
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        if object is [Any] {
            return "[]"
        }
        if object is [AnyHashable: Any] {
            return "{}"
        }
        return jsonScalar("\(object)")
    }

    private func jsonScalar(_ value: Any) -> String {
        if let string = value as? String {
            if let data = try? JSONSerialization.data(withJSONObject: [string], options: []),
               var string = String(data: data, encoding: .utf8) {
                string.removeFirst()
                string.removeLast()
                return string
            }
            return "\"\""
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        return "\(value)"
    }

    private func write(_ string: String) {
        if let data = string.data(using: .utf8) {
            handle?.write(data)
        }
    }
}
