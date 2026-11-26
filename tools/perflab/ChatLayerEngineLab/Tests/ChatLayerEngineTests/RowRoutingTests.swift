import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

private final class NativeHitCounter { var calls = 0 }
private final class CountingNativeView: View {
    let counter: NativeHitCounter
    init(frame: NSRect, counter: NativeHitCounter) { self.counter = counter; super.init(frame: frame) }
    required init(frame: NSRect) { fatalError() }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { counter.calls += 1; return super.hitTest(point) }
}
private final class MutatingNativeView: View {
    var beforeHit: (() -> Void)?
    override func hitTest(_ point: NSPoint) -> NSView? {
        let action = beforeHit
        beforeHit = nil
        action?()
        return super.hitTest(point)
    }
}
private final class RoutingTrace { var events: [String] = [] }

private final class RoutingFixture {
    let host: View
    let background: View
    let counter = NativeHitCounter()
    let trace = RoutingTrace()
    let hit: (NSPoint) -> String?
    let pointer: (Int, NSPoint) -> Bool
    let setTargetFrame: (NSRect) -> Void
    let hideTarget: (Bool) -> Void
    let setCursor: (NSCursor) -> Void
    let removeTarget: () -> Void

    init(reference: Bool, counting: Bool = true, recording: Bool = true) {
        let frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        background = counting ? CountingNativeView(frame: frame, counter: counter) : View(frame: frame)
        let trace = trace
        if reference {
            let scene = ReferenceRowInteractionView(frame: frame)
            host = scene
            scene.layerHitBackground = background
            let parent = ReferenceChatLayerNode(id: "parent"), child = ReferenceChatLayerNode(id: "target")
            parent.frame = NSRect(x: 5, y: 5, width: 120, height: 60)
            child.frame = NSRect(x: 5, y: 5, width: 100, height: 30)
            child.acceptsPointerEvents = true
            child.cursor = .pointingHand
            for node in [parent, child] {
                let id = node.id, capturesDown = node === child
                node.onPointer = { event in
                    if recording { trace.events.append("\(id):\(event.kind)") }
                    return event.kind == .down && capturesDown
                }
            }
            try! parent.setChildren([child])
            try! scene.root.setChildren([parent])
            scene.layout()
            hit = { scene.hitNode(at: $0)?.id as? String }
            pointer = { kind, point in scene.handlePointer([.down, .dragged, .up, .moved][kind], at: point) }
            setTargetFrame = { child.frame = $0 }
            hideTarget = { child.isHidden = $0 }
            setCursor = { child.cursor = $0 }
            removeTarget = { try! parent.setChildren([]) }
        } else {
            let scene = ChatLayerRowView(frame: frame)
            host = scene
            scene.layerHitBackground = background
            let parent = ChatLayerNode(id: "parent"), child = ChatLayerNode(id: "target")
            parent.frame = NSRect(x: 5, y: 5, width: 120, height: 60)
            child.frame = NSRect(x: 5, y: 5, width: 100, height: 30)
            child.acceptsPointerEvents = true
            child.cursor = .pointingHand
            for node in [parent, child] {
                let id = node.id, capturesDown = node === child
                node.onPointer = { event in
                    if recording { trace.events.append("\(id):\(event.kind)") }
                    return event.kind == .down && capturesDown
                }
            }
            try! parent.setChildren([child])
            try! scene.root.setChildren([parent])
            scene.layout()
            hit = { scene.hitNode(at: $0)?.id as? String }
            pointer = { kind, point in scene.handlePointer([.down, .dragged, .up, .moved][kind], at: point) }
            setTargetFrame = { child.frame = $0 }
            hideTarget = { child.isHidden = $0 }
            setCursor = { child.cursor = $0 }
            removeTarget = { try! parent.setChildren([]) }
        }
        host.addSubview(background)
        for index in 0..<24 {
            let frame = NSRect(x: 250 + index % 6 * 20, y: 100 + index / 6 * 20, width: 18, height: 18)
            let view = counting ? CountingNativeView(frame: frame, counter: counter) : View(frame: frame)
            host.addSubview(view)
        }
    }
}

