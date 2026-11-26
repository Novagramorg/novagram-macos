import XCTest
@testable import Production

final class AlbumSelectionTests: XCTestCase {
    private struct Message: Equatable {
        let id: Int
        let group: Int?
    }

    private func original(_ messages: [Message], _ ids: [Int], album: Bool) -> [Message] {
        var filtered = messages.filter { ids.contains($0.id) }
        if album {
            let grouping = filtered.filter { $0.group != nil }
            for groupMessage in grouping {
                filtered.append(contentsOf: messages.filter { $0.group == groupMessage.group && $0.id != groupMessage.id })
            }
        }
        return filtered
    }

    private func select(_ messages: [Message], _ ids: [Int], album: Bool = true) -> [Message] {
        return selectedMessagesWithAlbums(from: messages, ids: ids, includeAlbums: album, id: { $0.id }, groupId: { $0.group })
    }

    func testMultipleSelectionsInOneAlbumAreNotDuplicated() {
        let messages = (0 ..< 3).map { Message(id: $0, group: 1) }
        XCTAssertEqual(original(messages, [0, 1], album: true).map(\.id), [0, 1, 1, 2, 0, 2])
        XCTAssertEqual(select(messages, [0, 1]).map(\.id), [0, 1, 2])
    }

    func testInterleavedAlbumsRetainFirstOccurrenceOrdering() {
        let messages = [Message(id: 0, group: 1), Message(id: 1, group: 2), Message(id: 2, group: 1), Message(id: 3, group: 2), Message(id: 4, group: nil)]
        XCTAssertEqual(select(messages, [3, 2]).map(\.id), [2, 3, 0, 1])
        XCTAssertEqual(select(messages, [3, 2], album: false).map(\.id), [2, 3])
        XCTAssertEqual(select(messages, [4]).map(\.id), [4])
        XCTAssertEqual(select(messages, [100]).map(\.id), [])
        XCTAssertEqual(select(messages, []).map(\.id), [])
    }

    func testRandomSelectionsMatchDeduplicatedOriginal() {
        var seed: UInt64 = 81
        func random(_ upper: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1
            return Int((seed >> 32) % UInt64(upper))
        }
        for _ in 0 ..< 2000 {
            let messages = (0 ..< random(100)).map { Message(id: $0, group: random(4) == 0 ? nil : random(12)) }
            let ids = (0 ..< random(100)).map { _ in random(120) }
            for album in [false, true] {
                var seen = Set<Int>()
                let expected = original(messages, ids, album: album).filter { seen.insert($0.id).inserted }
                XCTAssertEqual(select(messages, ids, album: album), expected)
            }
        }
    }
}
