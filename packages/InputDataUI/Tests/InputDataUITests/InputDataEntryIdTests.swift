import Foundation
import XCTest
@testable import InputDataUI

private final class CountingIdentifier: InputDataIdentifier {
    static var comparisons = 0

    override func isEqual(to other: InputDataIdentifier) -> Bool {
        Self.comparisons += 1
        return super.isEqual(to: other)
    }
}

private final class SharedNameIdentifier: InputDataIdentifier {
    let value: Int

    init(_ value: Int) {
        self.value = value
        super.init("shared")
    }

    override func isEqual(to other: InputDataIdentifier) -> Bool {
        return (other as? SharedNameIdentifier)?.value == value
    }
}

final class InputDataEntryIdTests: XCTestCase {
    private func cases(_ identifier: InputDataIdentifier) -> [InputDataEntryId] {
        return [.desc(42), .input(identifier), .general(identifier), .selector(identifier),
                .dataSelector(identifier), .dateSelector(identifier), .custom(identifier),
                .search(identifier), .loading, .sectionId(42)]
    }

    func testAllCasesPreserveIdentityAndLookup() {
        let first = cases(InputDataIdentifier("recipient"))
        let equivalent = cases(InputDataIdentifier("recipient"))
        XCTAssertEqual(Set(first).count, first.count)
        let rows = Dictionary(uniqueKeysWithValues: first.enumerated().map { (AnyHashable($0.element), $0.offset) })
        for (index, key) in equivalent.enumerated() {
            XCTAssertEqual(key, first[index])
            XCTAssertEqual(key.hashValue, first[index].hashValue)
            XCTAssertEqual(rows[AnyHashable(key)], index)
        }
        XCTAssertNotEqual(InputDataEntryId.desc(42), .desc(43))
        XCTAssertNotEqual(InputDataEntryId.sectionId(42), .sectionId(43))
        XCTAssertNotEqual(InputDataEntryId.custom(InputDataIdentifier("a")), .custom(InputDataIdentifier("b")))
    }

    func testReplacementAndRemovalUseEquivalentIdentifiers() {
        var rows: [AnyHashable: Int] = [:]
        for index in 0..<100 {
            rows[InputDataEntryId.custom(InputDataIdentifier("peer_\(index)"))] = index
        }
        let key = InputDataEntryId.custom(InputDataIdentifier("peer_50"))
        XCTAssertEqual(rows.updateValue(500, forKey: key), 50)
        XCTAssertEqual(rows.count, 100)
        XCTAssertEqual(rows.removeValue(forKey: InputDataEntryId.custom(InputDataIdentifier("peer_50"))), 500)
        XCTAssertEqual(rows.count, 99)
        XCTAssertEqual(rows[InputDataEntryId.custom(InputDataIdentifier("peer_51"))], 51)
    }

    func testSubclassEqualityWithCollidingHashes() {
        let first = InputDataEntryId.custom(SharedNameIdentifier(1))
        let other = InputDataEntryId.custom(SharedNameIdentifier(2))
        let same = InputDataEntryId.custom(SharedNameIdentifier(1))
        XCTAssertNotEqual(first, other)
        XCTAssertEqual(first, same)
        XCTAssertEqual(first.hashValue, same.hashValue)
        let rows: [AnyHashable: Int] = [first: 1, other: 2]
        XCTAssertEqual(rows[same], 1)
        XCTAssertEqual(rows[InputDataEntryId.custom(SharedNameIdentifier(2))], 2)
    }

    func testRecipientLookupDoesNotScanEveryRow() {
        let count = 2000
        let keys = (0..<count).map { InputDataEntryId.custom(CountingIdentifier("recipient_\($0)")) }
        CountingIdentifier.comparisons = 0
        var rows: [AnyHashable: Int] = [:]
        for (index, key) in keys.enumerated() {
            rows[key] = index
        }
        for index in 0..<count {
            XCTAssertEqual(rows[InputDataEntryId.custom(CountingIdentifier("recipient_\(index)"))], index)
        }
        XCTAssertLessThan(CountingIdentifier.comparisons, count * 30)
    }
}
