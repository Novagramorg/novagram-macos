import XCTest
import Cocoa
@testable import WaveformCurrent
@testable import WaveformOriginal

final class WaveformTests: XCTestCase {
    private func data(_ samples: [UInt16]) -> Data {
        samples.withUnsafeBytes { Data($0) }
    }

    private func bitmap(width: CGFloat, height: CGFloat = 20, scale: CGFloat, draw: (CGContext) -> Void) -> Data {
        let pixelWidth = max(1, Int(ceil(max(0, width) * scale)))
        let pixelHeight = max(1, Int(ceil(height * scale)))
        let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        draw(context)
        return Data(bytes: context.data!, count: pixelWidth * pixelHeight * 4)
    }

    private func pair(width: CGFloat, samples: Data?) -> (WaveformCurrent.AudioWaveformView, WaveformOriginal.AudioWaveformView) {
        _ = NSApplication.shared
        let frame = CGRect(x: 0, y: 0, width: width, height: 20)
        let current = WaveformCurrent.AudioWaveformView(frame: frame)
        let original = WaveformOriginal.AudioWaveformView(frame: frame)
        current.waveform = samples.map { WaveformCurrent.AudioWaveform(samples: $0, peak: 31) }
        original.waveform = samples.map { WaveformOriginal.AudioWaveform(samples: $0, peak: 31) }
        current.layout()
        original.layout()
        return (current, original)
    }