final class RowRoutingTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func testPointsWithoutLayerTargetsSkipNativeTraversal() {
        let reference = RoutingFixture(reference: true), current = RoutingFixture(reference: false)
        let point = NSPoint(x: 180, y: 150)
        reference.counter.calls = 0
        current.counter.calls = 0
        XCTAssertNil(reference.hit(point))
        XCTAssertNil(current.hit(point))
        XCTAssertGreaterThan(reference.counter.calls, 0)
        XCTAssertEqual(current.counter.calls, 0)
        current.hideTarget(true)
        current.counter.calls = 0
        XCTAssertNil(current.hit(NSPoint(x: 20, y: 20)))
        XCTAssertEqual(current.counter.calls, 0)
    }

    func testNativePriorityAndOffsetCoordinatesMatchAcrossGridAndMutations() {
        let reference = RoutingFixture(reference: true), current = RoutingFixture(reference: false)
        let parent = View(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        parent.addSubview(current.host)
        current.host.frame.origin = NSPoint(x: 25, y: 35)
        let overlays = [reference, current].map { fixture -> NSButton in
            let overlay = NSButton(title: "Native", target: nil, action: nil)
            overlay.frame = NSRect(x: 40, y: 12, width: 30, height: 20)
            fixture.host.addSubview(overlay)
            return overlay
        }
        for variant in 0..<4 {
            overlays.forEach { $0.isHidden = variant == 1 }
            [reference, current].forEach {
                $0.hideTarget(variant == 2)
                if variant == 3 { $0.setTargetFrame(NSRect(x: 80, y: 50, width: 100, height: 30)) }
            }
            for y in stride(from: -5, through: 205, by: 5) {
                for x in stride(from: -5, through: 405, by: 5) {
                    let point = NSPoint(x: x, y: y)
                    XCTAssertEqual(reference.hit(point), current.hit(point), "variant=\(variant) point=\(point)")
                }
            }
        }
        withExtendedLifetime(parent) {}
    }

    func testNativeHitCallbackCannotReturnARemovedOrMovedLayer() {
        for remove in [false, true] {
            let fixture = RoutingFixture(reference: false)
            let blocker = MutatingNativeView(frame: NSRect(x: 300, y: 150, width: 20, height: 20))
            fixture.host.addSubview(blocker)
            blocker.beforeHit = {
                if remove { fixture.removeTarget() }
                else { fixture.setTargetFrame(NSRect(x: 150, y: 100, width: 50, height: 20)) }
            }
            XCTAssertNil(fixture.hit(NSPoint(x: 20, y: 20)))
        }
    }

    func testPointerTraceAndCursorChangesMatchWhenHoverTargetIsUnchanged() {
        let reference = RoutingFixture(reference: true), current = RoutingFixture(reference: false)
        let point = NSPoint(x: 20, y: 20), outside = NSPoint(x: 450, y: 250)
        for fixture in [reference, current] {
            for _ in 0..<40 { _ = fixture.pointer(3, point) }
            fixture.setCursor(.iBeam)
            _ = fixture.pointer(3, point)
            XCTAssertEqual(NSCursor.current, .iBeam)
            _ = fixture.pointer(0, point)
            _ = fixture.pointer(1, outside)
            _ = fixture.pointer(2, outside)
            _ = fixture.pointer(3, point)
            fixture.hideTarget(true)
            _ = fixture.pointer(3, point)
        }
        XCTAssertEqual(reference.trace.events, current.trace.events)
        XCTAssertEqual(current.trace.events.filter { $0 == "target:entered" }.count, 2)
    }

    func testRoutingBenchmarks() throws {
        guard ProcessInfo.processInfo.environment["CHAT_ROUTING_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in native/layer routing benchmark") }
        let fixtures = [RoutingFixture(reference: true, counting: false, recording: false), RoutingFixture(reference: false, counting: false, recording: false)]
        var results: [String: [[Double]]] = [:], sink = 0
        for (name, point) in [("name", NSPoint(x: 20, y: 20)), ("body", NSPoint(x: 180, y: 150)), ("outside", NSPoint(x: 450, y: 250))] {
            for movement in [false, true] {
                let actions = fixtures.map { fixture in
                    return {
                        if movement { if fixture.pointer(3, point) { sink += 1 } }
                        else if fixture.hit(point) != nil { sink += 1 }
                    }
                }
                actions.forEach { action in for _ in 0..<100 { action() } }
                var samples = [[Double](), [Double]()]
                for batch in 0..<9 {
                    let reverse = ProcessInfo.processInfo.environment["CHAT_ROUTING_REVERSE"] == "1"
                    for mode in (batch % 2 == 0) != reverse ? [0, 1] : [1, 0] {
                        let start = CACurrentMediaTime()
                        for _ in 0..<10000 { actions[mode]() }
                        samples[mode].append((CACurrentMediaTime() - start) * 100)
                    }
                }
                results["\(movement ? "move" : "hit")_\(name)"] = samples
            }
        }
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "modes": ["before", "current"], "batches": results, "sink": sink], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/chat-routing-benchmark.json"))
    }
}


