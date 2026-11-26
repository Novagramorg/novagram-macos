import XCTest
import TGUIKit
import protocol TGUIKit.Identifiable

final class MergeListsTests: XCTestCase {
    private struct Row: Comparable, Identifiable {
        let stableId: Int
        let order: Int
        let value: Int

        static func < (lhs: Row, rhs: Row) -> Bool {
            return lhs.order < rhs.order
        }
    }

    private struct ValueEqualRow: Comparable, Identifiable {
        let stableId: Int
        let value: Int

        static func == (lhs: ValueEqualRow, rhs: ValueEqualRow) -> Bool {
            return lhs.value == rhs.value
        }

        static func < (lhs: ValueEqualRow, rhs: ValueEqualRow) -> Bool {
            return lhs.value < rhs.value
        }
    }

    private final class HashCounter {
        var count = 0
    }

    private struct CollisionId: Hashable {
        let value: Int
        let counter: HashCounter

        static func == (lhs: CollisionId, rhs: CollisionId) -> Bool {
            return lhs.value == rhs.value
        }

        func hash(into hasher: inout Hasher) {
            counter.count += 1
            hasher.combine(0)
        }
    }

    private struct CollisionRow: Comparable, Identifiable {
        let stableId: CollisionId
        let order: Int
        let value: Int

        static func < (lhs: CollisionRow, rhs: CollisionRow) -> Bool {
            return lhs.order < rhs.order
        }
    }

    private struct Generator {
        var seed: UInt64 = 348234

