import Cocoa
import CoreImage
import XCTest
import Darwin
import class TGUIKit.BlurEdgeView
import class TGUIKitBaseline.BlurEdgeView
import enum TGUIKit.BlurEdgeCacheInspection
import enum TGUIKit.ContainedViewLayoutTransition
import enum TGUIKitBaseline.ContainedViewLayoutTransition

final class BlurEdgeBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["BLUR_EDGE_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in blur edge benchmark") }
        TGUIKitTestBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["BLUR_EDGE_REVERSE"] == "1"
        let factory = BlurEdgeTests()
        let (a, b) = factory.pair(size: CGSize(width: 420, height: 48))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView!.addSubview(a); window.contentView!.addSubview(b)
        var results: [String: [[Double]]] = [:], sink = 0
        func measure(_ name: String, count: Int = 1000, operations: [() -> Int]) {
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
        measure("attached_repeated_layout", operations: [
            { a.layout(); return Int(a.bounds.width) },
            { b.layout(); return Int(b.bounds.width) }
        ])
        measure("attached_repeated_update", operations: [
            { a.update(edge: .bottom, edgeSize: 12, rect: a.frame, transition: .immediate); return Int(a.bounds.width) },
            { b.update(edge: .bottom, edgeSize: 12, rect: b.frame, transition: .immediate); return Int(b.bounds.width) }
        ])
        var oldIndex = 0, newIndex = 0
        measure("attached_radius_changes", operations: [
            { oldIndex += 1; a.blurRadius = CGFloat(oldIndex % 16); a.layout(); return Int(a.bounds.width) },
            { newIndex += 1; b.blurRadius = CGFloat(newIndex % 16); b.layout(); return Int(b.bounds.width) }
        ])
        measure("changing_size_17_values", count: 500, operations: [
            { oldIndex += 1; a.frame.size.width = CGFloat(460 + oldIndex % 17); a.layout(); return Int(a.bounds.width) },
            { newIndex += 1; b.frame.size.width = CGFloat(460 + newIndex % 17); b.layout(); return Int(b.bounds.width) }
        ])
        measure("create_destroy_17_sizes", count: 500, operations: [
            { oldIndex += 1; let view = TGUIKitBaseline.BlurEdgeView(frame: CGRect(x: 0, y: 0, width: 610 + oldIndex % 17, height: 35)); return Int(view.bounds.width) },
            { newIndex += 1; let view = TGUIKit.BlurEdgeView(frame: CGRect(x: 0, y: 0, width: 610 + newIndex % 17, height: 35)); return Int(view.bounds.width) }
        ])
        let (missA, missB) = factory.pair(size: CGSize(width: 420, height: 48))
        var oldMissIndex = 0, newMissIndex = 0
        measure("unique_padding_cache_misses", count: 500, operations: [
            { oldMissIndex += 1; missA.padding = CGFloat(oldMissIndex) * 0.001; missA.layout(); return Int(missA.bounds.width) },
            { newMissIndex += 1; missB.padding = CGFloat(newMissIndex) * 0.001; missB.layout(); return Int(missB.bounds.width) }
        ])
        let pairs = (0..<16).map { _ in factory.pair(size: CGSize(width: 420, height: 48)) }
        let oldMasks = try pairs.map { try factory.mask($0.0) }, newMasks = try pairs.map { try factory.mask($0.1) }
        func bitmapStorage(_ images: [CIImage]) throws -> [String: Int] {
            var bitmaps: [ObjectIdentifier: CGImage] = [:]
            for image in images {
                let bitmap = try XCTUnwrap(image.cgImage)
                bitmaps[ObjectIdentifier(bitmap)] = bitmap
            }
            return ["unique_masks": Set(images.map(ObjectIdentifier.init)).count, "unique_bitmaps": bitmaps.count, "unique_source_bitmap_bytes": bitmaps.values.reduce(0) { $0 + $1.bytesPerRow * $1.height }]
        }
        XCTAssertGreaterThan(sink, 0)
        let metadata: [String: Any] = ["unit": "microseconds_per_operation", "reverse": reverse, "batches_before_after": results, "retained_16_views": ["baseline": try bitmapStorage(oldMasks), "candidate": try bitmapStorage(newMasks)], "view_allocation_bytes": ["baseline": malloc_size(Unmanaged.passUnretained(a).toOpaque()), "candidate": malloc_size(Unmanaged.passUnretained(b).toOpaque())], "cache_entry_count": TGUIKit.BlurEdgeCacheInspection.count, "sink": sink]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/blur-edge-mask-benchmark.json"))
    }
}
