import Cocoa
import XCTest
import QuartzCore
import Darwin
import class TGUIKit.VisualEffect
import class TGUIKitBaseline.VisualEffect

final class MaskBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["MASK_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in mask benchmark") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let factory = MaskTests(), image = MaskTests().bitmap()
        let reverse = ProcessInfo.processInfo.environment["MASK_REVERSE"] == "1"
        let frame = NSRect(x: 0, y: 0, width: 60, height: 40)
        var sink = 0
        var results: [String: [[Double]]] = [:]
        func measure(_ name: String, count: Int = 500, _ operations: [() -> Int]) {
            for operation in operations { for _ in 0..<30 { autoreleasepool { sink += operation() } } }
            CATransaction.flush()
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                for index in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                    CATransaction.begin()
                    let start = CACurrentMediaTime()
                    for _ in 0..<count { autoreleasepool { sink += operations[index]() } }
                    batches[index].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                    CATransaction.commit()
                    CATransaction.flush()
                }
            }
            results[name] = batches
        }
        measure("construct_unmasked", [
            { let view = TGUIKitBaseline.VisualEffect(frame: frame); return Int(view.frame.width) },
            { let view = TGUIKit.VisualEffect(frame: frame); return Int(view.frame.width) }
        ])
        measure("construct_masked", [
            { let view = TGUIKitBaseline.VisualEffect(frame: frame); view.maskContents = image; return Int(view.frame.width) },
            { let view = TGUIKit.VisualEffect(frame: frame); view.maskContents = image; return Int(view.frame.width) }
        ])
        let old = TGUIKitBaseline.VisualEffect(frame: frame), new = TGUIKit.VisualEffect(frame: frame)
        measure("assign_nil", [
            { old.maskContents = nil; return Int(old.frame.width) },
            { new.maskContents = nil; return Int(new.frame.width) }
        ])
        measure("assign_same_mask", [
            { old.maskContents = image; return Int(old.frame.width) },
            { new.maskContents = image; return Int(new.frame.width) }
        ])
        measure("toggle_mask", [
            { old.maskContents = nil; old.maskContents = image; return Int(old.frame.width) },
            { new.maskContents = nil; new.maskContents = image; return Int(new.frame.width) }
        ])
        let oldHost = ReferencePanelHost(), newHost = CandidatePanelHost()
        for lite in [true, false] {
            for images: [CGImage?] in [[nil, nil, nil], [nil, image, nil], [image, image, image]] {
                let item = factory.item(lite: lite, images: images)
                oldHost.applyCutBands(item); newHost.applyCutBands(item)
                measure("panels_\(lite ? "flat" : "blur")_\(images.compactMap { $0 }.count)_masks", [
                    { oldHost.applyCutBands(item); return oldHost.cutBandViews.count },
                    { newHost.applyCutBands(item); return newHost.cutBandViews.count }
                ])
            }
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 150), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView!.addSubview(oldHost.rowView)
        window.contentView!.addSubview(newHost.rowView)
        for lite in [true, false] {
            let item = factory.item(lite: lite, images: [nil, image, nil])
            oldHost.applyCutBands(item); newHost.applyCutBands(item)
            measure("attached_panels_\(lite ? "flat" : "blur")_1_mask", [
                { oldHost.applyCutBands(item); oldHost.rowView.layoutSubtreeIfNeeded(); return oldHost.cutBandViews.count },
                { newHost.applyCutBands(item); newHost.rowView.layoutSubtreeIfNeeded(); return newHost.cutBandViews.count }
            ])
        }
        var allocationCounts: [[String: Int]] = []
        for baseline in [true, false] {
            autoreleasepool {
                let views: [NSView] = (0..<1000).map { _ in baseline ? TGUIKitBaseline.VisualEffect(frame: frame) : TGUIKit.VisualEffect(frame: frame) }
                var layers = 0, bytes = 0
                for view in views {
                    for name in ["overlay", "overlayMask"] {
                        if let layer = factory.storedLayer(view, name) {
                            layers += 1
                            bytes += malloc_size(Unmanaged.passUnretained(layer).toOpaque())
                        }
                    }
                }
                allocationCounts.append(["views": views.count, "explicit_layer_count": layers, "explicit_layer_object_bytes": bytes, "view_object_bytes_each": malloc_size(Unmanaged.passUnretained(views[0]).toOpaque())])
                sink += views.count
            }
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "reverse": reverse, "batches_before_after": results, "unmasked_retained_objects_before_after": allocationCounts, "sink": sink], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/visual-effect-mask-benchmark.json"))
    }
}
