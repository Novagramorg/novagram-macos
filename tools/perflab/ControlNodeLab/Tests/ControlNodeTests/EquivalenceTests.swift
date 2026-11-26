import Cocoa
import XCTest
import TGUIKit
import LabSupport
import SceneLab
import SceneLabMutant

final class EquivalenceTests: XCTestCase {
    let inside = NSPoint(x: 100, y: 70)
    let outside = NSPoint(x: 250, y: 160)

    @discardableResult
    func compare(_ name: String, _ config: HarnessConfig = HarnessConfig(), file: StaticString = #filePath, line: UInt = #line, _ steps: (HarnessBase) -> Void) -> [String] {
        let control = ControlHarness(config: config)
        steps(control)
        let expected = control.finish()
        let node = SceneLab.NodeHarness(config: config)
        steps(node)
        let actual = node.finish()
        print("[\(name)] control: \(expected)")
        if expected != actual { print("[\(name)] node:    \(actual)") }
        XCTAssertEqual(expected, actual, name, file: file, line: line)
        return expected
    }

    func events(_ log: [String]) -> [String] { log.filter { $0.hasPrefix("event:") || $0.hasPrefix("menu:presented") || $0.hasPrefix("next:") } }

    func testClick() {
        let log = compare("click") { h in
            h.move(inside); h.down(inside); h.up(inside)
        }
        XCTAssertEqual(events(log), ["event:Down", "event:Up", "event:SingleClick", "event:Click"])
        XCTAssertTrue(log.contains("clickTimestamp"))
        XCTAssertTrue(log.contains("state:Highlight now=Highlight"))
    }

    func testDoubleClick() {
        let log = compare("double click") { h in
            h.move(inside); h.down(inside); h.up(inside); h.down(inside, clickCount: 2); h.up(inside, clickCount: 2)
        }
        XCTAssertTrue(events(log).contains("event:DoubleClick"))
    }

    func testDragOut() {
        let log = compare("drag out") { h in
            h.move(inside); h.down(inside); h.drag(outside); h.up(outside)
        }
        XCTAssertFalse(log.contains("event:Click"))
        XCTAssertTrue(log.contains("state:Normal now=Normal"))
        XCTAssertTrue(log.last?.hasPrefix("state:Other now=Normal") == true)
    }

    func testDragOutAndBack() {
        let log = compare("drag out and back") { h in
            h.move(inside); h.down(inside); h.drag(outside); h.drag(inside); h.up(inside)
        }
        XCTAssertTrue(log.contains("event:Click"))
    }

    func testLongPressStill() {
        let log = compare("long press still") { h in
            h.move(inside); h.down(inside); h.wait(0.45); h.up(inside)
        }
        XCTAssertEqual(events(log), ["event:Down", "event:LongMouseDown", "event:Up", "event:LongMouseUp"])
    }

    func testReleaseBeforeLongPress() {
        let log = compare("release at 0.27 s") { h in
            h.move(inside); h.down(inside); h.wait(0.27); h.up(inside)
        }
        XCTAssertTrue(log.contains("event:Click"))
        XCTAssertFalse(log.contains("event:LongMouseDown"))
    }

    func testLongPressMovedThreePoints() {
        let log = compare("long press moved 3 pt") { h in
            h.move(inside); h.down(inside); h.drag(NSPoint(x: inside.x + 3, y: inside.y)); h.wait(0.45); h.up(NSPoint(x: inside.x + 3, y: inside.y))
        }
        XCTAssertFalse(log.contains("event:LongMouseDown"))
        XCTAssertTrue(log.contains("event:Click"))
    }

    func testLongPressMovedOnePoint() {
        let log = compare("long press moved 1 pt") { h in
            h.move(inside); h.down(inside); h.drag(NSPoint(x: inside.x + 1, y: inside.y)); h.wait(0.45); h.up(NSPoint(x: inside.x + 1, y: inside.y))
        }
        XCTAssertTrue(log.contains("event:LongMouseDown"))
    }