    func testPixelParityAcrossWaveformsWidthsScalesAndReveal() {
        var seed: UInt64 = 57
        let random: [UInt16] = (0 ..< 101).map { _ in
            seed = seed &* 6364136223846793005 &+ 1
            return UInt16(truncatingIfNeeded: seed >> 32)
        }
        let fixtures: [Data?] = [nil, Data(), data([0]), data([31]), data([65535]), data([0, 31, 4, 18, 0]), data(Array(repeating: 0, count: 100)), data(random), data(random) + Data([23])]
        for samples in fixtures {
            for width: CGFloat in [4, 7.99, 8, 36, 99.5, 200] {
                let (current, original) = pair(width: width, samples: samples)
                for color in [NSColor.red, NSColor(calibratedRed: 0.2, green: 0.7, blue: 0.5, alpha: 0.3)] {
                    current.set(foregroundColor: color, backgroundColor: .gray)
                    original.set(foregroundColor: color, backgroundColor: .gray)
                    for progress: CGFloat in [0, 0.08, 0.5, 0.99, 1] {
                        current.testProgress(progress)
                        original.testProgress(progress)
                        for scale: CGFloat in [1, 2, 3] {
                            for foreground in [false, true] {
                                let expected = bitmap(width: width, scale: scale) { original.testDraw($0, foreground: foreground) }
                                let actual = bitmap(width: width, scale: scale) { current.testDraw($0, foreground: foreground) }
                                XCTAssertEqual(actual, expected, "width=\(width), scale=\(scale), progress=\(progress), foreground=\(foreground)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testNarrowNonemptyWaveformsDrawNothingWithoutInvalidMemoryAccess() {
        for width: CGFloat in [0, 0.1, 1, 3, 3.999] {
            let (current, _) = pair(width: width, samples: data([31, 9]))
            let pixels = bitmap(width: width, scale: 3) { current.testDraw($0, foreground: false) }
            XCTAssertTrue(pixels.allSatisfy { $0 == 0 })
            XCTAssertNil(current.testSnapshot)
        }
    }

    func testPreparedBucketsMatchIndependentOriginalMapping() {
        for sourceCount in [0, 1, 2, 7, 100, 401] {
            let values = (0 ..< sourceCount).map { UInt16(($0 * 7919) % 65536) }
            for count in [1, 2, 3, 11, 100] {
                let (current, _) = pair(width: CGFloat(count * 4), samples: data(values))
                _ = bitmap(width: CGFloat(count * 4), scale: 1) { current.testDraw($0, foreground: false) }
                var expected = [UInt16](repeating: 0, count: count)
                for (index, value) in values.enumerated() {
                    let bucket = index * count / values.count
                    expected[bucket] = max(expected[bucket], value)
                }
                XCTAssertEqual(current.testSnapshot?.0, expected)
                XCTAssertEqual(current.testSnapshot?.1, 1 / max(1, CGFloat(values.max() ?? 0)))
            }
        }
    }

    func testBothLayersReusePreparationThroughColorProgressHeightAndScaleChanges() {
        let (current, _) = pair(width: 100, samples: data([4, 31, 5, 22]))
        XCTAssertTrue(current.testSharedPreparation)
        _ = bitmap(width: 100, scale: 1) { current.testDraw($0, foreground: false) }
        let retained = current.testSnapshot!.0
        let address = retained.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }
        for index in 0 ..< 20 {
            current.testProgress(CGFloat(index) / 19)
            current.set(foregroundColor: .blue, backgroundColor: .red)
            current.setFrameSize(CGSize(width: 100, height: CGFloat(20 + index)))
            current.layout()
            _ = bitmap(width: 100, height: CGFloat(20 + index), scale: CGFloat(index % 3 + 1)) { current.testDraw($0, foreground: index % 2 == 0) }
            XCTAssertEqual(current.testSnapshot!.0.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress!) }, address)
        }
    }

    func testReplacementNilAndResizeInvalidateCorrectly() {
        let (current, original) = pair(width: 100, samples: data([31, 0, 18]))
        _ = bitmap(width: 100, scale: 1) { current.testDraw($0, foreground: true) }
        weak var previous = current.waveform
        for input: Data? in [data([0, 31, 0, 9]), nil, data([31]), data([31])] {
            current.waveform = input.map { WaveformCurrent.AudioWaveform(samples: $0, peak: 31) }
            original.waveform = input.map { WaveformOriginal.AudioWaveform(samples: $0, peak: 31) }
            XCTAssertNil(current.testSnapshot)
            for width: CGFloat in [100, 101, 44, 100] {
                current.setFrameSize(CGSize(width: width, height: 20))
                original.setFrameSize(CGSize(width: width, height: 20))
                current.layout()
                original.layout()
                XCTAssertEqual(bitmap(width: width, scale: 2) { current.testDraw($0, foreground: false) }, bitmap(width: width, scale: 2) { original.testDraw($0, foreground: false) })
            }
        }
        XCTAssertNil(previous)
    }

    func testCopiedInputDataRemainsIndependent() {
        for count in [4, 100] {
            let values = (0 ..< count).map { UInt16(($0 * 7919) % 65536) }
            var input = data(values)
            let expected = data(values)
            let (current, original) = pair(width: 100, samples: input)
            _ = bitmap(width: 100, scale: 1) { current.testDraw($0, foreground: false) }
            input[0] = 255
            input[input.count - 1] ^= 255
            XCTAssertNotEqual(input, expected)
            XCTAssertEqual(current.waveform?.samples, expected)
            XCTAssertEqual(original.waveform?.samples, expected)
            XCTAssertEqual(bitmap(width: 100, scale: 2) { current.testDraw($0, foreground: true) }, bitmap(width: 100, scale: 2) { original.testDraw($0, foreground: true) })
        }
    }

    func testAnimationStartsOnceAndUpdatesBothLayers() {
        let (current, _) = pair(width: 100, samples: data([31, 5]))
        current.animateIn()
        current.testProgress(0.5)
        let pixels = bitmap(width: 100, scale: 1) { current.testDraw($0, foreground: false) }
        current.animateIn()
        XCTAssertEqual(pixels, bitmap(width: 100, scale: 1) { current.testDraw($0, foreground: false) })
        current.testProgress(1)
        current.set(foregroundColor: .red, backgroundColor: .red)
        XCTAssertEqual(bitmap(width: 100, scale: 1) { current.testDraw($0, foreground: false) }, bitmap(width: 100, scale: 1) { current.testDraw($0, foreground: true) })
    }

    func testAttachedWindowResizeAndClippingMatchFreshRendering() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSView(frame: CGRect(x: 0, y: 0, width: 240, height: 80))
        host.wantsLayer = true
        window.contentView = host
        defer { window.close() }
        let samples = data((0 ..< 100).map { UInt16(($0 * 13) % 32) })
        let (current, _) = pair(width: 100, samples: samples)
        current.backgroundColor = .clear
        current.set(foregroundColor: .red, backgroundColor: .blue)
        host.addSubview(current)
        XCTAssertTrue(current.window === window)

        func render(_ view: NSView) throws -> Data {
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let layer = try XCTUnwrap(view.layer)
            func display(_ value: CALayer) {
                value.displayIfNeeded()
                value.sublayers?.forEach(display)
            }
            display(layer)
            return bitmap(width: view.bounds.width, height: view.bounds.height, scale: 2) { layer.render(in: $0) }
        }

        let initial = try render(current)
        XCTAssertTrue(initial.contains { $0 != 0 })
        for width: CGFloat in [44, 3, 100, 101, 8] {
            current.setFrameSize(CGSize(width: width, height: 20))
            current.layout()
            var clippingPixels: [Data] = []
            for fraction: CGFloat in [0, 0.5, 1] {
                current.updateForegroundClip(size: CGSize(width: width * fraction, height: 20), animated: false)
                let actual = try render(current)
                if width < 4 {
                    XCTAssertTrue(actual.allSatisfy { $0 == 0 }, "Old waveform contents survived narrow resize")
                } else {
                    let (_, fresh) = pair(width: width, samples: samples)
                    fresh.backgroundColor = .clear
                    fresh.foregroundClipingView.backgroundColor = .clear
                    fresh.set(foregroundColor: .red, backgroundColor: .blue)
                    fresh.foregroundClipingView.setFrameSize(CGSize(width: width * fraction, height: 20))
                    host.addSubview(fresh)
                    defer { fresh.removeFromSuperview() }
                    XCTAssertEqual(actual, try render(fresh), "width=\(width), clip=\(fraction)")
                    clippingPixels.append(actual)
                }
            }
            if width >= 4 {
                XCTAssertNotEqual(clippingPixels[0], clippingPixels[1])
                XCTAssertNotEqual(clippingPixels[1], clippingPixels[2])
            }
        }
        current.removeFromSuperview()
        XCTAssertNil(current.window)
        host.addSubview(current)
        XCTAssertTrue(current.window === window)
        let before = try render(current)
        current.testProgress(0.4)
        XCTAssertNotEqual(before, try render(current))
    }

    func testOriginalNarrowWidthReproducer() throws {
        guard ProcessInfo.processInfo.environment["WAVEFORM_REPRODUCE_ORIGINAL_CRASH"] == "1" else {
            throw XCTSkip("Explicit Address Sanitizer reproducer only")
        }
        let (_, original) = pair(width: 1, samples: data([31, 9]))
        _ = bitmap(width: 1, scale: 1) { original.testDraw($0, foreground: false) }
    }
}
