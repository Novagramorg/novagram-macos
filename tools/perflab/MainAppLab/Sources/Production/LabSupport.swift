public struct LabMessage {
    public let id: Int
    public let group: Int?

    public init(id: Int, group: Int?) {
        self.id = id
        self.group = group
    }
}

public func labSelectedMessages(_ messages: [LabMessage], ids: [Int], includeAlbums: Bool) -> [LabMessage] {
    return selectedMessagesWithAlbums(from: messages, ids: ids, includeAlbums: includeAlbums, id: { $0.id }, groupId: { $0.group })
}

public func labLegacySelectedMessages(_ messages: [LabMessage], ids: [Int], includeAlbums: Bool) -> [LabMessage] {
    var filtered = messages.filter { ids.contains($0.id) }
    if includeAlbums {
        let grouping = filtered.filter { $0.group != nil }
        for message in grouping {
            filtered.append(contentsOf: messages.filter { $0.group == message.group && $0.id != message.id })
        }
    }
    return filtered
}