extension RowRoutingTests {
    func testStableHoverUpdatesInheritedCursorAndReparentingSendsBalancedEvents() throws {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let first = ChatLayerNode(id: "first"), second = ChatLayerNode(id: "second"), child = ChatLayerNode(id: "child")
        first.frame = scene.bounds
        second.frame = scene.bounds
        child.frame = NSRect(x: 10, y: 10, width: 100, height: 30)
        child.acceptsPointerEvents = true
        first.cursor = .pointingHand
        second.cursor = .crosshair
        var events: [String] = []
        for node in [first, second, child] {
            let id = node.id
            node.onPointer = { event in events.append("\(id):\(event.kind)"); return false }
        }
        try first.setChildren([child])
        try scene.root.setChildren([first, second])
        scene.layout()
        let point = NSPoint(x: 20, y: 20)
        _ = scene.handlePointer(.moved, at: point)
        XCTAssertEqual(NSCursor.current, .pointingHand)
        events.removeAll()
        first.cursor = .iBeam
        _ = scene.handlePointer(.moved, at: point)
        XCTAssertEqual(NSCursor.current, .iBeam)
        XCTAssertEqual(events, ["child:moved", "first:moved"])
        events.removeAll()
        try first.setChildren([])
        try second.setChildren([child])
        XCTAssertEqual(events, ["child:exited", "first:exited", "second:entered", "child:entered"])
        XCTAssertEqual(NSCursor.current, .crosshair)
    }

    func testReentrantHitRegionCannotPublishAStaleHoverPath() throws {
        let frame = NSRect(x: 0, y: 0, width: 200, height: 80), point = NSPoint(x: 10, y: 10)
        let reference = ReferenceChatLayerSceneView(frame: frame), current = ChatLayerSceneView(frame: frame)
        let oldNode = ReferenceChatLayerNode(id: "old"), node = ChatLayerNode(id: "new")
        oldNode.frame = frame
        node.frame = frame
        oldNode.acceptsPointerEvents = true
        node.acceptsPointerEvents = true
        try reference.root.setChildren([oldNode])
        try current.root.setChildren([node])
        reference.layout()
        current.layout()
        var oldFirstHit = true, firstHit = true, oldEvents: [String] = [], events: [String] = []
        oldNode.onPointer = { oldEvents.append("\($0.kind)"); return false }
        node.onPointer = { events.append("\($0.kind)"); return false }
        oldNode.hitRegion = { [weak reference] _ in
            if oldFirstHit { oldFirstHit = false; reference?.updateHover(at: nil) }
            return true
        }
        node.hitRegion = { [weak current] _ in
            if firstHit { firstHit = false; current?.updateHover(at: nil) }
            return true
        }
        reference.updateHover(at: point)
        current.updateHover(at: point)
        XCTAssertTrue(reference.hasActiveInput)
        XCTAssertFalse(current.hasActiveInput)
        reference.updateHover(at: nil)
        current.updateHover(at: nil)
        XCTAssertEqual(oldEvents, ["exited"])
        XCTAssertTrue(events.isEmpty)
    }
}


