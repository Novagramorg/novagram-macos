import Cocoa
import XCTest
import QuartzCore
import TGUIKit

final class TintBenchmarkTests: XCTestCase {
    func testCosts() throws {
        guard ProcessInfo.processInfo.environment["TINT_BENCHMARK"] == "1" else { throw XCTSkip("Opt-in tint benchmark") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        let factory = TintTests()
        let reverse = ProcessInfo.processInfo.environment["TINT_REVERSE"] == "1"
        var results: [String: [[Double]]] = [:]
        var sink = 0
        func measure(_ name: String, count: Int = 1200, operations: [() -> Int]) {
            for op in operations { for _ in 0..<100 { sink += op() } }
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
        let source = factory.source()
        for cardinality in [1, 8, 128] {
            let colors = (0..<cardinality).map { NSColor(calibratedHue: CGFloat($0) / CGFloat(cardinality), saturation: 0.7, brightness: 0.8, alpha: 1) }
            var indices = [0, 0]
            measure("retained_source_colors_\(cardinality)", operations: [
                { let color = colors[indices[0] % cardinality]; indices[0] += 1; return source.referencePrecomposed(color).width },
                { let color = colors[indices[1] % cardinality]; indices[1] += 1; return source.precomposed(color).width }
            ])
        }
        let manySources = (0..<128).map { factory.source($0) }
        var indices = [0, 0]
        measure("unique_source_cycle_128", operations: [
            { let source = manySources[indices[0] % manySources.count]; indices[0] += 1; return source.referencePrecomposed(.red).width },
            { let source = manySources[indices[1] % manySources.count]; indices[1] += 1; return source.precomposed(.red).width }
        ])
        measure("untinted_fallback", operations: [{ source.referencePrecomposed().width }, { source.precomposed().width }])
        measure("gradient_fallback", operations: [{ source.referencePrecomposed(.red, bottomColor: .blue).width }, { source.precomposed(.red, bottomColor: .blue).width }])
        measure("zoom_fallback", operations: [{ source.referencePrecomposed(.red, zoom: 1.5).width }, { source.precomposed(.red, zoom: 1.5).width }])
        let large = factory.source(size: NSSize(width: 128, height: 128))
        measure("large_fallback", count: 500, operations: [{ large.referencePrecomposed(.red).width }, { large.precomposed(.red).width }])
        if let path = ProcessInfo.processInfo.environment["TINT_ASSET_BUNDLE"], let bundle = Bundle(path: path) {
            let names = ["Icon_CopyCode", "Icon_Peer_Music_Chevron", "Wallet_Collectible_AddToCard"]
            for name in names {
                guard bundle.image(forResource: NSImage.Name(name)) != nil else { continue }
                measure("bundle_\(name)", operations: [
                    { bundle.image(forResource: NSImage.Name(name))!.referencePrecomposed(.red).width },
                    { bundle.image(forResource: NSImage.Name(name))!.precomposed(.red).width }
                ])
            }
            let views = (0..<2).map { _ in (0..<2).map { _ in ImageView(frame: CGRect(x: 0, y: 0, width: 16, height: 16)) } }
            measure("two_icon_views_rebind", operations: (0..<2).map { mode in
                return {
                    for (index, view) in views[mode].enumerated() {
                        let image = bundle.image(forResource: NSImage.Name(index == 0 ? "Icon_Peer_Music_Waveform" : "Icon_Peer_Music_Chevron"))!
                        view.image = mode == 0 ? image.referencePrecomposed(.red) : image.precomposed(.red)
                        view.sizeToFit()
                    }
                    return views[mode].count
                }
            })
        }
        XCTAssertGreaterThan(sink, 0)
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_operation", "batches_before_after": results, "reverse": reverse, "sink": sink], options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: "/tmp/precomposed-tint-benchmark.json"))
    }
}