    func testLongPressMenuWithoutLongHandler() {
        var config = HarnessConfig()
        config.hasContextMenu = true
        config.events.removeAll { $0 == .LongMouseDown }
        let log = compare("long press menu, no LongMouseDown handler", config) { h in
            h.move(inside); h.down(inside); h.wait(0.45); h.up(inside)
        }
        XCTAssertEqual(log.filter { $0 == "menu:presented" }.count, 1)
    }

    func testLongPressMenuWithLongHandler() {
        var config = HarnessConfig()
        config.hasContextMenu = true
        let log = compare("long press menu, with LongMouseDown handler", config) { h in
            h.move(inside); h.down(inside); h.wait(0.45); h.up(inside)
        }
        XCTAssertFalse(log.contains("menu:presented"))
        XCTAssertTrue(log.contains("event:LongMouseDown"))
    }

    func testClickMenuWithoutHandlers() {
        var config = HarnessConfig()
        config.hasContextMenu = true
        config.events = []
        let log = compare("click shows menu when there are no handlers", config) { h in
            h.move(inside); h.down(inside); h.up(inside)
        }
        XCTAssertEqual(log.filter { $0 == "menu:presented" }.count, 1)
    }

    func testRightClickMenu() {
        var config = HarnessConfig()
        config.hasContextMenu = true
        let log = compare("right click with menu", config) { h in
            h.move(inside); h.rightDown(inside); h.rightUp(inside)
        }
        XCTAssertEqual(events(log), ["menu:presented", "event:RightUp"])
    }

    func testRightClickForwarded() {
        let log = compare("right click, no menu, sendRightMouseAnyway") { h in
            h.move(inside); h.rightDown(inside); h.rightUp(inside)
        }
        XCTAssertTrue(log.contains("event:RightDown"))
        XCTAssertTrue(log.contains("next:rightMouseDown"))
    }

    func testRightClickNotForwarded() {
        var config = HarnessConfig()
        config.sendRightMouseAnyway = false
        let log = compare("right click, no menu, no forwarding", config) { h in
            h.move(inside); h.rightDown(inside); h.rightUp(inside)
        }
        XCTAssertTrue(log.contains("event:RightDown"))
        XCTAssertFalse(log.contains("next:rightMouseDown"))
    }

    func testControlClick() {
        for anyway in [true, false] {
            for menu in [true, false] {
                var config = HarnessConfig()
                config.sendRightMouseAnyway = anyway
                config.hasContextMenu = menu
                let log = compare("control-click anyway=\(anyway) menu=\(menu)", config) { h in
                    h.move(inside); h.down(inside, modifiers: .control); h.up(inside, modifiers: .control)
                }
                XCTAssertEqual(log.contains("next:mouseDown"), anyway)
                XCTAssertEqual(log.contains("menu:presented"), menu)
                XCTAssertTrue(log.contains("event:RightUp"))
            }
        }
    }

    func testUserInteractionDisabled() {
        var config = HarnessConfig()
        config.userInteractionEnabled = false
        let log = compare("userInteractionEnabled false", config) { h in
            h.move(inside); h.down(inside); h.drag(NSPoint(x: inside.x + 1, y: inside.y)); h.up(inside); h.rightDown(inside); h.rightUp(inside)
        }
        XCTAssertTrue(log.contains("next:mouseDown"))
        XCTAssertTrue(log.contains("next:mouseUp"))
        XCTAssertFalse(log.contains("event:Click"))
    }

    func testDisabled() {
        var config = HarnessConfig()
        config.isEnabled = false
        let log = compare("isEnabled false", config) { h in
            h.move(inside); h.down(inside); h.up(inside)
        }
        XCTAssertTrue(log.contains("event:Down"))
        XCTAssertFalse(log.contains("event:Click"))
    }

