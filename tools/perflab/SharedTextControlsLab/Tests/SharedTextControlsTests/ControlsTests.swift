import Cocoa
import XCTest
import Darwin
import ObjectiveC.runtime
@testable import TGUIKit

private final class LabelSpy: TextViewLabel {
    var displayRequests = 0
    override func setNeedsDisplay() { displayRequests += 1; super.setNeedsDisplay() }
}

private final class InsetTitleBar: TitledBarView {
    var reservedWidth: CGFloat = 0
    override var inset: CGFloat { reservedWidth }
}

private final class ReferenceInsetTitleBar: ReferenceTitledBarView {
    var reservedWidth: CGFloat = 0
    override var inset: CGFloat { reservedWidth }
}

final class ControlsTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func text(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
    }

    private func field<T>(_ object: Any, _ name: String, as: T.Type = T.self) -> T? {
        var mirror: Mirror? = Mirror(reflecting: object)
        while let current = mirror {
            if let value = current.children.first(where: { $0.label == name })?.value as? T { return value }
            mirror = current.superclassMirror
        }
        return nil
    }

    private func pair(_ bar: TitledBarView, _ name: String) throws -> (TextNodeLayout, TextNode) {
        try XCTUnwrap(field(bar.containerView, name))
    }

    func testEmptyLabelDoesNotOwnUnusedTextNode() {
        let label = TextViewLabel(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
        XCTAssertNil(field(label, "node", as: TextNode.self))
        XCTAssertNil(label.text)
    }

    func testLabelReusesNodeAndUnchangedLayout() throws {
        let label = TextViewLabel(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
        label.attributedString = text("Search")
        let first = try XCTUnwrap(label.text)
        label.attributedString = text("Search")
        let second = try XCTUnwrap(label.text)
        XCTAssertTrue(first.0 === second.0)
        XCTAssertTrue(first.1 === second.1)
        label.attributedString = text("Different")
        XCTAssertTrue(first.1 === label.text?.1)
        XCTAssertFalse(first.0 === label.text?.0)
    }

    func testAutosizingLabelDoesNotInvalidateUnchangedDrawing() throws {
        let label = LabelSpy(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
        label.autosize = true
        label.attributedString = text("Search")
        label.layout()
        let layer: CALayer = try XCTUnwrap(field(label, "drawLayer"))
        layer.display()
        XCTAssertFalse(layer.needsDisplay())
        let first = try XCTUnwrap(label.text)
        label.displayRequests = 0
        label.layout()
        XCTAssertEqual(label.displayRequests, 0)
        XCTAssertTrue(first.0 === label.text?.0)
        XCTAssertFalse(layer.needsDisplay())
    }

    func testClearingAutosizingLabelReleasesItsNode() {
        let label = TextViewLabel(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
        label.autosize = true
        weak var node: TextNode?
        autoreleasepool {
            label.attributedString = text("Temporary")
            label.layout()
            node = label.text?.1
        }
        XCTAssertNotNil(node)
        label.attributedString = nil
        label.layout()
        XCTAssertNil(node)
        XCTAssertNil(label.text)
    }

    func testTitleLayoutAndStatusUpdatesPreserveUnchangedTitle() throws {
        let controller = ViewController()
        let bar = TitledBarView(controller: controller, text("A title"), text("Status"))
        bar.setFrameSize(NSSize(width: 220, height: 50))
        let title = try pair(bar, "titleNode"), status = try pair(bar, "statusNode")
        bar.containerView.layout()
        XCTAssertTrue(title.0 === (try pair(bar, "titleNode")).0)
        XCTAssertTrue(status.0 === (try pair(bar, "statusNode")).0)
        bar.status = text("Changed status")
        XCTAssertTrue(title.0 === (try pair(bar, "titleNode")).0)
        XCTAssertTrue(status.1 === (try pair(bar, "statusNode")).1)
        XCTAssertFalse(status.0 === (try pair(bar, "statusNode")).0)
    }

    func testTitleImageImmediatelyChangesAvailableTextWidth() throws {
        let controller = ViewController()
        let bar = TitledBarView(controller: controller, text(String(repeating: "long title ", count: 10)))
        bar.setFrameSize(NSSize(width: 180, height: 50))
        let previous = try pair(bar, "titleNode")
        let context = try XCTUnwrap(CGContext(data: nil, width: 80, height: 32, bitsPerComponent: 8, bytesPerRow: 320, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        bar.titleImage = (image, .left(topInset: 0))
        let next = try pair(bar, "titleNode")
        XCTAssertFalse(previous.0 === next.0)
        XCTAssertLessThan(next.0.size.width, previous.0.size.width)
        let original = ReferenceTitledBarView(controller: controller, bar.text)
        original.setFrameSize(bar.frame.size)
        original.titleImage = (image, .left(topInset: 0))
        original.containerView.layout()
        let expected: (TextNodeLayout, TextNode) = try XCTUnwrap(field(original.containerView, "titleNode"))
        XCTAssertEqual(next.0.size, expected.0.size)
    }

    func testReassigningMutatedTitleAndStatusUpdatesLayouts() throws {
        let controller = ViewController()
        let title = NSMutableAttributedString(attributedString: text("Short"))
        let status = NSMutableAttributedString(attributedString: text("Status"))
        let bar = TitledBarView(controller: controller, title, status)
        bar.setFrameSize(NSSize(width: 220, height: 50))
        let oldTitle = try pair(bar, "titleNode"), oldStatus = try pair(bar, "statusNode")
        title.replaceCharacters(in: NSRange(location: 0, length: title.length), with: "A different title")
        bar.text = title
        XCTAssertNotEqual(oldTitle.0.size, try pair(bar, "titleNode").0.size)
        status.replaceCharacters(in: NSRange(location: 0, length: status.length), with: "A different status")
        bar.status = status
        XCTAssertNotEqual(oldStatus.0.size, try pair(bar, "statusNode").0.size)
    }
    func testLabelRenderingMatchesOriginalAcrossUpdateSequences() throws {
        var comparisons = 0
        for string in ["Search messages", "שלום עולם", "🎉 hello 🚀", "first line\nsecond line"] {
            for width: CGFloat in [80, 180] {
                for autosize in [false, true] {
                    for alignment: NSTextAlignment in [.left, .center] {
                        let initial = NSRect(x: 4, y: 7, width: width, height: 54)
                        let actual = TextViewLabel(frame: initial), original = ReferenceTextViewLabel(frame: initial)
                        actual.autosize = autosize; original.autosize = autosize
                        actual.linesCount = 3; original.linesCount = 3
                        actual.alignment = alignment; original.alignment = alignment
                        actual.inset = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 9); original.inset = actual.inset
                        actual.attributedString = text(string); original.attributedString = text(string)
                        for step in 0..<4 {
                            if step == 1 {
                                let frame = NSRect(x: 9, y: 12, width: width + 25, height: 60)
                                actual.frame = frame; original.frame = frame
                            } else if step == 2 {
                                actual.sizeToFit(); original.sizeToFit()
                            } else if step == 3 {
                                actual.attributedString = text("Updated " + string); original.attributedString = text("Updated " + string)
                            }
                            actual.layout(); original.layout()
                            XCTAssertEqual(actual.frame, original.frame)
                            XCTAssertEqual(actual.text?.0.size, original.text?.0.size)
                            let first: CALayer = try XCTUnwrap(field(actual, "drawLayer"))
                            let second: CALayer = try XCTUnwrap(field(original, "drawLayer"))
                            for scale: CGFloat in [1, 2] {
                                first.contentsScale = scale; second.contentsScale = scale
                                XCTAssertEqual(try bitmap(size: first.frame.size, scale: scale) { first.draw(in: $0) }, try bitmap(size: second.frame.size, scale: scale) { second.draw(in: $0) })
                                comparisons += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 256)
    }

    func testHeaderRenderingAndTitleRectMatchOriginal() throws {
        let controller = ViewController()
        let icon = try makeImage()
        var comparisons = 0
        for string in ["A profile title", "ملف شخصي 👋"] {
            for width: CGFloat in [120, 220] {
                for hasStatus in [false, true] {
                    for side in 0..<3 {
                        for hidden in [false, true] {
                            for offset in [false, true] {
                                let actualRoot = View(frame: NSRect(x: 0, y: 0, width: 320, height: 50))
                                let originalRoot = View(frame: actualRoot.frame)
                                let actual = TitledBarView(controller: controller, text(string), hasStatus ? text("online recently") : nil)
                                let original = ReferenceTitledBarView(controller: controller, text(string), hasStatus ? text("online recently") : nil)
                                actualRoot.addSubview(actual); originalRoot.addSubview(original)
                                actual.setFrameSize(NSSize(width: width, height: 50)); original.setFrameSize(actual.frame.size)
                                actual.setFrameOrigin(NSPoint(x: 20, y: 0)); original.setFrameOrigin(actual.frame.origin)
                                if side != 0 {
                                    actual.titleImage = (icon, side == 1 ? .left(topInset: 1) : .right(topInset: -1))
                                    original.titleImage = (icon, side == 1 ? .left(topInset: 1) : .right(topInset: -1))
                                }
                                actual.hiddenStatus = hidden; original.hiddenStatus = hidden
                                actual.titleInset = offset ? 7 : nil; original.titleInset = actual.titleInset
                                actual.textInset = offset ? 14 : nil; original.textInset = actual.textInset
                                actual.containerView.layout(); original.containerView.layout()
                                XCTAssertEqual(actual.titleRect, original.titleRect)
                                for scale: CGFloat in [1, 2] {
                                    XCTAssertEqual(try renderContainer(actual.containerView, scale: scale), try renderContainer(original.containerView, scale: scale))
                                    comparisons += 1
                                }
                                withExtendedLifetime((actualRoot, originalRoot)) {}
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(comparisons, 192)
    }

    func testRepeatedPresentationAssignmentsRefreshDynamicHeaderInsets() throws {
        let controller = ViewController()
        for trigger in 0..<3 {
            let bar = InsetTitleBar(controller: controller, text(String(repeating: "long title ", count: 10)), text("Status"))
            bar.setFrameSize(NSSize(width: 220, height: 50))
            let original = ReferenceInsetTitleBar(controller: controller, bar.text, bar.status)
            original.setFrameSize(bar.frame.size)
            let before = try pair(bar, "titleNode")
            bar.reservedWidth = 70
            original.reservedWidth = 70
            switch trigger {
            case 0: bar.titleInset = nil; original.titleInset = nil
            case 1: bar.textInset = nil; original.textInset = nil
            default: bar.hiddenStatus = false; original.hiddenStatus = false
            }
            let after = try pair(bar, "titleNode")
            XCTAssertFalse(before.0 === after.0)
            XCTAssertLessThan(after.0.size.width, before.0.size.width)
            let expected: (TextNodeLayout, TextNode) = try XCTUnwrap(field(original.containerView, "titleNode"))
            XCTAssertEqual(after.0.size, expected.0.size)
        }
    }

    func testDrawingOnlyHeaderPropertiesPreserveMeasurementsAndInvalidatePixels() throws {
        let controller = ViewController()
        let bar = TitledBarView(controller: controller, text("Title"), text("Status"))
        bar.setFrameSize(NSSize(width: 220, height: 50))
        let first = try pair(bar, "titleNode"), second = try pair(bar, "statusNode")
        for step in 0..<3 {
            bar.containerView.layer?.display()
            switch step {
            case 0: bar.titleInset = 8
            case 1: bar.textInset = 10
            default: bar.hiddenStatus = true
            }
            XCTAssertTrue(bar.containerView.layer?.needsDisplay() == true)
            XCTAssertTrue(first.0 === (try pair(bar, "titleNode")).0)
            XCTAssertTrue(second.0 === (try pair(bar, "statusNode")).0)
        }
        bar.containerView.layer?.display()
        bar.hiddenStatus = true; bar.textInset = 10; bar.titleInset = 8
        XCTAssertFalse(bar.containerView.layer?.needsDisplay() ?? true)
    }

    func testLabelGeometryChangesStillInvalidateDrawing() throws {
        let label = TextViewLabel(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
        label.autosize = true
        label.attributedString = text("Search")
        label.layout()
        let layer: CALayer = try XCTUnwrap(field(label, "drawLayer"))
        layer.display()
        label.setFrameSize(NSSize(width: 190, height: 30))
        label.inset = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 0)
        label.layout()
        XCTAssertTrue(layer.needsDisplay())
        XCTAssertEqual(layer.frame, label.bounds)
    }

    func testClearingLabelInvalidatesAndClearsItsPixels() throws {
        let label = TextViewLabel(frame: NSRect(x: 0, y: 0, width: 180, height: 30))
        label.autosize = true
        label.attributedString = text("Temporary")
        label.layout()
        let layer: CALayer = try XCTUnwrap(field(label, "drawLayer"))
        layer.display()
        XCTAssertFalse(layer.needsDisplay())
        label.attributedString = nil
        label.layout()
        XCTAssertTrue(layer.needsDisplay())
        let context = try XCTUnwrap(CGContext(data: nil, width: 180, height: 30, bitsPerComponent: 8, bytesPerRow: 720, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        layer.draw(in: context)
        let data = Data(bytes: try XCTUnwrap(context.data), count: 720 * 30)
        XCTAssertTrue(data.allSatisfy { $0 == 0 })
    }

    func testUnchangedHeaderAssignmentDoesNotRequestDisplay() {
        let controller = ViewController()
        let bar = TitledBarView(controller: controller, text("Title"), text("Status"))
        bar.setFrameSize(NSSize(width: 220, height: 50))
        bar.containerView.layer?.display()
        bar.text = text("Title"); bar.status = text("Status")
        XCTAssertFalse(bar.containerView.layer?.needsDisplay() ?? true)
    }

    func testControlUpdateBenchmarkAndOwnedObjects() throws {
        guard ProcessInfo.processInfo.environment["SHARED_TEXT_BENCHMARK"] != nil else { throw XCTSkip("Opt-in control update benchmark") }
        let controller = ViewController()
        let label = TextViewLabel(frame: NSRect(x: 0, y: 0, width: 220, height: 30))
        let oldLabel = ReferenceTextViewLabel(frame: label.frame)
        let value = text("Search conversations")
        label.attributedString = value; oldLabel.attributedString = value
        let bar = TitledBarView(controller: controller, text("Conversation title"), text("Online"))
        let oldBar = ReferenceTitledBarView(controller: controller, text("Conversation title"), text("Online"))
        bar.setFrameSize(NSSize(width: 220, height: 50)); oldBar.setFrameSize(bar.frame.size)
        let statuses = [text("Online"), text("Last seen recently")]
        var report: [String: Any] = [:]
        for mode in ["label-update", "label-layout", "label-layout-display", "header-layout", "header-status", "header-inset"] {
            label.autosize = mode.hasPrefix("label-layout"); oldLabel.autosize = label.autosize
            label.layout(); oldLabel.layout()
            let currentLayer: CALayer = try XCTUnwrap(field(label, "drawLayer"))
            let originalLayer: CALayer = try XCTUnwrap(field(oldLabel, "drawLayer"))
            currentLayer.display(); originalLayer.display()
            var before: [Double] = [], after: [Double] = []
            var checksum: CGFloat = 0
            for batch in 0..<9 {
                for current in batch % 2 == 0 ? [false, true] : [true, false] {
                    let elapsed = autoreleasepool { () -> Double in
                        let start = CACurrentMediaTime()
                        for index in 0..<1000 {
                            if current {
                                switch mode {
                                case "label-update": label.attributedString = value
                                case "label-layout": label.layout()
                                case "label-layout-display":
                                    label.layout()
                                    if currentLayer.needsDisplay() { currentLayer.display() }
                                case "header-layout": bar.containerView.layout()
                                case "header-status": bar.status = statuses[index % 2]
                                default: bar.titleInset = 8
                                }
                                checksum += label.frame.width + bar.frame.width
                            } else {
                                switch mode {
                                case "label-update": oldLabel.attributedString = value
                                case "label-layout": oldLabel.layout()
                                case "label-layout-display":
                                    oldLabel.layout()
                                    if originalLayer.needsDisplay() { originalLayer.display() }
                                case "header-layout": oldBar.containerView.layout()
                                case "header-status": oldBar.status = statuses[index % 2]
                                default: oldBar.titleInset = 8
                                }
                                checksum += oldLabel.frame.width + oldBar.frame.width
                            }
                        }
                        return (CACurrentMediaTime() - start) * 1000
                    }
                    if current { after.append(elapsed) } else { before.append(elapsed) }
                }
            }
            XCTAssertGreaterThan(checksum, 0)
            report[mode] = ["original_ms_per_1000": before, "candidate_ms_per_1000": after]
        }
        var objects: [String: Any] = [:]
        for state in ["empty", "text", "autosize", "cleared"] {
            let current = TextViewLabel(frame: label.frame), original = ReferenceTextViewLabel(frame: label.frame)
            if state != "empty" { current.attributedString = value; original.attributedString = value }
            if state == "autosize" || state == "cleared" {
                current.autosize = true; original.autosize = true
                current.layout(); original.layout()
            }
            if state == "cleared" { current.attributedString = nil; original.attributedString = nil; current.layout(); original.layout() }
            objects[state] = ["original": ownedTextObjects(original), "candidate": ownedTextObjects(current)]
        }
        report["retained_objects"] = objects
        report["label_instance_bytes"] = ["original": class_getInstanceSize(ReferenceTextViewLabel.self), "candidate": class_getInstanceSize(TextViewLabel.self)]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/shared-text-benchmark.json"))
    }

    private func ownedTextObjects(_ view: AnyObject) -> [String: Int] {
        var nodes: [ObjectIdentifier: TextNode] = [:]
        if let node: TextNode = field(view, "node") { nodes[ObjectIdentifier(node)] = node }
        if let pair: (TextNodeLayout, TextNode) = field(view, "text") { nodes[ObjectIdentifier(pair.1)] = pair.1 }
        var objects: [ObjectIdentifier: AnyObject] = [ObjectIdentifier(view): view]
        var layouts = 0
        for node in nodes.values {
            objects[ObjectIdentifier(node)] = node
            if let layout: TextNodeLayout = field(node, "currentLayout") {
                objects[ObjectIdentifier(layout)] = layout
                layouts += 1
            }
        }
        return ["nodes": nodes.count, "layouts": layouts, "direct_bytes": objects.values.reduce(0) { $0 + malloc_size(Unmanaged.passUnretained($1).toOpaque()) }]
    }

    private func makeImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemBlue.cgColor); context.fill(NSRect(x: 0, y: 0, width: 32, height: 32))
        return try XCTUnwrap(context.makeImage())
    }

    private func renderContainer(_ view: View, scale: CGFloat) throws -> Data {
        try bitmap(size: view.frame.size, scale: scale) { view.draw(view.layer!, in: $0) }
    }

    private func bitmap(size: NSSize, scale: CGFloat, draw: (CGContext) -> Void) throws -> Data {
        let width = Int(ceil(max(1, size.width) * scale)), height = Int(ceil(max(1, size.height) * scale))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: scale, y: scale)
        draw(context)
        let data = Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
        XCTAssertTrue(data.contains { $0 != 0 })
        return data
    }
}
