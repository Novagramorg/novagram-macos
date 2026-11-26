import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine
@testable import SortingBaseline

final class SiblingOrderTests: XCTestCase {
    override func setUp() {
        TGUIKitTestBootstrap.install()
        TGUIKitAccessibility.isEnabled = true
    }

    func pair(_ levels: [Int]) throws -> (SortingBaseline.ChatLayerNode, ChatLayerEngine.ChatLayerNode) {
        let old = SortingBaseline.ChatLayerNode(id: "root"), new = ChatLayerEngine.ChatLayerNode(id: "root")
        let a = levels.enumerated().map { index, level -> SortingBaseline.ChatLayerNode in
            let node = SortingBaseline.ChatLayerNode(id: index); node.zIndex = level; return node
        }
        let b = levels.enumerated().map { index, level -> ChatLayerEngine.ChatLayerNode in
            let node = ChatLayerEngine.ChatLayerNode(id: index); node.zIndex = level; return node
        }
        try old.setChildren(a); try new.setChildren(b)
        return (old, new)
    }

    func testExhaustiveSmallOrdersMatchStableOriginal() throws {
        for count in 0...6 {
            let combinations = Int(pow(3, Double(count)))
            for value in 0..<combinations {
                var value = value
                let levels = (0..<count).map { _ -> Int in defer { value /= 3 }; return value % 3 - 1 }
                let (old, new) = try pair(levels)
                XCTAssertEqual(old.orderedChildrenForLab.map(\.id), new.orderedChildrenForLab.map(\.id))
                XCTAssertEqual(old.children.map(\.id), new.children.map(\.id))
                let ordered = zip(levels, levels.dropFirst()).allSatisfy { $0 <= $1 }
                if count > 0 {
                    XCTAssertFalse(old.orderingSharesStorageForLab)
                    XCTAssertEqual(new.orderingSharesStorageForLab, ordered)
                }
            }
        }
        let (old, new) = try pair([Int.max, Int.min, 0, Int.max, Int.min])
        XCTAssertEqual(new.orderedChildrenForLab.map(\.id), [1, 4, 2, 0, 3].map(AnyHashable.init))
        XCTAssertEqual(old.orderedChildrenForLab.map(\.id), new.orderedChildrenForLab.map(\.id))
    }

    func testLargeMixedAndNearlyOrderedListsMatchIndependentOrdering() throws {
        var seed: UInt64 = 0xACE981
        for count in [12, 64, 129] {
            for iteration in 0..<40 {
                var levels = (0..<count).map { index -> Int in
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    return iteration % 2 == 0 ? Int(seed % 19) - 9 : index / 3
                }
                levels[count - 1] = iteration % 3 == 0 ? Int.min : -1
                levels[count / 2] = iteration % 5 == 0 ? Int.max : levels[count / 2]
                let expected = levels.indices.sorted {
                    levels[$0] == levels[$1] ? $0 < $1 : levels[$0] < levels[$1]
                }.map(AnyHashable.init)
                let (old, new) = try pair(levels)
                XCTAssertEqual(old.orderedChildrenForLab.map(\.id), expected)
                XCTAssertEqual(new.orderedChildrenForLab.map(\.id), expected)
                XCTAssertEqual(new.children.map(\.id), levels.indices.map(AnyHashable.init))
            }
        }
    }

    func testCopyOnWriteAndReorderingDoNotMutateInputOrOldSnapshots() throws {
        let (old, new) = try pair([0, 0, 0, 0])
        var a = old.children, b = new.children
        let oldSnapshot = old.orderedChildrenForLab, newSnapshot = new.orderedChildrenForLab
        a.swapAt(0, 3); b.swapAt(0, 3)
        XCTAssertEqual(new.children.map(\.id), [0, 1, 2, 3].map(AnyHashable.init))
        try old.setChildren(a); try new.setChildren(b)
        XCTAssertEqual(old.orderedChildrenForLab.map(\.id), new.orderedChildrenForLab.map(\.id))
        XCTAssertEqual(oldSnapshot.map(\.id), newSnapshot.map(\.id))
        XCTAssertEqual(newSnapshot.map(\.id), [0, 1, 2, 3].map(AnyHashable.init))
        new.children[0].zIndex = 5; old.children[0].zIndex = 5
        XCTAssertFalse(new.orderingSharesStorageForLab)
        XCTAssertEqual(old.orderedChildrenForLab.map(\.id), new.orderedChildrenForLab.map(\.id))
        new.children[0].zIndex = 0; old.children[0].zIndex = 0
        XCTAssertTrue(new.orderingSharesStorageForLab)
        XCTAssertEqual(new.orderedChildrenForLab.map(\.id), [3, 1, 2, 0].map(AnyHashable.init))
    }