    func testWindowMovedBetweenDownAndUp() {
        let log = compare("window moved") { h in
            h.move(inside); h.down(inside); h.moveWindow(); h.up(inside)
        }
        XCTAssertFalse(log.contains("event:Up"))
        XCTAssertFalse(log.contains("event:Click"))
    }

    func testHover() {
        let log = compare("hover enter, long over, exit") { h in
            h.move(outside); h.move(inside); h.wait(0.35); h.move(outside); h.move(inside); h.exitWindow()
        }
        XCTAssertTrue(log.contains("event:LongOver"))
        XCTAssertTrue(log.contains("state:Hover now=Hover"))
    }

    func testScaleOnClick() {
        var config = HarnessConfig()
        config.scaleOnClick = true
        let log = compare("scaleOnClick", config) { h in
            h.move(inside); h.down(inside); h.recordAnimations(); h.up(inside); h.recordAnimations()
        }
        XCTAssertTrue(log.contains { $0.hasPrefix("animation") && $0.contains("1.03") })
    }

    func testScaleDownOnClick() {
        var config = HarnessConfig()
        config.scaleDownOnClick = true
        let log = compare("scaleDownOnClick", config) { h in
            h.move(inside); h.down(inside); h.recordAnimations(); h.drag(outside); h.recordAnimations(); h.up(outside); h.recordAnimations()
        }
        XCTAssertTrue(log.contains { $0.hasPrefix("animation") && $0.contains("0.97") })
    }

    func testToolTipRects() {
        let h = SceneLab.NodeHarness(config: HarnessConfig())
        let view = h.sceneView
        XCTAssertEqual(ToolTipRecorder.rects(for: view), [])
        h.toolTip = "Hint"
        XCTAssertEqual(ToolTipRecorder.rects(for: view), [NSRect(x: 50, y: 50, width: 100, height: 40)])
        h.nodeFrame = NSRect(x: 40, y: 30, width: 110, height: 40)
        XCTAssertEqual(ToolTipRecorder.rects(for: view), [NSRect(x: 60, y: 50, width: 110, height: 40)])
        h.groupFrame = NSRect(x: 25, y: 20, width: 200, height: 100)
        h.move(NSPoint(x: 100, y: 70))
        XCTAssertEqual(ToolTipRecorder.rects(for: view), [NSRect(x: 65, y: 50, width: 110, height: 40)])
        h.toolTip = nil
        XCTAssertEqual(ToolTipRecorder.rects(for: view), [])
        h.toolTip = "Hint"
        XCTAssertEqual(ToolTipRecorder.rects(for: view).count, 1)
        h.removeNodeFromScene()
        XCTAssertEqual(ToolTipRecorder.rects(for: view), [])
        h.readdNodeToScene()
        XCTAssertEqual(ToolTipRecorder.rects(for: view), [NSRect(x: 65, y: 50, width: 110, height: 40)])
        _ = h.finish()
    }

    func testMutantIsDetected() {
        let steps: (HarnessBase) -> Void = { h in
            h.move(self.inside); h.down(self.inside); h.wait(0.27); h.up(self.inside)
        }
        let control = ControlHarness(config: HarnessConfig())
        steps(control)
        let expected = control.finish()
        let mutant = SceneLabMutant.NodeHarness(config: HarnessConfig())
        steps(mutant)
        let actual = mutant.finish()
        print("[mutant] control: \(expected)")
        print("[mutant] mutant:  \(actual)")
        if ProcessInfo.processInfo.environment["LAB_EXPECT_MUTANT_EQUAL"] == "1" {
            XCTAssertEqual(expected, actual, "mutant long-press delay 0.2 s")
        } else {
            XCTAssertNotEqual(expected, actual)
            XCTAssertTrue(actual.contains("event:LongMouseDown"))
            XCTAssertFalse(expected.contains("event:LongMouseDown"))
        }
    }
}
