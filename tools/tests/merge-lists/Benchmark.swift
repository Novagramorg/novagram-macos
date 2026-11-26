import Foundation
import TGUIKit
import MergeListsReference

struct SimpleRow: Comparable, TGUIKit.Identifiable {
    let stableId: Int
    let order: Int
    let value: Int

    static func < (lhs: SimpleRow, rhs: SimpleRow) -> Bool {
        return lhs.order < rhs.order
    }
}

struct PayloadRow: Comparable, TGUIKit.Identifiable {
    let stableId: AnyHashable
    let order: Int
    let title: String
    let metadata: [Int]

    static func < (lhs: PayloadRow, rhs: PayloadRow) -> Bool {
        return lhs.order < rhs.order
    }
}

var checksum = 0

@inline(never)
func measure<T>(_ left: [T], _ right: [T], allUpdated: Bool, reference: Bool, repeats: Int) -> Double where T: Comparable, T: TGUIKit.Identifiable {
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<repeats {
        let diff = reference
            ? referenceMergeListsStableWithUpdates(leftList: left, rightList: right, allUpdated: allUpdated)
            : mergeListsStableWithUpdates(leftList: left, rightList: right, allUpdated: allUpdated)
        checksum &+= diff.0.count + diff.1.count + diff.2.count
        checksum &+= diff.1.last?.2 ?? 0
        checksum &+= diff.2.last?.2 ?? 0
    }
    return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(repeats) / 1000
}

func benchmark<T>(_ name: String, makeRow: (Int, Int, Int) -> T) where T: Comparable, T: TGUIKit.Identifiable {
    for count in [100, 1000, 10000] {
        let left = (0..<count).map { makeRow($0, $0, 0) }
        var edited = left
        edited[count / 2] = makeRow(count / 2, count / 2, 1)
        let scenarios: [(String, [T], Bool)] = [
            ("unchanged", left, false),
            ("equal rebuilt", (0..<count).map { makeRow($0, $0, 0) }, false),
            ("one update", edited, false),
            ("allUpdated", left, true),
            ("prepend 20", (-20..<0).map { makeRow($0, $0, 0) } + left, false),
            ("delete half", Array(left.suffix(count / 2)), false),
            ("replace all", (0..<count).map { makeRow($0 + count, $0, 0) }, false)
        ]
        for (scenario, right, allUpdated) in scenarios {
            let repeats = max(20, 100000 / count)
            var oldTimes: [Double] = []
            var newTimes: [Double] = []
            for run in 0..<8 {
                for reference in (run % 2 == 0 ? [true, false] : [false, true]) {
                    let elapsed = measure(left, right, allUpdated: allUpdated, reference: reference, repeats: repeats)
                    if run > 0 {
                        if reference {
                            oldTimes.append(elapsed)
                        } else {
                            newTimes.append(elapsed)
                        }
                    }
                }
            }
            let old = oldTimes.sorted()[3]
            let new = newTimes.sorted()[3]
            print("\(name), n=\(count), \(scenario): baseline=\(String(format: "%.2f", old))us optimized=\(String(format: "%.2f", new))us speedup=\(String(format: "%.2f", old / new))x")
        }
    }
}

benchmark("SimpleRow") { SimpleRow(stableId: $0, order: $1, value: $2) }
benchmark("PayloadRow") {
    PayloadRow(stableId: AnyHashable($0), order: $1, title: "Row \($0)", metadata: [$2, $0, 1, 2, 3, 4, 5, 6])
}
print("checksum \(checksum)")