    func testHitAndAccessibilityOrderMatchAfterZAndChildChanges() throws {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let old = SortingBaseline.ChatLayerSceneView(frame: frame), new = ChatLayerEngine.ChatLayerSceneView(frame: frame)
        old.layout(); new.layout()
        let a = (0..<5).map { SortingBaseline.ChatLayerNode(id: $0) }
        let b = (0..<5).map { ChatLayerEngine.ChatLayerNode(id: $0) }
        for node in a { node.frame = CGRect(x: 10, y: 10, width: 80, height: 50); node.acceptsPointerEvents = true; node.accessibilityRole = .button; node.accessibilityLabel = String(describing: node.id) }
        for node in b { node.frame = CGRect(x: 10, y: 10, width: 80, height: 50); node.acceptsPointerEvents = true; node.accessibilityRole = .button; node.accessibilityLabel = String(describing: node.id) }
        try old.root.setChildren(a); try new.root.setChildren(b)
        let point = CGPoint(x: 20, y: 20)
        for step in 0..<30 {
            XCTAssertEqual(old.hitNode(at: point)?.id, new.hitNode(at: point)?.id)
            a[step % 5].zIndex = step % 7 - 3; b[step % 5].zIndex = step % 7 - 3
            if step % 3 == 0 { try old.root.setChildren(Array(a.reversed())); try new.root.setChildren(Array(b.reversed())) }
            if step % 3 == 1 { try old.root.setChildren(a); try new.root.setChildren(b) }
            XCTAssertEqual(old.hitNode(at: point)?.id, new.hitNode(at: point)?.id)
            let aa = old.accessibilityChildren()?.compactMap { ($0 as? NSAccessibilityProtocol)?.accessibilityLabel() }
            let bb = new.accessibilityChildren()?.compactMap { ($0 as? NSAccessibilityProtocol)?.accessibilityLabel() }
            XCTAssertEqual(aa, bb)
            XCTAssertEqual(old.root.orderedChildrenForLab.map(\.id), new.root.orderedChildrenForLab.map(\.id))
        }
    }

    func testCaptureSurvivesReorderingAndRemovalStillCancels() throws {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let old = SortingBaseline.ChatLayerSceneView(frame: frame), new = ChatLayerEngine.ChatLayerSceneView(frame: frame)
        old.layout(); new.layout()
        let a = (0..<3).map { SortingBaseline.ChatLayerNode(id: $0) }, b = (0..<3).map { ChatLayerEngine.ChatLayerNode(id: $0) }
        var oldEvents = [String](), newEvents = [String]()
        for node in a { node.frame = frame; node.acceptsPointerEvents = true; let id = node.id; node.onPointer = { oldEvents.append("\(id):\($0.kind)"); return $0.kind == .down } }
        for node in b { node.frame = frame; node.acceptsPointerEvents = true; let id = node.id; node.onPointer = { newEvents.append("\(id):\($0.kind)"); return $0.kind == .down } }
        try old.root.setChildren(a); try new.root.setChildren(b)
        let point = CGPoint(x: 20, y: 20)
        _ = old.handlePointer(.down, at: point); _ = new.handlePointer(.down, at: point)
        a[0].zIndex = 9; b[0].zIndex = 9
        _ = old.handlePointer(.up, at: point); _ = new.handlePointer(.up, at: point)
        XCTAssertEqual(oldEvents, newEvents)
        XCTAssertTrue(newEvents.contains("2:up"))
        _ = old.handlePointer(.down, at: point); _ = new.handlePointer(.down, at: point)
        try old.root.setChildren([]); try new.root.setChildren([])
        XCTAssertEqual(oldEvents, newEvents)
        XCTAssertTrue(newEvents.contains("0:cancelled"))
    }

    func testSharedOrderingReleasesRemovedNodes() throws {
        let root = ChatLayerEngine.ChatLayerNode(id: "root")
        weak var removed: ChatLayerEngine.ChatLayerNode?
        try autoreleasepool {
            var nodes = [ChatLayerEngine.ChatLayerNode(id: 0), ChatLayerEngine.ChatLayerNode(id: 1)]
            removed = nodes[0]
            try root.setChildren(nodes)
            XCTAssertTrue(root.orderingSharesStorageForLab)
            nodes.removeAll()
            XCTAssertNotNil(removed)
            try root.setChildren([])
        }
        XCTAssertNil(removed)
        XCTAssertTrue(root.orderedChildrenForLab.isEmpty)
    }
}
