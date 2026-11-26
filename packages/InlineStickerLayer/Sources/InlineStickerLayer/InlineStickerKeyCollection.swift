import Cocoa

public struct InlineStickerKeyCollection {
    @usableFromInline var keys: [InlineStickerItemLayer.Key] = []
    @usableFromInline var isSequential = true
    @usableFromInline var firstIndex = 0

    @inlinable public init() {
    }

    @inlinable public mutating func append(_ key: InlineStickerItemLayer.Key) {
        if keys.isEmpty {
            firstIndex = key.index
        } else if isSequential {
            let (offset, overflow) = key.index.subtractingReportingOverflow(firstIndex)
            isSequential = !overflow && offset == keys.count
        }
        keys.append(key)
    }

    @inlinable public func contains(_ key: InlineStickerItemLayer.Key) -> Bool {
        guard isSequential else {
            return keys.contains(key)
        }
        let (offset, overflow) = key.index.subtractingReportingOverflow(firstIndex)
        return !overflow && offset >= 0 && offset < keys.count && keys[offset] == key
    }
}
