import Cocoa
import XCTest
@testable import Reconciliation

final class ReconciliationTests: XCTestCase {
    private func keys(_ count: Int, start: Int = 0, step: Int = 1, revision: Int64 = 0) -> [Key] {
        (0..<count).map { Key(id: Int64($0 % 7) + revision, index: start &+ ($0 &* step), color: $0 % 3 == 0 ? .blue : nil) }
    }
    private func collection(_ keys: [Key]) -> InlineStickerKeyCollection {
        var result = InlineStickerKeyCollection()
        for key in keys { result.append(key) }
        return result
    }

    func testSequentialMembershipPreservesAllKeyFields() {
        let values = keys(200, start: -300)
        let current = collection(values)
        for key in values {
            XCTAssertTrue(current.contains(key))
            for query in [Key(id: key.id + 1, index: key.index, color: key.color), Key(id: key.id, index: key.index, color: .red), Key(id: key.id, index: key.index + 500, color: key.color)] {
                XCTAssertEqual(current.contains(query), values.contains(query))
            }
        }
        XCTAssertFalse(current.contains(Key(id: 0, index: Int.min)))
        XCTAssertFalse(current.contains(Key(id: 0, index: Int.max)))
    }

    func testSparseReversedAndDuplicateIndexesUseExactMembership() {
        for values in [keys(100, step: 2), Array(keys(100).reversed()), keys(100, step: 0), keys(10) + keys(10), keys(3) + keys(4, start: 20)] {
            let current = collection(values)
            for query in values + keys(200) { XCTAssertEqual(current.contains(query), values.contains(query)) }
        }
    }

    func testEmptyAndExtremeIndexesDoNotOverflow() {
        for values in [[], keys(8, start: Int.max - 3), keys(8, start: Int.min), keys(1, start: Int.max), keys(1, start: Int.min)] {
            let current = collection(values)
            for query in values + [Key(id: 0, index: Int.min), Key(id: 0, index: Int.max), Key(id: 0, index: 0)] {
                XCTAssertEqual(current.contains(query), values.contains(query))
            }
        }
    }

    func testCopyAndAppendPreserveValueSemantics() {
        let values = keys(20)
        let original = collection(values)
        var changed = original
        let extra = Key(id: 99, index: -100, color: .red)
        changed.append(extra)
        XCTAssertFalse(original.contains(extra))
        XCTAssertTrue(changed.contains(extra))
        for key in values { XCTAssertTrue(original.contains(key)); XCTAssertTrue(changed.contains(key)) }
    }

    func testSeededMembershipMatchesLinearSearch() {
        var random: UInt64 = 0x261016
        func next(_ bound: Int) -> Int {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            return Int((random >> 32) % UInt64(bound))
        }
        for _ in 0..<1500 {
            let count = next(250), start = next(1000) - 500
            let step = next(4) == 0 ? next(4) : 1
            let values = keys(count, start: start, step: step)
            let current = collection(values)
            for query in values + keys(100, start: next(1500) - 750, step: 1, revision: Int64(next(3))) {
                XCTAssertEqual(current.contains(query), values.contains(query))
            }
        }
    }

    func testLayerReuseRemovalAndOrderMatchReference() {
        let old = ReferenceRows(), new = CurrentRows()
        let cases = [keys(0), keys(1), keys(20), keys(20, revision: 1), keys(100), Array(keys(100).reversed()), keys(50, step: 2), keys(10, start: Int.max - 5), keys(2, step: 0), keys(0)]
        for values in cases {
            let retained = new.inlineStickerItemViews
            old.bind(values); new.bind(values)
            XCTAssertEqual(Set(old.inlineStickerItemViews.keys), Set(new.inlineStickerItemViews.keys))
            XCTAssertEqual(old.parent.sublayers?.count ?? 0, new.parent.sublayers?.count ?? 0)
            for (key, layer) in retained {
                if values.contains(key) {
                    XCTAssertTrue(new.inlineStickerItemViews[key] === layer)
                } else {
                    XCTAssertNil(layer.superlayer)
                }
            }
            func order(_ rows: LayerRows) -> [Key] {
                (rows.parent.sublayers ?? []).map { layer in rows.inlineStickerItemViews.first { $0.value === layer }!.key }
            }
            XCTAssertEqual(order(old), order(new))
        }
    }