extension RowRoutingTests {
    func testBoundsFilterRunsCustomHitRegionsOnceAfterNativeControls() throws {
        let scene = ChatLayerRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let node = ChatLayerNode(id: "custom")
        node.frame = NSRect(x: 10, y: 10, width: 20, height: 20)
        node.acceptsPointerEvents = true
        try scene.root.setChildren([node])
        scene.layout()
        var nativeWasChecked = false, hitCalls = 0
        node.hitRegion = { point in
            XCTAssertTrue(nativeWasChecked)
            hitCalls += 1
            return point.x < 200
        }
        let native = MutatingNativeView(frame: NSRect(x: 250, y: 70, width: 20, height: 20))
        native.beforeHit = { nativeWasChecked = true }
        scene.addSubview(native)
        XCTAssertTrue(scene.hitNode(at: NSPoint(x: 100, y: 20)) === node)
        XCTAssertEqual(hitCalls, 1)
        node.isHidden = true
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 100, y: 20)))
        XCTAssertEqual(hitCalls, 1)
    }

    func testBoundsFilterPreservesTransformedAndRoundedHits() throws {
        let frame = NSRect(x: 0, y: 0, width: 200, height: 100)
        let reference = ReferenceRowInteractionView(frame: frame), current = ChatLayerRowView(frame: frame)
        let oldParent = ReferenceChatLayerNode(id: "parent"), oldChild = ReferenceChatLayerNode(id: "target")
        let parent = ChatLayerNode(id: "parent"), child = ChatLayerNode(id: "target")
        oldParent.frame = NSRect(x: 20, y: 20, width: 80, height: 60)
        parent.frame = oldParent.frame
        oldChild.frame = NSRect(x: -10, y: -10, width: 100, height: 80)
        child.frame = oldChild.frame
        oldChild.acceptsPointerEvents = true
        child.acceptsPointerEvents = true
        oldParent.layer.cornerRadius = 20
        parent.layer.cornerRadius = 20
        try oldParent.setChildren([oldChild])
        try parent.setChildren([child])
        try reference.root.setChildren([oldParent])
        try current.root.setChildren([parent])
        reference.layout()
        current.layout()
        for variant in 0..<4 {
            oldParent.clipsChildren = variant > 0
            parent.clipsChildren = variant > 0
            oldChild.transform = variant > 1 ? CATransform3DMakeRotation(.pi / 6, 0, 0, 1) : CATransform3DIdentity
            child.transform = oldChild.transform
            oldParent.isHidden = variant == 3
            parent.isHidden = variant == 3
            for y in stride(from: 0, through: 100, by: 2) {
                for x in stride(from: 0, through: 200, by: 2) {
                    let point = NSPoint(x: x, y: y)
                    XCTAssertEqual(reference.hitNode(at: point)?.id, current.hitNode(at: point)?.id, "variant=\(variant) point=\(point)")
                }
            }
        }
    }

    func testNativeHitMutationFindsTheNewTargetUnderThePointer() throws {
        for mutation in 0..<3 {
            let scene = ChatLayerRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
            let underneath = ChatLayerNode(id: "underneath"), original = ChatLayerNode(id: "original")
            for node in [underneath, original] {
                node.frame = NSRect(x: 10, y: 10, width: 80, height: 30)
                node.acceptsPointerEvents = true
            }
            try scene.root.setChildren([underneath, original])
            scene.layout()
            let native = MutatingNativeView(frame: NSRect(x: 250, y: 70, width: 20, height: 20))
            scene.addSubview(native)
            native.beforeHit = {
                switch mutation {
                case 0: try! scene.root.setChildren([underneath])
                case 1: original.isHidden = true
                default: original.acceptsPointerEvents = false
                }
            }
            XCTAssertTrue(scene.hitNode(at: NSPoint(x: 20, y: 20)) === underneath, "mutation=\(mutation)")
        }
    }

    func testNativeHitCanReplaceSceneAndReuseTheNodeAtAnotherPosition() throws {
        let scene = ChatLayerRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let node = ChatLayerNode(id: "reused")
        node.acceptsPointerEvents = true
        try scene.root.setChildren([node])
        for offset in 0..<40 { node.frame = NSRect(x: offset, y: 10, width: 80, height: 30) }
        node.frame = NSRect(x: 10, y: 10, width: 80, height: 30)
        scene.layout()
        let generation = scene.geometryVersion
        let native = MutatingNativeView(frame: NSRect(x: 250, y: 70, width: 20, height: 20))
        scene.addSubview(native)
        native.beforeHit = {
            try! scene.root.setChildren([])
            XCTAssertTrue(scene.releaseEmptyLayerContent())
            node.frame = NSRect(x: 150, y: 50, width: 80, height: 30)
            try! scene.root.setChildren([node])
            while scene.geometryVersion < generation { node.frame.origin.x += 1 }
            XCTAssertEqual(scene.geometryVersion, generation)
        }
        XCTAssertNil(scene.hitNode(at: NSPoint(x: 20, y: 20)))
        XCTAssertTrue(node.scene === scene)
        XCTAssertGreaterThan(node.frame.minX, 100)
    }
}
