import Cocoa
import Darwin
import QuartzCore
import XCTest
import TGUIKit
@testable import WaveformCurrent
@testable import WaveformOriginal

final class ClipLayerBenchmarkTests: XCTestCase {
    private func data() -> Data {
        (0..<100).map { UInt16(($0 * 13) % 32) }.withUnsafeBytes { Data($0) }
    }

    private func viewCount(_ view: NSView) -> Int {
        1 + view.subviews.reduce(0) { $0 + viewCount($1) }
    }

    private func layerCount(_ layer: CALayer) -> Int {
        1 + (layer.sublayers ?? []).reduce(0) { $0 + layerCount($1) }
    }

    func testConstructionProgressAndLayoutCosts() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WAVEFORM_CLIP_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in clipping layer timing") }
        _ = NSApplication.shared
        let reversed = environment["WAVEFORM_CLIP_REVERSE"] == "1"
        let samples = data()
        let originalWaveform = WaveformOriginal.AudioWaveform(samples: samples, peak: 31)
        let currentWaveform = WaveformCurrent.AudioWaveform(samples: samples, peak: 31)
        var batches: [String: [[Double]]] = [:]
        var iterations: [String: Int] = [:]
        var counts: [String: [Int]] = [:]
        var sink: CGFloat = 0

        func measure(_ name: String, count: Int, operations: [() -> Void]) {
            for index in reversed ? [1, 0] : [0, 1] {
                autoreleasepool { for _ in 0..<20 { operations[index]() } }
            }
            var samples = [[Double](), [Double]()]
            for batch in 0..<9 {
                for index in (batch % 2 == 0) != reversed ? [0, 1] : [1, 0] {
                    let elapsed = autoreleasepool { () -> Double in
                        let start = CACurrentMediaTime()
                        for _ in 0..<count { operations[index]() }
                        return (CACurrentMediaTime() - start) * 1_000_000 / Double(count)
                    }
                    samples[index].append(elapsed)
                }
            }
            batches[name] = samples
            iterations[name] = count
        }

