import Cocoa
import XCTest
import TGUIKit
@testable import ChatLayerEngine

final class RowTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install(); System.updateScaleFactor(2) }
    override func tearDown() { System.updateScaleFactor(2) }
    func testCompleteRowBitmapParityAndViewCount() throws {
        var comparisons = 0
        for scale in [CGFloat(1), 2, 3] {
            System.updateScaleFactor(scale)
            for width in [CGFloat(320), 460, 620] {
                for variant in 0..<4 {
                    try autoreleasepool {
                        let native = NativePlainRow(PlainRowFixture(width: width, variant: variant))
                        let candidate = LayerPlainRow(PlainRowFixture(width: width, variant: variant))
                        XCTAssertEqual(viewTreeCount(candidate.view), 1)
                        XCTAssertEqual(viewTreeCount(native.view), 15)
                        let a = ViewSnapshot.render(native.view, scale: scale)
                        let b = ViewSnapshot.render(candidate.view, scale: scale)
                        let differences = a.differingPixels(from: b, tolerance: 0)
                        if differences > 0 || ProcessInfo.processInfo.environment["CHAT_LAYER_SAVE_RENDERS"] != nil {
                            let path = URL(fileURLWithPath: "/tmp/chat-layer-engine-renders")
                            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
                            try a.write(to: path.appendingPathComponent("views-\(scale)-\(width)-\(variant).png"))
                            try b.write(to: path.appendingPathComponent("layers-\(scale)-\(width)-\(variant).png"))
                        }
                        XCTAssertEqual(differences, 0, "scale=\(scale) width=\(width) variant=\(variant)")
                        XCTAssertGreaterThan(a.pixels(darkerThan: 150), 100)
                        comparisons += 1
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 36)
    }
    func testRowActionsSelectionAndRebinding() throws {
        let candidate = LayerPlainRow(PlainRowFixture())
        var actions: [String] = []
        candidate.onAction = { actions.append($0) }
        for id in ["avatar", "reply", "reaction", "action"] {
            let node = try XCTUnwrap(candidate.nodes[id])
            let point = node.layer.convert(NSPoint(x: node.layer.bounds.midX, y: node.layer.bounds.midY), to: candidate.view.root.layer)
            XCTAssertTrue(candidate.view.hitNode(at: point) === node, id)
            XCTAssertTrue(candidate.view.handlePointer(.down, at: point))
            XCTAssertTrue(candidate.view.handlePointer(.up, at: point))
            XCTAssertEqual(actions.last, id)
        }
        let oldBody = try XCTUnwrap(candidate.nodes["body"] as? ChatLayerTextNode)
        oldBody.setSelection(NSRange(location: 0, length: 5))
        for variant in 1...20 {
            candidate.bind(PlainRowFixture(width: 320 + CGFloat(variant % 4) * 50, variant: variant))
            XCTAssertTrue(candidate.nodes["body"] === oldBody)
            XCTAssertEqual(candidate.view.subviews.count, 0)
            XCTAssertEqual(candidate.nodes.count, 14)
            XCTAssertEqual(candidate.view.root.children.count, 4)
        }
        XCTAssertEqual(oldBody.textLayout?.selectedRange.range.location, NSNotFound)
    }
    func testButtonCaptureCancellationKeyboardAndAccessibility() throws {
        let scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        scene.layout()
        var actions = 0
        let button = ChatLayerButtonNode(id: "button", label: "Action") { actions += 1 }
        button.frame = NSRect(x: 10, y: 10, width: 70, height: 30)
        try scene.root.setChildren([button])
        _ = scene.handlePointer(.down, at: NSPoint(x: 20, y: 20))
        _ = scene.handlePointer(.dragged, at: NSPoint(x: 200, y: 50))
        _ = scene.handlePointer(.up, at: NSPoint(x: 200, y: 50))
        XCTAssertEqual(actions, 0)
        _ = scene.handlePointer(.down, at: NSPoint(x: 20, y: 20))
        button.isEnabled = false
        _ = scene.handlePointer(.up, at: NSPoint(x: 20, y: 20))
        XCTAssertEqual(actions, 0)
        button.isEnabled = true
        scene.focus(button)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        scene.keyDown(with: key)
        XCTAssertEqual(actions, 1)
        TGUIKitAccessibility.isEnabled = true
        let accessible = try XCTUnwrap(scene.accessibilityChildren()?.first as? NSAccessibilityProtocol)
        XCTAssertTrue(accessible.accessibilityPerformPress())
        XCTAssertEqual(actions, 2)
        button.isHidden = true
        XCTAssertFalse(accessible.accessibilityPerformPress())
    }
}

extension RowTests {
    func testAccessibilityIsReachableThroughDocument() throws {
        TGUIKitAccessibility.isEnabled = true
        let document = ChatLayerDemo.makeDocument(layerBased: true, count: 3, onAction: { _ in })
        let elements = AccessibilityAudit.elements(document)
        XCTAssertGreaterThan(elements.count, 30)
        XCTAssertEqual(elements.filter { $0.accessibilityLabel() == "Reply" }.count, 3)
        XCTAssertEqual(elements.filter { $0.accessibilityLabel() == "Open profile" }.count, 3)
        XCTAssertTrue(AccessibilityAudit.audit(document).isEmpty)
    }
}

extension RowTests {
    func testCompleteRowHitGridMatchesNativeActionTargets() {
        var points = 0
        for variant in 0..<4 {
            let native = NativePlainRow(PlainRowFixture(variant: variant))
            let candidate = LayerPlainRow(PlainRowFixture(variant: variant))
            let parent = View(frame: native.view.frame)
            parent.addSubview(native.view)
            let identifiers = Dictionary(uniqueKeysWithValues: native.views.map { (ObjectIdentifier($0.value), $0.key) })
            let actionIds = Set(["avatar", "reply", "reaction", "action", "body"])
            func action(_ hit: NSView?) -> String? {
                var current = hit
                while let view = current {
                    if let id = identifiers[ObjectIdentifier(view)], actionIds.contains(id) { return id }
                    current = view.superview
                }
                return nil
            }
            for y in stride(from: CGFloat(0.5), to: native.view.frame.height, by: 3) {
                for x in stride(from: CGFloat(0.5), to: native.view.frame.width, by: 3) {
                    let point = NSPoint(x: x, y: y)
                    let expected = action(native.view.hitTest(point))
                    let actual = candidate.view.hitNode(at: point)?.id as? String
                    XCTAssertEqual(expected, actual, "\(variant), \(point)")
                    points += 1
                }
            }
        }
        XCTAssertGreaterThan(points, 40_000)
        print("ROW_HIT_GRID \(points) checked points")
    }
}
