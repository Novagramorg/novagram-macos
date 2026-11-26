import Cocoa
import XCTest
import QuartzCore
import Darwin
import class TGUIKit.DrawingContext
import struct TGUIKit.System
import struct TGUIKit.DeviceGraphicsContextSettings
import func TGUIKit.setDisplayColorSpace
import class TGUIKitBaseline.DrawingContext
import struct TGUIKitBaseline.System
import struct TGUIKitBaseline.DeviceGraphicsContextSettings
import func TGUIKitBaseline.setDisplayColorSpace

final class ContextBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["DRAWING_CONTEXT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in drawing-context benchmark") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        TGUIKit.System.updateScaleFactor(2)
        TGUIKitBaseline.System.updateScaleFactor(2)
        TGUIKit.setDisplayColorSpace(nil)
        TGUIKitBaseline.setDisplayColorSpace(nil)
        let factory = ContextTests()
        let reverse = ProcessInfo.processInfo.environment["DRAWING_CONTEXT_REVERSE"] == "1"
        var results: [String: [[Double]]] = [:]
        var sink = 0
        func measure(_ name: String, count: Int, operations: [() -> Int]) {
            for op in operations { for _ in 0..<50 { sink += op() } }
            var batches = [[Double](), [Double]()]
            for batch in 0..<9 {
                for mode in ((batch % 2 == 0) != reverse ? [0, 1] : [1, 0]) {
                    let start = CACurrentMediaTime()
                    for _ in 0..<count { autoreleasepool { sink += operations[mode]() } }
                    batches[mode].append((CACurrentMediaTime() - start) * 1e6 / Double(count))
                }
            }
            results[name] = batches
        }
        let samples = UnsafeMutablePointer<Int>.allocate(capacity: 4)
        samples.initialize(repeating: 0, count: 4)
        defer { samples.deinitialize(count: 4); samples.deallocate(); TGUIKitBaseline.DeviceGraphicsContextSettings.install(nil); TGUIKitBaseline.setDisplayColorSpace(nil); TGUIKit.DeviceGraphicsContextSettings.install(nil); TGUIKit.setDisplayColorSpace(nil) }
        for format in ["default", "installed_srgb", "installed_float"] {
            if format == "installed_srgb" { TGUIKit.DeviceGraphicsContextSettings.install(factory.format(CGColorSpace.sRGB)); TGUIKitBaseline.DeviceGraphicsContextSettings.install(factory.format(CGColorSpace.sRGB)) }
            if format == "installed_float" { TGUIKit.DeviceGraphicsContextSettings.install(factory.format(CGColorSpace.extendedLinearSRGB, floating: true)); TGUIKitBaseline.DeviceGraphicsContextSettings.install(factory.format(CGColorSpace.extendedLinearSRGB, floating: true)) }
            for size in [CGSize(width: 16, height: 16), CGSize(width: 120, height: 80), CGSize(width: 512, height: 288)] {
                let name = "\(format)_\(Int(size.width))x\(Int(size.height))"
                let iterations = size.width > 128 ? 150 : 1500
                measure(name + "_construct", count: iterations, operations: [
                    { TGUIKitBaseline.DrawingContext(size: size, scale: 2, clear: true).length },
                    { TGUIKit.DrawingContext(size: size, scale: 2, clear: true).length }
                ])
                measure(name + "_paint_export", count: iterations, operations: [
                    { let c = TGUIKitBaseline.DrawingContext(size: size, scale: 2, clear: true); c.withContext { factory.paint($0, size: size) }; return c.generateImage()!.width },
                    { let c = TGUIKit.DrawingContext(size: size, scale: 2, clear: true); c.withContext { factory.paint($0, size: size) }; return c.generateImage()!.width }
                ])
            }
            let old = TGUIKitBaseline.DrawingContext(size: CGSize(width: 16, height: 16), scale: 2, clear: true)
            let new = TGUIKit.DrawingContext(size: CGSize(width: 16, height: 16), scale: 2, clear: true)
            measure(format + "_repeated_export", count: 5000, operations: [{ old.generateImage()!.width }, { new.generateImage()!.width }])
            measure(format + "_four_workers_800_contexts", count: 8, operations: [
                {
                    DispatchQueue.concurrentPerform(iterations: 4) { worker in
                        var sum = 0
                        for _ in 0..<200 { autoreleasepool { let c = TGUIKitBaseline.DrawingContext(size: CGSize(width: 16, height: 16), scale: 2, clear: true); sum += c.generateImage()!.width } }
                        samples[worker] = sum
                    }
                    return samples[0] + samples[1] + samples[2] + samples[3]
                },
                {
                    DispatchQueue.concurrentPerform(iterations: 4) { worker in
                        var sum = 0
                        for _ in 0..<200 { autoreleasepool { let c = TGUIKit.DrawingContext(size: CGSize(width: 16, height: 16), scale: 2, clear: true); sum += c.generateImage()!.width } }
                        samples[worker] = sum
                    }
                    return samples[0] + samples[1] + samples[2] + samples[3]
                }
            ])
        }
        TGUIKit.DeviceGraphicsContextSettings.install(factory.format(CGColorSpace.sRGB))
        TGUIKitBaseline.DeviceGraphicsContextSettings.install(factory.format(CGColorSpace.sRGB))
        TGUIKit.setDisplayColorSpace(CGColorSpace(name: CGColorSpace.displayP3))
        TGUIKitBaseline.setDisplayColorSpace(CGColorSpace(name: CGColorSpace.displayP3))
        for size in [CGSize(width: 16, height: 16), CGSize(width: 120, height: 80), CGSize(width: 512, height: 288)] {
            measure("display_p3_\(Int(size.width))x\(Int(size.height))", count: size.width > 128 ? 100 : 1200, operations: [
                { let c = TGUIKitBaseline.DrawingContext(size: size, scale: 2, clear: true); c.withContext { factory.paint($0, size: size) }; return c.generateDisplayImage()!.width },
                { let c = TGUIKit.DrawingContext(size: size, scale: 2, clear: true); c.withContext { factory.paint($0, size: size) }; return c.generateDisplayImage()!.width }
            ])
        }
        XCTAssertGreaterThan(sink, 0)
        let old = TGUIKitBaseline.DrawingContext(size: CGSize(width: 16, height: 16), scale: 1, clear: true)
        let new = TGUIKit.DrawingContext(size: CGSize(width: 16, height: 16), scale: 1, clear: true)
        let sizes = [malloc_size(Unmanaged.passUnretained(old).toOpaque()), malloc_size(Unmanaged.passUnretained(new).toOpaque())]
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_before_after": results, "reverse": reverse, "sink": sink, "context_allocation_bytes": sizes], options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: "/tmp/drawing-context-benchmark.json"))
    }
}