    func testEqualColorObjectsKeepTheirLayer() {
        let old = ReferenceRows(), new = CurrentRows()
        let first = Key(id: 12, index: 40, color: NSColor(calibratedRed: 0.2, green: 0.3, blue: 0.4, alpha: 1))
        let second = Key(id: 12, index: 40, color: NSColor(calibratedRed: 0.2, green: 0.3, blue: 0.4, alpha: 1))
        old.bind([first]); new.bind([first])
        let original = new.inlineStickerItemViews[first]!
        old.bind([second]); new.bind([second])
        XCTAssertTrue(new.inlineStickerItemViews[second] === original)
        XCTAssertEqual(Set(old.inlineStickerItemViews.keys), Set(new.inlineStickerItemViews.keys))
    }

    @inline(never) private func match(_ baseline: Bool, keys: [Key], queries: [Key]) -> Int {
        if baseline {
            var valid: [Key] = []
            for key in keys { valid.append(key) }
            return queries.reduce(0) { $0 + (valid.contains($1) ? 1 : 0) }
        } else {
            let valid = collection(keys)
            return queries.reduce(0) { $0 + (valid.contains($1) ? 1 : 0) }
        }
    }

    func testReconciliationBenchmark() throws {
        guard ProcessInfo.processInfo.environment["INLINE_RECONCILIATION_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in release benchmark") }
        var results: [[String: Any]] = []
        var checksum = 0
        for (count, mode) in [(0, "membership"), (1, "membership"), (4, "membership"), (16, "membership"), (64, "membership"), (256, "membership"), (1024, "membership"), (64, "sparse"), (16, "binding"), (64, "binding"), (256, "binding"), (64, "replacement")] {
            let values = keys(count, step: mode == "sparse" ? 2 : 1)
            let replacement = values.enumerated().map { index, key in index % 2 == 0 ? Key(id: key.id + 100, index: key.index, color: key.color) : key }
            let shared = LayerRows()
            bindCurrentRows(shared, values)
            let iterations = max(30, 3000 / max(count, 1))
            var before: [Double] = [], after: [Double] = []
            func measure(_ baseline: Bool) -> Double {
                bindCurrentRows(shared, values)
                let start = DispatchTime.now().uptimeNanoseconds
                for index in 0..<iterations {
                    if mode == "binding" || mode == "replacement" {
                        autoreleasepool {
                            let keys = mode == "replacement" && index % 2 == 0 ? replacement : values
                            if baseline { bindReferenceRows(shared, keys) }
                            else { bindCurrentRows(shared, keys) }
                            checksum += shared.inlineStickerItemViews.count
                        }
                    } else {
                        checksum += match(baseline, keys: values, queries: values)
                    }
                }
                return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations) / 1000
            }
            XCTAssertEqual(match(true, keys: values, queries: replacement), match(false, keys: values, queries: replacement))
            _ = measure(true); _ = measure(false)
            for batch in 0..<9 {
                if batch % 2 == 0 { before.append(measure(true)); after.append(measure(false)) }
                else { after.append(measure(false)); before.append(measure(true)) }
            }
            results.append(["keys": count, "mode": mode, "iterations_per_batch": iterations, "baseline_us": before.sorted()[4], "candidate_us": after.sorted()[4], "baseline_trials_us": before, "candidate_trials_us": after])
        }
        XCTAssertGreaterThan(checksum, 0)
        let data = try JSONSerialization.data(withJSONObject: ["batches": 9, "results": results], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/inline-reconciliation-benchmark.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