        mutating func next(_ limit: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 32) % UInt64(limit))
        }

        mutating func rows() -> [Row] {
            return (0..<next(100)).map { _ in
                Row(stableId: next(30), order: next(30), value: next(3))
            }
        }
    }

    private func matchesReference<T>(_ left: [T], _ right: [T], allUpdated: Bool) -> Bool where T: Comparable, T: Identifiable {
        let actual = mergeListsStableWithUpdates(leftList: left, rightList: right, allUpdated: allUpdated)
        let expected = referenceMergeListsStableWithUpdates(leftList: left, rightList: right, allUpdated: allUpdated)
        return actual.0 == expected.0
            && actual.1.count == expected.1.count
            && actual.2.count == expected.2.count
            && zip(actual.1, expected.1).allSatisfy {
                $0.0 == $1.0 && $0.1 == $1.1 && $0.1.stableId == $1.1.stableId && $0.2 == $1.2
            }
            && zip(actual.2, expected.2).allSatisfy {
                $0.0 == $1.0 && $0.1 == $1.1 && $0.1.stableId == $1.1.stableId && $0.2 == $1.2
            }
    }

    func testExhaustiveSmallListsMatchEveryReferenceTuple() {
        let alphabet = (0..<8).map {
            Row(stableId: $0 % 2, order: ($0 / 2) % 2, value: $0 / 4)
        }
        var lists: [[Row]] = [[]]
        var level: [[Row]] = [[]]
        for _ in 0..<3 {
            level = level.flatMap { prefix in alphabet.map { prefix + [$0] } }
            lists.append(contentsOf: level)
        }
        for left in lists {
            for right in lists {
                for allUpdated in [false, true] {
                    if !matchesReference(left, right, allUpdated: allUpdated) {
                        XCTFail("left=\(left), right=\(right), allUpdated=\(allUpdated)")
                        return
                    }
                }
            }
        }
    }

    func testRandomSortedAndUnsortedListsMatchEveryReferenceTuple() {
        var generator = Generator()
        for trial in 0..<10000 {
            var left = generator.rows()
            var right = generator.rows()
            if trial % 2 == 0 {
                left.sort()
                right.sort()
            }
            for allUpdated in [false, true] {
                if !matchesReference(left, right, allUpdated: allUpdated) {
                    XCTFail("trial=\(trial), left=\(left), right=\(right), allUpdated=\(allUpdated)")
                    return
                }
            }
        }
    }

    func testDuplicateIdsUseLastPreviousIndexForUpdatesAndInsertions() {
        let left = [
            Row(stableId: 7, order: 0, value: 0),
            Row(stableId: 7, order: 1, value: 0),
            Row(stableId: 8, order: 2, value: 0)
        ]
        let updated = Row(stableId: 7, order: 0, value: 1)
        let updateDiff = mergeListsStableWithUpdates(leftList: left, rightList: [updated])
        XCTAssertEqual(updateDiff.0, [1, 2])
        XCTAssertTrue(updateDiff.1.isEmpty)
        XCTAssertEqual(updateDiff.2.count, 1)
        XCTAssertEqual(updateDiff.2.first?.0, 0)
        XCTAssertEqual(updateDiff.2.first?.1, updated)
        XCTAssertEqual(updateDiff.2.first?.2, 1)

        let inserted = Row(stableId: 7, order: 3, value: 0)
        let insertDiff = mergeListsStableWithUpdates(leftList: left, rightList: [left[2], inserted])
        XCTAssertEqual(insertDiff.0, [0, 1])
        XCTAssertEqual(insertDiff.1.count, 1)
        XCTAssertEqual(insertDiff.1.first?.0, 1)
        XCTAssertEqual(insertDiff.1.first?.1, inserted)
        XCTAssertEqual(insertDiff.1.first?.2, 1)
        XCTAssertTrue(insertDiff.2.isEmpty)
    }

    func testEqualValuesWithDifferentIdsPreserveMatchingRules() {
        let alphabet = (0..<4).map { ValueEqualRow(stableId: $0 % 2, value: $0 / 2) }
        let lists = [[]] + alphabet.map { [$0] } + alphabet.flatMap { first in alphabet.map { [first, $0] } }
        for left in lists {
            for right in lists {
                for allUpdated in [false, true] {
                    XCTAssertTrue(matchesReference(left, right, allUpdated: allUpdated))
                }
            }
        }
    }

    func testHashCollisionsPreserveEveryReferenceTuple() {
        let counter = HashCounter()
        var generator = Generator()
        for trial in 0..<1000 {
            let left = generator.rows().map {
                CollisionRow(stableId: CollisionId(value: $0.stableId, counter: counter), order: $0.order, value: $0.value)
            }
            let right = generator.rows().map {
                CollisionRow(stableId: CollisionId(value: $0.stableId, counter: counter), order: $0.order, value: $0.value)
            }
            for allUpdated in [false, true] {
                XCTAssertTrue(matchesReference(left, right, allUpdated: allUpdated), "trial=\(trial)")
            }
        }
    }

    func testUnchangedAndDeletionOnlyListsDoNotHashIds() {
        let counter = HashCounter()
        let left = (0..<100).map {
            CollisionRow(stableId: CollisionId(value: $0, counter: counter), order: $0, value: 0)
        }
        for right in [left, Array(left.dropFirst(20)), left.filter { $0.order % 2 == 0 }, []] {
            counter.count = 0
            let diff = mergeListsStableWithUpdates(leftList: left, rightList: right)
            XCTAssertEqual(counter.count, 0)
            XCTAssertEqual(diff.0, left.indices.filter { index in !right.contains(left[index]) })
            XCTAssertTrue(diff.1.isEmpty)
            XCTAssertTrue(diff.2.isEmpty)
        }
        let diff = mergeListsStableWithUpdates(leftList: left, rightList: left, allUpdated: true)
        XCTAssertEqual(diff.2.count, left.count)
        XCTAssertGreaterThan(counter.count, 0)
    }

    func testSortedTransitionsReconstructRightList() {
        let left = (0..<20).map { Row(stableId: $0, order: $0 * 2, value: 0) }
        let scenarios = [
            [],
            left,
            Array(left.dropFirst(5)),
            left.filter { $0.stableId % 2 == 0 },
            [Row(stableId: 100, order: -1, value: 0)] + left,
            left + [Row(stableId: 100, order: 100, value: 0)],
            left.map { Row(stableId: $0.stableId, order: $0.order, value: 1) },
            Array(left.dropFirst()) + [Row(stableId: 0, order: 100, value: 0)],
            left.map { Row(stableId: $0.stableId + 100, order: $0.order, value: 0) },
            left.enumerated().flatMap { index, row in [row, Row(stableId: index + 100, order: row.order, value: 1)] }
        ]
        for right in scenarios {
            for allUpdated in [false, true] {
                XCTAssertTrue(matchesReference(left, right, allUpdated: allUpdated))
                let diff = mergeListsStableWithUpdates(leftList: left, rightList: right, allUpdated: allUpdated)
                var result = left
                for index in diff.0.reversed() {
                    result.remove(at: index)
                }
                for (index, row, _) in diff.1 {
                    result.insert(row, at: index)
                }
                for (index, row, _) in diff.2 {
                    result[index] = row
                }
                XCTAssertEqual(result, right)
            }
        }
    }
}
