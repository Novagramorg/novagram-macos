import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine
@testable import LayoutBaseline

final class SceneLayoutBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["SCENE_LAYOUT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in scene layout benchmark") }
        TGUIKitTestBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["SCENE_LAYOUT_REVERSE"] == "1"
        var sink = 0, results: [String: [[Double]]] = [:]
        func measure(_ name: String, count: Int = 5000, operations: [() -> Int]) {
            for op in operations { for _ in 0..<100 { sink += op() } }
            CATransaction.flush()
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                for variant in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                    autoreleasepool {
                        CATransaction.begin()
                        let start = CACurrentMediaTime()
                        for _ in 0..<count { sink += operations[variant]() }
                        batches[variant].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                        CATransaction.commit()
                    }
                    CATransaction.flush()
                }
            }
            results[name] = batches
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let factory = SceneLayoutTests()
        let point = CGPoint(x: 20, y: 20)
        for count in [1, 8, 32] {
            let p = try factory.pair(count, counting: false)
            window.contentView!.addSubview(p.old); window.contentView!.addSubview(p.new)
            _ = p.old.hitNode(at: point); _ = p.new.hitNode(at: point)
            measure("layout_only_\(count)", operations: [
                { p.old.layout(); return p.old.root.children.count },
                { p.new.layout(); return p.new.root.children.count }
            ])
            measure("layout_and_hit_\(count)", operations: [
                { p.old.layout(); return p.old.hitNode(at: point) == nil ? 0 : 1 },
                { p.new.layout(); return p.new.hitNode(at: point) == nil ? 0 : 1 }
            ])
            _ = p.old.handlePointer(.moved, at: point); _ = p.new.handlePointer(.moved, at: point)
            measure("layout_with_hover_\(count)", operations: [
                { p.old.layout(); return p.old.root.children.count },
                { p.new.layout(); return p.new.root.children.count }
            ])
            var a = false, b = false
            measure("changed_geometry_with_hover_\(count)", operations: [
                { a.toggle(); p.a[0].frame.origin.x = a ? 11 : 10; p.old.layout(); return p.old.root.children.count },
                { b.toggle(); p.b[0].frame.origin.x = b ? 11 : 10; p.new.layout(); return p.new.root.children.count }
            ])
            p.old.cancelInput(); p.new.cancelInput()
            measure("changed_scene_size_\(count)", operations: [
                { a.toggle(); p.old.setFrameSize(CGSize(width: a ? 500 : 510, height: 300)); p.old.layout(); return p.old.hitNode(at: point) == nil ? 0 : 1 },
                { b.toggle(); p.new.setFrameSize(CGSize(width: b ? 500 : 510, height: 300)); p.new.layout(); return p.new.hitNode(at: point) == nil ? 0 : 1 }
            ])
            p.old.removeFromSuperview(); p.new.removeFromSuperview()
        }
        let aFixtures = (0..<4).map { LayoutBaseline.PlainRowFixture(width: 400 + CGFloat($0 % 2) * 20, variant: $0) }
        let bFixtures = (0..<4).map { ChatLayerEngine.PlainRowFixture(width: 400 + CGFloat($0 % 2) * 20, variant: $0) }
        let oldRow = LayoutBaseline.LayerPlainRow(aFixtures[0]), newRow = ChatLayerEngine.LayerPlainRow(bFixtures[0])
        window.contentView!.addSubview(oldRow.view); window.contentView!.addSubview(newRow.view)
        let body = CGPoint(x: 80, y: 80)
        XCTAssertNotNil(oldRow.view.hitNode(at: body)); XCTAssertNotNil(newRow.view.hitNode(at: body))
        _ = oldRow.view.handlePointer(.moved, at: body); _ = newRow.view.handlePointer(.moved, at: body)
        measure("premeasured_row_layout_with_hover", operations: [
            { oldRow.view.layout(); return oldRow.nodes.count },
            { newRow.view.layout(); return newRow.nodes.count }
        ])
        measure("unchanged_row_rebind_with_hover", count: 2000, operations: [
            { oldRow.bind(aFixtures[0]); oldRow.view.layoutSubtreeIfNeeded(); return oldRow.nodes.count },
            { newRow.bind(bFixtures[0]); newRow.view.layoutSubtreeIfNeeded(); return newRow.nodes.count }
        ])
        var a = 0, b = 0
        measure("changed_row_rebind_with_hover", count: 2000, operations: [
            { defer { a += 1 }; oldRow.bind(aFixtures[a % 4]); oldRow.view.layoutSubtreeIfNeeded(); return oldRow.nodes.count },
            { defer { b += 1 }; newRow.bind(bFixtures[b % 4]); newRow.view.layoutSubtreeIfNeeded(); return newRow.nodes.count }
        ])
        measure("premeasured_row_construction", count: 1000, operations: [
            { defer { a += 1 }; return LayoutBaseline.LayerPlainRow(aFixtures[a % 4]).nodes.count },
            { defer { b += 1 }; return ChatLayerEngine.LayerPlainRow(bFixtures[b % 4]).nodes.count }
        ])
        let oldNames = LayoutBaseline.ChatLayerRowView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        let newNames = ChatLayerEngine.ChatLayerRowView(frame: oldNames.frame)
        let oldBackground = View(frame: CGRect(x: 10, y: 10, width: 300, height: 200))
        let newBackground = View(frame: oldBackground.frame)
        oldNames.addSubview(oldBackground); newNames.addSubview(newBackground)
        oldNames.layerHitBackground = oldBackground; newNames.layerHitBackground = newBackground
        window.contentView!.addSubview(oldNames); window.contentView!.addSubview(newNames)
        func nameLayout() -> TextViewLayout {
            let text = NSAttributedString(string: "Sender name", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black, .link: "https://example.com"])
            let layout = TextViewLayout(text, disableTooltips: false)
            layout.measure(width: 200)
            return layout
        }
        oldNames.updateSenderName(nameLayout(), toolTip: "Sender", frame: CGRect(x: 30, y: 30, width: 100, height: 25), animated: false)
        newNames.updateSenderName(nameLayout(), toolTip: "Sender", frame: CGRect(x: 30, y: 30, width: 100, height: 25), animated: false)
        let namePoint = CGPoint(x: 34, y: 34)
        _ = oldNames.handlePointer(.moved, at: namePoint); _ = newNames.handlePointer(.moved, at: namePoint)
        measure("sender_name_layout_with_hover", operations: [
            { oldNames.layout(); return oldNames.root.children.count },
            { newNames.layout(); return newNames.root.children.count }
        ])
        let restoreA = oldNames.moveSenderNameForShake(into: oldBackground)
        let restoreB = newNames.moveSenderNameForShake(into: newBackground)
        measure("native_hosted_sender_layout_with_hover", operations: [
            { oldNames.layout(); return oldNames.root.children.count },
            { newNames.layout(); return newNames.root.children.count }
        ])
        restoreA?(); restoreB?()
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "reverse": reverse, "batches_before_after": results], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-scene-layout-benchmark.json"))
    }
}
