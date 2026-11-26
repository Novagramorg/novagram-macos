import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine
@testable import TreeBaseline

final class TreeUpdateBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["TREE_UPDATE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in tree update benchmark") }
        TGUIKitTestBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["TREE_UPDATE_REVERSE"] == "1"
        let factory = TreeUpdateTests()
        var sink = 0, results: [String: [[Double]]] = [:]
        func measure(_ name: String, count: Int = 2000, operations: [() -> Int]) {
            for op in operations { for _ in 0..<100 { autoreleasepool { sink += op() } } }
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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let p = try factory.pair(12, background: 64)
        window.contentView!.addSubview(p.old); window.contentView!.addSubview(p.new)
        let aReverse = Array(p.a.reversed()), bReverse = Array(p.b.reversed())
        var flipA = false, flipB = false
        for hover in [false, true] {
            let point = CGPoint(x: 20, y: 20)
            if hover { _ = p.old.handlePointer(.moved, at: point); _ = p.new.handlePointer(.moved, at: point) }
            measure("attached_reorder_12_background64_hover_\(hover)", operations: [
                { flipA.toggle(); try! p.oldLeft.setChildren(flipA ? aReverse : p.a); p.old.layoutSubtreeIfNeeded(); return p.oldLeft.children.count },
                { flipB.toggle(); try! p.newLeft.setChildren(flipB ? bReverse : p.b); p.new.layoutSubtreeIfNeeded(); return p.newLeft.children.count }
            ])
        }
        measure("unchanged_children_12", operations: [
            { try! p.oldLeft.setChildren(p.oldLeft.children); return p.oldLeft.children.count },
            { try! p.newLeft.setChildren(p.newLeft.children); return p.newLeft.children.count }
        ])
        let compact = try factory.pair(4, background: 0)
        window.contentView!.addSubview(compact.old); window.contentView!.addSubview(compact.new)
        let aCompactReverse = Array(compact.a.reversed()), bCompactReverse = Array(compact.b.reversed())
        var compactFlipA = false, compactFlipB = false
        for hover in [false, true] {
            let point = CGPoint(x: 20, y: 20)
            if hover { _ = compact.old.handlePointer(.moved, at: point); _ = compact.new.handlePointer(.moved, at: point) }
            measure("attached_reorder_4_background0_hover_\(hover)", operations: [
                { compactFlipA.toggle(); try! compact.oldLeft.setChildren(compactFlipA ? aCompactReverse : compact.a); compact.old.layoutSubtreeIfNeeded(); return compact.oldLeft.children.count },
                { compactFlipB.toggle(); try! compact.newLeft.setChildren(compactFlipB ? bCompactReverse : compact.b); compact.new.layoutSubtreeIfNeeded(); return compact.newLeft.children.count }
            ])
        }
        compact.old.cancelInput(); compact.new.cancelInput()
        let aExtra = TreeBaseline.ChatLayerNode(id: "compactExtra"), bExtra = ChatLayerEngine.ChatLayerNode(id: "compactExtra")
        let aExpanded = compact.a + [aExtra], bExpanded = compact.b + [bExtra]
        try compact.oldLeft.setChildren(compact.a); try compact.newLeft.setChildren(compact.b)
        measure("append_and_remove_one_small_tree", operations: [
            { try! compact.oldLeft.setChildren(aExpanded); try! compact.oldLeft.setChildren(compact.a); return compact.oldLeft.children.count },
            { try! compact.newLeft.setChildren(bExpanded); try! compact.newLeft.setChildren(compact.b); return compact.newLeft.children.count }
        ])
        let shrink = try factory.pair(16, background: 128)
        let aSmall = Array(shrink.a.prefix(8)), bSmall = Array(shrink.b.prefix(8))
        measure("nested_shrink_and_restore_16", count: 1000, operations: [
            { try! shrink.oldLeft.setChildren(aSmall); try! shrink.oldLeft.setChildren(shrink.a); return shrink.oldLeft.children.count },
            { try! shrink.newLeft.setChildren(bSmall); try! shrink.newLeft.setChildren(shrink.b); return shrink.newLeft.children.count }
        ])
        let replacement = try factory.pair(12, background: 64)
        let aNew = (0..<12).map { TreeBaseline.ChatLayerNode(id: "replacement\($0)") }
        let bNew = (0..<12).map { ChatLayerEngine.ChatLayerNode(id: "replacement\($0)") }
        flipA = false; flipB = false
        measure("replace_all_12", count: 1000, operations: [
            { flipA.toggle(); try! replacement.oldLeft.setChildren(flipA ? aNew : replacement.a); return replacement.oldLeft.children.count },
            { flipB.toggle(); try! replacement.newLeft.setChildren(flipB ? bNew : replacement.b); return replacement.newLeft.children.count }
        ])
        let extraA = TreeBaseline.ChatLayerNode(id: "extra"), extraB = ChatLayerEngine.ChatLayerNode(id: "extra")
        let withA = replacement.a + [extraA], withB = replacement.b + [extraB]
        try replacement.oldLeft.setChildren(replacement.a); try replacement.newLeft.setChildren(replacement.b)
        measure("append_and_remove_one", count: 1000, operations: [
            { try! replacement.oldLeft.setChildren(withA); try! replacement.oldLeft.setChildren(replacement.a); return replacement.oldLeft.children.count },
            { try! replacement.newLeft.setChildren(withB); try! replacement.newLeft.setChildren(replacement.b); return replacement.newLeft.children.count }
        ])
        let oldFixtures = (0..<4).map { TreeBaseline.PlainRowFixture(width: 400 + CGFloat($0 % 2) * 20, variant: $0) }
        let newFixtures = (0..<4).map { ChatLayerEngine.PlainRowFixture(width: 400 + CGFloat($0 % 2) * 20, variant: $0) }
        var a = 0, b = 0
        measure("premeasured_row_construction", count: 1000, operations: [
            { defer { a += 1 }; return TreeBaseline.LayerPlainRow(oldFixtures[a % 4]).nodes.count },
            { defer { b += 1 }; return ChatLayerEngine.LayerPlainRow(newFixtures[b % 4]).nodes.count }
        ])
        let oldRow = TreeBaseline.LayerPlainRow(oldFixtures[0]), newRow = ChatLayerEngine.LayerPlainRow(newFixtures[0])
        window.contentView!.addSubview(oldRow.view); window.contentView!.addSubview(newRow.view)
        a = 0; b = 0
        measure("attached_row_rebind", operations: [
            { defer { a += 1 }; oldRow.bind(oldFixtures[a % 4]); oldRow.view.layoutSubtreeIfNeeded(); return oldRow.nodes.count },
            { defer { b += 1 }; newRow.bind(newFixtures[b % 4]); newRow.view.layoutSubtreeIfNeeded(); return newRow.nodes.count }
        ])
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "reverse": reverse, "batches_before_after": results, "sink": sink, "state_allocation_bytes": ["baseline": p.old.stateAllocationSizeForLab, "candidate": p.new.stateAllocationSizeForLab]], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-tree-update-benchmark.json"))
    }
}
