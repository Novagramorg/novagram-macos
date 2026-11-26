import Foundation

struct PanelSearchRequestTracker<Key: Hashable> {
    struct Request: Equatable {
        let key: Key
        let query: String
        let offset: String
        let generation: Int
    }
    struct Completion {
        let nextOffset: String?
    }
    private var generation = 0
    private var pending: [Key: Request] = [:]
    private var completedOffsets: [Key: Set<String>] = [:]

    mutating func reset(_ key: Key) {
        pending.removeValue(forKey: key)
        completedOffsets.removeValue(forKey: key)
    }

    mutating func clearCompleted(_ key: Key) {
        completedOffsets.removeValue(forKey: key)
    }

    mutating func begin(key: Key, query: String, offset: String) -> Request? {
        guard pending[key] == nil, completedOffsets[key]?.contains(offset) != true else { return nil }
        generation += 1
        let request = Request(key: key, query: query, offset: offset, generation: generation)
        pending[key] = request
        return request
    }

    mutating func finish(_ request: Request, nextOffset: String?) -> Completion? {
        guard pending[request.key] == request else { return nil }
        pending.removeValue(forKey: request.key)
        completedOffsets[request.key, default: []].insert(request.offset)
        let next = nextOffset.flatMap { offset -> String? in
            guard !offset.isEmpty, completedOffsets[request.key]?.contains(offset) != true else { return nil }
            return offset
        }
        return Completion(nextOffset: next)
    }
}

func panelSearchAppendingUnique<Item, Id: Hashable>(_ current: [Item], _ incoming: [Item], id: (Item) -> Id) -> [Item] {
    var seen = Set(current.map(id))
    var result = current
    for item in incoming where seen.insert(id(item)).inserted {
        result.append(item)
    }
    return result
}

struct PanelEmojiSearchIndex {
    private let values: Set<String>
    private let firstScalars: Set<UInt32>
    private let singleFirstScalar: UInt32?

    init(_ values: [String]) {
        self.values = Set(values.map(Self.key))
        self.firstScalars = Set(self.values.compactMap { $0.unicodeScalars.first?.value })
        self.singleFirstScalar = firstScalars.count == 1 ? firstScalars.first : nil
    }

    func contains(_ value: String) -> Bool {
        if let first = value.unicodeScalars.first, !Self.isModifier(first) {
            if let singleFirstScalar = singleFirstScalar {
                guard first.value == singleFirstScalar else { return false }
            } else if !firstScalars.contains(first.value) {
                return false
            }
        }
        return values.contains(value) || values.contains(Self.key(value))
    }

    private static func isModifier(_ scalar: Unicode.Scalar) -> Bool {
        return scalar.value == 0xfe0f || scalar.value == 0xfe0e || (0x1f3fb...0x1f3ff).contains(scalar.value)
    }

    private static func key(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: isModifier) else { return value }
        return String(String.UnicodeScalarView(value.unicodeScalars.filter { !isModifier($0) }))
    }
}

func panelEmojiDisplayedSections<Section>(isSearching: Bool, isMessageEffects: Bool, browsing: [Section], matching: [Section]) -> [Section] {
    return isSearching && !isMessageEffects ? matching : browsing
}
