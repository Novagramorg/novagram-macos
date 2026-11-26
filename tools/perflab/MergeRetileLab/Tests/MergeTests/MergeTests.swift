import Cocoa
import XCTest
@testable import TGUIKit
import MergeHarness

private var retainedImages: [NSImage] = []

final class MergeTests: XCTestCase {
    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.liquidGlass = false
        System.updateScaleFactor(2)
        if retainedImages.isEmpty {
            for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
                let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                    NSColor.black.setFill()
                    rect.insetBy(dx: 4, dy: 4).fill()
                    return true
                }
                _ = image.setName(name)
                retainedImages.append(image)
            }
        }
    }

    struct Outcome {
        let before: [MergeScene.Placement]
        let after: [MergeScene.Placement]
        let binds: Int
        let boundIds: [Int]
        let image: [UInt8]?
        let ms: Double
    }

    enum Shift: String, CaseIterable {
        case upper, lower
    }

    func run(shift: Shift, groupInOne: Bool, startRow: Int, deleteCount: Int, insertCount: Int, flipped: Bool = false, updateVisible: Bool = false, sticky: Bool = false, mutate: CGFloat = 0) -> Outcome {
        let initial = Array(1000..<1200)
        let scene = MergeScene(ids: initial, flipped: flipped, sticky: sticky)
        defer { scene.close() }
        scene.scroll(toRow: startRow)
        let before = scene.placements()
        let deleted: [Int]
        let inserted: [(Int, TableRowItem)]
        let state: TableScrollState
        switch shift {
        case .upper:
            deleted = Array(0..<deleteCount)
            let base = initial.count - deleteCount
            inserted = (0..<insertCount).map { (base + $0, makeMergeItem(2000 + $0, width: 360, sticky: sticky)) }
            state = .saveVisible(.upper, false)
        case .lower:
            deleted = Array((initial.count - deleteCount)..<initial.count)
            inserted = (0..<insertCount).map { ($0, makeMergeItem(500 + $0, width: 360, sticky: sticky)) }
            state = .saveVisible(.lower, false)
        }
        let updated: [(Int, TableRowItem)] = updateVisible ? scene.placements().prefix(1).compactMap { placement -> (Int, TableRowItem)? in
            guard let old = scene.table.item(stableId: AnyHashable(placement.id)) else { return nil }
            let oldIndex = old.index
            let newIndex: Int
            switch shift {
            case .upper: newIndex = oldIndex - deleteCount
            case .lower: newIndex = oldIndex + insertCount
            }
            return (newIndex, makeMergeItem(placement.id, width: 360, sticky: sticky))
        } : []
        scene.table.mergesSaveVisibleInOneGroup = groupInOne
        let transition = TableUpdateTransition(deleted: deleted, inserted: inserted, updated: updated, animated: false, state: state, grouping: true, animateVisibleOnly: true)
        MergeRow.binds = 0
        MergeRow.boundIds = []
        let start = CACurrentMediaTime()
        scene.table.merge(with: transition)
        let ms = (CACurrentMediaTime() - start) * 1000
        let binds = MergeRow.binds
        let boundIds = MergeRow.boundIds
        if mutate != 0 {
            let origin = scene.table.clipView.bounds.origin
            scene.table.clipView.scroll(to: NSPoint(x: origin.x, y: origin.y + mutate))
            scene.table.reflectScrolledClipView(scene.table.clipView)
        }
        scene.table.layoutSubtreeIfNeeded()
        drain(0.3)
        let after = scene.placements()
        print("FRAME groupInOne=\(groupInOne) frameH=\(scene.table.tableView.frame.height) listH=\(scene.table.listHeight) clipH=\(scene.table.clipView.bounds.height) spacing=\(scene.table.tableView.intercellSpacing.height) rows=\(scene.table.tableView.numberOfRows)")
        return Outcome(before: before, after: after, binds: binds, boundIds: boundIds, image: scene.capture(), ms: ms)
    }

    func testOracleCatchesOnePointShift() throws {
        for shift in Shift.allCases {
            let current = run(shift: shift, groupInOne: false, startRow: 100, deleteCount: 80, insertCount: 72)
            let shifted = run(shift: shift, groupInOne: true, startRow: 100, deleteCount: 80, insertCount: 72, mutate: 1)
            XCTAssertNotEqual(current.after, shifted.after, "placement oracle missed a 1 pt shift (\(shift.rawValue))")
            XCTAssertNotEqual(current.image, shifted.image, "pixel oracle missed a 1 pt shift (\(shift.rawValue))")
        }
    }

    func testRowGeometryInsideUpdateGroup() throws {
        for flipped in [false, true] {
            for op in ["insertFront", "deleteFront", "insertBack", "deleteBack"] {
                let scene = MergeScene(ids: Array(1000..<1200), flipped: flipped)
                defer { scene.close() }
                scene.scroll(toRow: 100)
                let table = scene.table
                let anchorId = 1100
                table.tableView.beginUpdates()
                switch op {
                case "insertFront":
                    for i in 0..<40 { _ = table.insert(item: MergeItem(500 + i, width: 360), at: i, redraw: true, animation: []) }
                case "deleteFront":
                    for _ in 0..<40 { table.remove(at: 0, redraw: true, animation: []) }
                case "insertBack":
                    for i in 0..<40 { _ = table.insert(item: MergeItem(2000 + i, width: 360), at: table.count, redraw: true, animation: []) }
                default:
                    for _ in 0..<40 { table.remove(at: table.count - 1, redraw: true, animation: []) }
                }
                for (i, item) in table.list.enumerated() { item._index = i }
                let anchor = table.item(stableId: AnyHashable(anchorId))!
                let raw = table.rectOf(item: anchor)
                if op == "insertFront" {
                    table.tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<40))
                }
                let inside = table.rectOf(item: anchor)
                print("GEOMETRY raw=\(raw.minY) noted=\(inside.minY)")
                table.tableView.endUpdates()
                let after = table.rectOf(item: anchor)
                print("GEOMETRY flipped=\(flipped) op=\(op) insideGroup=\(inside.minY) afterEnd=\(after.minY) stale=\(inside != after)")
            }
        }
    }

    func testGroupInOneKeepsPlacementAndBindsLess() throws {
        for (flipped, sticky) in [(false, false), (true, false), (false, true)] {
            for shift in Shift.allCases {
                for (startRow, deleteCount, insertCount, updateVisible) in [(100, 80, 72, false), (120, 78, 88, false), (60, 40, 40, false), (150, 30, 90, false), (100, 80, 72, true), (199, 0, 60, false), (0, 60, 0, false)] {
                    let current = run(shift: shift, groupInOne: false, startRow: startRow, deleteCount: deleteCount, insertCount: insertCount, flipped: flipped, updateVisible: updateVisible, sticky: sticky)
                    let grouped = run(shift: shift, groupInOne: true, startRow: startRow, deleteCount: deleteCount, insertCount: insertCount, flipped: flipped, updateVisible: updateVisible, sticky: sticky)
                    let label = "sticky=\(sticky) flipped=\(flipped) shift=\(shift.rawValue) start=\(startRow) del=\(deleteCount) ins=\(insertCount) update=\(updateVisible)"
                    print("MERGE \(label) current binds=\(current.binds) ms=\(String(format: "%.2f", current.ms)) bound=\(current.boundIds) | groupInOne binds=\(grouped.binds) ms=\(String(format: "%.2f", grouped.ms)) bound=\(grouped.boundIds)")
                    print("MERGE \(label) before=\(current.before.prefix(4)) currentAfter=\(current.after.prefix(4)) groupedAfter=\(grouped.after.prefix(4))")
                    XCTAssertEqual(current.after, grouped.after, "placement differs: \(label)")
                    let sameImage = current.image != nil && current.image == grouped.image
                    if !sameImage, let a = current.image, let b = grouped.image, a.count == b.count {
                        let w = 720
                        var minX = Int.max, maxX = 0, minY = Int.max, maxY = 0
                        for i in stride(from: 0, to: a.count, by: 4) where a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] {
                            let px = i / 4
                            minX = min(minX, px % w); maxX = max(maxX, px % w); minY = min(minY, px / w); maxY = max(maxY, px / w)
                        }
                        print("MERGE_PIXELS \(label) region x=\(minX)...\(maxX) y=\(minY)...\(maxY)")
                    }
                    XCTAssertTrue(sameImage, "window pixels differ: \(label)")
                    XCTAssertLessThanOrEqual(grouped.binds, current.binds, "groupInOne binds more: \(label)")
                }
            }
        }
    }
}
