@inline(__always)
func selectedMessagesWithAlbums<Message, Id: Hashable, GroupId: Hashable>(from messages: [Message], ids: [Id], includeAlbums: Bool, id: (Message) -> Id, groupId: (Message) -> GroupId?) -> [Message] {
    guard !ids.isEmpty else {
        return []
    }
    if ids.count == 1 {
        var selected = messages.filter { ids.contains(id($0)) }
        if includeAlbums {
            let grouped = selected.filter { groupId($0) != nil }
            for message in grouped {
                selected.append(contentsOf: messages.filter { groupId($0) == groupId(message) && id($0) != id(message) })
            }
        }
        return selected
    }
    let selectedIds = Set(ids)
    let selected = messages.filter { selectedIds.contains(id($0)) }
    guard includeAlbums else {
        return selected
    }
    var groupIndices: [GroupId: Int] = [:]
    var additionalGroups: [[Message]] = []
    for message in selected {
        if let group = groupId(message), groupIndices[group] == nil {
            groupIndices[group] = additionalGroups.count
            additionalGroups.append([])
        }
    }
    guard !additionalGroups.isEmpty else {
        return selected
    }
    for message in messages {
        if let group = groupId(message), let index = groupIndices[group], !selectedIds.contains(id(message)) {
            additionalGroups[index].append(message)
        }
    }
    var result = selected
    for additional in additionalGroups {
        result.append(contentsOf: additional)
    }
    return result
}