        for width: CGFloat in [100, 200] {
            let suffix = "_\(Int(width))"
            let frame = CGRect(x: 0, y: 0, width: width, height: 20)
            let original = WaveformOriginal.AudioWaveformView(frame: frame)
            let current = WaveformCurrent.AudioWaveformView(frame: frame)
            original.waveform = originalWaveform
            current.waveform = currentWaveform
            original.layout()
            current.layout()
            counts["views" + suffix] = [viewCount(original), viewCount(current)]
            counts["connected_root_layers" + suffix] = [layerCount(original.layer!), layerCount(current.layer!)]
            counts["owned_layers" + suffix] = [waveformOwnedLayerCount(original), waveformOwnedLayerCount(current)]
            measure("construct" + suffix, count: 300, operations: [
                { let view = WaveformOriginal.AudioWaveformView(frame: frame); sink += view.frame.width },
                { let view = WaveformCurrent.AudioWaveformView(frame: frame); sink += view.frame.width }
            ])
            measure("construct_configure" + suffix, count: 300, operations: [
                {
                    let view = WaveformOriginal.AudioWaveformView(frame: frame)
                    view.waveform = originalWaveform
                    view.set(foregroundColor: .red, backgroundColor: .blue)
                    view.layout()
                    view.testSetClip(CGSize(width: width / 2, height: 20), animated: false)
                    sink += view.testClipLayer.bounds.width
                },
                {
                    let view = WaveformCurrent.AudioWaveformView(frame: frame)
                    view.waveform = currentWaveform
                    view.set(foregroundColor: .red, backgroundColor: .blue)
                    view.layout()
                    view.testSetClip(CGSize(width: width / 2, height: 20), animated: false)
                    sink += view.testClipLayer.bounds.width
                }
            ])
            original.testSetClip(CGSize(width: width / 2, height: 20), animated: false)
            current.testSetClip(CGSize(width: width / 2, height: 20), animated: false)
            measure("same_immediate_clip" + suffix, count: 2000, operations: [
                { original.testSetClip(CGSize(width: width / 2, height: 20), animated: false); sink += original.testClipLayer.bounds.width },
                { current.testSetClip(CGSize(width: width / 2, height: 20), animated: false); sink += current.testClipLayer.bounds.width }
            ])
            for animated in [false, true] {
                var originalIndex = 0, currentIndex = 0
                measure((animated ? "animated_retarget" : "changing_immediate_clip") + suffix, count: 1000, operations: [
                    {
                        originalIndex += 1
                        original.testSetClip(CGSize(width: width * CGFloat(originalIndex % 61) / 60, height: 20), animated: animated)
                        sink += original.testClipLayer.bounds.width
                    },
                    {
                        currentIndex += 1
                        current.testSetClip(CGSize(width: width * CGFloat(currentIndex % 61) / 60, height: 20), animated: animated)
                        sink += current.testClipLayer.bounds.width
                    }
                ])
                original.testClipLayer.removeAllAnimations()
                current.testClipLayer.removeAllAnimations()
            }
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 260, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = View(frame: CGRect(x: 0, y: 0, width: 260, height: 80))
            window.contentView = host
            host.addSubview(original)
            host.addSubview(current)
            var originalIndex = 0, currentIndex = 0
            measure("attached_resize_layout" + suffix, count: 500, operations: [
                {
                    originalIndex += 1
                    original.setFrameSize(CGSize(width: width + CGFloat(originalIndex % 2), height: 20))
                    original.layoutSubtreeIfNeeded()
                    sink += original.frame.width
                },
                {
                    currentIndex += 1
                    current.setFrameSize(CGSize(width: width + CGFloat(currentIndex % 2), height: 20))
                    current.layoutSubtreeIfNeeded()
                    sink += current.frame.width
                }
            ])
            window.close()
        }
        XCTAssertGreaterThan(sink, 0)
        let payload: [String: Any] = [
            "batches": batches, "iterations_per_batch": iterations, "counts": counts,
            "variant_order": ["immediate_pre_clip_layer", "current"], "reversed": reversed,
            "batch_count": 9, "warmup_iterations": 20, "units": "microseconds_per_operation",
            "source_samples": 100, "rasterized": false,
            "scope": "Construction, model progress updates, explicit animation setup and attached layout; excludes waveform measurement, rasterization, presentation, media and full-app scrolling"
        ]
        let output = environment["WAVEFORM_CLIP_OUTPUT"] ?? "/tmp/waveform-clip-benchmark.json"
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
    }

    func testRetainedWaveformAllocationFootprint() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let variant = environment["WAVEFORM_CLIP_MEMORY"], ["original", "current"].contains(variant) else {
            throw XCTSkip("Opt-in fresh-process waveform allocation footprint")
        }
        _ = NSApplication.shared
        let count = 2000
        let samples = data()
        let originalWaveform = WaveformOriginal.AudioWaveform(samples: samples, peak: 31)
        let currentWaveform = WaveformCurrent.AudioWaveform(samples: samples, peak: 31)
        let frame = CGRect(x: 0, y: 0, width: 170, height: 20)
        autoreleasepool {
            for _ in 0..<30 {
                let original = WaveformOriginal.AudioWaveformView(frame: frame)
                let current = WaveformCurrent.AudioWaveformView(frame: frame)
                original.waveform = originalWaveform
                current.waveform = currentWaveform
                original.layout()
                current.layout()
            }
            CATransaction.flush()
        }
        func memory() -> [String: UInt64] {
            var info = task_vm_info_data_t()
            var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size)
                }
            }
            XCTAssertEqual(status, KERN_SUCCESS)
            return ["footprint": info.phys_footprint, "resident": info.resident_size]
        }
        var views: [NSView] = []
        views.reserveCapacity(count)
        let before = memory()
        autoreleasepool {
            for _ in 0..<count {
                if variant == "original" {
                    let view = WaveformOriginal.AudioWaveformView(frame: frame)
                    view.waveform = originalWaveform
                    view.layout()
                    views.append(view)
                } else {
                    let view = WaveformCurrent.AudioWaveformView(frame: frame)
                    view.waveform = currentWaveform
                    view.layout()
                    views.append(view)
                }
            }
            CATransaction.flush()
        }
        let after = withExtendedLifetime(views) { memory() }
        let retainedViews = views.reduce(0) { $0 + viewCount($1) }
        let connectedRootLayers = views.reduce(0) { $0 + layerCount($1.layer!) }
        let ownedLayers = views.reduce(0) { $0 + waveformOwnedLayerCount($1) }
        let payload: [String: Any] = [
            "variant": variant, "count": count, "before": before, "after": after,
            "views": retainedViews, "connected_root_layers": connectedRootLayers, "owned_layers": ownedLayers,
            "waveform_shared_across_rows": true,
            "attached": false, "rasterized": false, "includes_allocator_and_framework_storage": true
        ]
        let output = environment["WAVEFORM_CLIP_OUTPUT"] ?? "/tmp/waveform-clip-memory-\(variant).json"
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
    }
}
