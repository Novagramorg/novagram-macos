import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine
@testable import SortingBaseline

final class SiblingOrderBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["SIBLING_ORDER_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in sibling order benchmark") }
        TGUIKitTestBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["SIBLING_ORDER_REVERSE"] == "1"
        let factory = SiblingOrderTests()
        var sink = 0, results: [String: [[Double]]] = [:]
        func measure(_ name: String, count: Int = 1000, operations: [() -> Int]) {
            for op in operations { for _ in 0..<30 { autoreleasepool { sink += op() } } }
            CATransaction.flush()
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                for variant in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                    CATransaction.begin()
                    let start = CACurrentMediaTime()
                    for _ in 0..<count { autoreleasepool { sink += operations[variant]() } }
                    batches[variant].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                    CATransaction.commit(); CATransaction.flush()
                }
            }
            results[name] = batches
        }
        for count in [1, 3, 12, 64] {
            for kind in ["equal", "ascending", "descending", "mixed", "late_inversion"] {
                let levels = (0..<count).map { index in kind == "equal" ? 0 : kind == "ascending" ? index / 2 : kind == "descending" ? -index : kind == "late_inversion" ? (index == count - 1 ? -1 : index) : (index * 7) % 11 }
                let (old, new) = try factory.pair(levels)
                measure("sort_\(count)_\(kind)", operations: [
                    { old.sortChildrenForLab(); return old.children.count },
                    { new.sortChildrenForLab(); return new.children.count }
                ])
            }
        }
        let oldFixtures = (0..<4).map { SortingBaseline.PlainRowFixture(width: 400 + CGFloat($0 % 2) * 20, variant: $0) }
        let newFixtures = (0..<4).map { ChatLayerEngine.PlainRowFixture(width: 400 + CGFloat($0 % 2) * 20, variant: $0) }
        var a = 0, b = 0
        measure("premeasured_row_construction", count: 300, operations: [
            { defer { a += 1 }; return SortingBaseline.LayerPlainRow(oldFixtures[a % 4]).nodes.count },
            { defer { b += 1 }; return ChatLayerEngine.LayerPlainRow(newFixtures[b % 4]).nodes.count }
        ])
        let oldRow = SortingBaseline.LayerPlainRow(oldFixtures[0]), newRow = ChatLayerEngine.LayerPlainRow(newFixtures[0])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView!.addSubview(oldRow.view); window.contentView!.addSubview(newRow.view)
        a = 0; b = 0
        measure("attached_row_rebind", count: 600, operations: [
            { defer { a += 1 }; oldRow.bind(oldFixtures[a % 4]); oldRow.view.layoutSubtreeIfNeeded(); return oldRow.nodes.count },
            { defer { b += 1 }; newRow.bind(newFixtures[b % 4]); newRow.view.layoutSubtreeIfNeeded(); return newRow.nodes.count }
        ])
        let oldScene = SortingBaseline.ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let newScene = ChatLayerEngine.ChatLayerSceneView(frame: oldScene.frame)
        let (oldNodes, newNodes) = try factory.pair(Array(repeating: 0, count: 12))
        let oldChildren = oldNodes.children, newChildren = newNodes.children
        try oldNodes.setChildren([]); try newNodes.setChildren([])
        for node in oldChildren { node.frame = NSRect(x: 10, y: 10, width: 80, height: 40); node.acceptsPointerEvents = true }
        for node in newChildren { node.frame = NSRect(x: 10, y: 10, width: 80, height: 40); node.acceptsPointerEvents = true }
        try oldScene.root.setChildren(oldChildren); try newScene.root.setChildren(newChildren)
        oldScene.layout(); newScene.layout()
        let point = NSPoint(x: 20, y: 20)
        oldScene.updateHover(at: point); newScene.updateHover(at: point)
        let oldReverse = Array(oldChildren.reversed()), newReverse = Array(newChildren.reversed())
        var oldFlip = false, newFlip = false
        measure("active_scene_reorder_12", count: 600, operations: [
            { oldFlip.toggle(); try! oldScene.root.setChildren(oldFlip ? oldChildren : oldReverse); oldScene.layoutSubtreeIfNeeded(); return oldScene.hitNode(at: point) == nil ? 0 : 1 },
            { newFlip.toggle(); try! newScene.root.setChildren(newFlip ? newChildren : newReverse); newScene.layoutSubtreeIfNeeded(); return newScene.hitNode(at: point) == nil ? 0 : 1 }
        ])
        var sharing: [[String: Int]] = []
        for count in [1, 3, 12, 64] {
            let (old, new) = try factory.pair(Array(repeating: 0, count: count))
            sharing.append(["child_count": count, "baseline_unique_child_array_buffers": old.orderingSharesStorageForLab ? 1 : 2, "candidate_unique_child_array_buffers": new.orderingSharesStorageForLab ? 1 : 2])
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "reverse": reverse, "batches_before_after": results, "array_storage": sharing, "sink": sink], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-sibling-order-benchmark.json"))
    }
}
