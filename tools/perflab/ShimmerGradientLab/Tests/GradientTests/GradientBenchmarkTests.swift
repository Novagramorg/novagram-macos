import Cocoa
import XCTest
import Darwin
import ObjectiveC
import class TGUIKit.StickerShimmerEffectView
import class TGUIKitBaseline.StickerShimmerEffectView
import enum TGUIKit.GradientCacheInspection
import enum TGUIKitBaseline.GradientCacheInspection

final class GradientBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["SHIMMER_GRADIENT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in gradient timings") }
        MeasureBootstrap.install()
        let reverse = ProcessInfo.processInfo.environment["SHIMMER_GRADIENT_REVERSE"] == "1"
        var results: [String: [[Double]]] = [:], sizes: [String: [Int]] = [:]
        var sink = 0
        for layer in [false, true] {
            let prefix = layer ? "layer" : "view"
            let anchors = [gradient(layer: layer, baseline: true), gradient(layer: layer, baseline: false)]
            for anchor in anchors { anchor.update(GradientInput()) }
            sizes[prefix + "_allocation"] = anchors.map { malloc_size(Unmanaged.passUnretained($0.object).toOpaque()) }
            sizes[prefix + "_instance"] = anchors.map { class_getInstanceSize(object_getClass($0.object)!) }
            for operation in ["unchanged", "construct_shared", "unique_colors", "duration_changes"] {
                if layer && operation == "duration_changes" { continue }
                var batches = [[Double](), [Double]()]
                let count = operation == "unchanged" ? 10000 : 300
                for batch in 0..<9 {
                    for variant in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                        autoreleasepool {
                            var retained: [GradientHarness] = []; retained.reserveCapacity(count)
                            let start = CACurrentMediaTime()
                            for index in 0..<count {
                                var input = GradientInput()
                                if operation == "unique_colors" {
                                    let value = batch * count + index
                                    input.foreground = NSColor(deviceRed: CGFloat(value % 64) / 64, green: CGFloat((value / 64) % 64) / 64, blue: 0.8, alpha: 0.35)
                                } else if operation == "duration_changes" { input.duration = index % 2 == 0 ? 1 : 2 }
                                if operation == "construct_shared" || operation == "unique_colors" {
                                    let value = gradient(layer: layer, baseline: variant == 0); value.update(input); retained.append(value)
                                } else { anchors[variant].update(input) }
                            }
                            batches[variant].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                            sink += retained.count + (anchors[variant].image()?.width ?? 0)
                            retained.removeAll()
                            CATransaction.flush()
                        }
                    }
                }
                results[prefix + "_" + operation] = batches
            }
        }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(frame: window.contentView!.bounds); host.wantsLayer = true; window.contentView = host
        defer { window.close() }
        for layer in [false, true] {
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                for variant in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                    var total = 0.0
                    for _ in 0..<40 {
                        weak var releasedOwner: AnyObject?
                        autoreleasepool {
                            let start = CACurrentMediaTime()
                            var value: GradientHarness? = gradient(layer: layer, baseline: variant == 0)
                            var input = GradientInput(); input.foreground = NSColor(deviceRed: 0.73, green: 0.29, blue: 0.02, alpha: 0.61)
                            value!.update(input)
                            total += CACurrentMediaTime() - start
                            sink += value!.image()?.width ?? 0
                            releasedOwner = value!.object
                            if layer {
                                let native = value!.object as! CALayer
                                host.layer!.addSublayer(native); native.removeFromSuperlayer()
                            }
                            value = nil
                            CATransaction.flush()
                        }
                        XCTAssertNil(releasedOwner)
                    }
                    batches[variant].append(total * 1e6 / 40)
                }
            }
            results[(layer ? "layer" : "view") + "_recreate_after_owner_release"] = batches
        }
        var detailed = Data([0, 128])
        for index in 0..<60 { detailed.append(contentsOf: [203, UInt8((index * 17) % 64), UInt8(128 + (index * 31) % 64)]) }
        for hasPath in [false, true] {
            var batches = [[Double](), [Double]()]
            let data: Data? = hasPath ? detailed : nil
            for batch in 0..<9 {
                for variant in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                    autoreleasepool {
                        var retained: [AnyObject] = []; retained.reserveCapacity(200)
                        let start = CACurrentMediaTime()
                        for _ in 0..<200 {
                            if variant == 0 {
                                let value = TGUIKitBaseline.StickerShimmerEffectView()
                                value.update(backgroundColor: nil, data: data, size: CGSize(width: 64, height: 48))
                                retained.append(value)
                            } else {
                                let value = TGUIKit.StickerShimmerEffectView()
                                value.update(backgroundColor: nil, data: data, size: CGSize(width: 64, height: 48))
                                retained.append(value)
                            }
                        }
                        batches[variant].append((CACurrentMediaTime() - start) * 1e6 / 200)
                        sink += retained.count
                        retained.removeAll()
                        CATransaction.flush()
                    }
                }
            }
            results["sticker_construct_" + (hasPath ? "detailed_path" : "rounded")] = batches
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "reverse": reverse, "batches": results, "object_bytes": sizes], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/shimmer-gradient-benchmark.json"))
    }
}
