import XCTest
import Cocoa
@testable import WaveformCurrent
@testable import WaveformOriginal

final class WaveformBenchmarkTests: XCTestCase {
    func testCompletePairRasterizationAndConstructionBenchmark() throws {
        guard ProcessInfo.processInfo.environment["WAVEFORM_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt-in timing")
        }
        _ = NSApplication.shared
        let reversed = ProcessInfo.processInfo.environment["WAVEFORM_REVERSE"] == "1"
        var rows: [[String: Any]] = []
        let context = CGContext(data: nil, width: 400, height: 40, bitsPerComponent: 8, bytesPerRow: 1600, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: 2, y: 2)
        for sourceCount in [100, 1000] {
            let values = (0 ..< sourceCount).map { UInt16(($0 * 7919) % 65536) }
            let data = values.withUnsafeBytes { Data($0) }
            for width: CGFloat in [40, 200] {
                let frame = CGRect(x: 0, y: 0, width: width, height: 20)
                let currentWaveform = WaveformCurrent.AudioWaveform(samples: data, peak: 31)
                let originalWaveform = WaveformOriginal.AudioWaveform(samples: data, peak: 31)
                let current = WaveformCurrent.AudioWaveformView(frame: frame)
                let original = WaveformOriginal.AudioWaveformView(frame: frame)
                current.waveform = currentWaveform
                original.waveform = originalWaveform
                current.layout()
                original.layout()
                let drawCurrent: () -> Void = {
                    current.testDraw(context, foreground: false)
                    current.testDraw(context, foreground: true)
                }
                let drawOriginal: () -> Void = {
                    original.testDraw(context, foreground: false)
                    original.testDraw(context, foreground: true)
                }
                for _ in 0 ..< 100 {
                    drawCurrent()
                    drawOriginal()
                }
                for scenario in ["reveal_pair_draw", "same_color_pair_draw", "construct_and_draw", "construct_only"] {
                    for batch in 0 ..< 9 {
                        let order = ((batch % 2 == 0) != reversed) ? [false, true] : [true, false]
                        for candidate in order {
                            let iterations = 300
                            let started = CACurrentMediaTime()
                            autoreleasepool {
                                for index in 0 ..< iterations {
                                    if scenario == "construct_only" || scenario == "construct_and_draw" {
                                        if candidate {
                                            let view = WaveformCurrent.AudioWaveformView(frame: frame)
                                            view.waveform = currentWaveform
                                            view.layout()
                                            if scenario == "construct_and_draw" {
                                                view.testDraw(context, foreground: false)
                                                view.testDraw(context, foreground: true)
                                            }
                                        } else {
                                            let view = WaveformOriginal.AudioWaveformView(frame: frame)
                                            view.waveform = originalWaveform
                                            view.layout()
                                            if scenario == "construct_and_draw" {
                                                view.testDraw(context, foreground: false)
                                                view.testDraw(context, foreground: true)
                                            }
                                        }
                                    } else if candidate {
                                        if scenario == "reveal_pair_draw" { current.testProgress(CGFloat(index % 60) / 59) }
                                        drawCurrent()
                                    } else {
                                        if scenario == "reveal_pair_draw" { original.testProgress(CGFloat(index % 60) / 59) }
                                        drawOriginal()
                                    }
                                }
                            }
                            let duration = (CACurrentMediaTime() - started) * 1_000_000 / Double(iterations)
                            rows.append(["scenario": scenario, "variant": candidate ? "current" : "original", "sourceCount": sourceCount, "width": width, "batch": batch, "microseconds": duration])
                        }
                    }
                }
            }
        }
        let path = ProcessInfo.processInfo.environment["WAVEFORM_BENCHMARK_OUTPUT"] ?? "/tmp/audio-waveform-benchmark.json"
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
    }
}
