import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine
@testable import LayoutBaseline

final class CountingLayer: SimpleLayer {
    var conversions = 0
    override func convert(_ rect: CGRect, to layer: CALayer?) -> CGRect {
        conversions += 1
        return super.convert(rect, to: layer)
    }
}

final class TrackingScene: ChatLayerEngine.ChatLayerSceneView {
    var rectangles: [NSView.ToolTipTag: CGRect] = [:]
    override func addToolTip(_ rect: NSRect, owner: Any, userData: UnsafeMutableRawPointer?) -> NSView.ToolTipTag {
        let tag = super.addToolTip(rect, owner: owner, userData: userData)
        rectangles[tag] = rect
        return tag
    }
    override func removeToolTip(_ tag: NSView.ToolTipTag) {
        rectangles.removeValue(forKey: tag)
        super.removeToolTip(tag)
    }
}

final class SceneLayoutTests: XCTestCase {
    struct Pair {
        let old: LayoutBaseline.ChatLayerSceneView
        let new: ChatLayerEngine.ChatLayerSceneView
        let a: [LayoutBaseline.ChatLayerNode]
        let b: [ChatLayerEngine.ChatLayerNode]
    }

    override func setUp() { TGUIKitTestBootstrap.install() }

    func pair(_ count: Int = 8, counting: Bool = true) throws -> Pair {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 300)
        let old = LayoutBaseline.ChatLayerSceneView(frame: frame)
        let new = ChatLayerEngine.ChatLayerSceneView(frame: frame)
        let a = (0..<count).map { LayoutBaseline.ChatLayerNode(id: $0, layer: counting ? CountingLayer() : SimpleLayer()) }
        let b = (0..<count).map { ChatLayerEngine.ChatLayerNode(id: $0, layer: counting ? CountingLayer() : SimpleLayer()) }
        for i in 0..<count {
            let rect = CGRect(x: 10 + (i % 8) * 50, y: 10 + (i / 8) * 40, width: 45, height: 35)
            a[i].frame = rect; b[i].frame = rect
            a[i].acceptsPointerEvents = true; b[i].acceptsPointerEvents = true
            a[i].acceptsKeyboardFocus = true; b[i].acceptsKeyboardFocus = true
        }
        try old.root.setChildren(a); try new.root.setChildren(b)
        old.layout(); new.layout()
        return Pair(old: old, new: new, a: a, b: b)
    }

    func testUnchangedLayoutsRetainIndexWithoutCoordinateConversions() throws {
        for hover in [false, true] {
            let p = try pair()
            let point = CGPoint(x: 20, y: 20)
            if hover { _ = p.old.handlePointer(.moved, at: point); _ = p.new.handlePointer(.moved, at: point) }
            XCTAssertEqual(p.old.hitNode(at: point)?.id, p.new.hitNode(at: point)?.id)
            let version = p.new.geometryVersion
            for n in p.a { (n.layer as! CountingLayer).conversions = 0 }
            for n in p.b { (n.layer as! CountingLayer).conversions = 0 }
            for _ in 0..<1000 {
                p.old.layout(); p.new.layout()
                XCTAssertEqual(p.old.hitNode(at: point)?.id, p.new.hitNode(at: point)?.id)
            }
            XCTAssertEqual(p.a.reduce(0) { $0 + ($1.layer as! CountingLayer).conversions }, 8000)
            XCTAssertEqual(p.b.reduce(0) { $0 + ($1.layer as! CountingLayer).conversions }, 0)
            XCTAssertEqual(p.new.geometryVersion, version)
            XCTAssertTrue(p.new.indexIsValidForLab)
            XCTAssertEqual(p.old.stateAllocationSizeForLab, p.new.stateAllocationSizeForLab)
        }
    }

    func testGeometryAndTreeChangesStillInvalidateAndMatchHitTargets() throws {
        let p = try pair()
        var comparisons = 0
        for step in 0..<100 {
            let i = step % p.a.count
            switch step % 10 {
            case 0:
                let rect = CGRect(x: CGFloat(step % 60), y: CGFloat(step % 30), width: 50 + CGFloat(step), height: 45)
                p.a[i].frame = rect; p.b[i].frame = rect
            case 1:
                let transform = CATransform3DMakeTranslation(CGFloat(step % 20), 12, 0)
                p.a[i].transform = transform; p.b[i].transform = transform
            case 2:
                let transform = CATransform3DMakeScale(1.1, 0.8, 1)
                p.old.root.sublayerTransform = transform; p.new.root.sublayerTransform = transform
            case 3:
                p.a[i].zIndex += 1; p.b[i].zIndex += 1
            case 4:
                p.a[i].acceptsPointerEvents.toggle(); p.b[i].acceptsPointerEvents.toggle()
            case 5:
                p.a[i].hitRegion = { $0.x > -10 && $0.x < 80 && $0.y > -10 && $0.y < 40 }
                p.b[i].hitRegion = { $0.x > -10 && $0.x < 80 && $0.y > -10 && $0.y < 40 }
            case 6:
                try p.old.root.setChildren(Array(p.old.root.children.reversed()))
                try p.new.root.setChildren(Array(p.new.root.children.reversed()))
            case 7:
                let size = CGSize(width: 400 + CGFloat(step), height: 200 + CGFloat(step))
                p.old.setFrameSize(size); p.new.setFrameSize(size)
            case 8:
                let origin = CGPoint(x: CGFloat(step % 8), y: CGFloat(step % 5))
                p.old.setBoundsOrigin(origin); p.new.setBoundsOrigin(origin)
            default:
                p.a[i].updateFrame(CGRect(x: 50, y: 60, width: 80, height: 70), transition: .immediate)
                p.b[i].updateFrame(CGRect(x: 50, y: 60, width: 80, height: 70), transition: .immediate)
            }
            p.old.layout(); p.new.layout()
            for y in stride(from: 0, through: 300, by: 15) {
                for x in stride(from: 0, through: 500, by: 20) {
                    let point = CGPoint(x: x, y: y)
                    XCTAssertEqual(p.old.hitNode(at: point)?.id, p.new.hitNode(at: point)?.id, "step=\(step) point=\(point)")
                    XCTAssertEqual(p.old.mayHitNode(at: point), p.new.mayHitNode(at: point))
                    comparisons += 1
                }
            }
        }
        XCTAssertEqual(comparisons, 54600)
    }

    func testLiveClippingVisibilityAndCustomRegionStillRunDuringLayout() throws {
        let p = try pair(2)
        p.a[1].frame = p.a[0].frame; p.b[1].frame = p.b[0].frame
        var enabled = true, oldCalls = 0, newCalls = 0
        p.a[1].hitRegion = { _ in oldCalls += 1; return enabled }
        p.b[1].hitRegion = { _ in newCalls += 1; return enabled }
        var a = [String](), b = [String]()
        p.a[0].onPointer = { a.append("0:\($0.kind)"); return $0.kind == .down }
        p.a[1].onPointer = { a.append("1:\($0.kind)"); return $0.kind == .down }
        p.b[0].onPointer = { b.append("0:\($0.kind)"); return $0.kind == .down }
        p.b[1].onPointer = { b.append("1:\($0.kind)"); return $0.kind == .down }
        let point = CGPoint(x: 10.1, y: 10.1)
        _ = p.old.handlePointer(.moved, at: point); _ = p.new.handlePointer(.moved, at: point)
        for i in 0..<100 {
            enabled = i % 2 == 0
            p.a[1].clipsChildren = i % 3 == 0; p.b[1].clipsChildren = i % 3 == 0
            p.a[1].layer.cornerRadius = CGFloat(i % 20); p.b[1].layer.cornerRadius = CGFloat(i % 20)
            p.a[1].isHidden = i % 5 == 0; p.b[1].isHidden = i % 5 == 0
            p.a[1].opacity = i % 7 == 0 ? 0 : 1; p.b[1].opacity = i % 7 == 0 ? 0 : 1
            p.a[1].isEnabled = i % 11 != 0; p.b[1].isEnabled = i % 11 != 0
            p.old.layout(); p.new.layout()
            _ = p.old.handlePointer(.down, at: point); _ = p.new.handlePointer(.down, at: point)
            _ = p.old.handlePointer(.up, at: point); _ = p.new.handlePointer(.up, at: point)
            XCTAssertEqual(p.old.hitNode(at: point)?.id, p.new.hitNode(at: point)?.id)
            XCTAssertEqual(p.old.focusedNode?.id, p.new.focusedNode?.id)
            XCTAssertEqual(a, b)
            XCTAssertEqual(oldCalls, newCalls)
        }
    }

    func testNestedTransformAndReentrantHoverGeometryChanges() throws {
        let p = try pair(2)
        let oldChild = LayoutBaseline.ChatLayerNode(id: "child"), newChild = ChatLayerEngine.ChatLayerNode(id: "child")
        oldChild.frame = CGRect(x: 0, y: 0, width: 100, height: 100); newChild.frame = oldChild.frame
        oldChild.acceptsPointerEvents = true; newChild.acceptsPointerEvents = true
        p.a[0].clipsChildren = true; p.b[0].clipsChildren = true
        try p.a[0].setChildren([oldChild]); try p.b[0].setChildren([newChild])
        var a = [String](), b = [String]()
        oldChild.onPointer = { [weak parent = p.a[0]] event in
            a.append("\(event.kind)")
            if event.kind == .entered { parent?.transform = CATransform3DMakeTranslation(150, 0, 0) }
            return false
        }
        newChild.onPointer = { [weak parent = p.b[0]] event in
            b.append("\(event.kind)")
            if event.kind == .entered { parent?.transform = CATransform3DMakeTranslation(150, 0, 0) }
            return false
        }
        let point = CGPoint(x: 20, y: 20)
        _ = p.old.handlePointer(.moved, at: point); _ = p.new.handlePointer(.moved, at: point)
        for _ in 0..<10 {
            p.old.layout(); p.new.layout()
            XCTAssertEqual(p.old.hitNode(at: point)?.id, p.new.hitNode(at: point)?.id)
            XCTAssertEqual(p.old.hitNode(at: CGPoint(x: 170, y: 20))?.id, p.new.hitNode(at: CGPoint(x: 170, y: 20))?.id)
            XCTAssertEqual(a, b)
        }
    }

    func testTooltipRectanglesFollowGeometryAndMutableSources() throws {
        let scene = TrackingScene(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        let parent = ChatLayerEngine.ChatLayerNode(id: "parent")
        let text = ChatLayerEngine.ChatLayerTextNode(id: "text", selectable: false)
        let attributed = NSMutableAttributedString(string: "First link Next link", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
        attributed.addAttribute(.link, value: "https://example.com", range: NSRange(location: 0, length: attributed.length))
        let layout = TextViewLayout(attributed, disableTooltips: false)
        layout.interactions.resolveLink = { $0 as? String }
        layout.measure(width: 250)
        try parent.setChildren([text]); try scene.root.setChildren([parent])
        text.update(layout, knownHasLinks: true, frame: CGRect(origin: CGPoint(x: 10, y: 10), size: layout.layoutSize))
        scene.layout()
        XCTAssertFalse(scene.rectangles.isEmpty)
        for i in 0..<40 {
            if i % 3 == 0 { parent.frame.origin = CGPoint(x: i, y: i % 5) }
            if i % 3 == 1 { parent.transform = CATransform3DMakeTranslation(CGFloat(i), 0, 0) }
            if i % 3 == 2 {
                layout.measure(width: CGFloat(80 + i))
                text.update(layout, knownHasLinks: true, frame: CGRect(origin: text.frame.origin, size: layout.layoutSize))
            }
            scene.layout()
            let expected = layout.toolTipRects.map { text.layer.convert($0, to: scene.root.layer) }
            XCTAssertEqual(Set(scene.rectangles.values.map(NSStringFromRect)), Set(expected.map(NSStringFromRect)))
            let version = scene.geometryVersion
            for _ in 0..<10 { scene.layout() }
            XCTAssertEqual(scene.geometryVersion, version)
        }
    }

    func testNativeHostedNamesFollowTheirMovingBackground() throws {
        for forward in [false, true] {
            let frame = CGRect(x: 0, y: 0, width: 500, height: 300)
            let old = LayoutBaseline.ChatLayerRowView(frame: frame), new = ChatLayerEngine.ChatLayerRowView(frame: frame)
            let a = View(frame: CGRect(x: 10, y: 10, width: 300, height: 200))
            let b = View(frame: a.frame)
            old.addSubview(a); new.addSubview(b)
            old.layerHitBackground = a; new.layerHitBackground = b
            func layout() -> TextViewLayout {
                let text = NSAttributedString(string: "Sender name", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black, .link: "https://example.com"])
                let result = TextViewLayout(text, disableTooltips: false)
                result.measure(width: 200)
                return result
            }
            if forward {
                _ = old.updateForwardName(layout(), frame: CGRect(x: 30, y: 30, width: 100, height: 25), animated: false)
                _ = new.updateForwardName(layout(), frame: CGRect(x: 30, y: 30, width: 100, height: 25), animated: false)
            } else {
                old.updateSenderName(layout(), toolTip: "Sender", frame: CGRect(x: 30, y: 30, width: 100, height: 25), animated: false)
                new.updateSenderName(layout(), toolTip: "Sender", frame: CGRect(x: 30, y: 30, width: 100, height: 25), animated: false)
            }
            old.layout(); new.layout()
            let restoreA = forward ? old.moveForwardNameForShake(into: a) : old.moveSenderNameForShake(into: a)
            let restoreB = forward ? new.moveForwardNameForShake(into: b) : new.moveSenderNameForShake(into: b)
            old.layout(); new.layout()
            let oldNode = try XCTUnwrap(forward ? old.forwardName : old.senderName)
            let newNode = try XCTUnwrap(forward ? new.forwardName : new.senderName)
            let local = CGPoint(x: 4, y: 4)
            let initial = oldNode.layer.convert(local, to: old.root.layer)
            XCTAssertNotNil(old.hitNode(at: initial)); XCTAssertNotNil(new.hitNode(at: initial))
            a.setFrameOrigin(CGPoint(x: 150, y: 100)); b.setFrameOrigin(a.frame.origin)
            old.layout(); new.layout()
            let moved = oldNode.layer.convert(local, to: old.root.layer)
            XCTAssertEqual(moved, newNode.layer.convert(local, to: new.root.layer))
            XCTAssertTrue(old.hitNode(at: moved) === oldNode)
            XCTAssertTrue(new.hitNode(at: moved) === newNode)
            XCTAssertEqual(old.hitNode(at: initial)?.id, new.hitNode(at: initial)?.id)
            restoreA?(); restoreB?()
            old.layout(); new.layout()
            XCTAssertEqual(old.hitNode(at: moved)?.id, new.hitNode(at: moved)?.id)
        }
    }

    func testTransformedRootLayoutsMatch() throws {
        let p = try pair(4)
        for step in 0..<24 {
            let angle = CGFloat(step) * .pi / 16
            let transform = CATransform3DMakeRotation(angle, 0, 0, 1)
            p.old.root.transform = transform; p.new.root.transform = transform
            for _ in 0..<4 {
                p.old.layout(); p.new.layout()
                for y in stride(from: 0, through: 300, by: 20) {
                    for x in stride(from: 0, through: 500, by: 20) {
                        let point = CGPoint(x: x, y: y)
                        XCTAssertEqual(p.old.hitNode(at: point)?.id, p.new.hitNode(at: point)?.id)
                    }
                }
            }
        }
    }

    func testRemovedNodesReleaseAndDeferredScenesStayEmpty() throws {
        let scene = ChatLayerEngine.ChatLayerSceneView(frame: CGRect(x: 0, y: 0, width: 200, height: 100), deferred: true)
        for _ in 0..<100 { scene.layout() }
        XCTAssertFalse(scene.hasLayerContent)
        weak var removed: ChatLayerEngine.ChatLayerNode?
        try autoreleasepool {
            let node = ChatLayerEngine.ChatLayerNode(id: "temporary")
            node.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
            node.acceptsPointerEvents = true
            try scene.root.setChildren([node])
            scene.layout()
            XCTAssertTrue(scene.hitNode(at: CGPoint(x: 20, y: 20)) === node)
            removed = node
        }
        try scene.root.setChildren([])
        XCTAssertNil(removed)
        XCTAssertTrue(scene.releaseEmptyLayerContent())
        scene.layout()
        XCTAssertFalse(scene.hasLayerContent)
    }
}
